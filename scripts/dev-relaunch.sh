#!/bin/zsh
# Quit Wisp gracefully (pages unloaded first), wait for the process to exit,
# then install the Debug build and relaunch it with dev hooks. Never overlaps
# two instances on the same WebKit storage.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/Wisp/build/Build/Products/Debug/Wisp.app"
APP_DST="$HOME/Applications/Wisp.app"
DBG="$HOME/Downloads/wisp-debug"; mkdir -p "$DBG"
if pgrep -x Wisp >/dev/null; then
  pkill -TERM -x Wisp
  for i in {1..60}; do pgrep -x Wisp >/dev/null || break; sleep 0.5; done
  if pgrep -x Wisp >/dev/null; then echo "Wisp did not exit (sync guard?). Aborting." >&2; exit 1; fi
fi
rm -rf "$APP_DST" && cp -R "$APP_SRC" "$APP_DST"
: > /tmp/wisp.err
mkdir -p "$DBG/themes" && cp "$ROOT"/Wisp/Resources/Web/themes/*.css "$DBG/themes/"
open --env WISP_DEBUG_THEME_DIR="$DBG/themes" --env WISP_DEBUG_SNAPSHOT_DIR="$DBG" "$@" --stderr /tmp/wisp.err "$APP_DST"
echo "relaunched (theme hot-reload from repo, snapshots via touch $DBG/snap.request)"
