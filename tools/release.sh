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
# The Deployment build config still references the upstream iTerm2 author's
# Developer ID. Until we sign up for our own Apple Developer cert, override
# with ad-hoc so the archive succeeds. Sparkle still verifies via EdDSA,
# users see the unidentified-developer warning once on first launch (same
# as the share.sh hand-off path).
xcodebuild -project "$REPO_ROOT/iTerm2.xcodeproj" \
           -scheme iTerm2 \
           -configuration Deployment \
           -archivePath "$ARCHIVE" \
           -quiet \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGN_STYLE=Manual \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           DEVELOPMENT_TEAM= \
           ARCHS=arm64 \
           ONLY_ACTIVE_ARCH=YES \
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
# The Deployment build setting still emits iTerm2.app as the bundle dir
# name even though CFBundleName/Executable inside are MomenTerm. Rename
# so end users see MomenTerm.app in Finder/Dock.
APP_LOCAL="$EXPORT_DIR/$(basename "$APP_PATH")"
APP_FINAL="$EXPORT_DIR/$APP_NAME.app"
if [ "$APP_LOCAL" != "$APP_FINAL" ]; then
  mv "$APP_LOCAL" "$APP_FINAL"
fi
ditto -c -k --keepParent "$APP_FINAL" "$ZIP"

ZIP_LENGTH=$(stat -f%z "$ZIP")

# -- Sign with EdDSA --------------------------------------------------------

echo "[release] signing zip..."
# This Sparkle vintage's sign_update wants the base64(privKey+pubKey) as
# arg 2. generate_keys stashes that blob in the login keychain under
# service=https://sparkle-project.org, account=ed25519. Pull it out at
# call time so we never have to write the secret to disk.
SPARKLE_KEY="$(security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w 2>/dev/null)"
if [ -z "$SPARKLE_KEY" ]; then
  echo "error: no Sparkle ed25519 key in keychain. Run build/sparkle-tools/generate_keys first." >&2
  exit 1
fi
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP" "$SPARKLE_KEY")"
if [ -z "$SIGNATURE" ]; then
  echo "error: sign_update produced no signature." >&2
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

# -- Render Korean release notes for the GitHub Release page ----------------

ZIP_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
NOTES_FILE="$OUT/release_notes.md"
CHANGELOG_FILE="$OUT/changelog.txt"
PREV_TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 --exclude="$TAG" 2>/dev/null || echo "")"
if [ -n "$PREV_TAG" ]; then
  git -C "$REPO_ROOT" log "$PREV_TAG"..HEAD --pretty='- %s' | head -n 50 > "$CHANGELOG_FILE"
else
  git -C "$REPO_ROOT" log -1 --pretty='- %s' > "$CHANGELOG_FILE"
fi

# sed for scalar fields; awk reads CHANGELOG from a file because `awk -v
# cl=...` chokes on newlines in the assignment.
sed -e "s|__VERSION__|$VERSION|g" \
    -e "s|__GIT_DESCRIBE__|$GIT_DESCRIBE|g" \
    -e "s|__PUBDATE__|$PUBDATE|g" \
    -e "s|__ZIP_NAME__|$(basename "$ZIP")|g" \
    -e "s|__SHA256__|$ZIP_SHA256|g" \
    "$REPO_ROOT/tools/RELEASE_BODY.md.template" \
  | awk -v clfile="$CHANGELOG_FILE" '
      BEGIN {
        cl = ""
        while ((getline line < clfile) > 0) {
          cl = (cl == "") ? line : cl "\n" line
        }
        close(clfile)
      }
      { gsub(/__CHANGELOG__/, cl); print }
    ' \
  > "$NOTES_FILE"

echo "[release] release notes written to $NOTES_FILE"

# -- Publish to GitHub ------------------------------------------------------

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "[release] tag $TAG already exists — uploading assets only."
  gh release upload "$TAG" "$ZIP" "$APPCAST" --clobber
  gh release edit "$TAG" --notes-file "$NOTES_FILE"
else
  echo "[release] creating GitHub release $TAG..."
  gh release create "$TAG" \
     --title "MomenTerm $VERSION" \
     --notes-file "$NOTES_FILE" \
     "$ZIP" "$APPCAST"
fi

echo
echo "Done. Sparkle clients will see this release at:"
echo "  $RELEASE_URL"
echo "Appcast feed (latest):"
echo "  https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml"
