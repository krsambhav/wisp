import Foundation
import Security

// WispUpdateHelper — tiny XPC service, deliberately NOT sandboxed.
//
// The app sandbox quarantines every file the app writes and forbids removing
// that flag, so an update the app installed itself would be stopped by
// Gatekeeper on relaunch. launchd starts this service outside the sandbox; it
// re-verifies the staged bundle, clears quarantine, swaps it into place and
// reopens the app after the old process exits.

nonisolated struct HelperError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

nonisolated enum Installer {
    static var teamID: String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let code = selfCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code as! SecStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func verify(_ url: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            throw HelperError("unreadable code object")
        }
        var requirement: SecRequirement?
        if let team = teamID {
            let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
            guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess else { throw HelperError("bad requirement") }
        }
        var cfError: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), requirement, &cfError)
        guard status == errSecSuccess else {
            throw HelperError("signature check failed: " + ((cfError?.takeRetainedValue()).map { String(describing: $0) } ?? "OSStatus \(status)"))
        }
    }

    static func stripQuarantine(_ root: URL) {
        var paths = [root.path]
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: []) {
            for case let u as URL in e { paths.append(u.path) }
        }
        for p in paths { removexattr(p, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }

    static func swap(_ staged: URL, into target: URL) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        let old = parent.appendingPathComponent(".Wisp-old-\(getpid()).app")
        if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: old) }
        do { try fm.moveItem(at: staged, to: target) }
        catch {
            if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: target) }
            throw error
        }
        try? fm.removeItem(at: old)
    }

    /// `/bin/sh` in its own session (POSIX_SPAWN_SETSID) so it outlives this
    /// service. Waits for the old app to exit, then opens the new bundle.
    /// Gives up after two minutes if the app decided not to quit.
    static func spawnRelauncher(target: URL, afterPID pid: Int32) throws {
        let quoted = target.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "i=0; while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; i=$((i+1)); [ $i -gt 600 ] && exit 0; done; /usr/bin/open '\(quoted)'"
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/sh", "-c", script].map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, "/bin/sh", nil, &attr, argv, environ)
        guard rc == 0 else { throw HelperError("relaunch helper failed (errno \(rc))") }
    }
}

final class Service: NSObject, WispUpdateHelperProtocol, @unchecked Sendable {
    func install(staged: String, target: String, relaunchAfterPID parentPID: Int32, reply: @escaping @Sendable (String?) -> Void) {
        let stagedURL = URL(fileURLWithPath: staged).standardizedFileURL
        let targetURL = URL(fileURLWithPath: target).standardizedFileURL
        do {
            guard stagedURL.pathExtension == "app", targetURL.pathExtension == "app" else { throw HelperError("not app bundles") }
            guard Bundle(url: stagedURL)?.bundleIdentifier == "app.wisp.desktop" else { throw HelperError("staged bundle is not Wisp") }
            try Installer.verify(stagedURL)
            Installer.stripQuarantine(stagedURL)
            try Installer.swap(stagedURL, into: targetURL)
            Installer.stripQuarantine(targetURL)
            if parentPID > 0 { try Installer.spawnRelauncher(target: targetURL, afterPID: parentPID) }
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func processUsage(coalition: UInt64, reply: @escaping @Sendable (Data?) -> Void) {
        reply(try? JSONEncoder().encode(ProcessTable.members(ofCoalition: coalition)))
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only code signed by our team may drive the installer.
        if let team = Installer.teamID {
            do { try connection.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"") }
            catch { return false }
        }
        connection.exportedInterface = NSXPCInterface(with: WispUpdateHelperProtocol.self)
        connection.exportedObject = Service()
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
