import Foundation

/// Translates a `Theme` + `AppearanceSettings` into the CSS that is injected
/// into WhatsApp Web. Output is split into layers so each can be live-updated
/// independently:
///   tokens  — custom properties (ours + overrides of WhatsApp's own tokens)
///   theme   — base.css + the theme's stylesheet (bundled, versioned)
///   density — html attribute switches are set via JS; nothing here
///   user    — the user's custom CSS, untouched
nonisolated enum CSSGenerator {
    /// All WhatsApp tokens we override, expressed in terms of our `--wisp-*` set.
    /// `!important` is required: WhatsApp defines these on `html` via hashed
    /// classes with (0,3,0) specificity. Importance on custom properties is
    /// honored by the cascade, and inheritance then carries the value down.
    nonisolated static func tokensCSS(theme: Theme, appearance: AppearanceSettings) -> String {
        let light = resolved(theme.light, appearance: appearance)
        let dark = resolved(theme.dark, appearance: appearance)

        var out = "/* Wisp tokens — generated; theme \(theme.id) */\n"
        out += "html { color-scheme: light dark; }\n"
        out += "html {\n" + wispVariables(light) + waOverrides(light, isDark: false) + "}\n"
        out += "html[data-wisp-scheme=\"dark\"], html.dark, body.dark, html[data-theme=\"dark\"] {\n" + wispVariables(dark) + waOverrides(dark, isDark: true) + "}\n"

        // Fonts: bundled web font (data: URIs are allowed by WhatsApp's font-src CSP)
        if appearance.font.isBundledWebFont { out += fontFaceCSS }
        out += "html { --font-family-default: var(--wisp-font-family) !important; --font-family-apple: var(--wisp-font-family) !important; --font-family-segoe: var(--wisp-font-family) !important; }\n"
        out += "#app, #app *:not(code):not(pre):not([class*=\"emoji\"]) { font-family: var(--wisp-font-family) !important; }\n"

        // Non-color knobs
        out += "html {\n"
        out += "  --wisp-font-family: \(appearance.font.cssFamily);\n"
        out += "  --wisp-message-font-scale: \(fmt(appearance.messageFontScale));\n"
        out += "  --wisp-bubble-radius: \(fmt(appearance.bubbleRadius))px;\n"
        if let w = appearance.sidebarWidth { out += "  --wisp-sidebar-width: \(Int(w))px;\n" }
        out += "}\n"
        return out
    }

    /// @font-face rules for the bundled Plus Jakarta Sans (OFL) as data URIs. Cached.
    nonisolated static let fontFaceCSS: String = {
        func face(_ file: String, style: String) -> String {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") ?? Bundle.main.url(forResource: file, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { Log.warning("Font \(file).ttf missing from bundle", .injection); return "" }
            return "@font-face { font-family: \"Plus Jakarta Sans\"; font-style: \(style); font-weight: 200 800; font-display: swap; src: url(data:font/ttf;base64,\(data.base64EncodedString())) format(\"truetype\"); }\n"
        }
        return face("PlusJakartaSans-Variable", style: "normal") + face("PlusJakartaSans-Italic-Variable", style: "italic")
    }()

    /// Applies the user's accent override to a palette by re-deriving accent variants.
    nonisolated static func resolved(_ p: ThemePalette, appearance: AppearanceSettings) -> ThemePalette {
        guard let accent = appearance.accentOverride else {
            var copy = p
            if !appearance.tintOutgoingBubbles { copy.bubbleOutgoing = p.surfaceEmphasized }
            return copy
        }
        var copy = p
        let dark = p.background.isDark
        copy.accent = accent
        copy.accentEmphasized = accent.adjustedLightness(by: dark ? -0.28 : -0.22)
        copy.accentDeemphasized = dark ? accent.lightness(0.16) : accent.lightness(0.93)
        copy.onAccent = accent.luminance > 0.5 ? HexColor("#0A0A0A") : HexColor("#FFFFFF")
        copy.unreadBadge = accent
        copy.unreadBadgeText = copy.onAccent
        copy.readReceipt = accent
        if appearance.tintOutgoingBubbles {
            copy.bubbleOutgoing = dark ? accent.lightness(0.2).mixed(with: p.surface, t: 0.35) : accent.lightness(0.92)
        } else {
            copy.bubbleOutgoing = p.surfaceEmphasized
        }
        return copy
    }

    nonisolated private static func wispVariables(_ p: ThemePalette) -> String {
        """
          --wisp-accent: \(p.accent.css);
          --wisp-accent-emphasized: \(p.accentEmphasized.css);
          --wisp-accent-deemphasized: \(p.accentDeemphasized.css);
          --wisp-on-accent: \(p.onAccent.css);
          --wisp-background: \(p.background.css);
          --wisp-background-inset: \(p.backgroundInset.css);
          --wisp-surface: \(p.surface.css);
          --wisp-surface-emphasized: \(p.surfaceEmphasized.css);
          --wisp-surface-elevated: \(p.surfaceElevated.css);
          --wisp-surface-highlight: \(p.surfaceHighlight.css);
          --wisp-text-primary: \(p.textPrimary.css);
          --wisp-text-secondary: \(p.textSecondary.css);
          --wisp-text-disabled: \(p.textDisabled.css);
          --wisp-link: \(p.link.css);
          --wisp-divider: \(p.divider.css);
          --wisp-outline: \(p.outline.css);
          --wisp-bubble-incoming: \(p.bubbleIncoming.css);
          --wisp-bubble-outgoing: \(p.bubbleOutgoing.css);
          --wisp-bubble-incoming-rgb: \(p.bubbleIncoming.rgbTriplet);
          --wisp-bubble-outgoing-rgb: \(p.bubbleOutgoing.rgbTriplet);
          --wisp-chat-background: \(p.chatBackground.css);
          --wisp-composer: \(p.composer.css);
          --wisp-unread-badge: \(p.unreadBadge.css);
          --wisp-unread-badge-text: \(p.unreadBadgeText.css);
          --wisp-scrollbar: \(p.scrollbar.css);
          --wisp-scrollbar-hover: \(p.scrollbarHover.css);

        """
    }

    /// Mapping onto WhatsApp's tokens. Two generations coexist in WhatsApp's
    /// CSS (WDS-* and the older flat names); both are overridden so the theme
    /// holds up whichever code path a given component uses.
    nonisolated private static func waOverrides(_ p: ThemePalette, isDark: Bool) -> String {
        func t(_ name: String, _ c: HexColor) -> String { "  --\(name): \(c.css) !important;\n" }
        func rgb(_ name: String, _ c: HexColor) -> String { "  --\(name): \(c.rgbTriplet) !important;\n" }
        var s = ""
        // WDS generation
        s += t("WDS-accent", p.accent) + rgb("WDS-accent-RGB", p.accent)
        s += t("WDS-accent-emphasized", p.accentEmphasized) + rgb("WDS-accent-emphasized-RGB", p.accentEmphasized)
        s += t("WDS-accent-deemphasized", p.accentDeemphasized) + rgb("WDS-accent-deemphasized-RGB", p.accentDeemphasized)
        s += t("WDS-content-on-accent", p.onAccent)
        s += t("WDS-background-wash-plain", p.background) + rgb("WDS-background-wash-plain-RGB", p.background)
        s += t("WDS-background-wash-inset", p.backgroundInset) + rgb("WDS-background-wash-inset-RGB", p.backgroundInset)
        s += t("WDS-surface-default", p.surface) + rgb("WDS-surface-default-RGB", p.surface)
        s += t("WDS-surface-emphasized", p.surfaceEmphasized) + rgb("WDS-surface-emphasized-RGB", p.surfaceEmphasized)
        s += t("WDS-surface-elevated-default", p.surfaceElevated) + rgb("WDS-surface-elevated-default-RGB", p.surfaceElevated)
        s += t("WDS-surface-elevated-emphasized", p.surfaceEmphasized)
        s += t("WDS-surface-highlight", p.surfaceHighlight)
        s += t("WDS-content-default", p.textPrimary) + rgb("WDS-content-default-RGB", p.textPrimary)
        s += t("WDS-content-deemphasized", p.textSecondary) + rgb("WDS-content-deemphasized-RGB", p.textSecondary)
        s += t("WDS-content-disabled", p.textDisabled)
        s += t("WDS-content-action-default", p.textPrimary)
        s += t("WDS-content-action-emphasized", p.accent)
        s += t("WDS-content-read", p.readReceipt)
        s += t("WDS-lines-divider", p.divider) + rgb("WDS-lines-divider-RGB", p.divider)
        s += t("WDS-lines-outline-default", p.outline)
        s += t("WDS-lines-outline-deemphasized", p.outlineDeemphasized)
        s += t("WDS-systems-bubble-surface-incoming", p.bubbleIncoming) + rgb("WDS-systems-bubble-surface-incoming-RGB", p.bubbleIncoming)
        s += t("WDS-systems-bubble-surface-outgoing", p.bubbleOutgoing) + rgb("WDS-systems-bubble-surface-outgoing-RGB", p.bubbleOutgoing)
        s += t("WDS-systems-bubble-surface-system", p.bubbleSystem)
        s += t("WDS-systems-bubble-content-deemphasized", p.bubbleMeta)
        s += t("WDS-systems-chat-background-wallpaper", p.chatBackground)
        s += t("WDS-systems-chat-foreground-wallpaper", p.chatPattern)
        s += t("WDS-systems-chat-surface-composer", p.composer)
        s += t("WDS-systems-chat-surface-tray", p.tray)
        // Legacy generation (still referenced by many components)
        s += t("app-background", p.background)
        s += t("app-background-deeper", p.backgroundInset)
        s += t("navbar-background", p.surfaceEmphasized)
        s += t("panel-background", p.surface) + rgb("panel-background-rgb", p.surface)
        s += t("panel-background-deep", p.surfaceEmphasized)
        s += t("panel-input-background", p.surfaceEmphasized)
        s += t("panel-header-background", p.surfaceEmphasized)
        s += t("panel-background-colored", p.surfaceEmphasized)
        s += rgb("background-default-rgb", p.surface)
        s += rgb("background-default-hover-rgb", p.surfaceEmphasized)
        s += t("conversation-panel-background", p.chatBackground)
        s += t("compose-input-background", p.composer)
        s += t("rich-text-panel-background", p.composer)
        s += t("search-input-background", p.surfaceEmphasized)
        s += t("drawer-background", p.surface)
        s += t("drawer-background-deep", p.surfaceEmphasized)
        s += t("picker-background", p.surfaceElevated)
        s += t("modal-backdrop-solid", p.surface)
        s += t("empty-state-background", p.surfaceEmphasized)
        s += t("border-deeper", p.divider)
        s += t("border-list", p.divider)
        s += t("border-default", p.divider)
        s += t("border-stronger", p.outline)
        s += t("chat-border", p.divider)
        s += rgb("primary-rgb", p.textPrimary) + rgb("primary-strong-rgb", p.textPrimary) + rgb("primary-stronger-rgb", p.textPrimary)
        s += rgb("secondary-rgb", p.textSecondary) + t("text-muted", p.textSecondary) + t("primary-muted", p.textSecondary)
        s += t("text-primary-strong", p.textPrimary)
        s += t("text-action", p.accent) + t("icon-primary", p.accent) + t("icon-high-emphasis", p.accent)
        s += t("link-alt", p.accent) + rgb("link-rgb", p.link)
        s += t("incoming-background", p.bubbleIncoming) + t("outgoing-background", p.bubbleOutgoing)
        s += t("incoming-background-deeper", p.bubbleIncoming.adjustedLightness(by: isDark ? 0.04 : -0.04))
        s += t("outgoing-background-deeper", p.bubbleOutgoing.adjustedLightness(by: isDark ? 0.04 : -0.04))
        s += t("unread-marker-background", p.unreadBadge) + t("unread-marker-text", p.unreadBadgeText)
        s += t("badge-pending", p.accent) + t("status-ring-unread", p.accent)
        s += t("chip-button-background", p.accentDeemphasized) + t("chip-button-foreground", p.accentEmphasized)
        s += t("avatar-background", p.surfaceEmphasized)
        s += t("button-round-background-inverted", p.surfaceEmphasized)
        s += t("compose-panel-background-hover", p.surfaceHighlight)
        s += t("teal", p.accent) + t("teal-light", p.accent) + rgb("teal-rgb", p.accent)
        s += t("green", p.accent) + rgb("green-rgb", p.accent) + t("green-deep", p.accentEmphasized)
        return s
    }

    /// Loads base.css + the theme's stylesheet from the bundle.
    /// Debug-only override: load theme stylesheets from a directory on disk (hot reload).
    nonisolated(unsafe) static var themeDirectoryOverride: URL?

    nonisolated static func themeCSS(theme: Theme, bundle: Bundle = .main) -> String {
        func load(_ name: String) -> String {
            if let dir = themeDirectoryOverride, let s = try? String(contentsOf: dir.appendingPathComponent("\(name).css"), encoding: .utf8) { return s }
            guard let url = bundle.url(forResource: name, withExtension: "css") ?? bundle.url(forResource: name, withExtension: "css", subdirectory: "themes"),
                  let s = try? String(contentsOf: url, encoding: .utf8) else {
                Log.warning("Stylesheet \(name).css not found in bundle", .injection)
                return ""
            }
            return s
        }
        return load("base") + "\n" + load(theme.stylesheet)
    }

    /// JavaScript that sets the `data-wisp-*` switches on <html>.
    nonisolated static func attributesJS(appearance: AppearanceSettings) -> String {
        """
        (function(){ var h=document.documentElement; if(!h) return;
          h.setAttribute('data-wisp-density', \(appearance.density.rawValue.jsStringLiteral));
          h.setAttribute('data-wisp-bubbles', \((appearance.roundedBubbles ? "rounded" : "default").jsStringLiteral));
          h.setAttribute('data-wisp-copy-button', \(appearance.copyButtonEnabled ? "'1'" : "'0'"));
          h.setAttribute('data-wisp-download-button', \(appearance.downloadButtonEnabled ? "'1'" : "'0'"));
          h.setAttribute('data-wisp-copyfile-button', \(appearance.copyFileButtonEnabled ? "'1'" : "'0'"));
          h.setAttribute('data-wisp-msginfo-popover', \(appearance.messageInfoPopoverEnabled ? "'1'" : "'0'"));
          \(appearance.sidebarWidth != nil ? "h.setAttribute('data-wisp-sidebar','1');" : "h.removeAttribute('data-wisp-sidebar');")
        })();
        """
    }

    /// Cheap sanity check for user CSS: unbalanced braces are the one mistake
    /// that silently wipes every rule after it.
    nonisolated static func validate(css: String) -> String? {
        var depth = 0
        var inString: Character? = nil
        var escaped = false
        var inComment = false
        var commentLength = 0
        var prev: Character = " "
        for ch in css {
            if inComment {
                commentLength += 1
                if prev == "*" && ch == "/" && commentLength > 1 { inComment = false }
                prev = ch; continue
            }
            if let q = inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == q || ch == "\n" { inString = nil }
                prev = ch; continue
            }
            switch ch {
            case "\"", "'": inString = ch; escaped = false
            case "*" where prev == "/": inComment = true; commentLength = 0
            case "{": depth += 1
            case "}": depth -= 1; if depth < 0 { return "Unexpected “}” — more closing than opening braces." }
            default: break
            }
            prev = ch
        }
        if inComment { return "Unterminated comment (/* … */)." }
        if depth > 0 { return "Missing \(depth) closing brace\(depth == 1 ? "" : "s") “}”." }
        return nil
    }

    nonisolated private static func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.3g", d)
    }
}
