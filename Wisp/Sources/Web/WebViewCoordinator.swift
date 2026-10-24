import AppKit
import AVFoundation
import WebKit

/// Navigation + UI delegate for one session's web view.
@MainActor
final class WebViewCoordinator: NSObject {
    weak var session: AccountSession?
    weak var environment: AppEnvironment?

    init(session: AccountSession, environment: AppEnvironment) {
        self.session = session
        self.environment = environment
    }

    private func openExternally(_ url: URL) {
        guard ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
        Log.info("Opened external link in default browser", .web)
    }
}

// MARK: - WKNavigationDelegate

extension WebViewCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        Log.debug("navigationAction \(navigationAction.request.url?.scheme ?? "?") type=\(navigationAction.navigationType.rawValue) download=\(navigationAction.shouldPerformDownload) main=\(navigationAction.targetFrame?.isMainFrame ?? true)", .web)
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame || WebViewFactory.isFirstParty(url) || (environment?.mockMode == true && url.isFileURL) {
            decisionHandler(.allow)
            return
        }
        // Main-frame navigation away from WhatsApp: never let the chat view leave.
        if environment?.settings.general.openExternalLinksInBrowser ?? true {
            openExternally(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType { decisionHandler(.download); return }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
           disposition.hasPrefix("attachment") {
            decisionHandler(.download); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        environment?.downloads.adopt(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        environment?.downloads.adopt(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session?.navigationDidStart()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        session?.navigationDidCommit()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        session?.navigationDidFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        session?.navigationDidFail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        session?.navigationDidFail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.error("Web content process terminated — reloading", .web)
        session?.processDidTerminate()
    }

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }
}

// MARK: - WKUIDelegate

extension WebViewCoordinator: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if WebViewFactory.isFirstParty(url), url.scheme?.hasPrefix("http") == true {
                // Rare: WhatsApp opening its own pages (help, business tools). Load in place is wrong; use the browser.
                openExternally(url)
            } else {
                openExternally(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.message = "Choose files to attach"
        let host = webView.window
        let handler: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let host { panel.beginSheetModal(for: host, completionHandler: handler) } else { handler(panel.runModal()) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        guard origin.host.hasSuffix("whatsapp.com") else { decisionHandler(.deny); return }
        let needsAudio = type == .microphone || type == .cameraAndMicrophone
        let needsVideo = type == .camera || type == .cameraAndMicrophone
        Task { @MainActor in
            var ok = true
            if needsAudio { ok = await AVCaptureDevice.requestAccess(for: .audio) && ok }
            if needsVideo { ok = await AVCaptureDevice.requestAccess(for: .video) && ok }
            Log.info("Media capture (\(type.rawValue)) \(ok ? "granted" : "denied")", .web)
            decisionHandler(ok ? .grant : .deny)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = "WhatsApp"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let w = webView.window { alert.beginSheetModal(for: w) { _ in completionHandler() } } else { alert.runModal(); completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "WhatsApp"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let w = webView.window { alert.beginSheetModal(for: w) { r in completionHandler(r == .alertFirstButtonReturn) } }
        else { completionHandler(alert.runModal() == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "WhatsApp"
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { r in completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil) }
        if let w = webView.window { alert.beginSheetModal(for: w, completionHandler: finish) } else { finish(alert.runModal()) }
    }
}
