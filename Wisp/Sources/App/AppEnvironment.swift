import AppKit
import Foundation
import SwiftUI

/// Composition root. Everything with lifetime == app lifetime lives here and
/// is injected into SwiftUI via `.environment(env)`.
@MainActor
@Observable
final class AppEnvironment {
    /// Created lazily on first access (the SwiftUI scene body may evaluate
    /// before the app delegate's launch callbacks).
    static let shared = AppEnvironment()

    let settings: SettingsStore
    let accounts: AccountStore
    let scripts: ScriptStore
    let customCSS: CustomCSSStore
    let injection: InjectionEngine
    let notifications: NotificationBridge
    let downloads: DownloadManager
    let network: NetworkMonitor
    let updates = UpdateManager()
    let resources = ResourceMonitor()
    let toasts = ToastCenter()
    let settingsNavigation = SettingsNavigation()
    let launchedAt = Date()
    /// Set by debug hooks (timed quit) to bypass the sync guard.
    var isQuitForced = false

    /// Debug-only: load the bundled mock page instead of web.whatsapp.com
    /// (WISP_MOCK=1). Lets the theme engine, bridge and notifications be
    /// exercised without a linked phone. Always false in Release builds.
    let mockMode: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["WISP_MOCK"] == "1"
        #else
        return false
        #endif
    }()

    private(set) var sessions: SessionManager!
    private(set) var window: MainWindowController!
    private(set) var menuBar: MenuBarController!

    init() {
        settings = SettingsStore()
        accounts = AccountStore()
        scripts = ScriptStore()
        customCSS = CustomCSSStore()
        injection = InjectionEngine(settings: settings, scripts: scripts, customCSS: customCSS)
        notifications = NotificationBridge(settings: settings)
        downloads = DownloadManager(settings: settings)
        network = NetworkMonitor()

        sessions = SessionManager(environment: self)
        window = MainWindowController(environment: self)
        menuBar = MenuBarController(environment: self)

        wire()
        startObservingSettings()
        Log.info("Environment ready in \(Int(Date().timeIntervalSince(launchedAt) * 1000)) ms", .performance)
    }

    // MARK: Wiring

    private func wire() {
        notifications.onActivate = { [weak self] accountID, id in
            guard let self else { return }
            self.sessions.activate(accountID)
            self.showMainWindow()
            self.sessions.session(for: accountID)?.notificationClicked(id: id)
        }
        notifications.onDownloadActivate = { [weak self] url in self?.downloads.reveal(url) }
        downloads.onFinished = { [weak self] url in
            guard let self else { return }
            self.toasts.show(title: "Downloaded \(url.lastPathComponent)", actionTitle: "Show in Finder") { [weak self] in self?.downloads.reveal(url) }
            if !NSApp.isActive || !self.window.isKeyAndVisible { self.notifications.notifyDownloadFinished(url: url) }
        }
        network.onReconnect = { [weak self] in self?.sessions.retryFailed() }
        updates.onUpdateFound = { [weak self] release in
            guard let self else { return }
            self.toasts.show(title: "Wisp \(release.version) is available", actionTitle: "Update") { [weak self] in
                Task { await self?.updates.downloadAndInstall() }
            }
        }
        scripts.onExternalChange = { [weak self] in
            guard let self else { return }
            self.sessions.refreshUserScriptsEverywhere()
            self.sessions.reloadAll()
            self.toasts.show(title: "Scripts reloaded from disk")
        }
        scripts.setWatching(settings.advanced.hotReloadScripts)
        applyHotKey()
    }

    /// Observation-driven propagation: appearance → live CSS; scripts → user
    /// scripts; advanced → dev tools/hot reload. No timers, no polling.
    private func startObservingSettings() {
        track({ [settings] in _ = settings.appearance }) { [weak self] in
            guard let self else { return }
            self.sessions.applyAppearanceEverywhere()
            self.sessions.applyLiveStylesEverywhere()
            self.window.refreshChrome()
        }
        track({ [customCSS, settings] in _ = customCSS.css; _ = settings.appearance.customCSSEnabled; _ = settings.appearance.livePreview }) { [weak self] in
            guard let self, self.settings.appearance.livePreview else { return }
            self.sessions.applyLiveStylesEverywhere()
        }
        track({ [scripts] in _ = scripts.revision }) { [weak self] in
            self?.sessions.refreshUserScriptsEverywhere()
        }
        track({ [settings] in _ = settings.advanced.developerToolsEnabled; _ = settings.advanced.hotReloadScripts }) { [weak self] in
            guard let self else { return }
            self.sessions.setDeveloperToolsEverywhere(self.settings.advanced.developerToolsEnabled)
            self.scripts.setWatching(self.settings.advanced.hotReloadScripts)
        }
        track({ [settings] in _ = settings.general.globalHotKey; _ = settings.general.globalHotKeyEnabled }) { [weak self] in
            self?.applyHotKey()
        }
        track({ [settings] in _ = settings.general.showMenuBarItem; _ = settings.general.hideDockIconInMenuBarMode; _ = settings.notifications.menuBarBadge; _ = settings.notifications.dockBadge; _ = settings.notifications.muted; _ = settings.notifications.muteUntil }) { [weak self] in
            self?.badgesDidChange()
            self?.menuBar.refresh()
        }
    }

    /// Re-arming observation helper. `read` touches the properties to observe;
    /// `onChange` fires on the main actor after any of them change.
    private func track(_ read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
        withObservationTracking {
            read()
        } onChange: {
            Task { @MainActor [weak self] in
                onChange()
                self?.track(read, onChange: onChange)
            }
        }
    }

    // MARK: App-level actions

    func showMainWindow() {
        window.show()
        NSApp.activateFrontmost()
    }

    func toggleMainWindow() {
        if window.isKeyAndVisible && NSApp.isActive { window.hide() } else { showMainWindow() }
    }

    func openSettings(_ section: SettingsSection? = nil) {
        if let section { settingsNavigation.section = section }
        NSApp.activateFrontmost()
        // SwiftUI's Settings scene is reachable through its own "Settings…" menu item.
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let item = appMenu.items.first(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == [.command] }),
           let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func reloadActive(ignoringCache: Bool = false) { sessions.activeSession?.reload(ignoringCache: ignoringCache) }

    /// Restarts every loaded page in a fresh WebContent process, dropping what
    /// WhatsApp accumulated in memory (a plain reload keeps the process and its
    /// footprint). The device stays linked; unsent drafts are lost. Refuses
    /// while WhatsApp is still downloading history, since interrupting that
    /// can unlink the device.
    func freeUpMemory() {
        guard !resources.isFreeing else { return }
        if let syncing = sessions.loadedSessions.first(where: \.mayBeSyncing) {
            Log.info("Free up memory refused: \(syncing.account.name) is still loading", .performance)
            toasts.show(title: "WhatsApp (\(syncing.account.name)) is still loading. Try again once its chat list appears.")
            return
        }
        let before = resources.sample?.memory ?? 0
        resources.isFreeing = true
        Log.info("Freeing memory: reloading \(sessions.loadedSessions.count) page(s) from \(ResourceFormat.memory(before))", .performance)
        Task { [weak self] in
            guard let self else { return }
            for session in sessions.loadedSessions { await session.restartContentProcess() }
            try? await Task.sleep(for: .seconds(15))
            resources.isFreeing = false
            let after = resources.sample?.memory ?? before
            if before > after, before - after > 50 << 20 {
                toasts.show(title: "Freed \(ResourceFormat.memory(before - after)). WhatsApp reloaded.")
            } else {
                toasts.show(title: "WhatsApp reloaded.")
            }
        }
    }

    /// Menu / Settings entry point. Reports the outcome as a toast; the header
    /// pill and Settings › General carry the state afterwards.
    func checkForUpdates() {
        Task { @MainActor in
            await updates.check(userInitiated: true)
            switch updates.state {
            case .upToDate: toasts.show(title: "Wisp \(updates.currentVersion) is up to date")
            case .available(let r): toasts.show(title: "Wisp \(r.version) is available", actionTitle: "Update") { [weak self] in Task { await self?.updates.downloadAndInstall() } }
            case .failed(let why): toasts.show(title: "Couldn’t check for updates: \(why)")
            default: break
            }
        }
    }
    func focusSearch() { sessions.activeSession?.focusSearch() }

    func toggleMute() {
        settings.notifications.muted.toggle()
        settings.notifications.muteUntil = nil
        toasts.show(title: settings.notifications.muted ? "Notifications muted" : "Notifications on")
    }

    func badgesDidChange() {
        let total = sessions?.totalUnread ?? 0
        NSApp.dockTile.badgeLabel = (settings.notifications.dockBadge && total > 0) ? String(total) : nil
        Log.debug("Badge total=\(total) dock=\(NSApp.dockTile.badgeLabel ?? "nil")", .notifications)
        menuBar?.refresh()
    }

    private func applyHotKey() {
        if settings.general.globalHotKeyEnabled {
            GlobalHotKeyManager.shared.register(settings.general.globalHotKey) { [weak self] in self?.toggleMainWindow() }
        } else {
            GlobalHotKeyManager.shared.unregister()
        }
    }

    /// "Reset all customizations": appearance defaults, empty custom CSS,
    /// all scripts disabled (files are kept).
    func resetCustomizations() {
        settings.resetAppearance()
        customCSS.css = ""
        scripts.disableAll()
        sessions.applyLiveStylesEverywhere()
        toasts.show(title: "Customizations reset")
        Log.info("Customizations reset to defaults", .settings)
    }

    func applyPreset(_ preset: CustomizationPreset, includeScripts: Bool) {
        settings.appearance = preset.appearance
        customCSS.css = preset.customCSS
        if includeScripts, let scripts = preset.scripts {
            for var s in scripts {
                s.id = UUID(); s.enabled = false
                _ = self.scripts.create(name: s.name)
                if var created = self.scripts.scripts.last { created.source = s.source; created.summary = s.summary; created.world = s.world; created.injectionTime = s.injectionTime; created.enabled = false; self.scripts.update(created) }
            }
        }
        toasts.show(title: "Preset “\(preset.name)” applied")
    }

    func exportPreset(name: String, includeScripts: Bool) -> CustomizationPreset {
        CustomizationPreset(name: name, exportedAt: Date(), appearance: settings.appearance, customCSS: customCSS.css, scripts: includeScripts ? scripts.scripts : nil)
    }

    var currentTheme: Theme { ThemeCatalog.theme(id: settings.appearance.themeID) }

    /// Palette for the native chrome, respecting the forced appearance mode.
    func shellPalette(systemIsDark: Bool) -> ThemePalette {
        let theme = currentTheme
        let mode = theme.preferredMode ?? settings.appearance.mode
        var dark = switch mode { case .system: systemIsDark; case .light: false; case .dark: true }
        // Follow what WhatsApp is actually rendering when we know it.
        if let scheme = sessions?.activeSession?.webScheme { dark = scheme == "dark" }
        return CSSGenerator.resolved(theme.palette(for: dark), appearance: settings.appearance)
    }
}

// MARK: - Small shared observables

@MainActor
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general
}

nonisolated enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, scripts, notifications, accounts, advanced
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general: "settings"
        case .appearance: "palette"
        case .scripts: "code"
        case .notifications: "bell"
        case .accounts: "users"
        case .advanced: "wrench"
        }
    }
}

nonisolated struct Toast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let actionTitle: String?
    let action: (@MainActor () -> Void)?
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var toasts: [Toast] = []

    func show(title: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        let t = Toast(title: title, actionTitle: actionTitle, action: action)
        toasts.append(t)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(actionTitle == nil ? 3 : 6))
            self?.dismiss(t.id)
        }
    }

    func dismiss(_ id: UUID) { toasts.removeAll { $0.id == id } }
}
