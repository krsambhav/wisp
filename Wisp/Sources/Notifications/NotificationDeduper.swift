import Foundation

/// Suppresses duplicate notifications. WhatsApp occasionally fires the same
/// notification twice (e.g. on reconnect), and tags are reused per chat.
nonisolated struct NotificationDeduper {
    private var recent: [String: Date] = [:]
    let window: TimeInterval

    init(window: TimeInterval = 4) { self.window = window }

    /// Returns true if this notification should be shown.
    mutating func shouldShow(key: String, now: Date = Date()) -> Bool {
        recent = recent.filter { now.timeIntervalSince($0.value) < window }
        if let last = recent[key], now.timeIntervalSince(last) < window { return false }
        recent[key] = now
        return true
    }

    nonisolated static func key(accountID: UUID, title: String, body: String, tag: String) -> String {
        var hasher = Hasher()
        hasher.combine(title); hasher.combine(body); hasher.combine(tag)
        return "\(accountID.uuidString):\(hasher.finalize())"
    }
}

/// Parses WhatsApp's `document.title` into an unread count.
/// Observed formats: "WhatsApp", "(3) WhatsApp", "• WhatsApp" (muted unread).
nonisolated enum UnreadTitleParser {
    nonisolated static func unreadCount(from title: String?) -> Int {
        guard let title else { return 0 }
        guard let open = title.firstIndex(of: "("), let close = title[open...].firstIndex(of: ")") else { return 0 }
        let inner = title[title.index(after: open)..<close]
        return Int(inner.trimmingCharacters(in: .whitespaces)) ?? 0
    }
}
