import SwiftUI

struct AccountSwitcher: View {
    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env
    @State private var hoveringAdd = false

    var body: some View {
        HStack(spacing: 4) {
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
                WIcon("plus", size: 13)
                    .foregroundStyle(palette.shellForeground.color.opacity(hoveringAdd ? 0.9 : 0.5))
                    .frame(width: 24, height: 24)
                    .background(hoveringAdd ? palette.surfaceHighlight.color : .clear)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringAdd = $0 }
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
        Button(action: action) {
            HStack(spacing: 7) {
                AvatarView(account: account, size: 22)
                    .overlay(Circle().stroke(isActive ? palette.accent.color : .clear, lineWidth: 1.5).padding(-2))
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 && !isActive {
                            UnreadPill(count: unread, color: palette.unreadBadge.color, textColor: palette.unreadBadgeText.color).offset(x: 6, y: -6)
                        }
                    }
                if isActive {
                    Text(account.name)
                        .font(WispUI.font(12.5, .semibold))
                        .foregroundStyle(palette.shellForeground.color)
                        .lineLimit(1)
                    if account.muted { WIcon("bell-off", size: 11).foregroundStyle(palette.shellForeground.color.opacity(0.5)) }
                }
            }
            .padding(.leading, 4).padding(.trailing, isActive ? 10 : 4).frame(height: 28)
            .background(isActive || hovering ? palette.surfaceHighlight.color : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isActive ? account.name : "\(account.name)\(unread > 0 ? " — \(unread) unread" : "")")
    }
}
