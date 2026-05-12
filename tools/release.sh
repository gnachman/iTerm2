#!/bin/bash
# End-to-end MomenTerm release: archive → notarize-ready .zip → sign → appcast → GitHub Release.
# Designed to be re-run idempotently for the same tag; outputs are placed in build/release/.
#
# Prerequisites (one-time):
#   1. tools/sparkle_tools.sh        — builds sign_update from the Sparkle submodule.
#   2. Generate keys once:
#         build/sparkle-tools/generate_keys
#      then paste the printed base64 public key into plists/release-iTerm2.plist's
#      <key>SUPublicEDKey</key>. The matching private key lives in your login keychain
#      (Sparkle stores it under service "https://sparkle-project.org").
#   3. gh CLI authenticated:  gh auth login
#
# Usage:
#   tools/release.sh <version>            # e.g. 0.4.0 → tag "momenterm-v0.4.0"
#
# Outputs:
#   build/release/MomenTerm-<version>.zip
#   build/release/appcast.xml
#   GitHub release tagged "momenterm-v<version>" with both files attached.

set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "Usage: $0 <version>"
  exit 2
fi

VERSION="$1"
# Reject anything that isn't strict semver — sed substitutions below trust
# this value, so a hostile argument like "0.4|foo" would corrupt appcast.xml.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._A-Za-z0-9-]*)?$ ]]; then
  echo "error: version must look like X.Y.Z (got: $VERSION)" >&2
  exit 2
fi
TAG="momenterm-v$VERSION"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/build/release"
APP_NAME="MomenTerm"
SPARKLE_BIN="$REPO_ROOT/build/sparkle-tools"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT_DIR="$OUT/export"
ZIP="$OUT/$APP_NAME-$VERSION.zip"
APPCAST="$OUT/appcast.xml"

mkdir -p "$OUT"

# -- Sanity checks ----------------------------------------------------------

if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  echo "error: $SPARKLE_BIN/sign_update missing. Run tools/sparkle_tools.sh first." >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not on PATH." >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not on PATH." >&2
  exit 1
fi

REPO_SLUG=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
RELEASE_URL="https://github.com/$REPO_SLUG/releases/tag/$TAG"
ZIP_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$APP_NAME-$VERSION.zip"

# -- Build & export ---------------------------------------------------------

echo "[release] xcodebuild archive (Deployment / iTerm2 scheme)..."
xcodebuild -project "$REPO_ROOT/iTerm2.xcodeproj" \
           -scheme iTerm2 \
           -configuration Deployment \
           -archivePath "$ARCHIVE" \
           -quiet \
           archive

# Locate the produced .app inside the archive.
APP_PATH="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  # Fallback: look for any .app inside the archive
  APP_PATH=$(find "$ARCHIVE/Products/Applications" -name "*.app" -maxdepth 1 -type d | head -n 1)
fi
if [ ! -d "$APP_PATH" ]; then
  echo "error: no .app inside $ARCHIVE" >&2
  exit 1
fi

echo "[release] zipping $APP_PATH..."
rm -rf "$EXPORT_DIR" && mkdir -p "$EXPORT_DIR"
cp -R "$APP_PATH" "$EXPORT_DIR/"
ditto -c -k --keepParent "$EXPORT_DIR/$(basename "$APP_PATH")" "$ZIP"

ZIP_LENGTH=$(stat -f%z "$ZIP")

# -- Sign with EdDSA --------------------------------------------------------

echo "[release] signing zip..."
# sign_update writes "sparkle:edSignature=... length=..." to stdout
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP")
SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
if [ -z "$SIGNATURE" ]; then
  echo "error: failed to extract signature from: $SIGN_OUTPUT" >&2
  exit 1
fi

# -- Render appcast ---------------------------------------------------------

PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
BUILD=$(date "+%Y%m%d%H%M")

sed -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD|g" \
    -e "s|__PUBDATE__|$PUBDATE|g" \
    -e "s|__ZIP_URL__|$ZIP_URL|g" \
    -e "s|__ZIP_LENGTH__|$ZIP_LENGTH|g" \
    -e "s|__SIGNATURE__|$SIGNATURE|g" \
    -e "s|__RELEASE_URL__|$RELEASE_URL|g" \
    "$REPO_ROOT/tools/appcast.template.xml" > "$APPCAST"

echo "[release] appcast written to $APPCAST"

# -- Publish to GitHub ------------------------------------------------------

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "[release] tag $TAG already exists — uploading assets only."
  gh release upload "$TAG" "$ZIP" "$APPCAST" --clobber
else
  echo "[release] creating GitHub release $TAG..."
  gh release create "$TAG" \
     --title "MomenTerm $VERSION" \
     --notes "Automated release. See CHANGELOG or git log for details." \
     "$ZIP" "$APPCAST"
fi

echo
echo "Done. Sparkle clients will see this release at:"
echo "  $RELEASE_URL"
echo "Appcast feed (latest):"
echo "  https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml"
