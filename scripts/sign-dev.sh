#!/bin/zsh
# Re-sign a built Wisp.app with a real Apple Development identity so macOS allows
# notifications and the sandbox container is attributed to your team.
# Usage: scripts/sign-dev.sh [path/to/Wisp.app] [identity-substring]
set -euo pipefail
APP="${1:-$(dirname "$0")/../Wisp/build/Build/Products/Debug/Wisp.app}"
IDENTITY="${2:-Apple Development}"
ENTITLEMENTS="$(dirname "$0")/../Wisp/Resources/Wisp.entitlements"
codesign --force --deep --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "Signed: $APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority|TeamIdentifier" | head -2
