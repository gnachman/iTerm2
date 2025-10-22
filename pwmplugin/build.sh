#!/bin/bash

set -e

echo "Building iterm2-keepassxc-adapter as universal binary..."

# Build for arm64
echo "Building for arm64..."
swift build -c release --arch arm64 --scratch-path .build-arm64

# Build for x86_64
echo "Building for x86_64..."
swift build -c release --arch x86_64 --scratch-path .build-x86_64

# Create output directory
mkdir -p .build/release

# Create universal binary using lipo
echo "Creating universal binary..."
lipo -create \
    .build-arm64/arm64-apple-macosx/release/iterm2-keepassxc-adapter \
    .build-x86_64/x86_64-apple-macosx/release/iterm2-keepassxc-adapter \
    -output .build/release/iterm2-keepassxc-adapter

echo "Code signing binary..."
# Use Developer ID Application for distribution, or ad-hoc signing for local development
# Can be overridden with CODESIGN_IDENTITY environment variable
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    # Try to find Developer ID Application certificate (use the first one if multiple exist)
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | grep -o '[0-9A-F]\{40\}')
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with certificate: $SIGNING_IDENTITY"
    codesign --force --options runtime --entitlements entitlements.plist --sign "$SIGNING_IDENTITY" .build/release/iterm2-keepassxc-adapter
else
    echo "Warning: No Developer ID Application certificate found, using ad-hoc signature (development only)"
    codesign -s - .build/release/iterm2-keepassxc-adapter
fi

echo "✓ Build complete: .build/release/iterm2-keepassxc-adapter (universal binary)"
echo "Architectures:"
lipo -archs .build/release/iterm2-keepassxc-adapter
cp .build/release/iterm2-keepassxc-adapter binaries/
