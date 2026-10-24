import WebKit

extension WKWebView {
    /// Completion-handler evaluate wrapped for async use, returning a String
    /// (numbers/bools are stringified) so the result is Sendable. The SDK's async
    /// overload with `in:in:` labels returned Void in practice.
    @MainActor
    func eval(_ js: String, world: WKContentWorld) async throws -> String? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            self.evaluateJavaScript(js, in: nil, in: world) { result in
                switch result {
                case .success(let v):
                    if let s = v as? String { cont.resume(returning: s) }
                    else if let n = v as? NSNumber { cont.resume(returning: n.stringValue) }
                    else { cont.resume(returning: String(describing: v)) }
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }
    }
}
