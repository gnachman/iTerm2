# Bugs found and preserved

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

Bugs found during the migration and deliberately left as they are, so that a
port reproduces them and a fix happens in its own commit. Also existing
problems that affect the gate. An entry is removed when the bug is fixed.

Each entry has the file and method, a description, how to reproduce it, and
what the migration does about it in the meantime.

## Disabled flaky tests

Each test below is flaky by the definition in
[test-speed.md §3](test-speed.md) and is disabled by a first statement of
`try XCTSkipIf(true, "FLAKY-DISABLED: <date>, see docs/swift-migration/bugs.md")`,
with the date it was disabled.
It still appears in the test log, as skipped. To find every disabled test,
search `ModernTests` for `FLAKY-DISABLED`. To re-enable one, delete that line
(and the `throws` added to its signature, if nothing else in it throws), then
remove its entry here. The owner has been told (owner queue Q9) and has
another agent debug each one. Which assertion failed was not recorded in any
of the occurrences below, because a parallel run names a failing test but not
its assertion.

### Flaky test `AsyncFilterTemporaryLineTests.testOnCompleteCallback`

- **Where:** `ModernTests/AsyncFilterTests.swift`, class
  `AsyncFilterTemporaryLineTests`, `testOnCompleteCallback`. Not the test of
  the same name in `AsyncFilterIntegrationTests`, which is still enabled.
- **What:** failed once, on 2026-11-18, in a full
  `tools/run_tests.expect -parallel` run, together with
  `PTYSessionEndedMessageTests.testShortOutputMovesToTheBottomOfTheScreen`.
  It passed when run alone, and a second full parallel run passed. The cause
  is unknown; that it depends on timing under load is a guess. Nobody has
  reproduced the failure with the test run alone.
- **Reproduce:** not reliably. Full parallel runs on 2026-11-19 passed.
- **Meanwhile:** disabled on 2026-11-19 with the `FLAKY-DISABLED` marker.
- **Found:** 2026-11-18.

### Flaky test `AsyncFilterStateMachineTests.testStateTransitionsWithPendingDeliveries`

- **Where:** `ModernTests/AsyncFilterTests.swift`, class
  `AsyncFilterStateMachineTests`, `testStateTransitionsWithPendingDeliveries`.
- **What:** failed once, on 2026-11-18, in a full
  `tools/run_tests.expect -parallel` run, together with
  `PTYSessionEndedMessageTests.testShortOutputMovesToTheBottomOfTheScreen`.
  It passed when run alone. The cause is unknown; that it depends on timing
  under load is a guess. Nobody has reproduced the failure with the test run
  alone.
- **Reproduce:** not reliably. Full parallel runs on 2026-11-19 passed.
- **Meanwhile:** disabled on 2026-11-19 with the `FLAKY-DISABLED` marker.
- **Found:** 2026-11-18.

### Flaky test `PTYSessionEndedMessageTests.testShortOutputMovesToTheBottomOfTheScreen`

- **Where:** `ModernTests/PTYSessionEndActionTests.swift`, class
  `PTYSessionEndedMessageTests`, `testShortOutputMovesToTheBottomOfTheScreen`.
- **What:** failed twice, both on 2026-11-18, in full
  `tools/run_tests.expect -parallel` runs: once together with
  `AsyncFilterTemporaryLineTests.testOnCompleteCallback`, and once together
  with `AsyncFilterStateMachineTests.testStateTransitionsWithPendingDeliveries`.
  It passed when run alone each time. The cause is unknown; that it depends
  on timing under load is a guess. Nobody has reproduced the failure with the
  test run alone.
- **Reproduce:** not reliably. Full parallel runs on 2026-11-19 passed.
- **Meanwhile:** disabled on 2026-11-19 with the `FLAKY-DISABLED` marker.
- **Found:** 2026-11-18.

### Flaky tests `CompanionBrowserInputTests.testInputReachesPageInWindowThatIsNotKey` and `testInputReachesPageWithNoWindow`

- **Where:** `ModernTests/CompanionBrowserInputTests.swift`, both tests
  call `exercise(inWindow:)`.
- **What:** both failed on 2026-11-20 in one full
  `tools/run_tests.expect -parallel` run (log `tmp/full-slow-review.log`),
  each after about 15 seconds, while another process was compiling. Run
  alone on the same commit, all 14 tests of the class passed. Three other
  full runs the same night passed them. Belief, not verified: the tests
  wait in real time, with a 15 second limit, for a web view to load a page
  and report a caret position, and under load the page did not get there
  in time.
- **Reproduce:** not reliably.
- **Meanwhile:** both disabled on 2026-11-20 with the `FLAKY-DISABLED`
  marker.
- **Found:** 2026-11-20.

### Flaky test `AIPluginClientLifetimeTests.testCancelledRequestFreesItsObjects`

- **Where:** `ModernTests/AIPluginClientConcurrentCancelTests.swift`, class
  `AIPluginClientLifetimeTests`, `testCancelledRequestFreesItsObjects`.
- **What:** failed once, on 2026-11-20, in one of two full
  `tools/run_tests.expect -parallel` runs on the same commit (log
  `tmp/full-binding-review.log`); the other run passed. The failing run
  took 21.2 seconds against about 1.1 seconds normally. The log names the
  test twice under "Failing tests" but, being a parallel run, carries no
  assertion text, and its result bundle no longer exists. Run alone three
  times on 2026-11-20, the class passed each time, this test taking 1.07,
  1.07 and 1.06 seconds. Belief, not verified: the test has two real-time
  waits of 10 seconds each, one for the URL protocol to see the transfer
  stop and the completion to run after `cancel()`, and one
  (`assertEverythingFreed`) polling for the client, JS context, delegate
  and token to be freed. 21 seconds is both timing out, which suggests
  that under load the cancellation did not reach the URL protocol and the
  completion within 10 seconds, so the objects the in-flight request holds
  were still alive at the second wait and its assertions failed too.
- **Reproduce:** not reliably. It passed in the other full parallel run and
  in three solo runs.
- **Meanwhile:** disabled on 2026-11-20 with the `FLAKY-DISABLED` marker.
- **Found:** 2026-11-20.

### Flaky test `TabLifetimeWitnessTests.testClosedTabIsFreedWithItsSession`

- **Where:** `ModernTests/LifetimeWitnessTests.swift`, class
  `TabLifetimeWitnessTests`, `testClosedTabIsFreedWithItsSession`.
- **What:** failed once, on 2026-11-21, in a full serial thread sanitizer
  run (`tools/swift_migration/sanitizer_tests.sh thread`, unit
  `phase0-test-items`, lane-1, on a heavily loaded machine), after 473
  seconds: `XCTAssertEqual failed: ("["session", "session.screen",
  "session.textview", "session.terminal", "session.tokenExecutor"]") is not
  equal to ("[]") - A closed tab and its session must be freed`
  (line 573, `assertAllFreed`). Run alone in thread mode on the same build
  minutes later, the class passed (this test 3.8 s). It passed in the
  address sanitizer full parallel runs before (3.25 s in lane-1's gate run
  of the same day). What the log shows during the 473 seconds, unexplained:
  the test process had 25 `PseudoTerminal`s alive (windows left by earlier
  test classes, presumably), and `kRefreshTerminalNotification` was posted
  about 450 times, each time refitting all 25 windows (11,250
  `refreshTerminal: trigger=kRefreshTerminalNotification` lines, with
  `tabBarShouldBeAccessory` alternating between YES and NO) over about 450
  seconds. Belief, not verified: that kept the main thread busy, and the
  30-second deadline of `LifetimeWitnessSupport.spin(until:)`, which is
  checked only between run loop passes, could not end the wait sooner. Who
  posted the notification so often was not found. The
  run's log is `tmp/sanitizers/runs/thread-20261121-192129/test.log` in
  lane-1 (not committed), lines 253461 to 718293.
  The review read the same log: this looks like a refresh feedback loop
  that starves the main thread, not random flakiness and not a leak in
  closing a tab (the tab was freed; only the session, waiting on the main
  thread, survived). The refresh rate was steady for the whole 473 seconds,
  so one run loop pass probably lasted about 440 seconds, which points to
  a nested run loop or a re-entrant posting loop. Prime suspect, not
  proven: `+[iTermPreferences setHideTabBarSuppressedDuringDrag:]`
  (`iTermPreferences.m`), which posts a refresh on every change and is
  driven by the tab drag begin and end notifications through
  `-[PseudoTerminal draggingDidBeginOrEnd:]`; the class that ran just
  before was `TabGroupSubgroupDragOutTests`, a tab drag class. Running
  those two classes together in the address sanitizer build did not
  reproduce it (0.46 s). The storm belongs to this test: its two siblings
  ran right after with the same 24 leftover windows and passed. Separate
  defect: some earlier test classes leave 24 windows open, and no witness
  catches that.
- **Reproduce:** not reliably; it passed alone. Perhaps a full serial
  thread-mode run, where earlier classes leave windows open.
- **Owner's explanation (2026-11-21):** running the full suite sometimes
  uses up all of memory, and then everything gets very slow. He attributes
  the 473 seconds of the full serial thread sanitizer run to that; memory
  pressure was not recorded during the run. The refresh storm is not
  investigated further.
- **Resolved (2026-11-21, re-enabled):** disabled earlier that day with the
  `FLAKY-DISABLED` marker, then, as the owner asked, run by itself: the
  class `TabLifetimeWitnessTests` passed five times in a row in the normal
  build (`tools/run_tests.expect ModernTests/TabLifetimeWitnessTests`, this
  test 0.35 s each time) and once alone under the thread sanitizer
  (`tools/swift_migration/sanitizer_tests.sh thread
  ModernTests/TabLifetimeWitnessTests`, 3 of 3 passed, verdict PASS), all
  in lane-1. The skip is removed. If it fails again in a full run, record
  the machine's memory pressure at the time (for example `memory_pressure`
  or Activity Monitor's memory pressure graph, and the swap in use) before
  disabling it.
- **Found:** 2026-11-21.

## `@synchronized` sites whose lock can be nil

Found by the Phase 0 nil-lock audit ([concurrency.md §2](concurrency.md)).
That audit put `ITNonnilLock` (`DebugLogging.h`) on every site that locks on an
ivar or on the result of a call; none of those can be nil. The sites below lock
on a local or a global, which section 2 does not ask the audit to assert, so
they have no assertion yet. The port of each one asserts as section 2 requires.

### `helper` in `+[iTermAPIHelper debugStartInProcessOnlyServer]`

- **Where:** `sources/API/iTermAPIHelper.m`,
  `+debugStartInProcessOnlyServer`, both `@synchronized (helper)` blocks.
  Compiled only in `DEBUG` builds.
- **What:** `helper` is `[self sharedInstance]`, which returns nil when the
  API server is disabled in settings, the process is not running unit tests,
  and the user declines the prompt in `-initWithExplicitUserAction:`. The
  first block would then lock nothing and dereference `helper->_apiServer`
  through a nil pointer, which crashes; the nil lock is the lesser problem.
- **Reproduce:** not reachable today. The only caller is
  `ModernTests/SSHIntegrationLiveHarness.swift`, which runs in the test host,
  where `-initWithExplicitUserAction:` skips the prompt and never returns nil.
- **Meanwhile:** left as it is, with no assertion (a local, outside the
  audit's scope). The port asserts the lock is non-nil per section 2.
- **Found:** 2026-11-19.

### `gThreads` in `+[iTermThread currentThread]`

- **Where:** `sources/Infrastructure/iTermThreadSafety.m`, `+currentThread`,
  `@synchronized (gThreads)`. Compiled only when `CHECK_DOUBLE_INVOKES`, which
  is `BETA`.
- **What:** `gThreads` is a global assigned under `dispatch_once` in the first
  `-[iTermThread initWithQueue:stateFactory:]`. Until some `iTermThread` has
  been initialized it is nil. `+currentThread` is called from
  `-[iTermThread dispatchAsync:]` (an `iTermThread` exists, so not nil there)
  and from `-[iTermCallback invokeWithObject:]`, whose callback may have been
  created with `+onThread:block:` and a nil thread. In that case, with no
  `iTermThread` yet created, the block runs with no lock. It only iterates the
  nil array and returns nil, so nothing goes wrong beyond the missing lock.
- **Reproduce:** not observed. `+[iTermThread main]` and the other threads are
  created early in the app's life, so in practice `gThreads` is set before any
  callback is invoked.
- **Meanwhile:** left as it is, with no assertion (a global, outside the
  audit's scope). The port asserts the lock is non-nil per section 2.
- **Found:** 2026-11-19.

## `StatusPriorityPopoverLayoutTests` is slow under load

- **Where:** `ModernTests`, class `StatusPriorityPopoverLayoutTests`.
- **What:** slow, not flaky: it has never failed. On 2026-11-18, with the
  machine heavily loaded by other builds, the stall detector killed a full
  parallel run inside it; it passed alone in 192 seconds. Its tests took 39
  to 49 seconds each in one loaded run. In a full parallel run on 2026-11-19,
  five of its seven tests took 44 to 50 seconds each.
- **Meanwhile:** stays enabled. It is to be fixed as a slow test
  ([test-speed.md §2](test-speed.md)).
- **Found:** 2026-11-18.

## nil reaches non-optional Swift parameters from Objective-C (pending per site)
- **Where:** switchToTmuxPoller(tmuxController:) (PTYSession.m:10884),
  metalView(_:drawableSizeWillChange:) (SessionView.m:1471),
  VT100SavedColorsSlot init (iTermColorMap.m:796-799), the titlebar accessory
  nanny has(_:) (PseudoTerminal.m:7345); bridged-value cases listed in
  nullability/classification.txt.
- **What:** undefined behavior for class types; a silent empty value for String,
  Array, Dictionary and Data.
- **Meanwhile:** each Swift signature becomes optional with a guard, or the caller
  is fixed, decided per site.
- **Found:** 2026-11-20, nullability collection.

## `MarkCache.copy(with:)` is not `-copyWithZone:`

- **Where:** `sources/DataStructuresAlgorithms/MarkCache.swift`, the method `copy(with:)`.
- **What:** the class does not adopt `NSCopying`, so the method's selector is
  `copyWith:`, not `copyWithZone:` (the compiler's USR confirms it). Swift
  callers that write `copy(with: nil)` reach it; Objective-C code that sends
  `-copy` or `-copyWithZone:` to a `MarkCache` would not.
- **Reproduce:** not observed; found by reading the code database's Swift
  declarations.
- **Meanwhile:** preserved.
- **Found:** 2026-11-20, by the code database's Swift side.

## `RuntimeSnapshotTests` expects the normal test build directory

- **Where:** `ModernTests`,
  `RuntimeSnapshotTests.testHeaderRecordsArchitectureAndConfiguration`.
- **What:** fails in the builds of `tools/swift_migration/sanitizer_tests.sh`,
  which build into `tmp/sanitizers/<mode>/`, because it expects the normal
  build directory. A limit of the test, not of the app.
- **Reproduce:** `tools/swift_migration/sanitizer_tests.sh plain` with the
  test's name.
- **Meanwhile:** enabled; expect it in the failures of those runs.
- **Found:** 2026-11-20, by the whole-suite sanitizer runs.

## `iTerm2.sdef` names properties that nothing implements

- **Where:** `iTerm2.sdef`. Class window: `position`, `origin`, `size`,
  `frame` (cocoa keys `scriptPosition`, `scriptOrigin`, `scriptSize`,
  `scriptFrame`), added in 2a55712c1 (2015). Class session:
  `use underline color` (cocoa key `useUnderlineColor`), added in f7772b24c.
- **What:** no class implements any of these keys. Eleven more properties
  are read-write in the dictionary but have no setter: application
  `currentScriptingWindow`; window `scriptFrontmost`, `currentTab`,
  `currentSession`, `isHotkeyWindow`, `hotkeyWindowProfile`; tab
  `indexOfTab`, `title`; session `isProcessing`, `isAtShellPrompt`, `text`.
- **Reproduce:** `tell application "iTerm2" to get position of window 1`
  should fail with an unknown-key error (not run). Pinned by
  `BindingTests.testScriptingDefinition` and its known-failures table.
- **Meanwhile:** preserved. A port keeps exactly the accessors that exist.
- **Found:** 2026-11-20, by the binding tests.

## Dead outlet in `SearchableComboView.xib`

- **Where:** `SearchableComboListView/SearchableComboView/SearchableComboView.xib`,
  the Content View's `tableView` outlet.
- **What:** `SearchableComboContentView` has no such property (dead since
  817462d8d, 2021). AppKit logs "Failed to connect (tableView) outlet" on
  every load of the searchable combo popup. The xib's File's Owner also
  names module `iTerm2SharedARC` for a class that is compiled into
  `SearchableComboListView`; that is harmless at run time.
- **Reproduce:** open any searchable combo popup and read the log.
- **Meanwhile:** preserved; listed in the binding tests' known failures.
- **Found:** 2026-11-20, by the binding tests.

## Assignment where a comparison was meant in `iTermWebSocketFrame`

- **Where:** `sources/API/iTermWebSocketFrame.m`, `-closeFrameCode` (line
  241) and `-closeFrameReason` (line 251).
- **What:** each begins with
  `ITAssertWithMessage(self.opcode = iTermWebSocketOpcodeConnectionClose, @"Not a close frame")`.
  That is an assignment. Each call sets the frame's opcode to
  ConnectionClose through `setOpcode:`, and the condition is always
  nonzero, so the assertion can never fire: calling either method on a
  frame that is not a close frame silently turns it into one. The object
  file confirms it (the assertion's failure branch is not emitted). No
  caller exists outside the file today.
- **Reproduce:** read the two lines; or call `closeFrameCode` on a text
  frame and read its `opcode` afterwards.
- **Meanwhile:** preserved. A port keeps the assignment until a `fix`
  commit, test first, makes it a comparison.
- **Found:** 2026-11-20, by the object-file cross-check.

## Integer truncated into `BOOL` on Intel: the fn key state is always NO

- **Where:** `sources/AppKit/iTermApplication.m:721`,
  `_functionPressed = event.modifierFlags & NSEventModifierFlagFunction;`.
- **What:** on x86_64 `BOOL` is `signed char`, and the flag is bit 23, so
  the conversion keeps only the low byte and the result is always NO. On
  arm64 `BOOL` is `bool` and the result is right. The generated code
  confirms it (x86_64: `xorl %eax,%eax; retq`). So on Intel Macs
  `it_functionModifierPreviouslyPressed`, which `iTermModernKeyMapper`
  uses, is wrong for the fn key.
- **Reproduce:** not run on Intel hardware. Compile
  `BOOL f(unsigned long x){ return x & (1UL<<23); }` for
  `x86_64-apple-macos13.0` and read the assembly, or run
  `tools/swift_migration/warning_survey.py compare --mode strict`.
- **Meanwhile:** preserved. A `fix` commit, test first, writes
  `(flags & NSEventModifierFlagFunction) != 0`.
- **Found:** 2026-11-20, by the warning survey.

## Other integer or float values stored into `BOOL`

- **Where:** `sources/.../iTermFileDescriptorMultiClientChild.m:128`
  (`-terminationStatus` copies an `int` wait status into a `__block BOOL`:
  wrong on both architectures, since a status of 256 becomes 0 on Intel
  and any nonzero status becomes 1 on arm64; the getter has no caller
  today); `iTermApplicationDelegate.m:602` (an `NSInteger` count returned
  as `BOOL`: wrong on Intel only at multiples of 256);
  `PTYSession.m:6811` (a float preference passed as `BOOL`: 0.5 is YES on
  arm64 and NO on Intel; the stored value is 0 or 1 in practice).
- **What:** as above. Eleven further sites the survey flags are correct on
  both architectures because the value is 0 or 1 by construction.
- **Meanwhile:** preserved; each is fixed in Objective-C before its file is
  ported, since `-Wobjc-signed-char-bool` is in the strict set.
- **Found:** 2026-11-20, by the warning survey.

## `iTermProfilePreferenceObserver.value(_:)` traps when its profile is missing

- **Where:** `sources/Settings/iTermProfilePreferenceObserver.swift`, the five
  `value(_:)` overloads (`[[AnyHashable: Any]]?`, `[String]?`, `String?`,
  `Double`, `Bool`), through the private `observedProfile`.
- **What:** each accessor reads `model.bookmark(withGuid: guid)`. When the
  model has no profile with that GUID, the process crashes. Until unit N1 of
  `nullability-triage.md` this was an implicit unwrap: the result of
  `bookmark(withGuid:)` (implicitly unwrapped, since `ProfileModel.h` is not
  annotated) went to the `profile` parameter of
  `+[iTermProfilePreferences ...ForKey:inProfile:]`, which was nonnull. The
  same class's `value(for:)`, used by the observation closures, tolerates a
  missing profile with `?? [:]`, and the Objective-C methods tolerate a nil
  profile (they read the defaults). So the crash is probably not intended. The
  browser (`iTermBrowserManager`, `iTermBrowserViewController`,
  `iTermBrowserExtensionManager`) reads these accessors for a session's
  profile GUID in `ProfileModel.sharedInstance()` or `sessionsInstance()`.
- **Reproduce:** not reproduced. It would need a browser session whose
  profile GUID is gone from the model it observes when one of the accessors
  runs.
- **Meanwhile:** preserved, now as an explicit `it_fatalError` naming the
  GUID. A `fix` commit, test first, can pass the optional through, so the
  accessors read the defaults the way `value(for:)` does.
- **Found:** 2026-11-20, unit `nullability-n1-profile-preferences`.

## ICH, DCH, DECIC and DECDC with a huge count pass a size near 2^64 to memmove

The most serious of the integer findings of 2026-11-20: memory corruption
or a crash from program output.

- **Where:** `sources/VT100/VT100Grid.m`,
  `-insertChar:externalAttributes:at:times:` (line 2698,
  `n + pos.x > self.rightMargin`; `charsToMove` at :2708; the `memmove` at
  :2726) and `-deleteChars:startingAt:` (line 1945,
  `n + startCoord.x > rightMargin`; line 1952, `startCoord.x + n <= rightMargin`;
  the `memmove` at :1987). Reached by ICH (`CSI n @`,
  `-terminalInsertEmptyCharsAtCursor:`), DCH (`CSI n P`,
  `-terminalDeleteCharactersAtCursor:`), DECIC (`CSI n ' }`,
  `-[VT100ScreenMutableState insertColumns:]`, once per row of the scroll
  region) and DECDC (`CSI n ' ~`, `-deleteColumns:`, likewise); and by SL
  and SR (`-[VT100Grid moveContentLeft:]`, `-moveContentRight:`), which
  start at column 0 or the left margin, so only with a left margin at
  column 9 or more.
- **What:** the CSI parser stores counts up to 2147483639. With the cursor
  at column 9 (x = 9) or later, `n + x` overflows `int` and wraps negative,
  so the clamp to the margin does not happen and n keeps its huge value.
  Then `charsToMove = rightMargin - x - n + 1` is about -2^31, and
  `charsToMove * sizeof(screen_char_t)` converts it to `size_t`: memmove
  gets a size near 2^64 (18446744047939748800 for x = 9), and a pointer
  2^31 cells past the line. DCH also passes its second test
  (`x + n <= rightMargin`, which wraps the same way) and does the same.
  memmove with that size reads and writes far outside the buffer: a crash
  at best, memory corruption at worst. On double-width lines ICH and DCH
  first double n, which wraps to a small negative number for counts over
  1073741823, so they do nothing there instead.
- **Reproduce:** by reading and a C copy of the arithmetic; not run against
  the real code. The copy (`ichdch.c`, the two functions' arithmetic with
  memmove replaced by printing its arguments, written during the unit in
  the lane's scratch directory) gives, at `-O0` and `-Os` on arm64:
  x = 4 and x = 8 clamp correctly (n = 76 and 72, nothing moved); x = 9
  gives n = 2147483639, `charsToMove` = -2147483568 and a memmove size of
  18446744047939748800, for both functions. Under the integer sanitizer the
  copy reports `signed integer overflow: 2147483639 + 9` at both sums. In a
  terminal: `printf '\e[1;10H\e[2147483639@'` (do not run it in a session
  you care about).
- **Meanwhile:** being fixed by the unit `integer-findings-fixes-2`, test
  first. Until that lands, `ModernTests/StressStreamReplayTests.swift`
  sends huge ICH and DCH counts only at column 5 (x = 4) and sends no huge
  DECIC or DECDC.
- **Found:** 2026-11-20, review of unit `phase0-integer-discovery-2`.

## Cursor movement by a huge count overflows `int` and lands at the wrong edge

- **Where:** `sources/VT100/VT100Grid.m`, `-moveCursorDown:` (line 1203,
  `cursor_.y + n`) and `-moveCursorRight:` (line 1179,
  `cursor_.x + n * step`); `-moveCursorLeft:` (lines 1132 and 1169,
  `cursor_.x - n * step`) on double-width lines only; and
  `-[VT100ScreenMutableState eraseCharactersAfterCursor:]`
  (`VT100ScreenMutableState.m`, `j *= 2` and `cursorX + j`, lines 2016 to
  2037).
- **What:** the CSI parser stores parameters up to 2147483639. The sums
  overflow `int` and, in practice, wrap to a negative number. Then:
  - **CUD** (`CSI n B`, also CNL `CSI n E`) with the cursor on row 9 or
    lower and n = 2147483639: `MAX(0, MIN(height - 1, y + n))` gives 0, so
    the cursor goes to the top row (above any scroll region's top margin)
    instead of to the bottom margin. Seen in the integer sanitizer run
    (`23 + 2147483639`, integer-findings.md section 7).
  - **CUF** (`CSI n C`) with the cursor in column 9 or later, or any huge n
    on a double-width line (`n * 2` overflows): the negative x is clamped by
    `-setCursorX:` to 0, so the cursor goes to column 0 instead of the right
    margin. By reading; the run did not reach it.
  - **CUB** (`CSI n D`) on a double-width line: `n * 2` wraps, so the
    "left" move computes an x to the right of the cursor; with a column
    scroll region the cursor moves right, and without one the loop's `n`
    grows instead of shrinking until it wraps. By reading; the effect was
    not run.
  - **ECH** (`CSI n X`) with the cursor in column 9 or later and a huge n,
    or on a double-width line: the limit wraps negative and nothing is
    erased instead of the rest of the line. By reading.
  - **CUU** (`CSI n A`, `cursor_.y - n`) cannot overflow: y is at least 0
    and n at most 2147483639. Not affected.
- **Reproduce:** `printf '\e[24;1H\e[2147483639Bx'` prints the x on the top
  row. `ModernTests/StressStreamReplayTests.testCursorMovementWithHugeCounts`
  under `tools/swift_migration/sanitizer_tests.sh integer-sign` reports the
  overflow at `VT100Grid.m:1203`.
- **Meanwhile:** preserved. A `fix` commit, test first, computes each sum in
  `NSInteger` (or clamps n to the grid size first). A port must not use the
  asserting helpers on the unfixed code: they would fire on these inputs in
  tests.
- **Found:** 2026-11-20, unit `phase0-integer-discovery-2`.

## CHT and CBT loop once per count, so a huge count freezes the app

- **Where:** `sources/VT100/VT100Terminal.m`, `case VT100CSI_CHT:` (line
  2131, `for (int i = 0; i < token.csi->p[0]; i++)` calling
  `terminalAppendTabAtCursor:`), and
  `-[VT100ScreenMutableState backTab:]` (`VT100ScreenMutableState.m:3105`),
  reached from `case ANSICSI_CBT:` (`VT100Terminal.m:2753`).
- **What:** `CSI n I` and `CSI n Z` run their loop n times, and n can be
  2147483639. Once the cursor reaches the last tab stop (or column 0 for
  CBT) every further pass does nothing, but the loop keeps going. REP is
  capped at 65535 (`VT100Terminal.m:2625`); these are not.
  - The loop runs inside one token, on the session's mutation queue, not on
    the main thread.
  - The main thread's next join with that session
    (`-[TokenExecutor whilePaused:onExecutorQueue:]`, TokenExecutor.swift:707,
    used for redraws and input) waits on a semaphore with no timeout until
    the queue reaches the join, which happens only between tokens. So the
    whole app's UI freezes until the loop ends, not just the session. With
    Maximize Throughput on (the shared queue), every session stops as well.
    This is by reading the join code; the freeze was not observed in the
    app.
  - Measured in the Development test build with the address sanitizer
    (`tools/run_tests.expect`, a temporary test, 100,000 and 400,000
    counts): CHT about 150 ns per count with the cursor already at the last
    tab stop, CBT about 14 ns per count with the cursor at column 0. So
    `CSI 2147483639 I` holds the queue for about 320 seconds and
    `CSI 2147483639 Z` for about 30 seconds in that build. A Deployment
    build is faster; it was not measured.
  - With the advanced setting `tabsWrapAround` on, each CHT pass at the
    right margin wraps to the next line and may scroll, so it is far slower
    per count and adds lines to the scrollback. Not measured.
  - In Development builds (and in ModernTests) the execution permits health
    check calls `crashInDebugBuilds` once a holder is silent for 5 seconds,
    so they crash instead of freezing (seen in the test host).
    `crashInDebugBuilds` is under `#if ITERM_DEBUG`
    (`ExecutionPermits.swift:267-271`), which Swift gets only in
    iTerm2SharedARC's Development configuration; Beta, Nightly and
    Deployment builds log and freeze.
- **Reproduce:** `printf '\e[2147483639I'` in a session. In the test host:
  the CHT and CBT huge counts that
  `ModernTests/StressStreamReplayTests.swift` leaves out
  (`countIsSafeForTabLoops`).
- **Meanwhile:** preserved. A `fix` commit, test first, caps the count (for
  example at the screen width, since no tab move can go farther). Until
  then `StressStreamReplayTests` sends CHT and CBT only counts up to 65536.
- **Found:** 2026-11-20, unit `phase0-integer-discovery-2`.

## Execution permits health check wraps an unsigned difference and crashes Development builds

- **Where:** `sources/VT100/ExecutionPermits.swift`, `checkHealth()` (line
  715 to 720, `now &- last`), with `checkpointIsNeeded(_:)` (line 380) as the
  writer; `Client.description(now:)` (line 96) has the same subtraction.
- **What:** `checkHealth()` reads `now` under the mutex and then each
  running holder's `lastHeardFrom`. `checkpointIsNeeded(_:)` stores
  `lastHeardFrom` without the mutex, from the session's queue. If a holder
  checkpoints between the two reads, `last` is later than `now`, and
  `now &- last` wraps to nearly 2^64 nanoseconds. That exceeds
  `silentHolderThreshold` (5 seconds), so the check reports a lost wakeup
  and calls `crashInDebugBuilds`. That function crashes only under
  `#if ITERM_DEBUG` (`ExecutionPermits.swift:267-271`), which Swift gets
  only in iTerm2SharedARC's Development configuration: Development builds
  and ModernTests crash with "woke a holder not heard from for
  18446744073.7s"; Beta, Nightly and Deployment builds log an RLog message
  and wake a holder that is already running. A holder that checkpoints
  often (a long run of tokens, such as REP at its cap) makes the race more
  likely.
- **Reproduce:** seen once, on 2026-11-20, in
  `StressStreamReplayTests.testRepeatPreviousCharacterAtItsCap` under
  `tools/run_tests.expect`; the test passed on the next two runs. Not
  reproducible on demand.
- **Meanwhile:** preserved. A `fix` commit, test first (with the injected
  `now` clock the initializer takes), treats `last > now` as just heard
  from. Until then, any test that executes tokens can rarely crash this
  way; this is the cause to look for when a test host dies with that
  message.
- **Found:** 2026-11-20, unit `phase0-integer-discovery-2`.

## Inline images in a session without a screen get an infinite size

- **Where:** `sources/InlineImages/VT100InlineImageHelper.m`,
  `-scaledSizeForDecodedImage:` (line 320, dividing by `_scaleFactor`) and
  the conversions at :353 and :388 (`ceil(scaledSize / cellSize)` to
  `int`); the scale factor comes from `config.backingScaleFactor`
  (`VT100ScreenMutableState+TerminalDelegate.m:3313` for sixel; :3250 and
  `VT100ScreenMutableState.m:7897` pass the same value to the other
  helpers), which `-[PTYSession updateConfigurationFields]` copies from
  `_view.window.screen.backingScaleFactor` (`PTYSession.m:20460`).
- **What:** that value is 0 when the session's view has no window or the
  window has no screen; a session in a tab that is not selected is the
  likely case. The scaled image size is then infinite, and converting
  `ceil(inf / cellSize)` to `int` is undefined: arm64 gives `INT_MAX`,
  x86_64 gives `INT_MIN`. By reading the clamping that follows
  (`:438` to `:461`): on arm64 the width becomes the grid width and the
  height about the same number of rows as the width available, whatever
  the image's shape; on x86_64 `MAX(1, ...)` makes it one cell by one
  cell. Either way the image is sized wrongly; nothing hangs. Other code
  already guards the same value (`PTYSession.m:23574`, `:10399` with
  `?: 1`; `VT100ScreenMutableState.m:9269` with `MAX(1.0, ...)`).
- **Reproduce:** app-reachable by reading; not verified in the app. In the
  test host, `StressStreamReplayTests.testSixel` under
  `tools/swift_migration/sanitizer_tests.sh integer-sign` reports
  float-cast overflow at both lines, because the test harness's
  configuration leaves the backing scale factor 0.
- **Meanwhile:** preserved. A `fix` commit, test first, treats a zero or
  non-finite scale factor as 1, as the other sites do. A port must not
  convert with `it_floatToInteger` before that fix: it would assert in
  `testSixel`.
- **Found:** 2026-11-20, unit `phase0-integer-discovery-2` and its review.

## Assigning a profile to a broken arrangement with no name raises

- **Where:** `-[PTYSession setProfileInArrangement:withGUID:toProfile:]`
  (`PTYSession.m`), reached from
  `-[iTermNaggingController offerToFixSessionWithBrokenArrangementProfileIn:guid:]`
  through `-naggingControllerAssignProfileToSession:guid:`,
  `-changeProfileInArrangementNamed:guid:completion:` and
  `-reallyChangeProfileInArrangement:guid:profiles:completion:`.
- **What:** the offer is made from the restore path in `PTYSession.m`
  (`missingProfile`, a saved profile without a name or GUID) with the
  arrangement's name, which is nil when the session was not restored from a
  named arrangement. If the user accepts and picks a profile,
  `+[WindowArrangements arrangementWithName:nil]` returns the default
  arrangement, and `+[WindowArrangements setArrangement:withName:nil]` then
  calls `-[NSMutableDictionary setObject:forKey:]` with a nil key, which
  raises `NSInvalidArgumentException` outside its `@try`. The triage reason
  for `iTermNaggingController.h:120` said a nil name gives no arrangements;
  it does not.
- **Reproduce:** not reproduced. It needs a session restored outside a named
  arrangement whose saved profile lacks `Name` or `Guid`, then Assign Profile,
  a profile selected, and OK.
- **Meanwhile:** preserved. Unit `nullability-n9-session-triggers` left both
  parameters of the nagging method nonnull. A `fix` commit, test first, can
  skip the save (or not offer) when the name is nil; the claim can then be
  made nullable.
- **Found:** 2026-11-20, unit `nullability-n9-session-triggers`.

## Copying, dragging or opening an image without encoded data gives no usable image

- **Where:** `sources/InlineImages/iTermImageInfo.m`,
  `-pasteboard:item:provideDataForType:` and `-nameForNewSavedTempFile`
  (the pasteboard's file URL, the file URL `PTYTextView+ARC.m` builds for
  an image action, and opening the image from `PTYTextView+ARC.m` and
  `iTermURLActionHelper.m`); `sources/TerminalView/PTYTextView.m`,
  `-_dragImage:forEvent:`.
- **What:** these use the image's encoded data, which a native image (the
  `BrokenPipeDivider` drawn when a session ends) does not have, nor does an
  inline image whose base64 payload decodes to no bytes.
  - `-nameForNewSavedTempFile` gets its name from
    `-[NSWorkspace temporaryFileNameWithPrefix:suffix:]`, which creates the
    file with `mkstemps`, and then writes the data into it. With no data the
    file stays empty, so every one of those gets a zero-byte file. This
    was so before unit `nullability-n6-swift-parameters` too: empty data
    also wrote nothing.
  - Copying offered zero bytes of `public.image` while the bridge stored
    empty data; since that unit it offers none (offering nil would raise in
    `-setData:forType:`).
  - Cmd-dragging the image began a drag whose drop gave a zero-byte file;
    since that unit `-_dragImage:forEvent:` returns at its existing
    `!imageData` test and no drag starts. The mouse handler has already set
    `_committedToDrag`, which the next mouse-up or mouse-down clears, as on
    the existing path for an image with no picture.
  None of these gives the user the image. Saving it (`-saveToFile:`,
  `-saveToItem:`) renders the image when there is no data, and works.
- **Reproduce:** with the advanced setting for the session-end divider
  character empty, end a session so the divider image is drawn, then copy,
  Cmd-drag or open the image.
- **Meanwhile:** left as it is. A `fix` commit could render the image for
  these paths the way `-dataForSavingFilename:` does.
- **Found:** 2026-11-20, unit `nullability-n6-swift-parameters`.

## `-[iTermParsedExpression string]` and `-description` abort for an expression made from a nil string

- **Where:** `sources/Language/iTermParsedExpression.m`, `-string`
  (`assert([_object isKindOfClass:[NSString class]])`) and `-description`,
  which calls `-string` for a string expression.
- **What:** `-initWithString:` stores its argument in `_object` and sets the
  type to string. The app passes nil there: `+[iTermExpressionParser
  parsedExpressionWithInterpolatedString:...]` (`iTermExpressionParser.m`, the
  all-literals return) builds the expression from
  `[swifty it_stringByExpandingBackslashEscapedCharacters]`, which is nil
  when the interpolated string is nil, as it is for semantic history's
  script in a profile never edited there (`iTermSemanticHistoryController.m`).
  For that expression `-string` and `-description` abort (asserts are on in
  release builds), and `-object`, claimed nonnull, returns nil. Unit
  `nullability-n7-expression-language` made the initializer's parameter
  nullable, because the app passes nil; the getters' claims and the assert
  still say a string expression always has a string.
- **Reproduce:** not reproduced in the app. The evaluator reads `-object` for
  a string expression and the parser's other uses of `-string` see only
  non-nil parts, so no live path calls `-string` or `-description` on it.
  The one log that would, `NSLog(@"Evaluate %@", _parsedExpression)` in
  `-[iTermExpressionEvaluator reallyEvaluateWithTimeout:...]`, runs only when
  the evaluator's `debug` property is set, and nothing in the tree sets it.
  Printing the expression in the debugger aborts.
- **Meanwhile:** left as it is. A `fix` commit could make the parser return
  a Nil expression for a nil interpolated string, or make the getters
  tolerate nil.
- **Found:** 2026-11-20, review of unit `nullability-n7-expression-language`.

## Terminal protocol fixes written but not landed (parked patch)

- **Where:** `tmp/parked/integer-findings-fixes-4b.patch` in the owner's
  checkout (not committed), against `sources/VT100/VT100Output.m`,
  `VT100Terminal.m`, `VT100TerminalDelegate.h`,
  `sources/VT100Screen/VT100ScreenMutableState.{h,m}`,
  `VT100ScreenMutableState+TerminalDelegate.m`,
  `sources/InlineImages/VT100InlineImageHelper.m` and two test files.
- **What:** four bugs the patch fixes, each with a test:
  - The DECRQCRA report (`VT100Output.m`, `(short)checksum` with `%04x`)
    prints eight hex digits for a checksum of 0x8000 or more.
  - DECCRA's destination ignores origin mode while its source rectangle
    honors it.
  - An inline image capped at 255 rows has its width multiplied by
    height / 255 instead of shrunk (`width=10;height=510` gives 20 by 255),
    and an image too wide for the rest of the line keeps the whole screen's
    width and is clipped.
  - CHT (`CSI n I`) with the `tabsWrapAround` advanced setting on runs up to
    65535 wrapping tabs, a stall of several seconds.
- **Meanwhile:** not landed. The review found that the patch's CHT change can
  loop about 2^31 times on a double-width line (a tab there neither moves
  nor wraps), and that its release note overstates the image fix. The image
  sizing and DECCRA changes are visible to users and wait for the owner
  (owner-queue.md Q23). Fix the loop before landing any of it.
- **Found:** 2026-11-21, unit `integer-findings-fixes-4` and its review.

## Kitty graphics: smaller problems left after the hardening

- **Where:** `sources/InlineImages/KittyImageController.swift`.
- **What:**
  - When a chunked transmission is abandoned for exceeding the size cap, the
    `ENOSPC` reply is sent for the final chunk's own command, which has
    `i=0` and no `q`, so a client waiting for its image id never sees it and
    a client that asked for silence gets a reply.
  - A FIFO under `/tmp` named like a `t=t` temporary file blocks the
    `open`, and the session's thread with it, until a writer appears. Only
    a local program can arrange this. `O_NONBLOCK` would fix it.
  - `t=f` reads any regular file the user can read except a denylist, by the
    protocol's design. Three denylist entries (`/private/etc`,
    `/private/var/db`, `/private/var/root`) can never match, because the
    path is resolved first and resolution strips `/private`. The error
    replies distinguish a missing file, a non-file, a denylisted path, a
    file that is not an image and a file over the cap, so program output,
    including from a remote host, can probe which paths exist.
  - The `S=` and `O=` keys are parsed and ignored.
  - An APC string is cut at 1 MiB by the parser and the rest of the payload
    is then printed as text.
- **Meanwhile:** left as they are. The denylist and the reply for abandoned
  transmissions are small fixes; restricting `t=f` is the owner's decision.
- **Found:** 2026-11-21, units `integer-findings-fixes-3` and `-4` and their
  reviews.

## DCH right after printing in the last column deletes nothing

- **Where:** `-[VT100Grid deleteChars:startingAt:]`.
- **What:** after a full line is printed the cursor is at x == width, pending
  a wrap, which is past the right margin, so `CSI P` deletes nothing. xterm
  is believed to delete the last character there (not verified).
- **Meanwhile:** left as it is.
- **Found:** 2026-11-21, review of unit `integer-findings-fixes-3`.


## `-screenRestoreState:` receives nil while a session is created

- **Where:** `sources/VT100Screen/VT100ScreenMutableState.m`,
  `-reallyPerformBlockWithJoinedThreads:delegate:topmost:`, line 7190:
  `[delegate screenRestoreState:oldState]`, where `oldState` came from
  `[delegate screenSwitchToSharedState]` a few lines earlier. The parameter
  is declared `_Nonnull` (`VT100ScreenDelegate.h:524`).
- **What:** during `-[PTYSession initSynthetic:]`, which joins threads,
  `screenSwitchToSharedState` returns nil and the nil is passed back to
  `screenRestoreState:`. The nullability sanitizer reports it
  (`invalid-null-argument`) and, in its aborting mode, stops the test host,
  so any test that creates a `PTYSession` cannot run clean under
  `tools/swift_migration/sanitizer_tests.sh nullability`. Not in the
  suppression list, so not triaged before.
- **Reproduce:** `tools/swift_migration/sanitizer_tests.sh nullability
  ModernTests/iTermCacheableImageSessionTests` (any test that calls
  `PTYSession(synthetic: false)` does it).
- **Which way nil arrives:** the delegate is nil. `-[PTYSession
  initSynthetic:]` calls `-[VT100Screen performBlockWithJoinedThreads:]`
  right after creating the screen (to set the flow ledger), before
  `_screen.delegate = self` (set later, in `-[PTYSession
  setScreenSize:parent:]`, `PTYSession.m` about line 2953). Messaging the nil
  delegate for `screenSwitchToSharedState` yields nil, and the
  `screenRestoreState:` call site passes it on. The sanitizer's stack
  confirms it: the report is at the call site
  (`VT100ScreenMutableState.m:7190`) with
  `-[PTYSession initSynthetic:]` below it and no `PTYSession` delegate
  frame above. No implementer ever runs with nil: with a delegate,
  `-[VT100Screen switchToSharedState]` returns the screen's `_state`, which
  `-[VT100Screen initWithOptionalMutationQueue:ownsQueue:]` sets to a copy
  of the mutable state, so it is never nil.
- **Resolved (2026-11-21, wrong annotation):** unit
  `screenRestoreState-nullability` (kind `annotate`) declares the
  parameter of `-[VT100ScreenDelegate screenRestoreState:]` `_Nullable`,
  with a comment saying why. The return of `screenSwitchToSharedState` and
  `-[VT100Screen switchToSharedState]` / `-restoreState:` keep their
  nonnull claims, which are true. The Swift conformers and their overrides
  in ModernTests and PerformanceTests take `VT100ScreenState?` and return
  early on nil (which cannot happen there, since they run only as a
  delegate). No behavior change. The nullability sanitizer run of
  `iTermCacheableImageSessionTests` no longer reports this path; it now
  stops at the next violation on the same session-creation path,
  `iTermGenericEvaluator.m:214` (nil passed to `-[NSMutableSet unionSet:]`
  from `-[iTermGenericEvaluator evaluateSynchronously:sideEffectsAllowed:completion:]`,
  reached from `-[iTermGenericEvaluator initWithScope:...]` in
  `-[PTYSession initSynthetic:]`), which is not triaged yet.
- **Follow-up (2026-11-22, unit `session-nullability-guards`, kind
  `fix`):** the next violations on the session and window creation paths
  were worked through one at a time with
  `tools/swift_migration/sanitizer_tests.sh nullability`. Each fix keeps
  today's behavior: a guard that skips a call whose result with nil is
  already known (checked with a small probe program against the SDK where
  it returns a value), or one annotation made nullable. Fixed, in the order
  the sanitizer reached them:
  1. `iTermGenericEvaluator.m`, `-evaluateSynchronously:sideEffectsAllowed:completion:`:
     `-unionSet:` with a nil `missing` (the evaluator's `missingValues` is
     nil for an expression with no function call) is skipped.
  2. `iTermScriptFunctionCall.m`, `-evaluateParametersWithScope:...`: the
     same, for an argument's `innerMissing`.
  3. `iTermProfilePreferences.h`, `iTermAmendedColorKey()`: the `profile`
     parameter is now `_Nullable` (wrong annotation). `-[PTYSession
     updateConfigurationFields]` passes the nil profile it has before
     `-setProfile:`, and the function only passes it to
     `+boolForKey:inProfile:`, which is nullable. No Swift caller.
  4. `ProfileModel.m`, `-bookmarkWithGuid:`: returns nil at once for a nil
     GUID (`-[PTYSession profileName]` passes one before the profile is
     set); `-isEqualToString:nil` is NO for every profile, so the search
     found nothing anyway.
  5. `PseudoTerminal.m`, `-windowDecorationColor`: no selected tab while
     the window is set up; `-indexOfTabViewItem:nil` is `NSNotFound`, so a
     nil item counts as not the first tab (and a nil tab view still counts
     as index 0, as before).
  6. `iTermKeyboardHandler.m`, `-stringForEventWithoutSideEffects:encoding:`:
     nil key mapper data becomes empty data; `-initWithData:nil` gives the
     same empty string as empty data in all 105 available encodings.
  7. `PTYSession.m`, `-setBadgeFormat:` and 8. `-setSubtitleFormat:`: the
     current format is nil the first time; the early return is skipped for
     nil, as `-isEqualToString:nil` is NO.
  9. `iTermSessionHotkeyController.m`, `-removeSession:`: no registration
     (no hotkey) skips `-removeObject:nil` and `-unregister`, both no-ops.
  10. `iTermBroadcastInputHelper.m`, `-shouldBroadcastToSessionWithID:fromSessionWithGUID:`:
      a nil domain skips `-intersectsSet:nil`, which is NO.
  11. `PseudoTerminal.m`, `-autoCommandHistoryEnabledForSession:`: a nil
      auto command history GUID skips `-isEqualToString:nil`.
  12. `PseudoTerminal+TouchBar.m`, `-updateTouchBarIfNeeded:`: a nil
      current customization identifier counts as different, as before.
  13. `iTermTouchbarMappings.m`, `+loadGlobalTouchBarMap`: a nil plist path
      (the resource is missing from the bundle) skips
      `-dictionaryWithContentsOfFile:nil`, which is nil.
  14. `SessionTitleView.m`, `-setTitle:`: a nil current title skips
      `-isEqualToString:nil`.

  `iTermCacheableImageSessionTests`, `PTYSessionEndActionTests`,
  `PTYSessionNullabilityTests` and `PTYSessionSendTextSlowlyTests` now run
  clean under the nullability sanitizer.
- **Follow-up (2026-11-22, unit `window-nullability-guards`, kind `fix`,
  with one `annotate` commit):** the owner then allowed guards anywhere,
  hot paths included, “as long as you're sure they have no
  behavior-changing effect”. Tests that open a window or a tab were run with
  `sanitizer_tests.sh nullability --collect` until no report was left. Each
  guard keeps the old result for every combination of nil and non-nil
  operands, with the same calls in the same order apart from skipped
  side-effect-free getters; results for nil were checked with probe
  programs against the SDK. Guarded:
  1. `iTermMutableAttributedStringBuilder.m`, `-setAttributes:` (hot path,
     per-row text drawing): `[attributes isEqualToDictionary:_attributes]`
     with nil `_attributes` (the first attributes on a builder) became
     `_attributes && [...]`, one nil test. `-isEqualToDictionary:nil` is NO
     for every dictionary class tried, and a nil `attributes` gives NO as a
     nil receiver either way.
  2. `iTermProfileModelJournal.m`, `+journalWithAction:bookmark:model:index:identifier:`:
     a nil `KEY_TAGS` gets `[[NSArray alloc] init]`, the same `__NSArray0`
     singleton `-initWithArray:nil` returned.
  3. `ProfileModel.m`, `-bookmark:differsJournalablyFrom:`: each field is
     compared by a helper that fetches a's value, then b's (the old
     receiver-then-argument order), counts a missing b value as a
     difference when a's value is nil or a string (an array for tags),
     which is what `-isEqualToString:nil`/`-isEqualToArray:nil` and a nil
     receiver gave, and otherwise sends the same message as before, so a
     value of another class in a malformed profile (an `NSNumber`, which
     has an `-isEqualToString:` category, or a string under `KEY_TAGS`)
     still gets it with nil. A field absent from both profiles still
     counts as a difference, as before.
  4. `iTermAutomaticProfileSwitcher.m`, `-setHostname:...`: each
     `-isEqualToString:` against a last value (nil before the first update
     or for an unknown field) and against a nil current GUID is skipped
     for a nil argument. The parameters are strings from session
     variables, which only app code sets (the API sets only `user.`).
     The same path in `iTermRule.m`,
     `-scoreForHostname:username:path:job:commandLine:expressionValueProvider:`,
     skips `-isEqualToString:` against a rule's nil `username` (found by
     `AutomaticProfileSwitcherTests`).
  5. and 6. `iTermExpressionEvaluator.m`, the interpolated-string and array
     paths: `-unionSet:` with a nil `missingValues` is skipped (no test
     reached these; the same proof as in `iTermGenericEvaluator`).
  7. `IntervalTree.m`, `-objectsWithSmallestLimitAfter:fromNode:` and
     `-objectsWithLargestLimitBelow:fromNode:`: `-addObjectsFromArray:`
     with a nil array (a subtree not searched) is skipped; it is a no-op.
     `-objectsWithSmallestLimitFromNode:` has the same shape, was not
     reached, and is unchanged.
  8. `iTermController.m`, `-indexOfTerminal:`: nil returns `NSNotFound`, or
     0 when the array is nil after `-cleanUpIfNeeded`, as
     `-indexOfObject:nil` and the nil array gave.
  9. `PseudoTerminal.m`, `-hideAutoCommandHistoryForSession:` (reached),
     `-wantsCommandHistoryUpdatesFromSession:` and
     `-updateAutoCommandHistoryForPrefix:inSession:popIfNeeded:` (same
     test, not reached): a nil auto command history GUID skips
     `-isEqualToString:`, as in `-autoCommandHistoryEnabledForSession:`.
  10. `PseudoTerminal.m`, `-nextTabGroupColorForParentGroupID:movingTabs:`:
      a nil parent group ID skips `-isEqualToString:`.
  11. `PseudoTerminal.m`, `-addTabGroupNestingItemsToMenu:forGroupID:`: a
      nil parent of the group skips `-isEqualToString:`;
      `-parentIDOfTabGroup:` is now called before `uniqueIdentifier` is
      read (both pure).
  12. (Made later, with the owner's leave: see below. The site is in
      `ThirdParty/PSMTabBarControl`.)
  13. `VT100ScreenState.m`, `-blockMarkWithID:`: a nil block ID (a line in
      no foldable block) returns nil at once; `-objectForKeyedSubscript:nil`
      is nil for every dictionary class tried.
  14. `iTermRootTerminalView.m`, both status bar layout methods: with no
      status bar view controller, `-addSubview:nil` is skipped. A probe
      showed it changes no subviews and calls none of the view's
      overridable hooks (`-didAddSubview:`, `-setNeedsLayout:`,
      `-setNeedsDisplay:`), unlike a real add.

  Annotations made nullable (outward positions, or an inward one every use
  tolerates; no Swift caller or conformer):
  `-[iTermSearchResultsMinimapViewDelegate searchResultsMinimapViewLocations:]`
  return (`SessionView` forwards it to its weak delegate; every caller
  treats nil as empty), and the `tabStyle` parameter of
  `-[iTermTheme statusBarTextColorForEffectiveAppearance:marginColor:colorMap:tabStyle:mainAndActive:]`
  (passed on to
  `-terminalWindowDecorationTextColorForBackgroundColor:effectiveAppearance:tabStyle:mainAndActive:`,
  which only casts it to `PSMMinimalTabStyle`; that method's own
  parameter is still nonnull, see Remaining).

  `TabLifetimeWitnessTests`, `WindowLifetimeWitnessTests`,
  `SessionLifetimeWitnessTests`, `PTYSessionTabColorResetTests`,
  `SwapSessionPaneTitleTests`, `ProfileColorsReloadTests`,
  `SessionNoteFocusTests`, `PTYSessionScreenWindowIndexTests`,
  `DuplicateWindowLocationLockTests`, `TabGroupNewGroupColorTests`,
  `PTYSessionSelectedCommandSearchTests`, `DuplicateTabSavedProgramTests`,
  `TabGroupMenuAppearanceTests`, `TabGroupRestoreValidationTests`,
  `WindowStyleChangeFocusTests` and `PaneFocusFollowsMouseIntegrationTests`
  now run clean under the nullability sanitizer, and so do
  `AutomaticProfileSwitcherTests`, `IntervalTreeBasicsTests`,
  `IntervalTreeForwardLocationEnumeratorTests`,
  `IntervalTreeSmallestLocationBugTests`,
  `AttributedStringBuilderSpacingMarkTests`,
  `InterpolateBuiltInFunctionTests`, `TriggerInterpolatedParameterTests`
  and the four session classes above. **Fixed 2026-11-22 with the
  owner's leave** (unit `psm-nullability-guards`; decisions.md), two
  sites that stopped a test class, both needing an edit under
  `ThirdParty/PSMTabBarControl`, which otherwise stays unedited until the
  owner says so:
  - `ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m:5070`,
    `-setTabGroupIdentifiers:parentIdentifiers:forTabViewItems:`: nil
    passed to `-isEqualToString:` when a parent identifier is `NSNull`.
    Stopped `TabGroupSubgroupDragOutTests` (3 of 6 tests). The guard is a
    nil test before the comparison; the group identifier test beside it
    has the same shape.
  - `sources/TerminalView/PseudoTerminal.m`,
    `-minimalTabStyleBackgroundColor`: returns nil while the window has no
    current session, through the nonnull return of
    `-[PSMMinimalTabStyleDelegate minimalTabStyleBackgroundColor]` in
    `PSMMinimalTabStyle.h`. Stopped `MinimalWindowSubtitleLayoutTests` (both
    tests). The fix is `nullable` on that return; 
    `-[PSMMinimalTabStyle tabBarColor]` already uses black for nil, and
    the callers in `PseudoTerminal.m` send `isDark` to the result, which
    is NO for nil as before.

  Also remaining, seen while reading and not reached by these tests:
  - `-[iTermTheme terminalWindowDecorationTextColorForBackgroundColor:effectiveAppearance:tabStyle:mainAndActive:]`
    receives the same nil `tabStyle` in the minimal theme (its parameter is
    nonnull) and then returns nil from its nonnull return. Both claims are
    in `iTermTheme.h`; the methods of `PTYWindow.h` that forward the color
    are unannotated. Not changed, since the sanitizer did not reach it and
    the return claim needs its callers checked.
  - `TerminalWindowTestFixtureTests` and `PTYTabTiledSessionsTests` skip
    unless on-screen tests are enabled (`OnscreenTestGate`), so they were
    not checked.
- **Found:** 2026-11-21, unit `iTermCacheableImage`, step 3.


## Clicking a notification posted without a window reveals a session in the first window

- **Where:** `sources/Notifications/iTermNotificationController.m`,
  `-notificationWasClicked:`.
- **What:** a notification posted with a negative window index (a session
  whose window is not registered, for which `-[PTYSession
  screenWindowIndex]` gives -1, or the convenience method that passes -1)
  gets an empty user info. On a click, the missing `win`, `tab` and `view`
  read as 0, so the handler reveals the session with view id 0 in tab 0 of
  window 0, if there is one, when it should do nothing. The handler checks
  only the upper bound of `win` before `-[iTermController
  terminalAtIndex:]`, relying on the posting side never to store a
  negative index. The indexes are also those of the time of posting;
  windows and tabs may have been reordered or closed since.
- **Reproduce:** by reading; not run.
- **Meanwhile:** left as it is.
- **Found:** 2026-11-21, a question from the owner about
  `screenWindowIndex`.


## `AsyncFilterDeliveryQueueTests.testDeliveriesQueuedDuringCatchUp` is flaky

- **Where:** `ModernTests/AsyncFilterTests.swift`.
- **What:** the test failed once in a full parallel run of the suite
  (2026-11-21, in a build lane, during unit `iTermCacheableImage`'s `fix`
  and `annotate` steps, which touch nothing it uses) and passed when its
  class was run alone on the same tree. It passed in the full runs before
  and after. It starts a second filter with a 1 ms cadence and expects a
  line delivered while that filter is catching up to be counted after
  `syncProcessToCompletion()`, so it probably depends on how far the
  timer-driven catch-up got when the line was delivered. Whether the test
  or `AsyncFilter` is at fault is not known.
- **Reproduce:** not reliably; `tools/run_tests.expect -parallel` on a busy
  machine.
- **Meanwhile:** the test is skipped (`XCTSkipIf(true, ...)`), by the flaky
  test rule of test-speed.md section 3. Not debugged.
- **Found:** 2026-11-21, unit `iTermCacheableImage`.

## `-[NSColor labColor]` swaps green and blue

- **Where:** `sources/Categories/NSColor+iTerm.m`, `-labColor`.
- **What:** it builds the sRGB triple as `.g = color.blueComponent` and
  `.b = color.greenComponent` before converting to L\*a\*b\*, so the
  lightness of a saturated color is wrong (green weighs most in
  lightness). Neutral grays are unaffected. Callers include
  `iTermColorSuggester` (the default background's lightness, which decides
  how far the suggested background must be from it) and whatever else uses
  `labColor`; not surveyed.
- **Reproduce:** by reading, not yet run: pure green,
  `NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).labColor().l`, should
  give the lightness of pure blue (about 32) instead of about 88.
- **Meanwhile:** preserved; `iTermColorSuggesterTests` uses gray defaults
  and reads result lightness without it.
- **Found:** 2026-11-21, unit `iTermColorSuggester`.


## `iTermColorSuggester` reseeds and draws from the process-wide `drand48` generator

- **Where:** `sources/TryingTooHard/iTermColorSuggester.swift`, the
  initializer (`srand48`, then two `drand48` calls per attempt). The
  Objective-C did the same; the port kept it.
- **What:** `srand48` and `drand48` share one generator for the whole
  process, with no locking. Each suggestion resets the sequence of anything
  else in the process that uses the family (nothing else in `sources/`
  does; linked libraries were not searched), and two threads constructing
  a suggester at once would interleave draws and get colors that do not
  match their seeds. Every caller is on the main thread, and the
  initializer asserts it in beta builds, which the owner judged the right
  guard (2026-11-21).
- **Reproduce:** by reading; `testOneAttemptTakesTwoNumbersFromTheSharedGenerator`
  pins the shared use.
- **Meanwhile:** left as it is. A fix that changes no colors: seed a local
  three-word state as `srand48` does (the seed's low 32 bits, then
  `0x330E`) and draw with `erand48`.
- **Found:** 2026-11-21, unit `iTermColorSuggester`.

## The inventory's parser misses a method written with a semicolon before its body

- **Where:** `tools/swift_migration/inventory.py`, `ObjCFile` (the method
  parser). Seen at `ColorPicker/ColorPicker/CPKFavorite.m:25`,
  `+ (BOOL)supportsSecureCoding; {`.
- **What:** Objective-C allows a `;` between a method's declarator and its
  body in an `@implementation`. The parser does not list such a method, so
  the inventory's method counts and anything built on them miss it. The
  compiler records it.
- **Reproduce:** `codedb.py verifyinventory CPKFavorite` reports
  `method database only: +[CPKFavorite supportsSecureCoding]` as
  unexplained.
- **Meanwhile:** left as it is; no tool decision depends on the inventory's
  per-method list.
- **Found:** 2026-11-21, unit `phase0-class-state-table`.

## `verifyinventory` compares `null_resettable`, which the database does not record

- **Where:** `tools/swift_migration/codedb/verify_inventory.py`,
  `KNOWN_ATTRIBUTES`. Seen at
  `sources/SearchingFiltering/iTermFindPasteboard.h:13`.
- **What:** the comparison of property attributes is meant to leave
  nullability out, because `objc_property.attributes` holds the attributes
  without it, but `null_resettable` is in the set it compares. Every
  `null_resettable` property is reported as an unexplained difference.
- **Reproduce:** `codedb.py verifyinventory iTermFindPasteboard` reports
  `property differs: stringValue ... inventory (copy,nonatomic,null_resettable,readonly), database (copy,nonatomic,readonly)`.
- **Meanwhile:** left as it is: one unexplained line on the whole tree.
  The fix is to drop `null_resettable` from `KNOWN_ATTRIBUTES`, with a
  fixture property that shows the line first.
- **Found:** 2026-11-21, unit `phase0-class-state-table`.
