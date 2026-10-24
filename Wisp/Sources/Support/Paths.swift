import Foundation

/// All on-disk locations Wisp owns. Everything lives under Application Support
/// so a user can inspect or back up their customizations.
nonisolated enum Paths {
    nonisolated static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Wisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var settingsFile: URL { applicationSupport.appendingPathComponent("settings.json") }
    nonisolated static var accountsFile: URL { applicationSupport.appendingPathComponent("accounts.json") }
    nonisolated static var customCSSFile: URL { applicationSupport.appendingPathComponent("custom.css") }

    nonisolated static var scriptsDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var avatarsDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    nonisolated static var temporaryDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
