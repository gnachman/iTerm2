#!/bin/bash
# Run the fast test tier of ModernTests, for the Objective-C to Swift
# migration (docs/swift-migration/test-speed.md section 2, test-tiers.md).
#
# Usage:
#   tools/swift_migration/fast_tests.sh [--dry-run] [--no-build] [--serial] [--no-skip]
#                                       [--workers N] [--jobs N] [--enforce-budget]
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
#      in parallel unless --serial, with two workers
#      (-parallel-testing-worker-count 2 -maximum-parallel-testing-workers 2,
#      the cap of tools/run_tests.expect -parallel) unless --workers. Before
#      2026-11-23 the count was left to xcodebuild (about one per core), so
#      the wall-clock times of earlier fast-tier runs are not comparable.
#      It runs on a pseudo-terminal, under
#      tools/swift_migration/suite_guard.py run --pty (until 2026-11-24,
#      script -q /dev/null): xcodebuild writes results and its end marker
#      on two streams, and through a pipe they arrive out of order. The
#      log, with the terminal's carriage returns removed, goes to
#      tmp/fast-tests/runs/<time>/test.log. suite_guard.py also holds the
#      whole-suite lock for the step and runs the stall watchdog (below).
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
#   --workers N N parallel workers instead of two. Refused with --serial.
#   --jobs N    At most N concurrent build tasks in step 1 (passed on as
#               sanitizer_tests.sh --jobs N, which gives xcodebuild -jobs N).
#               Step 3 builds nothing. Refused with --no-build.
#   --no-skip   Skip nothing: run the whole suite as the fast tier runs
#               (no address sanitizer, no MallocStackLogging). Its logs are
#               the evidence test_tiers.py propose-removals needs to take
#               entries out of the slow tier. Slow: about the whole suite.
#   --enforce-budget
#               Fail (status 1, unless the run already failed) when the whole
#               command takes longer than the fast tier's budget. Without it
#               the comparison is printed and fails nothing. Refused with
#               --dry-run and --kill-test-hosts. See below.
#   --kill-test-hosts
#               Only kill this checkout's test hosts (below) and exit; for
#               cleaning up after an interrupted run, and for the tests.
#   --test-allowance-seconds N
#               XCTest's per-test time limit (-test-timeouts-enabled YES
#               -default-test-execution-time-allowance N): a test that runs
#               longer fails and its host is replaced. Default 60 (XCTest
#               rounds up to whole minutes; the fast tier's slowest tests
#               take seconds: orchestration.md section 3 has the evidence).
#               0 turns it off.
#   --max-test-allowance-seconds M
#               The most a test may ask for with executionTimeAllowance
#               (-maximum-test-execution-time-allowance M). Default: N.
#   --stall-seconds N
#               Stop the test step after N seconds with no test progress
#               (default: the larger allowance plus 300, so 360; 300 with
#               the allowance off; 0 turns the watchdog off). See below.
#   --no-wait   When another whole-suite run holds the whole-suite lock,
#               fail at once (status 75), naming it, instead of waiting.
#   -h, --help  Print this text.
#
# The whole-suite lock: every run of the fast tier is a whole-suite run (the
# suite less the slow tier), so its test step holds the machine-wide
# whole-suite lock of suite_guard.py: one whole suite, plain or sanitized,
# at a time on the machine, across every checkout and lane
# (docs/swift-migration/orchestration.md section 3). It waits for the lock,
# saying who holds it, unless --no-wait. The build (step 1) does not take
# it.
#
# The stall watchdog (added 2026-11-24, after five test hosts in three
# whole suites each waited for hours in one test one night): the backstop
# behind the allowance. Its progress signal is each test host's output in
# the step's result bundle (tmp/fast-tests/runs/<time>/results/
# test.xcresult; suite_guard.py's header has the rule): when a host has
# been inside one test for --stall-seconds, or no test progress has shown
# for that long, suite_guard.py records, in the run directory's stall/,
# a sample of each of this run's test hosts (the plain build's executable
# with -suite iterm2-tests), the process list with CPU, threads and memory
# footprint, the machine's memory state, the tail of the log and the tests
# in progress per worker (each command bounded in time), then kills
# xcodebuild's process group and the test hosts, prints its account (also
# in stall/stall.txt), and the script exits 124.
#
# The script prints its pid first, so that a caller that runs it in the
# background can wait for it with a bound (suite_guard.py wait --pid PID
# --seconds N).
#
# The budget: at the end the script prints the whole command's wall time,
# build included and time spent waiting for the whole-suite lock left out
# (the wait is printed on a line of its own), against FAST_TIER_BUDGET_SECONDS (300 s with two workers,
# the owner, 2026-11-23; test-tiers.md section 1), "under" or "OVER". Going
# over fails the run only with --enforce-budget: test-speed.md section 3
# makes a commit that pushes the fast tier over budget fail the gate, but
# the gate runs the whole suite at step 3, not this script, until the owner
# switches it; from then the gate runs it with --enforce-budget.
#
# Interrupting the script kills the process group it started xcodebuild in
# and any process whose command is the plain build's test host executable
# (tmp/sanitizers/plain/Build/Development/iTerm2.app/Contents/MacOS/iTerm2
# under this checkout): the command must be that path exactly, or that path
# followed by a space and arguments; nothing else. The same happens after a
# normal end.
#
# Exit status: 124 when the stall watchdog stopped the test step; 75 when
# --no-wait found the whole-suite lock held; otherwise
# xcodebuild's (step 1 or 3), except 1 when the tests succeeded
# but the log shows no executed test, there is no .xctestrun to run, or (with
# --enforce-budget) the whole command went over the budget, and 2 for a
# usage error.

set -uo pipefail

COMMAND_START=$(date +%s)
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
}

# san_check_count, san_parallel_args and SAN_DEFAULT_WORKERS.
source "$HERE/sanitizer_common.sh"

# The fast tier's wall-clock budget for the whole command, build included
# (the owner, 2026-11-23: “Let it go for 300 seconds”; test-tiers.md
# section 1).
FAST_TIER_BUDGET_SECONDS=300

DRY_RUN=NO
ENFORCE_BUDGET=NO
KILL_ONLY=NO
NO_SKIP=NO
DO_BUILD=YES
PARALLEL=YES
WORKERS=""
JOBS=""
STALL_SECONDS=""
ALLOWANCE=60
MAX_ALLOWANCE=""
NO_WAIT=NO
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --dry-run) DRY_RUN=YES ;;
        --no-wait) NO_WAIT=YES ;;
        --stall-seconds|--test-allowance-seconds|--max-test-allowance-seconds)
            san_check_seconds "$1" "${2-}" || exit 2
            case "$1" in
                --stall-seconds) STALL_SECONDS="$2" ;;
                --test-allowance-seconds) ALLOWANCE="$2" ;;
                *) MAX_ALLOWANCE="$2" ;;
            esac
            shift ;;
        --no-build) DO_BUILD=NO ;;
        --serial) PARALLEL=NO ;;
        --kill-test-hosts) KILL_ONLY=YES ;;
        --no-skip) NO_SKIP=YES ;;
        --enforce-budget) ENFORCE_BUDGET=YES ;;
        --workers)
            san_check_count "$1" "${2-}" || exit 2
            WORKERS="$2"
            shift ;;
        --jobs)
            san_check_count "$1" "${2-}" || exit 2
            JOBS="$2"
            shift ;;
        *) echo "error: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[ -n "$MAX_ALLOWANCE" ] || MAX_ALLOWANCE="$ALLOWANCE"
# The watchdog waits longer than XCTest would, so that the allowance acts
# first however it is raised.
if [ -z "$STALL_SECONDS" ]; then
    if [ "$ALLOWANCE" -gt 0 ]; then STALL_SECONDS=$(( MAX_ALLOWANCE + 300 )); else STALL_SECONDS=300; fi
fi
if [ "$ALLOWANCE" -gt 0 ] && [ "$MAX_ALLOWANCE" -lt "$ALLOWANCE" ]; then
    echo "error: --max-test-allowance-seconds ($MAX_ALLOWANCE) is below --test-allowance-seconds ($ALLOWANCE)" >&2
    exit 2
fi
if [ -n "$WORKERS" ] && [ "$PARALLEL" = NO ]; then
    echo "error: --workers needs a parallel run; --serial runs one class at a time" >&2
    exit 2
fi
if [ "$ENFORCE_BUDGET" = YES ] && { [ "$DRY_RUN" = YES ] || [ "$KILL_ONLY" = YES ]; }; then
    echo "error: --enforce-budget applies to a run; --dry-run and --kill-test-hosts run nothing" >&2
    exit 2
fi
if [ -n "$JOBS" ] && [ "$DO_BUILD" = NO ]; then
    echo "error: --jobs applies to the build, which --no-build leaves out" >&2
    exit 2
fi

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
if [ -n "$JOBS" ]; then
    BUILD_COMMAND+=(--jobs "$JOBS")
fi
san_parallel_args "$PARALLEL" "$WORKERS"
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
san_allowance_args "$ALLOWANCE" "$MAX_ALLOWANCE"
RESULT_BUNDLE="$RUN_DIR/results/test.xcresult"
TEST_COMMAND=(xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination 'platform=macOS'
              "${SAN_PARALLEL_ARGS[@]}" ${SAN_ALLOWANCE_ARGS[@]+"${SAN_ALLOWANCE_ARGS[@]}"}
              -resultBundlePath "$RESULT_BUNDLE" ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"})

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

echo "fast_tests.sh: pid $$"
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
    echo "(run on a terminal under suite_guard.py run --pty --lock --stall-seconds $STALL_SECONDS, its output to $RUN_DIR/test.log)"
    exit 0
fi

cd "$ROOT"

GROUP_PID=""
# suite_guard.py starts the test command in a process group of its own and
# writes its id here, so that an interruption reaches it too.
PGID_FILE="$RUN_DIR/.test-pgid"
on_signal() {
    trap '' INT TERM HUP
    echo "fast_tests.sh: interrupted; stopping xcodebuild and the test hosts" >&2
    [ -n "$GROUP_PID" ] && kill -KILL -- "-$GROUP_PID" 2>/dev/null
    [ -s "$PGID_FILE" ] && kill -KILL -- "-$(cat "$PGID_FILE")" 2>/dev/null
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
    # On a terminal (its carriage returns removed from the log), under the
    # whole-suite lock and the stall watchdog. The command's stdin is
    # /dev/null and is not the terminal, so no "^D" is echoed.
    local guard=(python3 -B "$HERE/suite_guard.py" run --pty --lock --log "$RUN_DIR/test.log"
                 --stall-seconds "$STALL_SECONDS" --stall-dir "$RUN_DIR/stall"
                 --result-bundle "$RESULT_BUNDLE"
                 --host-prefix "$BUILD_DIR" --pgid-file "$PGID_FILE"
                 --lock-wait-file "$LOCK_WAIT_FILE"
                 --label "fast_tests.sh (run $RUN_DIR)")
    [ "$NO_WAIT" = YES ] && guard+=(--no-wait)
    "${guard[@]}" -- "${TEST_COMMAND[@]}"
}
# Seconds the step waited for the whole-suite lock, which the budget leaves
# out: a fast tier queued behind another whole suite is not slow.
LOCK_WAIT_FILE="$RUN_DIR/.lock-wait"
echo "Testing (log: $RUN_DIR/test.log)..."
START=$(date +%s)
run_in_group test_step
STATUS=$?
kill_test_hosts
echo "Tests finished with status $STATUS in $(( $(date +%s) - START )) seconds."
if [ "$STATUS" -eq 75 ] && [ ! -e "$RUN_DIR/test.log" ]; then
    echo "error: --no-wait: another whole-suite run holds the whole-suite lock (named above); nothing was tested" >&2
    exit 75
fi
if [ "$STATUS" -eq 124 ] && [ -f "$RUN_DIR/stall/stall.txt" ]; then
    echo "error: the test step stalled and was stopped by the watchdog (status 124); see $RUN_DIR/stall/stall.txt" >&2
    exit 124
fi

echo "Times, with the tests at or over the 10-second ceiling (reported, not enforced):"
python3 -B "$HERE/test_timing.py" "$RUN_DIR/test.log" --threshold 10 ${TIMING_SKIP[@]+"${TIMING_SKIP[@]}"} \
    | tee "$RUN_DIR/timing.txt"
# Tests that ran out of the time allowance, counted apart (test_timing.py
# counts each as whatever XCTest printed for it, passed included).
ALLOWANCE_REPORT=$(san_allowance_report "$RUN_DIR/test.log" "$ALLOWANCE")
if [ -n "$ALLOWANCE_REPORT" ]; then
    printf '%s\n' "$ALLOWANCE_REPORT" | tee -a "$RUN_DIR/timing.txt"
fi
# The number of results of any kind (passed, failed, skipped, other), in
# either log format; 0 if the log has none (test_timing.py then exits 2).
EXECUTED=$(python3 -B "$HERE/test_timing.py" "$RUN_DIR/test.log" --json ${TIMING_SKIP[@]+"${TIMING_SKIP[@]}"} 2>/dev/null \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["results"]["total"])' 2>/dev/null || echo 0)
if [ "${EXECUTED:-0}" -eq 0 ]; then
    echo "error: the run executed no tests; it proves nothing" >&2
    [ "$STATUS" -eq 0 ] && STATUS=1
fi
LOCK_WAIT=0
if [ -f "$LOCK_WAIT_FILE" ]; then
    LOCK_WAIT=$(tr -cd '0-9' < "$LOCK_WAIT_FILE")
    LOCK_WAIT=${LOCK_WAIT:-0}
    rm -f "$LOCK_WAIT_FILE"
fi
if [ "$LOCK_WAIT" -gt 0 ]; then
    echo "Waited $LOCK_WAIT s for the whole-suite lock; left out of the budget."
fi
ELAPSED=$(( $(date +%s) - COMMAND_START - LOCK_WAIT ))
if [ "$ELAPSED" -gt "$FAST_TIER_BUDGET_SECONDS" ]; then
    echo "Whole command: $ELAPSED s; fast tier budget $FAST_TIER_BUDGET_SECONDS s (FAST_TIER_BUDGET_SECONDS): OVER."
    if [ "$ENFORCE_BUDGET" = YES ]; then
        echo "error: the fast tier went over its budget (test-speed.md section 3)" >&2
        [ "$STATUS" -eq 0 ] && STATUS=1
    else
        echo "Over budget, not enforced (no --enforce-budget)."
    fi
else
    echo "Whole command: $ELAPSED s; fast tier budget $FAST_TIER_BUDGET_SECONDS s (FAST_TIER_BUDGET_SECONDS): under."
fi
exit $STATUS
