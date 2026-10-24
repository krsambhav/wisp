import Foundation

/// Owns the user's scripts: load/save from the Scripts folder, ordering, and
/// (optionally) a directory watcher for hot reload during development.
@MainActor
@Observable
final class ScriptStore {
    private(set) var scripts: [CustomScript] = []
    /// Incremented whenever the set of *injectable* scripts changes; the
    /// injection engine observes this.
    private(set) var revision: Int = 0
    /// Set while a file watcher is active.
    private(set) var isWatching = false
    /// Scripts whose source failed the syntax check (id → error).
    private(set) var syntaxErrors: [UUID: CustomScript.SyntaxError] = [:]

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let orderFile: URL
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private let reloadDebouncer = Debouncer(delay: .milliseconds(300))
    /// Called after an external change was picked up (hot reload).
    @ObservationIgnored var onExternalChange: (@MainActor () -> Void)?

    init(directory: URL = Paths.scriptsDirectory) {
        self.directory = directory
        self.orderFile = directory.appendingPathComponent("order.json")
        reloadFromDisk()
    }

    var enabledScripts: [CustomScript] { scripts.filter { $0.enabled && syntaxErrors[$0.id] == nil } }

    // MARK: Disk

    func reloadFromDisk() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
        var loaded: [CustomScript] = []
        for url in files where url.pathExtension.lowercased() == "js" {
            let base = url.deletingPathExtension().lastPathComponent
            let id = UUID(uuidString: base) ?? UUID(uuidString: Self.stableUUID(for: base)) ?? UUID()
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let script = CustomScript.parse(fileContents: contents, id: id, fallbackName: base, dates: (attrs?.creationDate ?? Date(), attrs?.contentModificationDate ?? Date()))
            loaded.append(script)
            // Files not named by UUID are adopted: rewritten under their id so edits round-trip.
            if UUID(uuidString: base) == nil {
                try? fm.moveItem(at: url, to: directory.appendingPathComponent(script.fileName))
            }
        }
        let order = (try? JSONDecoder.standard.decode([UUID].self, from: Data(contentsOf: orderFile))) ?? []
        loaded.sort { a, b in
            let ia = order.firstIndex(of: a.id) ?? Int.max, ib = order.firstIndex(of: b.id) ?? Int.max
            return ia != ib ? ia < ib : a.createdAt < b.createdAt
        }
        // Compare only what affects injection; timestamps differ between memory and disk.
        func key(_ s: CustomScript) -> String { "\(s.id)|\(s.enabled)|\(s.world.rawValue)|\(s.injectionTime.rawValue)|\(s.name)|\(s.source.hashValue)" }
        let changed = loaded.map(key) != scripts.map(key)
        scripts = loaded
        revalidateAll()
        if changed { revision += 1 }
        Log.info("Loaded \(scripts.count) script(s)", .scripts)
    }

    private func persistOrder() {
        try? JSONEncoder.pretty.encode(scripts.map(\.id)).write(to: orderFile, options: .atomic)
    }

    private func write(_ script: CustomScript) {
        do { try script.fileContents.write(to: directory.appendingPathComponent(script.fileName), atomically: true, encoding: .utf8) }
        catch { Log.error("Failed to save script \(script.name): \(error.localizedDescription)", .scripts) }
    }

    // MARK: Mutations

    @discardableResult
    func create(name: String = "New Script") -> CustomScript {
        let script = CustomScript(name: name, source: CustomScript.template(named: name))
        scripts.append(script)
        write(script); persistOrder(); revalidate(script); revision += 1
        return script
    }

    func importScript(from url: URL) throws -> CustomScript {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let name = url.deletingPathExtension().lastPathComponent
        var script = CustomScript.parse(fileContents: contents, id: UUID(), fallbackName: name, dates: (Date(), Date()))
        script.enabled = false // imported scripts start disabled; the user opts in
        scripts.append(script)
        write(script); persistOrder(); revalidate(script); revision += 1
        Log.info("Imported script \(script.name) (disabled until enabled)", .scripts)
        return script
    }

    func update(_ script: CustomScript) {
        guard let i = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        var s = script
        s.updatedAt = Date()
        let injectableChanged = scripts[i].source != s.source || scripts[i].enabled != s.enabled || scripts[i].injectionTime != s.injectionTime || scripts[i].world != s.world
        scripts[i] = s
        write(s); revalidate(s)
        if injectableChanged { revision += 1 }
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard var s = scripts.first(where: { $0.id == id }), s.enabled != enabled else { return }
        s.enabled = enabled
        update(s)
    }

    func delete(_ id: UUID) {
        guard let i = scripts.firstIndex(where: { $0.id == id }) else { return }
        let s = scripts.remove(at: i)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(s.fileName))
        syntaxErrors[id] = nil
        persistOrder(); revision += 1
    }

    func move(from: IndexSet, to: Int) {
        scripts.move(fromOffsets: from, toOffset: to)
        persistOrder(); revision += 1
    }

    func disableAll() {
        for s in scripts where s.enabled { setEnabled(s.id, false) }
    }

    func deleteAll() {
        for s in scripts { try? FileManager.default.removeItem(at: directory.appendingPathComponent(s.fileName)) }
        scripts.removeAll(); syntaxErrors.removeAll(); persistOrder(); revision += 1
    }

    // MARK: Validation

    private func revalidate(_ s: CustomScript) {
        syntaxErrors[s.id] = CustomScript.checkSyntax(s.source)
    }

    private func revalidateAll() {
        syntaxErrors = [:]
        for s in scripts { revalidate(s) }
    }

    // MARK: Hot reload

    func setWatching(_ on: Bool) {
        if on { startWatching() } else { stopWatching() }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { Log.error("Cannot watch scripts directory", .scripts); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.reloadDebouncer.call { [weak self] in
                guard let self else { return }
                let before = self.revision
                self.reloadFromDisk()
                if self.revision != before { Log.info("Scripts changed on disk — hot reloading", .scripts); self.onExternalChange?() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
        isWatching = true
        Log.info("Watching scripts directory for changes", .scripts)
    }

    private func stopWatching() {
        watcher?.cancel(); watcher = nil; isWatching = false
    }

    var directoryURL: URL { directory }

    /// Deterministic UUID for legacy file names (so a dropped-in `foo.js` keeps its identity across launches until adopted).
    nonisolated private static func stableUUID(for name: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for b in name.utf8 { hash ^= UInt64(b); hash = hash &* 1099511628211 }
        let hex = String(format: "%016llx", hash) + String(format: "%016llx", hash &* 31)
        let h = Array(hex)
        return "\(String(h[0..<8]))-\(String(h[8..<12]))-4\(String(h[13..<16]))-8\(String(h[17..<20]))-\(String(h[20..<32]))"
    }
}
