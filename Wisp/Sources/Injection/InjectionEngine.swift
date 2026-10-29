import Foundation
import WebKit

/// Builds the `WKUserScript` set for a session and pushes live updates (CSS,
/// attributes) into already-loaded pages without reloading.
///
/// Layering (all main frame only):
///   1. wisp-page.js            page world, document start
///   2. wisp-core.js            core world, document start
///   3. style bootstrap         core world, document start  (tokens + theme + user CSS)
///   4. wisp-user-runtime.js    user world + page world (only if a script needs it)
///   5. user scripts            their chosen world & time, each wrapped for error capture
@MainActor
final class InjectionEngine {
    private let settings: SettingsStore
    private let scripts: ScriptStore
    private let customCSS: CustomCSSStore

    private let pageBridgeSource: String
    private let coreSource: String
    private let userRuntimeSource: String

    init(settings: SettingsStore, scripts: ScriptStore, customCSS: CustomCSSStore) {
        self.settings = settings
        self.scripts = scripts
        self.customCSS = customCSS
        pageBridgeSource = Self.loadResource("wisp-page")
        coreSource = Self.loadResource("wisp-core")
        userRuntimeSource = Self.loadResource("wisp-user-runtime")
    }

    nonisolated private static func loadResource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            Log.error("Bundled script \(name).js missing", .injection)
            return ""
        }
        return s
    }

    // MARK: Current state

    var theme: Theme { ThemeCatalog.theme(id: settings.appearance.themeID) }

    var tokensCSS: String { CSSGenerator.tokensCSS(theme: theme, appearance: settings.appearance) }
    var themeCSS: String { CSSGenerator.themeCSS(theme: theme) }
    var userCSS: String { settings.appearance.customCSSEnabled ? customCSS.css : "" }

    // MARK: Building

    /// Installs everything on a fresh content controller.
    func configure(_ controller: WKUserContentController, router: ScriptMessageRouter) {
        controller.removeAllUserScripts()
        controller.removeAllScriptMessageHandlers()

        // Handlers — scoped per world.
        controller.add(router, contentWorld: .page, name: BridgeMessage.notify.rawValue)
        controller.add(router, contentWorld: ContentWorlds.core, name: BridgeMessage.state.rawValue)
        controller.add(router, contentWorld: ContentWorlds.core, name: BridgeMessage.diag.rawValue)
        controller.add(router, contentWorld: ContentWorlds.core, name: BridgeMessage.clipboard.rawValue)
        controller.add(router, contentWorld: ContentWorlds.core, name: BridgeMessage.log.rawValue)
        controller.add(router, contentWorld: ContentWorlds.user, name: BridgeMessage.log.rawValue)
        controller.add(router, contentWorld: .page, name: BridgeMessage.log.rawValue)

        for script in buildUserScripts() { controller.addUserScript(script) }
    }

    /// Replaces the user scripts on an existing controller (takes effect on next navigation).
    func refreshUserScripts(on controller: WKUserContentController) {
        controller.removeAllUserScripts()
        for script in buildUserScripts() { controller.addUserScript(script) }
    }

    private func buildUserScripts() -> [WKUserScript] {
        var out: [WKUserScript] = []
        out.append(WKUserScript(source: pageBridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        out.append(WKUserScript(source: coreSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ContentWorlds.core))
        out.append(WKUserScript(source: styleBootstrapJS(), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ContentWorlds.core))

        let enabled = scripts.enabledScripts
        let worldsInUse = Set(enabled.map(\.world))
        for w in worldsInUse {
            out.append(WKUserScript(source: userRuntimeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ContentWorlds.world(for: w)))
        }
        Log.debug("Injecting \(enabled.count) user script(s): \(enabled.map(\.name).joined(separator: ", "))", .injection)
        for s in enabled {
            let wrapped = Self.wrap(script: s)
            let time: WKUserScriptInjectionTime = s.injectionTime == .documentStart ? .atDocumentStart : .atDocumentEnd
            out.append(WKUserScript(source: wrapped, injectionTime: time, forMainFrameOnly: true, in: ContentWorlds.world(for: s.world)))
        }
        return out
    }

    /// Every user script runs inside `wisp.__run(name, fn)` so an exception is
    /// reported and cannot take down other scripts or the page.
    nonisolated static func wrap(script: CustomScript) -> String {
        """
        (function(){
          var __run = (globalThis.wisp && globalThis.wisp.__run) ? globalThis.wisp.__run : function(n, f){ try { f(); } catch (e) { console.error('[wisp:' + n + ']', e); } };
          __run(\(script.name.jsStringLiteral), function(){
        \(script.source)
          });
        })();
        """
    }

    private func styleBootstrapJS() -> String {
        let css = settings.appearance
        return """
        (function(){
          var c = globalThis.__wispCore; if (!c) { return; }
          c.setStyle('tokens', \(tokensCSS.jsStringLiteral));
          c.setStyle('theme', \(themeCSS.jsStringLiteral));
          c.setStyle('user', \(userCSS.jsStringLiteral));
          c.setHealthSelectors(\(Self.json(theme.healthSelectors)));
          \(CSSGenerator.attributesJS(appearance: css))
        })();
        """
    }

    // MARK: Live updates (no reload)

    func applyLiveStyles(to webView: WKWebView) {
        let js = """
        (function(){ var c = globalThis.__wispCore; if (!c) { return false; }
          c.setStyle('tokens', \(tokensCSS.jsStringLiteral));
          c.setStyle('theme', \(themeCSS.jsStringLiteral));
          c.setStyle('user', \(userCSS.jsStringLiteral));
          \(CSSGenerator.attributesJS(appearance: settings.appearance))
          return true; })();
        """
        webView.evaluateJavaScript(js, in: nil, in: ContentWorlds.core) { result in
            if case .failure(let error) = result { Log.warning("Live style apply failed: \(error.localizedDescription)", .injection) }
        }
    }

    /// Preview arbitrary CSS in the `user` slot without persisting it.
    func previewUserCSS(_ css: String, in webView: WKWebView) {
        let js = "(function(){ var c = globalThis.__wispCore; if (!c) { return false; } c.setStyle('user', \(css.jsStringLiteral)); return true; })();"
        webView.evaluateJavaScript(js, in: nil, in: ContentWorlds.core, completionHandler: nil)
    }

    nonisolated private static func json<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "[]"
    }
}
