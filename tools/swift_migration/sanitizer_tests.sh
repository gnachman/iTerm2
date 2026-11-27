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
#     nullability  -fsanitize=nullability on the Objective-C, C and C++.
#                  Reports matching
#                  tools/swift_migration/sanitizer_nullability_suppressions.txt
#                  are hidden by the runtime: not written anywhere and no
#                  abort. The file stays empty (the owner chose guards over
#                  suppressions as the fix for a violation). Every other
#                  report goes, with its stack, to a file in the run's
#                  reports/ directory. After the run the summary
#                  (sanitizer_summary.py --fail-on-reports
#                  --nullability-baseline) compares them with
#                  docs/swift-migration/nullability-baseline.tsv, the known,
#                  not yet triaged violations (proposed 2026-11-23, awaiting
#                  the owner's confirmation; owner-queue.md Q26), keyed by
#                  check kind, file, function, message and the declaring
#                  header's base name, not line (the file's header says
#                  what still shares an entry). A report outside it fails
#                  the run and is listed with the tests it came from,
#                  reports declared in a generated Swift header first; an
#                  incomplete report (cut off before its stack) or an
#                  unparsable report file fails it too; entries no report
#                  matched are listed as candidates for removal; the
#                  summary ends with "Verdict: PASS" or "Verdict: FAIL".
#                  Write or refresh the baseline from a
#                  whole-suite --collect run, with this checkout's script
#                  (or pass --root naming the checkout that ran):
#
#                    python3 -B tools/swift_migration/sanitizer_summary.py \
#                        --write-nullability-baseline \
#                        docs/swift-migration/nullability-baseline.tsv \
#                        tmp/sanitizers/runs/nullability-<time>/reports
#
#                  It prints every entry added (each needs a row in
#                  nullability-triage.md) and keeps entries not seen unless
#                  --drop-unseen. What a report does to the test host
#                  depends on the run:
#
#                  Whole suite (no TEST names, or a TEST naming only the
#                  target, ModernTests; with or without --skip), and
#                  any run with --recover: nothing aborts
#                  (halt_on_error=0). The test goes on and so does the host;
#                  the run fails afterwards on reports outside the
#                  baseline. This is the form
#                  for gate step 7. The aborting form is refused for the
#                  whole suite (there is no option for it): each abort
#                  relaunches the app under the sanitizer, and on 2026-11-23
#                  the orchestrator's nine-minute whole-suite run in this
#                  form that afternoon aborted 193 tests across 197 test
#                  hosts, and the load average reached about 150, with two
#                  other agents' test runs going at the same time. (The
#                  load of 467 earlier that day came from the night
#                  session's three concurrent heavy jobs.)
#
#                  Targeted (TEST names, without --recover): the first
#                  report ends the test host, so the test that violated the
#                  claim fails at once and test_timing.py reports the log as
#                  incomplete. The host ends with _exit(1)
#                  (halt_on_error=1:abort_on_error=0), not abort(), so macOS
#                  writes no crash report and runs no ReportCrash or spindump
#                  for it; xcodebuild still relaunches the host for the
#                  remaining tests. For targeted classes only.
#
#                  --collect: nothing aborts and nothing is suppressed, every
#                  report goes to a file for triage, and reports do not fail
#                  the run (the verdict is printed as information).
#
#                  Which test a report came from: a test method on the
#                  report's stack names it (a violation on the test's own
#                  thread has one; one from the host's launch, or from work a
#                  test left on another thread, has none). The UBSan runtime
#                  reports a source location once per process, so a later
#                  test in the same host that violates the same claim is not
#                  named. The reports are not in test.log (with --parallel
#                  xcodebuild would not pass a worker's stderr on anyway);
#                  the summary reads reports/ and test.log both.
#
#                  Not built, a test-target change: a test observer in
#                  ModernTests that, as each test starts, points the
#                  runtime's report path at the test with
#                  __sanitizer_set_report_path("<reports>/ubsan.<Class>.<method>")
#                  (the reports directory is the log_path in UBSAN_OPTIONS,
#                  which the host's environment carries) and restores it
#                  when the test ends, and adds a teardown block that records
#                  an issue on the test if its file exists. Then every report
#                  names its test and the test fails in place. The summary
#                  already reads a test from such a file name. A
#                  __ubsan_on_report defined in the test bundle cannot do
#                  this: the bundle is loaded after launch, and the
#                  runtime's weak default is replaced only by a definition
#                  in an image loaded at launch (an experiment, 2026-11-23).
#
#                  Every report needs a recoverable build, and the halt
#                  comes from halt_on_error=1, not from
#                  -fno-sanitize-recover: the runtime calls abort after an
#                  unrecoverable check even when the report is suppressed,
#                  and the app violates a claim while launching
#                  (iTermVariables.m), so with -fno-sanitize-recover no test
#                  could run at all. The same build serves every form.
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
#                  this mode (thread-baseline.md section 4), so the script
#                  refuses `thread --parallel` (status 2; since 2026-11-24,
#                  when a night session ran it anyway).
#     plain        No sanitizer at all: the address sanitizer off as in every
#                  mode, and nothing added. The fast test tier runs this way
#                  (docs/swift-migration/test-speed.md section 2). The script
#                  checks that the app links no sanitizer runtime. There are
#                  no reports; the summary only confirms that tests ran.
#     combined     One build and one run for three verdicts, the closing
#                  checks' first run (lifecycle.md section 5). The owner,
#                  2026-11-26: "Can the sanitizer runs be combined?
#                  nullability + integer + tsan in one go?", and to one run of
#                  the normal suite that also carries the nullability and
#                  integer checks plus one thread run: "Yes, please do". The
#                  build is the test plan's normal configuration, exactly as
#                  tools/run_tests.expect and whole_suite.sh build the plain
#                  whole suite: the plan's address sanitizer is on, given as
#                  -enableAddressSanitizer YES and ENABLE_ADDRESS_SANITIZER=YES
#                  on both steps (build-for-testing does not take it from
#                  the plan: a build on 2026-11-26 without them linked no
#                  ASan runtime), with the plan's ASAN_OPTIONS and its other
#                  settings. Added on top, as
#                  OTHER_CFLAGS and OTHER_LDFLAGS, both UBSan groups,
#                  -fsanitize=nullability,<the integer group>, with
#                  -fsanitize-recover for both: nothing aborts on a UBSan
#                  report, in a whole suite or a targeted run
#                  (halt_on_error=0, the nullability suppressions file, log
#                  path in reports/). The address sanitizer still ends its
#                  process at its first report, as in the plain suite, so
#                  the running test fails. Its runtime holds the UBSan
#                  handlers, so the app links libclang_rt.asan_osx_dynamic and
#                  no UBSan runtime; the script checks that the app links the
#                  ASan runtime and calls ___ubsan_handle_nullability_arg and
#                  ___ubsan_handle_implicit_conversion (nm -u), proving both
#                  groups are compiled in. The ignore list is applied to the
#                  two groups only (a generated copy under one [section],
#                  tmp/sanitizers/combined/sanitizer_ignorelist_ubsan_only.txt):
#                  the checked-in list, with no section, would take the
#                  address sanitizer away from every exempt file too. The
#                  address sanitizer's reports go to the same report files
#                  (its runtime reads UBSAN_OPTIONS after ASAN_OPTIONS and
#                  log_path is common to both), where the summary lists them
#                  apart; in the plain suite they go to stderr. The three
#                  verdicts:
#                    tests        xcodebuild's result, as for the plain suite
#                                 (with the per-test allowance, which
#                                 whole_suite.sh cannot pass).
#                    nullability  the nullability reports against
#                                 docs/swift-migration/nullability-baseline.tsv,
#                                 judged as in the nullability mode
#                                 (sanitizer_summary.py --fail-on-reports
#                                 --combined): any outside it fails, as does an
#                                 incomplete report or an unparsable report
#                                 file; a report of neither group fails too.
#                                 --collect makes it informational.
#                    integer      the integer group's reports, collected and
#                                 summarized, informational, as in the
#                                 integer mode, which fails only when the
#                                 tests fail, no test ran, or the summary
#                                 cannot be made.
#                  The summary ends with "Verdicts of the combined run:", a
#                  line for each, and "Combined verdict: PASS" or "Combined
#                  verdict: FAIL (tests)", "FAIL (nullability)" or "FAIL
#                  (tests and nullability)"; <run>/verdicts.txt has
#                  tests=, nullability=, integer=<reports> and combined=.
#                  Instrumentation changes code generation (on 2026-11-25
#                  six tests failed only under the nullability and thread
#                  builds), so a test that fails in a combined run is
#                  isolated by running that test class under the plain suite
#                  and then under each single sanitizer: rerun that test
#                  class under one sanitizer alone (the nullability and
#                  integer modes here) to tell which combination it is
#                  sensitive to. The thread sanitizer cannot share a build
#                  with the address sanitizer, so the thread mode stays a
#                  run of its own. --probe is refused (each probe test runs
#                  only when ITERM2_SANITIZER_PROBE names its one group), as
#                  is --recover (it always recovers).
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
#                   file, no suppressions, reports do not fail the run (for
#                   the triage of reports).
#                   combined: the nullability verdict is printed and fails
#                   nothing (the suppressions stay in force).
#                   thread: compare with the baseline but do not fail the run
#                   on reports (for building or re-judging the baseline).
#     --recover     nullability, targeted run: do not abort on a report; the
#                   run still fails on it. (A whole-suite run always works
#                   this way.) Refused in the other modes and with --collect.
#     --parallel    Run test classes in parallel worker processes, like
#                   tools/run_tests.expect -parallel, and with the same cap:
#                   two workers (-parallel-testing-worker-count 2
#                   -maximum-parallel-testing-workers 2) unless --workers.
#     --workers N   With --parallel: N workers instead of two (both options
#                   above, with N). Refused without --parallel.
#     --skip ModernTests/Class[/test]
#                   Leave that class or test out (-skip-testing:, once per
#                   --skip; repeatable). With TEST names, xcodebuild runs
#                   what the TEST names select minus what --skip names; with
#                   none, the whole suite minus what --skip names. A run
#                   whose --skip leaves nothing fails as one that executed no
#                   tests. It works with --collect and --no-build, and is
#                   refused with --build-only, as is --workers: both act on
#                   the test step only. What was skipped, the worker count
#                   and the job limit are stated with the rest of what is in
#                   force (console and summary.txt).
#     --jobs N      At most N concurrent build tasks (xcodebuild -jobs N), on
#                   the build step and on the test step (which brings the
#                   build up to date). Without it xcodebuild chooses (about
#                   one per core).
#     --build-only  Build for testing and stop.
#     --no-build    Skip the separate build-for-testing step. The test step
#                   is `xcodebuild test`, which still brings the build up to
#                   date (a no-op when nothing changed); it is used rather
#                   than test-without-building because only `test` ends its
#                   log with the "** TEST SUCCEEDED **" or "** TEST FAILED **"
#                   line that test_timing.py needs to call a log complete.
#     --test-allowance-seconds N
#                   XCTest's per-test time limit: every test case gets at
#                   most N seconds (-test-timeouts-enabled YES
#                   -default-test-execution-time-allowance N), so that a
#                   hung test fails and its test host is replaced instead
#                   of the run waiting for hours. Default 120, 300 in the
#                   thread mode; 0 turns it off. XCTest rounds it up to
#                   whole minutes. The evidence for the defaults is in
#                   docs/swift-migration/orchestration.md section 3.
#     --max-test-allowance-seconds M
#                   The most any test may ask for with executionTimeAllowance
#                   (-maximum-test-execution-time-allowance M). Default: N.
#                   No test sets executionTimeAllowance today.
#     --stall-seconds N
#                   The stall watchdog (below), the backstop behind the
#                   allowance: a test step with no test progress for N
#                   seconds is diagnosed and killed. Default: the larger
#                   allowance plus 300 (420; 600 in the thread mode), or
#                   600 with the allowance off. 0 turns it off.
#     --no-wait     A whole-suite run whose lock (below) another run holds
#                   fails at once with status 75, naming the holder, instead
#                   of waiting for it.
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
#   tools/swift_migration/sanitizer_tests.sh thread
#   tools/swift_migration/sanitizer_tests.sh plain --parallel
#   tools/swift_migration/sanitizer_tests.sh combined --parallel
#   nice -n 15 tools/swift_migration/sanitizer_tests.sh integer --parallel --jobs 4 \
#       --skip ModernTests/FramerFlowTwoHopSimulationTests
#
# Priority: started under nice, the script's xcodebuild, its build service
# (SWBBuildService, a child of xcodebuild) and the compilers run at that
# priority. The test hosts do not: xcodebuild has them launched outside its
# process tree, so they run at normal priority whatever the script's.
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
#   tmp/sanitizers/runs/combined-<time>/verdicts.txt
#                                               The combined mode's verdicts,
#                                               one key=value per line.
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
# every mode but combined (it cannot be combined with the thread sanitizer,
# and the single-sanitizer modes are cheaper and their reports clearer
# without it). For combined, the runtime is the ASan runtime the test plan
# links, with the UBSan handlers in it; -fsanitize=<groups> is still added
# to OTHER_LDFLAGS, for the targets the plan's setting may not reach.
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
# test hosts are killed after a normal end.
#
# The test step runs under tools/swift_migration/suite_guard.py run (its
# header is the manual), on a pseudo-terminal so that xcodebuild writes each
# line as it happens (through tee's pipe it was block-buffered: on
# 2026-11-24 each test.log stopped mid-line minutes before its tests hung),
# with output to the console and test.log, the result bundle in
# <run>/results/test.xcresult, XCTest's per-test time allowance
# (--test-allowance-seconds), and two more things. That night five test
# hosts in three whole suites each entered a test that waits with no
# deadline for a dispatch or XPC callback that never came; nothing had a
# per-test timeout or a stall watchdog, and the session waiting on the jobs
# had no bound either.
#
#   The stall watchdog, the backstop behind the allowance. Its progress
#   signal is each test host's output in the result bundle: when a host
#   has been inside one test (its last test event a start) for
#   --stall-seconds while alive, or neither xcodebuild nor any host has
#   shown test progress for that long, then before anything is killed the
#   run directory gets stall/: each host's test in progress (workers.txt),
#   a `sample` of every test host of this run (an executable under
#   tmp/sanitizers/<mode>/Build/ ending in iTerm2.app/Contents/MacOS/iTerm2,
#   run with -suite iterm2-tests, started after the test step: never the
#   owner's iTerm2) with its thread count, the process list with CPU,
#   thread counts and memory footprint, the machine's memory state
#   (memory_pressure -Q, vm_stat, vm.swapusage), the tail of test.log and
#   the tests in progress. Every command there has a time bound. Then
#   xcodebuild's process group and this run's test hosts are killed,
#   summary.txt says STALLED with the tests in progress (the sanitizer
#   summary is not made; the reports written so far stay in reports/), and
#   the script exits 124.
#
#   The whole-suite lock. A whole-suite run (no TEST names, or only the
#   target) holds the machine-wide whole-suite lock for its test step, so
#   that at most one whole suite, plain or sanitized, runs at a time on the
#   machine, across every checkout and lane (orchestration.md section 3).
#   It waits for the lock, saying who holds it; with --no-wait it fails at
#   once (status 75). The build step does not take it. A targeted run takes
#   no lock and still has the watchdog.
#
# The script prints its pid first, so that a caller that runs it in the
# background can wait for it with a bound: suite_guard.py wait --pid PID
# --seconds N.
#
# Exit status: 124 when the stall watchdog stopped the run; 75 when
# --no-wait found the whole-suite lock held; otherwise xcodebuild's, except 1 when xcodebuild succeeded but the run
# executed no tests (a misspelled TEST runs nothing and would look clean;
# skipped tests count as executed), the summary could not be made, (thread
# mode without --collect) a report is outside the baseline or cannot be
# compared with it, or (nullability mode without --collect) there is a report
# that neither the suppressions nor the nullability baseline accepts, or a
# report file that does not parse (a host killed while writing it), and 2 for a usage error or a refused checkout path. So a
# thread run exits 0 only if the tests passed and every report is in the
# baseline. The combined mode (after 124 and 75): 0 when the tests passed
# and the nullability verdict passed (with --collect, whatever it says);
# xcodebuild's status (65 for failed tests) when only the tests failed; 1
# when only the nullability verdict failed, or no test ran, or the summary
# could not be made; 4 when the tests and the nullability verdict both
# failed. The integer verdict never changes the status.

set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/sanitizer_common.sh"

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
}

MODE=""
PROBE=NO
COLLECT=NO
RECOVER=NO
PARALLEL=NO
WORKERS=""
JOBS=""
DO_BUILD=YES
DO_TEST=YES
STALL_SECONDS=""
ALLOWANCE=""
MAX_ALLOWANCE=""
NO_WAIT=NO
TESTS=()
SKIPS=()
# The value of option $1, which is $2; fails with status 2 if there is none.
option_value() {
    case "${2-}" in
        ''|-*) echo "error: $1 needs a value" >&2; return 2 ;;
    esac
}
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --probe) PROBE=YES ;;
        --collect) COLLECT=YES ;;
        --recover) RECOVER=YES ;;
        --parallel|-parallel) PARALLEL=YES ;;
        --build-only) DO_TEST=NO ;;
        --no-build) DO_BUILD=NO ;;
        --no-wait) NO_WAIT=YES ;;
        --stall-seconds|--test-allowance-seconds|--max-test-allowance-seconds)
            option_value "$1" "${2-}" || exit 2
            san_check_seconds "$1" "$2" || exit 2
            case "$1" in
                --stall-seconds) STALL_SECONDS="$2" ;;
                --test-allowance-seconds) ALLOWANCE="$2" ;;
                *) MAX_ALLOWANCE="$2" ;;
            esac
            shift ;;
        --skip)
            option_value "$1" "${2-}" || exit 2
            case "$2" in
                */*/*/*|/*|*/|*//*|*/*/) echo "error: --skip takes Target/Class or Target/Class/test, not $2" >&2; exit 2 ;;
                */*) ;;
                *) echo "error: --skip takes Target/Class or Target/Class/test, not $2" >&2; exit 2 ;;
            esac
            SKIPS+=("$2")
            shift ;;
        --workers)
            option_value "$1" "${2-}" || exit 2
            san_check_count "$1" "$2" || exit 2
            WORKERS="$2"
            shift ;;
        --jobs)
            option_value "$1" "${2-}" || exit 2
            san_check_count "$1" "$2" || exit 2
            JOBS="$2"
            shift ;;
        nullability|integer|integer-sign|thread|plain|combined)
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
if [ "$COLLECT" = YES ] && [ "$MODE" != nullability ] && [ "$MODE" != thread ] && [ "$MODE" != combined ]; then
    echo "error: --collect applies to the nullability and thread modes and to combined; the other modes always collect" >&2
    exit 2
fi
if [ "$MODE" = combined ] && [ "$PROBE" = YES ]; then
    echo "error: --probe applies to the single-sanitizer modes: each probe test runs only when ITERM2_SANITIZER_PROBE names its one group. Run the probes in the nullability and integer modes." >&2
    exit 2
fi
if [ "$RECOVER" = YES ] && { [ "$MODE" != nullability ] || [ "$COLLECT" = YES ]; }; then
    echo "error: --recover applies to the nullability mode without --collect (--collect never aborts)" >&2
    exit 2
fi
# The nullability mode aborts the test host on a report only in a targeted
# run (TEST names given) without --recover. A whole-suite run never does:
# each abort relaunches the app under the sanitizer, and on 2026-11-23 one
# such run had 197 test hosts in nine minutes.
# A TEST that names only the target (ModernTests, no class) selects the
# whole suite, as no TEST does.
WHOLE_SUITE=YES
for t in ${TESTS[@]+"${TESTS[@]}"}; do
    case "$t" in
        */*) WHOLE_SUITE=NO ;;
        *) WHOLE_SUITE=YES; break ;;
    esac
done
if [ "$MODE" = nullability ] && [ "$COLLECT" = NO ] && [ "$WHOLE_SUITE" = YES ]; then
    RECOVER=YES
fi
if [ "$DO_TEST" = NO ] && { [ ${#SKIPS[@]} -gt 0 ] || [ -n "$WORKERS" ]; }; then
    echo "error: --skip and --workers apply to the test step, which --build-only leaves out" >&2
    exit 2
fi
if [ "$MODE" = thread ] && [ "$PARALLEL" = YES ]; then
    echo "error: the thread mode runs serially: --parallel loses test hosts under the thread sanitizer (docs/swift-migration/thread-baseline.md section 4). Run it without --parallel." >&2
    exit 2
fi
# The per-test allowance (evidence: orchestration.md section 3) and the
# watchdog behind it, which must wait longer than XCTest would.
if [ -z "$ALLOWANCE" ]; then
    if [ "$MODE" = thread ]; then ALLOWANCE=300; else ALLOWANCE=120; fi
fi
[ -n "$MAX_ALLOWANCE" ] || MAX_ALLOWANCE="$ALLOWANCE"
if [ "$ALLOWANCE" -gt 0 ] && [ "$MAX_ALLOWANCE" -lt "$ALLOWANCE" ]; then
    echo "error: --max-test-allowance-seconds ($MAX_ALLOWANCE) is below --test-allowance-seconds ($ALLOWANCE)" >&2
    exit 2
fi
if [ -z "$STALL_SECONDS" ]; then
    if [ "$ALLOWANCE" -gt 0 ]; then
        STALL_SECONDS=$(( MAX_ALLOWANCE + 300 ))
    else
        STALL_SECONDS=600
    fi
fi
san_allowance_args "$ALLOWANCE" "$MAX_ALLOWANCE"
if [ -n "$WORKERS" ] && [ "$PARALLEL" = NO ]; then
    echo "error: --workers needs --parallel" >&2
    exit 2
fi

san_check_root_path || exit 2

BUILD_DIR="$SAN_ROOT/tmp/sanitizers/$MODE"
RUN_DIR="$SAN_ROOT/tmp/sanitizers/runs/$MODE-$(date +%Y%m%d-%H%M%S)"
REPORTS="$RUN_DIR/reports"
THREAD_BASELINE="$SAN_ROOT/docs/swift-migration/thread-baseline.tsv"
NULLABILITY_BASELINE="$SAN_ROOT/docs/swift-migration/nullability-baseline.tsv"
mkdir -p "$BUILD_DIR" "$REPORTS"

# The combined mode's ignore list exempts files from the two UBSan groups
# only, never from the address sanitizer (san_write_sectioned_ignorelist).
IGNORELIST="$SAN_IGNORELIST"
if [ "$MODE" = combined ]; then
    IGNORELIST="$BUILD_DIR/sanitizer_ignorelist_ubsan_only.txt"
    san_write_sectioned_ignorelist "$IGNORELIST" "$SAN_COMBINED_GROUPS" || exit 1
fi

# What is in force, stated on the console and at the top of summary.txt.
if [ "$MODE" = combined ]; then
    IN_FORCE="Address sanitizer: on, as the ModernTests test plan has it for tools/run_tests.expect and whole_suite.sh (-enableAddressSanitizer YES, the plan's ASAN_OPTIONS); a report ends its test host and fails its test, as in the plain suite. Its report goes to reports/ (the runtimes share log_path) and is listed apart."
    IN_FORCE+=$'\n'"Ignore list (C, Objective-C, C++ compiles; the nullability and integer groups only, the address sanitizer instruments every file): $IGNORELIST (the $(san_count_entries "$SAN_IGNORELIST") entries of $SAN_IGNORELIST under one section)."
    IN_FORCE+=$'\n'"UBSan groups: -fsanitize=$SAN_COMBINED_GROUPS, recovering: nothing aborts on a UBSan report, in a whole suite or a targeted run."
    IN_FORCE+=$'\n'"Suppressions: $SAN_NULLABILITY_SUPPRESSIONS ($(san_count_entries "$SAN_NULLABILITY_SUPPRESSIONS") entries)."
    IN_FORCE+=$'\n'"Nullability verdict: nullability reports against $NULLABILITY_BASELINE ($(( $(san_count_entries "$NULLABILITY_BASELINE") - 1 )) entries); a report outside it fails the run."
    if [ "$COLLECT" = YES ]; then
        IN_FORCE+=$'\n'"--collect: the nullability verdict is printed and fails nothing."
    fi
    IN_FORCE+=$'\n'"Integer verdict: the integer group's reports are collected and summarized; informational, they never fail the run."
else
    IN_FORCE="Ignore list (C, Objective-C, C++ compiles): $SAN_IGNORELIST ($(san_count_entries "$SAN_IGNORELIST") entries)."
fi
if [ "$MODE" = combined ]; then
    :
elif [ "$MODE" = nullability ] && [ "$COLLECT" = NO ]; then
    IN_FORCE+=$'\n'"Suppressions: $SAN_NULLABILITY_SUPPRESSIONS ($(san_count_entries "$SAN_NULLABILITY_SUPPRESSIONS") entries)."
    IN_FORCE+=$'\n'"Reports matching a suppression are hidden: not written anywhere, and they do not abort. Run with --collect to see them."
    IN_FORCE+=$'\n'"Baseline: $NULLABILITY_BASELINE ($(( $(san_count_entries "$NULLABILITY_BASELINE") - 1 )) entries), compared after the run; a report outside it fails the run."
    if [ "$RECOVER" = YES ]; then
        if [ "$WHOLE_SUITE" = YES ]; then
            IN_FORCE+=$'\n'"Whole suite: violations do not abort the test host (the aborting mode is for targeted classes)."
        fi
        IN_FORCE+=$'\n'"Recover: every report not suppressed goes to a file and the test goes on; a report outside the baseline fails the run, listed with the tests it came from."
    else
        IN_FORCE+=$'\n'"Aborting: the first report not suppressed ends the test host (with _exit, abort_on_error=0, so no crash report), which fails the test; a report outside the baseline fails the run."
    fi
elif [ "$MODE" = nullability ]; then
    IN_FORCE+=$'\n'"Suppressions: none."
    IN_FORCE+=$'\n'"--collect: nothing aborts and every report is listed; reports do not fail the run."
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

CFLAGS="\$(inherited) -fsanitize-ignorelist=$IGNORELIST"
LDFLAGS="\$(inherited)"
EXTRA_ARGS=(-enableThreadSanitizer NO ENABLE_THREAD_SANITIZER=NO)
RUNTIME=ubsan
case "$MODE" in
    nullability)
        CFLAGS+=" -fsanitize=$SAN_NULLABILITY_GROUP -fsanitize-recover=$SAN_NULLABILITY_GROUP"
        LDFLAGS+=" -fsanitize=$SAN_NULLABILITY_GROUP"
        if [ "$COLLECT" = YES ]; then
            export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=0:log_path=$REPORTS/ubsan"
        elif [ "$RECOVER" = YES ]; then
            export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=0:log_path=$REPORTS/ubsan:suppressions=$SAN_NULLABILITY_SUPPRESSIONS"
        else
            # log_path: the report goes to a file, written before the halt,
            # and not to stderr. stderr would reach test.log only in a
            # serial run: xcodebuild does not pass on the stderr of
            # parallel workers. abort_on_error=0: the runtime ends the
            # process with _exit(exitcode) (1) instead of abort(), so macOS
            # writes no crash report (.ips) and runs no ReportCrash for it.
            export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=1:abort_on_error=0:log_path=$REPORTS/ubsan:suppressions=$SAN_NULLABILITY_SUPPRESSIONS"
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
    combined)
        # The address sanitizer comes from the test plan (and links its
        # runtime, which holds the UBSan handlers too); the groups are added.
        CFLAGS+=" -fsanitize=$SAN_COMBINED_GROUPS -fsanitize-recover=$SAN_COMBINED_GROUPS"
        LDFLAGS+=" -fsanitize=$SAN_COMBINED_GROUPS"
        RUNTIME=asan
        export TEST_RUNNER_UBSAN_OPTIONS="$SAN_UBSAN_BASE_OPTIONS:halt_on_error=0:log_path=$REPORTS/ubsan:suppressions=$SAN_NULLABILITY_SUPPRESSIONS"
        ;;
esac
if [ "$PROBE" = YES ]; then
    export TEST_RUNNER_ITERM2_SANITIZER_PROBE="$MODE"
fi

if [ "$MODE" = combined ]; then
    san_common_xcodebuild_args "$BUILD_DIR" plan-asan
else
    san_common_xcodebuild_args "$BUILD_DIR"
fi
ARGS=(
    "${SAN_XCODEBUILD_ARGS[@]}"
    -scheme ModernTests
    -enableCodeCoverage NO
    "${EXTRA_ARGS[@]}"
    "OTHER_CFLAGS=$CFLAGS"
    "OTHER_LDFLAGS=$LDFLAGS"
)
# -jobs on both steps: `xcodebuild test` brings the build up to date too.
if [ -n "$JOBS" ]; then
    ARGS+=(-jobs "$JOBS")
fi
san_parallel_args "$PARALLEL" "$WORKERS"
# Stated with the rest of what is in force, so summary.txt says whether the
# run was the whole suite.
if [ -n "$JOBS" ]; then
    IN_FORCE+=$'\n'"Build jobs: at most $JOBS."
fi
if [ "$DO_TEST" = YES ] && [ "$PARALLEL" = YES ]; then
    IN_FORCE+=$'\n'"Parallel: ${WORKERS:-$SAN_DEFAULT_WORKERS} workers."
fi
if [ ${#SKIPS[@]} -gt 0 ]; then
    IN_FORCE+=$'\n'"Skipped: ${SKIPS[*]}"
fi

if [ "$DO_TEST" = YES ]; then
    if [ "$ALLOWANCE" -gt 0 ]; then
        IN_FORCE+=$'\n'"Test time allowance: $ALLOWANCE seconds per test (at most $MAX_ALLOWANCE); XCTest fails a test that runs longer and restarts its host."
    else
        IN_FORCE+=$'\n'"Test time allowance: off (--test-allowance-seconds 0)."
    fi
    if [ "$STALL_SECONDS" -gt 0 ]; then
        IN_FORCE+=$'\n'"Stall watchdog: the test step is stopped after $STALL_SECONDS seconds with no test progress."
    else
        IN_FORCE+=$'\n'"Stall watchdog: off (--stall-seconds 0)."
    fi
    if [ "$WHOLE_SUITE" = YES ]; then
        IN_FORCE+=$'\n'"Whole-suite lock: held for the test step (one whole suite at a time on this machine)."
    fi
fi

cd "$SAN_ROOT"
echo "sanitizer_tests.sh: pid $$"
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
# suite_guard.py starts the test step's xcodebuild in a process group of its
# own and writes its id here, so that an interruption reaches it too.
PGID_FILE="$RUN_DIR/.test-pgid"
on_signal() {
    trap '' INT TERM HUP
    echo "sanitizer_tests.sh: interrupted; stopping xcodebuild and the test hosts" >&2
    [ -n "$GROUP_PID" ] && kill -KILL -- "-$GROUP_PID" 2>/dev/null
    [ -s "$PGID_FILE" ] && kill -KILL -- "-$(cat "$PGID_FILE")" 2>/dev/null
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
# The test step under suite_guard.py: output to the console and test.log,
# the stall watchdog, and for a whole suite the whole-suite lock.
test_step() {
    local guard=(python3 -B "$SAN_HERE/suite_guard.py" run --log "$RUN_DIR/test.log"
                 --stall-seconds "$STALL_SECONDS" --stall-dir "$RUN_DIR/stall" --pty
                 --result-bundle "$RUN_DIR/results/test.xcresult"
                 --host-prefix "$BUILD_DIR/Build" --pgid-file "$PGID_FILE"
                 --label "sanitizer_tests.sh $MODE (run $RUN_DIR)")
    if [ "$WHOLE_SUITE" = YES ]; then
        guard+=(--lock)
        [ "$NO_WAIT" = YES ] && guard+=(--no-wait)
    fi
    "${guard[@]}" -- xcodebuild test "${ARGS[@]}" ${ONLY[@]+"${ONLY[@]}"} ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"} \
        "${SAN_PARALLEL_ARGS[@]}" ${SAN_ALLOWANCE_ARGS[@]+"${SAN_ALLOWANCE_ARGS[@]}"} \
        -resultBundlePath "$RUN_DIR/results/test.xcresult"
}

# The combined mode's three verdicts, on the console, in summary.txt and in
# verdicts.txt (tests=, nullability=, integer=<reports>, combined=), and its
# exit status: 0 both pass; xcodebuild's status when only the tests failed;
# 1 when only the nullability verdict failed (or the summary could not be
# made, or no test ran); 4 when the tests and the nullability verdict both
# failed. Reads STATUS and SUMMARY_STATUS; sets STATUS.
combined_verdicts() {
    local tests nullability integer_line integer_count combined tests_ok=YES nullability_ok=YES
    if [ "$SUMMARY_STATUS" -eq 3 ]; then
        tests="FAIL (no test executed)"
        tests_ok=NO
    elif [ "$STATUS" -eq 0 ]; then
        tests="PASS (xcodebuild status 0)"
    else
        tests="FAIL (xcodebuild status $STATUS)"
        tests_ok=NO
    fi
    case "$SUMMARY_STATUS" in
        0)
            nullability="PASS"
            if [ "$COLLECT" = YES ] && grep -q '^Verdict (--collect, does not fail the run): FAIL' "$RUN_DIR/summary.txt"; then
                nullability="FAIL (--collect: informational)"
            fi ;;
        1) nullability="FAIL"; nullability_ok=NO ;;
        3) nullability="not judged (no test executed)" ;;
        *) nullability="FAIL (sanitizer_summary.py failed with status $SUMMARY_STATUS)"; nullability_ok=NO ;;
    esac
    integer_line=$(grep -m1 '^Integer verdict (informational, never fails the run): ' "$RUN_DIR/summary.txt" \
                   | sed 's/^Integer verdict (informational, never fails the run): //; s/\.$//')
    integer_count=$(printf '%s\n' "$integer_line" | sed -n 's/^\([0-9][0-9]*\) report.*/\1/p')
    if [ "$tests_ok" = YES ] && [ "$nullability_ok" = YES ]; then
        combined="PASS"
        [ "$COLLECT" = YES ] && combined="PASS (--collect)"
    elif [ "$tests_ok" = YES ]; then
        combined="FAIL (nullability)"
        STATUS=1
    elif [ "$nullability_ok" = YES ]; then
        combined="FAIL (tests)"
        [ "$STATUS" -eq 0 ] && STATUS=1
    else
        combined="FAIL (tests and nullability)"
        STATUS=4
    fi
    {
        echo
        echo "Verdicts of the combined run:"
        echo "  tests:       $tests"
        echo "  nullability: $nullability"
        echo "  integer:     informational: ${integer_line:-not summarized}"
        echo "Combined verdict: $combined"
    } | tee -a "$RUN_DIR/summary.txt"
    printf 'tests=%s\nnullability=%s\ninteger=%s\ncombined=%s\n' "${tests%% *}" "${nullability%% *}" \
        "${integer_count:-?}" "${combined%% *}" > "$RUN_DIR/verdicts.txt"
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
if [ "$MODE" = combined ]; then
    san_check_ubsan_handlers "$HOST" ___ubsan_handle_nullability_arg ___ubsan_handle_implicit_conversion || exit 1
fi

if [ "$DO_TEST" = NO ]; then
    exit 0
fi

ONLY=()
for t in ${TESTS[@]+"${TESTS[@]}"}; do
    ONLY+=("-only-testing:$t")
done
SKIP_ARGS=()
for t in ${SKIPS[@]+"${SKIPS[@]}"}; do
    SKIP_ARGS+=("-skip-testing:$t")
done
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
    { echo "$IN_FORCE"; echo; cat "$RUN_DIR/stall/stall.txt"
      echo "The sanitizer summary was not made. The reports written before the stall are in $REPORTS:"
      echo "  python3 -B tools/swift_migration/sanitizer_summary.py $REPORTS"; } > "$RUN_DIR/summary.txt"
    echo "error: the test step stalled and was stopped by the watchdog (status 124); see $RUN_DIR/summary.txt and $RUN_DIR/stall/" >&2
    exit 124
fi

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
elif [ "$MODE" = combined ]; then
    # The nullability verdict, as in the nullability mode but over the
    # nullability reports only; the integer reports are summarized.
    SUMMARY_ARGS=(--fail-on-reports --combined --nullability-baseline "$NULLABILITY_BASELINE")
    if [ "$COLLECT" = YES ]; then
        SUMMARY_ARGS+=(--collect)
    fi
elif [ "$MODE" = nullability ]; then
    # A report outside the nullability baseline (after the empty runtime
    # suppressions), an incomplete report or an unparsable report file
    # fails the run (with --collect the verdict is printed and fails
    # nothing).
    SUMMARY_ARGS=(--fail-on-reports --nullability-baseline "$NULLABILITY_BASELINE")
    if [ "$COLLECT" = YES ]; then
        SUMMARY_ARGS+=(--collect)
    fi
fi
python3 -B "$SAN_HERE/sanitizer_summary.py" "$REPORTS" --console "$RUN_DIR/test.log" \
    --test-log "$RUN_DIR/test.log" ${SUMMARY_ARGS[@]+"${SUMMARY_ARGS[@]}"} | tee -a "$RUN_DIR/summary.txt"
SUMMARY_STATUS=${PIPESTATUS[0]}
# Tests that ran out of the time allowance, counted apart (the summary
# above counts each as whatever XCTest printed for it, passed included).
ALLOWANCE_REPORT=$(san_allowance_report "$RUN_DIR/test.log" "$ALLOWANCE")
if [ -n "$ALLOWANCE_REPORT" ]; then
    printf '%s\n' "$ALLOWANCE_REPORT" | tee -a "$RUN_DIR/summary.txt"
fi
if [ "$SUMMARY_STATUS" -eq 3 ]; then
    echo "error: the run executed no tests; check the TEST names. Its report count proves nothing." >&2
elif [ "$SUMMARY_STATUS" -eq 1 ] && [ "$MODE" = thread ]; then
    echo "error: the thread sanitizer reported races outside the baseline, or reports that cannot be compared with it (see the verdict above and docs/swift-migration/thread-baseline.md)" >&2
elif [ "$SUMMARY_STATUS" -eq 1 ] && [ "$MODE" = combined ]; then
    echo "error: the combined run failed its nullability verdict: nullability reports outside the baseline, unclassifiable or incomplete reports, or report files that do not parse (see the verdict above)" >&2
elif [ "$SUMMARY_STATUS" -eq 1 ] && [ "$MODE" = nullability ]; then
    echo "error: the nullability run failed its verdict: reports outside the baseline, incomplete reports or report files that do not parse (see the verdict above, with the tests the reports came from; docs/swift-migration/nullability.md section 7)" >&2
elif [ "$SUMMARY_STATUS" -ne 0 ]; then
    echo "error: sanitizer_summary.py failed with status $SUMMARY_STATUS" >&2
fi
if [ "$MODE" = combined ]; then
    combined_verdicts
fi
if [ "$STATUS" -eq 0 ] && [ "$SUMMARY_STATUS" -ne 0 ]; then
    STATUS=1
fi
exit $STATUS
