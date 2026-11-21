# Test tiers: the data

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first. The rules are in [test-speed.md](test-speed.md);
this file holds the numbers behind the fast tier, how to regenerate them, and
the work list for the slow tests. It is data, not rules.

## 1. What exists

- `tools/swift_migration/slow_tier.txt`: the slow tier, one class or test
  per line with its reason. Every other ModernTests test is in the fast tier.
  Its timing entries are derived from address sanitizer medians, so the list
  is expected to shrink once enough fast-tier evidence exists (section 3).
- `tools/swift_migration/fast_tests.sh`: runs the fast tier with no address
  sanitizer and no MallocStackLogging. It builds with
  `sanitizer_tests.sh plain --build-only`, copies that build's `.xctestrun`
  without the MallocStackLogging variables the ModernTests test plan sets,
  and runs `xcodebuild test-without-building` on a pseudo-terminal (so that
  xcodebuild's two output streams stay in order) with one `-skip-testing:`
  per slow-tier entry. `--dry-run` prints the exact commands and the skipped
  entries; `--no-skip` runs the whole suite the same way, which is the
  evidence for taking entries out of the slow tier.
- `tools/swift_migration/test_tiers.py`: per-test maximum and median across
  several logs (`stats`), the split of each log's serial time between the
  tiers (`budget`), slow-tier lines for fast-tier tests at or over one second
  (`propose`), slow-tier entries that no longer take a second
  (`propose-removals`), and the helpers `fast_tests.sh` uses (`skip-args`,
  `strip-env`). It reads logs with `test_timing.py`'s parser, which
  attributes each result of a parallel log to its test by name, so the
  interleaved output of several test hosts does not matter.

**The first real runs** (2026-11-20, lane-8, on a machine loaded by other
agents' builds; measured facts, not the budget). The second run used the
fixed tooling and the first run's build (`--no-build`):

| | Run 1 | Run 2 |
|---|---|---|
| Build (`sanitizer_tests.sh plain --build-only`, fresh build directory) | 341 s | not built |
| Test phase, wall time (parallel) | 94 s | 42 s |
| Passed, failed, skipped | 11,471, 0, 445 (and 3 expected failures then unparsed) | 11,475, 0, 445 |
| Serial sum of test times | 396 s | 207 s |
| Tests at or over 10 s | none (slowest 8.1 s) | none |
| Tests at or over 1 s | 65 | 16 |
| End-of-log marker | `** TEST EXECUTE SUCCEEDED ** [89.786 sec]` | `** TEST EXECUTE SUCCEEDED ** [41.752 sec]` |
| `timing.txt` | incomplete (the defects below) | complete, no warning |
| Exit status | 0 | 0 |

`strip-env` removed the three MallocStackLogging variables from the plain
build's real `.xctestrun`, and no slow-tier test ran. Run 1's log showed
three defects of the tooling, fixed since: results after the end marker
(xcodebuild's two streams through a pipe; the test step now runs on a
pseudo-terminal), "recorded an expected failure" results that the timing
script did not parse, and suites that `-skip-testing` emptied taken for
damage (`test_timing.py --skip-list`).

**The budget is not set.** It needs runs on a quiet machine
(test-speed.md section 3: the measured time, including the build, plus a
quarter).

## 2. The data (2026-11-20)

**Logs.** 21 full-suite runs with the address sanitizer
(`tools/run_tests.expect -parallel`, 12,348 to 12,436 results each, from
slightly different trees), found by their `Command line invocation:` line:
in the main checkout `tmp/full-binding.log`, `tmp/full-binding-review.log`,
`tmp/full-binding-fix.log`, `tmp/full-slow-tests.log`,
`tmp/full-slow-review.log`, `tmp/full-classcheck.log`,
`tmp/xlog-to-rlog/tests.log` and `tests2.log`,
`tmp/delete-stale-files/tests.out` and `tests2.out`,
`tmp/delete-unused-reflective-helpers/tests.out`,
`tmp/swift-build-conditions/tests1.out` and `tests2.out`; in the lanes
`lane-3/tmp/gate-test.out`, `lane-3/tmp/bound/suite.log` and `suite2.log`,
`lane-2/tmp/helpers-like-c/full.log`, `lane-2/tmp/floatclamp/full.log`,
`lane-1/tmp/integer-fixes/full.log`,
`lane-1/tmp/nullability-n2-n4-n5/full-suite.out` and
`lane-1/tmp/n3n6n7/full-suite.out`. Eight of them are incomplete in
`test_timing.py`'s sense; their times are used. These files are not
committed and may be gone.

Two runs without the address sanitizer (`sanitizer_tests.sh plain
--parallel`), one of each kind: `tmp/full-noasan.log` (MallocStackLogging
on, as the test plan sets it) and `tmp/full-noasan-nomsl.log`
(MallocStackLogging off; how it was turned off is not recorded in the log).

**Serial totals** (the sum of all result times) of the 21 address sanitizer
runs: median 1,390 s, from 1,220 to 1,883 s. The machine was shared with
other agents' builds all day, so the maxima are mostly load.

**Tests over 5 seconds.** By median, 31 tests take 5 seconds or more, and 9
of them 10 seconds or more. By maximum (the worst of 21 runs) it is 124 and
83: on a loaded machine many usually fast tests have one slow run. The
median list:

| Test | Median s | Max s | Runs |
|---|---|---|---|
| `FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp` | 224.3 | 270.9 | 21 |
| `FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenTheOuterHopSpeedsUpAtAnyMoment` | 98.4 | 122.3 | 21 |
| `SmartSelectionTranslationLayoutTests/testLinksFit` | 41.1 | 50.2 | 21 |
| `ManualAIModelEditorCredentialPopupWidthTests/testTranslatedAutomaticChoicesFit` | 40.9 | 52.2 | 21 |
| `PSMTabGroupDragInvariantTests/testEveryPairOfItems` | 27.5 | 35.1 | 21 |
| `FramerFlowTwoHopSimulationTests/testASlowOuterHopBoundsCtrlCAtTheInnerHost` | 17.3 | 22.0 | 21 |
| `SmartSelectionTranslationLayoutTests/testRegexLabelFits` | 12.3 | 39.9 | 21 |
| `ShellIntegrationInstallerStepsLayoutTests/testStepsFitInEveryLanguage` | 11.8 | 20.5 | 21 |
| `FramerFlowTwoHopSimulationTests/testAJitteryOuterHopStillBoundsCtrlC` | 10.0 | 12.7 | 21 |
| `SmartSelectionTranslationLayoutTests/testBottomRowFits` | 9.3 | 11.5 | 21 |
| `FramerFlowSimulationTests/testWatchingTheControllerDoesNotChangeWhatItDoes` | 8.9 | 10.7 | 21 |
| `AISafetyRefusalParserTests/testEachStreamingFixtureProducesNonEmptyMessage` | 7.5 | 9.2 | 21 |
| `TmuxDividerMoverPropertyTests/testNonFiniteAndExtremeMeasurementsDoNotCrash` | 7.4 | 9.0 | 21 |
| `FramerFlowTwoHopSimulationTests/testFloodsOnBothHostsShareTheOuterHop` | 7.3 | 9.4 | 21 |
| `TwoTierTokenQueueTests/testTokensAddedDuringFirstAccessAreNotLost` | 6.4 | 10.9 | 21 |
| `ManualAIModelEditorTranslationLayoutTests/testFetchModelsButtonFitsEveryTitle` | 6.4 | 11.3 | 21 |
| `TmuxDividerMoverPropertyTests/testDividerMovesMonotonically` | 6.3 | 7.9 | 21 |
| `ManualAIModelEditorKeyHintLayoutTests/testEveryTranslatedHintFitsTheEditor` | 6.2 | 9.9 | 21 |
| `TokenExecutorPermitTests/testWaiterInCopyModePassesThePermitOn` | 6.1 | 6.2 | 21 |
| `ManualAIModelEditorTranslationLayoutTests/testTranslatedTitlesFit` | 6.0 | 9.0 | 21 |
| `TmuxDividerMoverPropertyTests/testArbitraryMeasurementsGiveValidLayouts` | 5.8 | 7.4 | 21 |
| `TmuxDividerMoverPropertyTests/testAnyReachableLayoutRoundTrips` | 5.8 | 7.9 | 21 |
| `PSMTabGroupDragTests/testStillMouseBeforeParentChipSettlesWhenDraggingCollapsedSubgroup` | 5.8 | 21.7 | 21 |
| `ShellIntegrationInstallerButtonLayoutTests/testInternetFreePageBottomButtonsFit` | 5.7 | 9.6 | 21 |
| `PTYSessionSelectedCommandSearchTests/testDeselectingByTypingSearchesEverythingWithoutSelectingAResult` | 5.6 | 22.8 | 21 |
| `HotkeySettingsLabelLayoutTests/testLabelsFitEveryTranslation` | 5.2 | 12.8 | 21 |
| `ShellIntegrationInstallerStepsLayoutTests/testGermanNushellStepsNeedMoreThanTheNibHeight` | 5.2 | 10.6 | 21 |
| `ToolStatusCellViewJobExitTests/test_jobExitAfterReconfigureUpdatesTheRow` | 5.2 | 5.3 | 21 |
| `SwiftyStringTextFieldRenameTests/test_renameAfterReuseUpdatesTheField` | 5.1 | 5.3 | 21 |
| `TokenExecutorPermitTests/testSessionFreedWhileWaitingLeavesTheLine` | 5.1 | 5.2 | 21 |
| `ProgramStatusDisplayRecordTests/testBatchOfNewRecordsAndClearsIsHandled` | 5.0 | 6.2 | 21 |

**Tests over 1 second.** By median, 259 tests take a second or more (454 by
maximum). They are the ten tests of `FramerFlowTwoHopSimulationTests` and
the 249 lines marked "ceiling" or "one second" in `slow_tier.txt`, each with
its median and maximum.

**Classes** by the sum of their tests' medians (of 1,007 classes with
timings):

| Class | Tests | Sum of medians s | Sum of maxima s |
|---|---|---|---|
| `FramerFlowTwoHopSimulationTests` | 10 | 367.9 | 451.1 |
| `SmartSelectionTranslationLayoutTests` | 6 | 63.7 | 103.3 |
| `TokenExecutorPermitTests` | 23 | 58.9 | 62.4 |
| `ShellIntegrationOfflineTcshFromZshDeferredCompletionInstallerTests` | 30 | 53.1 | 89.1 |
| `ShellIntegrationOfflineTcshFromZshInstallerTests` | 30 | 46.0 | 57.3 |
| `ManualAIModelEditorCredentialPopupWidthTests` | 3 | 41.1 | 52.9 |
| `ShellIntegrationOfflineDashDeferredCompletionInstallerTests` | 30 | 39.4 | 45.5 |
| `TmuxDividerMoverPropertyTests` | 12 | 32.5 | 41.0 |
| `ShellIntegrationOfflineDashInstallerTests` | 30 | 31.9 | 54.0 |
| `RemoteGitStateParityTests` | 25 | 30.7 | 54.5 |
| `PSMTabGroupDragInvariantTests` | 2 | 29.6 | 37.7 |
| `FramerFlowSimulationTests` | 22 | 26.0 | 32.5 |
| `It2gitParityTests` | 25 | 24.8 | 37.8 |
| `ShellIntegrationInstallerStepsLayoutTests` | 2 | 17.0 | 31.1 |
| `iTermGitClientTests` | 28 | 14.4 | 17.9 |

## 3. The slow tier and the fast tier's time

**The slow tier** (`slow_tier.txt`, 280 entries):

- The ten tests of `FramerFlowTwoHopSimulationTests`, each listed: the two
  slowest by the owner's decision (owner-queue.md Q22), the other eight by
  the one-second rule (medians 1.3 to 17 s).
- `RuntimeSnapshotTests/testHeaderRecordsArchitectureAndConfiguration`: it
  fails in any build outside `Build/` (bugs.md), and the fast tier is built
  in `tmp/sanitizers/plain`. It failed in both plain runs.
- 20 classes that put windows on screen and skip themselves unless
  `ITERM2_ONSCREEN_TESTS=1` (every test of each was skipped in all 21 runs),
  so the fast tier stays off screen even when the variable is set.
- 249 other tests with a median of one second or more: 5 over the
  10-second ceiling, marked "ceiling", and 244 marked "one second". None
  has a recorded reason to stay in the fast tier (test-speed.md section 2).

The one-second rule is test-speed.md's; measuring it by the median of the
address sanitizer runs was this unit's choice, made because those were the
runs with enough repeats. The fast tier runs without the sanitizer, where
many tests are faster, so **the list is expected to shrink** once enough
runs of the whole suite as the fast tier runs it exist (`fast_tests.sh
--no-skip`; a fast-tier run skips these tests and is no evidence).
`test_tiers.py propose-removals` lists the timing entries whose median in
such runs is under one second over at least three runs (`--min-runs`). It
has not been applied: one loaded run is not enough. As an indication only,
on the single plain run without MallocStackLogging (`--mode plain
--min-runs 1`), 87 of the 257 timing entries took under one second; the
classes that would lose the most:

| Class | Proposed for removal | Listed for their time |
|---|---|---|
| `It2gitParityTests` | 8 | 8 |
| `ShellIntegrationOfflineDashInstallerTests` | 4 | 14 |
| `FramerFlowSimulationTests` | 4 | 6 |
| `LocalizationHygieneTests` | 4 | 5 |
| `ShellIntegrationOfflineTcshFromZshInstallerTests` | 3 | 23 |
| `FramerFlowTwoHopSimulationTests` | 3 | 8 |
| `PasteSpecialTranslationLayoutTests` | 3 | 3 |
| `ShellIntegrationInstallerButtonLayoutTests` | 3 | 3 |
| `TabGroupSubgroupDragOutTests` | 3 | 3 |
| `ShellIntegrationOfflineTcshFromZshDeferredCompletionInstallerTests` | 2 | 27 |
| `ShellIntegrationOfflineDashDeferredCompletionInstallerTests` | 2 | 20 |
| `RemoteGitStateParityTests` | 2 | 15 |


Not in the slow tier: the three weak-reference tests
(`PromptMarkExcludedSubrangeTests.test_codable_foldRC_deadWeakBox_encodesAsInvalid`,
`ResilientCoordinateTests.test_dict_invalid_shapeMatchesCodable`,
`WeakReferenceTests.testTwoWeakReferencesToSameObjectBothNullify`). They
failed without the address sanitizer on the night of the sanitizer runs, but
the unit `phase0-weakref-tests-pool` fixed them (they now read the object in
an explicit autorelease pool), and both plain runs passed them.

**The fast tier** has 11,527 tests with timings in the address sanitizer runs
(11,405 in the plain runs), plus the tests that skip themselves.

**Its serial time**, from the logs, with `test_tiers.py budget`:

| Runs | Whole suite, serial s | Fast tier, serial s | Slow tier, serial s |
|---|---|---|---|
| 21 with the address sanitizer (median; range) | 1,390 (1,220 to 1,883) | 371 (236 to 621) | 1,056 (968 to 1,292) |
| 1 plain, MallocStackLogging on | 1,862 | 338 | 1,524 |
| 1 plain, MallocStackLogging off | 786 | 196 | 590 |

The two plain rows are one run each on a shared machine, so they say little
about the size of the difference; they are not a speed-up factor. The fast
tier as `fast_tests.sh` runs it (plain, MallocStackLogging off, the slow tier
skipped, in parallel) has not been run: its serial and wall-clock times are
unknown until it is. The wall-clock time of a parallel run, and the build
time the budget includes, cannot be derived from these logs. The first real
run of `fast_tests.sh` is in section 1.

**Risks the first runs should check:**

- In the plain run without MallocStackLogging, 8 fast-tier tests took a
  second or more, among them
  `BrowserPopupUserContentControllerTests/testWebKitAcceptsPopupWithItsOwnUserContentController`
  (20.2 s; median 0.57 s with the address sanitizer) and
  `TaskIOCharacterizationWithChildReaperTests/testCoprocessRoundTrip`
  (4.4 s). Once several fast-tier runs exist, `test_tiers.py propose --mode
  fast` lists the tests to re-judge.
- 46 fast-tier tests have a median under one second but took 10 seconds or
  more in at least one address sanitizer run (the worst,
  `StatusPriorityPopoverLayoutTests/testNotifyHeaderFits`, 78 s against a
  median of 0.2 s; bugs.md has an entry for that class under load).

**Open question for the owner: the ceiling.** test-speed.md section 2 says a
test over the 10-second ceiling fails the gate. `fast_tests.sh` reports such
tests but does not fail the run on them, because 46 fast-tier tests took 10
seconds or more in a single loaded address sanitizer run while their medians
are under one second: enforcing the ceiling run by run would fail the gate at
random. Should the ceiling be judged on the median of several runs, or should
those tests be fixed first and the ceiling then enforced per run?

Until the owner switches gate step 3 ([README.md §5](README.md)) to the
fast tier, the gate runs the whole suite.

## 4. Work list: the ten slowest tests

Why each is slow, from reading the test (none was profiled, except that
owner-queue.md Q22 records 91 percent of the two-hop simulations' time
inside `FramerFlowController`), and what a fix would be. Nothing here has
been changed. Medians are from the address sanitizer runs.

1. **`FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp`**
   (224 s). `checkRecovery` runs 15 simulations of 100 simulated seconds
   (the speed-up moment from 30.0 to 39.8 s in steps of 0.7), once for each
   of two jitters: 30 simulations, each stepping both `FramerFlowController`s
   every simulated millisecond (100,000 steps). Fix: an event-driven loop
   that jumps to the next arrival or controller tick instead of stepping
   every millisecond. Fewer speed-up moments would change what it proves.
   The owner put the class in the slow tier and `FramerFlowController` is
   not to change.
2. **`FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenTheOuterHopSpeedsUpAtAnyMoment`**
   (98 s). The same with one jitter: 15 simulations. Same fix.
3. **`SmartSelectionTranslationLayoutTests/testLinksFit`** (41 s). For each
   of 125 titles it builds a controller whose six frames are each found by
   an XPath search (`//*[@id='...']`) of the whole 1.2 MB
   `PreferencePanel.xib` document, with two more searches per title:
   about 1,000 searches of the document. `-setUp` parses the xib again for
   every test. Fix: parse it once per class and index the elements by id in
   one pass.
4. **`ManualAIModelEditorCredentialPopupWidthTests/testTranslatedAutomaticChoicesFit`**
   (41 s; 5.6 s in the plain run without MallocStackLogging). For each of
   41 languages it parses the whole `Localizable.strings` (1.3 MB in the
   German build) and creates three editor controllers. The large gap
   between the address sanitizer and plain runs points at the
   allocation-heavy parse. Fix: parse each language's table once per
   process and reuse one editor.
5. **`PSMTabGroupDragInvariantTests/testEveryPairOfItems`** (27 s). A
   deliberate exhaustive check: 64 bar layouts, every draggable group in
   each, a sweep across the bar and back in 4-point steps, holding 24 ticks
   of the real drag animation at each position and fingerprinting the bar
   every tick. Splitting it into several test methods (for example by the
   first item) lets parallel workers share it without changing what it
   proves. Fewer ticks or wider steps would change what it proves and need
   the owner.
6. **`FramerFlowTwoHopSimulationTests/testASlowOuterHopBoundsCtrlCAtTheInnerHost`**
   (17 s). 14 simulations of 60 simulated seconds at one-millisecond steps
   (two, then six nearby paths for each of two designs). Same fix as 1.
7. **`SmartSelectionTranslationLayoutTests/testRegexLabelFits`** (12 s). 41
   controllers, seven whole-document XPath searches each. Same fix as 3.
8. **`ShellIntegrationInstallerStepsLayoutTests/testStepsFitInEveryLanguage`**
   (12 s). `-stringForKey:language:` parses the whole 1.3 MB
   `Localizable.strings` for every key it looks up: eight keys for each of
   41 languages, 328 parses, and the nib is instantiated 82 times. Fix: parse
   each language's table once.
9. **`FramerFlowTwoHopSimulationTests/testAJitteryOuterHopStillBoundsCtrlC`**
   (10 s). 12 simulations of 60 simulated seconds at one-millisecond steps.
   Same fix as 1.
10. **`SmartSelectionTranslationLayoutTests/testBottomRowFits`** (9.3 s). 41
    controllers, six whole-document XPath searches each. Same fix as 3.

Nine of the ten share two causes: re-parsing large localization or xib files
inside loops (3, 4, 7, 8, 10) and millisecond-stepped simulations (1, 2, 6,
9).

## 5. Regenerating

```
# Per-test maximum and median over several full-suite logs (address
# sanitizer runs by default; --mode fast for fast-tier runs, fast-full for
# fast_tests.sh --no-skip, plain for sanitizer_tests.sh plain):
python3 -B tools/swift_migration/test_tiers.py stats LOG ...
# The tiers' serial totals per log, stale slow-tier entries, and fast-tier
# tests still at or over one second:
python3 -B tools/swift_migration/test_tiers.py budget --slow-tier tools/swift_migration/slow_tier.txt LOG ...
# Slow-tier lines for those tests:
python3 -B tools/swift_migration/test_tiers.py propose --slow-tier tools/swift_migration/slow_tier.txt LOG ...
# Timing entries that no longer take a second (fast_tests.sh --no-skip logs):
python3 -B tools/swift_migration/test_tiers.py propose-removals --slow-tier tools/swift_migration/slow_tier.txt LOG ...
# The stale entries budget lists mean something only for full-suite logs.
# What the fast tier would run:
tools/swift_migration/fast_tests.sh --dry-run
```

A log of another mode than the one asked for (thread, ubsan, coverage,
plain, fast, fast-full, asan) or with the same content as an earlier one is left out and the
output says so, so a directory of mixed logs can be passed as it is.
