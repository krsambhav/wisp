import AppKit
import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        SettingsPage(title: "Notifications", subtitle: "Native macOS notifications for new messages. Focus and Do Not Disturb are respected by the system.") {
            if let reason = env.notifications.notificationsUnavailableReason {
                WCard { WRow(title: "Notifications unavailable in this build", description: reason) { WBadge(text: "Ad-hoc", color: WispUI.warning) } }
            }
            if env.notifications.authorizationStatus == .denied {
                WCard {
                    WRow(title: "Notifications are turned off for Wisp in System Settings", description: "Enable them under System Settings › Notifications › Wisp.") {
                        WButton(title: "Open System Settings", icon: "external-link", small: true) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
            WGroupLabel("Messages")
            WCard {
                WRow(title: "Show notifications") { WToggle(isOn: $settings.notifications.enabled) }
                WDivider()
                WRow(title: "Show message previews", description: "Off shows “New message” with the sender only.") { WToggle(isOn: $settings.notifications.showPreviews) }
                WDivider()
                WRow(title: "Sound", description: "WhatsApp also plays its own sound inside the page; turn that off in WhatsApp › Settings › Notifications to avoid a double chime.") {
                    WSelect(selection: $settings.notifications.sound, options: NotificationSoundChoice.allCases, width: 280, label: { $0.label })
                }
                WDivider()
                WRow(title: "Don't notify while Wisp is in front", description: "Suppress banners for the account you're already looking at.") { WToggle(isOn: $settings.notifications.suppressWhenWindowFocused) }
                WDivider()
                WRow(title: "Download notifications", description: "Notify when an attachment finishes downloading while Wisp is in the background.") { WToggle(isOn: $settings.notifications.showDownloadNotifications) }
            }

            WGroupLabel("Mute")
            WCard {
                WRow(title: "Mute all notifications", description: settings.notifications.muteUntil.map { $0 > Date() ? "Muted until \($0.formatted(date: .omitted, time: .shortened))" : nil } ?? nil) {
                    HStack(spacing: 8) {
                        WButton(title: "1 hour", small: true) { settings.notifications.muted = false; settings.notifications.muteUntil = Date().addingTimeInterval(3600) }
                        WButton(title: "Until tomorrow", small: true) { settings.notifications.muted = false; settings.notifications.muteUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)).addingTimeInterval(8 * 3600) }
                        WToggle(isOn: Binding(get: { settings.notifications.muted }, set: { settings.notifications.muted = $0; settings.notifications.muteUntil = nil }))
                    }
                }
            }

            WGroupLabel("Badges")
            WCard {
                WRow(title: "Dock badge", description: "Total unread count across accounts.") { WToggle(isOn: $settings.notifications.dockBadge) }
                WDivider()
                WRow(title: "Menu bar count") { WToggle(isOn: $settings.notifications.menuBarBadge) }
            }

            WGroupLabel("Per account")
            WCard {
                ForEach(Array(env.accounts.accounts.enumerated()), id: \.element.id) { i, account in
                    if i > 0 { WDivider() }
                    HStack(spacing: 12) {
                        AvatarView(account: account, size: 26)
                        Text(account.name).font(WispUI.body)
                        Spacer()
                        WCheckbox(label: "Previews", isOn: Binding(get: { account.showPreviews ?? settings.notifications.showPreviews }, set: { var a = account; a.showPreviews = $0; env.sessions.updateAccount(a) }))
                        WCheckbox(label: "Muted", isOn: Binding(get: { account.muted }, set: { var a = account; a.muted = $0; env.sessions.updateAccount(a) }))
                        WCheckbox(label: "Enabled", isOn: Binding(get: { account.notificationsEnabled }, set: { var a = account; a.notificationsEnabled = $0; env.sessions.updateAccount(a) }))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }

            Text("Notifications are delivered only while the account's session is loaded and connected. WhatsApp Web must be linked and the Mac awake; there is no server-side push.")
                .font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
        }
    }
}
