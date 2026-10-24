#!/bin/zsh
# Build (Debug) and run Wisp with development hooks. Usage:
#   scripts/dev-run.sh            # real WhatsApp
#   scripts/dev-run.sh --mock     # bundled mock page with auto scenario + snapshots in $HOME/Downloads/wisp-debug
set -euo pipefail
cd "$(dirname "$0")/../Wisp"
xcodegen generate >/dev/null
xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD" || true
APP="build/Build/Products/Debug/Wisp.app"
pkill -x Wisp 2>/dev/null || true
if [[ "${1:-}" == "--mock" ]]; then
  mkdir -p $HOME/Downloads/wisp-debug
  WISP_MOCK=1 WISP_MOCK_QUERY=auto=1 WISP_DEBUG_DUMP=1 WISP_DEBUG_SNAPSHOT=$HOME/Downloads/wisp-debug/page.png \
  WISP_DEBUG_WINDOW_DIR=$HOME/Downloads/wisp-debug "$APP/Contents/MacOS/Wisp"
else
  "$APP/Contents/MacOS/Wisp"
fi
