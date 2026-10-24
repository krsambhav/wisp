import AppKit
import SwiftUI

/// shadcn/ui design tokens (zinc palette) for Wisp's native chrome.
/// Light/dark values mirror shadcn's default theme CSS variables.
enum WispUI {
    static let radiusSM: CGFloat = 6     // --radius - 2px
    static let radius: CGFloat = 8       // --radius (0.5rem)
    static let radiusLG: CGFloat = 12

    static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? HexColor(dark).nsColor : HexColor(light).nsColor })
    }

    // shadcn semantic tokens
    static let background        = adaptive("#FFFFFF", "#09090B")
    static let foreground        = adaptive("#09090B", "#FAFAFA")
    static let card              = adaptive("#FFFFFF", "#09090B")
    static let cardElevated      = adaptive("#FFFFFF", "#18181B")   // popover / toast
    static let popover           = adaptive("#FFFFFF", "#09090B")
    static let primary           = adaptive("#18181B", "#FAFAFA")
    static let primaryForeground = adaptive("#FAFAFA", "#18181B")
    static let secondary         = adaptive("#F4F4F5", "#27272A")
    static let secondaryForeground = adaptive("#18181B", "#FAFAFA")
    static let muted             = adaptive("#F4F4F5", "#27272A")
    static let mutedForeground   = adaptive("#71717A", "#A1A1AA")
    static let accent            = adaptive("#F4F4F5", "#27272A")   // hover surface
    static let accentForeground  = adaptive("#18181B", "#FAFAFA")
    static let destructive       = adaptive("#EF4444", "#7F1D1D")
    static let destructiveForeground = Color.white
    static let border            = adaptive("#E4E4E7", "#27272A")
    static let input             = adaptive("#E4E4E7", "#27272A")
    static let ring              = adaptive("#18181B", "#D4D4D8")
    static let sidebar           = adaptive("#FAFAFA", "#18181B")
    static let success           = adaptive("#16A34A", "#22C55E")
    static let warning           = adaptive("#D97706", "#F59E0B")

    // Legacy aliases used across views
    static var hover: Color { accent }
    static var pressed: Color { adaptive("#E4E4E7", "#3F3F46") }
    static var borderStrong: Color { adaptive("#D4D4D8", "#3F3F46") }
    static var muted_: Color { mutedForeground }

    // Typography (shadcn: text-sm 14/20 for body, text-xs 12/16 for descriptions)
    static let title = Font.system(size: 22, weight: .semibold)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13.5)
    static let bodyMedium = Font.system(size: 13.5, weight: .medium)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 12, design: .monospaced)
}
