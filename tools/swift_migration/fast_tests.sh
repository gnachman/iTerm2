#!/bin/bash
# Run the fast test tier of ModernTests, for the Objective-C to Swift
# migration (docs/swift-migration/test-speed.md section 2, test-tiers.md).
#
# Usage:
#   tools/swift_migration/fast_tests.sh [--dry-run] [--no-build] [--serial] [--no-skip]
#
# The fast tier is every ModernTests test except the slow tier, the entries of
# tools/swift_migration/slow_tier.txt (each with its reason). It runs with no
# address sanitizer and no MallocStackLogging, which the ModernTests test
# plan turns on for tools/run_tests.expect:
#
#   1. Build: tools/swift_migration/sanitizer_tests.sh plain --build-only,
#      the build with no sanitizer at all, in tmp/sanitizers/plain/Build
#      (Build/ is left alone). That script checks that the app links no
#      sanitizer runtime.
#   2. The .xctestrun file the build wrote
#      (ModernTests_ModernTests_<sdk>-<arch>.xctestrun) is copied to
#      ModernTests_FastTier.xctestrun beside it, without the
#      MallocStackLogging variables (tools/swift_migration/test_tiers.py
#      strip-env). Every other variable of the test plan is kept.
#   3. Test: xcodebuild test-without-building -xctestrun that file, with one
#      -skip-testing: argument per slow-tier entry (test_tiers.py skip-args),
#      in parallel unless --serial. It runs on a pseudo-terminal
#      (script -q /dev/null ...): xcodebuild writes results and its end
#      marker on two streams, and through a pipe they arrive out of order.
#      The log, with the terminal's carriage returns removed, goes to
#      tmp/fast-tests/runs/<time>/test.log.
#   4. tools/swift_migration/test_timing.py (with --skip-list slow_tier.txt,
#      so the suites -skip-testing emptied are not taken for damage) reports
#      the run's times and the tests at or over the 10-second ceiling of
#      test-speed.md section 2. The ceiling is reported, not enforced (an
#      open question for the owner: test-tiers.md). The number of executed
#      tests is taken from its JSON output.
#
#   --dry-run   Print the commands of steps 1 to 3 exactly as they would run,
#               and the slow-tier entries with their reasons. Runs nothing.
#   --no-build  Skip step 1 and use the build already in tmp/sanitizers/plain.
#   --serial    Run the test classes one at a time (-parallel-testing-enabled NO).
#   --no-skip   Skip nothing: run the whole suite as the fast tier runs
#               (no address sanitizer, no MallocStackLogging). Its logs are
#               the evidence test_tiers.py propose-removals needs to take
#               entries out of the slow tier. Slow: about the whole suite.
#   --kill-test-hosts
#               Only kill this checkout's test hosts (below) and exit; for
#               cleaning up after an interrupted run, and for the tests.
#   -h, --help  Print this text.
#
# Interrupting the script kills the process group it started xcodebuild in
# and any process whose command is the plain build's test host executable
# (tmp/sanitizers/plain/Build/Development/iTerm2.app/Contents/MacOS/iTerm2
# under this checkout): the command must be that path exactly, or that path
# followed by a space and arguments; nothing else. The same happens after a
# normal end.
#
# Exit status: xcodebuild's (step 1 or 3), except 1 when the tests succeeded
# but the log shows no executed test, or there is no .xctestrun to run, and 2
# for a usage error.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
}

DRY_RUN=NO
KILL_ONLY=NO
NO_SKIP=NO
DO_BUILD=YES
PARALLEL=YES
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --dry-run) DRY_RUN=YES ;;
        --no-build) DO_BUILD=NO ;;
        --serial) PARALLEL=NO ;;
        --kill-test-hosts) KILL_ONLY=YES ;;
        --no-skip) NO_SKIP=YES ;;
        *) echo "error: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

SLOW_TIER="$HERE/slow_tier.txt"
BUILD_DIR="$ROOT/tmp/sanitizers/plain/Build"
XCTESTRUN="$BUILD_DIR/ModernTests_FastTier.xctestrun"
TEST_HOST_EXECUTABLE="$BUILD_DIR/Development/iTerm2.app/Contents/MacOS/iTerm2"
RUN_DIR="$ROOT/tmp/fast-tests/runs/$(date +%Y%m%d-%H%M%S)"

# True if the ps command line $1 is this checkout's test host: exactly its
# executable's path, or that path followed by a space.
is_test_host_command() {
    case "$1" in
        "$TEST_HOST_EXECUTABLE"|"$TEST_HOST_EXECUTABLE "*) return 0 ;;
    esac
    return 1
}
kill_test_hosts() {
    local pid command
    # FAST_TESTS_PS: the tests' stand-in for ps, which lists only their own
    # processes, so that no mistake in the matcher can reach anything else.
    "${FAST_TESTS_PS:-ps}" -axo pid=,command= 2>/dev/null | while read -r pid command; do
        if is_test_host_command "$command"; then
            kill -KILL "$pid" 2>/dev/null
        fi
    done
}
if [ "$KILL_ONLY" = YES ]; then
    kill_test_hosts
    exit 0
fi

SKIP_ARGS=()
while IFS= read -r arg; do
    SKIP_ARGS+=("$arg")
done < <(python3 -B "$HERE/test_tiers.py" skip-args "$SLOW_TIER")
if [ ${#SKIP_ARGS[@]} -eq 0 ]; then
    echo "error: no slow-tier entries read from $SLOW_TIER" >&2
    exit 1
fi
TIMING_SKIP=(--skip-list "$SLOW_TIER")
if [ "$NO_SKIP" = YES ]; then
    SKIP_ARGS=()
    TIMING_SKIP=()
fi

BUILD_COMMAND=("$HERE/sanitizer_tests.sh" plain --build-only)
# The .xctestrun the build writes; its name has the SDK version in it.
find_source_xctestrun() {
    local found=()
    local f
    for f in "$BUILD_DIR"/ModernTests_ModernTests_*-"$(uname -m)".xctestrun; do
        [ -f "$f" ] && found+=("$f")
    done
    if [ ${#found[@]} -ne 1 ]; then
        return 1
    fi
    printf '%s\n' "${found[0]}"
}
TEST_COMMAND=(xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination 'platform=macOS'
              -parallel-testing-enabled "$PARALLEL" ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"})

# Prints a command so that it can be pasted into a shell.
print_command() {
    local out="" a
    for a in "$@"; do
        case "$a" in
            *[!A-Za-z0-9_./:=+@%,-]*) out+=" '${a//\'/\'\\\'\'}'" ;;
            *) out+=" $a" ;;
        esac
    done
    printf '%s\n' "${out# }"
}

echo "Fast tier: No address sanitizer, no MallocStackLogging (docs/swift-migration/test-speed.md section 2)."
if [ "$NO_SKIP" = YES ]; then
    echo "--no-skip: no test is skipped; the slow tier runs too."
else
    echo "Slow tier: ${#SKIP_ARGS[@]} entries skipped, from $SLOW_TIER:"
    grep -vE '^[[:space:]]*(#|$)' "$SLOW_TIER" | sed 's/^/  /'
fi

if [ "$DRY_RUN" = YES ]; then
    SOURCE="$(find_source_xctestrun)" || {
        SOURCE="$BUILD_DIR/ModernTests_ModernTests_<sdk>-$(uname -m).xctestrun"
        echo
        echo "(No build yet: <sdk> below is the SDK the build uses, for example macosx27.0.)"
    }
    echo
    echo "Commands (from $ROOT):"
    if [ "$DO_BUILD" = YES ]; then
        print_command "${BUILD_COMMAND[@]#$ROOT/}"
    fi
    print_command python3 -B "${HERE#$ROOT/}/test_tiers.py" strip-env "$SOURCE" "$XCTESTRUN"
    print_command "${TEST_COMMAND[@]}"
    echo "(run as: script -q /dev/null <that command>, its output to $RUN_DIR/test.log)"
    exit 0
fi

cd "$ROOT"

GROUP_PID=""
on_signal() {
    trap '' INT TERM HUP
    echo "fast_tests.sh: interrupted; stopping xcodebuild and the test hosts" >&2
    [ -n "$GROUP_PID" ] && kill -KILL -- "-$GROUP_PID" 2>/dev/null
    kill_test_hosts
    exit 130
}
trap on_signal INT TERM HUP
run_in_group() {
    set -m
    "$@" &
    GROUP_PID=$!
    set +m
    wait "$GROUP_PID"
    local status=$?
    GROUP_PID=""
    return $status
}

if [ "$DO_BUILD" = YES ]; then
    run_in_group "${BUILD_COMMAND[@]}"
    STATUS=$?
    if [ $STATUS -ne 0 ]; then
        echo "error: the build failed with status $STATUS" >&2
        exit $STATUS
    fi
fi

SOURCE="$(find_source_xctestrun)" || {
    echo "error: no .xctestrun (or more than one) for $(uname -m) in $BUILD_DIR; build first" >&2
    exit 1
}
python3 -B "$HERE/test_tiers.py" strip-env "$SOURCE" "$XCTESTRUN" || exit 1

mkdir -p "$RUN_DIR"
test_step() {
    # script exits with the command's status. Its stdin is /dev/null, and at
    # that end of file the terminal echoes "^D" and two backspaces before the
    # first line; perl removes them and the terminal's carriage returns.
    script -q /dev/null "${TEST_COMMAND[@]}" < /dev/null 2>&1 \
        | perl -pe 'BEGIN { $| = 1 } s/^\^D\x08\x08// if $. == 1; s/\r+$//' \
        | tee "$RUN_DIR/test.log"
    return "${PIPESTATUS[0]}"
}
echo "Testing (log: $RUN_DIR/test.log)..."
START=$(date +%s)
run_in_group test_step
STATUS=$?
kill_test_hosts
echo "Tests finished with status $STATUS in $(( $(date +%s) - START )) seconds."

echo "Times, with the tests at or over the 10-second ceiling (reported, not enforced):"
python3 -B "$HERE/test_timing.py" "$RUN_DIR/test.log" --threshold 10 ${TIMING_SKIP[@]+"${TIMING_SKIP[@]}"} \
    | tee "$RUN_DIR/timing.txt"
# The number of results of any kind (passed, failed, skipped, other), in
# either log format; 0 if the log has none (test_timing.py then exits 2).
EXECUTED=$(python3 -B "$HERE/test_timing.py" "$RUN_DIR/test.log" --json ${TIMING_SKIP[@]+"${TIMING_SKIP[@]}"} 2>/dev/null \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["results"]["total"])' 2>/dev/null || echo 0)
if [ "${EXECUTED:-0}" -eq 0 ]; then
    echo "error: the run executed no tests; it proves nothing" >&2
    [ "$STATUS" -eq 0 ] && STATUS=1
fi
exit $STATUS
