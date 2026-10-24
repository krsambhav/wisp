import Foundation

/// WhatsApp Web gates features on the browser it detects. WKWebView's default
/// UA lacks the `Version/x Safari/x` suffix, which WhatsApp treats as an
/// unknown browser. Appending the suffix makes the UA identical to Safari's
/// on this macOS version — which is what WKWebView actually is.
nonisolated enum UserAgent {
    /// e.g. "Version/26.0 Safari/605.1.15"
    nonisolated static func applicationNameSuffix(extra: String = "") -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let safariMajor: Int
        switch v.majorVersion {
        case ..<14: safariMajor = 17
        case 14: safariMajor = 17
        case 15: safariMajor = 18
        default: safariMajor = v.majorVersion // macOS 26 → Safari 26, and so on
        }
        let minor = v.majorVersion >= 26 ? v.minorVersion : (v.majorVersion == 15 ? min(v.minorVersion, 6) : 6)
        var s = "Version/\(safariMajor).\(minor) Safari/605.1.15"
        let trimmed = extra.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { s += " " + trimmed }
        return s
    }
}
