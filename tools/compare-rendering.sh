#!/bin/bash
# Compare GPU and legacy terminal rendering for a given input file.
# Usage: tools/compare-rendering.sh <file> [rows] [columns]
#
# The file should contain raw bytes including any escape sequences.
# Outputs comparison stats and saves images to /tmp/iterm2-compare-*.png

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <file> [rows] [columns]" >&2
    exit 2
fi

FILE="$1"
ROWS="${2:-24}"
COLS="${3:-80}"

if [ ! -f "$FILE" ]; then
    echo "Error: file not found: $FILE" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP="$PROJECT_DIR/Build/Development/iTerm2.app/Contents/MacOS/iTerm2"

if [ ! -x "$APP" ]; then
    echo "Error: iTerm2 not built. Run tools/build.sh first." >&2
    exit 2
fi

FILE_URL="file://$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

exec "$APP" -compare-rendering "$FILE_URL" -rows "$ROWS" -columns "$COLS"
