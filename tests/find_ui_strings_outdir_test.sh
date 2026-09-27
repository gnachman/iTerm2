#!/bin/bash
#
# Regression test for a fixed bug in tools/find_ui_strings.py.
#
# find_ui_strings.py writes its TSV reports with:
#
#     outdir = sys.argv[1] if len(sys.argv) > 1 else "tmp"
#     ...
#     open(f"{outdir}/ui_{b}.tsv", "w").write(...)
#     open(f"{outdir}/ui_all.tsv", "w").write(...)
#
# It used to never create `outdir`, so if the output directory did not already
# exist the script scanned the whole repo and then died with FileNotFoundError
# when it tried to open the first report for writing. The default outdir ("tmp")
# is gitignored, so a fresh checkout hit this too.
#
# The fix adds `os.makedirs(outdir, exist_ok=True)` before the opens.
#
# This test invokes the real script with an outdir that does not exist and
# asserts that it now SUCCEEDS (exit 0) and writes the reports there.
#
# Exit status:
#   0  = fix verified (nonexistent outdir created, reports written)
#   1  = fix missing or regressed -> investigate
#
# Run: tests/find_ui_strings_outdir_test.sh

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/find_ui_strings.py"

if [[ ! -f "$SCRIPT" ]]; then
    echo "FAIL: cannot find $SCRIPT" >&2
    exit 1
fi

# A guaranteed-nonexistent output directory (nested, to also prove makedirs
# creates parents) under a temp area we clean up afterward.
TMPROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

MISSING="$TMPROOT/does/not/exist"
if [[ -d "$MISSING" ]]; then
    echo "FAIL: sentinel outdir unexpectedly exists: $MISSING" >&2
    exit 1
fi

# The script scans ./sources, so run from the repo root.
cd "$ROOT" || { echo "FAIL: cannot cd to $ROOT" >&2; exit 1; }

out="$(python3 "$SCRIPT" "$MISSING" 2>&1)"
status=$?

echo "exit status: $status"
echo "----- output -----"
echo "$out"
echo "------------------"

if [[ "$status" -ne 0 ]]; then
    echo "FAIL: script exited nonzero with a nonexistent outdir." >&2
    if echo "$out" | grep -q "FileNotFoundError"; then
        echo "FAIL: still raises FileNotFoundError (os.makedirs fix missing)." >&2
    fi
    exit 1
fi

if [[ ! -d "$MISSING" ]]; then
    echo "FAIL: script succeeded but did not create the output directory." >&2
    exit 1
fi

if [[ ! -f "$MISSING/ui_all.tsv" ]]; then
    echo "FAIL: script did not write ui_all.tsv into the created outdir." >&2
    exit 1
fi

echo "OK: script created the nonexistent outdir and wrote its reports."
echo "PASS: missing-outdir fix in find_ui_strings.py verified."
exit 0
