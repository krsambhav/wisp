import AppKit
import Foundation
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

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    func adopt(_ download: WKDownload) {
        download.delegate = self
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

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(Paths.downloadsDirectory)
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
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
        update(download) { $0.state = .failed(error.localizedDescription) }
        active[ObjectIdentifier(download)] = nil
        Log.error("Download failed: \(error.localizedDescription)", .downloads)
    }

    func download(_ download: WKDownload, decidePlaceholderPolicy completionHandler: @escaping @MainActor (WKDownload.PlaceholderPolicy, URL?) -> Void) {
        completionHandler(.disable, nil)
    }
}
