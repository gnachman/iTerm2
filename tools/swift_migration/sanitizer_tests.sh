#!/bin/bash
# Build and run the ModernTests tests under a sanitizer, for the Objective-C to
# Swift migration (docs/swift-migration/phase0.md section 4,
# nullability.md section 7, translation-rules.md section 1 "Discovery runs",
# concurrency.md section 10).
#
# Usage:
#   tools/swift_migration/sanitizer_tests.sh MODE [options] [TEST ...]
#
#   MODE is one of:
#     nullability  -fsanitize=nullability on the Objective-C, C and C++. The
#                  first violated nullability claim writes its report (with
#                  its stack) to a file in the run's reports/ directory and
#                  then aborts the test host, so the test fails and
#                  tools/swift_migration/test_timing.py reports the log as
#                  incomplete. The report is not in test.log (with --parallel
#                  xcodebuild would not pass a worker's stderr on anyway);
#                  the summary reads reports/ and test.log both. Reports
#                  matching
#                  tools/swift_migration/sanitizer_nullability_suppressions.txt
#                  (known, not yet triaged violations) are hidden: not
#                  written anywhere and no abort. With --collect nothing
#                  aborts and nothing is suppressed: every report goes to a
#                  file, for triage.
#
#                  The abort comes from UBSAN_OPTIONS=halt_on_error=1 on a
#                  recoverable build, not from -fno-sanitize-recover: the
#                  runtime calls abort after an unrecoverable check even when
#                  the report is suppressed, and the app violates a claim
#                  while launching (iTermVariables.m), so with
#                  -fno-sanitize-recover no test could run at all. The same
#                  build serves both the aborting run and --collect.
#
#                  Until the first triage of reports, ordinary tests also
#                  violate claims (VT100ScreenTests aborts in
#                  iTermLineBlockArray.m on most of its tests), and each
#                  abort costs a test-host restart. Use --collect to survey.
#     integer      The integer discovery group,
#                  -fsanitize=signed-integer-overflow,implicit-conversion,
#                  float-cast-overflow,integer-divide-by-zero,shift,bounds, in
#                  recover mode, so one run collects every report. Reports go
#                  to files, which are summarized at the end. The UBSan
#                  runtime prints each source location once per process.
#                  The Development configuration compiles at -O0, where
#                  bounds does only its array-bounds part: indexing into an
#                  array whose bound the compiler knows (int a[4]; a[i]).
#                  Its local-bounds part, pointer accesses into local
#                  objects, needs optimization; NSArray is never checked.
#                  The truncation checks (implicit-signed-integer-truncation
#                  and implicit-unsigned-integer-truncation) come with
#                  implicit-conversion; the sign-change check does not (see
#                  integer-sign).
#     integer-sign The integer group plus the sign-change check,
#                  implicit-integer-sign-change: a conversion that keeps or
#                  widens the width but changes the sign of the value (int -1
#                  to NSUInteger, NSUInteger above NSIntegerMax to NSInteger).
#                  Xcode's clang (Apple clang 21) refuses
#                  -fsanitize=implicit-integer-sign-change for arm64 macOS in
#                  its driver ("unsupported option") and leaves it out of
#                  implicit-conversion, but its compiler and its UBSan runtime
#                  implement it: the flag is given to the compiler itself,
#                  -Xclang -fsanitize=implicit-integer-sign-change, with
#                  -Xclang -fsanitize-recover=implicit-integer-sign-change
#                  (without it the first report aborts). The runtime is the
#                  one the integer group already links. A conversion that
#                  both truncates and changes the sign is reported as
#                  implicit-signed-integer-truncation-or-sign-change. Recover
#                  mode and reports to files, as for integer, with its own
#                  build directory, so the integer build is left alone.
#                  Expect many more reports than integer.
#     thread       The thread sanitizer (ENABLE_THREAD_SANITIZER=YES, Objective-C
#                  and Swift), in recover mode, reports to files. For tests
#                  only: never build or run the app with it (it flags every
#                  Metal frame). TSAN_OPTIONS exitcode=0, so a report does
#                  not fail a test host by itself. Instead the summary
#                  compares the reports with the baseline,
#                  docs/swift-migration/thread-baseline.tsv (the ledger is
#                  thread-baseline.md), and the run fails if any report is
#                  not in it or cannot be compared (a frame the comparison
#                  needs has no name). The comparison first names unnamed
#                  frames with atos on this mode's build, the binaries that
#                  just ran (sanitizer_summary.py --symbolize). With
#                  --collect the comparison is printed and nothing fails on
#                  reports. Run serially: --parallel loses test hosts in
#                  this mode (thread-baseline.md section 4).
#     plain        No sanitizer at all: the address sanitizer off as in every
#                  mode, and nothing added. The fast test tier runs this way
#                  (docs/swift-migration/test-speed.md section 2). The script
#                  checks that the app links no sanitizer runtime. There are
#                  no reports; the summary only confirms that tests ran.
#
#   TEST is an -only-testing name such as ModernTests/SanitizerProbeTests or
#   ModernTests/FooTests/testBar. With no TEST the whole suite runs; do that
#   only for a deliberate full sanitizer run.
#
#   Options:
#     --probe       Set ITERM2_SANITIZER_PROBE=MODE in the test host, which
#                   turns on the matching tests of ModernTests/SanitizerProbeTests.m
#                   (each commits one violation, to show the mode works). Without
#                   it they are skipped, as they are under tools/run_tests.expect.
#     --collect     nullability: report without aborting, every report to a
#                   file, no suppressions (for the triage of reports).
#                   thread: compare with the baseline but do not fail the run
#                   on reports (for building or re-judging the baseline).
#     --parallel    Run test classes in parallel worker processes, like
#                   tools/run_tests.expect -parallel.
#     --build-only  Build for testing and stop.
#     --no-build    Skip the separate build-for-testing step. The test step
#                   is `xcodebuild test`, which still brings the build up to
#                   date (a no-op when nothing changed); it is used rather
#                   than test-without-building because only `test` ends its
#                   log with the "** TEST SUCCEEDED **" or "** TEST FAILED **"
#                   line that test_timing.py needs to call a log complete.
#     -h, --help    Print this text.
#
#   Environment:
#     SIGNED=1      Build signed, as for tools/run_tests.expect. The default is
#                   unsigned, also as for tools/run_tests.expect.
#
# Examples:
#   tools/swift_migration/sanitizer_tests.sh nullability --probe ModernTests/SanitizerProbeTests
#   tools/swift_migration/sanitizer_tests.sh integer ModernTests/SwiftMigrationArithmeticTests
#   tools/swift_migration/sanitizer_tests.sh integer-sign --parallel
#   tools/swift_migration/sanitizer_tests.sh thread --parallel
#   tools/swift_migration/sanitizer_tests.sh plain --parallel
#
# Where things go:
#   tmp/sanitizers/<mode>/Build/                The mode's own SYMROOT and OBJROOT.
#                                               Nothing is written to Build/, so
#                                               the regular Development build,
#                                               the address sanitizer test build
#                                               and the code database are left
#                                               alone. Each directory is a full
#                                               build of the app and its tests.
#   tmp/sanitizers/runs/<mode>-<time>/build.log The xcodebuild build output.
#   tmp/sanitizers/runs/<mode>-<time>/test.log  The xcodebuild test output, the
#                                               format test_timing.py reads.
#   tmp/sanitizers/runs/<mode>-<time>/reports/  Report files, one per process
#                                               that reported (UBSan/TSan
#                                               log_path), in every mode.
#   tmp/sanitizers/runs/<mode>-<time>/summary.txt
#                                               The ignore list and
#                                               suppressions in force, then
#                                               sanitizer_summary.py's output.
#   The summary reads reports/ and also test.log, where a report lands only
#   if a runtime could not write its file; a report in both is counted once.
#   Run directories accumulate, one per run; nothing deletes them. Clean up
#   with `rm -rf tmp/sanitizers/runs` (the builds in tmp/sanitizers/<mode>
#   are kept, so the next run is still incremental).
#
# Not collected: helper processes that the test host starts through launchd
# (XPC services such as pidinfo) do not inherit the test runner's
# environment, so they run without UBSAN_OPTIONS and TSAN_OPTIONS: their
# reports go to their own stderr, which nothing captures, and no
# suppressions or halt apply to them.
#
# What is instrumented: the flags are added on the xcodebuild command line as
# OTHER_CFLAGS='$(inherited) ...' (OTHER_CPLUSPLUSFLAGS inherit OTHER_CFLAGS in
# this project), so they reach every C, Objective-C, C++ and Objective-C++
# compile of every target the scheme builds, with each target's own flags
# kept: iTerm2Shared, iTerm2SharedARC, iTerm2, ModernTests, pidinfo,
# iTermServer, ShellLauncher, iTerm2SandboxedWorker, SSKeychain and the C
# targets of Swift packages. tools/swift_migration/sanitizer_ignorelist.txt
# (-fsanitize-ignorelist=) then exempts submodules/, ThirdParty/ except
# ThirdParty/PSMTabBarControl/, Swift package checkouts, Companion/ and the
# generated protobuf code. The ignore list matches the file a check is in, so
# an inline function from an SDK header (dispatch_once in dispatch/once.h)
# is still checked where an exempt file calls it; such a report has an SDK
# location and is counted as other code. BetterFontPicker, ColorPicker and
# SearchableComboListView are checked-in prebuilt frameworks and are not
# compiled, so not instrumented. Swift is instrumented only by the thread
# mode.
#
# How the runtime is linked: for nullability and integer, the same
# -fsanitize=<group> is added to OTHER_LDFLAGS='$(inherited) ...', so the clang
# driver links libclang_rt.ubsan_osx_dynamic.dylib (with an absolute rpath to
# the Xcode toolchain, so the build runs only on a Mac with that Xcode) into
# every linked image: iTerm2.debug.dylib (a Development app's code; the
# iTerm2 executable is a stub that loads it), ModernTests.xctest, iTermServer,
# ShellLauncher, pidinfo and iTerm2SandboxedWorker. Xcode's ENABLE_UNDEFINED_BEHAVIOR_SANITIZER is not used:
# it compiles the whole -fsanitize=undefined set, not just these groups. For
# thread, ENABLE_THREAD_SANITIZER=YES has Xcode compile and link with
# -fsanitize=thread. The script checks that the app links the runtime.
#
# The address sanitizer, which the ModernTests test plan enables, is off in
# every mode (it cannot be combined with the thread sanitizer, and the other
# modes are cheaper and their reports clearer without it).
#
# Reading the results: tools/swift_migration/sanitizer_summary.py groups
# reports by kind and source location and separates the migration's scope
# from other code. It runs on the reports directory at the end of each run;
# run it again by hand with `python3 -B tools/swift_migration/sanitizer_summary.py DIR`.
#
# Every run says which ignore list and suppressions file are in force, with
# their numbers of entries, on the console and in summary.txt. The script
# refuses to run (status 2) in a checkout whose path has a directory named
# submodules, ThirdParty or Companion, since the ignore list would then
# exempt every file.
#
# Interrupting the script (INT, TERM, HUP), during the build or the tests,
# kills the process group the script started xcodebuild in, and any process
# whose command is this mode's test host executable
# (tmp/sanitizers/<mode>/Build/Development/iTerm2.app/Contents/MacOS/iTerm2),
# since test hosts are not started in that group; nothing else. The same
# test hosts are killed after a normal end. There is no stall watchdog as in
# tools/run_tests.expect.
#
# Exit status: xcodebuild's, except 1 when xcodebuild succeeded but the run
# executed no tests (a misspelled TEST runs nothing and would look clean;
# skipped tests count as executed), the summary could not be made, or (thread
# mode without --collect) a report is outside the baseline or cannot be
# compared with it, and 2 for a usage error or a refused checkout path. So a
# thread run exits 0 only if the tests passed and every report is in the
# baseline.

set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/sanitizer_common.sh"

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
}

MODE=""
PROBE=NO
COLLECT=NO
PARALLEL=NO
DO_BUILD=YES
DO_TEST=YES
TESTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --probe) PROBE=YES ;;
        --collect) COLLECT=YES ;;
        --parallel|-parallel) PARALLEL=YES ;;
        --build-only) DO_TEST=NO ;;
        --no-build) DO_BUILD=NO ;;
        nullability|integer|integer-sign|thread|plain)
            if [ -n "$MODE" ]; then echo "error: more than one mode" >&2; exit 2; fi
            MODE="$1" ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) TESTS+=("$1") ;;
    esac
    shift
done
if [ -z "$MODE" ]; then
    usage >&2
    exit 2
fi
if [ "$COLLECT" = YES ] && [ "$MODE" != nullability ] && [ "$MODE" != thread ]; then
    echo "error: --collect applies to the nullability and thread modes; the other modes always collect" >&2
    exit 2
fi

san_check_root_path || exit 2

BUILD_DIR="$SAN_ROOT/tmp/sanitizers/$MODE"
RUN_DIR="$SAN_ROOT/tmp/sanitizers/runs/$MODE-$(date +%Y%m%d-%H%M%S)"
REPORTS="$RUN_DIR/reports"
THREAD_BASELINE="$SAN_ROOT/docs/swift-migration/thread-baseline.tsv"
mkdir -p "$BUILD_DIR" "$REPORTS"

# What is in force, stated on the console and at the top of summary.txt.
IN_FORCE="Ignore list (C, Objective-C, C++ compiles): $SAN_IGNORELIST ($(san_count_entries "$SAN_IGNORELIST") entries)."
if [ "$MODE" = nullability ] && [ "$COLLECT" = NO ]; then
    IN_FORCE+=$'\n'"Suppressions: $SAN_NULLABILITY_SUPPRESSIONS ($(san_count_entries "$SAN_NULLABILITY_SUPPRESSIONS") entries)."
    IN_FORCE+=$'\n'"Reports matching a suppression are hidden: not written anywhere, and they do not abort. Run with --collect to see them."
else
    IN_FORCE+=$'\n'"Suppressions: none."
fi
if [ "$MODE" = thread ]; then
    IN_FORCE+=$'\n'"Baseline: $THREAD_BASELINE ($(( $(san_count_entries "$THREAD_BASELINE") - 1 )) entries)."
    if [ "$COLLECT" = YES ]; then
        IN_FORCE+=$'\n'"--collect: reports outside the baseline are listed and do not fail the run."
    else
        IN_FORCE+=$'\n'"A report outside the baseline, or one that cannot be compared with it, fails the run."
    fi
fi

CFLAGS="\$(inherited) -fsanitize-ignorelist=$SAN_IGNORELIST"
LDFLAGS="\$(inherited)"
EXTRA_ARGS=(-enableThreadSanitizer NO ENABLE_THREAD_SANITIZER=NO)
RUNTIME=ubsan
case "$MODE" in
    nullability)
        CFLAGS+=" -fsanitize=$SAN_NULLABILITY_GROUP -fsanitize-recover=$SAN_NULLABILITY_GROUP"
        LDFLAGS+=" -fsanitize=$SAN_NULLABILITY_GROUP"
        if [ "$COLLECT" = YES ]; then
            export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=0:log_path=$REPORTS/ubsan"
        else
            # log_path: the report goes to a file, written before the abort,
            # and not to stderr. stderr would reach test.log only in a
            # serial run: xcodebuild does not pass on the stderr of
            # parallel workers.
            export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=1:log_path=$REPORTS/ubsan:suppressions=$SAN_NULLABILITY_SUPPRESSIONS"
        fi
        ;;
    integer|integer-sign)
        CFLAGS+=" -fsanitize=$SAN_INTEGER_GROUP -fsanitize-recover=$SAN_INTEGER_GROUP"
        LDFLAGS+=" -fsanitize=$SAN_INTEGER_GROUP"
        if [ "$MODE" = integer-sign ]; then
            CFLAGS+=" $SAN_SIGN_CHANGE_CFLAGS"
            IN_FORCE+=$'\n'"Sign-change check: -fsanitize=implicit-integer-sign-change (through -Xclang), in recover mode."
        fi
        export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=0:log_path=$REPORTS/ubsan"
        ;;
    thread)
        EXTRA_ARGS=(-enableThreadSanitizer YES ENABLE_THREAD_SANITIZER=YES)
        RUNTIME=tsan
        # exitcode=0: a report must not turn the test host's exit into a
        # failure of its own; the reports are in files and summarized below.
        export TEST_RUNNER_TSAN_OPTIONS="halt_on_error=0:exitcode=0:second_deadlock_stack=1:log_path=$REPORTS/tsan"
        ;;
    plain)
        RUNTIME=none
        ;;
esac
if [ "$PROBE" = YES ]; then
    export TEST_RUNNER_ITERM2_SANITIZER_PROBE="$MODE"
fi

san_common_xcodebuild_args "$BUILD_DIR"
ARGS=(
    "${SAN_XCODEBUILD_ARGS[@]}"
    -scheme ModernTests
    -enableCodeCoverage NO
    "${EXTRA_ARGS[@]}"
    "OTHER_CFLAGS=$CFLAGS"
    "OTHER_LDFLAGS=$LDFLAGS"
)

cd "$SAN_ROOT"
echo "Mode: $MODE. Build directory: $BUILD_DIR. Run directory: $RUN_DIR"
echo "$IN_FORCE"

# xcodebuild runs as a background job in its own process group (set -m),
# waited for, so that a signal stops it at once and kills the whole group.
# Test hosts are not in that group, so every process whose command is this
# mode's test host executable is killed as well (nothing broader: not
# Build/, not another mode, not another checkout), after an interruption and
# after a normal end.
TEST_HOST_EXECUTABLE="$BUILD_DIR/Build/Development/iTerm2.app/Contents/MacOS/iTerm2"
kill_test_hosts() {
    local pattern
    pattern="^$(printf '%s' "$TEST_HOST_EXECUTABLE" | sed 's/[]\\$*.^+?(){}|[]/\\&/g')( |$)"
    pkill -9 -f "$pattern" 2>/dev/null || true
}
GROUP_PID=""
on_signal() {
    trap '' INT TERM HUP
    echo "sanitizer_tests.sh: interrupted; stopping xcodebuild and the test hosts" >&2
    [ -n "$GROUP_PID" ] && kill -KILL -- "-$GROUP_PID" 2>/dev/null
    kill_test_hosts
    exit 130
}
trap on_signal INT TERM HUP
# Runs the function named $1 as a background job in its own process group
# and returns its status.
run_in_group() {
    set -m
    "$1" &
    GROUP_PID=$!
    set +m
    wait "$GROUP_PID"
    local status=$?
    GROUP_PID=""
    return $status
}
build_step() {
    xcodebuild build-for-testing "${ARGS[@]}" > "$RUN_DIR/build.log" 2>&1
}
test_step() {
    xcodebuild test "${ARGS[@]}" ${ONLY[@]+"${ONLY[@]}"} -parallel-testing-enabled "$PARALLEL" 2>&1 | tee "$RUN_DIR/test.log"
    return "${PIPESTATUS[0]}"
}

if [ "$DO_BUILD" = YES ]; then
    san_prepare_catalog
    echo "Building for testing (log: $RUN_DIR/build.log)..."
    START=$(date +%s)
    run_in_group build_step
    STATUS=$?
    echo "Build finished with status $STATUS in $(( $(date +%s) - START )) seconds."
    if [ $STATUS -ne 0 ]; then
        grep -E "error: " "$RUN_DIR/build.log" | head -20 >&2
        exit $STATUS
    fi
fi

HOST="$BUILD_DIR/Build/Development/iTerm2.app"
if [ ! -d "$HOST" ]; then
    echo "error: no test host under $BUILD_DIR/Build; build first" >&2
    exit 1
fi
if [ "$RUNTIME" = none ]; then
    san_check_no_runtime "$HOST" || exit 1
else
    san_check_runtime "$HOST" "$RUNTIME" || exit 1
fi

if [ "$DO_TEST" = NO ]; then
    exit 0
fi

ONLY=()
for t in ${TESTS[@]+"${TESTS[@]}"}; do
    ONLY+=("-only-testing:$t")
done
echo "Testing (log: $RUN_DIR/test.log)..."
START=$(date +%s)
run_in_group test_step
STATUS=$?
kill_test_hosts
echo "Tests finished with status $STATUS in $(( $(date +%s) - START )) seconds."

# Reports are in reports/ in every mode; test.log is read as well, for any
# report a runtime wrote to stderr because it could not write its file. The
# summarizer counts a report found in both once, and exits 3 if test.log
# shows no executed test.
echo "$IN_FORCE" > "$RUN_DIR/summary.txt"
SUMMARY_ARGS=()
if [ "$MODE" = thread ]; then
    # --symbolize: the build directory of this run holds exactly the
    # binaries that wrote the reports, so atos on them is safe; the summary
    # still checks them against the names the reports have.
    SUMMARY_ARGS=(--baseline "$THREAD_BASELINE" --symbolize "$BUILD_DIR/Build/Development")
    if [ "$COLLECT" = YES ]; then
        SUMMARY_ARGS+=(--collect)
    fi
fi
python3 -B "$SAN_HERE/sanitizer_summary.py" "$REPORTS" --console "$RUN_DIR/test.log" \
    --test-log "$RUN_DIR/test.log" ${SUMMARY_ARGS[@]+"${SUMMARY_ARGS[@]}"} | tee -a "$RUN_DIR/summary.txt"
SUMMARY_STATUS=${PIPESTATUS[0]}
if [ "$SUMMARY_STATUS" -eq 3 ]; then
    echo "error: the run executed no tests; check the TEST names. Its report count proves nothing." >&2
elif [ "$SUMMARY_STATUS" -eq 1 ] && [ "$MODE" = thread ]; then
    echo "error: the thread sanitizer reported races outside the baseline, or reports that cannot be compared with it (see the verdict above and docs/swift-migration/thread-baseline.md)" >&2
elif [ "$SUMMARY_STATUS" -ne 0 ]; then
    echo "error: sanitizer_summary.py failed with status $SUMMARY_STATUS" >&2
fi
if [ "$STATUS" -eq 0 ] && [ "$SUMMARY_STATUS" -ne 0 ]; then
    STATUS=1
fi
exit $STATUS
