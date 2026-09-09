#!/bin/bash
#
# Regression test for a fixed bug in tools/extract_strings.sh.
#
# extract_strings.sh used to derive BUILD_DIR from
# xcodebuild -showBuildSettings with:
#
#     awk '/^ *SYMROOT/{print $3; exit}'
#
# awk's default field splitting is on runs of whitespace, so a SYMROOT value
# whose path contains a space was truncated to its first whitespace-delimited
# token ($3). The subsequent `[[ ! -d "$BUILD_DIR" ]]` guard then failed and the
# script aborted with "could not determine BUILD_DIR".
#
# The fix replaces the awk parse with:
#
#     sed -n 's/^ *SYMROOT = //p' | head -1
#
# which keeps everything after "SYMROOT = ", so spaces survive.
#
# This test asserts the fix is in place:
#   1. tools/extract_strings.sh no longer uses awk to parse SYMROOT.
#   2. The sed pipeline preserves a SYMROOT path containing a space.
# It exits 0 on the fixed script and would have failed on the old one (which
# both used awk and would truncate the spaced path).
#
# Exit status:
#   0  = fix verified (no awk SYMROOT parse; sed preserves spaced path)
#   1  = fix missing or regressed -> investigate
#
# Run: tests/extract_strings_symroot_test.sh

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/extract_strings.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "FAIL: cannot find $SCRIPT" >&2
    exit 1
fi

fail=0

# --- 1. The script must no longer use awk to parse SYMROOT. ---
# Match an awk invocation on the same logical line as a SYMROOT reference.
if grep -nE 'awk.*SYMROOT|SYMROOT.*awk' "$SCRIPT"; then
    echo "FAIL: extract_strings.sh still parses SYMROOT with awk (truncates spaced paths)." >&2
    fail=1
else
    echo "OK: extract_strings.sh no longer uses awk to parse SYMROOT."
fi

# --- 2. The script must use the sed pipeline to extract SYMROOT. ---
if grep -qE "sed -n 's/\^ \*SYMROOT = //p'" "$SCRIPT"; then
    echo "OK: extract_strings.sh uses the sed SYMROOT parser."
else
    echo "FAIL: extract_strings.sh does not use the expected sed SYMROOT parser." >&2
    fail=1
fi

# --- 3. The new sed pipeline must preserve a spaced path. ---
# Feed a synthetic showBuildSettings line (exactly as xcodebuild prints it) with
# a space in the SYMROOT value through the same pipeline the script uses.
FULL_PATH="/Users/foo/My Build/Products"
LINE="    SYMROOT = ${FULL_PATH}"

sed_result="$(printf '%s\n' "$LINE" \
    | sed -n 's/^ *SYMROOT = //p' | head -1)"

echo "input line:  [$LINE]"
echo "sed (fix):   [$sed_result]"

if [[ "$sed_result" != "$FULL_PATH" ]]; then
    echo "FAIL: sed pipeline did not preserve the full spaced path (got '$sed_result')." >&2
    fail=1
else
    echo "OK: sed pipeline preserved the full spaced path."
fi

if [[ "$fail" -eq 0 ]]; then
    echo "PASS: SYMROOT parse fix verified (no awk; sed preserves spaces)."
fi
exit "$fail"
