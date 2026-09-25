#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Where SwiftPM put a build's product. Ask rather than assume: the layout
# differs between SwiftPM's own build system and the Xcode one it uses when
# Xcode is present, and hardcoding either silently produces no binary.
product_path() {
    swift build -c release --arch "$1" --scratch-path ".build-$1" --show-bin-path
}

echo "Building cc-status as universal binary..."

echo "Building for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64 --disable-sandbox

echo "Building for x86_64..."
swift build -c release --arch x86_64 --scratch-path .build-x86_64 --disable-sandbox

mkdir -p bin

echo "Creating universal binary..."
lipo -create \
    "$(product_path arm64)/cc-status" \
    "$(product_path x86_64)/cc-status" \
    -output bin/cc-status

echo "Build complete: bin/cc-status (universal binary)"
echo "Architectures:"
lipo -archs bin/cc-status
