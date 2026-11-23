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

**The third run** (2026-11-21, unit `phase0-test-items`, lane-1, at the
master tip with that unit's test changes; the machine was loaded by other
agents' builds, load average about 100 when the evening started):

| | Run 3 |
|---|---|
| Command | `tools/swift_migration/fast_tests.sh` |
| Build (`sanitizer_tests.sh plain --build-only`, no plain build directory before, so a full build, though other builds' caches were warm) | 145 s (`** TEST BUILD SUCCEEDED ** [145.060 sec]`) |
| Test phase, wall time (parallel) | 128 s (`Tests finished with status 0 in 128 seconds`; end marker `** TEST EXECUTE SUCCEEDED ** [125.807 sec]`) |
| Whole command, wall time | 280 s |
| Passed, failed, skipped | 12,144, 0, 448 (12,592 results) |
| Serial sum of test times | 524 s |
| Tests at or over 10 s | none (slowest 8.4 s, `EditKeyActionMenuItemTests/testChangingOnlyTheKeystrokePreservesTheMenuItem`) |
| Tests at or over 1 s | 85 |
| Exit status | 0 |
| Log | `tmp/fast-tests/runs/20261121-201852/` in lane-1 (not committed) |

**The budget:** 77 s, set on 2026-11-22 from a quiet run of 61 s (build
about 21 s, tests 40 s). The run: the owner had quit his other programs,
the tool called the machine quiet (load average 2.33, 3.92 over one and
five minutes), no agent or build was running, the plain build directory
was up to date, and one Swift file of the app was touched first so the
build did real work.

| | Run 4 (the budget's run) |
|---|---|
| Command | `/usr/bin/time -p tools/swift_migration/fast_tests.sh` in the main checkout, on the app sources of "Port iTermColorSuggester to Swift" plus the nullable `-screenRestoreState:` annotation and the two sped-up translation layout tests |
| Whole command, wall time | 61.19 s (`real`) |
| Test phase, wall time (parallel) | 40 s (`Tests finished with status 0 in 40 seconds`; end marker `** TEST EXECUTE SUCCEEDED ** [39.585 sec]`) |
| Build | the rest, about 21 s |
| Passed, failed, skipped | 12,147, 0, 447 (12,594 results) |
| Serial sum of test times | 156 s |
| Tests at or over 10 s | none |
| Exit status | 0 |
| Log | `tmp/fast-tests/runs/20261122-100907/` (not committed) |

The budget is the whole command's wall time times 1.25, as test-speed.md
section 3 sets it. A cold build is not in it: whether one is to be budgeted
is not decided (owner-queue.md Q24 item 3; the ceiling and the malloc
settings are Q23 item 4). An untimed run a quarter of an hour earlier on
the same machine also passed with no test at or over ten seconds.

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

**The slow tier** (`slow_tier.txt`, 257 entries; 280 until unit
`phase0-test-items` took out two, and 278 until unit `slow-tests-over-5s`
took out 27 and replaced one test with seven of the eight it split it into
and another with one of the four, section 4):

- The ten tests of `FramerFlowTwoHopSimulationTests`, each listed: the two
  slowest by the owner's decision (owner-queue.md Q22), the other eight by
  the one-second rule (medians 1.3 to 17 s).
- `RuntimeSnapshotTests/testHeaderRecordsArchitectureAndConfiguration`: it
  fails in any build outside `Build/` (bugs.md), and the fast tier is built
  in `tmp/sanitizers/plain`. It failed in both plain runs.
- 20 classes that put windows on screen and skip themselves unless
  `ITERM2_ONSCREEN_TESTS=1` (every test of each was skipped in all 21 runs),
  so the fast tier stays off screen even when the variable is set.
- 226 other tests marked "one second": a median of one second or more in
  the 21 runs, or, for the entries unit `slow-tests-over-5s` changed or
  measured, a second or more alone after it (247 before 2026-11-22, of
  which 4 were marked "ceiling"; 249 before 2026-11-21). None is over the
  10-second ceiling any longer. The entries still at or over five seconds
  alone name the app code or the design that keeps them slow (section 4);
  none has a recorded reason to stay in the fast tier (test-speed.md
  section 2).

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

**Checked against the runs of 2026-11-21** (unit `phase0-test-items`, both
on a loaded machine):

- *Over the ceiling and not listed:* none. The fast tier run (section 1,
  run 3) had no test at or over 10 s; its slowest took 8.4 s.
- *At or over one second and not listed:* 85 fast-tier tests in that one
  run (`test_tiers.py budget --mode fast`). One loaded run is not enough to
  move them (the rule is the median); `test_tiers.py propose --mode fast`
  over several fast-tier runs lists them.
- *Listed and now under one second:* in the one full address sanitizer run
  (`tools/run_tests.expect -parallel`, all 13,093 results, none failed),
  `test_tiers.py propose-removals --mode asan --min-runs 1` lists 21 timing
  entries. Two of them are tests this unit changed
  (`SmartSelectionTranslationLayoutTests/testRegexLabelFits` and
  `testBottomRowFits`, 0.14 s and 0.63 s against medians of 12.3 s and
  9.3 s), a change of the code and not of the load, so they were taken
  out of `slow_tier.txt`. The other 19 were not changed and have only this
  one run under a second (most of them just under it); they stay until
  the tool lists them over the three runs it asks for.

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

**The ceiling: answered.** The owner, 2026-11-22: “Sure, median is fine”. The ceiling is judged on a test's median over several runs, not run by run (decisions.md); enforcing that in `fast_tests.sh` is not built yet. As asked:  test-speed.md section 2 says a
test over the 10-second ceiling fails the gate. `fast_tests.sh` reports such
tests but does not fail the run on them, because 46 fast-tier tests took 10
seconds or more in a single loaded address sanitizer run while their medians
are under one second: enforcing the ceiling run by run would fail the gate at
random. Should the ceiling be judged on the median of several runs, or should
those tests be fixed first and the ceiling then enforced per run?

Until the owner switches gate step 3 ([README.md §5](README.md)) to the
fast tier, the gate runs the whole suite.

## 4. Work list: the slow tests

**Tests over five seconds on 2026-11-21**, from one full address sanitizer
run in lane-1 (`tools/run_tests.expect -parallel`, 432 s wall time with
its build, 13,093 results, none failed, after this unit's changes; a
loaded machine): 31 tests, 563 s of the 1,226 s serial total. The ten
slowest:

| Test | s |
|---|---|
| `FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp` | 233.4 |
| `FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenTheOuterHopSpeedsUpAtAnyMoment` | 108.5 |
| `PSMTabGroupDragInvariantTests/testEveryPairOfItems` | 26.2 |
| `FramerFlowTwoHopSimulationTests/testASlowOuterHopBoundsCtrlCAtTheInnerHost` | 20.0 |
| `ShellIntegrationInstallerStepsLayoutTests/testStepsFitInEveryLanguage` | 11.3 |
| `FramerFlowTwoHopSimulationTests/testAJitteryOuterHopStillBoundsCtrlC` | 9.6 |
| `FramerFlowSimulationTests/testWatchingTheControllerDoesNotChangeWhatItDoes` | 8.7 |
| `FramerFlowTwoHopSimulationTests/testFloodsOnBothHostsShareTheOuterHop` | 8.6 |
| `ManualAIModelEditorCredentialPopupWidthTests/testTranslatedAutomaticChoicesFit` | 8.0 |
| `ManualAIModelEditorKeyHintLayoutTests/testEveryTranslatedHintFitsTheEditor` | 7.6 |

The other 21, each between 5.0 and 7.2 s: `TmuxDividerMoverPropertyTests`
(four), `AISafetyRefusalParserTests/testEachStreamingFixtureProducesNonEmptyMessage`,
`TwoTierTokenQueueTests/testTokensAddedDuringFirstAccessAreNotLost`,
`ShellIntegrationInstallerStepsLayoutTests/testGermanNushellStepsNeedMoreThanTheNibHeight`,
`TaskIOMonitorCharacterizationTests` (two),
`TokenExecutorPermitTests` (two),
`ProfileBoolSettingPickerTests/testOnOffChangeWithClosedDropdownKeepsKeyAndUpdatesValue`,
`ManualAIModelEditorTranslationLayoutTests` (two),
`CharsetPerformanceTests/testPerf_ascii`,
`ExecutorUpdateTickerTests/testNoUpdateIsLostUnderConcurrency`,
`PTYSessionSelectedCommandSearchTests/testDeselectingByTypingSearchesEverythingWithoutSelectingAResult`,
`ToolStatusCellViewJobExitTests/test_jobExitAfterReconfigureUpdatesTheRow`,
`HotkeySettingsLabelLayoutTests/testLabelsFitEveryTranslation`,
`SwiftyStringTextFieldRenameTests/test_renameAfterReuseUpdatesTheField` and
`ProgramStatusDisplayRecordTests/testBatchOfNewRecordsAndClearsIsHandled`.
`tools/swift_migration/test_timing.py --threshold 5 LOG` prints the list.

**Fixed on 2026-11-21** (unit `phase0-test-items`, kind `test`; test code
only, no assertion, input or iteration changed). Times are single runs
alone with the address sanitizer (`tools/run_tests.expect`), on a loaded
machine:

- **`SmartSelectionTranslationLayoutTests`** (`testLinksFit`
  39.5 s to 1.4 s, `testRegexLabelFits` 11.7 s to 0.13 s,
  `testBottomRowFits` 8.9 s to 0.53 s; the class 61 s to 2.2 s). The cause
  was as item 3 of the old list said: every frame was found by an XPath
  search of the whole 1.2 MB `PreferencePanel.xib` (about 66 ms each), about
  1,000 times, and `-setUp` parsed the xib for every test; each string was
  looked up by parsing its whole table. The xib is now parsed once per
  process, each found frame and each parsed table is kept for the run, and
  a missing element or table is not kept, so it still fails every test
  that asks for it. Mutation: without
  `[self growLinkToFit:_visualizationButton]` in
  `-[SmartSelectionController layoutForTranslations]`, `testLinksFit`
  fails (for example “206 is less than 233”); restored byte for byte.
- **`ManualAIModelEditorCredentialPopupWidthTests/testTranslatedAutomaticChoicesFit`**
  (32.9 s, and 44.9 s in a second run, to 8.0 s). Item 4 of the old list
  blamed the parse of `Localizable.strings`; a `sample` of the running test
  showed the main thread almost entirely in building editors, with most
  samples in the Objective-C runtime's weak reference table
  (`weak_unregister_no_lock`, `weak_entry_for_referent`) and in adding
  notification observers: all 123 editors and their controls stayed alive
  until the test ended, and each new one cost more. Each iteration now runs
  in an `@autoreleasepool`. Still 8 s, about 65 ms per editor under the
  address sanitizer; making it faster means sharing an editor between
  iterations, which would change what is measured
  (`-sizeCredentialPopupToFit` reads the key field's right edge, which a
  clipped popup moves), so it is not done. Mutation: with the popup's width
  fixed at `kAICredentialPopupMinimumWidth` in `-sizeCredentialPopupToFit`,
  the test fails 74 assertions; restored byte for byte.

**Not changed on 2026-11-21, with the reason** (each was taken up on
2026-11-22, below):

1. **The framer two-hop simulations** (`FramerFlowTwoHopSimulationTests`,
   233 s, 108 s, 20 s, 9.6 s, 8.6 s and less). Each simulation steps both
   `FramerFlowController`s every simulated millisecond, and owner-queue.md
   Q22 records 91 percent of the time inside `FramerFlowController`. There
   is no sleep, wait or repeated setup to remove, and no clock to inject
   (the simulation already runs on simulated time). Making it fast means
   an event-driven loop that jumps to the next arrival or tick, which
   changes when the controllers are called and so what is simulated, or
   making `FramerFlowController` itself cheaper, which the owner ruled out
   (Q22). Fewer speed-up moments would weaken it. The owner put the two
   slowest in the slow tier; the others are there by the one-second rule.
2. **`PSMTabGroupDragInvariantTests/testEveryPairOfItems`** (26 s). A
   deliberate exhaustive check (64 bar layouts, every draggable group, a
   sweep in 4-point steps, 24 animation ticks at each position). Splitting
   it into several test methods would spread it over parallel workers but
   not reduce the work; fewer ticks or wider steps would weaken it.
3. **`ShellIntegrationInstallerStepsLayoutTests/testStepsFitInEveryLanguage`**
   (11 s) and `testGermanNushellStepsNeedMoreThanTheNibHeight` (6 s). Not
   attempted (the brief was the two slowest that could be fixed).
   `-stringForKey:language:` parses the whole 1.3 MB `Localizable.strings`
   for every key: 328 parses. Keeping each language's parsed table for the
   run, as `ShellIntegrationInstallerButtonLayoutTests` already does for
   the string catalog, should remove most of it without changing what it
   checks. Next in line.
4. **`FramerFlowSimulationTests/testWatchingTheControllerDoesNotChangeWhatItDoes`**
   (8.7 s). The one-hop simulation, same reason as 1.
5. **`ManualAIModelEditorKeyHintLayoutTests/testEveryTranslatedHintFitsTheEditor`**
   (7.6 s) and **`ManualAIModelEditorTranslationLayoutTests`** (5.9 and
   5.2 s). Not read. They build many `iTermManualAIModelEditorController`s
   too, so the cause found for the credential popup test (editors kept alive
   until the test ends) is the first thing to check.

**Worked through on 2026-11-22** (unit `slow-tests-over-5s`, kind `test`;
test code and `slow_tier.txt` only, no app code). The list was every test
at five seconds or more in the medians of section 2 or in either of two
full address sanitizer runs of 2026-11-21 in lane-1 (`tmp/rebase-tests.out`
and `tmp/gate-tests.out`): 41 tests, not counting the two framer tests
the owner put in the slow tier. "Before" and "after" are each one serial run of those
tests alone with the address sanitizer (`tools/run_tests.expect` with the
test and class names) in lane-2: before at the master tip, load average 7
to 12, and after with the change, load average 10 to 17; logs in lane-2's
`tmp/slow5/` (`before.log`, `after.log`, and `after-psmdrag.log` for the
split drag test), not committed. Together the 85 results before took
244 s and the 93 after 118 s. Every changed test still passes, and the
evidence that each still fails when it should is below the table.

| Test | Why it was slow | Change | Before s | After s |
|---|---|---|---|---|
| `TokenExecutorPermitTests`, all 23 (two over five seconds) | Each wait was an `XCTNSPredicateExpectation`, which checks its predicate about once a second, so every wait cost up to a second after the condition held | Each wait spins the main run loop and checks after every pass, with the same condition and 30-second limit; it fails with "Gave up waiting" | 59.3 for the class (6.2 and 5.1) | 0.6 for the class, each under 0.1 |
| `ToolStatusCellViewJobExitTests/test_jobExitAfterReconfigureUpdatesTheRow` | The same | The same, with a 10-second limit | 5.09 | 0.02 |
| `SwiftyStringTextFieldRenameTests/test_renameAfterReuseUpdatesTheField` | The same | The same | 5.11 | 0.003 |
| `PSMTabGroupDragInvariantTests/testEveryPairOfItems` | 64 layouts in one test; a third of the time was the test's own fingerprint of the bar, made on every hold tick though only the last 8 of 24 are compared | Split into eight tests, one per first building block, the same 64 layouts in the same order, plus a test that there are still 8 building blocks; the fingerprint is made in one pass over the bar's array, and only on the 8 compared ticks (every tick still runs) | 22.8 | eight tests, 0.73 to 3.23 by the median of three class runs (seven at a second or more, listed) |
| `PSMTabGroupDragTests/testStillMouseBeforeParentChipSettlesWhenDraggingCollapsedSubgroup` | 141 mouse positions in one test, each building a bar and starting and ending a drag; it slowed as it went (a quarter of the positions takes 0.6 s, the whole 9.4 s), most likely from what each drag leaves behind until the test ends | Split into four tests by mouse position (130 to 147.5, 148 to 165.5, 166 to 183.5, 184 to 200, in half points); each position still builds its own bar and drag | 8.16 (9.36 after the other changes) | four tests: medians 1.34 for `From130` (listed; its positions cost more, not its place in the class) and 0.60 to 0.64 for the others |
| `FramerFlowTwoHopSimulationTests/testASlowOuterHopBoundsCtrlCAtTheInnerHost` | 14 independent 60-second simulations one after another, almost all the time in `FramerFlowController` (owner-queue.md Q22) | The simulations run at once (`DispatchQueue.concurrentPerform`) and the assertions run afterwards on the main thread; each simulation has its own controllers and paths and the controller has no shared state | 14.17 | 1.83 |
| `FramerFlowTwoHopSimulationTests/testAJitteryOuterHopStillBoundsCtrlC` | 12 such simulations | The same | 8.91 | 1.36 |
| `FramerFlowTwoHopSimulationTests/testFloodsOnBothHostsShareTheOuterHop` | 14 such simulations | The same | 6.25 | 0.92 |
| The owner's two (`testANestedFloodRecovers...`), still in the slow tier by Q22 | 15 simulations of 100 seconds per jitter | The same | 240.6 and 111.5 in a full parallel run (not run alone before) | 28.5 and 12.7 alone, load average about 50 |
| `ShellIntegrationInstallerStepsLayoutTests/testStepsFitInEveryLanguage` | Parsed the 1.3 MB `Localizable.strings` once per key (9 keys, 41 languages) and read the nib from disk for each of 82 view controllers | Each language's parsed table and the `NSNib` are kept for the run and filled in the class `+setUp` (a table that fails to load is not kept); each view controller is still a fresh instantiation; a pool per case | 8.51 | 1.35 by the median of three class runs, plus about 0.75 in `+setUp` that no test is charged for |
| `ManualAIModelEditorKeyHintLayoutTests/testEveryTranslatedHintFitsTheEditor` | Kept all 41 editors alive, the cause found for the credential popup test, and parsed each table again | A pool per language; each parsed table kept for the run | 5.49 | 1.96 |
| `ManualAIModelEditorTranslationLayoutTests/testTranslatedTitlesFit` | The same | The same | 4.48 | 3.26 |
| `HotkeySettingsLabelLayoutTests/testLabelsFitEveryTranslation` | Parsed the 1.2 MB `PreferencePanel.xib` for each test and searched it by XPath once per label per language | The xib is parsed once and each found frame kept, as `SmartSelectionTranslationLayoutTests` does | 4.17 | 0.38 |
| `LocalizationFormatSpecifierParityTests/testTranslationsPreserveFormatArgumentCount` | Compiled its regular expression once per string counted | Compiled once | 3.43 | 1.70 |

Evidence that the changed tests still fail when they should (each change
to app code made alone, the tests run, then the file restored byte for
byte and checked with `git diff`):

- Without the dependency install in the completion block of
  `-[iTermGenericEvaluator evaluateSynchronously:sideEffectsAllowed:completion:]`
  (the fix the rename tests guard), all five
  `SwiftyStringTextFieldRenameTests` and both `ToolStatusCellViewJobExitTests`
  fail, the waits at their 10-second limit, for example “Evaluator observes only
  ["id"]” and “Field shows “-zsh”, expected “QA45C (-zsh)””.
- With `-[iTermShellIntegrationPasteShellCommandsViewController sizeStepListToFit]`
  returning before growing the list (`delta >= 0`),
  `testStepsFitInEveryLanguage` fails 27 assertions (“steps clipped”).
- With `ExecutionPermits.handOff` never waking the waiter it gives a permit
  to, `testSessionWaitsForAPermitAndRunsWhenOneFrees` and
  `testWaiterInCopyModePassesThePermitOn` fail with “Gave up waiting: b ran”
  and “Gave up waiting: c ran”. (Two other mutations, making a paused
  waiter count as runnable and dropping the copy-mode check from the
  executor's `settle`, left `testWaiterInCopyModePassesThePermitOn`
  passing; the path that passes the permit on lies elsewhere and was not
  traced.)
- The parallel simulations give the serial results: with a temporary check
  in `testFloodsOnBothHostsShareTheOuterHop` that ran its 14 simulations a
  second time one after another, every field of every result
  (`worstInnerWait`, `worstPaneWait`, `innerRate`, `paneRate`,
  `worstHost1Buffer`, `innerWindows`) was equal.
- The new fingerprint gives the old one: a temporary check computing both on
  every call compared 109,200 fingerprints in two of the invariant tests,
  all equal. Both temporary checks were removed.

What the faster waits change in `TokenExecutorPermitTests`: the old
`XCTNSPredicateExpectation` waited about a second even when its condition
already held, so a check that something did not happen, made after a wait
(b has run no token while a holds the only permit, b has run none in copy
mode or after its tokens were discarded, a has run only one token while
paused), used to look about a second later and now looks at once. That
second was an accident, in effect a sleep, and the checks were racy before
too, but a session that wrongly ran shortly afterwards was more likely to
be caught. Each such check now records the event itself: b's or a's
delegate notes any token that runs before the release, during copy mode or
during the pause, and the test asserts on that note after the session has
finished, so the check holds however late the wrong run happens. After its
tokens are discarded b has no note to make, so that test first waits for
anything already queued on b's queue (`b.queue.sync {}`) and then checks;
a wrong run scheduled later than that would still be missed.
No mutation was found that shows the new notes failing: the one tried,
letting `ExecutionPermits.acquire` succeed without a permit, stopped first
at the app's own assertion in `park` (“Parking a permit in state
waiting”).

The framer simulations, now run at once, were run under the thread
sanitizer (`tools/swift_migration/sanitizer_tests.sh thread
ModernTests/FramerFlowTwoHopSimulationTests`, lane-2
`tmp/sanitizers/runs/thread-20261122-120836`): all 10 tests passed, no
report, `Verdict: PASS: 0 report(s) outside the baseline, 0 unmatchable; 0
accepted.` The slowest took 53.3 s and 22.8 s, the others 1.5 to 3.8 s.

Measured again after review, three runs of the four classes alone with the
address sanitizer (lane-2 `tmp/slow5/r2-1.log` to `r2-3.log`, load average
10 to 14): `ShellIntegrationInstallerStepsLayoutTests/testGermanNushellStepsNeedMoreThanTheNibHeight`
took 5.72, 1.01 and 1.25 s. It runs first in its class and pays for the
first instantiation of the nib in the process, most likely AppKit setting
up, since the class `+setUp` has already read the nib and parsed every table
(the 0.05 s of the first measurement came from a process that had already
done that). It is back in the slow tier. All 55 tests of the four classes
passed in each run.

**At or over five seconds alone and not made fast**, in the slow tier with
the reason (each `slow_tier.txt` line names it):

- `ManualAIModelEditorCredentialPopupWidthTests/testTranslatedAutomaticChoicesFit`
  (6.59 before, 7.13 after, unchanged): 123 editors, one per case;
  `sample` shows almost all the time in
  `-[iTermManualAIModelEditorController initWithConfiguration:isEditing:]`,
  AppKit sizing the editor's controls. Sharing an editor would change what
  is measured (2026-11-21 entry above).
- `FramerFlowSimulationTests/testWatchingTheControllerDoesNotChangeWhatItDoes`
  (7.65, 7.67): its point is a snapshot of the controller twice every
  simulated millisecond for a minute, and most of the time is in
  `FramerFlowController.snapshot(now:)`. Its other simulation is a tenth of
  the time, so running the two at once would not help.
- `AISafetyRefusalParserTests/testEachStreamingFixtureProducesNonEmptyMessage`
  (6.08, 6.18): almost all the time is in
  `ResponsesResponseStreamingParser.splitFirstJSONEvent(from:)`, whose
  `SplitServerSentEvents` searches the remaining stream with
  `String.range(of:)` for every event, so a whole recorded stream costs
  time quadratic in its length. App code; reported, not changed.
- `TmuxDividerMoverPropertyTests`, four tests (5.2 to 6.4, unchanged):
  `sample` puts about 70 percent in `TmuxDividerMover` and
  `-[iTermTmuxLayoutBuilder layoutString]`, run for every divider of ten
  random layouts; the rest is the test's own reading and checking of each
  result.

Under five seconds alone but at or over it in a loaded full run, not
changed: `ProgramStatusDisplayRecordTests/testBatchOfNewRecordsAndClearsIsHandled`
(4.5; a guard against quadratic handling over 100,000 reports, three
quarters of the time in `ProgramStatusController.handle(_:)`),
`TaskIOMonitorCharacterizationTests/testStress` (4.0 to 4.3, real ptys and
threads), `CharsetPerformanceTests/testPerf_ascii` (3.9 and 1.8, a
`measure` block of app code; not in the slow tier),
`ManualAIModelEditorTranslationLayoutTests/testFetchModelsButtonFitsEveryTitle`
(3.0, 3.1; one editor per language), and tests under two seconds alone
that took five seconds or more only in a loaded parallel run
(`TaskIOMonitorCharacterizationTests/testBlockedReadDoesNotStallOtherTasks`,
`TaskIOCharacterizationWithChildReaperTests/testCoprocessRoundTrip`,
`ExecutorUpdateTickerTests/testNoUpdateIsLostUnderConcurrency`,
`TwoTierTokenQueueTests/testTokensAddedDuringFirstAccessAreNotLost`,
`PTYSessionSelectedCommandSearchTests/testDeselectingByTypingSearchesEverythingWithoutSelectingAResult`,
`ProfileBoolSettingPickerTests/testOnOffChangeWithClosedDropdownKeepsKeyAndUpdatesValue`,
`PSMTabGroupNestedDropSettlingTests/testStillMouseAtEndOfSubgroupAndParentSettles`,
`It2sshEndSSHAnswerTests/testBareControlCEndsTheWaitAndReturnsSSHStatus`,
`SwiftMigrationBetaAssertionFailsTestTests/testBetaAssertFailsTheRunningTest`,
`SearchableComboViewSelectionTests/testFailedSelectionClearsSelection`,
`ShellIntegrationInstallerButtonLayoutTests/testInternetFreePageBottomButtonsFit`,
`ShellIntegrationInstallerFirstPageLayoutTests/testLearnMoreLinksUseTheLabelFont`).

**The whole suite after it** (one run, `tools/run_tests.expect -parallel`
in lane-2 with the change, the build already up to date; load average 12
at the start and 58 at the end, other agents building; log
`tmp/slow5/full.log` in lane-2, not committed): 13,104 results, 12,415
passed, 0 failed, 689 skipped; `** TEST SUCCEEDED ** [132.216 sec]`, 134 s
for the whole command; a serial total of 849 s (1,226 s and 1,301 s in the
two lane-1 runs of 2026-11-21). 28 tests took five seconds or more. 23 are
in the slow tier, among them the owner's two framer tests (30.2 s and
13.4 s), `TmuxDividerMoverPropertyTests/testAnyReachableLayoutRoundTrips`
(18.4 s; 4.8 s alone just after) and git parity tests that run `git`. The
other five had medians under a second in the 21 runs and took 0.14 to 1.13 s
alone straight after (`tmp/slow5/outliers.log`), so the load, not the
tests, put them over: `RemoteGitStateParityTests/testBinaryFileCountsNoLines`
(11.9 s), `iTermGitClientTests/testAheadCountsLocalCommitsNotPushed` (9.1),
`EditKeyActionEncodingTests/testEncodingParameterRoundTripsThroughEditor`
(7.5; 1.13 alone, so a candidate for the slow tier by the one-second rule),
`It2gitParityTests/testCleanRepo` (5.6) and
`RemoteGitStateParityTests/testCleanRepo` (5.4).

So on this evidence no test that takes five seconds or more alone with the
address sanitizer is outside the slow tier, and the only tests over the
10-second ceiling alone are the owner's two. Whether a loaded parallel run
may push a fast-tier test over five seconds is the open question on the
ceiling above.

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
