# Architecture

Wisp is a native macOS shell around one persistent `WKWebView` per WhatsApp account. The native layer owns windows, accounts, notifications and preferences; the web layer is touched only through versioned CSS/JS injection and a small, validated message bridge.

## Module map

All sources live in `Wisp/Sources/`.

| Module | Contents |
|---|---|
| `App/` | `WispApp` (SwiftUI `@main`, Settings scene, menu commands), `AppDelegate` (lifecycle, reopen, terminate), `AppEnvironment` (composition root), `Commands` (main menu). |
| `Accounts/` | `Account` (model), `AccountStore` (accounts.json), `AccountSession` (runtime: web view, page state, unread, bridge callbacks), `SessionManager` (lazy creation, switching, background pinning, fan-out). |
| `Web/` | `WebViewFactory` (configuration, data store, user agent), `WebViewCoordinator` (navigation + UI delegate: policy, uploads, media permission, JS dialogs), `DownloadManager` (`WKDownloadDelegate`), `WebViewContainer` (SwiftUI host), `UserAgent`. |
| `Injection/` | `InjectionEngine` (builds `WKUserScript`s, live style updates), `ScriptMessageRouter` (validates bridge messages), `ContentWorlds` (world + handler names). |
| `Customization/` | `Theme`/`ThemePalette`, `ThemeCatalog` (built-ins), `CSSGenerator` (tokens → CSS), `CustomScript`/`ScriptStore` (user scripts, hot reload), `CustomCSSStore`, `PresetIO`. |
| `Updates/` | `UpdateManager` (GitHub Releases check, state machine, scheduling), `UpdateInstaller` (download, extract, signature verification, XPC call). The swap/relaunch lives in `Wisp/Helper` (unsandboxed `WispUpdateHelper.xpc`); the shared `@objc` protocol and the libproc walker `ProcessTable` are in `Wisp/Shared`. |
| `Notifications/` | `NotificationBridge` (`UNUserNotificationCenter`), `NotificationDeduper`, `UnreadTitleParser`. |
| `Platform/` | `MainWindowController` (AppKit window), `MenuBarController` (`NSStatusItem`), `GlobalHotKeyManager` (Carbon hot key), `LaunchAtLogin` (`SMAppService`), `NetworkMonitor` (`NWPathMonitor`), `ResourceMonitor` (live CPU/memory for the app's resource coalition, sampled through the unsandboxed helper because the sandbox denies `proc_pid_rusage` for other pids; falls back to in-process `PROC_PIDTASKINFO`; runs for the app's lifetime at 2 s / 10 s / 30 s depending on whether the meter, a window, or nothing is on screen, and feeds the opt-in idle free-up in `AppEnvironment`: only while the kernel reports memory pressure, after 15 min in the background above 1.5 GB, pages restart in a fresh WebContent process unless a draft, dialog, transfer or playing media would be lost; off by default because the restart shows WhatsApp's loading screen on return). |
| `Settings/` | `SettingsStore` (settings.json, debounced save) and one SwiftUI view per section (General, Appearance, Scripts, Notifications, Accounts, Advanced). |
| `UI/` | Design tokens, shadcn-style components (`WCard`, `WRow`, `WButton`, `WSegmented`, …), `CodeEditorView` (NSTextView + regex highlighter + line numbers), `HotKeyRecorderView`, `MainShellView`, `HeaderBar`, `AccountSwitcher`, `ResourceMeter` (header CPU/RAM sparkline + details popover), toasts. |
| `Support/` | `Log` (os.Logger + in-memory diagnostics ring buffer), `Paths`, `Debouncer`, `HexColor`, extensions, `DebugHooks` (DEBUG-only automation). |

Resources: `Wisp/Resources/Web/` holds the injected scripts (`wisp-page.js`, `wisp-core.js`, `wisp-user-runtime.js`), the theme stylesheets (`themes/base.css`, `default.css`, `minimal.css`, `midnight.css`) and the development fixture (`mock/whatsapp-mock.html`).

## Launch and data flow

1. `AppEnvironment.shared` is created lazily on first access (the SwiftUI scene body may run before the delegate's launch callbacks). It constructs stores (`SettingsStore`, `AccountStore`, `ScriptStore`, `CustomCSSStore`), the `InjectionEngine`, `NotificationBridge`, `DownloadManager`, `NetworkMonitor`, then `SessionManager`, `MainWindowController` and `MenuBarController`, wires callbacks, and starts observation.
2. `SessionManager` picks the last active account and creates an `AccountSession` for it and for every account marked "connect at launch". Other accounts get a session only when activated; switching away from an unpinned account tears its web view down.
3. `AccountSession.webView` lazily builds the `WKWebView` through `WebViewFactory`: a `WKWebsiteDataStore(forIdentifier:)` per account, `applicationNameForUserAgent` set to a Safari-style `Version/x Safari/605.1.15` suffix (WhatsApp treats the bare WKWebView UA as an unsupported browser), media playback without user gesture, and the injection engine's scripts and handlers.
4. `MainShellView` hosts the active session's web view through `WebViewContainer`, which only re-parents the existing view. Settings is a separate SwiftUI scene; the web view is never recreated.

## Injection layering

All scripts are main-frame only.

| Layer | World | Time | Purpose |
|---|---|---|---|
| `wisp-page.js` | page | document start | `Notification` polyfill. The only native handler reachable from the page world is `wispNotify`. |
| `wisp-core.js` | `wisp.core` (isolated) | document start | Owns the `<style data-wisp>` elements (tokens → theme → user), keeps them last in `<head>`, detects page state (loading / qr / chats) with one debounced `MutationObserver` (bubble tagging runs once per frame and only after an element was added), runs a one-shot selector health check after login, provides `focusSearch()`. |
| style bootstrap | `wisp.core` | document start | Generated by `InjectionEngine`: injects tokens CSS, theme CSS, user CSS, health selectors and `data-wisp-*` attributes. |
| `wisp-user-runtime.js` | `wisp.user` and/or page | document start | `wisp.log/warn/error` and `wisp.__run(name, fn)` for error capture. Only injected into worlds that host at least one enabled script. |
| user scripts | `wisp.user` or page | start or end | Each wrapped in `wisp.__run` so an exception is logged and cannot break other scripts or the page. Scripts with syntax errors are excluded before injection. |

Isolated worlds share the DOM with WhatsApp but not its JavaScript objects, so WhatsApp cannot see `__wispCore` or `wisp`.

### Bridge message handlers

| Handler | Registered in | Payload |
|---|---|---|
| `wispNotify` | page only | `{kind: show|close, id, title, body, tag, icon(data URL), silent}` |
| `wispState` | core | `{state}` |
| `wispDiag` | core | `{kind: selectors, total, missing[]}` |
| `wispLog` | core, user, page | `{level, source, message}` |

`ScriptMessageRouter` holds the session weakly (the content controller retains its handlers), accepts only main-frame messages from a `whatsapp.com` origin (or `file:` in mock mode), checks the world for `wispNotify`, and truncates every string before use.

## Theme pipeline

`Theme` has a light and a dark `ThemePalette` of plain colors. `CSSGenerator.tokensCSS` emits:

- `--wisp-*` variables for both schemes (used by the bundled stylesheets and custom CSS);
- overrides of WhatsApp's own tokens, both the current `--WDS-*` generation (accent, surfaces, content, lines, bubbles, chat wallpaper, composer) and the legacy flat names (`--panel-background`, `--incoming-background`, …), declared on `html` for light and on `html.dark, body.dark, html[data-theme="dark"]` for dark.

Every override carries `!important`. WhatsApp defines its tokens on `html` through hashed classes such as `.x15xz1xp.x15xz1xp:root` (specificity 0,3,0) and swaps those classes per theme. Importance wins that cascade regardless of specificity, and because custom properties inherit, a value declared on `body.dark` reaches every element inside the page. Dark detection relies on WhatsApp's `body.dark`, which is why Wisp sets the web view's `NSAppearance` rather than editing WhatsApp's own theme preference.

`base.css` plus the theme's stylesheet add selector-based refinements (scrollbars, hairlines, bubble radius via `html[data-wisp-bubbles]`, density via `html[data-wisp-density]`, sidebar width via `html[data-wisp-sidebar]`). These depend on structural hooks and degrade silently if a hook disappears; the one-shot health check reports missing hooks to the diagnostics log and Settings › Advanced.

Accent overrides re-derive emphasized/deemphasized variants and the outgoing bubble tint in `CSSGenerator.resolved`.

## Live updates

`AppEnvironment.startObservingSettings` uses `withObservationTracking` and re-arms after each change. Appearance changes push new CSS into every loaded web view (`__wispCore.setStyle`) and adjust the view appearance and page zoom; custom CSS edits apply when live preview is on; script changes replace the user scripts on the content controller (effective on next navigation); developer tools and hot reload toggles apply immediately. There are no timers or polling loops in the app; the only recurring work is the retry backoff after a failed load.

## Notifications

1. WhatsApp calls `new Notification(title, {body, tag, icon})`. The polyfill resolves the `blob:` icon to a small data URL and posts `wispNotify`.
2. `AccountSession` forwards to `NotificationBridge.deliver`, which checks global and per-account settings, the "suppress while in front" rule, and a 4-second dedupe window keyed by account + title + body + tag.
3. A `UNNotificationRequest` is posted with identifier `acct=<uuid>;tag=<tag>` so repeated notifications for the same chat replace each other. The avatar becomes a `UNNotificationAttachment`.
4. On click, the app activates the account and window and evaluates `__wispNotify.click(id)` in the page world, which dispatches the `click` event and calls the `onclick` handler WhatsApp itself installed, so WhatsApp opens the chat.
5. When WhatsApp closes a notification (chat read), the polyfill posts `close` and delivered notifications for that account are withdrawn.

Unread counts come from KVO on `WKWebView.title`: WhatsApp sets `"(N) WhatsApp"`. The total across sessions drives the Dock badge and the menu bar count.

## Downloads, uploads, links

- `decidePolicyFor navigationAction` returns `.download` when `shouldPerformDownload` is set (`<a download>` / blob links); `decidePolicyFor navigationResponse` returns `.download` for unshowable MIME types or `Content-Disposition: attachment`. `DownloadManager` picks a unique name in `~/Downloads` (or asks), then shows a toast and, when the app is in the background, a notification.
- `runOpenPanelWith` presents `NSOpenPanel` for attachments.
- Main-frame navigations to non-first-party hosts and `window.open` targets are handed to `NSWorkspace` and cancelled, so the chat view never leaves WhatsApp.
- `requestMediaCapturePermissionFor` grants microphone/camera for `whatsapp.com` after `AVCaptureDevice.requestAccess`.

## Window and system integration

- `MainWindowController` creates an `NSWindow` with `.fullSizeContentView`, hidden title, transparent title bar and an empty `NSToolbar` in `.unified` style so the title bar is 52 pt and the traffic lights sit centered in Wisp's header. Frame autosave restores size and position; `windowShouldClose` hides instead of closing when "keep running" is on; the window background follows the theme so nothing flashes white.
- `MenuBarController` manages an `NSStatusItem` (left click toggles the window, right click opens the menu) and the activation policy for menu bar mode.
- `GlobalHotKeyManager` registers the shortcut with Carbon `RegisterEventHotKey`, which works in the sandbox without Accessibility permission.
- `LaunchAtLogin` wraps `SMAppService.mainApp`; the system is the source of truth for the toggle.

## Concurrency model

Swift 6 language mode with strict concurrency and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Everything with UI or WebKit lifetime is main-actor isolated; pure value types (`HexColor`, `Theme`, settings structs, `CustomScript`, `Account`, parsers, `CSSGenerator`) are marked `nonisolated` so they can be used from any context and in tests. Delegate callbacks from WebKit and AppKit arrive on the main actor; `UNUserNotificationCenterDelegate` methods are `nonisolated` and hop to the main actor explicitly.
