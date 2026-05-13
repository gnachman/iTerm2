#!/bin/bash
# Build MomenTerm and bundle it for a one-off share with another Mac user.
# Produces build/share/MomenTerm-<version>.zip plus a Korean INSTALL.md the
# recipient can follow to get past Gatekeeper without an Apple Developer
# notarisation step.
#
# Usage:
#   tools/share.sh                 # Development build (fast)
#   tools/share.sh --release       # Deployment build (smaller, optimised)
#   tools/share.sh --out ~/Desktop # Drop the artifacts somewhere specific
#
# What it does:
#   1. Builds the app via tools/build.sh (Development) or `make Deployment`.
#   2. Locates MomenTerm.app under the DerivedData build directory.
#   3. Strips any com.apple.quarantine attribute and ad-hoc signs the bundle
#      so macOS doesn't refuse to launch with "the app is damaged".
#   4. ditto -c -k --keepParent to a zip.
#   5. Renders INSTALL.md from tools/INSTALL.md.template with the embedded
#      version + SHA-256 so the recipient can verify integrity.
#
# For proper public distribution (Sparkle auto-update, GitHub Release),
# use tools/release.sh instead — that path requires a one-time keypair
# but gives users automatic future updates.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# -- Flags ------------------------------------------------------------------

CONFIG="Development"
# Base output dir; the per-run artifacts land in a versioned subfolder
# (e.g. build/share/v3.6.dev/) created after the version is detected.
BASE_OUT="$REPO_ROOT/build/share"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      CONFIG="Deployment"
      shift
      ;;
    --dev|--development)
      CONFIG="Development"
      shift
      ;;
    --out)
      BASE_OUT="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$BASE_OUT"

# -- Build ------------------------------------------------------------------

echo "[share] building $CONFIG configuration..."
if [ "$CONFIG" = "Development" ]; then
  "$REPO_ROOT/tools/build.sh" Development
else
  ( cd "$REPO_ROOT" && make Deployment )
fi

# -- Locate the built .app -------------------------------------------------

DD_BASE="$(xcodebuild -workspace "$REPO_ROOT/iTerm2.xcodeproj/project.xcworkspace" -scheme iTerm2 -showBuildSettings 2>/dev/null | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR =/{print $2; exit}')"
if [ -z "$DD_BASE" ] || [ ! -d "$DD_BASE" ]; then
  # Fallback: glob DerivedData
  DD_BASE="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/iTerm2-"*"/Build/Products/$CONFIG" 2>/dev/null | head -n 1)"
fi
APP_PATH="$DD_BASE/MomenTerm.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: could not find MomenTerm.app at $APP_PATH" >&2
  exit 1
fi

# -- Version ---------------------------------------------------------------

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo dev)"
GIT_DESCRIBE="$(cd "$REPO_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo unknown)"
TAG="${VERSION}+${GIT_DESCRIBE}"

echo "[share] app: $APP_PATH"
echo "[share] version: $VERSION (git: $GIT_DESCRIBE)"

# Per-version output dir. e.g. build/share/v3.6.dev/. Wiped at the start
# of each run so retries don't accumulate stale staging junk.
OUT_DIR="$BASE_OUT/v${VERSION}"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# -- Stage a copy + ad-hoc sign --------------------------------------------

STAGE="$OUT_DIR/staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_PATH" "$STAGE/MomenTerm.app"

# Remove quarantine attribute that DerivedData copies sometimes carry
xattr -cr "$STAGE/MomenTerm.app" 2>/dev/null || true

# Ad-hoc sign the whole bundle. Without this Gatekeeper says "MomenTerm is
# damaged and can't be opened." Ad-hoc isn't a real Developer ID so the
# recipient still sees the unidentified-developer warning once, but the
# app actually runs after the right-click → Open dance.
echo "[share] ad-hoc signing..."
codesign --force --deep --sign - "$STAGE/MomenTerm.app" >/dev/null

# -- Zip --------------------------------------------------------------------

ZIP_NAME="MomenTerm-${VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
echo "[share] zipping..."
ditto -c -k --sequesterRsrc --keepParent "$STAGE/MomenTerm.app" "$ZIP_PATH"

ZIP_BYTES="$(stat -f%z "$ZIP_PATH")"
ZIP_MB="$(( ZIP_BYTES / 1024 / 1024 ))"
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

# -- Render INSTALL.md ------------------------------------------------------

INSTALL_MD="$OUT_DIR/INSTALL.md"
TEMPLATE="$REPO_ROOT/tools/INSTALL.md.template"
if [ ! -f "$TEMPLATE" ]; then
  echo "error: missing template $TEMPLATE" >&2
  exit 1
fi

PUBDATE="$(date "+%Y-%m-%d")"
sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__GIT_DESCRIBE__/${GIT_DESCRIBE}/g" \
    -e "s/__PUBDATE__/${PUBDATE}/g" \
    -e "s/__ZIP_NAME__/${ZIP_NAME}/g" \
    -e "s/__ZIP_BYTES__/${ZIP_BYTES}/g" \
    -e "s/__ZIP_MB__/${ZIP_MB}/g" \
    -e "s/__SHA256__/${SHA256}/g" \
    "$TEMPLATE" > "$INSTALL_MD"

# -- Cleanup staging --------------------------------------------------------

rm -rf "$STAGE"

cat <<EOF

[share] done.
  $ZIP_PATH  ($ZIP_MB MB)
  $INSTALL_MD

Send both files to the recipient. They should follow INSTALL.md to bypass
Gatekeeper once on first launch.

SHA-256:
  $SHA256
EOF
