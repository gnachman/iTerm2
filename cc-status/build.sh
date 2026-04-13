#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building cc-status as universal binary..."

echo "Building for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64 --disable-sandbox

echo "Building for x86_64..."
swift build -c release --arch x86_64 --scratch-path .build-x86_64 --disable-sandbox

mkdir -p bin

echo "Creating universal binary..."
lipo -create \
    .build-arm64/arm64-apple-macosx/release/cc-status \
    .build-x86_64/x86_64-apple-macosx/release/cc-status \
    -output bin/cc-status

echo "Build complete: bin/cc-status (universal binary)"
echo "Architectures:"
lipo -archs bin/cc-status
