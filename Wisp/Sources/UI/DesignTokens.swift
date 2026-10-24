import AppKit
import SwiftUI

/// Native design tokens for Wisp's own chrome (header, settings, overlays).
/// shadcn/ui-inspired: neutral surfaces, 1px borders, 8–12pt radii, restrained shadows.
enum WispUI {
    static let radiusSM: CGFloat = 6
    static let radius: CGFloat = 8
    static let radiusLG: CGFloat = 12

    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
    }

    static let background = adaptive(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(red: 0.075, green: 0.078, blue: 0.086, alpha: 1))
    static let sidebar = adaptive(light: NSColor(white: 0.965, alpha: 1), dark: NSColor(red: 0.06, green: 0.063, blue: 0.07, alpha: 1))
    static let card = adaptive(light: .white, dark: NSColor(red: 0.105, green: 0.11, blue: 0.12, alpha: 1))
    static let cardElevated = adaptive(light: .white, dark: NSColor(red: 0.13, green: 0.135, blue: 0.145, alpha: 1))
    static let border = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.09))
    static let borderStrong = adaptive(light: NSColor(white: 0, alpha: 0.16), dark: NSColor(white: 1, alpha: 0.16))
    static let hover = adaptive(light: NSColor(white: 0, alpha: 0.045), dark: NSColor(white: 1, alpha: 0.06))
    static let pressed = adaptive(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.1))
    static let foreground = adaptive(light: NSColor(white: 0.05, alpha: 1), dark: NSColor(white: 0.97, alpha: 1))
    static let muted = adaptive(light: NSColor(white: 0.42, alpha: 1), dark: NSColor(white: 0.62, alpha: 1))
    static let primary = adaptive(light: NSColor(white: 0.09, alpha: 1), dark: NSColor(white: 0.98, alpha: 1))
    static let primaryForeground = adaptive(light: .white, dark: NSColor(white: 0.05, alpha: 1))
    static let destructive = Color(nsColor: NSColor(red: 0.86, green: 0.2, blue: 0.22, alpha: 1))
    static let success = Color(nsColor: NSColor(red: 0.13, green: 0.66, blue: 0.38, alpha: 1))
    static let warning = Color(nsColor: NSColor(red: 0.88, green: 0.6, blue: 0.1, alpha: 1))

    static let title = Font.system(size: 20, weight: .semibold)
    static let heading = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11.5)
    static let mono = Font.system(size: 12, design: .monospaced)
}
