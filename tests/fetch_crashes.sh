#!/bin/bash
# Force download online-only Dropbox crash files
# Usage: ./fetch_crashes.sh [version]

CRASHDIR=~/Dropbox/Apps/CrashLogs/sorted-crashes
VERSION="${1:-3.6.8}"

cd "$CRASHDIR/$VERSION" 2>/dev/null || { echo "No such version: $VERSION"; exit 1; }

# Find 0-byte files (online-only)
zero_files=$(find . -maxdepth 1 -name "*.txt" -size 0 | wc -l | tr -d ' ')

if [ "$zero_files" -eq 0 ]; then
    echo "All files already local"
    exit 0
fi

echo "Found $zero_files online-only files, downloading..."

# brctl is the macOS command to request cloud file downloads
for f in *.txt; do
    if [ ! -s "$f" ]; then
        brctl download "$f" 2>/dev/null &
    fi
done
wait

# Wait for downloads (check every 2 seconds, timeout after 60s)
for i in {1..30}; do
    remaining=$(find . -maxdepth 1 -name "*.txt" -size 0 | wc -l | tr -d ' ')
    if [ "$remaining" -eq 0 ]; then
        echo "Done - all files downloaded"
        exit 0
    fi
    echo "Waiting... $remaining files remaining"
    sleep 2
done

echo "Timeout - some files may not have downloaded"
