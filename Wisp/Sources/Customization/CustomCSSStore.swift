import Foundation

/// The user's custom stylesheet lives in its own file so it can be edited
/// externally and diffed. Saved with a short debounce.
@MainActor
@Observable
final class CustomCSSStore {
    var css: String { didSet { if css != oldValue { scheduleSave() } } }
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let saveDebouncer = Debouncer(delay: .milliseconds(400))

    init(url: URL = Paths.customCSSFile) {
        self.url = url
        css = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func scheduleSave() {
        saveDebouncer.call { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        do { try css.write(to: url, atomically: true, encoding: .utf8) }
        catch { Log.error("Failed to save custom CSS: \(error.localizedDescription)", .settings) }
    }

    var validationError: String? { CSSGenerator.validate(css: css) }
}
