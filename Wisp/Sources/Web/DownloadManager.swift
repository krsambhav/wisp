import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

nonisolated struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    var fileName: String
    var destination: URL?
    var state: State
    var startedAt: Date
    enum State: Equatable { case inProgress, finished, failed(String) }
}

/// Native download handling (WKDownload). Files go to ~/Downloads (sandbox
/// entitlement) or to a user-chosen location when "Ask where to save" is on.
@MainActor
@Observable
final class DownloadManager: NSObject {
    private(set) var items: [DownloadItem] = []
    @ObservationIgnored private var active: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored var onFinished: (@MainActor (URL) -> Void)?
    /// Armed by the in-page "Copy file" button: the next download (within the
    /// deadline) lands in a temp folder and goes on the clipboard instead of
    /// into ~/Downloads, with no toast, no list entry and no Finder reveal.
    @ObservationIgnored private var clipboardDeadline: Date?
    @ObservationIgnored private var clipboardDownloads: [ObjectIdentifier: URL] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    func captureNextToClipboard(_ armed: Bool, timeout: TimeInterval = 15) {
        clipboardDeadline = armed ? Date().addingTimeInterval(timeout) : nil
    }

    func adopt(_ download: WKDownload) {
        download.delegate = self
        if let deadline = clipboardDeadline, deadline > Date() {
            clipboardDeadline = nil
            clipboardDownloads[ObjectIdentifier(download)] = Self.clipboardDirectory // placeholder until the name is known
            Log.info("Download started (to clipboard)", .downloads)
            return
        }
        Log.info("Download started", .downloads)
        let item = DownloadItem(id: UUID(), fileName: "Download", destination: nil, state: .inProgress, startedAt: Date())
        items.insert(item, at: 0)
        if items.count > 50 { items.removeLast(items.count - 50) }
        active[ObjectIdentifier(download)] = item.id
    }

    private func update(_ download: WKDownload, _ change: (inout DownloadItem) -> Void) {
        guard let id = active[ObjectIdentifier(download)], let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    private static let clipboardDirectory = Paths.temporaryDirectory.appendingPathComponent("clipboard", isDirectory: true)

    /// One folder per copied file so names stay intact; older folders are
    /// dropped once the clipboard can no longer be pointing at them.
    private func clipboardDestination(for name: String) -> URL {
        let fm = FileManager.default
        let root = Self.clipboardDirectory
        if let old = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) {
            let sorted = old.sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            for stale in sorted.dropFirst(4) { try? fm.removeItem(at: stale) }
        }
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return fm.uniqueURL(in: dir, preferredName: name)
    }

    /// File URL for Finder and file-accepting apps; pictures also carry image
    /// data so image fields (Notes, Slack, Preview) paste them directly.
    private func copyToPasteboard(_ url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image), let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
            if let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data).flatMap({ $0.tiffRepresentation }).flatMap({ NSBitmapImageRep(data: $0) }) {
                if type != .png, let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
                if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
        Log.info("Copied to clipboard: \(url.lastPathComponent) types=\(item.types.map(\.rawValue).joined(separator: ","))", .downloads)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(Paths.downloadsDirectory)
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        if clipboardDownloads[ObjectIdentifier(download)] != nil {
            let url = clipboardDestination(for: suggestedFilename)
            clipboardDownloads[ObjectIdentifier(download)] = url
            completionHandler(url)
            return
        }
        update(download) { $0.fileName = suggestedFilename }
        Log.debug("Download destination requested for \(suggestedFilename) (\(response.expectedContentLength) bytes)", .downloads)
        if settings.advanced.askWhereToSaveDownloads {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.directoryURL = Paths.downloadsDirectory
            panel.canCreateDirectories = true
            let finish: @MainActor (NSApplication.ModalResponse) -> Void = { r in
                let url = r == .OK ? panel.url : nil
                if let url { try? FileManager.default.removeItem(at: url) } // WKDownload refuses to overwrite
                self.update(download) { $0.destination = url }
                completionHandler(url)
            }
            if let w = NSApp.keyWindow { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
        } else {
            let url = FileManager.default.uniqueURL(in: Paths.downloadsDirectory, preferredName: suggestedFilename)
            update(download) { $0.destination = url }
            completionHandler(url)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = clipboardDownloads.removeValue(forKey: ObjectIdentifier(download)) {
            if FileManager.default.fileExists(atPath: url.path), !url.hasDirectoryPath { copyToPasteboard(url) }
            return
        }
        var finished: URL?
        update(download) { $0.state = .finished; finished = $0.destination }
        active[ObjectIdentifier(download)] = nil
        guard let url = finished else { return }
        Log.info("Download finished: \(url.lastPathComponent)", .downloads)
        NSApp.dockTile.display()
        if settings.advanced.revealDownloadsInFinder { reveal(url) }
        onFinished?(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        clipboardDownloads[ObjectIdentifier(download)] = nil
        update(download) { $0.state = .failed(error.localizedDescription) }
        active[ObjectIdentifier(download)] = nil
        Log.error("Download failed: \(error.localizedDescription)", .downloads)
    }

    func download(_ download: WKDownload, decidePlaceholderPolicy completionHandler: @escaping @MainActor (WKDownload.PlaceholderPolicy, URL?) -> Void) {
        completionHandler(.disable, nil)
    }
}
