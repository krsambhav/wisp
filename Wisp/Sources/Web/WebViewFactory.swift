import AppKit
import WebKit

/// Creates the single, long-lived `WKWebView` for an account session.
enum WebViewFactory {
    static let whatsappURL = URL(string: "https://web.whatsapp.com/")!

    @MainActor
    static func make(for account: Account, environment env: AppEnvironment, router: ScriptMessageRouter, coordinator: WebViewCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Persistent, per-account storage. Cookies, IndexedDB, localStorage,
        // caches and service-worker registrations all live under this identifier.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.dataStoreID)

        config.applicationNameForUserAgent = UserAgent.applicationNameSuffix(extra: env.settings.advanced.customUserAgentSuffix)
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.suppressesIncrementalRendering = false
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.preferences.isTextInteractionEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        if env.settings.advanced.developerToolsEnabled {
            // Adds "Inspect Element" to the context menu. Private preference key, long-standing.
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        env.injection.configure(config.userContentController, router: router)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.allowsLinkPreview = false
        webView.isInspectable = env.settings.advanced.developerToolsEnabled
        webView.pageZoom = env.settings.appearance.interfaceScale
        webView.setValue(false, forKey: "drawsBackground") // avoid white flash before first paint
        webView.underPageBackgroundColor = .clear
        return webView
    }

    /// Hosts WhatsApp may legitimately navigate the main frame to.
    nonisolated static let firstPartyHostSuffixes = ["whatsapp.com", "whatsapp.net", "facebook.com", "fbcdn.net", "meta.com", "fb.com", "metaai.com"]

    nonisolated static func isFirstParty(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return ["about", "blob", "data", "javascript"].contains(url.scheme?.lowercased() ?? "")
        }
        return firstPartyHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
