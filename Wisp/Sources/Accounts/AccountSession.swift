import AppKit
import Foundation
import WebKit

nonisolated enum PageState: Equatable, Sendable {
    case idle, loading, qr, chats, unknown
    case failed(String)

    var isFailed: Bool { if case .failed = self { return true } else { return false } }
    var label: String {
        switch self {
        case .idle: "Idle"
        case .loading: "Loading"
        case .qr: "Waiting for QR scan"
        case .chats: "Connected"
        case .unknown: "Loaded"
        case .failed(let m): "Failed: \(m)"
        }
    }
}

nonisolated struct SelectorHealth: Equatable, Sendable {
    let total: Int
    let missing: [String]
    let checkedAt: Date
}

/// One WhatsApp account at runtime: owns the persistent web view, tracks
/// unread count and page state, and bridges notifications for its account.
@MainActor
@Observable
final class AccountSession {
    private(set) var account: Account
    private(set) var pageState: PageState = .idle
    private(set) var unreadCount: Int = 0
    private(set) var hasFinishedFirstLoad = false
    private(set) var selectorHealth: SelectorHealth?
    private(set) var isWebViewCreated = false

    @ObservationIgnored private unowned let env: AppEnvironment
    @ObservationIgnored private var _webView: WKWebView?
    @ObservationIgnored private let router = ScriptMessageRouter()
    @ObservationIgnored private var coordinator: WebViewCoordinator?
    @ObservationIgnored private var titleObservation: NSKeyValueObservation?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0

    init(account: Account, environment: AppEnvironment) {
        self.account = account
        self.env = environment
        router.session = self
    }

    func updateAccount(_ a: Account) { account = a }
    var isMockMode: Bool { env.mockMode }

    // MARK: Web view lifecycle

    var webView: WKWebView {
        if let w = _webView { return w }
        let coordinator = WebViewCoordinator(session: self, environment: env)
        self.coordinator = coordinator
        let w = WebViewFactory.make(for: account, environment: env, router: router, coordinator: coordinator)
        _webView = w
        isWebViewCreated = true
        applyAppearance()
        titleObservation = w.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
            let title = view.title
            Task { @MainActor [weak self] in self?.titleDidChange(title) }
        }
        Log.info("Web view created for account \(account.id.uuidString.prefix(8))", .web)
        return w
    }

    func loadIfNeeded() {
        if webView.url == nil && pageState == .idle { load() }
    }

    func load() {
        pageState = .loading
        if env.mockMode, let mock = Bundle.main.url(forResource: "whatsapp-mock", withExtension: "html") {
            var comps = URLComponents(url: mock, resolvingAgainstBaseURL: false)!
            comps.query = ProcessInfo.processInfo.environment["WISP_MOCK_QUERY"]
            webView.loadFileURL(comps.url!, allowingReadAccessTo: mock.deletingLastPathComponent())
            return
        }
        webView.load(URLRequest(url: WebViewFactory.whatsappURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func reload(ignoringCache: Bool = false) {
        guard _webView != nil else { load(); return }
        cancelRetry()
        if webView.url == nil || pageState.isFailed { load(); return }
        pageState = .loading
        if ignoringCache { webView.reloadFromOrigin() } else { webView.reload() }
    }

    /// Releases the web view (used when an account is removed or unloaded).
    func tearDown() {
        cancelRetry()
        titleObservation = nil
        if let w = _webView {
            w.stopLoading()
            w.configuration.userContentController.removeAllScriptMessageHandlers()
            w.configuration.userContentController.removeAllUserScripts()
            w.navigationDelegate = nil
            w.uiDelegate = nil
            w.removeFromSuperview()
        }
        _webView = nil
        isWebViewCreated = false
        pageState = .idle
        unreadCount = 0
        hasFinishedFirstLoad = false
    }

    // MARK: Navigation callbacks (from coordinator)

    func navigationDidStart() {
        if !pageState.isFailed { pageState = .loading }
    }

    func navigationDidCommit() {
        hasFinishedFirstLoad = true
        retryAttempt = 0
    }

    func navigationDidFinish() {
        if pageState == .loading { pageState = .unknown }
        env.injection.applyLiveStyles(to: webView)
        Log.info("WhatsApp Web loaded (account \(account.id.uuidString.prefix(8)))", .web)
        #if DEBUG
        if ProcessInfo.processInfo.environment["WISP_DEBUG_DUMP"] != nil { scheduleDebugDump() }
        #endif
    }

    #if DEBUG
    /// Development aid (WISP_DEBUG_DUMP=1): logs view geometry and a short DOM
    /// summary of the login page. Never enabled in release builds.
    private func scheduleDebugDump() {
        Task { [weak self] in
            let delay = ProcessInfo.processInfo.environment["WISP_DEBUG_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 8
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let w = self._webView else { return }
            Log.debug("webView frame=\(w.frame) superview=\(String(describing: w.superview.map { type(of: $0) })) window=\(w.window != nil) hidden=\(w.isHidden) url=\(w.url?.absoluteString ?? "nil") title=\(w.title ?? "nil") loading=\(w.isLoading)", .web)
            let js = """
            JSON.stringify({ ready: document.readyState, state: (globalThis.__wispCore ? globalThis.__wispCore.state() : 'no-core'),
              app: !!document.querySelector('#app'), appChildren: document.querySelector('#app') ? document.querySelector('#app').children.length : -1,
              canvas: document.querySelectorAll('canvas').length, bodyBg: getComputedStyle(document.body).backgroundColor,
              styles: document.querySelectorAll('style[data-wisp]').length, text: (document.body ? document.body.innerText : '').replace(/\\s+/g,' ').slice(0, 300) })
            """
            w.evaluateJavaScript(js, in: nil, in: ContentWorlds.core) { result in
                switch result {
                case .success(let v): Log.debug("DOM: \(v)", .web)
                case .failure(let e): Log.debug("DOM dump failed: \(e)", .web)
                }
            }
            w.evaluateJavaScript("JSON.stringify({ wisp: typeof globalThis.wisp, attr: document.documentElement.getAttribute('data-wisp-script') })", in: nil, in: ContentWorlds.user) { result in
                Log.debug("user world: \((try? result.get()) ?? "error")", .web)
            }
            if ProcessInfo.processInfo.environment["WISP_DEBUG_DOM_OUTLINE"] != nil {
                // Structural outline only: tags, ids, roles, aria-labels, truncated class names. Never text content.
                let js = """
                (function(){
                  function desc(el){ var s=el.tagName.toLowerCase(); if(el.id) s+='#'+el.id; var r=el.getAttribute('role'); if(r) s+='[role='+r+']';
                    var a=el.getAttribute('aria-label'); if(a) s+='[aria-label='+a.slice(0,24)+']'; var d=el.getAttribute('data-icon'); if(d) s+='[data-icon='+d+']';
                    var t=el.getAttribute('data-tab'); if(t) s+='[data-tab='+t+']'; if(el.className && typeof el.className==='string') s+='.'+el.className.split(' ').slice(0,2).join('.').slice(0,40); return s; }
                  var out=[]; function walk(el,depth,max){ if(depth>max||out.length>260) return; out.push('  '.repeat(depth)+desc(el)+(el.children.length>6?' ('+el.children.length+' children)':'')); var kids=Array.from(el.children).slice(0,6); for(var k of kids) walk(k,depth+1,max); }
                  var app=document.querySelector('#app'); if(app) walk(app,0,5);
                  var hooks=['#side','#pane-side','#main','#main header','#main footer','#side header','#pane-side [role=row]','[role=listitem]','.message-in','.message-out','.message-in > div:first-child','.copyable-text','.selectable-text','#side [contenteditable]','#main footer [contenteditable]','[data-icon=tail-in]','[data-icon=tail-out]','a[href*="download"]','#app a[href*="whatsapp.com/download"]','nav','[data-navbar-item]','header','footer','[role=button][aria-label*="Search"]','[aria-label="Chat list"]','[data-tab]'];
                  var h=hooks.map(function(q){ try{ var n=document.querySelectorAll(q).length; var e=document.querySelector(q); return q+' => '+n+(e?' e.g. '+desc(e)+' size='+Math.round(e.getBoundingClientRect().width)+'x'+Math.round(e.getBoundingClientRect().height):''); }catch(x){ return q+' => invalid'; } });
                  var cs=getComputedStyle(document.body); var vars=['--WDS-surface-default','--WDS-background-wash-plain','--WDS-systems-chat-background-wallpaper','--radius-app','--navbar-width'].map(function(v){ return v+'='+cs.getPropertyValue(v).trim(); });
                  return 'HOOKS\\n'+h.join('\\n')+'\\nVARS '+vars.join(' ')+'\\nOUTLINE\\n'+out.join('\\n');
                })();
                """
                w.evaluateJavaScript(js, in: nil, in: ContentWorlds.core) { result in
                    if case .success(let v) = result, let text = v as? String {
                        for line in text.split(separator: "\n") { FileHandle.standardError.write(Data(("[DOM] " + line + "\n").utf8)) }
                    }
                }
            }
            if let path = ProcessInfo.processInfo.environment["WISP_DEBUG_SNAPSHOT"] {
                let cfg = WKSnapshotConfiguration()
                cfg.afterScreenUpdates = true
                w.takeSnapshot(with: cfg) { image, error in
                    guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
                        Log.debug("Snapshot failed: \(error?.localizedDescription ?? "?")", .web); return
                    }
                    try? png.write(to: URL(fileURLWithPath: path))
                    Log.debug("Snapshot written to \(path) (\(Int(image.size.width))x\(Int(image.size.height)))", .web)
                }
            }
        }
    }
    #endif

    func navigationDidFail(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // frame load interrupted (downloads / policy cancel)
        pageState = .failed(ns.localizedDescription)
        Log.warning("Navigation failed: \(ns.domain) \(ns.code) \(ns.localizedDescription)", .web)
        scheduleRetry()
    }

    func processDidTerminate() {
        pageState = .failed("The web content process stopped.")
        reload()
    }

    /// Exponential backoff retry (2s → 60s). Event-driven reconnects via
    /// NetworkMonitor short-circuit this.
    private func scheduleRetry() {
        cancelRetry()
        guard env.network.isOnline else { return } // NetworkMonitor will call retryNow() on reconnect
        retryAttempt += 1
        let delay = min(60, pow(2.0, Double(retryAttempt)))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.pageState.isFailed else { return }
            Log.info("Retrying WhatsApp load (attempt \(self.retryAttempt))", .web)
            self.load()
        }
    }

    func retryNowIfFailed() {
        guard pageState.isFailed else { return }
        cancelRetry()
        retryAttempt = 0
        load()
    }

    private func cancelRetry() { retryTask?.cancel(); retryTask = nil }

    // MARK: Title / unread

    private func titleDidChange(_ title: String?) {
        let n = UnreadTitleParser.unreadCount(from: title)
        if n != unreadCount {
            unreadCount = n
            env.badgesDidChange()
        }
    }

    // MARK: Bridge callbacks

    func handlePageState(_ s: String) {
        let new: PageState = switch s {
            case "qr": .qr
            case "chats": .chats
            case "loading": .loading
            default: .unknown
        }
        if new != pageState && !pageState.isFailed {
            pageState = new
            Log.info("Page state → \(new.label)", .web)
        }
    }

    func handleSelectorHealth(total: Int, missing: [String]) {
        selectorHealth = SelectorHealth(total: total, missing: missing, checkedAt: Date())
        if missing.isEmpty {
            Log.info("Theme selector check: all \(total) hooks present", .injection)
        } else {
            Log.warning("Theme selector check: \(missing.count)/\(total) hooks missing — \(missing.joined(separator: ", "))", .injection)
        }
    }

    func handleIncomingNotification(_ n: IncomingNotification) {
        env.notifications.deliver(n, account: account, isAccountVisibleAndFocused: isVisibleAndFocused)
    }

    func handleNotificationClosed(id: Int) {
        // WhatsApp closes a notification when the chat is read: mirror it.
        env.notifications.withdrawAll(accountID: account.id)
    }

    /// Called when the user clicks a native notification for this account.
    func notificationClicked(id: Int) {
        let js = "globalThis.__wispNotify ? globalThis.__wispNotify.click(\(id)) : false"
        webView.evaluateJavaScript(js, in: nil, in: .page) { result in
            if case .failure(let e) = result { Log.warning("Notification click dispatch failed: \(e.localizedDescription)", .notifications) }
        }
    }

    var isVisibleAndFocused: Bool {
        env.sessions.activeAccountID == account.id && env.window.isKeyAndVisible && NSApp.isActive
    }

    // MARK: Customization hooks

    func applyLiveStyles() {
        guard let w = _webView, w.url != nil else { return }
        env.injection.applyLiveStyles(to: w)
    }

    func refreshUserScripts() {
        guard let w = _webView else { return }
        env.injection.refreshUserScripts(on: w.configuration.userContentController)
    }

    func applyAppearance() {
        guard let w = _webView else { return }
        let theme = ThemeCatalog.theme(id: env.settings.appearance.themeID)
        let mode = theme.preferredMode ?? env.settings.appearance.mode
        switch mode {
        case .system: w.appearance = nil
        case .light: w.appearance = NSAppearance(named: .aqua)
        case .dark: w.appearance = NSAppearance(named: .darkAqua)
        }
        w.pageZoom = env.settings.appearance.interfaceScale
    }

    func setDeveloperTools(_ on: Bool) {
        guard let w = _webView else { return }
        w.isInspectable = on
        w.configuration.preferences.setValue(on, forKey: "developerExtrasEnabled")
    }

    func focusSearch() {
        guard let w = _webView else { return }
        w.window?.makeFirstResponder(w)
        w.evaluateJavaScript("globalThis.__wispCore && globalThis.__wispCore.focusSearch()", in: nil, in: ContentWorlds.core, completionHandler: nil)
    }

    // MARK: Data management

    /// Removes caches only; login state (cookies, IndexedDB, localStorage) is kept.
    func clearCache() async {
        let store = webView.configuration.websiteDataStore
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache]
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        Log.info("Cache cleared for account \(account.id.uuidString.prefix(8))", .accounts)
    }

    /// Full sign-out: wipes every piece of website data for this account.
    func clearSession() async {
        let store = webView.configuration.websiteDataStore
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        env.notifications.withdrawAll(accountID: account.id)
        unreadCount = 0
        env.badgesDidChange()
        Log.info("Session data cleared for account \(account.id.uuidString.prefix(8))", .accounts)
        load()
    }
}
