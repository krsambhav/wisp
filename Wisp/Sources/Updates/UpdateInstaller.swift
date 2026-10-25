import AppKit
import Foundation
import Security

/// GitHub Releases feed: `GET /repos/{owner}/{repo}/releases/latest`.
/// Drafts and pre-releases are excluded by GitHub; the asset is the first
/// `.zip` whose name starts with "Wisp".
nonisolated enum UpdateFeed {
    private struct GHRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let size: Int64 }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    static func latestRelease(repository: String) async throws -> UpdateManager.Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Wisp/\(UpdateManager.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200: break
        case 404: return nil   // no releases yet
        case 403, 429: throw URLError(.userAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "GitHub is rate-limiting update checks; try again in a while."])
        default: throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http?.statusCode ?? 0)."])
        }
        let gh = try JSONDecoder().decode(GHRelease.self, from: data)
        guard let asset = gh.assets.first(where: { $0.name.hasSuffix(".zip") && $0.name.lowercased().hasPrefix("wisp") }) else {
            throw UpdateError.noAsset
        }
        let version = gh.tag_name.hasPrefix("v") ? String(gh.tag_name.dropFirst()) : gh.tag_name
        return .init(version: version, tag: gh.tag_name, notes: gh.body ?? "", pageURL: gh.html_url, assetURL: asset.browser_download_url, assetSize: asset.size)
    }
}

/// Download, verify and swap. Everything runs inside the app sandbox: the
/// archive is extracted in the container's temp dir with `ditto`, the bundle
/// swap needs write access to the app's parent folder (granted by the
/// `/Applications` temporary-exception entitlements or a one-time folder pick).
nonisolated enum UpdateInstaller {
    // MARK: Download

    static func downloadAndStage(_ release: UpdateManager.Release) async throws -> URL {
        let fm = FileManager.default
        let stage = Paths.temporaryDirectory.appendingPathComponent("Update-\(release.version)", isDirectory: true)
        try? fm.removeItem(at: stage)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)

        var req = URLRequest(url: release.assetURL)
        req.setValue("Wisp/\(UpdateManager.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120
        let (tmp, response) = try await URLSession.shared.download(for: req)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."])
        }
        let zip = stage.appendingPathComponent("Wisp.zip")
        try fm.moveItem(at: tmp, to: zip)
        Log.info("Downloaded \(release.assetURL.lastPathComponent) (\(try fm.attributesOfItem(atPath: zip.path)[.size] ?? 0) bytes)", .updates)

        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path])
        guard let app = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.badArchive
        }
        removeQuarantine(at: app)
        return app
    }

    // MARK: Verify

    /// The downloaded bundle must carry a valid signature from the same Team ID
    /// as the running app (Gatekeeper never sees it: there is no quarantine
    /// flag on files we download ourselves), the same bundle identifier, and
    /// the version the release advertises.
    static func verify(appAt url: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.signature("different bundle identifier")
        }
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        guard SemVer(version) == SemVer(expectedVersion) else { throw UpdateError.versionMismatch(version) }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            throw UpdateError.signature("unreadable code object")
        }
        var requirement: SecRequirement?
        if let team = currentTeamID {
            let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
            guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess else { throw UpdateError.signature("bad requirement") }
        } else {
            Log.warning("Running app has no Team ID (ad-hoc build); only checking signature integrity", .updates)
        }
        var cfError: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), requirement, &cfError)
        guard status == errSecSuccess else {
            let why = (cfError?.takeRetainedValue()).map { String(describing: $0) } ?? "OSStatus \(status)"
            throw UpdateError.signature(why)
        }
    }

    static var currentTeamID: String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let code = selfCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code as! SecStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: Swap

    static func swap(staged: URL, into target: URL) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        let old = parent.appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-old-\(ProcessInfo.processInfo.processIdentifier).app")
        try fm.moveItem(at: target, to: old)
        do {
            try fm.moveItem(at: staged, to: target)
        } catch {
            try? fm.moveItem(at: old, to: target)   // roll back
            throw error
        }
        // The running executable is mapped from `old`; unlinking is fine on
        // macOS. If it fails (permissions) the next launch sweeps it.
        try? fm.removeItem(at: old)
    }

    static func cleanUpLeftovers(next bundle: URL) {
        let fm = FileManager.default
        let parent = bundle.deletingLastPathComponent()
        guard let items = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) else { return }
        for url in items where url.lastPathComponent.hasPrefix(".Wisp-old-") && url.pathExtension == "app" {
            try? fm.removeItem(at: url)
        }
        try? fm.removeItem(at: Paths.temporaryDirectory)
    }

    // MARK: Access

    /// Security-scoped access to the folder the app lives in. Remembered in a
    /// bookmark; on first use shows a pre-navigated panel with a single "Allow".
    @MainActor
    static func requestAccess(to folder: URL) -> URL? {
        let key = "wisp.updates.folderBookmark"
        if let data = UserDefaults.standard.data(forKey: key) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               url.standardizedFileURL == folder.standardizedFileURL, url.startAccessingSecurityScopedResource() {
                return url
            }
        }
        let panel = NSOpenPanel()
        panel.message = "Wisp needs permission to replace itself in “\(folder.lastPathComponent)”. Click Allow to continue."
        panel.prompt = "Allow"
        panel.directoryURL = folder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activateFrontmost()
        guard panel.runModal() == .OK, let url = panel.url, url.standardizedFileURL == folder.standardizedFileURL else { return nil }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return url.startAccessingSecurityScopedResource() ? url : nil
    }

    // MARK: Relaunch

    /// `/bin/sh` that waits for this pid to exit, then opens the bundle.
    /// Gives up after two minutes so a cancelled quit never relaunches later.
    static func spawnRelauncher(for bundle: URL) -> Process? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let quoted = bundle.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "i=0; while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; i=$((i+1)); [ $i -gt 600 ] && exit 0; done; /usr/bin/open '\(quoted)'"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = nil; p.standardError = nil
        do { try p.run(); return p } catch { Log.error("Relaunch helper failed: \(error.localizedDescription)", .updates); return nil }
    }

    // MARK: Helpers

    private static func run(_ tool: String, _ args: [String]) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
        guard status == 0 else { throw UpdateError.badArchive }
    }

    /// Belt and braces: strip com.apple.quarantine recursively so the new
    /// bundle launches without Gatekeeper's "unidentified developer" stop.
    private static func removeQuarantine(at root: URL) {
        let fm = FileManager.default
        var paths = [root.path]
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: []) {
            for case let u as URL in e { paths.append(u.path) }
        }
        for p in paths { removexattr(p, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }
}
