#!/usr/bin/env bash
# build-pkg.sh — Wrap the current Development MomenTerm.app into a double-
# clickable .pkg installer that copies the app to /Applications.
#
# Personal-use only: the resulting package is UNSIGNED. Gatekeeper on a
# different Mac will refuse to open it without right-click → Open. On this
# machine the app is already trusted, so double-click just works.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="${CONFIG:-Development}"
BUILD_DIR="$(xcodebuild -scheme iTerm2 -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/^ *SYMROOT/{print $2; exit}')"
APP_SRC="$BUILD_DIR/$CONFIG/MomenTerm.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: $APP_SRC not found — build first: tools/build.sh" >&2
  exit 1
fi

VERSION="$(defaults read "$APP_SRC/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")"
STAMP="$(date +%Y%m%d-%H%M)"
PKG_ID="com.momenterm.personal"
PKG_VERSION="${VERSION}.${STAMP}"

DIST_DIR="$REPO_ROOT/dist"
STAGING="$(mktemp -d -t momenterm-pkg)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$DIST_DIR" "$STAGING/Applications"
/bin/cp -R "$APP_SRC" "$STAGING/Applications/MomenTerm.app"

PKG_OUT="$DIST_DIR/MomenTerm-${PKG_VERSION}.pkg"

echo "→ pkgbuild ($PKG_ID @ $PKG_VERSION)"
pkgbuild \
  --root "$STAGING" \
  --identifier "$PKG_ID" \
  --version "$PKG_VERSION" \
  --install-location "/" \
  "$PKG_OUT"

# Refresh the "latest" symlink so the user always has a stable path.
ln -sfh "$(basename "$PKG_OUT")" "$DIST_DIR/MomenTerm-latest.pkg"

echo ""
echo "✅ Built:  $PKG_OUT"
echo "   Alias:  $DIST_DIR/MomenTerm-latest.pkg"
echo "   Size:   $(du -sh "$PKG_OUT" | awk '{print $1}')"
echo ""
echo "Next: double-click the .pkg. macOS Installer will copy MomenTerm.app"
echo "to /Applications. (Unsigned → right-click → Open if Gatekeeper complains.)"
