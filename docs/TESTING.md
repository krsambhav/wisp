# Testing

## Automated

```sh
cd Wisp
xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Debug -derivedDataPath build-tests test
```

`WispTests` (21 tests, all passing in this session) covers: unread title parsing, notification dedupe window, `HexColor` parsing / HSL / Codable, CSS token generation and validation for every theme in both schemes, accent derivation, script header round-trip, plain `.js` adoption, JavaScriptCore syntax check, the error-capturing wrapper, preset round-trip and rejection of foreign JSON, user agent shape, JS string escaping.

## Mock scenario

`scripts/dev-run.sh --mock` (or the env vars in `BUILD.md`) loads `Resources/Web/mock/whatsapp-mock.html`, which mirrors WhatsApp Web's structure (`#app`, `#side`, `#pane-side`, `#main`, `.message-in/.message-out`, `.copyable-text`, WDS token names, `body.dark`). With `auto=1` it switches from a QR landing to chats, sets the title to `(2) WhatsApp`, fires a `Notification` with a blob icon, fires a duplicate, and triggers a blob `<a download>`. Toolbar buttons allow the same actions manually plus upload, external link, dark toggle and a thrown error.

## Checklist

Legend: **verified (auto)** = exercised in this session with logs or snapshots; **mock** = verified against the mock page; **manual** = needs a linked phone.

| # | Test | How | Status / expected |
|---|---|---|---|
| 1 | First launch and QR authentication | Launch, scan the QR with the phone (Linked devices). | **verified visually** that WhatsApp Web loads to the "Scan to log in" page with a live QR in WKWebView using the Safari-style user agent; the header shows "Scan QR to link". Completing the scan is **manual**. |
| 2 | Quit and relaunch without losing the session | ⌘Q, relaunch. | Per-account `WKWebsiteDataStore(forIdentifier:)` persists cookies/IndexedDB; nothing is cleared on terminate (`applicationWillTerminate` only saves settings). **manual** confirmation after linking. Mock: the file-based page reloads with the same store. |
| 3 | Send and receive messages | Chat normally. | Uses WhatsApp Web unchanged. **manual**. |
| 4 | Receive a notification while the window is hidden | ⌘W, receive a message. | Polyfill → native banner. **Verified on mock** with a signed build: authorization granted, `Notification delivered`, duplicate within 4 s suppressed, dock badge 2, `Notification.close()` withdraws. Real-message delivery while hidden is **manual** (needs a linked phone). |
| 5 | Open the app from a notification | Click the banner. | `onActivate` activates the account, shows the window and calls `__wispNotify.click(id)`, which runs WhatsApp's own `onclick` to open the chat. Banner click is **manual**; the mock page records the click in `data-opened-chat`. |
| 6 | Upload and download attachments | Attach a file; download media. | Open panel via `runOpenPanelWith` (mock "upload" button opens it). Download **verified (auto)**: blob `<a download>` → `WKDownload` → `~/Downloads/wisp-mock-download.txt` (31 bytes), toast and log "Download finished". |
| 7 | Record and play voice messages | Hold the mic button; play back. | `requestMediaCapturePermissionFor` grants after `AVCaptureDevice.requestAccess`; playback needs no gesture. **manual**. |
| 8 | Switch themes without reloading | Settings › Appearance, pick a theme. | **mock, verified**: Default, Minimal and Midnight snapshots taken via `WKWebView.takeSnapshot` show the correct tokens with no navigation. Observation-driven live apply. |
| 9 | Inject and disable custom CSS | Type CSS in Settings › Appearance; toggle "Enable custom CSS". | Live preview updates the `user` style slot; disabling injects an empty stylesheet. Validation flags unbalanced braces. **mock** (same code path as themes). |
| 10 | Inject and disable custom JavaScript | Settings › Scripts › New Script, Save & Reload; toggle. | **Verified on mock**: an imported script ran in the isolated world (`wisp.log` → `[script:Debug probe] hello from user script`, DOM attribute set), and disabling it removes it from the next load (`Injecting 0 user script(s)`). Scripts take effect on the next reload (⌘R). |
| 11 | Recover from malformed CSS/JS | Enter `a {` or `const = ;`. | CSS: the brace validator warns in the editor and the browser ignores the invalid rule; the token layer is unaffected. JS: the editor shows the JavaScriptCore syntax error and the script is not injected; a runtime `throw` is caught by the `wisp.__run` wrapper — **verified on mock** (`[ERROR] [script:Debug probe] Error: boom from user script (@user-script:15:6:16)`) with WhatsApp unaffected. |
| 12 | Switch between isolated accounts | Settings › Accounts › Add; ⌘1/⌘2. | Separate data store identifiers; the header switcher re-parents the other web view; unread badge per account. Store logic **verified (auto)** (accounts.json); switching UI **manual**. |
| 13 | Restore after network disconnection | Turn Wi-Fi off and on. | Failed loads show the offline overlay and retry with backoff; `NWPathMonitor` triggers an immediate retry when the path is satisfied again. WhatsApp's own websocket reconnects after load. **manual**. |
| 14 | CPU and memory during idle and active use | Activity Monitor / Instruments. | Measured in this session on the real QR page (Debug build, M-series): environment ready ≈ 120–160 ms, window visible ≈ 200–280 ms after that; app process 0.0 % CPU idle, 54 MB physical footprint (131 MB RSS); WhatsApp's WebContent process ≈ 365 MB RSS at 1.5–2.8 % CPU, which is the page itself (QR refresh). Four WebKit helper processes are added per loaded account. Post-login numbers are **manual**. |

## Reproducing the session's checks

```sh
# themes
for t in default:light minimal:light midnight:dark; do
  open --env WISP_MOCK=1 --env "WISP_MOCK_QUERY=auto=1&dark=$([[ ${t#*:} == dark ]] && echo 1 || echo 0)" \
       --env WISP_DEBUG_DUMP=1 --env WISP_DEBUG_SNAPSHOT=$HOME/Downloads/wisp-debug/${t%:*}.png \
       --env WISP_DEBUG_THEME=${t%:*} --env WISP_DEBUG_MODE=${t#*:} --env WISP_DEBUG_QUIT_AFTER=14 \
       --stderr /tmp/wisp.err ~/Applications/Wisp.app; sleep 16
done
grep -E "Page state|Badge|Duplicate|selector|Download" /tmp/wisp.err
```

Expected log lines: `Page state → Waiting for QR scan`, `Page state → Connected`, `Badge total=2 dock=2`, `Theme selector check: all 6 hooks present`, `Notification delivered`, `Duplicate notification suppressed`, `Download finished: wisp-mock-download.txt`.
