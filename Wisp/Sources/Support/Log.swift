import Foundation
import os

/// Log categories map 1:1 to subsystems so Console.app filtering is useful.
nonisolated enum LogCategory: String, CaseIterable, Sendable {
    case app, window, web, injection, scripts, notifications, accounts, downloads, performance, settings
}

nonisolated enum LogLevel: Int, Codable, Sendable, Comparable, CaseIterable, Identifiable {
    var id: Int { rawValue }
    case debug = 0, info, warning, error
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
    var label: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        }
    }
}

nonisolated struct LogEntry: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let category: String
    let message: String
}

/// In-memory ring buffer surfaced in Settings › Advanced › Diagnostics and
/// Settings › Scripts › Logs. Never contains message content or credentials:
/// callers are responsible for logging *events*, not *payloads*.
@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private(set) var entries: [LogEntry] = []
    var minimumLevel: LogLevel = .info
    let capacity = 2000

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    func clear() { entries.removeAll() }

    func export() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out = "Wisp diagnostics export — \(f.string(from: Date()))\n"
        out += "App \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))\n"
        out += "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
        for e in entries {
            out += "\(f.string(from: e.date)) [\(e.level.label)] [\(e.category)] \(e.message)\n"
        }
        return out
    }
}

/// Structured logging facade. Writes to the unified log and mirrors into the
/// diagnostics buffer on the main actor.
nonisolated enum Log {
    nonisolated private static let subsystem = "app.wisp.desktop"
    nonisolated private static let loggers: [LogCategory: Logger] = {
        var dict: [LogCategory: Logger] = [:]
        for c in LogCategory.allCases { dict[c] = Logger(subsystem: subsystem, category: c.rawValue) }
        return dict
    }()

    nonisolated static func debug(_ message: String, _ category: LogCategory = .app) { emit(.debug, message, category.rawValue) }
    nonisolated static func info(_ message: String, _ category: LogCategory = .app) { emit(.info, message, category.rawValue) }
    nonisolated static func warning(_ message: String, _ category: LogCategory = .app) { emit(.warning, message, category.rawValue) }
    nonisolated static func error(_ message: String, _ category: LogCategory = .app) { emit(.error, message, category.rawValue) }

    /// Entry point for messages originating from injected scripts. `source` is
    /// the script name; it is prefixed so it is easy to filter.
    nonisolated static func script(_ level: LogLevel, source: String, message: String) {
        emit(level, message, "script:\(source)")
    }

    nonisolated private static func emit(_ level: LogLevel, _ message: String, _ category: String) {
        if let cat = LogCategory(rawValue: category), let logger = loggers[cat] {
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .warning: logger.warning("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
        } else {
            let logger = Logger(subsystem: subsystem, category: "scripts")
            logger.log(level: level == .error ? .error : .info, "[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        #if DEBUG
        FileHandle.standardError.write(Data("[\(level.label)] [\(category)] \(message)\n".utf8))
        #endif
        let entry = LogEntry(id: UUID(), date: Date(), level: level, category: category, message: message)
        Task { @MainActor in
            if entry.level >= DiagnosticsLog.shared.minimumLevel { DiagnosticsLog.shared.append(entry) }
        }
    }
}
