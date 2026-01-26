# Fairness Scheduler Testing Plan

This document specifies the tests required for the round-robin fair scheduling implementation described in `implementation.md`. Tests are organized by component with checkpoints where all tests must pass before proceeding.

## Test Status

| Milestone | Test File | Status | Passing | Skipped |
|-----------|-----------|--------|---------|---------|
| 1 | `FairnessSchedulerTests.swift` | **COMPLETE** | 18/18 | 0 |
| 2 | `TokenExecutorFairnessTests.swift` | **COMPLETE** | 8 | 24 |
| 3 | `PTYTaskDispatchSourceTests.swift` | **COMPLETE** | 0 | 35 |
| 4 | (TaskNotifier tests) | Not started | - | - |
| 5 | (Integration tests) | Not started | - | - |

**Note:** Milestone 3 tests are all skipped because the dispatch source infrastructure is in place but not yet activated. Tests will pass after Milestone 5 integration.

**Run commands:**
```bash
./tools/run_fairness_tests.sh milestone1   # FairnessScheduler only
./tools/run_fairness_tests.sh milestone2   # TokenExecutor only
./tools/run_fairness_tests.sh milestone3   # PTYTask dispatch sources only
./tools/run_fairness_tests.sh              # All fairness tests
```

---

## Testing Framework Notes

- Unit tests should be placed in `ModernTests/` using the existing XCTest infrastructure
- Run tests with: `tools/run_tests.expect ModernTests/<TestClass>/<testMethod>`
- Integration tests may require manual verification or specialized test harnesses
- Mock objects should be used to isolate components under test

---

## Milestone 1: FairnessScheduler Unit Tests

**Checkpoint: All Milestone 1 tests must pass before implementing Milestone 2**

### 1.1 Session Registration/Unregistration

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testRegisterReturnsUniqueSessionId` | Each registration returns a unique, monotonically increasing SessionID | - |
| `testRegisterMultipleExecutors` | Multiple executors can be registered simultaneously | - |
| `testUnregisterRemovesSession` | Unregistered session is removed from `sessions` dictionary | - |
| `testUnregisterRemovesFromBusySet` | Unregistered session is removed from `busySet` | - |
| `testUnregisterCleanupCalledOnExecutor` | `cleanupForUnregistration()` is called on the executor | - |
| `testUnregisterNonexistentSessionNoOp` | Unregistering a session that doesn't exist is a no-op | Edge: invalid ID |
| `testUnregisterDuringExecution` | Session can be safely unregistered while executing | Edge: race condition |
| `testSessionIdNoReuse` | Session IDs are never reused even after unregistration | Edge: pointer aliasing prevention |

### 1.2 Busy List Management

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testEnqueueWorkAddsToBusyList` | `sessionDidEnqueueWork` adds session to busyList if not present | - |
| `testEnqueueWorkNoDuplicates` | Calling `sessionDidEnqueueWork` twice doesn't duplicate entry | Edge: duplicate prevention |
| `testEnqueueWorkDuringExecutionSetsFlag` | Work arriving during execution sets `workArrivedWhileExecuting` | - |
| `testBusyListMaintainsOrder` | Sessions are processed in FIFO order | - |
| `testEmptyBusyListNoExecution` | No execution scheduled when busyList is empty | - |
| `testBusySetMembershipMatchesBusyList` | busySet contents always match busyList contents | Invariant check |

### 1.3 Turn Execution Flow

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testExecuteNextTurnCallsExecutor` | `executeNextTurn` calls `executeTurn` on the correct executor | - |
| `testExecuteNextTurnRemovesFromBusyList` | Session removed from busyList before execution | - |
| `testYieldedResultReaddsToBusyListTail` | `.yielded` result adds session to end of busyList | - |
| `testCompletedResultNoReaddWithoutNewWork` | `.completed` result doesn't re-add unless `workArrivedWhileExecuting` | - |
| `testCompletedResultReaddsIfWorkArrived` | `.completed` with `workArrivedWhileExecuting=true` re-adds to busyList | Edge: work during turn |
| `testBlockedResultNoReadd` | `.blocked` result doesn't re-add to busyList | - |
| `testExecutionScheduledFlagPreventsDoubleSchedule` | `executionScheduled` flag prevents multiple concurrent dispatches | Edge: race prevention |
| `testWeakExecutorReferenceCleansUp` | Dead executor is cleaned up when turn comes | Edge: executor dealloc |

### 1.4 Round-Robin Fairness

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testRoundRobinOrderPreserved` | Sessions execute in registration order when all have work | - |
| `testYieldedSessionMovesToTail` | After yielding, session goes to end of line | - |
| `testThreeSessionsRoundRobin` | With A, B, C having work, execution order is A, B, C, A, B, C... | Integration |
| `testNewSessionAddedToTail` | New session with work joins at tail, doesn't cut in line | Edge: late joiner |
| `testSingleSessionGetsAllTurns` | With only one session, it gets consecutive turns | Edge: single session |

---

## Milestone 2: TokenExecutor Modifications

**Checkpoint: All Milestone 1 and Milestone 2 tests must pass before implementing Milestone 3**

### 2.1 Non-Blocking Token Addition

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testAddTokensDoesNotBlock` | `addTokens` returns immediately without blocking | - |
| `testAddTokensDecrementsAvailableSlots` | Each `addTokens` call decrements `availableSlots` by 1 | - |
| `testAddTokensHighPriorityDecrementsSlots` | High-priority tokens also decrement `availableSlots` | - |
| `testAddTokensKicksScheduler` | `addTokens` calls `notifyScheduler` (async for normal, sync for high-pri) | - |
| `testSemaphoreNotCreated` | No semaphore is created for token arrays | Removal verification |
| `testSemaphoreWaitNotCalled` | `semaphore.wait()` is never called | Removal verification |

### 2.2 Token Consumption Accounting

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testOnTokenArrayConsumedIncrementsSlots` | Consuming a token array increments `availableSlots` by 1 | - |
| `testAccountingBalanceAfterEnqueueConsume` | Enqueue N arrays, consume N arrays → `availableSlots` unchanged | Invariant |
| `testAccountingBalanceWithHighPriority` | High-priority inject + consume → `availableSlots` unchanged | Invariant |
| `testAccountingBalanceWithTriggerReinjection` | Trigger re-injection during execution → `availableSlots` unchanged | Edge: re-entrant |
| `testBackpressureReleaseHandlerCalled` | Handler called when crossing threshold to non-heavy | - |
| `testBackpressureReleaseHandlerNotCalledIfStillHeavy` | Handler not called if still at heavy backpressure | - |

### 2.3 ExecuteTurn Implementation

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testExecuteTurnReturnsBlockedWhenPaused` | Returns `.blocked` immediately when `tokenExecutorShouldQueueTokens` is true | - |
| `testExecuteTurnDrainsTaskQueue` | High-priority tasks in `taskQueue` are executed | - |
| `testExecuteTurnRespectsTokenBudget` | Stops when budget would be exceeded | - |
| `testExecuteTurnGroupAtomicity` | Never splits a group mid-execution | - |
| `testExecuteTurnProgressGuarantee` | At least one group executes even if over budget | Edge: large first group |
| `testExecuteTurnReturnsYieldedWhenMoreWork` | Returns `.yielded` when queue has remaining work | - |
| `testExecuteTurnReturnsCompletedWhenEmpty` | Returns `.completed` when queue is empty | - |
| `testExecuteTurnBudgetCheckBetweenGroups` | Budget is checked between groups, not within | - |

### 2.4 Budget Enforcement Edge Cases

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testFirstGroupExceedingBudgetExecutes` | 600-token first group with 500 budget executes fully | Edge: overshoot |
| `testBudgetExactlyMetContinues` | If exactly at budget after group, check continues to next | Edge: exact budget |
| `testZeroTokenGroupExecutes` | Empty/zero-token group doesn't block progress | Edge: degenerate group |
| `testMultipleSmallGroupsUpToBudget` | Many small groups execute until budget reached | - |

### 2.5 Scheduler Entry Points

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testScheduleCallsNotifyScheduler` | `schedule()` calls `notifyScheduler` via async dispatch | - |
| `testScheduleHighPriorityTaskCallsNotifyScheduler` | `scheduleHighPriorityTask` calls `notifyScheduler` when appropriate | - |
| `testScheduleHighPriorityTaskSyncAllowedDuringExecution` | With `syncAllowed=true` during execution, no extra kick | Edge: re-entrancy |
| `testAllEntryPointsKickScheduler` | All three entry points (addTokens, schedule, scheduleHighPriorityTask) kick | Comprehensive |

### 2.6 Legacy Removal

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testActiveSessionsWithTokensRemoved` | Static `activeSessionsWithTokens` set no longer exists | Removal verification |
| `testBackgroundSessionNoForegroundCheck` | Background sessions don't check foreground session state | Removal verification |
| `testBackgroundSessionGetsEqualTurns` | Background sessions get same turn duration as foreground | Fairness guarantee |

### 2.7 Cleanup on Unregistration

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testCleanupForUnregistrationIncrementsSlots` | Unconsumed tokens increment `availableSlots` correctly | - |
| `testCleanupEmptyQueueNoChange` | Empty queue cleanup doesn't change `availableSlots` | Edge: nothing to clean |
| `testCleanupRestoresInitialValue` | After cleanup, `availableSlots` equals initial total | Invariant |
| `testCleanupCalledOnSessionClose` | Cleanup called when session closed with pending tokens | Integration |

---

## Milestone 3: PTYTask Dispatch Source

**Checkpoint: All Milestone 1, 2, and 3 tests must pass before implementing Milestone 4**

### 3.1 Dispatch Source Lifecycle

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testSetupDispatchSourcesAfterValidFd` | Sources created only after `fd >= 0` | - |
| `testSetupDispatchSourcesAssertsOnInvalidFd` | Assertion fails if called with `fd < 0` | Edge: precondition |
| `testSourcesStartSuspended` | Both read and write sources start in suspended state | - |
| `testInitialStateSyncCalled` | `updateReadSourceState` and `updateWriteSourceState` called after setup | - |
| `testTeardownResumesBeforeCancel` | Suspended sources are resumed before being canceled | Edge: GCD requirement |
| `testTeardownNilsSourceReferences` | Sources are set to nil after cancellation | - |
| `testTeardownIdempotent` | Multiple teardown calls are safe | Edge: double teardown |

### 3.2 Unified State Check - Read

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testShouldReadTrueWhenAllConditionsMet` | Returns true when not paused, ioAllowed, backpressure < heavy | - |
| `testShouldReadFalseWhenPaused` | Returns false when paused | - |
| `testShouldReadFalseWhenIoNotAllowed` | Returns false when `jobManager.ioAllowed` is false | - |
| `testShouldReadFalseWhenHeavyBackpressure` | Returns false when backpressure >= heavy | - |
| `testUpdateReadSourceStateResumesWhenShouldRead` | Source resumed when `shouldRead` transitions to true | - |
| `testUpdateReadSourceStateSuspendsWhenShouldNotRead` | Source suspended when `shouldRead` transitions to false | - |
| `testUpdateReadSourceStateIdempotent` | Multiple calls with same state are safe (no double resume/suspend) | Edge: idempotency |

### 3.3 Unified State Check - Write

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testShouldWriteTrueWhenAllConditionsMet` | Returns true when not paused, not readOnly, ioAllowed, buffer has data | - |
| `testShouldWriteFalseWhenPaused` | Returns false when paused | - |
| `testShouldWriteFalseWhenReadOnly` | Returns false when `isReadOnly` is true | - |
| `testShouldWriteFalseWhenIoNotAllowed` | Returns false when `jobManager.ioAllowed` is false | - |
| `testShouldWriteFalseWhenBufferEmpty` | Returns false when `writeBuffer` is empty | - |
| `testUpdateWriteSourceStateResumesWhenShouldWrite` | Source resumed when `shouldWrite` transitions to true | - |
| `testUpdateWriteSourceStateSuspendsWhenShouldNotWrite` | Source suspended when `shouldWrite` transitions to false | - |

### 3.4 Event Handlers

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testHandleReadEventReadsBytes` | Read event handler reads from fd | - |
| `testHandleReadEventCallsDelegate` | Read handler calls `threadedReadTask:length:` | - |
| `testHandleReadEventRechecksState` | Read handler calls `updateReadSourceState` after read | - |
| `testHandleReadEventEagainIgnored` | EAGAIN error is ignored (not treated as broken pipe) | Edge: transient error |
| `testHandleReadEventBrokenPipeOnError` | Other read errors call `brokenPipe` | Edge: fatal error |
| `testHandleWriteEventDrainsBuffer` | Write event handler drains writeBuffer | - |
| `testHandleWriteEventRechecksState` | Write handler calls `updateWriteSourceState` after write | - |
| `testWriteBufferDidChangeUpdatesState` | Adding to writeBuffer triggers state update | - |

### 3.5 Pause State Integration

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testSetPausedUpdatesBothSources` | Setting `paused` calls both `updateReadSourceState` and `updateWriteSourceState` | - |
| `testPauseSuspendsReadSource` | Pausing suspends the read source | - |
| `testPauseSuspendsWriteSource` | Pausing suspends the write source (even with data) | - |
| `testUnpauseResumesIfConditionsMet` | Unpausing resumes sources if other conditions allow | - |

### 3.6 Backpressure Release Handler Integration

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testBackpressureReleaseHandlerWiredUp` | PTYSession wires the handler between TokenExecutor and PTYTask | - |
| `testBackpressureReleaseCallsUpdateReadState` | Handler invokes `updateReadSourceState` | - |
| `testBackpressureReleaseResumesReading` | Heavy→normal transition resumes read source | Integration |
| `testBackpressureReleaseWeakReferenceNoRetainCycle` | Weak reference to PTYTask prevents retain cycle | Memory safety |

---

## Milestone 4: TaskNotifier Changes

**Checkpoint: All Milestone 1, 2, 3, and 4 tests must pass before implementing Milestone 5**

### 4.1 Dispatch Source Protocol

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testUseDispatchSourceOptionalMethod` | Method is @optional in iTermTask protocol | - |
| `testPTYTaskReturnsYesForUseDispatchSource` | PTYTask returns YES for `useDispatchSource` | - |
| `testRespondsToSelectorCheckUsed` | TaskNotifier uses `respondsToSelector:` before calling | - |
| `testDefaultBehaviorIsSelectLoop` | Tasks not implementing method use select() path | - |

### 4.2 Select Loop Changes

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testDispatchSourceTaskSkipsFdSet` | Tasks with `useDispatchSource=YES` are not added to fd_set | - |
| `testDispatchSourceTaskStillIteratedForCoprocess` | Dispatch source tasks still iterated for coprocess handling | - |
| `testUnblockPipeStillInSelect` | Unblock pipe remains in select() set | - |
| `testCoprocessFdsStillInSelect` | Coprocess FDs remain in select() set | - |
| `testDeadpoolHandlingUnchanged` | Deadpool/waitpid handling continues working | - |

### 4.3 Mixed Mode Operation

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testMixedDispatchSourceAndSelectTasks` | System works with some tasks on dispatch_source, some on select() | Integration |
| `testTmuxTaskStaysOnSelect` | Tmux tasks (fd < 0) continue using select() path | - |
| `testLegacyTasksUnaffected` | Tasks not implementing `useDispatchSource` work unchanged | Backwards compat |

---

## Milestone 5: VT100ScreenMutableState Integration

**Checkpoint: All Milestone 1-5 tests must pass before integration testing**

### 5.1 Registration

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testRegisterOnInit` | TokenExecutor registered with FairnessScheduler in init | - |
| `testSessionIdStoredOnExecutor` | `fairnessSessionId` set on TokenExecutor after registration | - |
| `testSessionIdStoredOnMutableState` | `_fairnessSessionId` stored on VT100ScreenMutableState | - |

### 5.2 Unregistration

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testUnregisterOnSetEnabledNo` | Unregistration called in `setEnabled:NO` | - |
| `testUnregisterBeforeDelegateCleared` | Unregistration happens before `delegate = nil` | Order matters |
| `testUnregisterCleanupCalled` | `cleanupForUnregistration` called during unregister | - |

### 5.3 Re-kick on Unblock

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testTaskUnpausedSchedulesExecution` | `taskPaused=NO` triggers `scheduleTokenExecution` | - |
| `testShortcutNavigationCompleteSchedulesExecution` | Shortcut nav complete triggers `scheduleTokenExecution` | - |
| `testTerminalEnabledSchedulesExecution` | `terminalEnabled=YES` triggers `scheduleTokenExecution` | - |
| `testCopyModeExitSchedulesExecution` | Copy mode exit triggers `scheduleTokenExecution` (existing) | Regression |

### 5.4 Mutation Queue Usage

| Test | Description | Edge Case |
|------|-------------|-----------|
| `testTaskPausedUsesMutateAsynchronously` | `taskDidChangePaused` uses `mutateAsynchronously` | - |
| `testShortcutNavUsesMutateAsynchronously` | `shortcutNavigationDidComplete` uses `mutateAsynchronously` | - |

---

## Integration Tests

**Checkpoint: All unit tests and integration tests must pass before merge**

### I.1 Fairness Verification

| Test | Description | Method |
|------|-------------|--------|
| `testYesCommandDoesNotStarveInteractiveShell` | Run `yes` in one tab, verify other tab responsive | Manual + timing |
| `testCatLargeFileDoesNotStarveOtherSessions` | `cat` large file, verify other sessions get turns | Manual + timing |
| `testThreeHighThroughputSessionsFair` | Three `yes` commands get approximately equal throughput | Automated metric |
| `testInteractiveResponseTimeUnderLoad` | Keystroke latency < 100ms with background throughput | Latency measurement |

### I.2 High-Priority Token Preservation

| Test | Description | Method |
|------|-------------|--------|
| `testTriggersFireSynchronously` | Triggers execute during session's turn, not queued | Trigger test |
| `testApiInjectionProcessedFirst` | API-injected tokens processed before PTY tokens | API test |
| `testTriggerReinjectionWithinTurn` | Re-injected trigger tokens consumed same turn | Trigger test |

### I.3 Backpressure Correctness

| Test | Description | Method |
|------|-------------|--------|
| `testHighThroughputSuspended` | High-throughput session's read source suspended at heavy backpressure | State inspection |
| `testSuspendedSessionResumedOnDrain` | Suspended session resumes when tokens consumed | State inspection |
| `testNoSpinningWhenSuspended` | CPU usage low when session suspended | CPU measurement |
| `testBackpressureIsolation` | Session A's backpressure doesn't affect Session B's reading | Multi-session test |

### I.4 Session Lifecycle

| Test | Description | Method |
|------|-------------|--------|
| `testSessionCloseWithPendingTokens` | Closing session with queued tokens doesn't leak/crash | Memory + crash test |
| `testSessionCloseAccountingCorrect` | `availableSlots` returns to initial after close | Invariant check |
| `testRapidSessionOpenClose` | Rapidly opening/closing sessions doesn't cause issues | Stress test |
| `testSessionCloseDuringExecution` | Session closes while its turn is executing | Edge: timing |

### I.5 Dispatch Source Lifecycle

| Test | Description | Method |
|------|-------------|--------|
| `testProcessLaunchCreatesSource` | Dispatch source created after successful forkpty | State inspection |
| `testProcessExitCleansUpSource` | Sources torn down when process exits | State inspection |
| `testNoSourceLeakOnRapidRestart` | Rapidly restarting shells doesn't leak sources | Resource measurement |

### I.6 Performance Regression

| Test | Description | Method |
|------|-------------|--------|
| `testThroughputNotDegraded` | Single-session throughput within 95% of baseline | Benchmark |
| `testLatencyNotDegraded` | Token processing latency within 110% of baseline | Benchmark |
| `testMemoryUsageStable` | Memory usage stable under sustained load | Memory measurement |
| `testCpuUsageNotIncreased` | CPU usage not significantly higher than baseline | CPU measurement |

---

## Smoke Tests

Run these after each significant change to verify basic functionality.

| Test | Description | Quick Check |
|------|-------------|-------------|
| `smokeTestBasicTerminalOperation` | Open terminal, type commands, see output | Manual: 30 seconds |
| `smokeTestMultipleTabs` | Open 3 tabs, run commands in each | Manual: 1 minute |
| `smokeTestHighThroughput` | Run `yes \| head -1000000` without crash | Manual: 30 seconds |
| `smokeTestSessionClose` | Close tab while command running | Manual: 15 seconds |
| `smokeTestPauseResume` | Pause/unpause session | Manual: 30 seconds |
| `smokeTestCopyMode` | Enter/exit copy mode | Manual: 30 seconds |
| `smokeTestTriggers` | Verify a simple trigger fires | Manual: 1 minute |

---

## Accounting Invariant Tests

These tests verify the critical `availableSlots` accounting never drifts.

| Test | Description | Assertion |
|------|-------------|-----------|
| `testAccountingInvariantSteadyState` | At rest, `availableSlots == totalSlots` | Debug assertion |
| `testAccountingInvariantAfterNormalFlow` | After N enqueue + N consume cycles | Debug assertion |
| `testAccountingInvariantAfterSessionClose` | After session closed with pending tokens | Debug assertion |
| `testAccountingInvariantUnderStress` | After 10000 operations under load | Debug assertion |
| `testAccountingNeverGoesNegativeByMoreThanInjectionRate` | Negative slots bounded by concurrent injections | Debug assertion |

---

## Test Execution Checkpoints

### Checkpoint 1: FairnessScheduler Complete
**Must pass before proceeding to TokenExecutor changes:**
- All Milestone 1 tests (1.1 - 1.4)
- Smoke tests for basic terminal operation

### Checkpoint 2: TokenExecutor Complete
**Must pass before proceeding to PTYTask changes:**
- All Milestone 1 tests
- All Milestone 2 tests (2.1 - 2.7)
- Accounting invariant tests
- Smoke tests

### Checkpoint 3: PTYTask Complete
**Must pass before proceeding to TaskNotifier changes:**
- All Milestone 1-3 tests
- Backpressure integration tests (I.3)
- Dispatch source lifecycle tests (I.5)
- Smoke tests

### Checkpoint 4: TaskNotifier Complete
**Must pass before proceeding to integration:**
- All Milestone 1-4 tests
- Mixed mode operation tests
- Smoke tests

### Checkpoint 5: Full Integration
**Must pass before merge:**
- All unit tests (Milestones 1-5)
- All integration tests (I.1 - I.6)
- All smoke tests
- Performance regression tests
- Accounting invariant tests under stress

---

## Test Implementation Priority

1. **Critical (implement first):**
   - Accounting invariant tests (data integrity)
   - Round-robin fairness tests (core functionality)
   - Dispatch source lifecycle tests (resource safety)

2. **High (implement second):**
   - ExecuteTurn budget enforcement
   - Backpressure integration
   - Session lifecycle tests

3. **Medium (implement third):**
   - Edge case handling
   - Legacy removal verification
   - Performance regression

4. **Lower (implement last):**
   - Stress tests
   - Comprehensive integration scenarios

---

## Mocking Strategy

### FairnessScheduler Tests
- Mock `TokenExecutor` to control `executeTurn` results
- Use `XCTestExpectation` for async verification

### TokenExecutor Tests
- Mock `iTermTokenExecutorDelegate` for `tokenExecutorShouldQueueTokens`
- Mock `FairnessScheduler.shared` for isolation
- Use atomic counters to verify accounting

### PTYTask Tests
- Mock file descriptor operations
- Use dispatch_source test helpers or mock sources
- Mock `TokenExecutor` for backpressure simulation

### Integration Tests
- Use real components with test harness
- Instrument with timing measurements
- Use dedicated test sessions/terminals

---

## Test Implementation Note

**TDD approach** - Write tests first, then implement to make them pass. Benefits:
1. Forces interface design - Test skeletons establish the API before implementation
2. Catches edge cases early - Writing tests surfaces scenarios you might miss while coding
3. Regression baseline - Can verify existing TokenExecutor behavior before modifying it

### Test-First Viability by Component

| Component | Test-first viable? | Why |
|-----------|-------------------|-----|
| FairnessScheduler | Yes | New class, isolated, behavior well-defined |
| TokenExecutor accounting invariants | Yes | Can test existing accounting before changes |
| PTYTask dispatch sources | Partially | Need stubs for dispatch_source mocking |
| TaskNotifier changes | Not really | Integration-heavy, hard to unit test |

### Recommended Implementation Order

1. ~~Create `FairnessSchedulerTests` with mocked `TokenExecutor`~~ **DONE**
2. ~~Write tests for registration, busy list management, round-robin ordering~~ **DONE** (18 tests)
3. Implement `FairnessScheduler` to pass those tests
4. Then proceed to TokenExecutor modifications

**Current status:** Milestones 1-3 complete. Milestone 1: 18/18 passing. Milestone 2: 8 passing, 24 skipped. Milestone 3: 0 passing, 35 skipped (infrastructure in place, pending integration). Run with `./tools/run_fairness_tests.sh`
