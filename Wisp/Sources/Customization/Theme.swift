import Foundation

/// One color scheme of a theme. Every value is a plain color so themes can be
/// authored as JSON without knowing anything about WhatsApp's internals; the
/// mapping onto WhatsApp's design tokens lives in `CSSGenerator`.
nonisolated struct ThemePalette: Codable, Equatable, Sendable {
    var accent: HexColor
    var accentEmphasized: HexColor
    var accentDeemphasized: HexColor
    var onAccent: HexColor

    var background: HexColor          // app wash behind panes
    var backgroundInset: HexColor
    var surface: HexColor             // sidebar / list
    var surfaceEmphasized: HexColor   // headers, selected rows
    var surfaceElevated: HexColor     // menus, popovers
    var surfaceHighlight: HexColor    // hover

    var textPrimary: HexColor
    var textSecondary: HexColor
    var textDisabled: HexColor
    var link: HexColor
    var readReceipt: HexColor

    var divider: HexColor
    var outline: HexColor
    var outlineDeemphasized: HexColor

    var bubbleIncoming: HexColor
    var bubbleOutgoing: HexColor
    var bubbleSystem: HexColor
    var bubbleMeta: HexColor

    var chatBackground: HexColor
    var chatPattern: HexColor
    var composer: HexColor
    var tray: HexColor

    var unreadBadge: HexColor
    var unreadBadgeText: HexColor
    var scrollbar: HexColor
    var scrollbarHover: HexColor

    /// Native shell (header bar) colors so the SwiftUI chrome matches the page.
    var shellBackground: HexColor
    var shellForeground: HexColor
    var shellDivider: HexColor
}

nonisolated struct Theme: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
    var author: String = "Wisp"
    var isBuiltIn: Bool = true
    /// nil → follow the user's appearance mode; otherwise the theme prefers one scheme.
    var preferredMode: AppearanceMode? = nil
    var light: ThemePalette
    var dark: ThemePalette
    /// Name of the bundled stylesheet in Resources/Web/themes (without extension).
    var stylesheet: String
    /// Selectors the theme's stylesheet relies on; checked once after login.
    var healthSelectors: [String] = ["#app", "#side", "#main", "#pane-side", ".message-in", ".message-out"]

    func palette(for dark: Bool) -> ThemePalette { dark ? self.dark : light }
}
