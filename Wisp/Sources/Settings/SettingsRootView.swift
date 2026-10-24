import SwiftUI

struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var nav = env.settingsNavigation
        HStack(spacing: 0) {
            sidebar(selection: $nav.section)
            Rectangle().fill(WispUI.border).frame(width: 1)
            detail(nav.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WispUI.background)
        }
        .frame(minWidth: 880, minHeight: 600)
    }

    private func sidebar(selection: Binding<SettingsSection>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings").font(.system(size: 11, weight: .semibold)).foregroundStyle(WispUI.mutedForeground)
                .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 6)
            ForEach(SettingsSection.allCases) { section in
                SidebarItem(section: section, selected: selection.wrappedValue == section) { selection.wrappedValue = section }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Wisp \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground)
                Text("WhatsApp Web in a native shell").font(WispUI.caption).foregroundStyle(WispUI.mutedForeground.opacity(0.7))
            }.padding(12)
        }
        .padding(.horizontal, 8)
        .frame(width: 200)
        .background(WispUI.sidebar)
    }

    @ViewBuilder private func detail(_ section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .scripts: ScriptsSettingsView()
        case .notifications: NotificationsSettingsView()
        case .accounts: AccountsSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                WIcon(section.icon, size: 15).foregroundStyle(selected ? WispUI.foreground : WispUI.mutedForeground)
                Text(section.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 30)
            .foregroundStyle(WispUI.foreground)
            .background(selected ? WispUI.card : (hovering ? WispUI.hover : .clear))
            .clipShape(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WispUI.radius, style: .continuous).stroke(selected ? WispUI.border : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Standard scrollable page layout for a settings section.
struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WSectionHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}
