import AppKit
import Foundation

// MARK: - Settings model

nonisolated struct HotKey: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt      // NSEvent.ModifierFlags raw value (device-independent)

    static let `default` = HotKey(keyCode: 13 /* W */, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask) }

    /// Human-readable, e.g. "⌃⌥W".
    var displayString: String {
        var s = ""
        let f = modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + KeyCodeNames.name(for: keyCode)
    }
}

nonisolated enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
}

nonisolated enum Density: String, Codable, CaseIterable, Sendable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

nonisolated enum FontChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case jakarta, system, rounded, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self { case .jakarta: "Plus Jakarta Sans"; case .system: "System (SF Pro)"; case .rounded: "Rounded (SF Rounded)"; case .serif: "Serif (New York)"; case .mono: "Monospace (SF Mono)" }
    }
    /// Bundled web font needs an @font-face injection.
    var isBundledWebFont: Bool { self == .jakarta }
    var cssFamily: String {
        switch self {
        case .jakarta: "\"Plus Jakarta Sans\", -apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif"
        case .system: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", Helvetica, Arial, sans-serif"
        case .rounded: "ui-rounded, \"SF Pro Rounded\", -apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: "ui-serif, \"New York\", Georgia, serif"
        case .mono: "ui-monospace, \"SF Mono\", Menlo, monospace"
        }
    }
}

nonisolated enum NotificationSoundChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, none
    var id: String { rawValue }
    var label: String { switch self { case .system: "System default"; case .none: "None (WhatsApp's in-page sound only)" } }
}

nonisolated struct GeneralSettings: Codable, Equatable, Sendable {
    var keepRunningWhenWindowCloses = true
    var showMenuBarItem = true
    var hideDockIconInMenuBarMode = false
    var startHidden = false
    var globalHotKeyEnabled = true
    var globalHotKey: HotKey = .default
    var confirmBeforeQuit = false
    var openExternalLinksInBrowser = true
}

nonisolated struct AppearanceSettings: Codable, Equatable, Sendable {
    var themeID: String = "minimal"
    var mode: AppearanceMode = .system
    /// nil → theme's own accent. Otherwise overrides the accent for the theme.
    var accentOverride: HexColor? = nil
    var font: FontChoice = .jakarta
    /// WebKit page zoom; 1.0 = 100%.
    var interfaceScale: Double = 1.0
    /// Multiplier for message text only.
    var messageFontScale: Double = 1.0
    var density: Density = .comfortable
    var roundedBubbles = true
    var bubbleRadius: Double = 14
    /// nil → WhatsApp's own responsive width.
    var sidebarWidth: Double? = nil
    var customCSSEnabled = true
    var livePreview = true
    var tintOutgoingBubbles = true
}

nonisolated struct NotificationSettings: Codable, Equatable, Sendable {
    var enabled = true
    var showPreviews = true
    var sound: NotificationSoundChoice = .system
    var dockBadge = true
    var menuBarBadge = true
    var muted = false
    var muteUntil: Date? = nil
    var suppressWhenWindowFocused = true
    var showDownloadNotifications = true

    var isEffectivelyMuted: Bool {
        if muted { return true }
        if let until = muteUntil, until > Date() { return true }
        return false
    }
}

nonisolated struct AdvancedSettings: Codable, Equatable, Sendable {
    var developerToolsEnabled = false
    var hotReloadScripts = false
    var verboseLogging = false
    var askWhereToSaveDownloads = false
    var revealDownloadsInFinder = false
    var customUserAgentSuffix: String = ""
}

nonisolated struct WindowSettings: Codable, Equatable, Sendable {
    var lastActiveAccountID: UUID? = nil
}

nonisolated struct AllSettings: Codable, Equatable, Sendable {
    var general = GeneralSettings()
    var appearance = AppearanceSettings()
    var notifications = NotificationSettings()
    var advanced = AdvancedSettings()
    var window = WindowSettings()
    var schemaVersion = 1
}

// MARK: - Store

/// Single source of truth for user preferences. Persists as JSON in
/// Application Support with a short debounce so sliders don't thrash the disk.
@MainActor
@Observable
final class SettingsStore {
    var general: GeneralSettings { didSet { if general != oldValue { scheduleSave() } } }
    var appearance: AppearanceSettings { didSet { if appearance != oldValue { scheduleSave() } } }
    var notifications: NotificationSettings { didSet { if notifications != oldValue { scheduleSave() } } }
    var advanced: AdvancedSettings { didSet { if advanced != oldValue { scheduleSave() } } }
    var window: WindowSettings { didSet { if window != oldValue { scheduleSave() } } }

    @ObservationIgnored private let saveDebouncer = Debouncer(delay: .milliseconds(250))
    @ObservationIgnored private let url: URL

    init(url: URL = Paths.settingsFile) {
        self.url = url
        let loaded = Self.load(from: url)
        general = loaded.general
        appearance = loaded.appearance
        notifications = loaded.notifications
        advanced = loaded.advanced
        window = loaded.window
    }

    private static func load(from url: URL) -> AllSettings {
        guard let data = try? Data(contentsOf: url) else { return AllSettings() }
        do { return try JSONDecoder.standard.decode(AllSettings.self, from: data) }
        catch {
            Log.error("Settings file unreadable, using defaults: \(error.localizedDescription)", .settings)
            return AllSettings()
        }
    }

    var snapshot: AllSettings {
        AllSettings(general: general, appearance: appearance, notifications: notifications, advanced: advanced, window: window)
    }

    private func scheduleSave() {
        saveDebouncer.call { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        do {
            let data = try JSONEncoder.pretty.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Failed to save settings: \(error.localizedDescription)", .settings)
        }
    }

    func resetAppearance() {
        appearance = AppearanceSettings()
    }
}

// MARK: - Key code names (for displaying shortcuts)

nonisolated enum KeyCodeNames {
    nonisolated static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: "A"; case 1: "S"; case 2: "D"; case 3: "F"; case 4: "H"; case 5: "G"; case 6: "Z"; case 7: "X"
        case 8: "C"; case 9: "V"; case 11: "B"; case 12: "Q"; case 13: "W"; case 14: "E"; case 15: "R"; case 16: "Y"
        case 17: "T"; case 18: "1"; case 19: "2"; case 20: "3"; case 21: "4"; case 22: "6"; case 23: "5"; case 24: "="
        case 25: "9"; case 26: "7"; case 27: "-"; case 28: "8"; case 29: "0"; case 30: "]"; case 31: "O"; case 32: "U"
        case 33: "["; case 34: "I"; case 35: "P"; case 36: "↩"; case 37: "L"; case 38: "J"; case 39: "'"; case 40: "K"
        case 41: ";"; case 42: "\\"; case 43: ","; case 44: "/"; case 45: "N"; case 46: "M"; case 47: "."; case 48: "⇥"
        case 49: "Space"; case 50: "`"; case 51: "⌫"; case 53: "⎋"; case 96: "F5"; case 97: "F6"; case 98: "F7"
        case 99: "F3"; case 100: "F8"; case 101: "F9"; case 103: "F11"; case 109: "F10"; case 111: "F12"; case 118: "F4"
        case 120: "F2"; case 122: "F1"; case 123: "←"; case 124: "→"; case 125: "↓"; case 126: "↑"
        default: "Key \(keyCode)"
        }
    }
}
