#!/bin/bash
# Build script that filters output to show only errors and warnings
# Usage: tools/build.sh [configuration]
# Configuration defaults to Development

set -o pipefail

CONFIG="${1:-Development}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$PROJECT_DIR/tmp"
LOG_FILE="$TMP_DIR/build.log"

# Create tmp directory if needed
mkdir -p "$TMP_DIR"

echo "Building $CONFIG configuration..."
echo "Full log: $LOG_FILE"

# Run the build and capture output
cd "$PROJECT_DIR"
make "$CONFIG" > "$LOG_FILE" 2>&1
BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "Build succeeded."
    exit 0
fi

echo ""
echo "Build failed. Errors and warnings:"
echo "-----------------------------------"

# Extract errors and warnings, filtering out noise
# Look for compiler errors/warnings with file:line:column format
grep -E "^/.*:\d+:\d+: (error|warning):" "$LOG_FILE" | head -50

# Also check for linker errors
grep -E "^(ld|clang): error:" "$LOG_FILE" | head -10

# Check for Swift errors (different format)
grep -E "error: " "$LOG_FILE" | grep -v "CLANG_WARN\|GCC_TREAT\|export " | head -20

# Show the failure summary
echo ""
echo "-----------------------------------"
grep -E "\([0-9]+ (error|warning|failure)" "$LOG_FILE" | tail -5

exit $BUILD_STATUS
