#!/bin/zsh
# Build a Release Wisp.app, sign it, and zip it for sharing.
#
# Usage: scripts/package-release.sh [identity-substring]
#   identity defaults to "Apple Development". Pass "Developer ID Application"
#   once you have a paid Apple Developer account; add --notarize to also notarize
#   (requires `xcrun notarytool store-credentials wisp-notary` to have been run).
#
# Output: dist/Wisp-<version>.zip (ditto-created, preserves the bundle's
# resource forks and code signature; safe to send over AirDrop/Drive/etc.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${1:-Apple Development}"
NOTARIZE=0
for arg in "$@"; do [[ "$arg" == "--notarize" ]] && NOTARIZE=1; done
[[ "$IDENTITY" == "--notarize" ]] && IDENTITY="Developer ID Application"

DERIVED="$ROOT/Wisp/build-release"
APP="$DERIVED/Build/Products/Release/Wisp.app"
ENTITLEMENTS="$ROOT/Wisp/Resources/Wisp.entitlements"

echo "▸ Building Release…"
xcodebuild -project "$ROOT/Wisp/Wisp.xcodeproj" -scheme Wisp -configuration Release \
  -derivedDataPath "$DERIVED" build -quiet

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT_DIR="$ROOT/dist"
ZIP="$OUT_DIR/Wisp-$VERSION.zip"
mkdir -p "$OUT_DIR"

echo "▸ Signing with '$IDENTITY'…"
"$ROOT/scripts/sign-app.sh" "$APP" "$IDENTITY" --timestamp

echo "▸ Zipping…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if (( NOTARIZE )); then
  echo "▸ Notarizing…"
  xcrun notarytool submit "$ZIP" --keychain-profile wisp-notary --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo
echo "Done: $ZIP ($(du -h "$ZIP" | cut -f1))"
spctl --assess --type execute -vv "$APP" 2>&1 | sed 's/^/  gatekeeper: /' || true
