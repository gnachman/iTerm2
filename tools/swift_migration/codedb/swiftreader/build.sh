#!/bin/bash
# Build the code database's reader of the Swift compiler's JSON AST dump.
#
# Usage: tools/swift_migration/codedb/swiftreader/build.sh [output-path]
# Default output: tmp/codedb/bin/swift_refs
#
# Needs RapidJSON's headers (its SAX parser streams the dump): from
# $CODEDB_RAPIDJSON_INCLUDE if set, else Homebrew's rapidjson
# (`brew --prefix rapidjson`, then /opt/homebrew/opt/rapidjson and
# /usr/local/opt/rapidjson). Install it with `brew install rapidjson`. No
# version is pinned: only reader.h, filereadstream.h and error/en.h are used,
# and they have been stable for years.
#
# Compiled with the SDK's clang++ (xcrun) and linked with the SDK's sqlite3;
# CommonCrypto computes digests. Nothing else.
#
# The binary's version is a digest of the reader's sources (this script,
# swift_refs.cpp and dump_format.h): SHA-256 of the output of
# `shasum -a 256 build.sh swift_refs.cpp dump_format.h` in this directory.
# codedb.py computes the same digest (swift_reader_source_digest), rebuilds
# the binary when they differ, and stores it with every Swift module, so a
# change to the reader makes every module stale.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="${1:-$ROOT/tmp/codedb/bin/swift_refs}"

fail() {
    echo "swift reader build: $*" >&2
    exit 1
}

candidates=()
if [ -n "${CODEDB_RAPIDJSON_INCLUDE:-}" ]; then
    candidates+=("$CODEDB_RAPIDJSON_INCLUDE")
else
    if command -v brew > /dev/null 2>&1; then
        p="$(brew --prefix rapidjson 2>/dev/null || true)"
        [ -n "$p" ] && candidates+=("$p/include")
    fi
    candidates+=("/opt/homebrew/opt/rapidjson/include" "/usr/local/opt/rapidjson/include")
fi
INCLUDE=""
for c in "${candidates[@]}"; do
    if [ -f "$c/rapidjson/reader.h" ]; then
        INCLUDE="$c"
        break
    fi
done
[ -n "$INCLUDE" ] || fail "RapidJSON not found (looked for rapidjson/reader.h in: ${candidates[*]}). Install it with 'brew install rapidjson' or set CODEDB_RAPIDJSON_INCLUDE."

SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
[ -n "$SDK" ] && [ -d "$SDK" ] || fail "no macOS SDK: 'xcrun --show-sdk-path' failed"
CXX="$(xcrun --find clang++ 2>/dev/null || true)"
[ -x "$CXX" ] || fail "no clang++: 'xcrun --find clang++' failed"

DIGEST="$(cd "$HERE" && /usr/bin/shasum -a 256 build.sh swift_refs.cpp dump_format.h | /usr/bin/shasum -a 256 | cut -d' ' -f1)"
[ ${#DIGEST} -eq 64 ] || fail "cannot compute the digest of the reader's sources"

echo "swift reader build: RapidJSON $INCLUDE"
echo "swift reader build: SDK $SDK"
echo "swift reader build: source digest $DIGEST"
echo "swift reader build: output $OUT"
mkdir -p "$(dirname "$OUT")"
"$CXX" -std=c++17 -O2 -g0 -Wall -Wextra -Wno-unused-parameter -Werror \
    -isysroot "$SDK" -isystem "$INCLUDE" \
    -DSWIFT_REFS_DIGEST="\"$DIGEST\"" \
    "$HERE/swift_refs.cpp" -o "$OUT" -lsqlite3
echo "swift reader build: built $OUT"
