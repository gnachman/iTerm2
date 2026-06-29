#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure protobuf symlinks exist
./setup.sh

NATIVE_ARCH=$(uname -m)

# Code signing setup
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | grep -o '[0-9A-F]\{40\}') || true
fi

sign_binary() {
    local name=$1
    echo "Code signing $name..."
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "Signing with certificate: $SIGNING_IDENTITY"
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" .build/release/$name
    else
        echo "Warning: No Developer ID Application certificate found, using ad-hoc signature (development only)"
        codesign -s - .build/release/$name
    fi
}

if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "Building it2 as universal binary..."

    echo "Building for arm64..."
    swift build -c release --arch arm64 --scratch-path .build-arm64 --disable-sandbox

    echo "Building for x86_64..."
    swift build -c release --arch x86_64 --scratch-path .build-x86_64 --disable-sandbox

    mkdir -p .build/release

    echo "Creating universal binary..."
    lipo -create \
        .build-arm64/arm64-apple-macosx/release/it2 \
        .build-x86_64/x86_64-apple-macosx/release/it2 \
        -output .build/release/it2

    sign_binary "it2"

    echo "Build complete: .build/release/it2 (universal binary)"
    echo "Architectures:"
    lipo -archs .build/release/it2
else
    echo "Building it2 for $NATIVE_ARCH..."
    swift build -c release --arch "$NATIVE_ARCH" --scratch-path ".build-$NATIVE_ARCH" --disable-sandbox

    mkdir -p .build/release
    cp ".build-$NATIVE_ARCH/${NATIVE_ARCH}-apple-macosx/release/it2" ".build/release/it2"

    sign_binary "it2"

    echo "Build complete: .build/release/it2 ($NATIVE_ARCH)"
fi

echo ""
echo "Build complete!"
