import AppKit
import Foundation
import Security
import UserNotifications

nonisolated struct IncomingNotification: Sendable {
    let id: Int
    let title: String
    let body: String
    let tag: String
    let iconDataURL: String?
    let silent: Bool
}

/// Native macOS Notification Center integration. One instance for the app.
///
/// Identifier scheme: "acct=<uuid>;n=<id>;tag=<tag>" — the tag makes
/// same-chat notifications replace one another (WhatsApp sets one tag per chat).
@MainActor
final class NotificationBridge: NSObject {
    private let settings: SettingsStore
    private let center = UNUserNotificationCenter.current()
    private var deduper = NotificationDeduper()
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// True when the running bundle has no Team ID (ad-hoc signature). macOS
    /// refuses notification authorization for such builds — and worse, records
    /// the refusal against the bundle identifier permanently. We never ask.
    nonisolated static let isAdHocSigned: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return true }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return true }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return true }
        return (dict[kSecCodeInfoTeamIdentifier as String] as? String)?.isEmpty ?? true
    }()
    var notificationsUnavailableReason: String? {
        Self.isAdHocSigned ? "This build is ad-hoc signed. macOS only delivers notifications for apps signed with a Developer ID or Apple Development certificate (see docs/BUILD.md)." : nil
    }
    /// Set by the app: (accountID, notificationID) → handle click.
    var onActivate: (@MainActor (UUID, Int) -> Void)?
    var onDownloadActivate: (@MainActor (URL) -> Void)?

    static let downloadCategory = "wisp.download"
    static let messageCategory = "wisp.message"

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        center.delegate = self
        let download = UNNotificationCategory(identifier: Self.downloadCategory, actions: [
            UNNotificationAction(identifier: "reveal", title: "Show in Finder", options: [])
        ], intentIdentifiers: [], options: [])
        let message = UNNotificationCategory(identifier: Self.messageCategory, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([download, message])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let s = await center.notificationSettings()
        authorizationStatus = s.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        if Self.isAdHocSigned {
            Log.warning("Skipping notification authorization: ad-hoc signed build (macOS would refuse and remember the refusal)", .notifications)
            return false
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            Log.info("Notification authorization: \(granted ? "granted" : "denied")", .notifications)
            return granted
        } catch {
            Log.error("Notification authorization failed: \(error.localizedDescription)", .notifications)
            return false
        }
    }

    // MARK: Messages

    func deliver(_ n: IncomingNotification, account: Account, isAccountVisibleAndFocused: Bool) {
        let prefs = settings.notifications
        guard prefs.enabled, account.notificationsEnabled else { return }
        if prefs.isEffectivelyMuted || account.muted { return }
        if prefs.suppressWhenWindowFocused && isAccountVisibleAndFocused {
            Log.debug("Notification suppressed: account is visible and focused", .notifications)
            return
        }
        guard deduper.shouldShow(key: NotificationDeduper.key(accountID: account.id, title: n.title, body: n.body, tag: n.tag)) else {
            Log.debug("Duplicate notification suppressed", .notifications)
            return
        }
        if authorizationStatus == .notDetermined {
            Task { _ = await requestAuthorization(); self.deliver(n, account: account, isAccountVisibleAndFocused: isAccountVisibleAndFocused) }
            return
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let showPreview = account.showPreviews ?? prefs.showPreviews
        let content = UNMutableNotificationContent()
        content.title = showPreview ? n.title : "New message"
        content.body = showPreview ? n.body : (n.title.isEmpty ? "You have a new message." : "From \(n.title)")
        content.categoryIdentifier = Self.messageCategory
        content.threadIdentifier = "\(account.id.uuidString):\(n.tag)"
        if prefs.sound == .system && !n.silent { content.sound = .default }
        content.userInfo = ["account": account.id.uuidString, "id": n.id]
        if let attachment = Self.attachment(fromDataURL: n.iconDataURL, id: "\(account.id)-\(n.id)") { content.attachments = [attachment] }

        let tag = n.tag.isEmpty ? "n\(n.id)" : n.tag
        let identifier = "acct=\(account.id.uuidString);tag=\(tag)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error { Log.error("Failed to post notification: \(error.localizedDescription)", .notifications) }
        }
        Log.info("Notification delivered (account \(account.id.uuidString.prefix(8)))", .notifications)
    }

    func withdraw(accountID: UUID, tag: String, id: Int) {
        let t = tag.isEmpty ? "n\(id)" : tag
        center.removeDeliveredNotifications(withIdentifiers: ["acct=\(accountID.uuidString);tag=\(t)"])
    }

    func withdrawAll(accountID: UUID) {
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix("acct=\(accountID.uuidString);") }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: Downloads

    func notifyDownloadFinished(url: URL) {
        guard settings.notifications.enabled, settings.notifications.showDownloadNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = url.lastPathComponent
        content.categoryIdentifier = Self.downloadCategory
        content.userInfo = ["download": url.path]
        center.add(UNNotificationRequest(identifier: "download-\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: Helpers

    nonisolated private static func attachment(fromDataURL dataURL: String?, id: String) -> UNNotificationAttachment? {
        guard let dataURL, let comma = dataURL.firstIndex(of: ",") else { return nil }
        let header = dataURL[..<comma]
        guard header.contains(";base64") else { return nil }
        let ext = header.contains("image/png") ? "png" : header.contains("image/jpeg") || header.contains("image/jpg") ? "jpg" : nil
        guard let ext, let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
        let url = Paths.temporaryDirectory.appendingPathComponent("notif-\(id).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "icon", url: url, options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false])
        } catch { return nil }
    }
}

extension NotificationBridge: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let accountString = info["account"] as? String
        let id = (info["id"] as? NSNumber)?.intValue
        let download = info["download"] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            if let download {
                let url = URL(fileURLWithPath: download)
                if action == "reveal" || action == UNNotificationDefaultActionIdentifier { self.onDownloadActivate?(url) }
                return
            }
            if let accountString, let accountID = UUID(uuidString: accountString), let id {
                self.onActivate?(accountID, id)
            }
        }
    }
}
