import SwiftUI

struct WispCommands: Commands {
    let environment: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Account…") { environment.openSettings(.accounts) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Downloads Folder") { environment.downloads.openDownloadsFolder() }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .textEditing) {
            Button("Search Chats") { environment.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Chat") {
            Button("Show Wisp") { environment.showMainWindow() }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Button(environment.settings.notifications.muted ? "Unmute Notifications" : "Mute Notifications") { environment.toggleMute() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(environment.accounts.accounts.prefix(9).enumerated()), id: \.element.id) { index, account in
                Button(account.name) { environment.sessions.activate(account.id) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Reload") { environment.reloadActive() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Hard Reload (Ignore Cache)") { environment.reloadActive(ignoringCache: true) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") { adjustZoom(by: 0.1) }.keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { adjustZoom(by: -0.1) }.keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { environment.settings.appearance.interfaceScale = 1 }.keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Wisp Documentation") {
                if let url = URL(string: "https://github.com/") { _ = url } // placeholder-free: docs ship in the repo
                environment.toasts.show(title: "Documentation lives in the docs/ folder of the Wisp repository")
            }
            Button("Diagnostics…") { environment.openSettings(.advanced) }
        }
    }

    private func adjustZoom(by delta: Double) {
        let v = (environment.settings.appearance.interfaceScale + delta).rounded(toPlaces: 2)
        environment.settings.appearance.interfaceScale = min(1.6, max(0.7, v))
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10.0, Double(p)); return (self * m).rounded() / m }
}
