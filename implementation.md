# Round-Robin Fair Scheduling Implementation Plan

**Testing:** A comprehensive test plan with checkpoints exists in `testing.md`. Each major section below references the checkpoint that must pass before proceeding to the next section.

## Implementation Status

| Milestone | Component | Status | Notes |
|-----------|-----------|--------|-------|
| 1 | FairnessScheduler | **DONE** | 18/18 tests passing. Commit `2ee3aebcf`. |
| 2 | TokenExecutor | **DONE** | 8 passing, 24 skipped. Commit `5afcfd07f`. |
| 3 | PTYTask Dispatch Sources | **DONE** | 0 passing, 35 skipped (infrastructure in place, pending activation). Commit `4087d02b9`. |
| 4 | TaskNotifier Changes | **DONE** | 1 passing, 11 skipped. Dispatch source tasks skip select(). |
| 5 | Integration | **DONE** | 0 passing, 24 skipped. System fully integrated. |

**Run tests:**
- Milestone 1: `./tools/run_fairness_tests.sh milestone1`
- Milestone 2: `./tools/run_fairness_tests.sh milestone2`
- Milestone 3: `./tools/run_fairness_tests.sh milestone3`
- Milestone 4: `./tools/run_fairness_tests.sh milestone4`
- Milestone 5: `./tools/run_fairness_tests.sh milestone5`

## Goal

Replace the current scheduling with round-robin fair scheduling so that "each PTY has some of its tokens executed after waiting for other PTYs to have *no more than one turn* getting their tokens executed." (PR #560)

## Problem Analysis

### The Two Starvation Points

**1. Read-level starvation (TaskNotifier thread):**
- TaskNotifier runs a single-threaded `select()` loop monitoring all PTY FDs
- When `TokenExecutor.addTokens()` is called, it blocks on `semaphore.wait()` if that session's queue is full
- This blocks the **entire TaskNotifier thread**, preventing ALL other sessions from being read
- A high-throughput session monopolizes TaskNotifier

**2. Execution-level starvation (mutation queue):**
- All sessions share a single mutation queue for token execution
- Currently, whichever session's `execute()` runs first processes all its tokens
- No mechanism ensures sessions take turns

### What's NOT the Problem

**High-priority tokens are per-session, not global.** Each session has its own `TokenExecutor` with its own `TwoTierTokenQueue`:
- queue[0]: That session's high-priority tokens (triggers, API injection)
- queue[1]: That session's normal PTY tokens

When Session A executes, it drains A's queue[0] before A's queue[1]. This doesn't affect Session B at all. **The current high-priority token handling is already correct and should be preserved.**

See `hi-pri-tokens.md` for detailed analysis of high-priority token categories and their functional requirements.

## Design Overview

### Core Changes

1. **Replace select() with per-PTY dispatch_source** - Decouples reading so one session can't block others
2. **Replace semaphore blocking with suspend/resume** - Non-blocking backpressure
3. **Add FairnessScheduler** - Coordinates round-robin execution on mutation queue
4. **Token budget per turn** - Execute groups until ~500 tokens consumed, then yield

### What Stays the Same

- Per-session `TokenExecutor` with `TwoTierTokenQueue` (high-priority handling)
- Trigger injection: synchronous/re-entrant within session's turn
- API injection: goes to session's queue[0], processed at start of session's turn
- Side effects system (30fps cadence on main queue)

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         READING (Decoupled)                         │
│                                                                     │
│   PTYTask A              PTYTask B              PTYTask C           │
│   dispatch_source        dispatch_source        dispatch_source     │
│        │                      │                      │              │
│        ▼                      ▼                      ▼              │
│   [Read+Parse]           [Read+Parse]           [Read+Parse]        │
│        │                      │                      │              │
│        ▼                      ▼                      ▼              │
│   TokenExecutor A        TokenExecutor B        TokenExecutor C     │
│   (owns its queue)       (owns its queue)       (owns its queue)    │
│   (suspend/resume)       (suspend/resume)       (suspend/resume)    │
└────────┼──────────────────────┼──────────────────────┼──────────────┘
         │                      │                      │
         │ "I have work"        │ "I have work"        │ "I have work"
         └──────────────────────┼──────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 FAIRNESS SCHEDULER (Gatekeeper)                     │
│                                                                     │
│   Busy List: [A] → [B] → [C] → ...  (round-robin)                  │
│                                                                     │
│   Does NOT buffer tokens. Only controls who executes.               │
│                                                                     │
│   On each turn:                                                     │
│     1. Pick session at head of busy list                           │
│     2. Grant permission: "Execute groups until ~500 tokens"        │
│     3. Wait for session to report back                              │
│     4. Move session to tail if more work remains                    │
└─────────────────────────────────────────────────────────────────────┘
                                │
                        "You may execute"
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      MUTATION QUEUE                                 │
│                                                                     │
│   Session's TokenExecutor.executeTurn(tokenBudget: 500):           │
│     1. Process queue[0] first, then queue[1] (priority order)      │
│     2. Execute complete groups; check budget between groups        │
│     3. Stop when next group would exceed budget (at least 1 runs)  │
│     4. Return: hasMoreWork                                          │
└─────────────────────────────────────────────────────────────────────┘
```

**Key principle:** Tokens stay in each session's TokenExecutor queue. The scheduler is a gatekeeper that controls execution order, not a buffer that holds tokens.

### Fairness Model: Token Budget with Group Atomicity

**The unit of execution is the TokenArray group, not individual tokens.**

Groups (TokenArrayGroups) represent atomic parsing units that cannot be split mid-execution. The fairness quota is expressed in tokens but enforced at group boundaries:

- Execute complete groups until cumulative tokens would exceed budget
- Never cut a group mid-execution
- One group can exceed the budget (bounded overshoot)

**Example:** Budget = 500 tokens
- Group A: 200 tokens → execute (total: 200)
- Group B: 250 tokens → execute (total: 450)
- Group C: 300 tokens → **skip** (450 + 300 > 500, and we've done at least one group)
- Yield to next session

**Edge case:** If the first group is 600 tokens, execute it anyway. At least one group always runs per turn.

This model provides:
1. **Approximate fairness** - bounded by max group size, not exact token count
2. **Parsing correctness** - groups remain atomic
3. **Progress guarantee** - each turn makes at least one group of progress

## Implementation Details

### 1. Per-PTY dispatch_source + Non-Blocking Admission Control

**Location:** `sources/PTYTask.m`

Replace TaskNotifier's select() with per-FD dispatch sources. **Critical:** The dispatch_source handler must NEVER block.

```objc
@interface PTYTask () {
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
    dispatch_queue_t _ioQueue;  // Shared by read and write sources
    BOOL _readSourceSuspended;
    BOOL _writeSourceSuspended;
}

// LIFECYCLE RULE: Only call after fd ≥ 0 (i.e., after process launch succeeds)
// Call from launchWithPath: after successful forkpty(), or equivalent
- (void)setupDispatchSources {
    NSAssert(self.fd >= 0, @"setupDispatchSources called with invalid fd");

    _ioQueue = dispatch_queue_create("com.iterm2.pty-io", DISPATCH_QUEUE_SERIAL);

    // Read source - starts SUSPENDED, will be resumed by updateReadSourceState
    // if conditions allow
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                         self.fd, 0, _ioQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf handleReadEvent];
    });
    dispatch_resume(_readSource);  // Must resume before we can suspend
    dispatch_suspend(_readSource); // Start suspended - updateReadSourceState will resume
    _readSourceSuspended = YES;

    // Write source - starts SUSPENDED until writeBuffer has data
    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,
                                          self.fd, 0, _ioQueue);
    dispatch_source_set_event_handler(_writeSource, ^{
        [weakSelf handleWriteEvent];
    });
    dispatch_resume(_writeSource);  // Must resume before we can suspend
    dispatch_suspend(_writeSource); // Start suspended - updateWriteSourceState will resume
    _writeSourceSuspended = YES;

    // Initial state sync - resume sources if conditions allow
    [self updateReadSourceState];
    [self updateWriteSourceState];
}

// TEARDOWN: Must resume suspended sources before canceling to avoid crash
// Call from dealloc or when PTY is being torn down
- (void)teardownDispatchSources {
    // ALL operations on _ioQueue to ensure serialization
    dispatch_async(_ioQueue, ^{
        if (_readSource) {
            // Resume if suspended before canceling (required by GCD)
            if (_readSourceSuspended) {
                dispatch_resume(_readSource);
            }
            dispatch_source_cancel(_readSource);
            _readSource = nil;
        }
        if (_writeSource) {
            // Resume if suspended before canceling (required by GCD)
            if (_writeSourceSuspended) {
                dispatch_resume(_writeSource);
            }
            dispatch_source_cancel(_writeSource);
            _writeSource = nil;
        }
    });
}

// ============================================================================
// UNIFIED STATE CHECK: Centralized predicates for source state management
// ============================================================================
// Instead of scattering suspend/resume calls, all conditions are checked in
// one place. Call updateReadSourceState/updateWriteSourceState when ANY
// condition changes.
//
// Why unified? Dispatch sources are level-triggered. If we don't suspend when
// conditions aren't met, the source fires continuously → busy-loop / CPU waste.
// ============================================================================

// All conditions that affect whether we should read
- (BOOL)shouldRead {
    return !self.paused &&
           self.jobManager.ioAllowed &&
           self.tokenExecutor.backpressureLevel < BackpressureLevelHeavy;
}

// All conditions that affect whether we should write
- (BOOL)shouldWrite {
    if (self.paused || self.isReadOnly || !self.jobManager.ioAllowed) {
        return NO;
    }
    [writeLock lock];
    BOOL hasData = [writeBuffer length] > 0;
    [writeLock unlock];
    return hasData;
}

// Called whenever ANY condition affecting read state changes:
// - paused property
// - jobManager.ioAllowed
// - backpressureLevel (via backpressureReleaseHandler)
// - after handleReadEvent (re-check backpressure)
- (void)updateReadSourceState {
    BOOL shouldRead = [self shouldRead];
    dispatch_async(_ioQueue, ^{
        if (shouldRead && _readSourceSuspended && _readSource) {
            dispatch_resume(_readSource);
            _readSourceSuspended = NO;
        } else if (!shouldRead && !_readSourceSuspended && _readSource) {
            dispatch_suspend(_readSource);
            _readSourceSuspended = YES;
        }
    });
}

// Called whenever ANY condition affecting write state changes:
// - paused property
// - isReadOnly property
// - jobManager.ioAllowed
// - writeBuffer contents (via writeBufferDidChange)
// - after handleWriteEvent (buffer may be empty)
- (void)updateWriteSourceState {
    BOOL shouldWrite = [self shouldWrite];
    dispatch_async(_ioQueue, ^{
        if (shouldWrite && _writeSourceSuspended && _writeSource) {
            dispatch_resume(_writeSource);
            _writeSourceSuspended = NO;
        } else if (!shouldWrite && !_writeSourceSuspended && _writeSource) {
            dispatch_suspend(_writeSource);
            _writeSourceSuspended = YES;
        }
    });
}

- (void)handleWriteEvent {
    [self processWrite];  // Existing method - drains writeBuffer

    // Re-check state after write (buffer may now be empty)
    [self updateWriteSourceState];
}

// Called when data is added to writeBuffer (replaces TaskNotifier unblock)
- (void)writeBufferDidChange {
    [self updateWriteSourceState];
}

- (void)handleReadEvent {
    // 1. Read bytes and parse to tokens (as processRead does now)
    ssize_t bytesRead = read(self.fd, buffer, MAXRW);
    if (bytesRead <= 0) {
        if (bytesRead < 0 && errno != EAGAIN) {
            [self brokenPipe];
        }
        return;
    }

    // 2. Add tokens to TokenExecutor via NEW non-blocking path
    //    (see TokenExecutor changes below - no semaphore.wait())
    //    NOTE: addTokens() internally calls notifyScheduler() which kicks FairnessScheduler
    [self.delegate threadedReadTask:buffer length:bytesRead];

    // 3. Re-check state after read (backpressure may have increased)
    [self updateReadSourceState];
}

// Hook pause state changes to update both sources
- (void)setPaused:(BOOL)paused {
    _paused = paused;
    [self updateReadSourceState];
    [self updateWriteSourceState];
}
```

**Why unified state check is better:**
- All conditions checked in one place (`shouldRead`/`shouldWrite`)
- No risk of forgetting to suspend/resume when a condition changes
- Dispatch sources are level-triggered: without suspension, they fire continuously when data is available but we don't want to process it → busy-loop
- `updateReadSourceState`/`updateWriteSourceState` are idempotent and safe to call from any queue

**Call sites for state updates:**

| Trigger | Call |
|---------|------|
| `setPaused:` | Both `updateReadSourceState` + `updateWriteSourceState` |
| `backpressureReleaseHandler` | `updateReadSourceState` |
| After `handleReadEvent` | `updateReadSourceState` |
| After `handleWriteEvent` | `updateWriteSourceState` |
| `writeBufferDidChange` | `updateWriteSourceState` |
| `jobManager.ioAllowed` changes | Both (if dynamic for non-tmux) |

**Invariant:** Any code that changes a condition affecting source state MUST call the appropriate update method.

### 2. Capacity Tracking: Per-Executor (Not Global)

**Design choice:** Each TokenExecutor tracks its own capacity via `availableSlots` / `backpressureLevel`. No global counter.

**Accounting unit:** One slot = one TokenArray. This matches the current semaphore semantics where each `addTokens()` call decrements by 1 and each array consumption increments by 1.

**Note:** This is separate from the per-turn token budget (see Fairness Model section). Backpressure limits queue depth (in arrays); the turn budget limits execution time (in tokens). These are independent mechanisms:

| Mechanism | Unit | Purpose |
|-----------|------|---------|
| `availableSlots` | TokenArrays | Backpressure - limit queue depth |
| `tokenBudget` | Tokens | Fairness - limit execution per turn |

**Why per-executor, not global:**
- Session A flooding cannot block Session B's reads (B has its own capacity)
- Already exists in this branch - reuse it
- Simpler: each PTY checks its own executor's state

| Concern | Data | Accessed From | Synchronization |
|---------|------|---------------|-----------------|
| **Per-session capacity** | `TokenExecutor.availableSlots` | Any queue | Atomic operations |
| **Turn scheduling** | `busyList`, `executionScheduled` | Mutation queue only | None needed |

#### Read-Side Admission

The read path uses the unified state check approach defined in Section 1. The `handleReadEvent` method:

1. Reads data from the PTY FD
2. Passes tokens to TokenExecutor (non-blocking `addTokens()`)
3. Calls `updateReadSourceState` to re-evaluate whether reading should continue

**Key insight:** No separate reservation step is needed. The unified state check evaluates `backpressureLevel` along with `paused` and `jobManager.ioAllowed` in one atomic decision. If backpressure becomes heavy after enqueueing tokens, `updateReadSourceState` will suspend the read source until conditions improve.

**Why this is simpler than reserve-before-read:**
- No CAS loops or slot reservation complexity
- All conditions checked in one predicate (`shouldRead`)
- State changes are idempotent - calling `updateReadSourceState` multiple times is safe
- Backpressure handler from mutation queue also calls `updateReadSourceState`

#### Dispatch Source Lifecycle Summary

| Phase | When | What | Queue |
|-------|------|------|-------|
| **Setup** | After `forkpty()` succeeds, `fd ≥ 0` | `setupDispatchSources` (sources start suspended) | Any (creates _ioQueue) |
| **Initial sync** | End of `setupDispatchSources` | `updateReadSourceState` + `updateWriteSourceState` | Dispatches to _ioQueue |
| **State change** | Any condition changes | `updateReadSourceState` or `updateWriteSourceState` | Dispatches to _ioQueue |
| **Teardown** | `dealloc` or PTY close | `teardownDispatchSources` (resume before cancel) | _ioQueue |

**Teardown invariant:** Must resume suspended sources before cancel. GCD maintains a suspend count; canceling while suspended is undefined behavior (typically crashes).

#### Drain-Side Resume (Mutation Queue)

**Problem:** TokenExecutor needs to signal PTYTask to re-evaluate read state, but:
1. Adding a direct reference creates a dependency cycle
2. Routing through VT100ScreenDelegate leaks I/O concerns into the wrong layer

**Solution:** Closure set by PTYSession (which knows both components):

```swift
// In TokenExecutor.swift - add closure property
@objc var backpressureReleaseHandler: (() -> Void)?

// In TokenExecutor, on mutation queue
private func onTokenArrayConsumed(_ tokenArray: TokenArray) {
    let newValue = iTermAtomicInt64Add(availableSlots, 1)

    // Notify PTYTask to re-evaluate read state
    // The unified state check will resume reading if ALL conditions are met
    // (not just backpressure - also checks paused, jobManager.ioAllowed)
    if newValue > 0 && backpressureLevel < .heavy {
        backpressureReleaseHandler?()
    }
}
```

```objc
// In PTYSession.m - wire up after screen and shell exist
// Called from sessionDidFinishLaunching or equivalent setup point
- (void)wireBackpressureHandler {
    __weak PTYTask *weakShell = self.shell;
    self.screen.mutableState.tokenExecutor.backpressureReleaseHandler = ^{
        // Use unified state check - will only resume if ALL conditions allow
        [weakShell updateReadSourceState];
    };
}
```

**Why this is better than delegate chain:**
- I/O concern stays at PTYTask/TokenExecutor boundary
- No new methods in VT100ScreenDelegate or iTermTokenExecutorDelegate
- PTYSession just does wiring - doesn't handle the callback itself
- Weak reference avoids retain cycles

**Thread safety (compatibility with #1):**
- `backpressureReleaseHandler` called from mutation queue
- `updateReadSourceState()` evaluates `shouldRead` then dispatches to `_ioQueue`
- Already designed to be callable from any queue - no conflict

**Control loop summary (unified state check model):**
1. Read source fires → `handleReadEvent` reads + enqueues tokens
2. After read: `updateReadSourceState` re-evaluates `shouldRead` predicate
3. If `shouldRead` returns NO (backpressure heavy, paused, or !ioAllowed) → suspend
4. Mutation queue: consume TokenArray → `backpressureReleaseHandler` → `updateReadSourceState`
5. If `shouldRead` returns YES (all conditions met) → resume
6. Each session's capacity is independent - no cross-session blocking

**(see: testing.md:Checkpoint 3)** — PTYTask dispatch source tests must pass before proceeding to TaskNotifier changes.

### 3. FairnessScheduler

**Location:** `sources/FairnessScheduler.swift` (new file)

**Critical design principle:** The scheduler does NOT buffer tokens. It only controls which session is allowed to execute. Tokens stay in TokenExecutor's queue (as today), preserving its flow control model.

```swift
@objc(iTermFairnessScheduler)
class FairnessScheduler: NSObject {
    static let shared = FairnessScheduler()

    // Session ID type - use a simple incrementing counter for stability
    // (avoids pointer aliasing issues with ObjectIdentifier after dealloc)
    typealias SessionID = UInt64
    private var nextSessionId: SessionID = 0

    // ALL state is mutation-queue-only - no locks needed
    private var sessions: [SessionID: SessionState] = [:]
    private var busyList: [SessionID] = []           // Ordered list for round-robin
    private var busySet: Set<SessionID> = []         // O(1) membership check
    private var executionScheduled = false

    struct SessionState {
        weak var executor: TokenExecutor?
        var isExecuting: Bool = false
        var workArrivedWhileExecuting: Bool = false
    }

    // Called from TokenExecutor - ALREADY ON MUTATION QUEUE
    func sessionDidEnqueueWork(_ sessionId: SessionID) {
        guard var state = sessions[sessionId] else { return }

        if state.isExecuting {
            // Session is currently executing - can't add to busyList now
            // Mark that work arrived; will be handled when turn finishes
            state.workArrivedWhileExecuting = true
            sessions[sessionId] = state
            return
        }

        if !busySet.contains(sessionId) {
            busySet.insert(sessionId)
            busyList.append(sessionId)
            ensureExecutionScheduled()
        }
    }

    // Called from mutation queue when a session finishes its turn
    func sessionFinishedTurn(_ sessionId: SessionID, result: TurnResult) {
        guard var state = sessions[sessionId] else { return }

        state.isExecuting = false
        let workArrived = state.workArrivedWhileExecuting
        state.workArrivedWhileExecuting = false

        switch result {
        case .completed:
            if workArrived {
                // New work arrived during execution - re-add to busyList
                busySet.insert(sessionId)
                busyList.append(sessionId)
            }
            // else: already removed from busySet in executeNextTurn
        case .yielded:
            // More work - back of the line
            busySet.insert(sessionId)
            busyList.append(sessionId)
        case .blocked:
            // Can't make progress - don't reschedule
            // Session will be re-kicked when unblocked via scheduleTokenExecution
            break
        }

        sessions[sessionId] = state
        ensureExecutionScheduled()
    }

    private func ensureExecutionScheduled() {
        guard !busyList.isEmpty else { return }
        guard !executionScheduled else { return }

        executionScheduled = true

        // Already on mutation queue, but use async to avoid deep recursion
        iTermGCD.mutationQueue.async { [weak self] in
            self?.executeNextTurn()
        }
    }

    private func executeNextTurn() {
        executionScheduled = false

        guard !busyList.isEmpty else { return }

        let sessionId = busyList.removeFirst()
        busySet.remove(sessionId)  // O(1) removal

        guard var state = sessions[sessionId],
              let executor = state.executor else {
            // Dead session - clean up
            sessions.removeValue(forKey: sessionId)
            ensureExecutionScheduled()
            return
        }

        // Mark as executing - prevents duplicate busyList entries
        state.isExecuting = true
        state.workArrivedWhileExecuting = false
        sessions[sessionId] = state

        executor.executeTurn(tokenBudget: 500) { [weak self] result in
            self?.sessionFinishedTurn(sessionId, result: result)
        }
    }

    // Registration - returns a stable session ID
    @objc func register(_ executor: TokenExecutor) -> SessionID {
        let sessionId = nextSessionId
        nextSessionId += 1
        sessions[sessionId] = SessionState(executor: executor)
        return sessionId
    }

    @objc func unregister(sessionId: SessionID) {
        // Clean up any unconsumed tokens in the executor's queue
        // to prevent availableSlots drift
        if let state = sessions[sessionId], let executor = state.executor {
            executor.cleanupForUnregistration()
        }

        sessions.removeValue(forKey: sessionId)
        busySet.remove(sessionId)
        // busyList will be cleaned lazily in executeNextTurn when session not found
    }
}
```

**The Kick Guarantee:**

There are THREE entry points that can schedule work, and ALL must notify the scheduler:

1. **`addTokens()`** - adds tokens to queue (normal PTY flow)
2. **`schedule()`** - explicitly triggers execution (called by `scheduleTokenExecution`)
3. **`scheduleHighPriorityTask()`** - adds tasks to `taskQueue` (called by `performBlockAsynchronously`)

```swift
// ENTRY POINT 1: addTokens() - called from various queues
func addTokens(_ vector: CVector, ..., highPriority: Bool) {
    iTermAtomicInt64Add(availableSlots, -1)
    reallyAddTokens(vector, ..., semaphore: nil)

    if highPriority {
        // High-priority: caller is already on mutation queue
        notifyScheduler()
    } else {
        // Normal: dispatch kick to mutation queue
        queue.async { [weak self] in
            self?.notifyScheduler()
        }
    }
}

// ENTRY POINT 2: schedule() - explicit execution trigger
func schedule() {
    queue.async { [weak self] in
        self?.notifyScheduler()
    }
}

// ENTRY POINT 3: scheduleHighPriorityTask() - task queue
func scheduleHighPriorityTask(_ task: @escaping TokenExecutorTask, syncAllowed: Bool) {
    taskQueue.append(task)
    if syncAllowed {
        // Already on mutation queue during execution - task will run this turn
        // No scheduler notification needed - we're already executing
        if executingCount == 0 {
            notifyScheduler()  // Not currently executing, need a kick
        }
    } else {
        queue.async { [weak self] in
            self?.notifyScheduler()
        }
    }
}

// UNIFIED: All paths go through this
private func notifyScheduler() {
    // On mutation queue
    // fairnessSessionId is set by VT100ScreenMutableState after registration
    FairnessScheduler.shared.sessionDidEnqueueWork(fairnessSessionId)
}
```

**Why this is race-free:**
1. All three entry points call `notifyScheduler()` (sync or async)
2. `notifyScheduler()` always runs on mutation queue
3. `sessionDidEnqueueWork()` adds to busyList if not already there
4. All scheduler state is mutation-queue-only - no races possible
5. `busySet` provides O(1) membership check to prevent duplicate entries

**Edge case - syncAllowed during execution:**
When `scheduleHighPriorityTask(syncAllowed: true)` is called during `executeTurn()`, the task is already on the mutation queue and will be consumed in the current turn's `taskQueue` drain. No extra kick needed - but if `executingCount == 0`, we need to kick.

**Blocked sessions - re-kick on unblock:**

When `tokenExecutorShouldQueueTokens()` returns true (paused, copy mode, shortcut navigation), the session returns `.blocked` and is NOT re-added to busyList. This prevents spinning.

**Canonical unblock API: `scheduleTokenExecution`**

The codebase already has `[mutableState scheduleTokenExecution]` which calls `[_tokenExecutor schedule]`. With our changes, `schedule()` calls `notifyScheduler()` → kicks the FairnessScheduler.

**Existing usage (already correct):**
- Copy mode exit: `PTYSession.m:19961` calls `scheduleTokenExecution` ✓

**Missing usage (add these):**
- `taskPaused` transition: `PTYSession.m:4039` - add `scheduleTokenExecution` when `paused=NO`
- `shortcutNavigationDidComplete`: `PTYSession.m:19930` - has TODO, add `scheduleTokenExecution`
- `terminalEnabled` transition: `VT100ScreenMutableState.setTerminalEnabled:` - add `scheduleTokenExecution` when `enabled=YES`

```objc
// PTYSession.m - taskDidChangePaused:paused: (around line 4039)
// NOTE: Convert to mutateAsynchronously for single-writer consistency (per existing TODO)
- (void)taskDidChangePaused:(PTYTask *)task paused:(BOOL)paused {
    [_screen mutateAsynchronously:^(VT100Terminal *terminal,
                                    VT100ScreenMutableState *mutableState,
                                    id<VT100ScreenDelegate> delegate) {
        mutableState.taskPaused = paused;
        if (!paused) {
            // Resume token execution when unpausing
            [mutableState scheduleTokenExecution];
        }
    }];
}

// PTYSession.m - shortcutNavigationDidComplete (around line 19930)
// NOTE: The textview operation must happen on main thread, so we use performBlockWithJoinedThreads
// for that part, then separately handle the mutation queue state change.
- (void)shortcutNavigationDidComplete {
    [_textview removeContentNavigationShortcutsAndSearchResults:_modeHandler.clearSelectionsOnExit];
    [_screen mutateAsynchronously:^(VT100Terminal *terminal,
                                    VT100ScreenMutableState *mutableState,
                                    id<VT100ScreenDelegate> delegate) {
        mutableState.shortcutNavigationMode = NO;
        [mutableState scheduleTokenExecution];
    }];
}

// VT100ScreenMutableState.m - setTerminalEnabled: (add re-kick)
- (void)setTerminalEnabled:(BOOL)terminalEnabled {
    BOOL wasEnabled = _terminalEnabled;
    _terminalEnabled = terminalEnabled;
    if (terminalEnabled && !wasEnabled) {
        // Re-kick token execution when terminal becomes enabled
        [self scheduleTokenExecution];
    }
}
```

**Design note on `performBlockWithJoinedThreads` vs `mutateAsynchronously`:**

The existing TODOs ask about converting to `mutateAsynchronously`. The key consideration:
- `performBlockWithJoinedThreads`: Blocks the calling thread until mutation queue processes the block. Useful when the caller needs to observe the state change immediately (e.g., for UI synchronization).
- `mutateAsynchronously`: Non-blocking. Better for single-writer consistency and avoiding deadlocks.

For state changes that affect token execution (`taskPaused`, `shortcutNavigationMode`, `terminalEnabled`), `mutateAsynchronously` is preferred because:
1. The re-kick must happen on mutation queue anyway
2. The caller doesn't need to block waiting for the state change
3. Avoids potential priority inversion with the mutation queue

**No property-setter re-kicks needed in addition to above** - use the existing `scheduleTokenExecution` pattern within the async blocks.

**Queue contracts (explicit):**

| Operation | Called From | Accesses | Blocking? |
|-----------|-------------|----------|-----------|
| Backpressure check | PTYTask read queue | This executor's `availableSlots` (atomic) | NO |
| `addTokens()` | PTYTask read queue | Enqueues + dispatches to mutation queue | NO |
| `schedule()` | Any queue | Dispatches to mutation queue | NO |
| `scheduleHighPriorityTask()` | Any queue | Appends to taskQueue + maybe dispatches | NO |
| `notifyScheduler()` | Mutation queue | Calls scheduler | NO |
| `sessionDidEnqueueWork()` | Mutation queue | Scheduler state (no lock) | NO |
| `ensureExecutionScheduled()` | Mutation queue | Scheduler state (no lock) | NO |
| `executeNextTurn()` | Mutation queue | Scheduler state (no lock) | NO |
| `sessionFinishedTurn()` | Mutation queue | Scheduler state (no lock) | NO |
| `onTokenArrayConsumed()` | Mutation queue | This executor's `availableSlots` (atomic) | NO |

**Threading model:**
- **Per-executor `availableSlots`**: each TokenExecutor's capacity, accessed via atomic ops
- **Scheduler state** (busyList, sessions, executionScheduled): mutation-queue-only, no locks
- **Kick mechanism**: all entry points (addTokens, schedule, scheduleHighPriorityTask) → notifyScheduler()

**The "Kick" Chain (explicit):**

```
PTYTask read queue (normal token flow):
  1. Check this executor's backpressureLevel (atomic read)
  2. If heavy: suspend, return
  3. Read bytes, parse tokens
  4. addTokens():
       a. Decrements availableSlots (atomic)
       b. Enqueues TokenArray
       c. queue.async { notifyScheduler() }  ← KICK
  5. Re-check backpressureLevel, suspend if now heavy

Other kick entry points:
  - schedule(): queue.async { notifyScheduler() }  ← KICK
  - scheduleHighPriorityTask(): appends task, then notifyScheduler() if needed  ← KICK

Mutation queue:
  6. notifyScheduler() calls scheduler.sessionDidEnqueueWork()
  7. sessionDidEnqueueWork() adds to busyList if not already there
  8. ensureExecutionScheduled() → async { executeNextTurn() }
  9. executeNextTurn() picks session, calls executor.executeTurn()
  10. TokenExecutor.executeTurn():
       - If blocked (paused/copy mode): return .blocked immediately
       - Drains taskQueue (high-priority tasks)
       - Runs token groups until budget exhausted
  11. onTokenArrayConsumed() increments availableSlots per array
  12. If backpressureLevel < heavy: backpressureReleaseHandler() → task.updateReadSourceState()
  13. Completion calls sessionFinishedTurn(result:)
       └─► .yielded: adds to busyList tail
       └─► .completed: removes from busyList
       └─► .blocked: removes from busyList (re-kick on unblock)
       └─► ensureExecutionScheduled()

Unblock path (paused→unpaused, copyMode→normal, shortcutNav complete, terminalEnabled):
  14. PTYSession/VT100ScreenMutableState calls [mutableState scheduleTokenExecution]
  15. scheduleTokenExecution → [_tokenExecutor schedule] → notifyScheduler()
  16. Re-enters at step 6
```

**Critical invariants:**
- All three entry points (addTokens, schedule, scheduleHighPriorityTask) call notifyScheduler()
- `busySet` provides O(1) duplicate detection; `busyList` maintains round-robin order
- `executionScheduled` prevents duplicate execution dispatches
- Per-executor `availableSlots` stays balanced (decrement on enqueue, increment on consume)
- Session cleanup calls `cleanupForUnregistration()` to restore `availableSlots` for unconsumed tokens
- All scheduler state mutations happen on mutation queue (no races)

**(see: testing.md:Checkpoint 1)** — FairnessScheduler tests must pass before proceeding to TokenExecutor changes.

### 4. TokenExecutor Modifications

**Location:** `sources/TokenExecutor.swift`

#### Token Accounting: All Paths

**Critical:** `availableSlots` must be correctly maintained across ALL token paths. Missing accounting will stall readers or cause overflow.

| Path | Enqueue Accounting | Consume Accounting | Notes |
|------|-------------------|-------------------|-------|
| **Normal PTY** | `addTokens()` decrements | `onTokensConsumed()` increments | Primary path |
| **API injection** | `addTokens(highPriority:true)` decrements | `onTokensConsumed()` increments | Rare, but counts |
| **Startup injection** | Same as API | Same as API | One-time at init |
| **Trigger re-injection** | `addTokens(highPriority:true)` decrements | Consumed same turn, increments | Re-entrant |

**Key decision:** High-priority tokens ALSO count against `availableSlots`. This prevents a flood of API injections from overflowing the queue. They just skip the semaphore blocking (which we're removing anyway).

**Accounting call sites:**

```swift
// SIMPLIFIED MODEL: All paths decrement on enqueue, increment on consume.
// No separate reservation step - simpler and avoids CAS complexity.

// ENQUEUE - always decrements (called from any queue)
func addTokens(_ vector: CVector, ..., highPriority: Bool) {
    // Decrement by 1 per TokenArray for ALL paths
    // High-priority can temporarily go negative (bounded by injection rate)
    iTermAtomicInt64Add(availableSlots, -1)

    reallyAddTokens(vector, ..., semaphore: nil)

    if highPriority {
        notifyScheduler()  // Sync - already on mutation queue
    } else {
        queue.async { [weak self] in
            self?.notifyScheduler()
        }
    }
}

// CONSUME - always increments (called on mutation queue)
private func onTokenArrayConsumed(_ tokenArray: TokenArray) {
    let newValue = iTermAtomicInt64Add(availableSlots, 1)

    // Resume reading if we crossed above threshold
    if newValue > 0 && backpressureLevel < .heavy {
        backpressureReleaseHandler?()
    }
}
```

**Accounting model:**

| Path | Decrement | Increment | Can go negative? |
|------|-----------|-----------|------------------|
| Normal PTY | In `addTokens()` | In `onTokenArrayConsumed()` | Yes (temporarily, if high-priority concurrent) |
| High-priority | In `addTokens()` | In `onTokenArrayConsumed()` | Yes (temporarily) |

**Why no separate reservation step:**
- CAS loops add complexity and can have ABA-style issues
- High-priority must be able to go negative anyway (can't block API injection)
- PTYTask checks `backpressureLevel >= .heavy` BEFORE calling `addTokens()`
- If heavy, PTYTask suspends reading - never calls addTokens when at capacity
- Simplifies the model: one decrement path, one increment path

**Invariants:**
- `backpressureLevel` treats `<= 0` as `.heavy`
- PTYTask suspends reading when `backpressureLevel >= .heavy`
- Consumption restores balance
- Steady-state: availableSlots == totalSlots (no drift)

**Trigger re-injection accounting:**
Triggers inject during `executeTokenGroups()`. The injected tokens go to queue[0] and are consumed in the SAME `enumerateTokenArrayGroups` loop (it re-checks queue[0] after each group). Accounting:
- `addTokens(highPriority:true)` → decrements `availableSlots`
- When consumed later in same loop → `onTokenArrayConsumed()` increments

This is balanced within a single turn.

#### Changes Summary

1. **Remove semaphore blocking** - `semaphore.wait()` removed from normal path
2. **Universal accounting** - ALL paths decrement on enqueue, increment on consume
3. **Drain-side state update** - `onTokensConsumed()` triggers `backpressureReleaseHandler()` which calls `updateReadSourceState()` (unified state check re-evaluates ALL conditions)
4. **Add `executeTurn(tokenBudget:completion:)`** - group-level fairness with token budget

```swift
// CHANGED: addTokens no longer blocks, but ALWAYS does accounting and kicks scheduler
func addTokens(_ vector: CVector, ..., highPriority: Bool) {
    // Decrement by 1 per TokenArray (matches current semaphore semantics)
    iTermAtomicInt64Add(availableSlots, -1)
    reallyAddTokens(vector, ..., semaphore: nil)

    if highPriority {
        // High-priority: caller is already on mutation queue
        // Kick synchronously
        impl.didAddTokens()
    } else {
        // Normal: dispatch kick to mutation queue
        queue.async { [weak self] in
            self?.impl.didAddTokens()
        }
    }
}

// Called when TokenArray is fully consumed (replaces semaphore.signal())
private func onTokenArrayConsumed(_ tokenArray: TokenArray) {
    // Increment by 1 (one slot freed)
    iTermAtomicInt64Add(availableSlots, 1)

    // Trigger unified state check - PTYTask will re-evaluate shouldRead
    // (checks backpressure AND paused AND jobManager.ioAllowed)
    if backpressureLevel < .heavy {
        backpressureReleaseHandler?()
    }
}

enum TurnResult {
    case completed      // No more work
    case yielded        // More work, re-add to busyList
    case blocked        // Can't make progress (paused, copy mode) - don't reschedule
}

// Fairness-limited execution - token budget enforced at group boundaries
func executeTurn(tokenBudget: Int, completion: @escaping (TurnResult) -> Void) {
    // Check if we're blocked (paused, copy mode, etc.)
    if delegate.tokenExecutorShouldQueueTokens() {
        // Can't make progress - don't reschedule until unblocked
        completion(.blocked)
        return
    }

    var tokensConsumed = 0
    var groupsExecuted = 0

    tokenQueue.enumerateTokenArrayGroups { (group, priority) in
        let groupTokenCount = group.arrays.reduce(0) { $0 + Int($1.count) }

        // Budget check BETWEEN groups, not within
        // At least one group always executes (progress guarantee)
        if tokensConsumed + groupTokenCount > tokenBudget && groupsExecuted > 0 {
            return false  // budget would be exceeded, yield to next session
        }

        // Execute the entire group atomically
        executeTokenGroups(group, ...)
        tokensConsumed += groupTokenCount
        groupsExecuted += 1

        return true  // continue to next group
    }

    // Report back to scheduler
    let hasMoreWork = !tokenQueue.isEmpty || !taskQueue.isEmpty
    completion(hasMoreWork ? .yielded : .completed)
}
```

**Where consume accounting happens:**

Good news: `TokenArray` already has `onSemaphoreSignaled` callback invoked when consumed. The existing code at `TokenExecutor.swift:299-301` already wires this to increment `availableSlots`:

```swift
// EXISTING code in TokenExecutor.reallyAddTokens()
let onSemaphoreSignaled: (() -> Void)?
if semaphore != nil {
    onSemaphoreSignaled = { [availableSlots] in
        iTermAtomicInt64Add(availableSlots, 1)
    }
} else {
    onSemaphoreSignaled = nil
}
```

**What needs to change:**
1. Remove the `semaphore != nil` condition - always set the callback
2. Add `backpressureReleaseHandler` call when crossing threshold

```swift
// UPDATED code in TokenExecutor.reallyAddTokens()
let onConsumed: (() -> Void) = { [weak self] in
    guard let self = self else { return }
    let newValue = iTermAtomicInt64Add(self.availableSlots, 1)
    if newValue > 0 && self.backpressureLevel < .heavy {
        self.backpressureReleaseHandler?()
    }
}
let tokenArray = TokenArray(vector,
                            lengthTotal: lengthTotal,
                            lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                            semaphore: nil,  // No semaphore - non-blocking
                            onSemaphoreSignaled: onConsumed)
```

**Key insights:**
1. `addTokens()` never blocks - dispatch_source handler always returns quickly
2. ALL paths decrement on enqueue (normal AND high-priority)
3. Consume accounting reuses existing `onSemaphoreSignaled` callback mechanism
4. `backpressureReleaseHandler` called when crossing threshold
5. Both queue[0] and queue[1] count toward fairness quota

### Scheduler Registration/Unregistration

**Session ID design:** Use a monotonically increasing `UInt64` counter instead of `NSValue valueWithPointer`. This avoids pointer aliasing issues where a deallocated object's address could be reused by a new object.

**Registration point:** After TokenExecutor created in `VT100ScreenMutableState.init` (line 122):

```objc
@interface VT100ScreenMutableState () {
    uint64_t _fairnessSessionId;
}
@end

// In init:
_tokenExecutor = [[iTermTokenExecutor alloc] initWithTerminal:_terminal
                                             slownessDetector:...
                                                        queue:_queue];
_tokenExecutor.delegate = self;

// NEW: Register with FairnessScheduler - returns stable session ID
_fairnessSessionId = [[FairnessScheduler shared] registerExecutor:_tokenExecutor];
_tokenExecutor.fairnessSessionId = _fairnessSessionId;
```

**Unregistration point:** In `setEnabled:NO` (line 212):

```objc
if (!enabled) {
    // NEW: Unregister BEFORE clearing delegate
    // This also calls cleanupForUnregistration() on the executor
    // to increment availableSlots for any unconsumed tokens
    [[FairnessScheduler shared] unregisterSessionId:_fairnessSessionId];

    [_commandRangeChangeJoiner invalidate];
    _tokenExecutor.delegate = nil;
    ...
}
```

**TokenExecutor cleanup method (for session close with tokens in queue):**

```swift
// In TokenExecutor.swift
@objc func cleanupForUnregistration() {
    // Increment availableSlots for each unconsumed TokenArray
    // to prevent accounting drift
    let unconsumedCount = tokenQueue.discardAllAndReturnCount()
    if unconsumedCount > 0 {
        iTermAtomicInt64Add(availableSlots, Int64(unconsumedCount))
    }
}
```

This ensures that if a session is closed while tokens are still queued, the `availableSlots` counter returns to its initial value (no drift).

### Legacy Removal: activeSessionsWithTokens

**What it does today (TokenExecutor.swift:768):**
```swift
if isBackgroundSession && !Self.activeSessionsWithTokens.value.isEmpty {
    // Avoid blocking the active session. If there were multiple mutation threads this
    // would be unnecessary.
    DLog("Stop processing early because active session has tokens")
    return false
}
```

Background sessions check if any foreground session has pending tokens. If so, they stop early to let the foreground session run. This was a workaround for lack of proper scheduling.

**Why it's no longer needed:**
- FairnessScheduler provides equal round-robin for ALL sessions
- Each session gets exactly one turn before others
- No session can monopolize execution regardless of foreground/background
- The original comment even notes "If there were multiple mutation threads this would be unnecessary" - fairness scheduling is the proper solution

**What to remove:**

```swift
// REMOVE: Static set tracking foreground sessions with tokens
private static var activeSessionsWithTokens = MutableAtomicObject<Set<ObjectIdentifier>>(Set())

// REMOVE: In isBackgroundSession didSet - the set manipulation
if isBackgroundSession {
    Self.activeSessionsWithTokens.mutableAccess { set in
        set.remove(ObjectIdentifier(self))
    }
}

// REMOVE: In deinit - the set cleanup
Self.activeSessionsWithTokens.mutableAccess { set in
    set.remove(ObjectIdentifier(self))
}

// REMOVE: In reallyAddTokens - adding to set
if !isBackgroundSession {
    Self.activeSessionsWithTokens.mutableAccess { set in
        set.insert(ObjectIdentifier(self))
    }
}

// REMOVE: In execute() - removing from set when drained
if !isBackgroundSession && tokenQueue.isEmpty {
    DLog("Active session completely drained")
    Self.activeSessionsWithTokens.mutableAccess { set in
        set.remove(ObjectIdentifier(self))
    }
}

// REMOVE: In executeTokenGroups - the early exit check
if isBackgroundSession && !Self.activeSessionsWithTokens.value.isEmpty {
    DLog("Stop processing early because active session has tokens")
    return false
}
```

**What stays:**
- `isBackgroundSession` property - still used for side effect cadence (30fps vs 1fps)
- `sideEffectScheduler.period` adjustment - unrelated to token execution fairness

**(see: testing.md:Checkpoint 2)** — TokenExecutor tests must pass before proceeding to PTYTask changes.

### 5. TaskNotifier Changes

**Location:** `sources/TaskNotifier.m`

**All tasks still register** with TaskNotifier for:
- Deadpool/waitpid handling (reaping zombie processes)
- Coprocess FD handling (if task has coprocess)
- Process lifecycle management

**What changes:**
- PTY tasks with valid FD (`fd >= 0`): Skip adding FD to select() sets
- These tasks use dispatch_source instead for read/write
- Condition: `if (fd >= 0 && ![task useDispatchSource])` → skip FD_SET

**What stays the same:**
- Tmux tasks (`fd < 0`): Already skipped at line 291, no change needed
- Coprocess FDs: Still in select() for ALL tasks (including PTY tasks with coprocesses)
- Unblock pipe: Stays in select()
- Deadpool/waitpid: Unchanged

**PTY write handling migration:**
- Currently: TaskNotifier monitors PTY FDs for write-readiness, calls `processWrite`
- After: PTYTask owns a `DISPATCH_SOURCE_TYPE_WRITE` source
- Write source starts suspended, resumed when `writeBuffer` has data
- `writeBufferDidChange` replaces `[[TaskNotifier sharedInstance] unblock]` for PTY tasks

**New protocol method (@optional to avoid ripple):**
```objc
// In iTermTask protocol - add to @optional section
@optional
- (BOOL)useDispatchSource;  // YES for PTY tasks using new model
                            // Default (not implemented): NO - use select()
```

**TaskNotifier change - use respondsToSelector:**
```objc
// In TaskNotifier.m, inside the task iteration loop
int fd = [task fd];
if (fd < 0) {
    // No FD (e.g., tmux task) - skip FD handling
    continue;
}

// Check if task uses dispatch_source (optional method)
BOOL usesDispatchSource = NO;
if ([task respondsToSelector:@selector(useDispatchSource)]) {
    usesDispatchSource = [task useDispatchSource];
}

if (usesDispatchSource) {
    // Skip FD_SET - this task handles I/O via dispatch_source
    // Still iterate for coprocess handling below
} else {
    // Legacy path - add to select() sets
    if ([task wantsRead]) {
        FD_SET(fd, &rfds);
    }
    if ([task wantsWrite]) {
        FD_SET(fd, &wfds);
    }
    FD_SET(fd, &efds);
}
// Coprocess handling continues for ALL tasks...
```

**Benefits of @optional:**
- No changes needed to existing iTermTask conformers (TmuxTaskWrapper, etc.)
- Default behavior (not implemented) = NO = use select() = backwards compatible
- Only PTYTask implements the method to return YES

The select() loop changes from handling all FDs to:
1. Unblock pipe (always)
2. Coprocess FDs (for any task with coprocess)
3. Tasks where `useDispatchSource` returns NO or is not implemented

**Future consideration: Eliminate TaskNotifier entirely**

The deadpool/waitpid handling could be replaced with `DISPATCH_SOURCE_TYPE_PROC`:

```objc
// Per-process dispatch_source for reaping
dispatch_source_t procSource = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    pid,
    DISPATCH_PROC_EXIT,
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

dispatch_source_set_event_handler(procSource, ^{
    int status;
    waitpid(pid, &status, WNOHANG);
    // Handle process exit...
    dispatch_source_cancel(procSource);
});
dispatch_resume(procSource);
```

This would allow complete elimination of TaskNotifier in a future phase. However, this is out of scope for Phase 1 to minimize risk.

**(see: testing.md:Checkpoint 4)** — TaskNotifier tests must pass before proceeding to full integration.

## Files to Modify

| File | Changes |
|------|---------|
| `sources/FairnessScheduler.swift` | **NEW** - Round-robin scheduler with `busyList`/`busySet`, stable `SessionID` counter, `cleanupForUnregistration()` support |
| `sources/PTYTask.m` | Add read/write dispatch_sources, `setupDispatchSources` (after fd valid), `teardownDispatchSources` (resume-before-cancel), unified state check (`shouldRead`/`shouldWrite` predicates, `updateReadSourceState`/`updateWriteSourceState`), hook `setPaused:` to call state updates, `writeBufferDidChange` |
| `sources/PTYTask.h` | Declare `updateReadSourceState`, `updateWriteSourceState`, `useDispatchSource` |
| `sources/TokenExecutor.swift` | Remove semaphore blocking (and semaphore creation), update `onSemaphoreSignaled` callback to always run + call `backpressureReleaseHandler`, add `executeTurn()`, `notifyScheduler()`, `backpressureReleaseHandler` closure, `fairnessSessionId` property, `cleanupForUnregistration()`, **remove `activeSessionsWithTokens` foreground preemption** |
| `sources/VT100ScreenMutableState.m` | Register/unregister with FairnessScheduler in init and setEnabled:NO, store `_fairnessSessionId`, add re-kick in `setTerminalEnabled:` |
| `sources/TokenArray.swift` | No changes needed - existing `onSemaphoreSignaled` callback mechanism is reused |
| `sources/PTYSession.m` | Wire `backpressureReleaseHandler`, convert `taskDidChangePaused:` and `shortcutNavigationDidComplete` to use `mutateAsynchronously` with `scheduleTokenExecution` |
| `sources/TaskNotifier.m` | Skip FD_SET for tasks with `useDispatchSource`, keep select() for coprocess FDs + deadpool |
| `sources/iTermTask.h` | Add `useDispatchSource` as @optional method (no ripple to existing conformers) |
| `sources/TwoTierTokenQueue.swift` | Add `discardAllAndReturnCount()` method for cleanup accounting |

## What Doesn't Change

| Component | Why |
|-----------|-----|
| `TwoTierTokenQueue` | Per-session high-priority handling is already correct |
| High-priority token paths | Triggers, API injection work correctly within session turns |
| `availableSlots` / `backpressureLevel` | Already exists in this branch; used for non-blocking admission control |
| Side effects system | Unrelated to fairness |
| Mutation queue | Still single-threaded; fairness is about who gets to use it |

## What Changes

| Component | From | To |
|-----------|------|-----|
| PTY reading | TaskNotifier select() loop | Per-PTY DISPATCH_SOURCE_TYPE_READ |
| PTY writing | TaskNotifier select() loop | Per-PTY DISPATCH_SOURCE_TYPE_WRITE |
| Backpressure mechanism | semaphore.wait() blocks caller | Unified state check (`shouldRead`/`shouldWrite`) controls dispatch_source suspend/resume |
| TokenExecutor semaphore | Created and used for blocking | **Removed entirely** - no longer needed |
| Foreground preemption | `activeSessionsWithTokens` lets foreground interrupt background | **Removed** - FairnessScheduler provides equal round-robin |
| Execution control | Unbounded per session | FairnessScheduler grants bounded turns |
| Read state management | Implicit via select() polling `wantsRead` | Explicit via `updateReadSourceState()` called when ANY condition changes (backpressure, paused, ioAllowed) |
| Write state management | Implicit via select() polling `wantsWrite` | Explicit via `updateWriteSourceState()` called when ANY condition changes (paused, isReadOnly, writeBuffer, ioAllowed) |

## Migration Strategy

### Phase 1: Core Fairness (This Work)
1. Add FairnessScheduler
2. Migrate PTYTask to dispatch_source
3. Shrink TaskNotifier to coprocess-only (keeps select() for coprocess FDs + deadpool)
4. Feature flag for rollback

### Phase 2: Coprocess Fairness (Future)
1. Migrate coprocesses to dispatch_source
2. Integrate coprocess I/O into fairness system
3. Remove TaskNotifier entirely

## Verification

1. **Fairness test:** Run `yes` in one tab, interactive shell in another. Verify interactive shell stays responsive.
2. **High-priority test:** Verify triggers still fire synchronously during token execution.
3. **Backpressure test:** Verify high-throughput sessions get suspended/resumed correctly.
4. **Performance:** Compare throughput to current system (should be similar or better).

### Accounting Invariant Check

**Critical:** If `availableSlots` drifts, readers will stall (too low) or overflow (too high).

Add debug assertion:
```swift
// At steady state (no tokens in flight):
assert(availableSlots == totalSlots, "Accounting drift detected")
```

**Test scenarios for accounting correctness:**
- Normal PTY flow: enqueue N arrays, consume N arrays → availableSlots unchanged
- API injection: inject, consume → unchanged
- Trigger re-injection during execution: inject, consume in same turn → unchanged
- Session close with tokens in queue: cleanup must increment for unconsumed tokens
- Error paths: any cleanup/discard must increment

**(see: testing.md:Checkpoint 5)** — All integration tests and accounting invariant tests must pass before merge.

## Design Decisions

1. **Token budget (heuristic):** Start with ~500 tokens per turn. This is a tunable heuristic, not a hard bound:
   - Enforced at group boundaries (may overshoot by one group)
   - A group with 1000 tokens still executes fully if it's first
   - The goal is approximate fairness, not precise metering
   - Tune empirically based on latency vs. throughput tradeoffs
2. **Background sessions:** Equal round-robin with foreground. No special treatment. Tune later if needed.
3. **Coprocess handling:** Keep on select() for Phase 1. TaskNotifier shrinks to manage only: unblock pipe + coprocess FDs + deadpool/waitpid. Migrate to dispatch_source in future Phase 2.

### Coprocess Analysis

Coprocesses are external processes that filter terminal I/O (rare, advanced feature). Key findings:

- **Hybrid viable:** Coprocesses can stay on select() while PTYs move to dispatch_source
- **Starvation risk:** Coprocesses bypass the token queue (direct to writeBuffer), but low severity in practice due to low throughput
- **Future work:** Full migration to dispatch_source + fairness integration deferred to Phase 2
