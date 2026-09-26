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

# Where swift build puts the product moved between toolchains (it used to be
# <scratch>/<triple>/release), and both lipo and cp will happily take whatever
# stale copy is still sitting at the old path, so ask for the path rather than
# assuming it.
build_arch() {
    local arch="$1"
    local scratch="$2"
    echo "Building for $arch..." >&2
    # This function runs inside $(...), where bash drops set -e, so a failed
    # build has to fail loudly on its own or a stale product would be shipped.
    swift build -c release --arch "$arch" --scratch-path "$scratch" --disable-sandbox >&2 || exit 1
    swift build -c release --arch "$arch" --scratch-path "$scratch" --disable-sandbox --show-bin-path
}

if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "Building it2 as universal binary..."

    ARM64_BIN="$(build_arch arm64 .build-arm64)"
    X86_64_BIN="$(build_arch x86_64 .build-x86_64)"

    mkdir -p .build/release

    echo "Creating universal binary..."
    lipo -create \
        "$ARM64_BIN/it2" \
        "$X86_64_BIN/it2" \
        -output .build/release/it2

    sign_binary "it2"

    echo "Build complete: .build/release/it2 (universal binary)"
    echo "Architectures:"
    lipo -archs .build/release/it2
else
    echo "Building it2 for $NATIVE_ARCH..."
    NATIVE_BIN="$(build_arch "$NATIVE_ARCH" ".build-$NATIVE_ARCH")"

    mkdir -p .build/release
    cp "$NATIVE_BIN/it2" ".build/release/it2"

    sign_binary "it2"

    echo "Build complete: .build/release/it2 ($NATIVE_ARCH)"
fi

echo ""
echo "Build complete!"
