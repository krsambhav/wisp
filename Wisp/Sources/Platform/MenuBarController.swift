import AppKit

/// Status-bar item with unread count. Left click toggles the window; right
/// click opens a menu with accounts, mute and quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let env: AppEnvironment
    private var item: NSStatusItem?

    init(environment: AppEnvironment) {
        self.env = environment
        super.init()
        refresh()
    }

    func refresh() {
        let wanted = env.settings.general.showMenuBarItem
        if wanted && item == nil { install() }
        if !wanted, let existing = item { NSStatusBar.system.removeStatusItem(existing); item = nil }
        updateAppearance()
        let accessory = env.settings.general.showMenuBarItem && env.settings.general.hideDockIconInMenuBarMode
        let policy: NSApplication.ActivationPolicy = accessory ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "lucide.message-circle")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item
    }

    private func updateAppearance() {
        guard let button = item?.button else { return }
        let total = env.sessions?.totalUnread ?? 0
        let muted = env.settings.notifications.isEffectivelyMuted
        button.image = NSImage(named: muted ? "lucide.bell-off" : "lucide.message-circle")
        button.image?.isTemplate = true
        button.image?.size = NSSize(width: 16, height: 16)
        if env.settings.notifications.menuBarBadge && total > 0 {
            button.title = " \(total)"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
        }
        button.toolTip = total > 0 ? "Wisp — \(total) unread" : "Wisp"
    }

    @objc private func clicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { env.toggleMainWindow(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            env.toggleMainWindow()
        }
    }

    private func showMenu() {
        guard let item else { return }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show Wisp", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        for (i, account) in env.accounts.accounts.enumerated() {
            let unread = env.sessions.sessions[account.id]?.unreadCount ?? 0
            let title = unread > 0 ? "\(account.name) (\(unread))" : account.name
            let mi = NSMenuItem(title: title, action: #selector(switchAccount(_:)), keyEquivalent: i < 9 ? String(i + 1) : "")
            mi.target = self
            mi.representedObject = account.id
            mi.state = account.id == env.sessions.activeAccountID ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let mute = NSMenuItem(title: env.settings.notifications.muted ? "Unmute Notifications" : "Mute Notifications", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        menu.addItem(mute)
        let muteHour = NSMenuItem(title: "Mute for 1 Hour", action: #selector(muteForHour), keyEquivalent: "")
        muteHour.target = self
        menu.addItem(muteHour)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload WhatsApp", action: #selector(reload), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Wisp", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func showWindow() { env.showMainWindow() }
    @objc private func switchAccount(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { env.sessions.activate(id); env.showMainWindow() }
    }
    @objc private func toggleMute() { env.toggleMute() }
    @objc private func muteForHour() {
        env.settings.notifications.muted = false
        env.settings.notifications.muteUntil = Date().addingTimeInterval(3600)
        env.toasts.show(title: "Muted for 1 hour")
    }
    @objc private func reload() { env.reloadActive() }
    @objc private func openSettings() { env.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
