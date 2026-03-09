#!/bin/bash
#
# analyze-crashes.sh - Automate crash log analysis for iTerm2
#
# Usage: ./analyze-crashes.sh VERSION
# Example: ./analyze-crashes.sh 3.6.8
#

set -e

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 VERSION"
    echo "Example: $0 3.6.8"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(pwd)"
CRASHES_DIR="$WORK_DIR/crashes"
SORTED_CRASHES_DIR="$HOME/dropbox/Apps/CrashLogs/sorted-crashes"
APP_PATH="$HOME/Applications/iTerm2 ${VERSION}.app/Contents/MacOS/iTerm2"

echo "=== iTerm2 Crash Analysis Script ==="
echo "Version: $VERSION"
echo "Working directory: $WORK_DIR"
echo ""

# Step 1: Process crashes
echo "=== Step 1: Processing crashes ==="
if [ ! -d "$SORTED_CRASHES_DIR" ]; then
    echo "Error: $SORTED_CRASHES_DIR does not exist"
    exit 1
fi

pushd "$SORTED_CRASHES_DIR" > /dev/null
if [ -f "./process.sh" ]; then
    ./process.sh "$VERSION"
else
    echo "Error: process.sh not found in $SORTED_CRASHES_DIR"
    exit 1
fi
popd > /dev/null

# Step 2: Copy processed crashes
echo ""
echo "=== Step 2: Copying processed crashes ==="
rm -rf "$CRASHES_DIR"
mkdir -p "$CRASHES_DIR"

PROCESSED_DIR="$SORTED_CRASHES_DIR/$VERSION/processed"
if [ ! -d "$PROCESSED_DIR" ]; then
    echo "Error: $PROCESSED_DIR does not exist"
    exit 1
fi

cp "$PROCESSED_DIR"/* "$CRASHES_DIR/"
INITIAL_COUNT=$(ls "$CRASHES_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
echo "Copied $INITIAL_COUNT crash files"

# Step 3: Get correct UUIDs from app bundle
echo ""
echo "=== Step 3: Getting UUIDs from app bundle ==="
if [ ! -f "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

UUID_OUTPUT=$(dwarfdump --uuid "$APP_PATH")
UUID_X86=$(echo "$UUID_OUTPUT" | grep "x86_64" | grep -oE "[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}" || true)
UUID_ARM=$(echo "$UUID_OUTPUT" | grep "arm64" | grep -oE "[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}" || true)

echo "x86_64 UUID: ${UUID_X86:-not found}"
echo "arm64 UUID:  ${UUID_ARM:-not found}"

if [ -z "$UUID_X86" ] && [ -z "$UUID_ARM" ]; then
    echo "Error: Could not extract any UUIDs from app bundle"
    exit 1
fi

# Step 4: Remove crashes with incorrect UUIDs
echo ""
echo "=== Step 4: Removing crashes with incorrect UUIDs ==="
REMOVED_COUNT=0

cd "$CRASHES_DIR"
for f in *.txt; do
    [ -f "$f" ] || continue

    # Check if this crash has a valid UUID
    HAS_VALID_UUID=0

    if [ -n "$UUID_ARM" ] && grep -q "$UUID_ARM" "$f"; then
        HAS_VALID_UUID=1
    fi

    if [ -n "$UUID_X86" ] && grep -q "$UUID_X86" "$f"; then
        HAS_VALID_UUID=1
    fi

    if [ $HAS_VALID_UUID -eq 0 ]; then
        rm "$f"
        ((REMOVED_COUNT++)) || true
    fi
done

FINAL_COUNT=$(ls "$CRASHES_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
echo "Removed $REMOVED_COUNT crashes with incorrect UUIDs"
echo "Remaining: $FINAL_COUNT crashes"

if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "No crashes to analyze"
    exit 0
fi

# Step 5: Cluster crashes using Claude Code
echo ""
echo "=== Step 5: Clustering crashes with Claude Code ==="
cd "$WORK_DIR"

CLUSTER_PROMPT="Investigate the crash logs in the crashes folder. Start by using subagents to cluster similar crashes. This is something agents have a hard time with, so afterwards check their work. Make a folder for each cluster and put crashlogs in them."

echo "Running: claude -p \"$CLUSTER_PROMPT\""
claude -p "$CLUSTER_PROMPT"

# Step 6: Analyze each cluster
echo ""
echo "=== Step 6: Analyzing each cluster ==="
cd "$CRASHES_DIR"

for dir in [0-9][0-9]-*/; do
    [ -d "$dir" ] || continue

    COUNT=$(ls "$dir"/*.txt 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -eq 0 ]; then
        continue
    fi

    DIRNAME=$(basename "$dir")
    echo ""
    echo "--- Analyzing cluster: $DIRNAME ($COUNT files) ---"

    ANALYZE_PROMPT="Find the root cause of the crashes in this folder: $CRASHES_DIR/$DIRNAME"

    echo "Running: claude -p \"$ANALYZE_PROMPT\""
    claude -p "$ANALYZE_PROMPT"
done

echo ""
echo "=== Analysis Complete ==="
echo "Results are in: $CRASHES_DIR"
