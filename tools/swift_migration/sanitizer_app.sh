#!/bin/bash
# Build a Development app with the nullability and integer sanitizer groups in
# recover mode, for day-to-day use of a debug build that reports violations
# the tests do not reach (docs/swift-migration/phase0.md section 4, the
# second mode). Nothing aborts: each report is written to a file and the app
# carries on.
#
# Usage:
#   tools/swift_migration/sanitizer_app.sh [-h|--help]
#
# What it builds: the iTerm2 scheme, Development configuration, with
#   OTHER_CFLAGS='$(inherited) -fsanitize=nullability,<integer group>
#                 -fsanitize-recover=<both groups>
#                 -fsanitize-ignorelist=tools/swift_migration/sanitizer_ignorelist.txt'
#   OTHER_LDFLAGS='$(inherited) -fsanitize=<both groups>'
# where the integer group is signed-integer-overflow,implicit-conversion,
# float-cast-overflow,integer-divide-by-zero,shift,bounds. The address and
# thread sanitizers are off; the thread sanitizer is never used with the app.
# Targets, ignore list and runtime linking are as described in
# tools/swift_migration/sanitizer_tests.sh. Signed or not as for
# `make Development`: unsigned unless SIGNED=1.
#
# Where it goes: tmp/sanitizers/app/Build/ (its own SYMROOT and OBJROOT), so
# the regular build in Build/ is not touched. The log is
# tmp/sanitizers/app/build.log.
#
# Running it: the build does not run the app. To run it, with reports going
# to a directory of their own for each run, and with the -suite argument that
# keeps it apart from the iTerm2 you are using (CLAUDE.md):
#
#   RUN=tmp/sanitizers/app-runs/$(date +%Y%m%d-%H%M%S); mkdir -p "$RUN"
#   UBSAN_OPTIONS="print_stacktrace=1:report_error_type=1:halt_on_error=0:log_path=$PWD/$RUN/ubsan" \
#       tmp/sanitizers/app/Build/Development/iTerm2.app/Contents/MacOS/iTerm2 -suite iterm2-alt
#
# (the -suite value is the last path component of the checkout; iterm2-alt
# for this one). Each process writes $RUN/ubsan.<pid>; child processes that
# inherit the environment write their own. Afterwards:
#
#   python3 -B tools/swift_migration/sanitizer_summary.py "$RUN"
#
# Exit status: xcodebuild's.

set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/sanitizer_common.sh"

case "${1:-}" in
    -h|--help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    "") ;;
    *) echo "error: unknown argument $1" >&2; exit 2 ;;
esac

san_check_root_path || exit 2
BUILD_DIR="$SAN_ROOT/tmp/sanitizers/app"
LOG="$BUILD_DIR/build.log"
mkdir -p "$BUILD_DIR"
BOTH_GROUPS="$SAN_NULLABILITY_GROUP,$SAN_INTEGER_GROUP"

san_common_xcodebuild_args "$BUILD_DIR"
cd "$SAN_ROOT"
san_prepare_catalog
# make Development also does this copy (plists/iTerm2.plist is not tracked);
# made only when the content differs, as for the catalog.
cmp -s plists/dev-iTerm2.plist plists/iTerm2.plist || cp plists/dev-iTerm2.plist plists/iTerm2.plist

echo "Building the sanitized Development app (log: $LOG)..."
START=$(date +%s)
xcodebuild build "${SAN_XCODEBUILD_ARGS[@]}" \
    -scheme iTerm2 \
    -enableThreadSanitizer NO ENABLE_THREAD_SANITIZER=NO \
    "OTHER_CFLAGS=\$(inherited) -fsanitize=$BOTH_GROUPS -fsanitize-recover=$BOTH_GROUPS -fsanitize-ignorelist=$SAN_IGNORELIST" \
    "OTHER_LDFLAGS=\$(inherited) -fsanitize=$BOTH_GROUPS" \
    > "$LOG" 2>&1
STATUS=$?
echo "Build finished with status $STATUS in $(( $(date +%s) - START )) seconds."
if [ $STATUS -ne 0 ]; then
    grep -E "error: " "$LOG" | head -20 >&2
    exit $STATUS
fi
san_check_runtime "$BUILD_DIR/Build/Development/iTerm2.app" ubsan || exit 1
echo "Built $BUILD_DIR/Build/Development/iTerm2.app"
