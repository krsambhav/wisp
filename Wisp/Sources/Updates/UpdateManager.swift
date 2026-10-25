import AppKit
import Foundation

/// In-app updates from GitHub Releases. Checks `releases/latest` on the
/// repository, compares the tag with the running version, downloads the
/// `Wisp-<version>.zip` asset, verifies its code signature against the running
/// app's Team ID, swaps the bundle on disk and relaunches. No third-party
/// framework and no server of our own: the release page is the feed.
@MainActor
@Observable
final class UpdateManager {
    static let repository = "krsambhav/wisp"
    static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }

    nonisolated struct Release: Equatable, Sendable {
        let version: String
        let tag: String
        let notes: String
        let pageURL: URL
        let assetURL: URL
        let assetSize: Int64
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(Release)
        case downloading(Release)
        case installing(Release)
        case installed(Release)
        case failed(String)

        var release: Release? {
            switch self {
            case .available(let r), .downloading(let r), .installing(let r), .installed(let r): r
            default: nil
            }
        }
        var isBusy: Bool {
            switch self { case .checking, .downloading, .installing: true; default: false }
        }
    }

    private(set) var state: State = .idle
    /// Release found by the last check, kept so the header pill survives a
    /// later failed manual check.
    private(set) var lastCheck: Date? = UserDefaults.standard.object(forKey: Keys.lastCheck) as? Date

    var automaticChecks: Bool {
        get { UserDefaults.standard.object(forKey: Keys.automatic) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.automatic); _automaticChecksVersion += 1 }
    }
    private var _automaticChecksVersion = 0   // observation hook for the toggle

    /// Called when an update is found by an automatic check (not user initiated).
    var onUpdateFound: (@MainActor (Release) -> Void)?

    private enum Keys {
        static let lastCheck = "wisp.updates.lastCheck"
        static let automatic = "wisp.updates.automatic"
    }
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private var relaunchHelper: Process?
    private var periodicTask: Task<Void, Never>?

    /// Running version. `WISP_DEBUG_VERSION` lets a Debug build pretend to be
    /// older so the whole update path can be exercised against a real release.
    nonisolated static let currentVersion: String = {
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment["WISP_DEBUG_VERSION"], !v.isEmpty { return v }
        #endif
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }()
    var currentVersion: String { Self.currentVersion }

    // MARK: Scheduling

    /// Launch hook: one check shortly after start (so it never competes with
    /// the first page load), then every six hours while running.
    func startAutomaticChecks() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            while !Task.isCancelled {
                if let self, self.automaticChecks, self.isDue { await self.check(userInitiated: false) }
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
        UpdateInstaller.cleanUpLeftovers(next: Bundle.main.bundleURL)
    }

    private var isDue: Bool {
        guard state.release == nil, !state.isBusy else { return false }
        guard let last = lastCheck else { return true }
        return Date().timeIntervalSince(last) >= Self.checkInterval
    }

    // MARK: Check

    func check(userInitiated: Bool) async {
        if state.isBusy { return }
        if case .installed = state { return }
        state = .checking
        do {
            let latest = try await UpdateFeed.latestRelease(repository: Self.repository)
            lastCheck = Date()
            UserDefaults.standard.set(lastCheck, forKey: Keys.lastCheck)
            if let latest, SemVer(latest.version) > SemVer(currentVersion) {
                Log.info("Update available: \(latest.version) (running \(currentVersion))", .updates)
                state = .available(latest)
                if !userInitiated { onUpdateFound?(latest) }
            } else {
                Log.info("Up to date (\(currentVersion); latest \(latest?.version ?? "none"))", .updates)
                state = .upToDate(Date())
            }
        } catch {
            Log.warning("Update check failed: \(error.localizedDescription)", .updates)
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Install

    func downloadAndInstall() async {
        guard let release = state.release, !state.isBusy else { return }
        if case .installed = state { relaunch(); return }
        state = .downloading(release)
        do {
            let staged = try await UpdateInstaller.downloadAndStage(release)
            state = .installing(release)
            try UpdateInstaller.verify(appAt: staged, expectedVersion: release.version)
            try await installWithAccess(staged: staged, target: Bundle.main.bundleURL)
            state = .installed(release)
            Log.info("Installed \(release.version) at \(Bundle.main.bundleURL.path)", .updates)
            relaunch()
        } catch {
            Log.error("Update failed: \(error.localizedDescription)", .updates)
            state = .failed(error.localizedDescription)
        }
    }

    /// Swap the bundle; if the sandbox denies the write, ask once for the
    /// folder (security-scoped bookmark, remembered) and retry.
    private func installWithAccess(staged: URL, target: URL) async throws {
        if target.path.contains("/AppTranslocation/") {
            throw UpdateError.translocated
        }
        do {
            try UpdateInstaller.swap(staged: staged, into: target)
        } catch {
            let folder = target.deletingLastPathComponent()
            guard let access = UpdateInstaller.requestAccess(to: folder) else { throw error }
            defer { access.stopAccessingSecurityScopedResource() }
            try UpdateInstaller.swap(staged: staged, into: target)
        }
    }

    /// Quit through the normal path (sessions unload, IndexedDB flushes) and
    /// have a tiny shell helper reopen the new bundle once this process exits.
    func relaunch() {
        relaunchHelper?.terminate()
        relaunchHelper = UpdateInstaller.spawnRelauncher(for: Bundle.main.bundleURL)
        NSApp.terminate(nil)
        // Reached only if termination was cancelled (sync guard / confirm dialog).
        relaunchHelper?.terminate()
        relaunchHelper = nil
    }

    func openReleaseNotes() {
        NSWorkspace.shared.open(state.release?.pageURL ?? Self.releasesPage)
    }
}

nonisolated enum UpdateError: LocalizedError {
    case noAsset, badArchive, signature(String), versionMismatch(String), translocated, noAccess

    var errorDescription: String? {
        switch self {
        case .noAsset: "The release has no Wisp .zip attached."
        case .badArchive: "The downloaded archive did not contain Wisp.app."
        case .signature(let why): "The update's signature could not be verified (\(why))."
        case .versionMismatch(let v): "The downloaded app reports version \(v), not the release version."
        case .translocated: "Move Wisp to your Applications folder first, then update."
        case .noAccess: "Wisp was not given permission to replace itself."
        }
    }
}

/// Dotted numeric version with an optional leading "v" (1.2.3, v1.10).
nonisolated struct SemVer: Comparable, Sendable {
    let parts: [Int]
    init(_ s: String) {
        var t = Substring(s)
        if t.hasPrefix("v") || t.hasPrefix("V") { t = t.dropFirst() }
        parts = t.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
    static func < (a: SemVer, b: SemVer) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}
