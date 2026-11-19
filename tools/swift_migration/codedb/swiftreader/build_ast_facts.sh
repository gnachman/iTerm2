#!/bin/bash
# Build the reader of the Swift compiler's JSON AST dump for the type-aware
# migration lints (tools/swift_migration/swift_ast_lints.py).
#
# Usage: tools/swift_migration/codedb/swiftreader/build_ast_facts.sh [output-path]
# Default output: tmp/swift_ast_lints/bin/swift_ast_facts
#
# Needs RapidJSON's headers, found as build.sh finds them: from
# $CODEDB_RAPIDJSON_INCLUDE if set, else Homebrew's rapidjson. Compiled with
# the SDK's clang++ (xcrun). Nothing else is linked.
#
# The binary's version is a digest of its sources (this script,
# swift_ast_facts.cpp and dump_format.h): SHA-256 of the output of
# `shasum -a 256 build_ast_facts.sh swift_ast_facts.cpp dump_format.h` in this
# directory. swift_ast_lints.py computes the same digest and rebuilds the
# binary when they differ.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="${1:-$ROOT/tmp/swift_ast_lints/bin/swift_ast_facts}"

fail() {
    echo "swift_ast_facts build: $*" >&2
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

DIGEST="$(cd "$HERE" && /usr/bin/shasum -a 256 build_ast_facts.sh swift_ast_facts.cpp dump_format.h | /usr/bin/shasum -a 256 | cut -d' ' -f1)"
[ ${#DIGEST} -eq 64 ] || fail "cannot compute the digest of the reader's sources"

mkdir -p "$(dirname "$OUT")"
"$CXX" -std=c++17 -O2 -g0 -Wall -Wextra -Wno-unused-parameter -Werror \
    -isysroot "$SDK" -isystem "$INCLUDE" \
    -DSWIFT_AST_FACTS_DIGEST="\"$DIGEST\"" \
    "$HERE/swift_ast_facts.cpp" -o "$OUT"
echo "swift_ast_facts build: built $OUT (source digest $DIGEST)"
