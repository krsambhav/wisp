import Foundation
import JavaScriptCore

nonisolated enum ScriptInjectionTime: String, Codable, CaseIterable, Sendable, Identifiable {
    case documentStart = "document-start"
    case documentEnd = "document-end"
    var id: String { rawValue }
    var label: String { self == .documentStart ? "Document start" : "Document end" }
}

nonisolated enum ScriptWorld: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Runs in a separate JavaScript world: sees the DOM, not WhatsApp's JS objects.
    case isolated
    /// Runs alongside WhatsApp's own code. Required to patch `window`, intercept
    /// fetch, etc. Riskier — a bug can break the page.
    case page
    var id: String { rawValue }
    var label: String { self == .isolated ? "Isolated (recommended)" : "Page context" }
}

/// A user script. Stored on disk as `<id>.js` with a userscript-style header so
/// scripts remain readable and portable outside Wisp.
nonisolated struct CustomScript: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var enabled: Bool
    var injectionTime: ScriptInjectionTime
    var world: ScriptWorld
    var source: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, summary: String = "", enabled: Bool = true,
         injectionTime: ScriptInjectionTime = .documentEnd, world: ScriptWorld = .isolated,
         source: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.summary = summary; self.enabled = enabled
        self.injectionTime = injectionTime; self.world = world; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    var fileName: String { "\(id.uuidString).js" }

    // MARK: Header (de)serialization

    nonisolated static let headerStart = "// ==WispScript=="
    nonisolated static let headerEnd = "// ==/WispScript=="

    /// Full file contents, header included.
    var fileContents: String {
        """
        \(Self.headerStart)
        // @name        \(name.replacingOccurrences(of: "\n", with: " "))
        // @description \(summary.replacingOccurrences(of: "\n", with: " "))
        // @run-at      \(injectionTime.rawValue)
        // @world       \(world.rawValue)
        // @enabled     \(enabled)
        \(Self.headerEnd)
        \(source)
        """
    }

    /// Parses a file written by `fileContents` (or a hand-written one). Files
    /// without a header are accepted with defaults so users can drop plain .js
    /// files into the Scripts folder.
    nonisolated static func parse(fileContents: String, id: UUID, fallbackName: String, dates: (Date, Date)) -> CustomScript {
        var name = fallbackName, summary = "", enabled = true
        var runAt: ScriptInjectionTime = .documentEnd, world: ScriptWorld = .isolated
        var body = fileContents
        if let startRange = fileContents.range(of: headerStart), let endRange = fileContents.range(of: headerEnd), startRange.upperBound <= endRange.lowerBound {
            let header = fileContents[startRange.upperBound..<endRange.lowerBound]
            for line in header.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("//") else { continue }
                let rest = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
                guard rest.hasPrefix("@") else { continue }
                let parts = rest.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { continue }
                let key = parts[0].lowercased(), value = parts[1].trimmingCharacters(in: .whitespaces)
                switch key {
                case "name": name = value
                case "description": summary = value
                case "run-at": runAt = ScriptInjectionTime(rawValue: value) ?? runAt
                case "world": world = ScriptWorld(rawValue: value) ?? world
                case "enabled": enabled = (value as NSString).boolValue
                default: break
                }
            }
            body = String(fileContents[endRange.upperBound...])
            if body.hasPrefix("\n") { body.removeFirst() }
        }
        return CustomScript(id: id, name: name, summary: summary, enabled: enabled, injectionTime: runAt, world: world, source: body, createdAt: dates.0, updatedAt: dates.1)
    }

    // MARK: Syntax check

    struct SyntaxError: Equatable, Sendable { let message: String; let line: Int?; let column: Int? }

    /// Compiles (never runs) the source in a throwaway JavaScriptCore context.
    nonisolated static func checkSyntax(_ source: String) -> SyntaxError? {
        guard let ctx = JSContext() else { return nil }
        var found: SyntaxError? = nil
        ctx.exceptionHandler = { _, exc in
            guard let exc else { return }
            let msg = exc.toString() ?? "Syntax error"
            let line = exc.objectForKeyedSubscript("line")?.toInt32()
            let col = exc.objectForKeyedSubscript("column")?.toInt32()
            found = SyntaxError(message: msg, line: line.map { Int($0) }, column: col.map { Int($0) })
        }
        // `new Function` parses the body without executing it.
        ctx.setObject(source, forKeyedSubscript: "__src" as NSString)
        ctx.evaluateScript("try { new Function(__src); } catch (e) { throw e; }")
        return found
    }

    nonisolated static func template(named name: String) -> String {
        """
        // \(name)
        // Runs inside WhatsApp Web. Use wisp.log(...) to write to Settings › Scripts › Logs.
        // In the isolated world you can read and style the DOM but not WhatsApp's JS.

        wisp.log('Hello from \(name)');

        // Example: add a subtle hover lift to message bubbles
        // const style = document.createElement('style');
        // style.textContent = '.message-in > div:first-child:hover { transform: translateY(-1px); }';
        // document.head.appendChild(style);
        """
    }
}
