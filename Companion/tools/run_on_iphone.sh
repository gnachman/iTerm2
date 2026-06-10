#!/bin/bash
# Build the iTerm2 Companion app and run it on a connected iPhone, no Xcode UI.
#
# Usage: Companion/tools/run_on_iphone.sh [device-identifier]
# With no argument, picks the first available iPhone devicectl can see.
# The app's stdout (companionLog output) streams to this terminal; ctrl-C
# detaches (and stops the app, as with Xcode).

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${DEVELOPMENT_TEAM:-H7V7XYVQ7D}"
DEVICE="${1:-}"

if [[ -z "$DEVICE" ]]; then
    JSON=$(mktemp)
    trap 'rm -f "$JSON"' EXIT
    xcrun devicectl list devices --json-output "$JSON" >/dev/null
    DEVICE=$(python3 - "$JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for device in data.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    if "iPhone" not in hardware.get("deviceType", hardware.get("productType", "")):
        continue
    if connection.get("tunnelState") == "unavailable":
        continue
    print(device["identifier"])
    break
PY
)
    if [[ -z "$DEVICE" ]]; then
        echo "No connected iPhone found. Plug it in (or pass an identifier from:" >&2
        echo "  xcrun devicectl list devices" >&2
        exit 1
    fi
    echo "Using iPhone: $DEVICE"
fi

echo "Building…"
xcodebuild -project iTerm2Companion.xcodeproj \
           -scheme iTerm2Companion \
           -destination generic/platform=iOS \
           -allowProvisioningUpdates \
           DEVELOPMENT_TEAM="$TEAM" \
           build | grep -E "error:|warning:.*\.swift|BUILD" || true

APP="Build/Debug-iphoneos/iTerm2Companion.app"
if [[ ! -d "$APP" ]]; then
    echo "Build product not found at $APP" >&2
    exit 1
fi

echo "Installing…"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo "Launching (ctrl-C to detach)…"
xcrun devicectl device process launch --console --terminate-existing \
    --device "$DEVICE" com.googlecode.iterm2.companion
