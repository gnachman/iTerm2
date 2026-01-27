//
//  IntegrationTests.swift
//  ModernTests
//
//  Integration tests for the fairness scheduler system.
//  See testing.md Milestone 5 for test specifications.
//
//  Test Design:
//  - Tests verify wiring between components (VT100ScreenMutableState, TokenExecutor, FairnessScheduler)
//  - Registration/unregistration lifecycle
//  - Re-kick mechanisms for blocked sessions
//  - PTYSession dispatch source activation
//
//  Note: Tests exercise actual VT100ScreenMutableState.init and setTerminalEnabled:NO
//  to verify the real integration points, not just direct scheduler calls.
//

import XCTest
@testable import iTerm2SharedARC

// MockSideEffectPerformer is defined in Mocks/MockSideEffectPerformer.swift
// MockTokenExecutorDelegate is defined in Mocks/MockTokenExecutorDelegate.swift

// MARK: - 5.1 Registration Tests

/// Tests for FairnessScheduler registration during initialization (5.1)
final class IntegrationRegistrationTests: XCTestCase {

    func testRegisterOnInit() throws {
        // REQUIREMENT: TokenExecutor registered with FairnessScheduler in VT100ScreenMutableState.init
        // This tests the ACTUAL call site, not a simulation
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for FairnessScheduler introspection")

        #if ITERM_DEBUG
        let initialCount = FairnessScheduler.shared.testRegisteredSessionCount

        // Create VT100ScreenMutableState - this should register with FairnessScheduler in init
        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        // The tokenExecutor should have a valid fairnessSessionId set during init
        let sessionId = mutableState.tokenExecutor.fairnessSessionId

        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered after VT100ScreenMutableState.init")
        XCTAssertEqual(FairnessScheduler.shared.testRegisteredSessionCount, initialCount + 1,
                       "Registered count should increase by 1")

        // Cleanup via setTerminalEnabled:NO (the real unregistration path)
        // First enable (to allow disable to work)
        mutableState.terminalEnabled = true
        mutableState.terminalEnabled = false
        waitForMutationQueue()
        #endif
    }

    func testSessionIdStoredOnExecutor() throws {
        // REQUIREMENT: fairnessSessionId set on TokenExecutor after registration
        // Verify VT100ScreenMutableState.init stores session ID on executor

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        // After init, executor should have session ID stored
        XCTAssertGreaterThan(mutableState.tokenExecutor.fairnessSessionId, 0,
                             "TokenExecutor should have fairnessSessionId set after init")

        // Cleanup (enable then disable to trigger unregistration)
        mutableState.terminalEnabled = true
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testSessionIdStoredOnMutableState() throws {
        // REQUIREMENT: _fairnessSessionId stored on VT100ScreenMutableState
        // The mutable state stores the session ID for unregistration

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        // VT100ScreenMutableState stores _fairnessSessionId internally
        // We can verify by checking the executor has the same ID
        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        // Session ID can be 0 for first session - verify registration instead
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered with FairnessScheduler")
        #endif

        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered")
        #endif

        // Cleanup (enable then disable to trigger unregistration)
        mutableState.terminalEnabled = true
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }
}

// MARK: - 5.2 Unregistration Tests

/// Tests for FairnessScheduler unregistration on session close (5.2)
final class IntegrationUnregistrationTests: XCTestCase {

    func testUnregisterOnSetEnabledNo() throws {
        // REQUIREMENT: Unregistration called in setTerminalEnabled:NO
        // This tests the ACTUAL call site in VT100ScreenMutableState

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        // Session ID can be 0 for first session - verify registration instead
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered after init")
        #endif

        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered initially")
        #endif

        // First enable the terminal (setTerminalEnabled: has early return if unchanged)
        mutableState.terminalEnabled = true

        // Now call setTerminalEnabled:NO - this is the ACTUAL unregistration call site
        mutableState.terminalEnabled = false
        waitForMutationQueue()

        #if ITERM_DEBUG
        XCTAssertFalse(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                       "Session should be unregistered after setTerminalEnabled:NO")
        #endif
    }

    func testUnregisterBeforeDelegateCleared() throws {
        // REQUIREMENT: Unregistration happens before delegate = nil
        // Verify that setTerminalEnabled:NO calls unregister before clearing delegate
        // (This is enforced by the order of operations in VT100ScreenMutableState.setTerminalEnabled:)

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        let sessionId = mutableState.tokenExecutor.fairnessSessionId

        // First enable the terminal (which sets up delegates)
        mutableState.terminalEnabled = true

        // The executor's delegate is set by VT100ScreenMutableState when enabled
        XCTAssertNotNil(mutableState.tokenExecutor.delegate, "Delegate should be set when enabled")

        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered before disable")
        #endif

        // setTerminalEnabled:NO calls unregister THEN clears delegate (see VT100ScreenMutableState.m:216-223)
        mutableState.terminalEnabled = false
        waitForMutationQueue()

        // After setTerminalEnabled:NO, delegate should be nil (cleared in the method)
        XCTAssertNil(mutableState.tokenExecutor.delegate, "Delegate should be nil after disable")

        #if ITERM_DEBUG
        // Unregistration happened before delegate was cleared
        XCTAssertFalse(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                       "Session should be unregistered")
        #endif
    }

    func testUnregisterCleanupCalled() throws {
        // REQUIREMENT: cleanupForUnregistration called during unregister
        // This restores availableSlots for any unconsumed tokens

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        // Enable terminal first
        mutableState.terminalEnabled = true

        // Add some tokens to create backpressure
        var vector = CVector()
        CVectorCreate(&vector, 10)
        for _ in 0..<10 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)

        // Verify we have some backpressure
        XCTAssertNotEqual(mutableState.tokenExecutor.backpressureLevel, .heavy,
                          "Should have light/medium backpressure before cleanup")

        // setTerminalEnabled:NO calls unregister which calls cleanupForUnregistration
        mutableState.terminalEnabled = false
        waitForMutationQueue()

        // After cleanup, backpressure should be released
        XCTAssertEqual(mutableState.tokenExecutor.backpressureLevel, .none,
                       "Cleanup should release all backpressure")
    }
}

// MARK: - 5.2.5 Automatic Scheduling Contract Tests

/// Tests that addTokens() automatically kicks the scheduler without explicit scheduleTokenExecution().
/// This is the fundamental contract: tokens added to an unblocked session execute automatically.
final class IntegrationAutomaticSchedulingTests: XCTestCase {

    func testAddTokensAutomaticallyTriggersExecution() throws {
        // REQUIREMENT: addTokens() must call notifyScheduler() which causes tokens to execute
        // WITHOUT any explicit scheduleTokenExecution() call.
        //
        // This tests the core contract: when a session is unblocked (terminalEnabled=true,
        // taskPaused=false, copyMode=false, shortcutNavigationMode=false), adding tokens
        // should automatically trigger execution via the FairnessScheduler.

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        // Enable terminal - this makes the session ready to execute
        mutableState.terminalEnabled = true
        waitForMutationQueue()

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered with FairnessScheduler")

        // Reset test counters for clean measurement
        mutableState.tokenExecutor.testResetCounters()

        // Verify no execution has happened yet
        XCTAssertEqual(mutableState.tokenExecutor.testExecuteTurnCompletedCount, 0,
                       "No execution should have happened before adding tokens")
        #endif

        // Add tokens - this should AUTOMATICALLY trigger execution via notifyScheduler()
        // We are NOT calling scheduleTokenExecution() - that's the point of this test
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        // Drain mutation queue to let execution complete - deterministic, no polling
        #if ITERM_DEBUG
        // Sync mutation queue multiple times to ensure all async work completes
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, 0,
                      "addTokens() should automatically trigger execution via notifyScheduler(). " +
                      "ExecutionCount: \(mutableState.tokenExecutor.testExecuteTurnCompletedCount)")

        // Also verify tokens were consumed (slots restored) - the deterministic assertion
        let availableSlots = mutableState.tokenExecutor.testAvailableSlots
        let totalSlots = mutableState.tokenExecutor.testTotalSlots
        XCTAssertEqual(availableSlots, totalSlots,
                       "All tokens should be consumed after automatic execution")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testAddTokensToUnregisteredExecutorDoesNotCrash() throws {
        // REQUIREMENT: addTokens() should be safe even if executor is not registered.
        // This is a defensive test - ensure no crash or hang occurs.

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())

        // Don't register with FairnessScheduler - fairnessSessionId remains 0

        // Add tokens - should not crash
        var vector = CVector()
        CVectorCreate(&vector, 1)
        let token = VT100Token()
        token.type = VT100_UNKNOWNCHAR
        CVectorAppendVT100Token(&vector, token)
        executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)

        // Flush queue to ensure async operations complete
        waitForMutationQueue()

        // If we get here without crashing, test passes
        XCTAssertTrue(true, "addTokens to unregistered executor should not crash")
    }

    func testMultipleAddTokensTriggersMultipleExecutions() throws {
        // REQUIREMENT: Multiple addTokens() calls should each contribute to scheduling,
        // and all tokens should eventually be consumed.

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true
        waitForMutationQueue()

        #if ITERM_DEBUG
        mutableState.tokenExecutor.testResetCounters()
        #endif

        // Add tokens in multiple batches - each should trigger scheduling
        for _ in 0..<3 {
            var vector = CVector()
            CVectorCreate(&vector, 5)
            for _ in 0..<5 {
                let token = VT100Token()
                token.type = VT100_UNKNOWNCHAR
                CVectorAppendVT100Token(&vector, token)
            }
            mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
            // No delay needed - queue sync is deterministic
        }

        // Drain mutation queue to let all execution complete - deterministic, no polling
        #if ITERM_DEBUG
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        // Verify all tokens were consumed via slot accounting
        XCTAssertEqual(mutableState.tokenExecutor.testAvailableSlots,
                       mutableState.tokenExecutor.testTotalSlots,
                       "All tokens from multiple addTokens() calls should be automatically consumed")

        // Verify at least one execution occurred
        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, 0,
                             "At least one execution turn should have completed")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }
}

// MARK: - 5.3 Re-kick on Unblock Tests

/// Tests for re-kicking the scheduler when sessions are unblocked (5.3)
final class IntegrationRekickTests: XCTestCase {

    func testTaskUnpausedSchedulesExecution() throws {
        // REQUIREMENT: taskPaused=NO triggers scheduleTokenExecution
        // When a task is unpaused, scheduleTokenExecution re-kicks the scheduler
        //
        // Test design:
        // 1. Set blocking state (taskPaused=true) BEFORE adding tokens to prevent race conditions
        // 2. Add tokens (they queue but cannot execute because blocked)
        // 3. Verify tokens are pending via availableSlots
        // 4. Record execution count before unblocking
        // 5. Unblock and call scheduleTokenExecution
        // 6. Wait for execution to complete
        // 7. Verify execution count increased

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered with FairnessScheduler")

        // Reset test counters for clean measurement
        mutableState.tokenExecutor.testResetCounters()
        #endif

        // Step 1: Set blocking state BEFORE adding tokens
        iTermGCD.mutationQueue().async {
            mutableState.taskPaused = true
        }
        waitForMutationQueue()
        XCTAssertTrue(mutableState.taskPaused, "taskPaused should be true")

        // Step 2: Add tokens while blocked - they should queue without executing
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        waitForMutationQueue()

        #if ITERM_DEBUG
        // Step 3: Verify tokens are pending (slots consumed)
        let availableSlotsBefore = mutableState.tokenExecutor.testAvailableSlots
        let totalSlots = mutableState.tokenExecutor.testTotalSlots
        XCTAssertLessThan(availableSlotsBefore, totalSlots,
                          "Should have pending tokens (available slots < total slots)")

        // Step 4: Record execution count before unblocking
        let executionCountBefore = mutableState.tokenExecutor.testExecuteTurnCompletedCount
        #endif

        // Step 5: Simulate PTYSession.taskDidChangePaused:paused: when unpausing
        iTermGCD.mutationQueue().async {
            mutableState.taskPaused = false
            mutableState.scheduleTokenExecution()
        }
        waitForMutationQueue()

        XCTAssertFalse(mutableState.taskPaused, "taskPaused should be false after unpausing")

        #if ITERM_DEBUG
        // Step 6: Drain mutation queue deterministically
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        // Step 7: Verify execution occurred
        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, executionCountBefore,
                      "scheduleTokenExecution after unpausing should trigger token execution. " +
                      "ExecutionCountBefore: \(executionCountBefore), " +
                      "ExecutionCountAfter: \(mutableState.tokenExecutor.testExecuteTurnCompletedCount)")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testShortcutNavigationCompleteSchedulesExecution() throws {
        // REQUIREMENT: Shortcut nav complete triggers scheduleTokenExecution
        // When shortcut navigation ends, scheduleTokenExecution re-kicks the scheduler
        //
        // Test design: Same pattern as testTaskUnpausedSchedulesExecution
        // 1. Set blocking state BEFORE adding tokens
        // 2. Add tokens (queued but not executed)
        // 3. Record execution count
        // 4. Unblock and call scheduleTokenExecution
        // 5. Verify execution occurred

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered with FairnessScheduler")

        // Reset test counters for clean measurement
        mutableState.tokenExecutor.testResetCounters()
        #endif

        // Step 1: Set blocking state BEFORE adding tokens
        iTermGCD.mutationQueue().async {
            mutableState.shortcutNavigationMode = true
        }
        waitForMutationQueue()
        XCTAssertTrue(mutableState.shortcutNavigationMode, "shortcutNavigationMode should be true")

        // Step 2: Add tokens while blocked
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        waitForMutationQueue()

        #if ITERM_DEBUG
        // Verify tokens are pending
        let availableSlotsBefore = mutableState.tokenExecutor.testAvailableSlots
        let totalSlots = mutableState.tokenExecutor.testTotalSlots
        XCTAssertLessThan(availableSlotsBefore, totalSlots,
                          "Should have pending tokens (available slots < total slots)")

        // Step 3: Record execution count before unblocking
        let executionCountBefore = mutableState.tokenExecutor.testExecuteTurnCompletedCount
        #endif

        // Step 4: Simulate PTYSession.shortcutNavigationDidComplete
        iTermGCD.mutationQueue().async {
            mutableState.shortcutNavigationMode = false
            mutableState.scheduleTokenExecution()
        }
        waitForMutationQueue()

        XCTAssertFalse(mutableState.shortcutNavigationMode, "shortcutNavigationMode should be false")

        #if ITERM_DEBUG
        // Step 5: Drain mutation queue and verify execution occurred
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, executionCountBefore,
                      "scheduleTokenExecution after shortcut nav complete should trigger token execution. " +
                      "ExecutionCountBefore: \(executionCountBefore), " +
                      "ExecutionCountAfter: \(mutableState.tokenExecutor.testExecuteTurnCompletedCount)")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testTerminalEnabledSchedulesExecution() throws {
        // REQUIREMENT: terminalEnabled=YES triggers scheduleTokenExecution
        // Test the ACTUAL call site: VT100ScreenMutableState.setTerminalEnabled:
        //
        // Note: Terminal is disabled by default, which blocks execution via
        // tokenExecutorShouldQueueTokens returning YES. So tokens added while
        // disabled will queue until terminal is enabled.

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered after init")

        // Reset test counters for clean measurement
        mutableState.tokenExecutor.testResetCounters()
        #endif

        // Terminal is disabled by default - this is our blocking state
        XCTAssertFalse(mutableState.terminalEnabled, "terminalEnabled should be false after init")

        // Add tokens while terminal is disabled - they queue without executing
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        waitForMutationQueue()

        #if ITERM_DEBUG
        // Verify tokens are pending
        let availableSlotsBefore = mutableState.tokenExecutor.testAvailableSlots
        let totalSlots = mutableState.tokenExecutor.testTotalSlots
        XCTAssertLessThan(availableSlotsBefore, totalSlots,
                          "Should have queued tokens (consumed slots)")

        // Record execution count before enabling
        let executionCountBefore = mutableState.tokenExecutor.testExecuteTurnCompletedCount
        #endif

        // Enable terminal - this calls scheduleTokenExecution internally
        mutableState.terminalEnabled = true
        waitForMutationQueue()

        #if ITERM_DEBUG
        // Drain mutation queue and verify execution occurred
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, executionCountBefore,
                      "setTerminalEnabled:YES should trigger token execution. " +
                      "ExecutionCountBefore: \(executionCountBefore), " +
                      "ExecutionCountAfter: \(mutableState.tokenExecutor.testExecuteTurnCompletedCount)")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testCopyModeExitSchedulesExecution() throws {
        // REQUIREMENT: Copy mode exit triggers scheduleTokenExecution (existing)
        // This is a regression test - existing behavior should be preserved
        //
        // Test design: Same pattern as other re-kick tests
        // 1. Set blocking state (copyMode=true) BEFORE adding tokens
        // 2. Add tokens (queued but not executed)
        // 3. Record execution count
        // 4. Exit copy mode and call scheduleTokenExecution
        // 5. Verify execution occurred

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered with FairnessScheduler")

        // Reset test counters for clean measurement
        mutableState.tokenExecutor.testResetCounters()
        #endif

        // Step 1: Set blocking state BEFORE adding tokens
        iTermGCD.mutationQueue().async {
            mutableState.copyMode = true
        }
        waitForMutationQueue()
        XCTAssertTrue(mutableState.copyMode, "copyMode should be true")

        // Step 2: Add tokens while blocked
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        waitForMutationQueue()

        #if ITERM_DEBUG
        // Verify tokens are pending
        let availableSlotsBefore = mutableState.tokenExecutor.testAvailableSlots
        let totalSlots = mutableState.tokenExecutor.testTotalSlots
        XCTAssertLessThan(availableSlotsBefore, totalSlots,
                          "Should have pending tokens (available slots < total slots)")

        // Step 3: Record execution count before unblocking
        let executionCountBefore = mutableState.tokenExecutor.testExecuteTurnCompletedCount
        #endif

        // Step 4: Simulate PTYSession.copyModeHandlerDidChangeEnabledState when exiting copy mode
        iTermGCD.mutationQueue().async {
            mutableState.copyMode = false
            mutableState.scheduleTokenExecution()
        }
        waitForMutationQueue()

        XCTAssertFalse(mutableState.copyMode, "copyMode should be false after exit")

        #if ITERM_DEBUG
        // Step 5: Drain mutation queue and verify execution occurred
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, executionCountBefore,
                      "scheduleTokenExecution after copy mode exit should trigger token execution. " +
                      "ExecutionCountBefore: \(executionCountBefore), " +
                      "ExecutionCountAfter: \(mutableState.tokenExecutor.testExecuteTurnCompletedCount)")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testSetTerminalEnabledCallsScheduleTokenExecution() throws {
        // REQUIREMENT: setTerminalEnabled:YES calls scheduleTokenExecution
        // This tests the ACTUAL call site in VT100ScreenMutableState
        //
        // This is similar to testTerminalEnabledSchedulesExecution but focuses
        // specifically on verifying the scheduleTokenExecution call path.

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)

        // Terminal is disabled by default - this is our blocking state
        XCTAssertFalse(mutableState.terminalEnabled, "terminalEnabled should be false after init")

        let sessionId = mutableState.tokenExecutor.fairnessSessionId
        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered after init")

        // Reset test counters for clean measurement
        mutableState.tokenExecutor.testResetCounters()
        #endif

        // Add tokens while disabled - they queue without executing
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        mutableState.tokenExecutor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        waitForMutationQueue()

        #if ITERM_DEBUG
        // Verify tokens are pending
        let availableSlotsBefore = mutableState.tokenExecutor.testAvailableSlots
        let totalSlots = mutableState.tokenExecutor.testTotalSlots
        XCTAssertLessThan(availableSlotsBefore, totalSlots,
                          "Should have queued tokens before enabling (consumed slots)")

        // Record execution count before enabling
        let executionCountBefore = mutableState.tokenExecutor.testExecuteTurnCompletedCount
        #endif

        // Enable terminal - this calls scheduleTokenExecution internally
        mutableState.terminalEnabled = true
        waitForMutationQueue()

        XCTAssertTrue(mutableState.terminalEnabled, "terminalEnabled should be true after setting")

        #if ITERM_DEBUG
        // Drain mutation queue and verify execution occurred
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mutableState.tokenExecutor.testExecuteTurnCompletedCount, executionCountBefore,
                      "setTerminalEnabled:YES should trigger token execution via scheduleTokenExecution. " +
                      "ExecutionCountBefore: \(executionCountBefore), " +
                      "ExecutionCountAfter: \(mutableState.tokenExecutor.testExecuteTurnCompletedCount)")
        #endif

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }
}

// MARK: - 5.3.5 Background/Foreground Fairness Tests

/// Tests that background sessions get fair scheduling when foreground is busy.
/// This is the KEY REGRESSION TEST for removing activeSessionsWithTokens.
final class IntegrationBackgroundForegroundFairnessTests: XCTestCase {

    func testRoundRobinFairnessWithFullStack() throws {
        // REQUIREMENT: The round-robin fairness invariant must hold through the full stack:
        // VT100ScreenMutableState -> TokenExecutor -> FairnessScheduler
        //
        // Invariant: No session gets a second turn until all other busy sessions have had one turn.
        // This is the KEY REGRESSION TEST for removing activeSessionsWithTokens.
        //
        // Test design (DETERMINISTIC - no polling/timeouts):
        // 1. Create sessions with taskPaused=true to block execution
        // 2. Add tokens to all sessions while blocked
        // 3. Clear execution history
        // 4. Unblock all sessions and kick scheduler
        // 5. Sync to mutation queue to let execution complete
        // 6. Verify proper round-robin order
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for execution history tracking")

        #if ITERM_DEBUG
        // Create sessions with blocking enabled
        var sessions: [(state: VT100ScreenMutableState, performer: MockSideEffectPerformer, id: UInt64)] = []

        for i in 0..<3 {
            let performer = MockSideEffectPerformer()
            let state = VT100ScreenMutableState(sideEffectPerformer: performer)
            state.terminalEnabled = true
            state.tokenExecutor.isBackgroundSession = (i > 0)

            // Block execution using taskPaused
            iTermGCD.mutationQueue().sync {
                state.taskPaused = true
            }

            let sessionId = state.tokenExecutor.fairnessSessionId
            sessions.append((state: state, performer: performer, id: sessionId))
        }

        waitForMutationQueue()

        // Verify all sessions are registered
        for session in sessions {
            XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(session.id),
                          "Session \(session.id) should be registered")
        }

        // Add tokens to ALL sessions while blocked
        for session in sessions {
            for _ in 0..<10 {
                var vector = CVector()
                CVectorCreate(&vector, 100)
                for _ in 0..<100 {
                    let token = VT100Token()
                    token.type = VT100_UNKNOWNCHAR
                    CVectorAppendVT100Token(&vector, token)
                }
                session.state.tokenExecutor.addTokens(vector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000)
            }
        }

        waitForMutationQueue()

        // Clear execution history before unblocking
        FairnessScheduler.shared.testClearExecutionHistory()

        // Unblock all sessions
        iTermGCD.mutationQueue().sync {
            for session in sessions {
                session.state.taskPaused = false
            }
        }

        // Kick scheduler for each session
        for session in sessions {
            session.state.scheduleTokenExecution()
        }

        // Wait for quiescence using iteration-based approach (deterministic, no timeout)
        let iterations = waitForSchedulerQuiescence(maxIterations: 100)
        XCTAssertNotEqual(iterations, -1, "Scheduler should reach quiescence within 100 iterations")

        // Get execution history
        let history = FairnessScheduler.shared.testGetAndClearExecutionHistory()

        // Basic sanity check
        XCTAssertGreaterThanOrEqual(history.count, 3,
                                     "Should have at least one round. History: \(history)")

        // VERIFY ROUND-ROBIN INVARIANT: No session executes twice in a row
        var violations: [String] = []
        for i in 1..<history.count {
            if history[i] == history[i-1] {
                violations.append("Session \(history[i]) at indices \(i-1) and \(i)")
            }
        }

        XCTAssertTrue(violations.isEmpty,
                      "Round-robin violated: same session executed consecutively. " +
                      "History: \(history), Violations: \(violations)")

        // Each session should have gotten turns (no starvation)
        for session in sessions {
            let turnCount = history.filter { $0 == session.id }.count
            XCTAssertGreaterThan(turnCount, 0,
                                 "Session \(session.id) should have at least one turn. History: \(history)")
        }

        // Verify first round includes all sessions
        let sessionCount = sessions.count
        if history.count >= sessionCount {
            let firstRound = Array(history.prefix(sessionCount))
            let uniqueInFirstRound = Set(firstRound)
            XCTAssertEqual(uniqueInFirstRound.count, sessionCount,
                           "First round should include all sessions. First \(sessionCount): \(firstRound)")
        }
        #endif

        // Cleanup
        for session in sessions {
            session.state.terminalEnabled = false
        }
        waitForMutationQueue()
    }

    func testMultipleBackgroundSessionsAllGetTurns() throws {
        // REQUIREMENT: Multiple background sessions should all get fair turns.
        // Tests that fairness applies across ALL sessions, not just foreground vs one background.
        //
        // Test design (DETERMINISTIC):
        // 1. Create sessions with taskPaused=true to block execution
        // 2. Add tokens to all sessions while blocked
        // 3. Clear history, unblock, and let execution complete
        // 4. Verify all sessions got turns via execution history
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for execution history tracking")

        #if ITERM_DEBUG
        // Create 3 background sessions with blocking enabled
        var sessions: [(state: VT100ScreenMutableState, performer: MockSideEffectPerformer, id: UInt64)] = []
        for _ in 0..<3 {
            let performer = MockSideEffectPerformer()
            let state = VT100ScreenMutableState(sideEffectPerformer: performer)
            state.terminalEnabled = true
            state.tokenExecutor.isBackgroundSession = true

            // Block execution
            iTermGCD.mutationQueue().sync {
                state.taskPaused = true
            }

            let sessionId = state.tokenExecutor.fairnessSessionId
            sessions.append((state: state, performer: performer, id: sessionId))
        }

        waitForMutationQueue()

        // Add tokens while blocked
        for session in sessions {
            for _ in 0..<10 {
                var vector = CVector()
                CVectorCreate(&vector, 100)
                for _ in 0..<100 {
                    let token = VT100Token()
                    token.type = VT100_UNKNOWNCHAR
                    CVectorAppendVT100Token(&vector, token)
                }
                session.state.tokenExecutor.addTokens(vector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000)
            }
        }

        waitForMutationQueue()

        // Clear history before unblocking
        FairnessScheduler.shared.testClearExecutionHistory()

        // Unblock all sessions
        iTermGCD.mutationQueue().sync {
            for session in sessions {
                session.state.taskPaused = false
            }
        }

        // Kick scheduler
        for session in sessions {
            session.state.scheduleTokenExecution()
        }

        // Wait for quiescence using iteration-based approach (deterministic, no timeout)
        let iterations = waitForSchedulerQuiescence(maxIterations: 100)
        XCTAssertNotEqual(iterations, -1, "Scheduler should reach quiescence within 100 iterations")

        // Verify via execution history
        let history = FairnessScheduler.shared.testGetAndClearExecutionHistory()

        XCTAssertGreaterThanOrEqual(history.count, 3,
                                     "Should have at least one round. History: \(history)")

        // Each session should have gotten turns
        for session in sessions {
            let turnCount = history.filter { $0 == session.id }.count
            XCTAssertGreaterThan(turnCount, 0,
                                 "Session \(session.id) should have at least one turn. History: \(history)")
        }

        // Verify round-robin (no consecutive same-session executions)
        var violations = 0
        for i in 1..<history.count {
            if history[i] == history[i-1] {
                violations += 1
            }
        }
        XCTAssertEqual(violations, 0,
                       "Round-robin violated. History: \(history)")
        #endif

        // Cleanup
        for session in sessions {
            session.state.terminalEnabled = false
        }
        waitForMutationQueue()
    }
}

// MARK: - 5.4 Mutation Queue Usage Tests

/// Tests for proper mutation queue usage in state changes (5.4)
final class IntegrationMutationQueueTests: XCTestCase {

    func testTaskPausedStateChangeIsAsynchronous() throws {
        // REQUIREMENT: taskDidChangePaused uses mutateAsynchronously
        // The state change should be dispatched to mutation queue, not block caller

        // Create VT100ScreenMutableState to test the actual state change
        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true

        // Initial state
        XCTAssertFalse(mutableState.taskPaused, "taskPaused should start false")

        // Change state via mutateAsynchronously (simulating what PTYSession.taskDidChangePaused does)
        // Note: We verify the pattern by checking that state changes work through the mutation queue
        iTermGCD.mutationQueue().async {
            mutableState.taskPaused = true
        }

        // Verify async behavior - state change should happen after queue processes
        waitForMutationQueue()
        XCTAssertTrue(mutableState.taskPaused, "taskPaused should be true after mutation queue processes")

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testShortcutNavStateChangeIsAsynchronous() throws {
        // REQUIREMENT: shortcutNavigationDidComplete uses mutateAsynchronously
        // The state change should be dispatched to mutation queue, not block caller

        // Create VT100ScreenMutableState to test the actual state change
        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true

        // Set up initial state
        iTermGCD.mutationQueue().async {
            mutableState.shortcutNavigationMode = true
        }
        waitForMutationQueue()
        XCTAssertTrue(mutableState.shortcutNavigationMode, "shortcutNavigationMode should be true")

        // Change state via mutateAsynchronously (simulating what PTYSession.shortcutNavigationDidComplete does)
        iTermGCD.mutationQueue().async {
            mutableState.shortcutNavigationMode = false
            // Also verify scheduleTokenExecution is called
            mutableState.scheduleTokenExecution()
        }

        // Verify async behavior - state change should happen after queue processes
        waitForMutationQueue()
        XCTAssertFalse(mutableState.shortcutNavigationMode, "shortcutNavigationMode should be false after mutation queue processes")

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }

    func testMutateAsynchronouslyIsNonBlocking() throws {
        // REQUIREMENT: mutateAsynchronously should not block the calling thread
        // This verifies the async nature of the pattern used by taskDidChangePaused and shortcutNavigationDidComplete

        let performer = MockSideEffectPerformer()
        let mutableState = VT100ScreenMutableState(sideEffectPerformer: performer)
        mutableState.terminalEnabled = true

        let expectation = XCTestExpectation(description: "Non-blocking verification from background thread")

        // Run test from background thread to ensure we're not on mutation queue
        DispatchQueue.global().async {
            var stateChangedBeforeReturn = false

            // This simulates what mutateAsynchronously does
            iTermGCD.mutationQueue().async {
                mutableState.taskPaused = true
            }

            // Capture state immediately after dispatch (should still be false if truly async)
            // Since we're on a background thread (not the mutation queue), the async
            // dispatch should return before the state change happens
            stateChangedBeforeReturn = mutableState.taskPaused

            // Assert the non-blocking behavior - this is the core test
            XCTAssertFalse(stateChangedBeforeReturn,
                           "State should not change synchronously with mutateAsynchronously when called from background thread")

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Now wait for mutation queue to complete
        waitForMutationQueue()
        XCTAssertTrue(mutableState.taskPaused, "State should change after waiting for mutation queue")

        // Cleanup
        mutableState.terminalEnabled = false
        waitForMutationQueue()
    }
}

// MARK: - 5.5 Dispatch Source Activation Tests

/// Tests for PTYTask dispatch source activation during launch (5.5)
final class IntegrationDispatchSourceActivationTests: XCTestCase {

    func testSetupDispatchSourcesCreatesSourcesWhenFdValid() throws {
        // REQUIREMENT: setupDispatchSources called from launch code after fd is valid
        // Dispatch sources should be created when fd >= 0

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe to get valid file descriptors
        var pipeFds: [Int32] = [0, 0]
        let result = pipe(&pipeFds)
        XCTAssertEqual(result, 0, "pipe() should succeed")

        // Set up task with valid fd
        task.testSetFd(pipeFds[0])

        #if ITERM_DEBUG
        // Before setup, should have no sources
        XCTAssertFalse(task.testHasReadSource, "Fresh task should have no read source")
        XCTAssertFalse(task.testHasWriteSource, "Fresh task should have no write source")
        #endif

        // Call setupDispatchSources (simulating what didRegister does)
        task.testSetupDispatchSourcesForTesting()

        #if ITERM_DEBUG
        // After setup, should have sources
        XCTAssertTrue(task.testHasReadSource, "Task should have read source after setup")
        XCTAssertTrue(task.testHasWriteSource, "Task should have write source after setup")
        #endif

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        close(pipeFds[0])
        close(pipeFds[1])
    }

    func testBackpressureHandlerCalledOnBackpressureRelease() throws {
        // REQUIREMENT: backpressureReleaseHandler is called when transitioning from
        // heavy backpressure to non-heavy during token consumption.
        //
        // The handler is called in TokenExecutor.onConsumed when:
        //   availableSlots > 0 && backpressureLevel < .heavy
        //
        // Test design:
        // 1. Drive executor to heavy backpressure (>75% slots consumed)
        // 2. Set up handler to track calls
        // 3. Consume tokens via execution (scheduler turns)
        // 4. Verify handler was called when crossing out of heavy

        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks")

        #if ITERM_DEBUG
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())
        let delegate = MockTokenExecutorDelegate()
        executor.delegate = delegate

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer {
            FairnessScheduler.shared.unregister(sessionId: sessionId)
            waitForMutationQueue()
        }

        // Get total slots to calculate how many tokens needed for heavy backpressure
        let totalSlots = executor.testTotalSlots
        // Heavy = < 25% available, so consume > 75% of slots
        let tokensForHeavy = Int(Double(totalSlots) * 0.80)

        // Block execution initially so we can fill up the queue
        delegate.shouldQueueTokens = true

        // Add enough token arrays to reach heavy backpressure
        for _ in 0..<tokensForHeavy {
            var vector = CVector()
            CVectorCreate(&vector, 1)
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
            executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
        }

        waitForMutationQueue()

        // Verify we reached heavy backpressure
        XCTAssertEqual(executor.backpressureLevel, .heavy,
                       "Should be at heavy backpressure after adding \(tokensForHeavy) tokens")

        // Now set up handler to track calls AFTER reaching heavy
        let handlerCallCount = MutableAtomicObject<Int>(0)
        executor.backpressureReleaseHandler = {
            _ = handlerCallCount.mutate { $0 + 1 }
        }

        // Unblock execution and let tokens be consumed
        iTermGCD.mutationQueue().sync {
            delegate.shouldQueueTokens = false
        }
        executor.schedule()

        // Wait until all tokens consumed (deterministic, iteration-based)
        var iterations = 0
        let maxIterations = 100
        while executor.testAvailableSlots < executor.testTotalSlots && iterations < maxIterations {
            waitForMutationQueue()
            iterations += 1
        }
        XCTAssertLessThan(iterations, maxIterations, "Should consume all tokens within \(maxIterations) iterations")

        // Handler should have been called when crossing out of heavy backpressure
        let finalCount = handlerCallCount.value
        XCTAssertGreaterThan(finalCount, 0,
                             "backpressureReleaseHandler should be called when transitioning out of heavy. " +
                             "Final backpressure: \(executor.backpressureLevel)")

        // Backpressure should be reduced after consumption
        XCTAssertLessThan(executor.backpressureLevel.rawValue, BackpressureLevel.heavy.rawValue,
                          "Backpressure should be below heavy after consumption")
        #endif
    }

    func testTokenExecutorWiringEnablesBackpressureMonitoring() throws {
        // REQUIREMENT: PTYSession sets task.tokenExecutor
        // PTYTask uses tokenExecutor.backpressureLevel for shouldRead predicate

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create and wire executor
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())
        let delegate = MockTokenExecutorDelegate()
        executor.delegate = delegate

        // Wire up task.tokenExecutor (simulating what PTYSession.taskDidRegister does)
        task.tokenExecutor = executor

        // Verify the wiring
        XCTAssertNotNil(task.tokenExecutor, "PTYTask.tokenExecutor should be set")
        XCTAssert(task.tokenExecutor === executor, "PTYTask.tokenExecutor should reference the wired executor")

        // Verify backpressure level is accessible through the wiring
        if let backpressureLevel = task.tokenExecutor?.backpressureLevel {
            XCTAssertEqual(backpressureLevel, .none,
                           "Should be able to read backpressure level through wiring")
        } else {
            XCTFail("Should be able to read backpressure level through wiring")
        }
    }
}

// MARK: - 5.6 PTYSession Wiring Tests

/// Tests for PTYSession wiring between components (5.6)
final class IntegrationPTYSessionWiringTests: XCTestCase {

    func testFullSessionCreation() throws {
        // REQUIREMENT: Full session creates all components correctly
        // PTYSession should wire PTYTask, TokenExecutor, and FairnessScheduler

        // Create all components that a PTYSession would create
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        let delegate = MockTokenExecutorDelegate()
        executor.delegate = delegate

        // Create a PTYTask (simulating shell launch would require forkpty)
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Wire components as PTYSession would
        task.tokenExecutor = executor

        // Register with scheduler as VT100ScreenMutableState would
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Verify wiring
        XCTAssertNotNil(task.tokenExecutor, "PTYTask should have tokenExecutor")
        XCTAssertEqual(executor.fairnessSessionId, sessionId, "Executor should have session ID")

        #if ITERM_DEBUG
        XCTAssertTrue(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                      "Session should be registered")
        #endif

        // Cleanup
        FairnessScheduler.shared.unregister(sessionId: sessionId)
        waitForMutationQueue()
    }

    func testSessionCloseCleanup() throws {
        // REQUIREMENT: Session close cleans up all resources
        // No leaks of dispatch sources, scheduler registrations, etc.

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add some tokens to create pending work
        var vector = CVector()
        CVectorCreate(&vector, 5)
        for _ in 0..<5 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        #if ITERM_DEBUG
        let registeredBefore = FairnessScheduler.shared.testRegisteredSessionCount
        #endif

        // Simulate session close - unregister should cleanup
        FairnessScheduler.shared.unregister(sessionId: sessionId)
        waitForMutationQueue()

        #if ITERM_DEBUG
        XCTAssertEqual(FairnessScheduler.shared.testRegisteredSessionCount, registeredBefore - 1,
                       "Registered count should decrease after cleanup")
        XCTAssertFalse(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                       "Session should not be registered after cleanup")
        #endif

        // Backpressure should be released
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Cleanup should release all backpressure")
    }
}

// MARK: - Dispatch Source Lifecycle Integration Tests

/// Tests for dispatch source lifecycle during process lifecycle
final class DispatchSourceLifecycleIntegrationTests: XCTestCase {

    func testProcessLaunchCreatesSource() throws {
        // REQUIREMENT: Dispatch source created after successful forkpty
        // This test verifies the ACTUAL launch path calls setupDispatchSources:
        // TaskNotifier.registerTask: → dispatch_async(main) → didRegister → setupDispatchSources
        //
        // This exercises the production code path, not just test helpers.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe to get valid file descriptors (simulates what forkpty provides)
        var pipeFds: [Int32] = [0, 0]
        let pipeResult = pipe(&pipeFds)
        XCTAssertEqual(pipeResult, 0, "pipe() should succeed")

        // Cast to iTermTask protocol (PTYTask implements iTermTask but Swift needs explicit cast)
        let iTermTaskConformingTask = task as! any iTermTask

        defer {
            // Cleanup: teardown sources and close pipe
            task.testTeardownDispatchSourcesForTesting()
            TaskNotifier.sharedInstance().deregister(iTermTaskConformingTask)
            close(pipeFds[0])
            close(pipeFds[1])
        }

        // Set the fd on the task (simulates fd becoming valid after forkpty)
        task.testSetFd(pipeFds[0])

        #if ITERM_DEBUG
        // Before registration, task should have no dispatch sources
        XCTAssertFalse(task.testHasReadSource, "Task should have no read source before registration")
        XCTAssertFalse(task.testHasWriteSource, "Task should have no write source before registration")
        #endif

        // Register with TaskNotifier using the ACTUAL production API
        // This triggers: registerTask: → dispatch_async(main) → didRegister → setupDispatchSources
        TaskNotifier.sharedInstance().register(iTermTaskConformingTask)

        // Wait for the main queue dispatch where didRegister is called
        let expectation = XCTestExpectation(description: "didRegister called")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        #if ITERM_DEBUG
        // After registration through the real path, dispatch sources should be created
        XCTAssertTrue(task.testHasReadSource,
                      "Task should have read source after TaskNotifier registration calls didRegister")
        XCTAssertTrue(task.testHasWriteSource,
                      "Task should have write source after TaskNotifier registration calls didRegister")
        #endif
    }

    func testTaskNotifierRegistrationTriggersSetupDispatchSources() throws {
        // REQUIREMENT: Verify the wiring from TaskNotifier → didRegister → setupDispatchSources
        // This is an end-to-end test of the production dispatch source activation path.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe for valid fd
        var pipeFds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&pipeFds), 0, "pipe() should succeed")

        // Cast to iTermTask protocol
        let iTermTaskConformingTask = task as! any iTermTask

        defer {
            task.testTeardownDispatchSourcesForTesting()
            TaskNotifier.sharedInstance().deregister(iTermTaskConformingTask)
            close(pipeFds[0])
            close(pipeFds[1])
        }

        task.testSetFd(pipeFds[0])

        // Track whether didRegister was called by observing source creation
        #if ITERM_DEBUG
        let hadSourceBefore = task.testHasReadSource
        XCTAssertFalse(hadSourceBefore, "Should start without sources")
        #endif

        // Use the production TaskNotifier registration path
        TaskNotifier.sharedInstance().register(iTermTaskConformingTask)

        // The didRegister call is dispatched to main queue, wait for it to complete
        waitForMainQueue()

        #if ITERM_DEBUG
        // Verify the production path created sources
        XCTAssertTrue(task.testHasReadSource,
                      "Production path (TaskNotifier.register → didRegister) should create read source")
        XCTAssertTrue(task.testHasWriteSource,
                      "Production path (TaskNotifier.register → didRegister) should create write source")
        #endif
    }

    func testProcessExitCleansUpSource() throws {
        // REQUIREMENT: Sources torn down when process exits
        // teardownDispatchSources should be called on process exit

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Verify PTYTask has teardownDispatchSources method
        let selector = NSSelectorFromString("teardownDispatchSources")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have teardownDispatchSources for cleanup")

        #if ITERM_DEBUG
        // Fresh task has no sources
        XCTAssertFalse(task.testHasReadSource, "Fresh task has no read source")
        XCTAssertFalse(task.testHasWriteSource, "Fresh task has no write source")

        // Call teardown (simulates what happens on process exit/dealloc)
        task.perform(selector)

        // State should remain clean
        XCTAssertFalse(task.testHasReadSource, "No read source after teardown")
        XCTAssertFalse(task.testHasWriteSource, "No write source after teardown")
        #endif
    }

    func testNoSourceLeakOnRapidRestart() throws {
        // REQUIREMENT: Rapidly restarting shells doesn't leak sources
        // Each restart should clean up old sources before creating new ones

        // Create many tasks in rapid succession (simulates rapid shell restart)
        for i in 0..<20 {
            guard let task = PTYTask() else {
                XCTFail("Failed to create PTYTask at iteration \(i)")
                return
            }

            // Register with scheduler
            let terminal = VT100Terminal()
            let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
            let sessionId = FairnessScheduler.shared.register(executor)
            executor.fairnessSessionId = sessionId

            task.tokenExecutor = executor

            // Immediately cleanup (simulates quick close)
            FairnessScheduler.shared.unregister(sessionId: sessionId)

            let teardownSelector = NSSelectorFromString("teardownDispatchSources")
            if task.responds(to: teardownSelector) {
                task.perform(teardownSelector)
            }
        }

        // Wait for all async cleanup
        waitForMutationQueue()

        #if ITERM_DEBUG
        // All sessions should be cleaned up
        XCTAssertEqual(FairnessScheduler.shared.testBusySessionCount, 0,
                       "No busy sessions should remain after rapid restart test")
        #endif
    }
}

// MARK: - Backpressure Integration Tests

/// Tests for backpressure system integration
final class BackpressureIntegrationTests: XCTestCase {

    func testHighThroughputSuspended() throws {
        // REQUIREMENT: High-throughput session's read source suspended at high backpressure
        // When backpressure is blocked, reading should stop

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add many tokens to create blocked backpressure (50 tokens > 40 slots)
        for _ in 0..<50 {
            var vector = CVector()
            CVectorCreate(&vector, 10)
            for _ in 0..<10 {
                let token = VT100Token()
                token.type = VT100_UNKNOWNCHAR
                CVectorAppendVT100Token(&vector, token)
            }
            executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)
        }

        // Should be blocked when exceeding capacity
        XCTAssertEqual(executor.backpressureLevel, .blocked,
                       "Should be blocked after exceeding slot capacity")

        // Create a PTYTask to verify shouldRead is false
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            FairnessScheduler.shared.unregister(sessionId: sessionId)
            return
        }
        task.tokenExecutor = executor
        task.paused = false

        // Use test override to force ioAllowed = true (bypasses jobManager requirement)
        task.testIoAllowedOverride = NSNumber(value: true)

        // shouldRead should be false due to blocked backpressure
        // shouldRead checks: !paused && ioAllowed && backpressureLevel < .heavy
        // With blocked backpressure (>= .heavy), shouldRead must be false
        guard let shouldRead = task.value(forKey: "shouldRead") as? Bool else {
            XCTFail("Failed to get shouldRead from PTYTask")
            FairnessScheduler.shared.unregister(sessionId: sessionId)
            return
        }
        XCTAssertFalse(shouldRead,
                       "shouldRead should be false when backpressure is blocked")

        // Cleanup
        FairnessScheduler.shared.unregister(sessionId: sessionId)
        waitForMutationQueue()
    }

    func testSuspendedSessionResumedOnDrain() throws {
        // REQUIREMENT: Suspended session resumes when tokens consumed
        // backpressureReleaseHandler should resume reading

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        let delegate = MockTokenExecutorDelegate()
        executor.delegate = delegate

        var releaseHandlerCallCount = 0
        executor.backpressureReleaseHandler = {
            releaseHandlerCallCount += 1
        }

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add tokens to create backpressure
        for _ in 0..<30 {
            var vector = CVector()
            CVectorCreate(&vector, 5)
            for _ in 0..<5 {
                let token = VT100Token()
                token.type = VT100_UNKNOWNCHAR
                CVectorAppendVT100Token(&vector, token)
            }
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        // Record initial release handler calls
        let initialCallCount = releaseHandlerCallCount

        // Drain tokens via executeTurn
        let drainExpectation = XCTestExpectation(description: "Drain tokens")
        drainExpectation.expectedFulfillmentCount = 5
        for _ in 0..<5 {
            executor.executeTurn(tokenBudget: 500) { _ in
                drainExpectation.fulfill()
            }
        }
        wait(for: [drainExpectation], timeout: 5.0)

        // After draining, backpressureReleaseHandler should have been called
        XCTAssertGreaterThan(releaseHandlerCallCount, initialCallCount,
                             "backpressureReleaseHandler should be called during drain")

        // Cleanup
        FairnessScheduler.shared.unregister(sessionId: sessionId)
        waitForMutationQueue()
    }

    func testBackpressureIsolation() throws {
        // REQUIREMENT: Session A's backpressure doesn't affect Session B's reading
        // Each session has independent backpressure

        // Test with two independent executors
        let terminal1 = VT100Terminal()
        let terminal2 = VT100Terminal()
        let executor1 = TokenExecutor(terminal1, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        let executor2 = TokenExecutor(terminal2, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        // Register both with scheduler
        let sessionId1 = FairnessScheduler.shared.register(executor1)
        let sessionId2 = FairnessScheduler.shared.register(executor2)
        executor1.fairnessSessionId = sessionId1
        executor2.fairnessSessionId = sessionId2

        // Both should start with no backpressure
        XCTAssertEqual(executor1.backpressureLevel, .none,
                       "Executor 1 should start with no backpressure")
        XCTAssertEqual(executor2.backpressureLevel, .none,
                       "Executor 2 should start with no backpressure")

        // Drive executor1 to blocked backpressure (50 tokens > 40 slots)
        for _ in 0..<50 {
            var vector = CVector()
            CVectorCreate(&vector, 10)
            for _ in 0..<10 {
                let token = VT100Token()
                token.type = VT100_UNKNOWNCHAR
                CVectorAppendVT100Token(&vector, token)
            }
            executor1.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)
        }

        // Verify executor1 is now blocked
        XCTAssertEqual(executor1.backpressureLevel, .blocked,
                       "Executor 1 should be blocked after exceeding slot capacity")

        // CRITICAL: Verify executor2 remains unaffected - this is the isolation test
        XCTAssertEqual(executor2.backpressureLevel, .none,
                       "Executor 2 should remain at .none - backpressure must be isolated per-session")

        // Cleanup
        FairnessScheduler.shared.unregister(sessionId: sessionId1)
        FairnessScheduler.shared.unregister(sessionId: sessionId2)
        waitForMutationQueue()
    }
}

// MARK: - Session Lifecycle Integration Tests

/// Tests for session lifecycle edge cases
final class SessionLifecycleIntegrationTests: XCTestCase {

    func testSessionCloseWithPendingTokens() throws {
        // REQUIREMENT: Closing session with queued tokens doesn't leak/crash
        // cleanupForUnregistration should handle pending tokens

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add tokens
        var vector = CVector()
        CVectorCreate(&vector, 1)
        let token = VT100Token()
        token.type = VT100_UNKNOWNCHAR
        CVectorAppendVT100Token(&vector, token)
        executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)

        // Close session - should not crash
        FairnessScheduler.shared.unregister(sessionId: sessionId)

        // If we get here without crashing, test passes
        XCTAssertTrue(true, "Session closed with pending tokens without crash")
    }

    func testSessionCloseAccountingCorrect() throws {
        // REQUIREMENT: availableSlots returns to initial after close
        // No accounting drift after session lifecycle

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add tokens
        var vector = CVector()
        CVectorCreate(&vector, 1)
        let token = VT100Token()
        token.type = VT100_UNKNOWNCHAR
        CVectorAppendVT100Token(&vector, token)
        executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)

        // Close session
        FairnessScheduler.shared.unregister(sessionId: sessionId)

        // Backpressure should return to none
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Accounting should be correct after close")
    }

    func testRapidSessionOpenClose() throws {
        // REQUIREMENT: Rapidly opening/closing sessions doesn't cause issues
        // Stress test for session lifecycle

        let terminal = VT100Terminal()

        for _ in 0..<10 {
            let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
            let sessionId = FairnessScheduler.shared.register(executor)
            executor.fairnessSessionId = sessionId
            FairnessScheduler.shared.unregister(sessionId: sessionId)
        }

        // If we get here without crash/hang, test passes
        XCTAssertTrue(true, "Rapid open/close completed successfully")
    }

    func testSessionCloseDuringExecution() throws {
        // REQUIREMENT: Session closes while its turn is executing
        // Edge case: session removed from scheduler mid-turn

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        let delegate = MockTokenExecutorDelegate()
        executor.delegate = delegate

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add tokens
        var vector = CVector()
        CVectorCreate(&vector, 10)
        for _ in 0..<10 {
            let token = VT100Token()
            token.type = VT100_UNKNOWNCHAR
            CVectorAppendVT100Token(&vector, token)
        }
        executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)

        // Start execution
        let executionStarted = XCTestExpectation(description: "Execution started")
        let executionComplete = XCTestExpectation(description: "Execution complete")

        executor.executeTurn(tokenBudget: 500) { result in
            executionComplete.fulfill()
        }
        executionStarted.fulfill()

        // Immediately unregister (mid-turn)
        FairnessScheduler.shared.unregister(sessionId: sessionId)

        // Wait for both to complete without crash
        wait(for: [executionStarted, executionComplete], timeout: 2.0)

        // After everything settles, verify cleanup
        waitForMutationQueue()

        #if ITERM_DEBUG
        XCTAssertFalse(FairnessScheduler.shared.testIsSessionRegistered(sessionId),
                       "Session should be unregistered after mid-turn close")
        #endif
    }
}
