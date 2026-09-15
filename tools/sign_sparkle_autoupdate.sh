#!/bin/bash
# Re-sign the nested Autoupdate.app helpers inside Sparkle.framework with a real
# Developer ID signature, the hardened runtime, and a secure timestamp.
#
# Why this exists: Xcode's "Code Sign On Copy" only re-signs the OUTER
# Sparkle.framework when iTerm2 is built. It never descends into the nested
# Autoupdate.app (Sparkle's updater helper), so whatever signature that helper
# carries inside the committed ThirdParty/Sparkle.framework is exactly what ships.
# Building Sparkle with ad-hoc signing (the contributor-friendly default, i.e. no
# SIGNED=1) leaves Autoupdate and fileop ad-hoc, and notarization then rejects the
# whole app with:
#     "The binary is not signed with a valid Developer ID certificate."
#     "The signature does not include a secure timestamp."
# This has broken a release before, so the sparkle make target runs this script to
# restore the Developer ID signature on the nested helpers.
set -euo pipefail

FRAMEWORK="${1:?usage: sign_sparkle_autoupdate.sh <Sparkle.framework> <identity>}"
IDENTITY="${2:?usage: sign_sparkle_autoupdate.sh <Sparkle.framework> <identity>}"

AUTOUPDATE_APP="$FRAMEWORK/Versions/A/Resources/Autoupdate.app"
if [ ! -d "$AUTOUPDATE_APP" ]; then
    echo "sign_sparkle_autoupdate: $AUTOUPDATE_APP not found" >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "WARNING: Developer ID signing identity not found in keychain:" >&2
    echo "    $IDENTITY" >&2
    echo "Leaving Sparkle's Autoupdate.app ad-hoc signed. That is fine for local" >&2
    echo "development, but such a framework MUST NOT be committed: notarization of" >&2
    echo "a release built against it will fail." >&2
    exit 0
fi

# Sign the extra Mach-O helper (fileop) first, then seal the bundle, which signs
# the main Autoupdate executable and records fileop in the bundle's seal. codesign
# does not recurse into nested code without --deep, so fileop must be signed by
# hand before the bundle. --options runtime and --timestamp are both required by
# notarization.
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$AUTOUPDATE_APP/Contents/MacOS/fileop"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$AUTOUPDATE_APP"

# Fail loudly if anything is still ad-hoc or missing a secure timestamp, so a bad
# framework can never be committed silently.
codesign --verify --strict --verbose=2 "$AUTOUPDATE_APP"
for bin in "$AUTOUPDATE_APP/Contents/MacOS/Autoupdate" \
           "$AUTOUPDATE_APP/Contents/MacOS/fileop"; do
    info=$(codesign -dvv "$bin" 2>&1)
    if grep -q "Signature=adhoc" <<< "$info"; then
        echo "sign_sparkle_autoupdate: $bin is still ad-hoc after signing" >&2
        exit 1
    fi
    if ! grep -q "^Timestamp=" <<< "$info"; then
        echo "sign_sparkle_autoupdate: $bin is missing a secure timestamp" >&2
        exit 1
    fi
done

echo "Signed Sparkle Autoupdate.app helpers with: $IDENTITY"
