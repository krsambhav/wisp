import SwiftUI

/// Account tabs. The active account is a filled tab with its name; the others
/// collapse to their avatar (with an unread pill) until hovered.
struct AccountSwitcher: View {
    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env
    @State private var hoveringAdd = false

    var body: some View {
        let fg = palette.shellForeground.color
        HStack(spacing: 6) {
            ForEach(env.accounts.accounts) { account in
                AccountChip(account: account, palette: palette, isActive: account.id == env.sessions.activeAccountID,
                            unread: env.sessions.sessions[account.id]?.unreadCount ?? 0) {
                    env.sessions.activate(account.id)
                }
                .contextMenu {
                    Button("Rename…") { env.openSettings(.accounts) }
                    Button(account.muted ? "Unmute" : "Mute") { var a = account; a.muted.toggle(); env.sessions.updateAccount(a) }
                    Button("Reload") { env.sessions.session(for: account.id)?.reload() }
                    Divider()
                    Button("Manage Accounts…") { env.openSettings(.accounts) }
                }
            }
            Button { env.openSettings(.accounts) } label: {
                WIcon("plus", size: 14)
                    .foregroundStyle(fg.opacity(hoveringAdd ? 0.9 : 0.4))
                    .frame(width: 34, height: 34)
                    .background(hoveringAdd ? fg.opacity(0.06) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringAdd = $0 }
            .animation(.easeOut(duration: 0.12), value: hoveringAdd)
            .help("Add account")
        }
    }
}

private struct AccountChip: View {
    let account: Account
    let palette: ThemePalette
    let isActive: Bool
    let unread: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let fg = palette.shellForeground.color
        Button(action: action) {
            HStack(spacing: 9) {
                AvatarView(account: account, size: 24)
                    .opacity(isActive || hovering ? 1 : 0.7)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 && !isActive {
                            UnreadPill(count: unread, color: palette.unreadBadge.color, textColor: palette.unreadBadgeText.color)
                                .overlay(Capsule().stroke(palette.shellBackground.color, lineWidth: 1.5))
                                .offset(x: 7, y: -6)
                        }
                    }
                if isActive {
                    Text(account.name)
                        .font(WispUI.font(13, .semibold))
                        .foregroundStyle(fg)
                        .lineLimit(1)
                    if account.muted { WIcon("bell-off", size: 12).foregroundStyle(fg.opacity(0.45)) }
                }
            }
            .padding(.leading, 6).padding(.trailing, isActive ? 13 : 6).frame(height: 34)
            .background(isActive ? fg.opacity(0.07) : (hovering ? fg.opacity(0.04) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(isActive ? account.name : "\(account.name)\(unread > 0 ? " — \(unread) unread" : "")")
    }
}
