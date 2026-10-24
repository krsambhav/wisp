import Foundation
import WebKit

/// Receives messages from injected scripts and forwards them to the owning
/// session. Holds the session weakly: WKUserContentController retains its
/// handlers, so a strong reference would create a cycle.
///
/// Every payload is validated and truncated here; nothing is trusted.
@MainActor
final class ScriptMessageRouter: NSObject, WKScriptMessageHandler {
    weak var session: AccountSession?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let session else { return }
        guard let kind = BridgeMessage(rawValue: message.name) else { return }
        // Only the main frame of web.whatsapp.com may talk to us.
        let origin = message.frameInfo.securityOrigin
        let trusted = (origin.host.nonEmpty?.hasSuffix("whatsapp.com") ?? false) || (session.isMockMode && origin.protocol == "file")
        guard message.frameInfo.isMainFrame, trusted else {
            Log.warning("Dropped bridge message \(message.name) from unexpected frame", .injection)
            return
        }
        let body = message.body as? [String: Any] ?? [:]

        switch kind {
        case .notify:
            guard message.world == .page else { return }
            let kindStr = body["kind"] as? String ?? "show"
            let id = (body["id"] as? NSNumber)?.intValue ?? 0
            if kindStr == "close" {
                session.handleNotificationClosed(id: id)
            } else {
                let payload = IncomingNotification(
                    id: id,
                    title: String((body["title"] as? String ?? "").prefix(256)),
                    body: String((body["body"] as? String ?? "").prefix(1024)),
                    tag: String((body["tag"] as? String ?? "").prefix(128)),
                    iconDataURL: (body["icon"] as? String).flatMap { $0.hasPrefix("data:image/") && $0.count < 300_000 ? $0 : nil },
                    silent: body["silent"] as? Bool ?? false
                )
                session.handleIncomingNotification(payload)
            }
        case .state:
            if let s = body["state"] as? String { session.handlePageState(s) }
        case .diag:
            let missing = (body["missing"] as? [String] ?? []).map { String($0.prefix(120)) }
            let total = (body["total"] as? NSNumber)?.intValue ?? 0
            session.handleSelectorHealth(total: total, missing: missing)
        case .log:
            let level: LogLevel = switch body["level"] as? String ?? "info" {
                case "debug": .debug
                case "warning", "warn": .warning
                case "error": .error
                default: .info
            }
            let source = String((body["source"] as? String ?? "script").prefix(64))
            let text = String((body["message"] as? String ?? "").prefix(2000))
            Log.script(level, source: source, message: text)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
