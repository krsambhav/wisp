import AppKit
import SwiftUI

/// The main window. AppKit-owned so that:
///  - the frame is restored via autosave,
///  - ⌘W hides instead of closing (when "keep running" is on),
///  - the traffic lights sit inside our own 38pt header (unified compact toolbar trick),
///  - the SwiftUI shell is hosted once and never recreated.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private unowned let env: AppEnvironment
    private var hostingView: NSHostingView<AnyView>?

    init(environment: AppEnvironment) {
        self.env = environment
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        configure(window)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func configure(_ window: NSWindow) {
        window.title = "Wisp"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 480)
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.delegate = self
        window.backgroundColor = .windowBackgroundColor
        window.identifier = NSUserInterfaceItemIdentifier("WispMain")

        // An empty toolbar in unified-compact style makes the title bar 38pt
        // tall so the traffic lights are vertically centered in our header.
        let toolbar = NSToolbar(identifier: "WispMainToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        let root = AnyView(MainShellView().environment(env))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        window.contentView = hosting
        hostingView = hosting

        window.setFrameAutosaveName("WispMainWindow")
        if !window.setFrameUsingName("WispMainWindow") { window.center() }
        refreshChrome()
    }

    /// Matches the window's appearance and background to the current theme so
    /// nothing flashes white behind the web view.
    func refreshChrome() {
        guard let window else { return }
        let theme = env.currentTheme
        let mode = theme.preferredMode ?? env.settings.appearance.mode
        switch mode {
        case .system: window.appearance = nil
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        }
        let dark = window.effectiveAppearance.isDark
        window.backgroundColor = env.shellPalette(systemIsDark: dark).shellBackground.nsColor
    }

    var isKeyAndVisible: Bool { (window?.isVisible ?? false) && (window?.isKeyWindow ?? false) }
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        guard let window else { return }
        if NSApp.activationPolicy() == .accessory { /* menu bar mode: window still shows */ }
        window.makeKeyAndOrderFront(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
    }

    func hide() { window?.orderOut(nil) }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if env.settings.general.keepRunningWhenWindowCloses {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) { env.badgesDidChange() }
    func windowDidResignKey(_ notification: Notification) { env.badgesDidChange() }

    func windowDidChangeEffectiveAppearance(_ notification: Notification) { refreshChrome() }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
