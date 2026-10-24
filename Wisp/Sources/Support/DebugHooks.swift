import AppKit
import Foundation
import WebKit

#if DEBUG
/// Development-only automation driven by environment variables. Compiled out
/// of Release builds. Used by scripts/dev-run.sh and the test checklist.
///
///   WISP_MOCK=1                      load the bundled mock page instead of WhatsApp
///   WISP_MOCK_QUERY=auto=1           query string for the mock page (auto scenario)
///   WISP_DEBUG_DUMP=1                log geometry + DOM summary 8s after load
///   WISP_DEBUG_DOM_OUTLINE=1         with DUMP: log a structural outline (tags/ids/roles only, never text)
///   WISP_DEBUG_SNAPSHOT=/path.png    write a WebKit snapshot of the page after load
///   WISP_DEBUG_SNAPSHOT_DELAY=<s>    seconds after load for the dump/snapshot (default 8)
///   WISP_DEBUG_OPEN_SETTINGS=<sec>   open Settings at a section after 3s
///   WISP_DEBUG_WINDOW_DIR=/dir       write PNGs of every app window (native content) after 6s
///   WISP_DEBUG_QUIT_AFTER=<seconds>  terminate after N seconds (bypasses the sync-guard alert)
///   WISP_DEBUG_THEME=<id>            select a theme at launch (default|minimal|midnight)
///   WISP_DEBUG_MODE=<mode>           appearance mode (system|light|dark)
///   WISP_DEBUG_THEME_DIR=<dir>       load theme CSS from this directory and hot-reload it on change
///   WISP_DEBUG_SNAPSHOT_DIR=<dir>    touch <dir>/snap.request to write <dir>/snap.png (page) + window PNGs
///   WISP_DEBUG_IMPORT_SCRIPT=<path>  import a .js file as an enabled user script
///   WISP_DEBUG_CSS=<path>            load custom CSS from a file
///   WISP_DEBUG_RESET_SCRIPTS=1       delete all user scripts first
///   WISP_DEBUG_FORCE_NOTIFY=1        deliver notifications even while the window is focused
@MainActor
enum DebugHooks {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    nonisolated(unsafe) private static var watchers: [DispatchSourceFileSystemObject] = []

    private static func watch(directory: URL, _ onChange: @escaping @MainActor () -> Void) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { Log.warning("Cannot watch \(directory.path)", .app); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend, .attrib], queue: .main)
        let debouncer = Debouncer(delay: .milliseconds(250))
        src.setEventHandler { debouncer.call { onChange() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers.append(src)
    }

    static func installAfterLaunch(_ app: AppEnvironment) {
        // Hot-reload theme stylesheets from a directory (edit minimal.css → applied live, no reload).
        if let dir = env["WISP_DEBUG_THEME_DIR"] {
            let url = URL(fileURLWithPath: dir)
            CSSGenerator.themeDirectoryOverride = url
            watch(directory: url) { app.sessions.applyLiveStylesEverywhere(); Log.info("Theme CSS reloaded from \(dir)", .injection) }
        }
        // Snapshot on demand: touch "<dir>/snap.request" → "<dir>/snap.png" (web view) + "<dir>/window.png".
        if let dir = env["WISP_DEBUG_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir)
            watch(directory: url) {
                let req = url.appendingPathComponent("snap.request")
                guard FileManager.default.fileExists(atPath: req.path) else { return }
                try? FileManager.default.removeItem(at: req)
                guard let s = app.sessions.activeSession, s.isWebViewCreated else { return }
                let cfg = WKSnapshotConfiguration(); cfg.afterScreenUpdates = true
                s.webView.takeSnapshot(with: cfg) { image, _ in
                    if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: url.appendingPathComponent("snap.png"))
                        Log.info("Snapshot written to \(dir)/snap.png", .web)
                    }
                }
                snapshotWindows(to: dir)
            }
        }
        if let theme = env["WISP_DEBUG_THEME"] { app.settings.appearance.themeID = theme }
        if let mode = env["WISP_DEBUG_MODE"].flatMap(AppearanceMode.init(rawValue:)) { app.settings.appearance.mode = mode }
        if env["WISP_DEBUG_RESET_SCRIPTS"] == "1" { app.scripts.deleteAll() }
        if let path = env["WISP_DEBUG_IMPORT_SCRIPT"] {
            if let s = try? app.scripts.importScript(from: URL(fileURLWithPath: path)) {
                app.scripts.setEnabled(s.id, true)
                app.sessions.refreshUserScriptsEverywhere()
                app.sessions.reloadAll() // user scripts take effect on the next navigation
            }
        }
        if let path = env["WISP_DEBUG_CSS"], let css = try? String(contentsOfFile: path, encoding: .utf8) { app.customCSS.css = css }
        if env["WISP_DEBUG_FORCE_NOTIFY"] == "1" { app.settings.notifications.suppressWhenWindowFocused = false }
        if let section = env["WISP_DEBUG_OPEN_SETTINGS"].flatMap(SettingsSection.init(rawValue:)) {
            Task { try? await Task.sleep(for: .seconds(3)); app.openSettings(section) }
        }
        if let dir = env["WISP_DEBUG_WINDOW_DIR"] {
            Task { try? await Task.sleep(for: .seconds(6)); snapshotWindows(to: dir) }
        }
        if let secs = env["WISP_DEBUG_QUIT_AFTER"].flatMap(Double.init) {
            Task { try? await Task.sleep(for: .seconds(secs)); app.isQuitForced = true; NSApp.terminate(nil) }
        }
    }

    /// Renders each window's view hierarchy with `cacheDisplay` — works even when
    /// the display is locked or the window is on another Space. Web content is
    /// a remote layer and shows as blank here; use WISP_DEBUG_SNAPSHOT for it.
    static func snapshotWindows(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (i, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = (window.title.isEmpty ? "window-\(i)" : window.title).replacingOccurrences(of: " ", with: "-").lowercased()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
                Log.debug("Window snapshot: \(name).png \(Int(view.bounds.width))x\(Int(view.bounds.height))", .app)
            }
        }
    }
}
#endif
