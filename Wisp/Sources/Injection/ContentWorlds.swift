import WebKit

/// The JavaScript worlds Wisp uses. Keeping them named and centralized makes
/// the isolation story auditable:
///   page     — WhatsApp's own world. Only the Notification polyfill and
///              page-context user scripts run here.
///   core     — Wisp's private world (style injection, state detection).
///   user     — isolated user scripts share this world so they can cooperate
///              without touching WhatsApp's objects.
enum ContentWorlds {
    static let core = WKContentWorld.world(name: "wisp.core")
    static let user = WKContentWorld.world(name: "wisp.user")
    static var page: WKContentWorld { .page }

    static func world(for scriptWorld: ScriptWorld) -> WKContentWorld {
        scriptWorld == .page ? .page : user
    }
}

/// Names of native message handlers. Each is registered only in the worlds
/// that legitimately need it.
nonisolated enum BridgeMessage: String, CaseIterable {
    case notify = "wispNotify"   // page world only
    case state = "wispState"     // core world
    case diag = "wispDiag"       // core world
    case clipboard = "wispClipboard"  // core world: copy-message button
    case log = "wispLog"         // core, user, page
}
