import SwiftUI

@main
struct WispApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The main window is an AppKit NSWindowController (see MainWindowController)
        // so we get precise control over frame restoration, close-to-hide and the
        // persistent web view. SwiftUI owns Settings (⌘,) and the menu bar.
        Settings {
            SettingsRootView()
                .environment(delegate.environment)
                .frame(minWidth: 880, idealWidth: 940, minHeight: 600, idealHeight: 680)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { WispCommands(environment: delegate.environment) }
    }
}
