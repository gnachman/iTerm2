#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building cc-status as universal binary..."

# Where swift build puts the product moved between toolchains (it used to be
# <scratch>/<triple>/release), and lipo will happily fuse whatever stale copy is
# still sitting at the old path, so ask for the path instead of assuming it.
build_arch() {
    local arch="$1"
    local scratch="$2"
    echo "Building for $arch..." >&2
    # This function runs inside $(...), where bash drops set -e, so a failed
    # build has to fail loudly on its own or lipo would fuse a stale product.
    swift build -c release --arch "$arch" --scratch-path "$scratch" --disable-sandbox >&2 || exit 1
    swift build -c release --arch "$arch" --scratch-path "$scratch" --disable-sandbox --show-bin-path
}

ARM64_BIN="$(build_arch arm64 .build-arm64)"
X86_64_BIN="$(build_arch x86_64 .build-x86_64)"

mkdir -p bin

echo "Creating universal binary..."
lipo -create \
    "$ARM64_BIN/cc-status" \
    "$X86_64_BIN/cc-status" \
    -output bin/cc-status

echo "Build complete: bin/cc-status (universal binary)"
echo "Architectures:"
lipo -archs bin/cc-status
