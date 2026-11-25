#!/bin/bash
# Build and run the ModernTests tests with source-based code coverage, for the
# Objective-C to Swift migration (docs/swift-migration/large-code.md section
# 2.1: coverage decides when a golden-master net is good enough;
# test-speed.md section 2 item 7: a map from source file to the test classes
# that execute it). Read the results with
# tools/swift_migration/coverage_report.py.
#
# Usage:
#   tools/swift_migration/coverage_tests.sh [options] [TEST ...]
#
#   TEST is an -only-testing name such as ModernTests/VT100TerminalTests or
#   ModernTests/FooTests/testBar. With no TEST the whole suite runs.
#
#   Options:
#     --parallel    Run test classes in parallel worker processes, like
#                   tools/run_tests.expect -parallel, and with the same cap:
#                   two workers (-parallel-testing-worker-count 2
#                   -maximum-parallel-testing-workers 2) unless --workers.
#                   Every process writes its own profile files, so nothing
#                   collides.
#     --workers N   With --parallel: N workers instead of two. Refused
#                   without --parallel and with --build-only.
#     --jobs N      At most N concurrent build tasks (xcodebuild -jobs N), on
#                   the build step and the test step. Without it xcodebuild
#                   chooses (about one per core).
#     --per-class   Run each TEST, which must name a class
#                   (ModernTests/Class), in its own xcodebuild invocation with
#                   its own profile, merged to classes/<Class>.profdata, for
#                   coverage_report.py tests-for. Costs one test-host launch
#                   per class. Not with --parallel or --observer. The
#                   per-class statements of coverage_report.py tests-for are
#                   exact for such a run.
#     --observer    One run in which the test bundle's
#                   iTermCoveragePerClassObserver (ModernTests) zeroes every
#                   image's counters when a test class starts and copies the
#                   process's live profile files when it finishes, so each
#                   class gets classes/<Class>.profdata from a single run. Works
#                   with --parallel. Per-class attribution from an observer
#                   run is approximate: work a class leaves running (an
#                   asyncAfter block, a timer, another thread) is counted
#                   for the class that follows in the same process, and
#                   work the app's launch leaves running is counted for
#                   whichever class is running when it happens. So
#                   coverage_report.py tests-for on such a run says "may
#                   execute", never "executes", and exits 3; use
#                   --per-class for a per-class verdict.
#     --build-only  Build for testing and stop. The latest link is not
#                   moved, since the run has no profile.
#     --no-build    Skip the separate build-for-testing step. The test step
#                   is `xcodebuild test`, which still brings the build up to
#                   date (a no-op when nothing changed).
#     --test-allowance-seconds N
#                   XCTest's per-test time limit (-test-timeouts-enabled YES
#                   -default-test-execution-time-allowance N): a test that
#                   runs longer fails and its host is replaced. Default 120
#                   (no test that passed took over 13.1 s in the night's
#                   sanitized runs; orchestration.md section 3). 0 turns it
#                   off.
#     --max-test-allowance-seconds M
#                   The most a test may ask for with executionTimeAllowance.
#                   Default: N.
#     --stall-seconds N
#                   Stop a test step after N seconds with no test progress
#                   (default: the larger allowance plus 300, so 420; 600
#                   with the allowance off; 0 turns the watchdog off). See
#                   below.
#     --no-wait     A whole-suite run (no TEST, or only the target) whose
#                   lock another run holds fails at once with status 75,
#                   naming the holder, instead of waiting.
#     -h, --help    Print this text.
#
#   Environment:
#     SIGNED=1      Build signed, as for tools/run_tests.expect.
#     COVERAGE_IDLE_SECONDS
#                   How long to let xcodebuild sit after the end of testing
#                   is printed before stopping it (default 90). See below.
#
# Examples:
#   tools/swift_migration/coverage_tests.sh ModernTests/VT100TerminalTests
#   tools/swift_migration/coverage_tests.sh --parallel
#   tools/swift_migration/coverage_tests.sh --per-class ModernTests/VT100TerminalTests ModernTests/VT100ParserTests
#
# How the build is instrumented: the flags are added on the xcodebuild
# command line with $(inherited), so every target the scheme builds keeps its
# own flags:
#   OTHER_CFLAGS='$(inherited) -fprofile-instr-generate -fcoverage-mapping'
#       (C, Objective-C, C++ and Objective-C++: OTHER_CPLUSPLUSFLAGS inherits
#       OTHER_CFLAGS in this project)
#   OTHER_SWIFT_FLAGS='$(inherited) -profile-generate -profile-coverage-mapping'
#   OTHER_LDFLAGS='$(inherited) -fprofile-instr-generate'
#       (links the compiler's profile runtime into every image)
# Xcode's own coverage (-enableCodeCoverage YES with CLANG_ENABLE_CODE_COVERAGE)
# is not used and is turned off: with it xcodebuild chooses where profiles go
# and merges them into its result bundle, which these tools do not read. The
# address sanitizer, which the test plan turns on, is off. Products and
# intermediates go to tmp/coverage/Build/, never Build/.
#
# Where profiles go: the test host gets
# LLVM_PROFILE_FILE=<run>/profraw/%c%p-%m.profraw (through the TEST_RUNNER_
# prefix). %p is the process id and %m a signature of the image, so every
# image of every process (test hosts in parallel, restarted hosts, helper
# processes the host starts and that inherit its environment) has its own
# file. %c is continuous mode: the counters are mapped onto the file as the
# process runs, so a test host that crashes, or that this script kills, still
# leaves its counts. Only the test host and the processes it starts get the
# variable, so a profile file in the run's directory shows that it reached
# the host; the script fails if there is none.
#
# Where things go:
#   tmp/coverage/Build/                    The build (SYMROOT, OBJROOT).
#   tmp/coverage/runs/<time>/build.log     The xcodebuild build output.
#   tmp/coverage/runs/<time>/test.log      The xcodebuild test output (with
#                                          --per-class, test-<Class>.log).
#   tmp/coverage/runs/<time>/profraw/      Raw profiles.
#   tmp/coverage/runs/<time>/coverage.profdata
#                                          All raw profiles merged with
#                                          llvm-profdata merge -sparse.
#   tmp/coverage/runs/<time>/classes/      <Class>.profdata (--per-class,
#                                          --observer).
#   tmp/coverage/runs/<time>/per_class_route.txt
#                                          "per-class" or "observer": which
#                                          route made classes/, which the
#                                          report tool reads to know whether
#                                          per-class statements are exact.
#   tmp/coverage/runs/<time>/results/      The xcodebuild result bundles
#                                          (-resultBundlePath), kept here so
#                                          none is left in DerivedData; the
#                                          report tool does not read them.
#   tmp/coverage/runs/<time>/binaries.txt  The instrumented images: path,
#                                          size and modification time, one per
#                                          line, tab separated. The report
#                                          tool refuses an image that changed.
#   tmp/coverage/runs/<time>/sources.sha256
#                                          Digests of the tracked source files
#                                          when the build ended, for the
#                                          report tool's staleness check.
#   tmp/coverage/runs/<time>/toolchain.txt The llvm-profdata that merged.
#   tmp/coverage/runs/<time>/status.txt    "started" when the run begins,
#                                          then the script's exit status
#                                          after the merge; the report tool
#                                          calls a result from a run whose
#                                          status is anything but 0
#                                          incomplete.
#   tmp/coverage/runs/latest               Symbolic link to the newest run
#                                          with a merged profile whose tests
#                                          all passed.
# Run directories accumulate; remove them with rm -rf tmp/coverage/runs.
#
# Toolchain: the raw profile format is tied to the compiler that built the
# binaries. Merging and reporting use `xcrun llvm-profdata` and
# `xcrun llvm-cov` from the same Xcode. After an Xcode update, rebuild.
#
# The idle xcodebuild: xcodebuild sometimes sits idle after every test has
# finished. Once the end of testing is in the log (the top-level suite's
# result, "Test session results" or "** TEST ...**"), the script waits
# COVERAGE_IDLE_SECONDS and then stops xcodebuild's process group itself; the
# status is then taken from the log (1 if any test failed or crashed).
#
# Interrupting the script (INT, TERM, HUP) kills the process group it started
# xcodebuild in and any process whose command is this build's test host
# executable; nothing else. The same test hosts are killed after a normal end.
#
# Each test step runs under tools/swift_migration/suite_guard.py run (its
# header is the manual), which copies xcodebuild's output to the console
# and the log as tee did (on a pseudo-terminal, so that xcodebuild writes
# each line as it happens; through a pipe it was block-buffered), with
# XCTest's per-test allowance, and adds (2026-11-24, after five test hosts
# in three whole suites each waited hours in one test one night):
#   the stall watchdog, the backstop behind the allowance: a test step in
#   which a host stays inside one test, or no test progress shows, for
#   --stall-seconds (the signal is each host's output in the step's result
#   bundle; suite_guard.py's header has the rule) is diagnosed (in
#   <run>/stall/, or stall-<log name>/ for
#   --per-class: a sample of each of this run's test hosts, the executable
#   under tmp/coverage/Build/ with -suite iterm2-tests; the process list
#   with CPU, threads and memory footprint; the machine's memory state; the
#   log's tail and the tests in progress; every command bounded in time),
#   then xcodebuild's group and the test hosts are killed, status.txt gets
#   124 and the script exits 124 without merging. The idle watch above
#   (after the end of testing) is unchanged;
#   the whole-suite lock, for a whole-suite run (no TEST, or only the
#   target), and across the whole of a --per-class run (one test host per
#   class, one after another), not class by class: one whole suite, plain,
#   sanitized or instrumented, at a time on the machine
#   (docs/swift-migration/orchestration.md section 3), waited for unless
#   --no-wait.
# The script prints its pid first, so that a caller that runs it in the
# background can wait for it with a bound (suite_guard.py wait --pid PID
# --seconds N).
#
# Exit status: 124 when the stall watchdog stopped a test step; 75 when
# --no-wait found the whole-suite lock held; otherwise
# xcodebuild's, except 1 when the run executed no tests (a
# misspelled TEST runs nothing), produced no profile data, or the merge
# failed, and 2 for a usage error.

set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/sanitizer_common.sh"

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
}

PARALLEL=NO
PER_CLASS=NO
OBSERVER=NO
DO_BUILD=YES
DO_TEST=YES
TESTS=()
WORKERS=""
JOBS=""
STALL_SECONDS=""
ALLOWANCE=120
MAX_ALLOWANCE=""
NO_WAIT=NO
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --parallel|-parallel) PARALLEL=YES ;;
        --no-wait) NO_WAIT=YES ;;
        --stall-seconds|--test-allowance-seconds|--max-test-allowance-seconds)
            san_check_seconds "$1" "${2-}" || exit 2
            case "$1" in
                --stall-seconds) STALL_SECONDS="$2" ;;
                --test-allowance-seconds) ALLOWANCE="$2" ;;
                *) MAX_ALLOWANCE="$2" ;;
            esac
            shift ;;
        --workers)
            san_check_count "$1" "${2-}" || exit 2
            WORKERS="$2"
            shift ;;
        --jobs)
            san_check_count "$1" "${2-}" || exit 2
            JOBS="$2"
            shift ;;
        --per-class) PER_CLASS=YES ;;
        --observer) OBSERVER=YES ;;
        --build-only) DO_TEST=NO ;;
        --no-build) DO_BUILD=NO ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) TESTS+=("$1") ;;
    esac
    shift
done
if [ -n "$WORKERS" ] && { [ "$PARALLEL" = NO ] || [ "$DO_TEST" = NO ]; }; then
    echo "error: --workers needs --parallel and a test step" >&2
    exit 2
fi
if [ "$PER_CLASS" = YES ]; then
    if [ "$PARALLEL" = YES ] || [ "$OBSERVER" = YES ]; then
        echo "error: --per-class cannot be combined with --parallel or --observer" >&2
        exit 2
    fi
    if [ ${#TESTS[@]} -eq 0 ]; then
        echo "error: --per-class needs the test classes to run; it never runs the whole suite class by class" >&2
        exit 2
    fi
    for t in "${TESTS[@]}"; do
        case "$t" in
            */*/*|"") echo "error: --per-class takes classes (ModernTests/Class), not $t" >&2; exit 2 ;;
            */*) ;;
            *) echo "error: --per-class takes classes (ModernTests/Class), not $t" >&2; exit 2 ;;
        esac
    done
fi
[ -n "$MAX_ALLOWANCE" ] || MAX_ALLOWANCE="$ALLOWANCE"
if [ "$ALLOWANCE" -gt 0 ] && [ "$MAX_ALLOWANCE" -lt "$ALLOWANCE" ]; then
    echo "error: --max-test-allowance-seconds ($MAX_ALLOWANCE) is below --test-allowance-seconds ($ALLOWANCE)" >&2
    exit 2
fi
if [ -z "$STALL_SECONDS" ]; then
    if [ "$ALLOWANCE" -gt 0 ]; then STALL_SECONDS=$(( MAX_ALLOWANCE + 300 )); else STALL_SECONDS=600; fi
fi
san_allowance_args "$ALLOWANCE" "$MAX_ALLOWANCE"
# A run with no TEST, or with a TEST naming only the target, is the whole
# suite, and its test step takes the whole-suite lock.
WHOLE_SUITE=YES
for t in ${TESTS[@]+"${TESTS[@]}"}; do
    case "$t" in
        */*) WHOLE_SUITE=NO ;;
        *) WHOLE_SUITE=YES; break ;;
    esac
done
IDLE_SECONDS="${COVERAGE_IDLE_SECONDS:-90}"
case "$IDLE_SECONDS" in
    ''|*[!0-9]*) echo "error: COVERAGE_IDLE_SECONDS must be a whole number of seconds" >&2; exit 2 ;;
esac

PROFDATA_TOOL="$(xcrun --find llvm-profdata 2>/dev/null)" || PROFDATA_TOOL=""
if [ -z "$PROFDATA_TOOL" ]; then
    echo "error: xcrun cannot find llvm-profdata in the selected Xcode" >&2
    exit 2
fi

BUILD_DIR="$SAN_ROOT/tmp/coverage"
RUN_DIR="$BUILD_DIR/runs/$(date +%Y%m%d-%H%M%S)"
PROFRAW="$RUN_DIR/profraw"
mkdir -p "$PROFRAW" "$RUN_DIR/results"
# Not 0 until the end overwrites it with the real status, so a run that is
# interrupted or fails early never reads as passed.
echo started > "$RUN_DIR/status.txt"

CFLAGS="\$(inherited) -fprofile-instr-generate -fcoverage-mapping"
SWIFTFLAGS="\$(inherited) -profile-generate -profile-coverage-mapping"
LDFLAGS="\$(inherited) -fprofile-instr-generate"

san_common_xcodebuild_args "$BUILD_DIR"
ARGS=(
    "${SAN_XCODEBUILD_ARGS[@]}"
    -scheme ModernTests
    -enableCodeCoverage NO
    -enableThreadSanitizer NO
    ENABLE_THREAD_SANITIZER=NO
    CLANG_ENABLE_CODE_COVERAGE=NO
    "OTHER_CFLAGS=$CFLAGS"
    "OTHER_SWIFT_FLAGS=$SWIFTFLAGS"
    "OTHER_LDFLAGS=$LDFLAGS"
)
# -jobs on both steps: `xcodebuild test` brings the build up to date too.
if [ -n "$JOBS" ]; then
    ARGS+=(-jobs "$JOBS")
fi
san_parallel_args "$PARALLEL" "$WORKERS"

cd "$SAN_ROOT"
echo "coverage_tests.sh: pid $$"
echo "Build directory: $BUILD_DIR/Build. Run directory: $RUN_DIR"

# Process groups and cleanup, as in sanitizer_tests.sh.
TEST_HOST_EXECUTABLE="$BUILD_DIR/Build/Development/iTerm2.app/Contents/MacOS/iTerm2"
kill_test_hosts() {
    local pattern
    pattern="^$(printf '%s' "$TEST_HOST_EXECUTABLE" | sed 's/[]\\$*.^+?(){}|[]/\\&/g')( |$)"
    pkill -9 -f "$pattern" 2>/dev/null || true
}
GROUP_PID=""
WATCHER_PID=""
# suite_guard.py starts each test step's xcodebuild in a process group of
# its own and writes its id here, so that an interruption reaches it too.
PGID_FILE="$RUN_DIR/.test-pgid"
on_signal() {
    trap '' INT TERM HUP
    echo "coverage_tests.sh: interrupted; stopping xcodebuild and the test hosts" >&2
    [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null
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

# Stops the process group $1 when the log $2 has shown the end of testing
# for IDLE_SECONDS while the group is still running. Writes $3 when it did.
END_OF_TESTING="^(Test Suite '(All tests|Selected tests)' (passed|failed) at |Test session results|\*\* TEST [A-Z ]+ \*\*)"
idle_watch() {
    local group="$1" log="$2" marker="$3" seen=""
    while kill -0 "$group" 2>/dev/null; do
        if [ -z "$seen" ] && [ -f "$log" ] && grep -qE "$END_OF_TESTING" "$log"; then
            seen=$(date +%s)
        fi
        if [ -n "$seen" ] && [ $(( $(date +%s) - seen )) -ge "$IDLE_SECONDS" ]; then
            echo "coverage_tests.sh: xcodebuild still running ${IDLE_SECONDS}s after the end of testing; stopping it" >&2
            : > "$marker"
            kill -INT -- "-$group" 2>/dev/null
            sleep 5
            kill -KILL -- "-$group" 2>/dev/null
            return 0
        fi
        sleep 2
    done
}

build_step() {
    xcodebuild build-for-testing "${ARGS[@]}" -resultBundlePath "$RUN_DIR/results/build.xcresult" \
        > "$RUN_DIR/build.log" 2>&1
}
# $1: log file. The rest: extra xcodebuild arguments.
test_step() {
    local log="$1"
    shift
    local bundle
    bundle="$RUN_DIR/results/$(basename "$log" .log).xcresult"
    rm -rf "$bundle"
    local guard=(python3 -B "$SAN_HERE/suite_guard.py" run --log "$log"
                 --stall-seconds "$STALL_SECONDS" --stall-dir "$(stall_dir_for "$log")"
                 --pty --result-bundle "$bundle"
                 --host-prefix "$BUILD_DIR/Build" --pgid-file "$PGID_FILE"
                 --label "coverage_tests.sh (run $RUN_DIR)")
    if [ "$WHOLE_SUITE" = YES ]; then
        guard+=(--lock)
        [ "$NO_WAIT" = YES ] && guard+=(--no-wait)
    fi
    "${guard[@]}" -- xcodebuild test "${ARGS[@]}" "$@" "${SAN_PARALLEL_ARGS[@]}" \
        ${SAN_ALLOWANCE_ARGS[@]+"${SAN_ALLOWANCE_ARGS[@]}"} -resultBundlePath "$bundle"
}
# The stall watchdog's records for the log $1: stall/ for test.log,
# stall-<name>/ for test-<name>.log.
stall_dir_for() {
    local name
    name="$(basename "$1" .log)"
    if [ "$name" = test ]; then
        echo "$RUN_DIR/stall"
    else
        echo "$RUN_DIR/stall-${name#test-}"
    fi
}
# Runs test_step in its own group with the idle watcher. $1: log file. The
# rest: extra xcodebuild arguments. Returns the run's status.
run_tests() {
    local log="$1" marker="$RUN_DIR/.idle-stopped" status
    rm -f "$marker"
    set -m
    test_step "$@" &
    GROUP_PID=$!
    set +m
    idle_watch "$GROUP_PID" "$log" "$marker" &
    WATCHER_PID=$!
    wait "$GROUP_PID"
    status=$?
    GROUP_PID=""
    kill "$WATCHER_PID" 2>/dev/null
    wait "$WATCHER_PID" 2>/dev/null
    WATCHER_PID=""
    kill_test_hosts
    if [ "$status" -eq 75 ] && [ ! -e "$log" ]; then
        echo "error: --no-wait: another whole-suite run holds the whole-suite lock (named above); nothing was tested" >&2
        echo 75 > "$RUN_DIR/status.txt"
        exit 75
    fi
    if [ "$status" -eq 124 ] && [ -f "$(stall_dir_for "$log")/stall.txt" ]; then
        echo "error: the test step stalled and was stopped by the watchdog (status 124); see $(stall_dir_for "$log")/stall.txt" >&2
        echo 124 > "$RUN_DIR/status.txt"
        exit 124
    fi
    if [ -f "$marker" ]; then
        rm -f "$marker"
        status=$(python3 -B "$SAN_HERE/coverage_report.py" log-status "$log")
        echo "Status taken from the log after stopping the idle xcodebuild: $status"
    fi
    return "$status"
}

if [ "$DO_BUILD" = YES ]; then
    san_prepare_catalog
    echo "Building for testing with coverage (log: $RUN_DIR/build.log)..."
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
san_check_no_runtime "$HOST" || exit 1

# Records what the run's profile must be read with: the instrumented images
# (every Mach-O file in the products with a coverage mapping section), the
# toolchain, and digests of the tracked sources. Called after the build and
# again after the tests, since `xcodebuild test` brings the build up to date
# first and may relink.
record_build_info() {
    local list="$RUN_DIR/binaries.txt" f n
    : > "$list"
    while IFS= read -r -d '' f; do
        # Counted, not grep -q: with pipefail, grep -q exiting early would
        # fail otool with SIGPIPE.
        n=$(otool -l "$f" 2>/dev/null | grep -c "sectname __llvm_covmap")
        if [ "${n:-0}" -gt 0 ]; then
            printf '%s\t%s\t%s\n' "$f" "$(stat -f %z "$f")" "$(stat -f %m "$f")" >> "$list"
        fi
    done < <(find "$BUILD_DIR/Build/Development" -type f \( -perm -u+x -o -name '*.dylib' \) -not -path '*.dSYM/*' -print0)
    if ! grep -q "iTerm2.debug.dylib" "$list"; then
        echo "error: the app's iTerm2.debug.dylib has no coverage mapping; the build is not instrumented" >&2
        return 1
    fi
    echo "Instrumented images: $(wc -l < "$list" | tr -d ' ') (list: $list)"
    echo "$PROFDATA_TOOL" > "$RUN_DIR/toolchain.txt"
    xcrun llvm-profdata --version 2>&1 | head -2 >> "$RUN_DIR/toolchain.txt"
    git ls-files -z -- '*.m' '*.mm' '*.c' '*.cc' '*.cpp' '*.h' '*.swift' \
        | xargs -0 shasum -a 256 > "$RUN_DIR/sources.sha256" 2>/dev/null
}

record_build_info || exit 1
if [ "$DO_TEST" = NO ]; then
    exit 0
fi

# Merges the raw profiles in directory $1 into $2. Fails when there are none.
merge_profiles() {
    local dir="$1" out="$2" list
    list="$(mktemp "${TMPDIR:-/tmp}/coverage-inputs.XXXXXX")"
    find "$dir" -name '*.profraw' -size +0 > "$list"
    if [ ! -s "$list" ]; then
        rm -f "$list"
        echo "error: no profile data in $dir" >&2
        return 1
    fi
    if ! xcrun llvm-profdata merge -sparse -f "$list" -o "$out"; then
        rm -f "$list"
        echo "error: llvm-profdata merge failed. The raw profiles must be merged by the llvm-profdata of the toolchain that built the binaries ($PROFDATA_TOOL); rebuild after an Xcode update." >&2
        return 1
    fi
    rm -f "$list"
}

# Fails when the run wrote no profile file.
check_host_profiles() {
    local n
    n=$(find "$PROFRAW" -name '*.profraw' | wc -l | tr -d ' ')
    if [ "$n" -eq 0 ]; then
        echo "error: the run wrote no profile files to $PROFRAW; LLVM_PROFILE_FILE did not reach the test host" >&2
        return 1
    fi
    echo "Profile files: $n, $(du -sh "$PROFRAW" | cut -f1) ($PROFRAW)"
}

export TEST_RUNNER_LLVM_PROFILE_FILE="$PROFRAW/%c%p-%m.profraw"
if [ "$OBSERVER" = YES ]; then
    mkdir -p "$RUN_DIR/classes-raw"
    export TEST_RUNNER_ITERM2_COVERAGE_PER_CLASS_DIR="$RUN_DIR/classes-raw"
fi

START=$(date +%s)
STATUS=0
HOLD_PID=""
if [ "$PER_CLASS" = YES ]; then
    # One test host per class, one class after another: the whole-suite
    # lock is held across all of them (suite_guard.py hold, which lets go
    # when this script ends however it ends), not taken class by class.
    HOLD_FIFO="$RUN_DIR/.hold"
    mkfifo "$HOLD_FIFO" || exit 1
    HOLD_ARGS=(hold --pid $$ --label "coverage_tests.sh --per-class (run $RUN_DIR)")
    [ "$NO_WAIT" = YES ] && HOLD_ARGS+=(--no-wait)
    python3 -B "$SAN_HERE/suite_guard.py" "${HOLD_ARGS[@]}" > "$HOLD_FIFO" &
    HOLD_PID=$!
    HOLD_LINE=""
    read -r HOLD_LINE < "$HOLD_FIFO"
    rm -f "$HOLD_FIFO"
    case "$HOLD_LINE" in
        SWIFT_MIGRATION_SUITE_LOCK_HELD=*) export "$HOLD_LINE" ;;
        *) wait "$HOLD_PID"
           HOLD_STATUS=$?
           if [ "$HOLD_STATUS" -eq 75 ]; then
               echo "error: --no-wait: another whole-suite run holds the whole-suite lock (named above); nothing was tested" >&2
           else
               echo "error: could not take the whole-suite lock: suite_guard.py hold failed with status $HOLD_STATUS (see above); nothing was tested" >&2
               [ "$HOLD_STATUS" -eq 0 ] && HOLD_STATUS=1
           fi
           echo "$HOLD_STATUS" > "$RUN_DIR/status.txt"
           exit "$HOLD_STATUS" ;;
    esac
    mkdir -p "$RUN_DIR/classes"
    echo per-class > "$RUN_DIR/per_class_route.txt"
    for t in "${TESTS[@]}"; do
        cls="${t#*/}"
        export TEST_RUNNER_LLVM_PROFILE_FILE="$PROFRAW/$cls/%c%p-%m.profraw"
        mkdir -p "$PROFRAW/$cls"
        echo "Testing $t (log: $RUN_DIR/test-$cls.log)..."
        run_tests "$RUN_DIR/test-$cls.log" "-only-testing:$t"
        s=$?
        [ $s -ne 0 ] && STATUS=$s
        if ! python3 -B "$SAN_HERE/coverage_report.py" log-executed "$RUN_DIR/test-$cls.log" > /dev/null; then
            echo "error: $t executed no tests" >&2
            STATUS=1
            continue
        fi
        merge_profiles "$PROFRAW/$cls" "$RUN_DIR/classes/$cls.profdata" || STATUS=1
    done
    cat "$RUN_DIR"/test-*.log > "$RUN_DIR/test.log"
    kill "$HOLD_PID" 2>/dev/null
    wait "$HOLD_PID" 2>/dev/null
    HOLD_PID=""
else
    ONLY=()
    for t in ${TESTS[@]+"${TESTS[@]}"}; do
        ONLY+=("-only-testing:$t")
    done
    echo "Testing (log: $RUN_DIR/test.log)..."
    run_tests "$RUN_DIR/test.log" ${ONLY[@]+"${ONLY[@]}"}
    STATUS=$?
fi
echo "Tests finished with status $STATUS in $(( $(date +%s) - START )) seconds."
san_allowance_report "$RUN_DIR/test.log" "$ALLOWANCE"

EXECUTED=$(python3 -B "$SAN_HERE/coverage_report.py" log-executed "$RUN_DIR/test.log")
if [ $? -ne 0 ]; then
    echo "error: the run executed no tests; check the TEST names" >&2
    exit 1
fi
echo "Tests executed: $EXECUTED"
check_host_profiles || exit 1
record_build_info || exit 1

if [ "$OBSERVER" = YES ]; then
    mkdir -p "$RUN_DIR/classes"
    echo observer > "$RUN_DIR/per_class_route.txt"
    n=0
    for d in "$RUN_DIR/classes-raw"/*/; do
        [ -d "$d" ] || continue
        cls="$(basename "$d")"
        merge_profiles "$d" "$RUN_DIR/classes/$cls.profdata" > /dev/null && n=$((n + 1))
    done
    echo "Per-class profiles from the observer: $n in $RUN_DIR/classes"
    if [ "$n" -eq 0 ]; then
        echo "error: the observer wrote no per-class profiles" >&2
        [ "$STATUS" -eq 0 ] && STATUS=1
    fi
fi

MSTART=$(date +%s)
# With --observer the live profiles were zeroed after the last class, so the
# run's profile is the merge of the per-class copies (and _launch).
MERGE_FROM="$PROFRAW"
[ "$OBSERVER" = YES ] && MERGE_FROM="$RUN_DIR/classes-raw"
if ! merge_profiles "$MERGE_FROM" "$RUN_DIR/coverage.profdata"; then
    exit 1
fi
echo "Merged in $(( $(date +%s) - MSTART )) seconds: $RUN_DIR/coverage.profdata ($(du -h "$RUN_DIR/coverage.profdata" | cut -f1))"
# The run's exit status, which the report tool reads: it calls the result
# of a run whose tests did not all pass incomplete.
echo "$STATUS" > "$RUN_DIR/status.txt"
# Only a run with a merged profile whose tests all passed becomes latest, so
# that the report tool's default never names a run it cannot read or a
# failing net.
if [ "$STATUS" -eq 0 ]; then
    ln -sfn "$RUN_DIR" "$BUILD_DIR/runs/latest"
else
    echo "The latest link is not moved: the tests did not all pass (status $STATUS)."
fi
exit $STATUS
