#!/bin/bash
#
# Sign the nested code inside a built Sparkle.framework with Developer ID, a
# secure timestamp, and the hardened runtime.
#
# Why this is needed: `make sparkle` builds Sparkle with empty SIGNING_FLAGS, so
# Sparkle's own Xcode project signs its nested helpers ad-hoc ("Sign to Run
# Locally"). When iTerm2 embeds the framework it is copied with CodeSignOnCopy,
# which re-signs the framework wrapper but NOT the nested helpers, so those stay
# ad-hoc and Apple rejects the whole app at notarization ("not signed with a
# valid Developer ID certificate" / "does not include a secure timestamp").
# Running this after building the framework fixes the nested signatures. See the
# regression in commit d65c5f096.
#
# Sparkle 2 layout (Versions/B): the installer is the command-line tool
# `Autoupdate`, the progress agent that quits and relaunches the app is
# `Updater.app`, and sandboxed hosts would also have XPCServices/*.xpc. iTerm2 is
# not sandboxed and builds Sparkle without the XPC services, but they are signed
# here if present. Sparkle's own guidance is to sign each piece inside-out with
# the hardened runtime and never with --deep.
#
# Usage: sign_sparkle_helpers.sh <path-to-Sparkle.framework>
#   Override the identity with CODESIGN_IDENTITY if needed.

set -euo pipefail

FRAMEWORK="${1:?usage: sign_sparkle_helpers.sh <path-to-Sparkle.framework>}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: GEORGE NACHMAN (H7V7XYVQ7D)}"

if [ ! -d "$FRAMEWORK" ]; then
  echo "ERROR: no such framework: $FRAMEWORK" >&2
  exit 1
fi

VERSION_DIR="$FRAMEWORK/Versions/Current"
if [ ! -d "$VERSION_DIR" ]; then
  echo "ERROR: $VERSION_DIR does not exist" >&2
  exit 1
fi

sign() {
  echo "Signing $1"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
}

# Sign inside-out: nested Mach-O first, then bundles, then (last) the
# framework, so each enclosing seal is computed over already-signed contents.
for xpc in "$VERSION_DIR"/XPCServices/*.xpc; do
  if [ -e "$xpc" ]; then
    # Sparkle 2.6+ gives the Downloader service entitlements; keep them.
    echo "Signing $xpc"
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$xpc"
  fi
done
[ -e "$VERSION_DIR/Autoupdate" ] && sign "$VERSION_DIR/Autoupdate"
if [ -d "$VERSION_DIR/Updater.app" ]; then
  sign "$VERSION_DIR/Updater.app"
fi

# The framework wrapper. iTerm2's CodeSignOnCopy will re-sign this with the app's
# identity at embed time, but sign it here too so the on-disk artifact is
# self-consistently Developer ID and validates on its own.
sign "$VERSION_DIR"

# Fail loudly if any nested Mach-O is still ad-hoc.
BAD=$(find "$FRAMEWORK" -type f | while read -r f; do
  if file "$f" 2>/dev/null | grep -q "Mach-O" && codesign -dvv "$f" 2>&1 | grep -q "Signature=adhoc"; then
    echo "$f"
  fi
done)
if [ -n "$BAD" ]; then
  echo "ERROR: ad-hoc signatures remain after signing:" >&2
  echo "$BAD" >&2
  exit 1
fi

echo "OK: all nested Mach-O in $FRAMEWORK are Developer ID signed."
