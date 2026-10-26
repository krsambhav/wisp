import AppKit
import Darwin
import Foundation

/// Live CPU and memory for Wisp as a whole: this process plus the WebKit
/// helpers (WebContent, Networking, GPU) macOS runs on its behalf. Those are
/// not our children (launchd owns them), but they share our resource
/// coalition, which is also how Activity Monitor groups them.
///
/// The sampler runs for the life of the app at a cadence that follows how
/// closely anyone is looking: every two seconds while the header meter or its
/// popover is on screen, every ten seconds while a window is merely visible,
/// and every thirty seconds in the background, where its only job is to feed
/// the idle free-up in `AppEnvironment`. Rows come from the unsandboxed update
/// helper so memory matches Activity Monitor's footprint; if the helper is
/// unreachable the app walks the process table itself and reports resident
/// size instead.
@MainActor
@Observable
final class ResourceMonitor {
    nonisolated struct ProcessGroup: Identifiable, Sendable, Equatable {
        let name: String
        let count: Int
        /// Percent of one core, summed over the group (can exceed 100).
        let cpu: Double
        /// Bytes.
        let memory: UInt64
        var id: String { name }
    }

    nonisolated struct Sample: Sendable, Equatable {
        let date: Date
        let cpu: Double
        let memory: UInt64
        let groups: [ProcessGroup]
        /// False when memory is resident size (sandboxed fallback) rather than footprint.
        let exact: Bool
        var processCount: Int { groups.reduce(0) { $0 + $1.count } }
    }

    nonisolated struct IdleFree: Sendable, Equatable {
        let date: Date
        let freed: UInt64
    }

    /// Cadence while a view is watching, while a window is visible, and in the background.
    static let closeInterval: Duration = .seconds(2)
    static let quietInterval: Duration = .seconds(10)
    static let hiddenInterval: Duration = .seconds(30)
    /// Two minutes at `closeInterval`.
    static let historyLength = 60

    /// Above either of these the header pill turns amber and the popover
    /// suggests freeing memory. CPU is averaged over the last 15 samples so a
    /// page load doesn't trip it.
    static let highMemory: UInt64 = 2 << 30
    static let highCPU: Double = 90

    /// Idle free-up: after this long in the background, above this footprint,
    /// at most once per cooldown. The floor sits above what WhatsApp needs
    /// right after a fresh load (about 1.1 GB with two accounts), so a restart
    /// only happens when there is something to give back.
    static let idleFreeAfter: TimeInterval = debugOverride("WISP_DEBUG_IDLE_FREE_AFTER") ?? 15 * 60
    static let idleFreeMemory: UInt64 = debugOverride("WISP_DEBUG_IDLE_FREE_MB").map { UInt64($0) << 20 } ?? 1536 << 20
    static let idleFreeCooldown: TimeInterval = 60 * 60

    /// Debug builds can shorten the idle limits to exercise the free-up.
    private static func debugOverride(_ key: String) -> Double? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[key].flatMap(Double.init)
        #else
        return nil
        #endif
    }

    private(set) var sample: Sample?
    /// True while `AppEnvironment.freeUpMemory()` is reloading pages.
    var isFreeing = false
    /// The most recent automatic free-up this run, shown in the popover.
    var lastIdleFree: IdleFree?

    var isHigh: Bool {
        guard let sample else { return false }
        if sample.memory >= Self.highMemory { return true }
        let recent = history.suffix(15)
        return recent.count >= 15 && recent.reduce(0, +) / Double(recent.count) >= Self.highCPU
    }
    /// CPU percent per sample, oldest first.
    private(set) var history: [Double] = []
    private(set) var peakCPU: Double = 0

    var showsInHeader: Bool {
        didSet { UserDefaults.standard.set(showsInHeader, forKey: Self.showKey) }
    }
    /// Restart WhatsApp in a fresh process when the Mac is low on memory and
    /// Wisp has been in the background long enough with a high footprint (see
    /// the `idleFree*` limits). Off by default: a restart means a loading
    /// screen (and a re-sync) when the user comes back, and WhatsApp climbs
    /// back to most of its footprint within seconds of a fresh load.
    var freesWhenIdle: Bool {
        didSet { UserDefaults.standard.set(freesWhenIdle, forKey: Self.idleKey) }
    }
    /// True from a `warning` or `critical` memory-pressure event until the
    /// kernel reports `normal` again. The idle free-up only acts while this is set.
    private(set) var isUnderMemoryPressure = false
    private static let showKey = "wisp.resources.showInHeader"
    private static let idleKey = "wisp.resources.freeWhenIdle"

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var sampler = ResourceSampler()
    @ObservationIgnored private let coalition = ProcessTable.coalitionID(of: getpid())
    @ObservationIgnored private var helper: NSXPCConnection?
    @ObservationIgnored private var helperFailed = false
    @ObservationIgnored private var logged = false
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?

    init() {
        showsInHeader = UserDefaults.standard.object(forKey: Self.showKey) as? Bool ?? true
        freesWhenIdle = UserDefaults.standard.object(forKey: Self.idleKey) as? Bool ?? false
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let event = source.data
                let pressured = event.contains(.warning) || event.contains(.critical)
                if pressured != self.isUnderMemoryPressure {
                    Log.info("System memory pressure \(pressured ? "on" : "normal")", .performance)
                }
                self.isUnderMemoryPressure = pressured
            }
        }
        source.activate()
        pressureSource = source
    }

    /// Samples until the calling task is cancelled. Only the first caller runs the loop.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer {
            isRunning = false
            dropHelper()
        }
        while !Task.isCancelled {
            let onScreen = Self.somethingIsOnScreen
            await refresh()
            let interval = watchers > 0 && onScreen ? Self.closeInterval : onScreen ? Self.quietInterval : Self.hiddenInterval
            // In the background let the XPC helper exit between samples.
            if interval == Self.hiddenInterval { dropHelper() }
            try? await Task.sleep(for: interval)
        }
    }

    /// Keeps the sampler at its close cadence while the calling view is alive.
    /// Suspends until the task is cancelled.
    func watch() async {
        watchers += 1
        defer { watchers -= 1 }
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
    }

    /// Takes one sample now (the free-up uses it to measure what it gave back).
    func refresh() async {
        let rows = await fetchRows()
        if !logged {
            logged = true
            Log.info("Resource meter: \(rows.count) processes in coalition \(coalition), exact=\(rows.allSatisfy(\.exact)) via \(helperFailed ? "sandbox" : "helper")", .performance)
        }
        publish(sampler.sample(rows))
    }

    private func fetchRows() async -> [ProcessUsage] {
        if !helperFailed, let rows = await helperRows() { return rows }
        let coalition = self.coalition
        return await Task.detached(priority: .utility) { ProcessTable.members(ofCoalition: coalition) }.value
    }

    private func helperRows() async -> [ProcessUsage]? {
        if helper == nil {
            let c = NSXPCConnection(serviceName: WispUpdateHelper.serviceName)
            c.remoteObjectInterface = NSXPCInterface(with: WispUpdateHelperProtocol.self)
            c.resume()
            helper = c
        }
        guard let helper else { return nil }
        let once = OnceBox()
        let data: Data? = await withCheckedContinuation { cont in
            let proxy = helper.remoteObjectProxyWithErrorHandler { _ in
                once.run { cont.resume(returning: nil) }
            } as! WispUpdateHelperProtocol
            proxy.processUsage(coalition: coalition) { data in
                once.run { cont.resume(returning: data) }
            }
        }
        guard let data, let rows = try? JSONDecoder().decode([ProcessUsage].self, from: data), !rows.isEmpty else {
            Log.warning("Resource helper unavailable, falling back to in-process sampling", .performance)
            helperFailed = true
            dropHelper()
            return nil
        }
        return rows
    }

    private func dropHelper() {
        helper?.invalidate()
        helper = nil
    }

    private func publish(_ s: Sample) {
        sample = s
        history.append(s.cpu)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        peakCPU = history.max() ?? 0
    }

    private static var somethingIsOnScreen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
    }

    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}

// MARK: - Sampler

/// Turns two consecutive process-table readings into percentages: CPU is the
/// per-pid delta in ticks over wall time, so a helper that exits simply drops
/// out and a new one starts at zero.
nonisolated struct ResourceSampler: Sendable {
    private var previousTicks: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0

    mutating func sample(_ rows: [ProcessUsage]) -> ResourceMonitor.Sample {
        let now = mach_absolute_time()
        let wallNanos = previousTime == 0 ? 0 : Double(now - previousTime) * ProcessTable.nanosPerTick
        var ticks: [pid_t: UInt64] = [:]
        var groups: [String: (count: Int, cpu: Double, memory: UInt64)] = [:]

        for row in rows {
            ticks[row.pid] = row.cpuTicks
            var cpu = 0.0
            if wallNanos > 0, let before = previousTicks[row.pid], row.cpuTicks >= before {
                cpu = Double(row.cpuTicks - before) * ProcessTable.nanosPerTick / wallNanos * 100
            }
            let label = Self.label(for: row.name)
            var g = groups[label, default: (0, 0, 0)]
            g.count += 1
            g.cpu += cpu
            g.memory += row.memory
            groups[label] = g
        }
        previousTicks = ticks
        previousTime = now

        let list = groups
            .map { ResourceMonitor.ProcessGroup(name: $0.key, count: $0.value.count, cpu: $0.value.cpu, memory: $0.value.memory) }
            .sorted { $0.memory > $1.memory }
        return .init(date: Date(),
                     cpu: list.reduce(0) { $0 + $1.cpu },
                     memory: list.reduce(0) { $0 + $1.memory },
                     groups: list,
                     exact: rows.allSatisfy(\.exact))
    }

    private static func label(for name: String) -> String {
        switch name {
        case "com.apple.WebKit.WebContent": "Web content"
        case "com.apple.WebKit.Networking": "Networking"
        case "com.apple.WebKit.GPU": "Graphics"
        case "WispUpdateHelper": "Helper"
        default: name
        }
    }
}
