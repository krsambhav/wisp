import AppKit
import Foundation

nonisolated extension String {
    /// Truncates for logging / UI without ever throwing.
    func prefixed(_ n: Int) -> String { count > n ? String(prefix(n)) + "…" : self }

    /// Escapes a string so it can be embedded in a JavaScript single-quoted literal.
    var jsStringLiteral: String {
        var out = "'"
        for ch in unicodeScalars {
            switch ch {
            case "'": out += "\\'"
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "'"
    }
}

nonisolated extension JSONEncoder {
    nonisolated static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

nonisolated extension JSONDecoder {
    nonisolated static var standard: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

nonisolated extension FileManager {
    /// Returns a URL in `directory` that does not collide with an existing file,
    /// appending " 2", " 3", … before the extension.
    nonisolated func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let sanitized = preferredName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var candidate = directory.appendingPathComponent(sanitized)
        var i = 2
        while fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = directory.appendingPathComponent(name)
            i += 1
        }
        return candidate
    }
}

extension NSApplication {
    /// Brings the app forward regardless of which Space the window is on.
    func activateFrontmost() {
        if #available(macOS 14.0, *) { activate() } else { activate(ignoringOtherApps: true) }
    }
}
