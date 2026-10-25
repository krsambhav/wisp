#!/bin/zsh
# Sign Wisp.app inside-out. The XPC update helper must NOT inherit the app's
# sandbox entitlement (it clears quarantine and swaps the bundle), so it is
# signed first with hardened runtime only, then the app itself without --deep.
# Usage: scripts/sign-app.sh <Wisp.app> <identity> [extra codesign flags…]
set -euo pipefail
APP="$1"; IDENTITY="$2"; shift 2
ENTITLEMENTS="$(dirname "$0")/../Wisp/Resources/Wisp.entitlements"
for xpc in "$APP"/Contents/XPCServices/*.xpc(N); do
  codesign --force --options runtime "$@" --sign "$IDENTITY" "$xpc"
done
codesign --force --options runtime "$@" --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "Signed: $APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority|TeamIdentifier" | head -2
