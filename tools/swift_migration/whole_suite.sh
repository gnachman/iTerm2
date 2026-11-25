#!/bin/bash
# Run the whole ModernTests suite with tools/run_tests.expect under the
# whole-suite lock, for the Objective-C to Swift migration
# (docs/swift-migration/orchestration.md section 3, "Heavy jobs and the
# machine"; README.md section 5, gate step 3; lifecycle.md section 5, the
# closing checks).
#
# Usage:
#   tools/swift_migration/whole_suite.sh [--serial] [--no-wait]
#
# It runs, from the checkout it is in,
#   tools/run_tests.expect -parallel
# or with --serial `tools/run_tests.expect ModernTests` (run_tests.expect
# needs an argument; the bare target selects the whole suite), holding the
# machine-wide whole-suite lock of tools/swift_migration/suite_guard.py lock
# (its header is the manual): at most one whole suite, plain or sanitized,
# runs at a time on the machine, across every checkout and lane, by day and
# by night. That rule is the orchestrator's decision of 2026-11-24, recorded
# in decisions.md and open to the owner: it bounds the memory in use and
# keeps a failure attributable to one run. It was not found to be the cause
# of that night's hangs, which were per test host, in tests that wait with
# no deadline. The agents of the migration run the whole suite through this
# script, never run_tests.expect -parallel directly: run_tests.expect is the
# owner's script and does not take the lock itself.
#
# It waits for the lock, saying who holds it; with --no-wait it fails at
# once (status 75), naming the holder. A holder that died left no lock
# behind (an flock is released by the kernel).
#
# What it does not do, unlike sanitizer_tests.sh, fast_tests.sh and
# coverage_tests.sh:
#   - No per-test time allowance: run_tests.expect turns every argument but
#     -parallel into a test name, so the flags those scripts give
#     xcodebuild (-test-timeouts-enabled YES
#     -default-test-execution-time-allowance N
#     -maximum-test-execution-time-allowance N) cannot be passed through.
#     The owner's one-line change would add them to its `spawn xcodebuild
#     test` line.
#   - Not suite_guard.py's watchdog: run_tests.expect keeps its own, which
#     stops the run after 300 seconds with no output from xcodebuild
#     (RUN_TESTS_STALL_SECONDS changes it and is passed through), saves the
#     test hosts' stacks with tools/report_test_stall.sh to
#     tmp/test-stall-<time>.txt, kills the run and exits 1, as for a test
#     failure. The two are told apart by that file: when a
#     tmp/test-stall-*.txt that was not there when the lock was taken
#     appears during a run that failed, suite_guard.py names it and the
#     status is 124 instead.
#     (run_tests.expect's xcodebuild runs on a terminal, so its output is
#     not held back by buffering; its watchdog sees only xcodebuild's
#     output, not the result bundle.)
#
#   --serial    Run the test classes one at a time (no -parallel): readable
#               failures, about 20 minutes.
#   --no-wait   Fail at once when another whole-suite run holds the lock.
#   -h, --help  Print this text.
#
# The script prints its pid first, so that a caller that runs it in the
# background can wait for it with a bound:
#   python3 tools/swift_migration/suite_guard.py wait --pid PID --seconds 540
# On INT, TERM or HUP, run_tests.expect gets SIGTERM, so that its own trap
# runs (it kills xcodebuild's tree), for up to 30 seconds; then whatever is
# left below it is killed, then this checkout's test hosts (an executable
# under <checkout>/Build/ run with -suite iterm2-tests and started after the
# lock was taken; never by name alone), and only then is the lock released
# (suite_guard.py lock, its header).
#
# Exit status: 124 when run_tests.expect's stall watchdog stopped the run (a
# new tmp/test-stall-*.txt); 75 when --no-wait found the lock held; 2 for a
# usage error; 128 plus the signal when it is interrupted (it execs
# suite_guard.py lock); otherwise run_tests.expect's (0 passed; 1 for a
# failure or a run that executed no tests). Test names are refused
# (status 2): a targeted run needs no lock, so run tools/run_tests.expect for
# it directly.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)" || exit 2
ROOT="$(cd "$HERE/../.." && pwd)" || exit 2

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
}

PARALLEL=(-parallel)
GUARD=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --serial) PARALLEL=(ModernTests) ;;
        --no-wait) GUARD+=(--no-wait) ;;
        *) echo "error: whole_suite.sh runs the whole suite and takes no test names or other arguments: $1" >&2
           echo "(for a targeted run, use tools/run_tests.expect <tests> directly)" >&2
           exit 2 ;;
    esac
    shift
done

# RUN_TESTS_EXPECT: the tests' stand-in for tools/run_tests.expect.
EXPECT_SCRIPT="${RUN_TESTS_EXPECT:-$ROOT/tools/run_tests.expect}"
cd "$ROOT" || exit 2
echo "whole_suite.sh: pid $$"

exec python3 -B "$HERE/suite_guard.py" lock ${GUARD[@]+"${GUARD[@]}"} \
    --label "whole_suite.sh: run_tests.expect ${PARALLEL[*]} in $ROOT" \
    --host-prefix "$ROOT/Build" --stall-reports "$ROOT/tmp/test-stall-*.txt" \
    -- "$EXPECT_SCRIPT" "${PARALLEL[@]}"
