import SwiftUI

/// 38pt native header. Traffic lights live in the leading 70pt (window chrome);
/// then account switcher; trailing: status, mute, settings.
struct HeaderBar: View {
    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let fg = palette.shellForeground.color
        HStack(spacing: 6) {
            Spacer().frame(width: 72)
            AccountSwitcher(palette: palette)
            Spacer()
            statusPill
            WIconButton(icon: env.settings.notifications.isEffectivelyMuted ? "bell-off" : "bell",
                        help: env.settings.notifications.isEffectivelyMuted ? "Notifications muted — click to unmute" : "Mute notifications",
                        tint: env.settings.notifications.isEffectivelyMuted ? WispUI.warning : fg.opacity(0.75)) { env.toggleMute() }
            WIconButton(icon: "settings", help: "Settings (⌘,)", tint: fg.opacity(0.75)) { env.openSettings() }
            Spacer().frame(width: 6)
        }
        .frame(height: 38)
        .background(palette.shellBackground.color)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.shellDivider.color).frame(height: 1) }
        .foregroundStyle(fg)
    }

    @ViewBuilder private var statusPill: some View {
        if let s = env.sessions.activeSession {
            switch s.pageState {
            case .qr:
                WBadge(text: "Scan QR to link", color: WispUI.warning)
            case .failed:
                WBadge(text: env.network.isOnline ? "Disconnected" : "Offline", color: WispUI.destructive)
            case .loading where !s.hasFinishedFirstLoad:
                WBadge(text: "Connecting", color: WispUI.muted)
            default:
                EmptyView()
            }
        }
    }
}
