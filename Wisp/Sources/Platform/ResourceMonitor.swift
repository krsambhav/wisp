import AppKit
import Darwin
import Foundation

/// Live CPU and memory for Wisp as a whole: this process plus the WebKit
/// helpers (WebContent, Networking, GPU) macOS runs on its behalf. Those are
/// not our children (launchd owns them), but they share our resource
/// coalition, which is also how Activity Monitor groups them.
///
/// Sampling runs every two seconds while a window is on screen and stops when
/// nothing is showing it (the header meter drives it from `.task`). Rows come
/// from the unsandboxed update helper so memory matches Activity Monitor's
/// footprint; if the helper is unreachable the app walks the process table
/// itself and reports resident size instead.
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

    static let interval: Duration = .seconds(2)
    /// Two minutes at `interval`.
    static let historyLength = 60

    /// Above either of these the header pill turns amber and the popover
    /// suggests freeing memory. CPU is averaged over the last 30 s so a page
    /// load doesn't trip it.
    static let highMemory: UInt64 = 2 << 30
    static let highCPU: Double = 90

    private(set) var sample: Sample?
    /// True while `AppEnvironment.freeUpMemory()` is reloading pages.
    var isFreeing = false

    var isHigh: Bool {
        guard let sample else { return false }
        if sample.memory >= Self.highMemory { return true }
        let recent = history.suffix(15)
        return recent.count >= 15 && recent.reduce(0, +) / Double(recent.count) >= Self.highCPU
    }
    /// CPU percent per tick, oldest first.
    private(set) var history: [Double] = []
    private(set) var peakCPU: Double = 0

    var showsInHeader: Bool {
        didSet { UserDefaults.standard.set(showsInHeader, forKey: Self.showKey) }
    }
    private static let showKey = "wisp.resources.showInHeader"

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var helper: NSXPCConnection?
    @ObservationIgnored private var helperFailed = false

    init() {
        showsInHeader = UserDefaults.standard.object(forKey: Self.showKey) as? Bool ?? true
    }

    /// Samples until the calling task is cancelled. Safe to call from several
    /// views; only the first caller runs the loop.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer {
            isRunning = false
            helper?.invalidate()
            helper = nil
        }
        var sampler = ResourceSampler()
        let coalition = ProcessTable.coalitionID(of: getpid())
        var logged = false
        while !Task.isCancelled {
            if Self.somethingIsOnScreen {
                let rows = await fetchRows(coalition: coalition)
                if !logged {
                    logged = true
                    Log.info("Resource meter: \(rows.count) processes in coalition \(coalition), exact=\(rows.allSatisfy(\.exact)) via \(helperFailed ? "sandbox" : "helper")", .performance)
                }
                publish(sampler.sample(rows))
            }
            try? await Task.sleep(for: Self.interval)
        }
    }

    private func fetchRows(coalition: UInt64) async -> [ProcessUsage] {
        if !helperFailed, let rows = await helperRows(coalition: coalition) { return rows }
        return await Task.detached(priority: .utility) { ProcessTable.members(ofCoalition: coalition) }.value
    }

    private func helperRows(coalition: UInt64) async -> [ProcessUsage]? {
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
            helper.invalidate()
            self.helper = nil
            return nil
        }
        return rows
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
