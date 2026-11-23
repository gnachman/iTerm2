# Test speed

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The process runs tests on every commit, and there will be many thousands of
commits. A suite that takes about 20 minutes to run serially is too slow for
that. Making it faster is Phase 0 work and continues throughout.

## 1. Where the time goes

From the log of a full parallel run on 2026-11-12 (`tmp/full-tests.log`):

| Measure | Value |
|---|---|
| Test results | 11,850: 11,177 passed, 673 skipped, none failed |
| Wall-clock time, parallel, including the build step | 608 seconds, of which about 510 were testing |
| Sum of individual test times | 1,183 seconds, about 20 minutes, which is what a serial run costs |
| Tests taking 5 seconds or more | 25, totalling 560 seconds (47%) |
| Tests taking 1 second or more | 234, totalling 948 seconds (80%) |
| All the other results | 11,616, of which 673 skipped, totalling 235 seconds |

The time is extremely concentrated:

- Two tests in `FramerFlowTwoHopSimulationTests` take 249 and 114 seconds.
  Together they are 31% of all test time. The class as a whole (10 tests) is
  415 seconds, 35%.
- The next slowest classes are `TokenExecutorPermitTests` (60 seconds), four
  `ShellIntegrationOffline...InstallerTests` classes (34 to 55 seconds each),
  `RemoteGitStateParityTests` (44), `TmuxDividerMoverPropertyTests` (34),
  `ProcessCollectionTests` (33, of which one test is 33), and
  `FramerFlowSimulationTests` (27).
- The suite runs with the address sanitizer: the ModernTests test plan
  (`ModernTests/ModernTests.xctestplan`) enables it, and sets
  MallocStackLogging and other malloc diagnostics in the test environment.
  The address sanitizer costs time on every test.

Patterns in the test sources that usually mean real time is being spent
waiting: 265 expectation waits, 230 timeouts of five seconds or more, 64 run
loop spins, and 11 sleeps. Not all are slow in practice; the log says which.

These figures come from one run. `tools/swift_migration/test_timing.py`
turns a test log into per-test and per-class times (see its `--help`), and
`tools/swift_migration/test_tiers.py` combines several logs, so the numbers
are regenerated, not stored. Figures from 21 runs on 2026-11-20 are in
[test-tiers.md](test-tiers.md).

## 2. Plan

1. **Fix the worst offenders first.** No single test should take anywhere near
   114 seconds, let alone 249. The two slowest tests are worth more than
   everything else combined, and they are fixed, not moved aside: demoting
   them would leave the full suite as slow as it is now. For each of the
   roughly 25 tests over five seconds, find out why it is slow (real waiting,
   a very large simulated workload, an external process, a view layout pass)
   and make it fast. A test that genuinely cannot be made fast goes to the
   slow tier with the reason recorded. On 2026-11-20, 31 tests had a median
   of five seconds or more ([test-tiers.md](test-tiers.md), which also has
   the work list for the ten slowest). The ceiling for any single test in
   any tier is 10 seconds; a test over the ceiling fails the gate. Most tests
   should take under 1 second, and that is the target for new tests and for
   the tests being fixed.
2. **Two tiers.**
   - *Fast tier.* Everything except tests that take a second or more. On the
     numbers of 2026-11-20 that is about 11,500 tests with timings; their
     serial time in the address sanitizer runs was a median of 371 seconds.
     One run as it runs, without the address sanitizer, on a loaded machine,
     took 94 seconds of wall time in parallel plus the build
     ([test-tiers.md](test-tiers.md)). `tools/swift_migration/fast_tests.sh`
     runs it. It is meant to be what the gate runs on every commit; until
     the owner switches gate step 3 ([README.md §5](README.md)), the gate
     runs the whole suite.
   - *Full suite.* Everything. Run at the close of a unit and before any push,
     normally and with the sanitizers.
   The fast tier is defined by the list of excluded tests in
   `tools/swift_migration/slow_tier.txt`, each with its reason, so the list
   is reviewable and a test cannot leave the fast tier unnoticed. It is a
   checked-in list read by `fast_tests.sh`, not a test plan.
3. **Slow tests still run when they are relevant.** The targeted tests for a
   unit (gate step 2) include any slow test that covers it. A port of framer
   flow control runs the framer simulations regardless of tier.
4. **A budget for tests.** A test that takes more than one second needs a
   reason or goes to the slow tier. Time spent in the class's `+setUp`
   does not count toward a test's second (the owner, 2026-11-22:
   decisions.md). Tests written for the migration are held
   to a stricter standard: no real-time waits, no sleeps, no dependence on
   timing, in line with the project rule that tests must not be flaky.
5. **The fast tier runs without the address sanitizer.** The full suite keeps
   it. This trades some detection per commit for speed, and the full suite at
   unit close restores the detection before anything is pushed.
6. **Count the build.** The time from saving a file to seeing a test result
   includes compiling a Swift module of about 940 files as a whole. In the run
   above, about 100 seconds were not testing. This is measured in the pilot;
   if it dominates, splitting leaf code into separate modules ([performance.md §1](performance.md))
   becomes urgent for speed and not only for hygiene.
7. **Targeted selection.** At first, the tests for a unit are chosen by hand
   and listed in the dossier. Later, a map from source file to the test
   classes that execute it can be produced from a coverage run and regenerated
   periodically, so that the targeted set is derived.

## 3. Rules

- A test is never disabled or deleted to make the suite faster without the
  owner's approval. Moving a test to the slow tier is allowed and is visible
  in the diff of `tools/swift_migration/slow_tier.txt`.
- A test is never weakened to make it faster. Reducing iterations or inputs
  changes what it proves; that needs the same approval.
- **A flaky test is disabled** without waiting for the owner. A test is
  flaky only when, on one commit and with no change to the code, it has
  failed at least once in a full run and passed when run alone. A test that
  fails consistently, including one that also fails when run alone, is a
  failure, not a flake. A test among a unit's targeted tests (gate step 2)
  is not treated as flaky while that unit's change is uncommitted: a failure
  there is a finding against the change. The orchestrator disables a flaky
  test, records it in `bugs.md` with how it failed and when, and reports it
  to the owner in [owner-queue.md](owner-queue.md); the owner has another
  agent debug it. It is never retried until it passes. Deleting or
  weakening a test, or disabling one for any other reason, still needs the
  owner.
- The fast tier has a wall-clock budget, including the build. It is set
  once the fast tier has been measured in Phase 0, at the measured time plus
  a quarter. A commit that pushes the fast tier over budget fails the gate
  until the offending test is fixed or reassigned.
