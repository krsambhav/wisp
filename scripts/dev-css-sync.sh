#!/bin/zsh
# Copy theme CSS from the repo into the sandbox-readable hot-reload directory and
# request a snapshot. Usage: scripts/dev-css-sync.sh [--snap]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DBG="$HOME/Downloads/wisp-debug"
mkdir -p "$DBG/themes"
for f in "$ROOT"/Wisp/Resources/Web/themes/*.css; do cp "$f" "$DBG/themes/.$(basename "$f").tmp" && mv "$DBG/themes/.$(basename "$f").tmp" "$DBG/themes/$(basename "$f")"; done
if [[ "${1:-}" == "--snap" ]]; then sleep 1.5; rm -f "$DBG/snap.png"; touch "$DBG/snap.request"; sleep 4; ls "$DBG/snap.png"; fi
