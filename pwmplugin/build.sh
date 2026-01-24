#!/bin/bash

set -e

echo "Building password manager adapters as universal binaries..."

# Build for arm64
echo "Building for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64

# Build for x86_64
echo "Building for x86_64..."
swift build -c release --arch x86_64 --scratch-path .build-x86_64

# Create output directory
mkdir -p .build/release

# Code signing setup
# Use Developer ID Application for distribution, or ad-hoc signing for local development
# Can be overridden with CODESIGN_IDENTITY environment variable
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    # Try to find Developer ID Application certificate (use the first one if multiple exist)
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | grep -o '[0-9A-F]\{40\}')
fi

# Function to create and sign universal binary
build_universal() {
    local name=$1
    echo ""
    echo "Creating universal binary for $name..."
    lipo -create \
        .build-arm64/arm64-apple-macosx/release/$name \
        .build-x86_64/x86_64-apple-macosx/release/$name \
        -output .build/release/$name

    echo "Code signing $name..."
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "Signing with certificate: $SIGNING_IDENTITY"
        codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGNING_IDENTITY" .build/release/$name
    else
        echo "Warning: No Developer ID Application certificate found, using ad-hoc signature (development only)"
        codesign -s - .build/release/$name
    fi

    echo "✓ Build complete: .build/release/$name (universal binary)"
    echo "Architectures:"
    lipo -archs .build/release/$name
    cp .build/release/$name binaries/
}

# Build both adapters
build_universal "iterm2-keepassxc-adapter"
build_universal "iterm2-bitwarden-adapter"

echo ""
echo "✓✓✓ All builds complete! ✓✓✓"
