import Foundation

/// Built-in themes. Values were tuned against WhatsApp Web's own token set
/// (WDS-* and legacy variables) captured in October 2026.
nonisolated enum ThemeCatalog {
    nonisolated static let all: [Theme] = [defaultTheme, minimal, midnight]

    nonisolated static func theme(id: String) -> Theme {
        all.first { $0.id == id } ?? defaultTheme
    }

    // MARK: Default — refined WhatsApp

    nonisolated static let defaultTheme = Theme(
        id: "default",
        name: "Default",
        summary: "WhatsApp's own design, refined: softer surfaces, hairline borders, tidier spacing.",
        light: ThemePalette(
            accent: HexColor("#1DAA61"), accentEmphasized: HexColor("#15603E"), accentDeemphasized: HexColor("#D9FDD3"), onAccent: HexColor("#FFFFFF"),
            background: HexColor("#FFFFFF"), backgroundInset: HexColor("#F7F5F3"),
            surface: HexColor("#FFFFFF"), surfaceEmphasized: HexColor("#F5F3F0"), surfaceElevated: HexColor("#FFFFFF"), surfaceHighlight: HexColor("#0A0A0A0D"),
            textPrimary: HexColor("#0A0A0A"), textSecondary: HexColor("#00000099"), textDisabled: HexColor("#BDBDBD"), link: HexColor("#027EB5"), readReceipt: HexColor("#007BFC"),
            divider: HexColor("#0000001A"), outline: HexColor("#959393"), outlineDeemphasized: HexColor("#00000033"),
            bubbleIncoming: HexColor("#FFFFFF"), bubbleOutgoing: HexColor("#D9FDD3"), bubbleSystem: HexColor("#FFFFFFE6"), bubbleMeta: HexColor("#00000099"),
            chatBackground: HexColor("#F5F1EB"), chatPattern: HexColor("#EAE0D3"), composer: HexColor("#FFFFFF"), tray: HexColor("#F7F5F3"),
            unreadBadge: HexColor("#1DAA61"), unreadBadgeText: HexColor("#FFFFFF"), scrollbar: HexColor("#00000026"), scrollbarHover: HexColor("#00000040"),
            shellBackground: HexColor("#F7F5F3"), shellForeground: HexColor("#0A0A0A"), shellDivider: HexColor("#0000001A")
        ),
        dark: ThemePalette(
            accent: HexColor("#21C063"), accentEmphasized: HexColor("#144D37"), accentDeemphasized: HexColor("#103529"), onAccent: HexColor("#0A0A0A"),
            background: HexColor("#161717"), backgroundInset: HexColor("#0A0A0A"),
            surface: HexColor("#161717"), surfaceEmphasized: HexColor("#1D1F1F"), surfaceElevated: HexColor("#242626"), surfaceHighlight: HexColor("#FFFFFF14"),
            textPrimary: HexColor("#FAFAFA"), textSecondary: HexColor("#FFFFFF99"), textDisabled: HexColor("#757778"), link: HexColor("#53BDEB"), readReceipt: HexColor("#53BDEB"),
            divider: HexColor("#FFFFFF1A"), outline: HexColor("#757778"), outlineDeemphasized: HexColor("#FFFFFF33"),
            bubbleIncoming: HexColor("#242626"), bubbleOutgoing: HexColor("#144D37"), bubbleSystem: HexColor("#1D1F1FE6"), bubbleMeta: HexColor("#FFFFFF99"),
            chatBackground: HexColor("#161717"), chatPattern: HexColor("#1D1F1F"), composer: HexColor("#242626"), tray: HexColor("#1D1F1F"),
            unreadBadge: HexColor("#21C063"), unreadBadgeText: HexColor("#0A0A0A"), scrollbar: HexColor("#FFFFFF26"), scrollbarHover: HexColor("#FFFFFF40"),
            shellBackground: HexColor("#1D1F1F"), shellForeground: HexColor("#FAFAFA"), shellDivider: HexColor("#FFFFFF1A")
        ),
        stylesheet: "default"
    )

    // MARK: Minimal — monochrome, shadcn-inspired

    nonisolated static let minimal = Theme(
        id: "minimal",
        name: "Minimal",
        summary: "A clean, monochromatic interface. Neutral surfaces, 1px borders, accent used only where it matters.",
        light: ThemePalette(
            accent: HexColor("#18181B"), accentEmphasized: HexColor("#09090B"), accentDeemphasized: HexColor("#F4F4F5"), onAccent: HexColor("#FAFAFA"),
            background: HexColor("#FFFFFF"), backgroundInset: HexColor("#FAFAFA"),
            surface: HexColor("#FFFFFF"), surfaceEmphasized: HexColor("#F4F4F5"), surfaceElevated: HexColor("#FFFFFF"), surfaceHighlight: HexColor("#09090B0A"),
            textPrimary: HexColor("#09090B"), textSecondary: HexColor("#71717A"), textDisabled: HexColor("#A1A1AA"), link: HexColor("#2563EB"), readReceipt: HexColor("#2563EB"),
            divider: HexColor("#E4E4E7"), outline: HexColor("#D4D4D8"), outlineDeemphasized: HexColor("#E4E4E7"),
            bubbleIncoming: HexColor("#FFFFFF"), bubbleOutgoing: HexColor("#F4F4F5"), bubbleSystem: HexColor("#FAFAFAE6"), bubbleMeta: HexColor("#71717A"),
            chatBackground: HexColor("#FAFAFA"), chatPattern: HexColor("#FAFAFA"), composer: HexColor("#FFFFFF"), tray: HexColor("#FAFAFA"),
            unreadBadge: HexColor("#18181B"), unreadBadgeText: HexColor("#FAFAFA"), scrollbar: HexColor("#09090B1F"), scrollbarHover: HexColor("#09090B38"),
            shellBackground: HexColor("#FFFFFF"), shellForeground: HexColor("#09090B"), shellDivider: HexColor("#E4E4E7")
        ),
        dark: ThemePalette(
            accent: HexColor("#FAFAFA"), accentEmphasized: HexColor("#E4E4E7"), accentDeemphasized: HexColor("#27272A"), onAccent: HexColor("#09090B"),
            background: HexColor("#09090B"), backgroundInset: HexColor("#09090B"),
            surface: HexColor("#09090B"), surfaceEmphasized: HexColor("#18181B"), surfaceElevated: HexColor("#18181B"), surfaceHighlight: HexColor("#FAFAFA0F"),
            textPrimary: HexColor("#FAFAFA"), textSecondary: HexColor("#A1A1AA"), textDisabled: HexColor("#52525B"), link: HexColor("#60A5FA"), readReceipt: HexColor("#60A5FA"),
            divider: HexColor("#27272A"), outline: HexColor("#3F3F46"), outlineDeemphasized: HexColor("#27272A"),
            bubbleIncoming: HexColor("#18181B"), bubbleOutgoing: HexColor("#27272A"), bubbleSystem: HexColor("#18181BE6"), bubbleMeta: HexColor("#A1A1AA"),
            chatBackground: HexColor("#0C0C0E"), chatPattern: HexColor("#0C0C0E"), composer: HexColor("#18181B"), tray: HexColor("#09090B"),
            unreadBadge: HexColor("#FAFAFA"), unreadBadgeText: HexColor("#09090B"), scrollbar: HexColor("#FAFAFA1F"), scrollbarHover: HexColor("#FAFAFA38"),
            shellBackground: HexColor("#09090B"), shellForeground: HexColor("#FAFAFA"), shellDivider: HexColor("#27272A")
        ),
        stylesheet: "minimal"
    )

    // MARK: Midnight — sophisticated dark

    nonisolated static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        summary: "A deep, layered dark theme with low-contrast dividers and a cool indigo accent.",
        preferredMode: .dark,
        light: ThemePalette( // Used only if WhatsApp is forced into light mode; kept calm and neutral.
            accent: HexColor("#4F46E5"), accentEmphasized: HexColor("#3730A3"), accentDeemphasized: HexColor("#E0E7FF"), onAccent: HexColor("#FFFFFF"),
            background: HexColor("#F8FAFC"), backgroundInset: HexColor("#F1F5F9"),
            surface: HexColor("#FFFFFF"), surfaceEmphasized: HexColor("#F1F5F9"), surfaceElevated: HexColor("#FFFFFF"), surfaceHighlight: HexColor("#0F172A0A"),
            textPrimary: HexColor("#0F172A"), textSecondary: HexColor("#64748B"), textDisabled: HexColor("#94A3B8"), link: HexColor("#4F46E5"), readReceipt: HexColor("#4F46E5"),
            divider: HexColor("#E2E8F0"), outline: HexColor("#CBD5E1"), outlineDeemphasized: HexColor("#E2E8F0"),
            bubbleIncoming: HexColor("#FFFFFF"), bubbleOutgoing: HexColor("#E0E7FF"), bubbleSystem: HexColor("#F8FAFCE6"), bubbleMeta: HexColor("#64748B"),
            chatBackground: HexColor("#F1F5F9"), chatPattern: HexColor("#F1F5F9"), composer: HexColor("#FFFFFF"), tray: HexColor("#F8FAFC"),
            unreadBadge: HexColor("#4F46E5"), unreadBadgeText: HexColor("#FFFFFF"), scrollbar: HexColor("#0F172A1F"), scrollbarHover: HexColor("#0F172A38"),
            shellBackground: HexColor("#F8FAFC"), shellForeground: HexColor("#0F172A"), shellDivider: HexColor("#E2E8F0")
        ),
        dark: ThemePalette(
            accent: HexColor("#818CF8"), accentEmphasized: HexColor("#312E81"), accentDeemphasized: HexColor("#1E1B4B"), onAccent: HexColor("#0B0D14"),
            background: HexColor("#0B0D14"), backgroundInset: HexColor("#07080D"),
            surface: HexColor("#0E1119"), surfaceEmphasized: HexColor("#141826"), surfaceElevated: HexColor("#171B2A"), surfaceHighlight: HexColor("#C7D2FE14"),
            textPrimary: HexColor("#E5E7EB"), textSecondary: HexColor("#8B93A7"), textDisabled: HexColor("#4B5163"), link: HexColor("#A5B4FC"), readReceipt: HexColor("#A5B4FC"),
            divider: HexColor("#FFFFFF12"), outline: HexColor("#2A3042"), outlineDeemphasized: HexColor("#FFFFFF1A"),
            bubbleIncoming: HexColor("#161A27"), bubbleOutgoing: HexColor("#232A4A"), bubbleSystem: HexColor("#141826E6"), bubbleMeta: HexColor("#8B93A7"),
            chatBackground: HexColor("#0B0D14"), chatPattern: HexColor("#0B0D14"), composer: HexColor("#141826"), tray: HexColor("#0E1119"),
            unreadBadge: HexColor("#818CF8"), unreadBadgeText: HexColor("#0B0D14"), scrollbar: HexColor("#C7D2FE1F"), scrollbarHover: HexColor("#C7D2FE38"),
            shellBackground: HexColor("#0B0D14"), shellForeground: HexColor("#E5E7EB"), shellDivider: HexColor("#FFFFFF12")
        ),
        stylesheet: "midnight"
    )
}
