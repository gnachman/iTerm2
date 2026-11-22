# Thread sanitizer baseline

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

This is the ledger that [concurrency.md §10](concurrency.md) asks for: every
data race the thread sanitizer reports in the existing code when the whole
ModernTests suite runs, with a verdict for each and how the gate treats it.

**What "baseline" means for a port.** The races below are known and judged.
When the thread sanitizer runs for a unit (at the close of any unit whose
dossier shows state shared across threads, and in the periodic full-suite
run), a report that is not in this ledger fails the gate. It is a new race,
and it is the port's until shown otherwise: the author either fixes it or
shows from the source that it exists unchanged in the Objective-C, in which
case it is added here with its verdict, in its own commit. A report that is
in this ledger does not fail the gate, but a port that touches either side
of a ledger entry must re-judge the entry (see each entry's "Re-judge when").

## 1. The run

The latest full-suite run (unit `phase0-test-items`, lane-1, on a machine
loaded by other agents' builds, load average near 100 at the start, so its
times are not quiet-machine times):

| | |
|---|---|
| Date | 2026-11-21 |
| Commands | `tools/swift_migration/sanitizer_tests.sh thread --build-only`; `dsymutil` on the thread build's `iTerm2.debug.dylib`; `tools/swift_migration/sanitizer_tests.sh thread --no-build` (whole suite, serial) |
| Run directory | `tmp/sanitizers/runs/thread-20261121-192129` in lane-1 (not committed) |
| Wall time | build 296 s (incremental), `dsymutil` 18 s, test step 2190 s (36 min 30 s; the log's own test total 2080 s) |
| Tests | 13093 executed: 12402 passed, 2 failed, 689 skipped. `test_timing.py` parses 22 fewer results because test output interleaved with their result lines; each of the 22 has a "passed" line in the log, and the log's own totals (13093, 2 failures) agree |
| Reports | 3 data race reports from one process, 2 distinct races; no lock-order inversion, thread leak or signal-unsafe report |
| Verdict | `Verdict: FAIL: 1 report(s) outside the baseline, 0 unmatchable; 2 accepted.` Exit status 65 (xcodebuild's, for the two failed tests). The report outside the baseline is entry 2.3, added after the run |

The two failures: `RuntimeSnapshotTests.testHeaderRecordsArchitectureAndConfiguration`
(expects the normal build directory; bugs.md) and
`TabLifetimeWitnessTests.testClosedTabIsFreedWithItsSession`, which took
473 seconds and failed, then passed alone in thread mode on the same build
(3.8 s), so it is disabled as flaky (bugs.md, "Flaky test
`TabLifetimeWitnessTests.testClosedTabIsFreedWithItsSession`"). The three
weak-reference tests that failed in the first run passed, which confirms the
fix of unit `phase0-weakref-tests-pool` in thread mode. xcodebuild's
"Failing tests" list also names
`ProfileCommandWrappingTests.testInterpolatedValueIsPartOfTheCommand`,
whose only result line in the log is "passed (48.470 seconds)" and which
has no error line; the log's own count is two failures. Why xcodebuild lists
it was not found.

With `dsymutil` run first, app frames now carry file and line
(`iTermMetalDriver.m:2668`), as section 4 predicted.

The first run, for the record:

| | |
|---|---|
| Date | 2026-11-20 |
| Command | `tools/swift_migration/sanitizer_tests.sh thread` (whole suite, serial) |
| Run directory | `tmp/sanitizers/runs/thread-20261120-022452` (not committed) |
| Wall time | 29 min 53 s (tests 1769 s) |
| Tests | 12325 executed: 11637 passed, 4 failed, 684 skipped, 0 started without a result |
| Reports | 4 data race reports, 2 distinct races; no lock-order inversion, thread leak or signal-unsafe report |
| Summary data | `tmp/sanitizer-collection/thread/` (groups.json, groups_table.txt), produced by `tools/swift_migration/sanitizer_summary.py` |

A count below is a number of reports, with the processes they came from.
The runtime suppresses some repeats of a report within one process, so a
count is not the number of times a race happened.

The four failures are build-environment effects, not sanitizer reports:
`RuntimeSnapshotTests.testHeaderRecordsArchitectureAndConfiguration` (it
expects the normal build directory; see `bugs.md`),
`PromptMarkExcludedSubrangeTests.test_codable_foldRC_deadWeakBox_encodesAsInvalid`,
`ResilientCoordinateTests.test_dict_invalid_shapeMatchesCodable` (both fail
in every sanitizer mode, where the address sanitizer the test plan normally
enables is off and object lifetimes differ), and
`WeakReferenceTests.testTwoWeakReferencesToSameObjectBothNullify` (thread
mode only; the same pattern: an object still alive after its last strong
reference is dropped, since the thread sanitizer instruments Swift
retain and release). None of them is a race report.

## 2. The races

In the first run app frames carried function names but no file and line:
the Development build keeps its debug information in the object files, and
neither the sanitizer's symbolizer nor `atos` found it. The run of
2026-11-21 ran `dsymutil` on the thread build's `iTerm2.debug.dylib` first,
and its reports carry file and line, which agree with the lines below that
were first found by reading the code. Function names are all the baseline
comparison needs (section 3).

### 2.1 Metal completion handler reading its own captures

| | |
|---|---|
| Kind | data race, 8-byte read against 8-byte write |
| Count | 2 reports from one process (serial run), one for each of the first two captures; 9 in the aborted parallel run |
| Tests | none named: no test frame is on either stack (the Metal driver draws asynchronously in whatever test host has a Metal view) |
| Variable | a captured pointer inside a heap-allocated block literal: the block is 56 bytes (32-byte header plus three 8-byte captures) and the two reports' accesses are at offsets 32 and 40, the first two captures |
| Verdict | **false report** |
| Gate | baseline entry 2.1 in `thread-baseline.tsv`, matched by the summary tool (section 3), not by a suppression |

Read, on a Metal completion thread (T231):

```
__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke_2.448
MTLDispatchListApply (Metal)
```

Previous write, on the thread that encoded the frame (T243):

```
__copy_helper_block_e8_32s40s48b
_call_copy_helpers_excp (libsystem_blocks.dylib)
-[iTermMetalFrameData measureTimeForStat:ofBlock:]
-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]
-[iTermMetalDriver enqueueDrawCallsForFrameData:commandBuffer:]
```

Heap block of 56 bytes allocated by T243 in
`-[iTermMetalFrameData measureTimeForStat:ofBlock:]` called from
`-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]`.

Reasoning from the source. `sources/MetalRenderer/iTermMetalDriver.m:2666`
passes a block to `-[MTLCommandBuffer addCompletedHandler:]` inside the
`measureTimeForStat:ofBlock:` block that starts at :2640. That block
captures `frameData`, `self` and `completedBlock`: two strong object
pointers and a block, which is exactly the layout the copy helper's name
encodes (`32s40s48b`: strong objects at offsets 32 and 40, a block at 48).
`addCompletedHandler:` copies the block, and the copy helper writes the
captures into the new heap block on T243. Metal later invokes the block on
its completion thread, which reads the capture at offset 32. Nothing writes
those captures after the copy; they are immutable for the block's life. The
hand-off from the encoding thread to the completion thread happens inside
Metal (`MTLDispatchListApply`), whose synchronization is not instrumented,
so the sanitizer sees a write and a read on two threads with no
happens-before edge between them. This is the Metal false report the owner
described ([concurrency.md §10](concurrency.md)): in the app the sanitizer
flags every Metal frame the same way.

Re-judge when: a port changes what the completed handler captures or
writes, or ports `iTermMetalDriver`. Metal is a hot path
([performance.md §2](performance.md)), so that is late.

Seen accepted on 2026-11-21: the full-suite run of section 1 produced it
(2 reports, accesses at `iTermMetalDriver.m:2668`) and the summary accepted
both as entry 2.1. The same day a targeted run,
`sanitizer_tests.sh thread --no-build ModernTests/TabLifetimeWitnessTests`,
produced it too, so that class is a known test that draws with Metal.

### 2.3 Metal scheduled handler reading its own captures

| | |
|---|---|
| Kind | data race, 8-byte read against 8-byte write |
| Count | 1 report from one process in the full-suite run of 2026-11-21; 1 in the targeted run of `TabLifetimeWitnessTests` the same day. Not seen in the run of 2026-11-20 |
| Tests | none named on either stack; reproduced by `ModernTests/TabLifetimeWitnessTests` run alone in thread mode |
| Variable | a captured pointer inside a heap-allocated block literal: the block is 48 bytes (32-byte header plus two 8-byte captures) and the access is at offset 32, the first capture |
| Verdict | **false report**, the mechanism of entry 2.1 on a sibling block |
| Gate | baseline entry 2.3 in `thread-baseline.tsv` |

Read, on a Metal completion thread (T430):

```
__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke_4 iTermMetalDriver.m:2658
MTLDispatchListApply (Metal)
```

Previous write, on the thread that encoded the frame (T466):

```
__copy_helper_block_e8_32s40b
_call_copy_helpers_excp (libsystem_blocks.dylib)
-[iTermMetalFrameData measureTimeForStat:ofBlock:] iTermMetalFrameData.m:185
-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:] iTermMetalDriver.m:2640
-[iTermMetalDriver enqueueDrawCallsForFrameData:commandBuffer:] iTermMetalDriver.m:1307
```

Heap block of 48 bytes allocated by T466 in
`-[iTermMetalFrameData measureTimeForStat:ofBlock:]` called from
`-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]`. (The
symbolizer files the copy helper under `iTermImageRenderer.m`, and entry
2.1's under `iTermCommandRunner.m`: a copy helper is shared by every block
with the same capture layout, and the linker keeps one copy, from whichever
file it picked. The key uses only the helper's name.)

Reasoning from the source. `ENABLE_STATS` is 1
(`sources/MetalRenderer/Infrastructure/iTermMetalConfig.h:17`), so the
`#if ENABLE_STATS` part of the present-and-commit block that starts at
`iTermMetalDriver.m:2640` is compiled. It makes `scheduledBlock` (copied
with `copy`) and at :2657 passes `-[MTLCommandBuffer addScheduledHandler:]`
the block `^{ dispatch_async(self->_queue, scheduledBlock); }`. That block
captures `self` and `scheduledBlock`: one strong object pointer and one
block, the layout the helper's name encodes (`32s40b`: a strong object at
offset 32, a block at 40), in a 48-byte literal. `addScheduledHandler:`
copies it on the encoding thread, where the copy helper writes the
captures; Metal later invokes it on its own thread through
`MTLDispatchListApply`, and its body at :2658 reads `self` (offset 32) to
get `_queue`. Nothing writes the captures after the copy. The hand-off
happens inside Metal, whose synchronization the sanitizer does not see, so
it reports a write and a read with no happens-before edge. It is the same
false report as 2.1, on the scheduled handler instead of the completed
handler. Why the first run did not report it is not known.

Re-judge when: a port changes what the scheduled handler captures, moves
the stats code, or ports `iTermMetalDriver`.

### 2.2 `VT100Grid.currentDate`: resolved

Resolved by the unit `flag-across-writes-fixture` (kind `test`). The race
was in test fixture code: `FlagAcrossWritesTests` shared one `FakeSession`
between the two screens of a test, so joining the first screen forwarded
`screenRestoreState:` to the second and merged that screen's state while
its own mutation queue ran (`-[VT100Grid setCurrentDate:]` against
`-[VT100Grid currentDate]`). Each screen now has its own `FakeSession`, and
the targeted thread runs no longer report it. No app path existed: each
`PTYSession` is the delegate of exactly one screen. The full analysis is in
the history of this file (`git log --grep 'Swift-Port: flag-across-writes-fixture'`).
It is no longer tolerated anywhere: the same report from any test is a new
race.

## 3. How the gate matches the baseline

No thread sanitizer suppression file is used, and none should be written
for these entries. The gate compares each report with a machine-readable
baseline instead: `thread-baseline.tsv`, beside this file, read by
`tools/swift_migration/sanitizer_summary.py --baseline`.

**Why not a suppression.** Entries 2.1 and 2.3 are the reports the
baseline accepts (2.2 is resolved). The argument below is made for 2.1 and
holds for 2.3 the same way (its write frame, `__copy_helper_block_e8_32s40b`,
is as widely shared). A suppression for it cannot be written soundly
in the sanitizer's syntax, whose patterns are substrings of a frame's
function, file or module name, with only `*`, `^` and `$` as operators:

- The read's top frame is
  `__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke_2.448`.
  The same method also has `_block_invoke_2` (the present-and-commit block
  starting at `iTermMetalDriver.m:2640`) and `_block_invoke_2.450` (the
  main-queue present block, which touches `iTermDrawableAcquisitionHelper`
  state that really is shared across threads); `nm` on the thread build's
  `iTerm2.debug.dylib` lists all three, with `_block_invoke`,
  `_block_invoke.447`, `.449`, `_3` and `_4`. A pattern ending in
  `_block_invoke_2` matches the first three. The `.N` suffixes are the
  compiler's uniquing and change when the file changes, so anchoring on
  `.448$` would match exactly one symbol today and the wrong one, or none,
  after an edit.
- The write's top frame, `__copy_helper_block_e8_32s40s48b`, is shared by
  every block with the same capture layout anywhere in the app.
- `race_top:` (which matches only top frames) does not help: it has the same
  substring problem on either frame.
- Suppressing `MTLDispatchListApply` or the Metal module would hide every
  race in every Metal callback, and a pattern of `Metal` also matches our
  own class names.

**The key.** The summary tool groups every thread report by four parts
(the full definition is in the tool's documentation):

- the kind, from the report's `WARNING:` line;
- the top application frame of the first stack (for a data race, the
  current access);
- the top application frame of the `Previous ...` stack;
- the `Location is` description with addresses and thread numbers removed
  (`heap block of size 56`).

An application frame is one in the app's own images (`iTerm2.debug.dylib`,
`iTerm2`, `ModernTests`, the helper executables, and the in-scope
frameworks shipped prebuilt: `BetterFontPicker`, `ColorPicker`,
`SearchableComboListView`); frames in the
sanitizer runtime, libdispatch, `libsystem_*`, the Objective-C and Swift
runtimes and Apple's frameworks are skipped. A block invoke function's
`.N` uniquing suffix is removed, so a rebuild that renumbers the blocks
still gives the same key. A block copy or dispose helper is shared by every
block with the same capture layout, so for one the key takes the helper and
the next two application frames.

For entry 2.1 that gives:

| Part | Value |
|---|---|
| kind | `data race` |
| access | `__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke_2` |
| previous | `__copy_helper_block_e8_32s40s48b ; -[iTermMetalFrameData measureTimeForStat:ofBlock:] ; -[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]` |
| location | `heap block of size 56` |

With the suffix removed, the access part is shared by the three
`_block_invoke_2` blocks of the method. The other two parts narrow it: a
report matches only if its previous access is a copy, through the helper for
this capture layout, called from `measureTimeForStat:ofBlock:` in
`finishDrawingWithCommandBuffer:frameData:`, and its location is a 56-byte
heap block. A race on state a block reads, such as the
`iTermDrawableAcquisitionHelper` state the main-queue present block touches,
is not an access to a block literal and does not match; nor does a block
with the same capture layout copied anywhere else.

**The comparison.** `sanitizer_tests.sh thread` runs it at the end of every
run. Its output lists the groups outside the baseline and the groups that
cannot be compared (both fail the run), the groups each entry accepted, and
the entries no report matched, then a verdict line. An entry no report
matched is informational: after a full-suite run it means the race no longer
occurs, and the entry is removed from the TSV and from section 2; after a
targeted run it means nothing. The run's exit status is 0 only if the tests
passed and every report is in the baseline. With `--collect` the comparison
is printed and reports never fail the run. First used on 2026-11-20 in
lane-8: `sanitizer_tests.sh thread ModernTests/FlagAcrossWritesTests` ran 27
tests with no report and exited 0 (`Verdict: PASS`); the same mode with
`--probe ModernTests/SanitizerProbeTests` reported the probe's race outside
the baseline and exited 1 (`Verdict: FAIL`). Entry 2.1 was first seen
accepted on 2026-11-21, in the full-suite run of section 1 and in a
targeted run of `ModernTests/TabLifetimeWitnessTests`.

**The gate command** for a unit that needs the thread sanitizer (concurrency.md
section 10): `tools/swift_migration/sanitizer_tests.sh thread TEST ...` for
its targeted tests, and `tools/swift_migration/sanitizer_tests.sh thread`
for the whole suite (serially; run `dsymutil` on the thread build's
`iTerm2.debug.dylib` between `--build-only` and `--no-build` for file and
line). It passes when it exits 0 and its last line is `Verdict: PASS`. On
the full-suite run of 2026-11-21 it exited 65 (two failed tests) with
`Verdict: FAIL` (entry 2.3 was not yet in the baseline); with 2.3 added, the
same reports give `Verdict: PASS` (checked by running
`sanitizer_summary.py` again on that run's reports with the new TSV,
section 5), and the remaining failures are `RuntimeSnapshotTests` (outside
`Build/`, bugs.md) and the test now disabled as flaky.

**Unnamed frames.** A frame the key needs that the runtime printed without a
name (`<null>`) makes the report unmatchable: it is reported as such, with
the frame, and fails, rather than being compared by address. The thread
mode first names such frames with `atos` on its own build directory, the
binaries that just ran (`--symbolize`), and refuses to use `atos` at all if
it gives a different name for any frame the report already names, which is
what a rebuilt binary does.

**Adding an entry.** Judge the race from the source on both sides (section
2), add its section here, and add a line to the TSV with the key as the
summary tool prints it, in the same commit.

If the owner prefers exclusion for Metal ([concurrency.md §10](concurrency.md)
leaves the choice open), the tests that draw with Metal must first be
identified: the report names no test, so that list does not exist yet. One
is known: `TabLifetimeWitnessTests` produces 2.1 and 2.3 when run alone.

## 4. Known limits

- **`--parallel` is not usable in thread mode.** The aborted run
  (`tmp/sanitizers/runs/thread-20261120-020252`) lost two of its ten test
  hosts after about three minutes (one in `FramerFlowTwoHopSimulationTests`,
  one in `StatusPriorityPopoverLayoutTests`) with no crash report and no
  result line; the kernel log shows repeated virtual-memory guard
  exceptions (`EXC_GUARD`, type 5) on the sanitizer hosts just before.
  `xcodebuild` then sat idle with 11944 of 12324 tests run and had to be
  stopped. It reported the same two races. Thread mode runs serially, about
  30 minutes for the suite. Memory peaked near 17.7 GB with ten hosts.
  Nobody has investigated the vanished hosts; it is an owner question
  whether to.
- **Tests that did not run.** 689 tests were skipped in the run of
  2026-11-21, by the same reasons in nearly the same numbers (294 live AI
  harness, 222 Swift on-screen tests plus the Objective-C ones, 40 live ssh,
  37 and 33 tmux workgroup harnesses, 19 shell integration live harness, 6
  `FLAKY-DISABLED`, 3 disabled in the source, 4 sanitizer probes, 2 live
  uv, and single tests with their own skip reasons). In the first run, 684
  were skipped,
  by reason: 294 the live AI harness (opt-in), 243 tests that put windows on
  screen (222 Swift and 21 Objective-C, all gated on `ITERM2_ONSCREEN_TESTS=1`,
  which was not set: the `FloatingPane*` classes,
  `TerminalWindowAutoLayoutFloorTests`, `TabBarVisibilityWindowSizeTests`,
  `PTYTabFloatingPaneModelTests`, `PTYTabContainerTests`,
  `PTYTabTiledSessionsTests`, `SplitPaneStaleTargetTests` and others), 40
  the live ssh harness, 37 the tmux workgroup end-to-end harness, 33 the tmux
  workgroup live harness, 19 the shell integration live harness, 3 skipped
  with the `FLAKY-DISABLED` marker (`bugs.md`), 3 disabled in the source, 4
  sanitizer probes (on only with `--probe`), 2 live uv tests, and 6 others
  each with its own skip reason (timing-dependent or environment-dependent
  tests that skip themselves). Only the ModernTests target ran; no other test target exists in
  the run. The on-screen tests are the main gap: they exercise floating
  panes and window layout with the real view hierarchy.
- **Coverage is thin by nature.** The suite rarely runs the token executor,
  the main thread and the renderer concurrently, and never with real input
  and a real display, so a small baseline is not evidence that the code is
  free of races ([concurrency.md §10](concurrency.md), "Its limit").
  Affinity assertions in nightly builds cover the gap.
- **The sanitizer cannot run in the app.** It falsely flags Metal on every
  frame (the owner's report, and entry 2.1 is one such report reached from a
  test), so there is no app-level baseline and none is planned.
- **File and line in app frames need `dsymutil`.** Without it (the first
  run) app frames carry only function names; with it (the run of
  2026-11-21) they carry file and line. The comparison uses function names
  either way.
- **The collection's reports cannot be symbolized after the fact.** Their
  binaries have been rebuilt. `atos` on the main checkout's thread build as
  it stood later on 2026-11-20 names the copy helper's offset in entry 2.1
  `__45-[iTermCommandRunner didReadData:completion:]_block_invoke`, and the
  summary tool's `--symbolize` refuses that build for those reports.
- **Failing tests** a reader of a gate run must not mistake for
  regressions: `RuntimeSnapshotTests` fails in any build outside `Build/`
  (bugs.md), so a full thread-mode run never exits 0 until that is fixed;
  judge it by its verdict line and its list of failures. The three
  weak-reference tests that failed in the first run passed in the run of
  2026-11-21 (unit `phase0-weakref-tests-pool` fixed them).

## 5. Regenerating

1. Run `tools/swift_migration/sanitizer_tests.sh thread` serially (a
   build-lane job; never `--parallel`, section 4). Run `dsymutil` on the
   thread build's `iTerm2.debug.dylib` first so app frames carry file and
   line.
2. The run's summary (`summary.txt` in the run directory) groups the
   races by the key of section 3 and compares them with `thread-baseline.tsv`.
   To see every report without failing the run, pass `--collect`. To
   summarize again by hand: `tools/swift_migration/sanitizer_summary.py
   REPORTS_DIR --test-log TEST_LOG --baseline docs/swift-migration/thread-baseline.tsv`
   (add `--json` for machine-readable output).
3. A group outside the baseline is a new race and is judged from the source
   on both sides before it is added (section 3, "Adding an entry"); an entry
   the run did not see is deleted from the TSV and from section 2, with the
   reason in the commit message.
4. Recount the skipped tests by reason from the run's test log for section 4.
