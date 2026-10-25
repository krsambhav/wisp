# Building, signing and releasing

## Requirements

- macOS 14 or later (deployment target). Developed and verified on macOS 27 with Xcode 27 / Swift 6.4.
- Xcode 16 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## Build from source

`Wisp/project.yml` is the source of truth. The `.xcodeproj` is generated; do not hand-edit it, regenerate instead.

```sh
cd Wisp
xcodegen generate
open Wisp.xcodeproj          # scheme "Wisp"
```

Command line:

```sh
cd Wisp
xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Debug -derivedDataPath build build
xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Debug -derivedDataPath build-tests test
```

The built app is at `Wisp/build/Build/Products/Debug/Wisp.app`.

Targets: `Wisp` (application) and `WispTests` (XCTest, runs with the app as host). The `Wisp` scheme builds both and tests `WispTests`.

### Developer script

```sh
scripts/dev-run.sh          # regenerate, build Debug, launch against web.whatsapp.com
scripts/dev-run.sh --mock   # launch against the bundled mock page with the auto scenario
```

The mock run writes a WebKit snapshot of the page and PNGs of every native window to `~/Downloads/wisp-debug` (note: a sandboxed build can only write there if the directory is inside a location the sandbox allows; `~/Downloads/...` always works).

### Debug environment variables

Implemented in `Sources/Support/DebugHooks.swift` and `AccountSession`; compiled out of Release builds.

| Variable | Effect |
|---|---|
| `WISP_MOCK=1` | Load `Resources/Web/mock/whatsapp-mock.html` instead of WhatsApp Web. |
| `WISP_MOCK_QUERY=auto=1&dark=1` | Query string for the mock page. `auto=1` runs the scenario (unread 2 → notification → duplicate → download); `dark=1` starts in dark mode. |
| `WISP_DEBUG_DUMP=1` | 8 s after load, log web view geometry and a DOM summary (state, element counts, first 300 chars of text). |
| `WISP_DEBUG_SNAPSHOT=/path.png` | With `WISP_DEBUG_DUMP`, write a `WKWebView.takeSnapshot` PNG. Works even when the window is occluded or on another Space. |
| `WISP_DEBUG_OPEN_SETTINGS=<general\|appearance\|scripts\|notifications\|accounts\|advanced>` | Open Settings at that section after 3 s. |
| `WISP_DEBUG_WINDOW_DIR=/dir` | After 6 s, write a PNG of every visible window's native view hierarchy (web content shows blank; use the snapshot for it). |
| `WISP_DEBUG_QUIT_AFTER=<seconds>` | Terminate after N seconds. |
| `WISP_DEBUG_THEME=<default\|minimal\|midnight>` | Select a theme at launch (persisted like a user change). |
| `WISP_DEBUG_MODE=<system\|light\|dark>` | Set the appearance mode at launch. |

Debug builds also mirror the structured log to stderr. Pass variables with `open --env`:

```sh
open --env WISP_MOCK=1 --env WISP_MOCK_QUERY=auto=1 --stderr /tmp/wisp.err ~/Applications/Wisp.app
```

## Signing

The project signs **ad-hoc** by default (`CODE_SIGN_IDENTITY = "-"`), so it builds on any Mac. Two things do not work with an ad-hoc signature:

1. **Notifications.** macOS returns "Notifications are not allowed for this application" from `UNUserNotificationCenter` for ad-hoc signed apps. Re-sign the built app with a real Apple Development identity:

   ```sh
   scripts/sign-dev.sh                                   # signs Wisp/build/.../Wisp.app with "Apple Development"
   scripts/sign-dev.sh path/to/Wisp.app "Apple Development: you@example.com (TEAMID)"
   ```

   The script applies `Resources/Wisp.entitlements` and the hardened runtime.

2. **Never let an ad-hoc build ask for notification permission.** Verified in this session: once an ad-hoc signed copy requests authorization, the notification daemon records the refusal *against the bundle identifier* and keeps refusing even after the app is properly signed (a fresh minimal app using the same identifier was refused; the same app under a new identifier was granted). The user-level store (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) is TCC-protected, so the only practical recovery is a new bundle identifier. `NotificationBridge` therefore detects an ad-hoc signature at runtime (`SecCodeCopySigningInformation`, no Team ID) and skips the request, showing an explanation in Settings › Notifications instead. If you change the identifier in `project.yml`, do it before the first launch of a signed build.

   Keep one installed copy registered with LaunchServices and launch it via Finder or `open` (not by executing the binary), so the daemon resolves `app.wisp.desktop` to the signed copy:

   ```sh
   LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
   $LSR -u /path/to/stale/Wisp.app
   $LSR -f ~/Applications/Wisp.app
   ```

To sign from Xcode instead, set `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY: "Apple Development"` in `project.yml` and regenerate. `ENABLE_DEBUG_DYLIB` is disabled so Debug builds ship one real executable, which keeps code-signature identity checks simple.

### Entitlements

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | Wisp runs sandboxed; all data lives in its container. |
| `com.apple.security.network.client` | Load WhatsApp Web, websockets, media. |
| `com.apple.security.device.audio-input` | Voice messages and calls. |
| `com.apple.security.device.camera` | Camera capture in WhatsApp. |
| `com.apple.security.files.user-selected.read-write` | Attachments chosen in the open panel, "ask where to save" downloads, preset import/export. |
| `com.apple.security.files.downloads.read-write` | Default download location `~/Downloads`. |
| `com.apple.security.print` | Printing from the web view. |

`Info.plist` also declares `NSMicrophoneUsageDescription` and `NSCameraUsageDescription`.

## Release build, Developer ID, notarization

1. Set your team in `project.yml` (`DEVELOPMENT_TEAM`), regenerate, and make sure a "Developer ID Application" certificate is in your keychain.
2. Archive:

   ```sh
   cd Wisp
   xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Release \
     archive -archivePath build/Wisp.xcarchive \
     DEVELOPMENT_TEAM=TEAMID CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application"
   ```

3. Export with an `exportOptions.plist`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>method</key><string>developer-id</string>
     <key>teamID</key><string>TEAMID</string>
     <key>signingStyle</key><string>manual</string>
     <key>signingCertificate</key><string>Developer ID Application</string>
     <key>destination</key><string>export</string>
   </dict></plist>
   ```

   ```sh
   xcodebuild -exportArchive -archivePath build/Wisp.xcarchive \
     -exportOptionsPlist exportOptions.plist -exportPath build/export
   ```

   The hardened runtime is enabled in the project (`ENABLE_HARDENED_RUNTIME = YES`), which notarization requires.

4. Notarize and staple:

   ```sh
   cd build/export
   ditto -c -k --keepParent Wisp.app Wisp.zip
   xcrun notarytool submit Wisp.zip --keychain-profile "AC_PROFILE" --wait
   xcrun stapler staple Wisp.app
   ```

   Create the keychain profile once with `xcrun notarytool store-credentials "AC_PROFILE" --apple-id … --team-id TEAMID --password <app-specific-password>`.

5. Verify:

   ```sh
   spctl -a -vv Wisp.app
   codesign -dvv --entitlements - Wisp.app
   ```

6. Distribute the stapled `.app` in a zip or DMG. Users should move it to `/Applications` before first launch to avoid App Translocation.

## Publishing a release (in-app updater)

`UpdateManager` reads `https://api.github.com/repos/krsambhav/wisp/releases/latest` and compares the tag (`v1.2.3`) with `CFBundleShortVersionString`. The first asset named `Wisp*.zip` is downloaded into the sandbox container, extracted with `ditto`, checked with `SecStaticCodeCheckValidity` against the running app's Team ID and bundle identifier, swapped into place (rename old → rename new, old removed) and the app relaunches through a tiny `/bin/sh` helper that waits for the old process to exit. Files Wisp downloads itself carry no quarantine flag, so Gatekeeper does not re-prompt after an update.

```sh
scripts/release.sh 1.0.1 --notes "What changed"          # Apple Development signed (default)
scripts/release.sh 1.0.1 --identity "Developer ID Application" --notarize
```

The script refuses to run on a dirty tree or an existing tag. It bumps `CFBundleShortVersionString`/`CFBundleVersion` in `project.yml`, regenerates the project, commits "Release x.y.z", tags `vx.y.z`, runs `package-release.sh`, pushes, and calls `gh release create` with the zip. The updater only needs write access to the folder the app lives in: `/Applications` and `~/Applications` are covered by temporary-exception entitlements; anywhere else it asks once for the folder and keeps a security-scoped bookmark. Set `WISP_DEBUG_VERSION=0.9.0` on a Debug build to exercise the full path against a real release.
