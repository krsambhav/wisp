#!/bin/zsh
# Cut a release: bump the version, regenerate the project, commit + tag, build,
# sign, zip, push, and publish a GitHub Release with the zip attached. The app's
# in-app updater (UpdateManager) reads `releases/latest` from this repository.
#
# Usage: scripts/release.sh 1.2.0 [--notes "text"] [--identity "Developer ID Application"] [--notarize]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: release.sh <version>}"; shift
NOTES=""; IDENTITY="Apple Development"; EXTRA=()
while (( $# )); do
  case "$1" in
    --notes) NOTES="$2"; shift 2;;
    --identity) IDENTITY="$2"; shift 2;;
    --notarize) EXTRA+=(--notarize); shift;;
    *) echo "unknown arg $1"; exit 2;;
  esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be MAJOR.MINOR.PATCH"; exit 2; }
cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean"; git status --short; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "tag v$VERSION exists"; exit 1; }

BUILD_NO="$(( $(grep -E '^\s+CFBundleVersion:' Wisp/project.yml | sed -E 's/.*"([0-9]+)".*/\1/') + 1 ))"
sed -i '' -E "s/^(\s+CFBundleShortVersionString:) \"[^\"]+\"/\1 \"$VERSION\"/; s/^(\s+CFBundleVersion:) \"[0-9]+\"/\1 \"$BUILD_NO\"/" Wisp/project.yml
(cd Wisp && xcodegen generate -q)
git add Wisp/project.yml Wisp/Wisp.xcodeproj Wisp/Resources/Info.plist
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "Wisp $VERSION"

scripts/package-release.sh "$IDENTITY" "${EXTRA[@]}"
ZIP="dist/Wisp-$VERSION.zip"
[[ -f "$ZIP" ]] || { echo "missing $ZIP"; exit 1; }

git push origin HEAD "v$VERSION"
if [[ -n "$NOTES" ]]; then
  gh release create "v$VERSION" "$ZIP" --title "Wisp $VERSION" --notes "$NOTES"
else
  gh release create "v$VERSION" "$ZIP" --title "Wisp $VERSION" --generate-notes
fi
echo "Published: $(gh release view "v$VERSION" --json url -q .url)"
