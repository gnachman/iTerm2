#!/bin/bash
# Build extraction_facts, the LibTooling program behind extract_check.py,
# against upstream LLVM.
#
# Usage: tools/swift_migration/extraction/build.sh [output-path]
# Default output: tmp/extraction/bin/extraction_facts
#
# LLVM is found exactly as the code database's extractor finds it
# (tools/swift_migration/codedb/extractor/build.sh): $CODEDB_LLVM_PREFIX if
# set, else Homebrew's llvm@22. The major version is pinned to 22, because the
# results are only validated against it. The macOS SDK comes from
# `xcrun --show-sdk-path`. Nothing from Xcode's own toolchain is linked.
#
# The binary's version is a digest of its sources: SHA-256 of the output of
# `shasum -a 256 build.sh extraction_facts.cpp` run in this directory.
# extract_check.py computes the same digest and rebuilds the binary when they
# differ.

set -euo pipefail

REQUIRED_LLVM_MAJOR=22

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${1:-$ROOT/tmp/extraction/bin/extraction_facts}"

fail() {
    echo "extraction_facts build: $*" >&2
    exit 1
}

candidates=()
if [ -n "${CODEDB_LLVM_PREFIX:-}" ]; then
    candidates+=("$CODEDB_LLVM_PREFIX")
else
    if command -v brew > /dev/null 2>&1; then
        p="$(brew --prefix "llvm@$REQUIRED_LLVM_MAJOR" 2>/dev/null || true)"
        [ -n "$p" ] && candidates+=("$p")
    fi
    candidates+=("/opt/homebrew/opt/llvm@$REQUIRED_LLVM_MAJOR" "/usr/local/opt/llvm@$REQUIRED_LLVM_MAJOR")
fi

LLVM=""
for c in "${candidates[@]}"; do
    if [ -x "$c/bin/llvm-config" ]; then
        LLVM="$c"
        break
    fi
done
[ -n "$LLVM" ] || fail "no LLVM $REQUIRED_LLVM_MAJOR found (looked for bin/llvm-config in: ${candidates[*]}). Install it with 'brew install llvm@$REQUIRED_LLVM_MAJOR' or set CODEDB_LLVM_PREFIX."

LLVM_CONFIG="$LLVM/bin/llvm-config"
VERSION="$("$LLVM_CONFIG" --version)"
MAJOR="${VERSION%%.*}"
[ "$MAJOR" = "$REQUIRED_LLVM_MAJOR" ] || fail "LLVM at $LLVM is version $VERSION; version $REQUIRED_LLVM_MAJOR is required."

INCLUDE="$("$LLVM_CONFIG" --includedir)"
LIBDIR="$("$LLVM_CONFIG" --libdir)"
CLANG="$LLVM/bin/clang"
CLANGXX="$LLVM/bin/clang++"
[ -f "$INCLUDE/clang/Tooling/Tooling.h" ] || fail "missing Clang LibTooling headers: $INCLUDE/clang/Tooling/Tooling.h"
[ -f "$LIBDIR/libclang-cpp.dylib" ] || fail "missing library: $LIBDIR/libclang-cpp.dylib"
[ -e "$LIBDIR/libLLVM.dylib" ] || fail "missing library: $LIBDIR/libLLVM.dylib"
[ -x "$CLANG" ] || fail "missing upstream clang: $CLANG"
[ -x "$CLANGXX" ] || fail "missing upstream clang++: $CLANGXX"
RESOURCE_DIR="$("$CLANG" -print-resource-dir)"
[ -f "$RESOURCE_DIR/include/stddef.h" ] || fail "missing clang resource headers: $RESOURCE_DIR/include/stddef.h"

SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
[ -n "$SDK" ] && [ -d "$SDK" ] || fail "no macOS SDK: 'xcrun --show-sdk-path' failed"

DIGEST="$(cd "$HERE" && /usr/bin/shasum -a 256 build.sh extraction_facts.cpp | /usr/bin/shasum -a 256 | cut -d' ' -f1)"
[ ${#DIGEST} -eq 64 ] || fail "cannot compute the digest of the sources"

echo "extraction_facts build: LLVM $VERSION at $LLVM, SDK $SDK, digest $DIGEST, output $OUT"

mkdir -p "$(dirname "$OUT")"
TMP_OUT="$OUT.tmp.$$"
"$CLANGXX" -std=c++17 -O1 -g0 -Wall -Wextra -Wno-unused-parameter -Werror \
    -isysroot "$SDK" \
    -I"$INCLUDE" -fno-exceptions -fno-rtti \
    -DEXTRACTION_LLVM_CLANG="\"$CLANG\"" \
    -DEXTRACTION_RESOURCE_DIR="\"$RESOURCE_DIR\"" \
    -DEXTRACTION_DIGEST="\"$DIGEST\"" \
    "$HERE/extraction_facts.cpp" -o "$TMP_OUT" \
    -L"$LIBDIR" -lclang-cpp -lLLVM -Wl,-rpath,"$LIBDIR"
mv -f "$TMP_OUT" "$OUT"
echo "extraction_facts build: built $OUT"
