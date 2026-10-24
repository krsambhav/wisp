import Foundation

/// A WhatsApp account slot. Each account owns an isolated
/// `WKWebsiteDataStore` identified by `dataStoreID`, so cookies, IndexedDB,
/// service-worker state and caches never mix between accounts.
nonisolated struct Account: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var dataStoreID: UUID
    var colorIndex: Int
    /// File name inside Paths.avatarsDirectory, if the user picked a custom image.
    var avatarFileName: String?
    var createdAt: Date

    // Per-account notification preferences
    var notificationsEnabled: Bool
    var showPreviews: Bool?        // nil → inherit global
    var muted: Bool
    /// Connect this account at launch (before it is first opened) so it receives
    /// notifications immediately. Sessions are always kept alive once opened.
    var keepLoadedInBackground: Bool

    init(id: UUID = UUID(), name: String, dataStoreID: UUID = UUID(), colorIndex: Int = 0, avatarFileName: String? = nil,
         createdAt: Date = Date(), notificationsEnabled: Bool = true, showPreviews: Bool? = nil, muted: Bool = false,
         keepLoadedInBackground: Bool = false) {
        self.id = id; self.name = name; self.dataStoreID = dataStoreID; self.colorIndex = colorIndex
        self.avatarFileName = avatarFileName; self.createdAt = createdAt
        self.notificationsEnabled = notificationsEnabled; self.showPreviews = showPreviews; self.muted = muted
        self.keepLoadedInBackground = keepLoadedInBackground
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    nonisolated static let avatarPalette: [HexColor] = [
        HexColor("#0EA5E9"), HexColor("#8B5CF6"), HexColor("#F59E0B"), HexColor("#10B981"),
        HexColor("#EF4444"), HexColor("#EC4899"), HexColor("#6366F1"), HexColor("#14B8A6")
    ]

    var avatarColor: HexColor { Self.avatarPalette[((colorIndex % Self.avatarPalette.count) + Self.avatarPalette.count) % Self.avatarPalette.count] }
}
