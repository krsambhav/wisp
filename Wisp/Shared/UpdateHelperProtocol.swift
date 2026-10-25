import Foundation

/// XPC contract between the sandboxed app and the (unsandboxed) update helper
/// service in Contents/XPCServices. Compiled into both targets.
@objc nonisolated protocol WispUpdateHelperProtocol {
    /// Strips the quarantine flag from `staged` (a verified Wisp.app the app
    /// downloaded into its container), swaps it into `target`, and when
    /// `parentPID` > 0 spawns a detached waiter that reopens `target` once
    /// that process has exited. `reply` carries an error description or nil.
    func install(staged: String, target: String, relaunchAfterPID parentPID: Int32, reply: @escaping @Sendable (String?) -> Void)

    /// JSON-encoded `[ProcessUsage]` for every process in `coalition`. The
    /// sandbox denies the app exact footprints for its WebKit helpers; the
    /// helper is not sandboxed, so the header resource meter asks it instead.
    func processUsage(coalition: UInt64, reply: @escaping @Sendable (Data?) -> Void)
}

nonisolated enum WispUpdateHelper {
    static let serviceName = "app.wisp.desktop.UpdateHelper"
}
