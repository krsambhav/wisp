import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var settings = env.settings
        SettingsPage(title: "General", subtitle: "Startup, window behavior and the global shortcut.") {
            WGroupLabel("Startup")
            WCard {
                WRow(title: "Launch at login", description: launchError ?? (LaunchAtLogin.requiresApproval ? "Approval pending in System Settings › General › Login Items." : nil)) {
                    WToggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                        do { try LaunchAtLogin.setEnabled(on); launchAtLogin = LaunchAtLogin.isEnabled; launchError = nil }
                        catch { launchError = error.localizedDescription; launchAtLogin = LaunchAtLogin.isEnabled }
                    }))
                }
                WDivider()
                WRow(title: "Start hidden", description: "Launch into the menu bar without opening the window.") {
                    WToggle(isOn: $settings.general.startHidden)
                }
            }

            WGroupLabel("Updates")
            WCard {
                WRow(title: "Wisp \(env.updates.currentVersion)", description: updateStatusText) { updateButton }
                WDivider()
                WRow(title: "Check for updates automatically", description: "Looks for new releases on GitHub shortly after launch and every six hours. Nothing is installed until you click Update.") {
                    WToggle(isOn: Binding(get: { env.updates.automaticChecks }, set: { env.updates.automaticChecks = $0 }))
                }
            }

            WGroupLabel("Window")
            WCard {
                WRow(title: "Keep running when the window closes", description: "⌘W hides the window; Wisp keeps receiving notifications. Quit with ⌘Q.") {
                    WToggle(isOn: $settings.general.keepRunningWhenWindowCloses)
                }
                WDivider()
                WRow(title: "Show menu bar item", description: "Unread count in the menu bar, click to show or hide Wisp.") {
                    WToggle(isOn: $settings.general.showMenuBarItem)
                }
                WDivider()
                WRow(title: "Menu bar mode", description: "Hide the Dock icon. Wisp lives in the menu bar only.") {
                    WToggle(isOn: $settings.general.hideDockIconInMenuBarMode).disabled(!settings.general.showMenuBarItem)
                }
                WDivider()
                WRow(title: "Show CPU and memory in the header", description: "Live usage of Wisp and its WebKit helpers, grouped the way Activity Monitor does. Click the meter for a breakdown.") {
                    WToggle(isOn: Binding(get: { env.resources.showsInHeader }, set: { env.resources.showsInHeader = $0 }))
                }
                WDivider()
                WRow(title: "Confirm before quitting") { WToggle(isOn: $settings.general.confirmBeforeQuit) }
                WDivider()
                WRow(title: "Open links in your default browser", description: "Links in chats open outside Wisp. Off keeps WhatsApp from leaving its page but still never navigates away.") {
                    WToggle(isOn: $settings.general.openExternalLinksInBrowser)
                }
            }

            WGroupLabel("Shortcut")
            WCard {
                WRow(title: "Global shortcut to show or hide Wisp", description: "Works from any app.") {
                    HStack(spacing: 10) {
                        HotKeyRecorderView(hotKey: $settings.general.globalHotKey).disabled(!settings.general.globalHotKeyEnabled).opacity(settings.general.globalHotKeyEnabled ? 1 : 0.5)
                        WToggle(isOn: $settings.general.globalHotKeyEnabled)
                    }
                }
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var updateStatusText: String? {
        switch env.updates.state {
        case .idle: env.updates.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))." }
        case .checking: "Checking GitHub…"
        case .upToDate: "You're on the latest version."
        case .available(let r): "Version \(r.version) is available. Updating downloads \(ByteCountFormatter.string(fromByteCount: r.assetSize, countStyle: .file)), installs and relaunches Wisp."
        case .downloading: "Downloading…"
        case .installing: "Installing…"
        case .installed(let r): "Version \(r.version) is installed and will start when Wisp relaunches."
        case .failed(let why): why
        }
    }

    @ViewBuilder private var updateButton: some View {
        HStack(spacing: 8) {
            if env.updates.state.release != nil {
                WButton(title: "Release notes", style: .ghost, small: true) { env.updates.openReleaseNotes() }
            }
            switch env.updates.state {
            case .checking, .downloading, .installing:
                ProgressView().controlSize(.small).frame(height: 28)
            case .available(let r):
                WButton(title: "Update to \(r.version)", icon: "download", style: .primary, small: true) { Task { await env.updates.downloadAndInstall() } }
            case .installed:
                WButton(title: "Relaunch", icon: "rocket", style: .primary, small: true) { env.updates.relaunch() }
            default:
                WButton(title: "Check for Updates", icon: "refresh-cw", style: .outline, small: true) { env.checkForUpdates() }
            }
        }
    }
}
