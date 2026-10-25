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

/// Download, verify, then hand over to the XPC helper. Download and extraction
/// (`ditto`) happen inside the sandbox in the container's temp dir; the swap
/// into /Applications and the relaunch happen in WispUpdateHelper.
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

    // MARK: Install (via XPC helper)

    /// The sandbox quarantines everything we write and will not let us clear
    /// the flag, so the swap and the relaunch run in the unsandboxed
    /// WispUpdateHelper XPC service (Contents/XPCServices).
    static func installViaHelper(staged: URL, target: URL, relaunchAfterPID pid: Int32) async throws {
        let connection = NSXPCConnection(serviceName: WispUpdateHelper.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: WispUpdateHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let once = OnceBox()
        let failure: String? = try await withCheckedThrowingContinuation { cont in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.run { cont.resume(throwing: UpdateError.helper("service unavailable: \(error.localizedDescription)")) }
            } as! WispUpdateHelperProtocol
            proxy.install(staged: staged.path, target: target.path, relaunchAfterPID: pid) { message in
                once.run { cont.resume(returning: message) }
            }
        }
        if let failure { throw UpdateError.helper(failure) }
    }

    static func cleanUpLeftovers(next bundle: URL) {
        let fm = FileManager.default
        let parent = bundle.deletingLastPathComponent()
        if let items = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) {
            for url in items where url.lastPathComponent.hasPrefix(".Wisp-old-") && url.pathExtension == "app" { try? fm.removeItem(at: url) }
        }
        try? fm.removeItem(at: Paths.temporaryDirectory)
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

}

/// Guards a continuation against being resumed by both the XPC error handler
/// and the reply block.
nonisolated final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
