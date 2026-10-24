# Known limitations

Honest list of what Wisp cannot do, or cannot guarantee, because of WebKit, WhatsApp Web, or macOS.

## Notifications

- **WKWebView has no Web Notifications API.** Wisp installs a `Notification` polyfill in the page so WhatsApp's own notification code runs and is forwarded to Notification Center. Delivery depends on WhatsApp's JavaScript, so notifications arrive only while the account's session is loaded, connected, and the Mac is awake. There is no server-side push; if Wisp is quit or the Mac sleeps, nothing is delivered until the session reconnects.
- **Double sound.** WhatsApp plays its own in-page sound in addition to the native notification sound. Set Wisp's sound to "None" or turn off sounds in WhatsApp › Settings › Notifications.
- **Ad-hoc builds cannot post notifications, and must not ask.** macOS refuses `UNUserNotificationCenter` for ad-hoc signed apps and permanently records that refusal against the bundle identifier. Wisp skips the request for ad-hoc builds and says so in Settings › Notifications. See `BUILD.md` › Signing.
- Focus and Do Not Disturb are enforced by the system; Wisp does not inspect Focus state.
- Suppression while the account is in front uses "window is key + app active"; a notification can still slip through in the instant between a message arriving and WhatsApp noticing focus.

## Appearance

- **Light/dark follows WhatsApp's own theme setting** unless it is set to "System default". Wisp changes the web view's `NSAppearance` (which drives `prefers-color-scheme`); it does not rewrite WhatsApp's stored preference. Wisp's token overrides adapt to whichever scheme WhatsApp actually applies.
- The pre-login landing page ignores dark mode, so Wisp's header can look darker than the page until you are logged in. Midnight is a dark theme and forces dark appearance.
- **Selector-based refinements can drift.** Bubble radius, density tweaks, sidebar width, row hover and the scrollbar styling depend on structural hooks (`#app`, `#side`, `#main`, `#pane-side`, `.message-in`, `.message-out`, `.copyable-text`). WhatsApp changes its markup regularly. The token layer (colors) survives such changes; selector rules simply stop matching. Settings › Advanced › "Theme hook check" shows which hooks were missing after the last login.
- **Compact density does not change chat-list row height.** The chat list is a virtualized list whose row height WhatsApp sets inline; changing it would break scrolling. Compact only tightens message spacing, headers and the composer.
- Hiding the chat wallpaper doodle in Minimal and Midnight works by setting the doodle color equal to the background; if WhatsApp changes the wallpaper implementation the doodle may reappear.
- Interface scale uses WebKit page zoom, which scales everything, not only text. Message text size is a separate multiplier that targets `.copyable-text .selectable-text`.

## Verification scope

- The post-login UI (chat list, bubbles, composer, notifications, badges, selector check) was verified against a bundled mock page that mirrors WhatsApp Web's DOM structure and design-token names captured from the live stylesheet on 2026-10-25, not against a linked account. Expect to adjust `themes/*.css` after a WhatsApp redesign.
- WhatsApp shows a "Download WhatsApp for Mac" banner on the login page because it detects Safari. It is harmless.

## Calls, media, service workers

- **Voice and video calls.** WebRTC and media capture work in WKWebView, but WhatsApp enables calling per browser and may not offer it under a Safari user agent. Treat calling as unsupported until WhatsApp enables it for Safari.
- **Service workers** are available in WKWebView on macOS only for App-Bound Domains, which Wisp does not enable (it would restrict every navigation and JavaScript injection to a fixed list). WhatsApp Web functions without a service worker; offline caching of the shell is lost.
- Microphone and camera require granting permission to Wisp when WhatsApp first asks; denying in System Settings disables voice messages and calls until re-enabled.
- Screen sharing from calls is not available in WKWebView.

## Accounts and data

- Account avatars and names are set in Wisp; the WhatsApp profile photo is not scraped from the page.
- Removing an account deletes its WebKit data store; WhatsApp's "Linked devices" list on the phone still shows the device until you unlink it there.
- Accounts not marked "connect at launch" are not loaded until you first open them, so they receive no notifications before that. Once opened, a session stays alive for the rest of the run and switching between accounts is instant.

## Platform

- No Spotlight, Handoff, Shortcuts or Share extension integration.
- Running Wisp from a non-standard location after downloading it (quarantined) can trigger App Translocation, which breaks the sandbox container path and launch at login. Move the app to `/Applications` first. Unsigned or ad-hoc builds are for local development only.
- The Settings window uses SwiftUI's `Settings` scene and therefore has a standard title bar rather than Wisp's custom header.
- `Cmd+F` focuses WhatsApp's search box by trying a short list of selectors and falls back to WhatsApp's own `⌘⌥/` shortcut; if WhatsApp renames both, the command does nothing.
