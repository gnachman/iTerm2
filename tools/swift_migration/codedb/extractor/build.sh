#!/bin/bash
# Build the code database extractor against upstream LLVM.
#
# Usage: tools/swift_migration/codedb/extractor/build.sh [output-path]
# Default output: tmp/codedb/bin/extract_sends
#
# Finds LLVM from $CODEDB_LLVM_PREFIX if set, else Homebrew's llvm@22
# (`brew --prefix llvm@22`, then /opt/homebrew/opt/llvm@22 and
# /usr/local/opt/llvm@22). The LLVM major version is pinned: any other version
# is refused, because the extractor's results are only validated against it.
#
# The macOS SDK (for sqlite3 and CommonCrypto, and later for parsing) comes from
# `xcrun --show-sdk-path`. Nothing from Xcode's own toolchain is linked.
#
# The binary's version is a digest of the extractor's sources (this script,
# extract_sends.cpp and reflective_table.h): SHA-256 of the output of
# `shasum -a 256 build.sh extract_sends.cpp reflective_table.h` run in this
# directory. codedb.py
# computes the same digest (extractor_source_digest), rebuilds the binary when
# they differ, and stores it with every unit, so any change to the extractor
# makes every unit stale.

set -euo pipefail

REQUIRED_LLVM_MAJOR=22

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="${1:-$ROOT/tmp/codedb/bin/extract_sends}"

fail() {
    echo "extractor build: $*" >&2
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
[ -f "$INCLUDE/llvm/Support/raw_ostream.h" ] || fail "missing LLVM headers: $INCLUDE/llvm/Support/raw_ostream.h"
[ -f "$LIBDIR/libclang-cpp.dylib" ] || fail "missing library: $LIBDIR/libclang-cpp.dylib"
[ -e "$LIBDIR/libLLVM.dylib" ] || fail "missing library: $LIBDIR/libLLVM.dylib"
[ -x "$CLANG" ] || fail "missing upstream clang: $CLANG"
[ -x "$CLANGXX" ] || fail "missing upstream clang++: $CLANGXX"
RESOURCE_DIR="$("$CLANG" -print-resource-dir)"
[ -f "$RESOURCE_DIR/include/stddef.h" ] || fail "missing clang resource headers: $RESOURCE_DIR/include/stddef.h"

SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
[ -n "$SDK" ] && [ -d "$SDK" ] || fail "no macOS SDK: 'xcrun --show-sdk-path' failed"
[ -f "$SDK/usr/include/sqlite3.h" ] || fail "missing sqlite3.h in SDK $SDK"
[ -f "$SDK/usr/include/CommonCrypto/CommonDigest.h" ] || fail "missing CommonCrypto in SDK $SDK"

DIGEST="$(cd "$HERE" && /usr/bin/shasum -a 256 build.sh extract_sends.cpp reflective_table.h | /usr/bin/shasum -a 256 | cut -d' ' -f1)"
[ ${#DIGEST} -eq 64 ] || fail "cannot compute the digest of the extractor's sources"

echo "extractor build: LLVM $VERSION at $LLVM"
echo "extractor build:   headers   $INCLUDE"
echo "extractor build:   libraries $LIBDIR/libclang-cpp.dylib $LIBDIR/libLLVM.dylib"
echo "extractor build:   clang     $CLANG (resource dir $RESOURCE_DIR)"
echo "extractor build: SDK $SDK"
echo "extractor build: source digest $DIGEST"
echo "extractor build: output $OUT"

mkdir -p "$(dirname "$OUT")"
"$CLANGXX" -std=c++17 -O1 -g0 -Wall -Wextra -Wno-unused-parameter -Werror \
    -isysroot "$SDK" \
    -I"$INCLUDE" -fno-exceptions -fno-rtti \
    -DCODEDB_LLVM_CLANG="\"$CLANG\"" \
    -DCODEDB_RESOURCE_DIR="\"$RESOURCE_DIR\"" \
    -DCODEDB_EXTRACTOR_DIGEST="\"$DIGEST\"" \
    "$HERE/extract_sends.cpp" -o "$OUT" \
    -L"$LIBDIR" -lclang-cpp -lLLVM -Wl,-rpath,"$LIBDIR" \
    -lsqlite3
echo "extractor build: built $OUT"
