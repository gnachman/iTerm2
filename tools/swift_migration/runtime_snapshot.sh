#!/bin/bash
# Takes an Objective-C runtime snapshot of one or more classes: what the
# runtime knows about each (defining language and binary, superclass,
# protocols, ivars with their type encodings and the ownership the runtime's
# ivar layouts give them, every method with its type encoding,
# overrides, and the binary of any method implemented elsewhere, every
# property with its attributes, and duplicate selectors). See
# docs/swift-migration/phase0.md section 9 and ModernTests/RuntimeSnapshot.swift.
#
# Usage:
#   tools/swift_migration/runtime_snapshot.sh <output-file> <ClassName> [<ClassName> ...]
#
# Example:
#   tools/swift_migration/runtime_snapshot.sh tmp/before.txt PTYSession iTermAdvancedSettingsModel
#
# Class names are runtime names, as NSClassFromString takes them. The snapshot
# runs inside the ModernTests test host, where the app's classes are loaded, by
# running ModernTests/RuntimeSnapshotTool/testWriteRequestedSnapshot. It builds
# the app and the tests first if needed, so the first run takes a while.
#
# Limitations:
# - It can only snapshot the configuration that the ModernTests scheme builds
#   for testing (today Development, with the address sanitizer variant), and
#   records that configuration in the snapshot. There is no option to choose
#   another, so code that exists only in other configurations is not seen.
# - It records what the runtime lists, not what methods do, so selectors or
#   keys a class answers dynamically (forwarding, method resolution,
#   valueForUndefinedKey:) are not covered; the comparison's pass message
#   lists every known gap.
# - Ivars are listed sorted by name, so a change in their declaration order is
#   not visible, although that order decides the order in which ARC releases
#   them at teardown.
# - Ivar ownership is what the runtime's strong and weak ivar layouts and
#   the class's ARC flag say. Where they cannot tell (an unretained pointer
#   from one retained by hand, a C struct from a C++ object, anything in a
#   class compiled without ARC, a Swift class's stored properties), the label
#   says so; ModernTests/RuntimeSnapshotIvarOwnership.swift lists the labels.
#   tools/swift_migration/ivar_ownership_check.py adds the compiler's answer
#   from the code database and reports where the two disagree.
# - Method encodings write every object as plain @, so the class of an object
#   parameter or return value is not recorded, and neither is nullability.
# - It does not record the ownership of a property it labels unrecorded. For
#   a Swift class it cannot tell a weak property from an unowned one, nor
#   whether a member is dynamic.
# - Concurrent runs in one checkout are not supported: they share
#   xcodebuild's build products and build database, and the second run fails
#   (with “database is locked”), exits 1, and keeps its log.
#
# If the run fails, its log is kept under tmp/, its path is printed, and no
# output file is left. An interrupted run ends the same way, because
# run_tests.expect catches the interrupt and exits with a failure.
#
# Compare two snapshots with tools/swift_migration/compare_runtime_snapshots.sh.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    # Print the comment block above, without its leading "# ".
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit 2
fi

# Resolve the output path against the caller's directory before changing
# to the repository root.
OUTPUT="$1"
shift
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
rm -f "$OUTPUT"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

mkdir -p tmp
# A new log file per run, kept if the run fails.
LOG="$(mktemp "$ROOT/tmp/runtime-snapshot.XXXXXX")"

# xcodebuild does not pass the shell's environment to the test host. Variables
# prefixed with TEST_RUNNER_ are forwarded with the prefix removed.
export TEST_RUNNER_ITERM2_RUNTIME_SNAPSHOT_CLASSES="$*"
export TEST_RUNNER_ITERM2_RUNTIME_SNAPSHOT_OUTPUT="$OUTPUT"

if ! "$ROOT/tools/run_tests.expect" ModernTests/RuntimeSnapshotTool/testWriteRequestedSnapshot > "$LOG" 2>&1; then
    ERRORS="$(grep -E "error:|failed" "$LOG" | sed 's/\x1b\[[0-9;]*m//g' | sort -u | head -40 || true)"
    if [[ -n "$ERRORS" ]]; then
        echo "The snapshot run failed. Errors from the log:" >&2
        echo "$ERRORS" >&2
    else
        echo "The snapshot run failed or was interrupted; the log has no error lines." >&2
    fi
    rm -f "$OUTPUT"
    echo "The full log is kept at $LOG" >&2
    exit 1
fi
if [[ ! -f "$OUTPUT" ]]; then
    echo "The test run passed but wrote no snapshot. It was probably skipped because the" >&2
    echo "TEST_RUNNER_ variables did not reach the test host." >&2
    echo "The full log is kept at $LOG" >&2
    exit 1
fi

grep -a "Runtime snapshot of" "$LOG" | sed 's/\x1b\[[0-9;]*m//g' | tail -1 || true

if grep -q "^  DUPLICATE " "$OUTPUT"; then
    echo "" >&2
    echo "*** DUPLICATES: a selector listed more than once in one class's method list, so" >&2
    echo "*** which implementation runs is undefined, or a property listed more than once with" >&2
    echo "*** different attributes. Any comparison will fail." >&2
    awk '/^class /{name=$2} /^  DUPLICATE /{print "    " name ":" substr($0, 2)}' "$OUTPUT" >&2
    echo "" >&2
fi
if grep -q "^  OWNERSHIP-CONFLICT " "$OUTPUT"; then
    echo "" >&2
    echo "*** OWNERSHIP CONFLICTS: the ivar layouts contradict each other, the ivar list, or the" >&2
    echo "*** runtime's own answer. Either the snapshot tool has a bug or the class is a real" >&2
    echo "*** surprise; see ModernTests/RuntimeSnapshotIvarOwnership.swift. Any comparison will fail." >&2
    awk '/^class /{name=$2} /^  OWNERSHIP-CONFLICT /{print "    " name ":" substr($0, 2)}' "$OUTPUT" >&2
    echo "" >&2
fi
rm -f "$LOG"
echo "Wrote $OUTPUT"
