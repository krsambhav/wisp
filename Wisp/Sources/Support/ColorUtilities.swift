import AppKit
import SwiftUI

/// A tiny sRGB color value used by themes. Stored as hex (#RRGGBB or #RRGGBBAA)
/// so theme files stay human-editable and diffable.
nonisolated struct HexColor: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    var r: Double, g: Double, b: Double, a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255; a = 1
        } else {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255; b = Double((v >> 8) & 0xFF) / 255; a = Double(v & 0xFF) / 255
        }
    }

    /// Literal initializer for built-in themes; traps on malformed input at
    /// development time, which is what we want for hard-coded values.
    init(_ hex: String) {
        guard let c = HexColor(hex: hex) else { preconditionFailure("Bad hex color \(hex)") }
        self = c
    }

    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = HexColor(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid color \(s)"))
        }
        self = c
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }

    var hexString: String {
        func h(_ v: Double) -> String { String(format: "%02X", Int((v.clamped01 * 255).rounded())) }
        return a < 1 ? "#\(h(r))\(h(g))\(h(b))\(h(a))" : "#\(h(r))\(h(g))\(h(b))"
    }

    var description: String { hexString }

    /// CSS representation: hex for opaque, rgba() otherwise.
    var css: String {
        a < 1 ? "rgba(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())), \(String(format: "%.3f", a)))" : hexString
    }

    /// "R, G, B" — WhatsApp uses `rgba(var(--token-RGB), alpha)` in places.
    var rgbTriplet: String { "\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded()))" }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(nsColor: nsColor) }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent); a = Double(c.alphaComponent)
    }

    // MARK: HSL manipulation (used to derive accent variants)

    var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        if maxC == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return (h / 6, s, l)
    }

    static func fromHSL(h: Double, s: Double, l: Double, a: Double = 1) -> HexColor {
        func hue2rgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        if s == 0 { return HexColor(r: l, g: l, b: l, a: a) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return HexColor(r: hue2rgb(p, q, h + 1/3), g: hue2rgb(p, q, h), b: hue2rgb(p, q, h - 1/3), a: a)
    }

    func lightness(_ l: Double) -> HexColor { let c = hsl; return .fromHSL(h: c.h, s: c.s, l: l.clamped01, a: a) }
    func adjustedLightness(by delta: Double) -> HexColor { let c = hsl; return .fromHSL(h: c.h, s: c.s, l: (c.l + delta).clamped01, a: a) }
    func withAlpha(_ alpha: Double) -> HexColor { HexColor(r: r, g: g, b: b, a: alpha.clamped01) }
    /// Mix with another color: t = 0 → self, t = 1 → other.
    func mixed(with other: HexColor, t: Double) -> HexColor {
        let t = t.clamped01
        return HexColor(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }
    /// Relative luminance (WCAG).
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    var isDark: Bool { luminance < 0.4 }
}

nonisolated extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
