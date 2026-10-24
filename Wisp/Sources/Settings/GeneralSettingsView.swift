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
}
