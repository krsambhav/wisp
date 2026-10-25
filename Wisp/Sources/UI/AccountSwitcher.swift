import SwiftUI

/// Account tabs. The active account is a filled tab with its name; the others
/// collapse to their avatar (with an unread pill) until hovered.
struct AccountSwitcher: View {
    let palette: ThemePalette
    @Environment(AppEnvironment.self) private var env
    @State private var hoveringAdd = false
    @Namespace private var tabNamespace

    var body: some View {
        let fg = palette.shellForeground.color
        HStack(spacing: 6) {
            ForEach(env.accounts.accounts) { account in
                AccountChip(account: account, palette: palette, isActive: account.id == env.sessions.activeAccountID,
                            unread: env.sessions.sessions[account.id]?.unreadCount ?? 0, namespace: tabNamespace) {
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
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let fg = palette.shellForeground.color
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Button(action: action) {
            HStack(spacing: 9) {
                AvatarView(account: account, size: 24)
                    .opacity(isActive || hovering ? 1 : 0.7)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 && !isActive {
                            TabBadge(count: unread, color: palette.unreadBadge.color, textColor: palette.unreadBadgeText.color,
                                     ring: palette.shellBackground.color)
                                .offset(x: 5, y: -4)
                        }
                    }
                if isActive {
                    Text(account.name)
                        .font(WispUI.font(13, .semibold))
                        .foregroundStyle(fg)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    if account.muted { WIcon("bell-off", size: 12).foregroundStyle(fg.opacity(0.45)) }
                }
            }
            .padding(.leading, 6).padding(.trailing, isActive ? 13 : 6).frame(height: 34)
            .background {
                // The active fill is one shared shape that glides between tabs.
                if isActive {
                    shape.fill(fg.opacity(0.07)).matchedGeometryEffect(id: "wisp.activeTab", in: namespace)
                } else if hovering {
                    shape.fill(fg.opacity(0.04))
                }
            }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(isActive ? account.name : "\(account.name)\(unread > 0 ? " — \(unread) unread" : "")")
    }
}

/// Compact unread badge for a 24pt tab avatar: 14pt tall, ringed in the shell
/// background so it reads as sitting on top of the avatar, not inside it.
private struct TabBadge: View {
    let count: Int
    let color: Color
    let textColor: Color
    let ring: Color

    var body: some View {
        Text(count > 99 ? "99+" : String(count))
            .font(WispUI.font(8.5, .bold))
            .monospacedDigit()
            .padding(.horizontal, 3.5).frame(minWidth: 14, minHeight: 14)
            .foregroundStyle(textColor)
            .background(color, in: Capsule())
            .overlay(Capsule().stroke(ring, lineWidth: 1.5))
            .fixedSize()
    }
}
