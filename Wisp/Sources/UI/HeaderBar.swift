import SwiftUI

/// 52pt native header that doubles as the title bar. The traffic lights sit in
/// the leading inset (window chrome); then the account tabs; trailing: status,
/// mute, settings. The bar shares the page surface so the shell and WhatsApp
/// read as one canvas.
struct HeaderBar: View {
    static let height: CGFloat = 52

    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let fg = palette.shellForeground.color
        HStack(spacing: 10) {
            Spacer().frame(width: 84)
            AccountSwitcher(palette: palette)
            Spacer(minLength: 16)
            if env.resources.showsInHeader { ResourceMeter(palette: palette) }
            updatePill
            statusPill
            HStack(spacing: 2) {
                HeaderIconButton(icon: env.settings.notifications.isEffectivelyMuted ? "bell-off" : "bell",
                                 help: env.settings.notifications.isEffectivelyMuted ? "Notifications muted — click to unmute" : "Mute notifications",
                                 palette: palette,
                                 tint: env.settings.notifications.isEffectivelyMuted ? WispUI.warning : nil) { env.toggleMute() }
                HeaderIconButton(icon: "settings", help: "Settings (⌘,)", palette: palette) { env.openSettings() }
            }
            Spacer().frame(width: 10)
        }
        .frame(height: Self.height)
        .background(palette.shellBackground.color)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.shellDivider.color).frame(height: 0.5) }
        .foregroundStyle(fg)
    }

    @ViewBuilder private var updatePill: some View {
        switch env.updates.state {
        case .available(let r):
            Button { Task { await env.updates.downloadAndInstall() } } label: { WBadge(text: "Update to \(r.version)", color: WispUI.success) }
                .buttonStyle(.plain).help("Download and install Wisp \(r.version), then relaunch")
        case .downloading:
            WBadge(text: "Downloading update", color: WispUI.mutedForeground)
        case .installing:
            WBadge(text: "Installing update", color: WispUI.mutedForeground)
        case .installed(let r):
            Button { env.updates.relaunch() } label: { WBadge(text: "Relaunch for \(r.version)", color: WispUI.success) }
                .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var statusPill: some View {
        if let s = env.sessions.activeSession {
            switch s.pageState {
            case .qr:
                WBadge(text: "Scan QR to link", color: WispUI.warning)
            case .failed:
                WBadge(text: env.network.isOnline ? "Disconnected" : "Offline", color: WispUI.destructive)
            case .loading where !s.hasFinishedFirstLoad:
                WBadge(text: "Connecting", color: WispUI.mutedForeground)
            default:
                EmptyView()
            }
        }
    }
}

/// Icon button tinted from the shell palette (not the settings palette) so it
/// follows WhatsApp's light/dark scheme like the rest of the header.
struct HeaderIconButton: View {
    let icon: String
    var help: String = ""
    let palette: ThemePalette
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let fg = palette.shellForeground.color
        Button(action: action) {
            WIcon(icon, size: 16)
                .foregroundStyle(tint ?? fg.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 34, height: 34)
                .background(hovering ? fg.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
