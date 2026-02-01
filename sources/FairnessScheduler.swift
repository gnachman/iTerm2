//
//  FairnessScheduler.swift
//  iTerm2SharedARC
//
//  Round-robin fair scheduler for token execution across PTY sessions.
//  See implementation.md for design details.
//
//  Thread Safety: Internal state is protected by a private Mutex lock.
//  Public methods may be called from any thread, including during "joined block"
//  contexts where the mutation queue is blocked. Actual token execution still
//  happens on the mutation queue via executionJoiner.
//

import Foundation

/// Result of executing a turn - returned by TokenExecutor.executeTurn()
@objc enum TurnResult: Int {
    case completed = 0  // No more work in queue
    case yielded = 1    // More work remains, re-add to busy list
    case blocked = 2    // Can't make progress (paused, copy mode, etc.)
}

/// Protocol that executors must conform to for FairnessScheduler integration.
/// TokenExecutor will conform to this protocol.
@objc(iTermFairnessSchedulerExecutor)
protocol FairnessSchedulerExecutor: AnyObject {
    /// Execute tokens up to the given budget. Calls completion with result.
    func executeTurn(tokenBudget: Int, completion: @escaping (TurnResult) -> Void)

    /// Called when session is unregistered to clean up pending tokens.
    func cleanupForUnregistration()
}

/// Coordinates round-robin fair scheduling of token execution across all PTY sessions.
@objc(iTermFairnessScheduler)
class FairnessScheduler: NSObject {

    /// Shared singleton instance
    @objc static let shared = FairnessScheduler()

    /// Session ID type - monotonically increasing counter
    typealias SessionID = UInt64

    /// Default token budget per turn
    static let defaultTokenBudget = 500

    // MARK: - Private State

    /// Lock protecting all scheduler state. Use lock.sync {} to access any state below.
    private let lock = Mutex()

    // Protected by lock
    // Start at 1 so that 0 can be used as "not registered" sentinel value
    private var nextSessionId: SessionID = 1
    // Protected by lock
    private var sessions: [SessionID: SessionState] = [:]
    // Protected by lock
    private var busyList: [SessionID] = []       // Round-robin order
    // Protected by lock
    private var busySet: Set<SessionID> = []     // O(1) membership check

    #if ITERM_DEBUG
    // Protected by lock
    /// Test-only: Records session IDs in the order they executed, for verifying round-robin fairness.
    private var _testExecutionHistory: [SessionID] = []
    #endif

    /// Coalesces multiple ensureExecutionScheduled() calls into a single async dispatch.
    private let executionJoiner = IdempotentOperationJoiner.asyncJoiner(iTermGCD.mutationQueue())

    private struct SessionState {
        weak var executor: FairnessSchedulerExecutor?
        var isExecuting: Bool = false
        var workArrivedWhileExecuting: Bool = false
    }

    // MARK: - Registration

    /// Register an executor with the scheduler. Returns a stable session ID.
    /// Thread-safe: may be called from any thread, including during joined blocks.
    @objc func register(_ executor: FairnessSchedulerExecutor) -> SessionID {
        return lock.sync {
            let sessionId = nextSessionId
            nextSessionId += 1
            sessions[sessionId] = SessionState(executor: executor)
            return sessionId
        }
    }

    /// Unregister a session.
    /// Thread-safe: may be called from any thread, including during joined blocks.
    @objc func unregister(sessionId: SessionID) {
        // Get executor reference and clean up bookkeeping under lock
        let executor: FairnessSchedulerExecutor? = lock.sync {
            let exec = sessions[sessionId]?.executor
            sessions.removeValue(forKey: sessionId)
            busySet.remove(sessionId)
            // busyList cleaned lazily in executeNextTurn
            return exec
        }

        // Cleanup must run on mutation queue (TokenExecutor requirement)
        if let executor = executor {
            iTermGCD.mutationQueue().async {
                executor.cleanupForUnregistration()
            }
        }
    }

    // MARK: - Work Notification

    /// Notify scheduler that a session has work to do.
    /// Thread-safe: may be called from any thread, including during joined blocks.
    @objc func sessionDidEnqueueWork(_ sessionId: SessionID) {
        let needsSchedule = lock.sync {
            sessionDidEnqueueWorkLocked(sessionId)
        }
        if needsSchedule {
            ensureExecutionScheduled()
        }
    }

    /// Internal implementation - must be called while holding lock.
    /// Returns true if ensureExecutionScheduled() should be called after releasing lock.
    private func sessionDidEnqueueWorkLocked(_ sessionId: SessionID) -> Bool {
        guard var state = sessions[sessionId] else { return false }

        if state.isExecuting {
            state.workArrivedWhileExecuting = true
            sessions[sessionId] = state
            return false
        }

        if !busySet.contains(sessionId) {
            busySet.insert(sessionId)
            busyList.append(sessionId)
            return true
        }
        return false
    }

    // MARK: - Execution

    /// Schedule execution if needed. Thread-safe: may be called from any thread.
    /// The actual execution happens on mutation queue via executionJoiner.
    private func ensureExecutionScheduled() {
        let hasBusyWork = lock.sync { !busyList.isEmpty }
        guard hasBusyWork else { return }
        executionJoiner.setNeedsUpdate { [weak self] in
            self?.executeNextTurn()
        }
    }

    /// Must be called on mutationQueue (via executionJoiner).
    private func executeNextTurn() {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))

        // Get next session under lock, release before calling executor
        let result: (sessionId: SessionID, executor: FairnessSchedulerExecutor)? = lock.sync {
            guard !busyList.isEmpty else { return nil }

            let sessionId = busyList.removeFirst()
            busySet.remove(sessionId)

            guard var state = sessions[sessionId],
                  let executor = state.executor else {
                // Dead session - clean up
                sessions.removeValue(forKey: sessionId)
                return nil
            }

            state.isExecuting = true
            state.workArrivedWhileExecuting = false
            sessions[sessionId] = state

            #if ITERM_DEBUG
            _testExecutionHistory.append(sessionId)
            #endif

            return (sessionId: sessionId, executor: executor)
        }

        guard let nextSession = result else {
            // Either empty or dead session - try again
            ensureExecutionScheduled()
            return
        }

        // Call executor outside the lock
        nextSession.executor.executeTurn(tokenBudget: Self.defaultTokenBudget) { [weak self] turnResult in
            // Completion may be called from any thread; dispatch back to mutationQueue
            iTermGCD.mutationQueue().async {
                self?.sessionFinishedTurn(nextSession.sessionId, result: turnResult)
            }
        }
    }

    /// Must be called on mutationQueue.
    private func sessionFinishedTurn(_ sessionId: SessionID, result: TurnResult) {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))

        lock.sync {
            guard var state = sessions[sessionId] else { return }

            state.isExecuting = false
            let workArrived = state.workArrivedWhileExecuting
            state.workArrivedWhileExecuting = false

            switch result {
            case .completed:
                if workArrived {
                    busySet.insert(sessionId)
                    busyList.append(sessionId)
                }
            case .yielded:
                busySet.insert(sessionId)
                busyList.append(sessionId)
            case .blocked:
                break // Don't reschedule
            }

            sessions[sessionId] = state
        }

        ensureExecutionScheduled()
    }
}

// MARK: - Testing Hooks

#if ITERM_DEBUG
extension FairnessScheduler {
    /// Test-only: Returns whether a session ID is currently registered.
    @objc func testIsSessionRegistered(_ sessionId: SessionID) -> Bool {
        return lock.sync {
            return sessions[sessionId] != nil
        }
    }

    /// Test-only: Returns the count of sessions in the busy list.
    @objc var testBusySessionCount: Int {
        return lock.sync {
            return busyList.count
        }
    }

    /// Test-only: Returns the total count of registered sessions.
    @objc var testRegisteredSessionCount: Int {
        return lock.sync {
            return sessions.count
        }
    }

    /// Test-only: Returns whether a session is currently in the busy list.
    @objc func testIsSessionInBusyList(_ sessionId: SessionID) -> Bool {
        return lock.sync {
            return busySet.contains(sessionId)
        }
    }

    /// Test-only: Returns whether a session is currently executing.
    @objc func testIsSessionExecuting(_ sessionId: SessionID) -> Bool {
        return lock.sync {
            return sessions[sessionId]?.isExecuting ?? false
        }
    }

    /// Test-only: Reset state for clean test runs.
    /// WARNING: Only call this in test teardown, never in production.
    @objc func testReset() {
        // Get executors under lock, then call cleanup outside lock
        let executors: [FairnessSchedulerExecutor] = lock.sync {
            let execs = sessions.values.compactMap { $0.executor }
            sessions.removeAll()
            busyList.removeAll()
            busySet.removeAll()
            nextSessionId = 1
            _testExecutionHistory.removeAll()
            return execs
        }

        // Cleanup must run on mutation queue (TokenExecutor requirement)
        iTermGCD.mutationQueue().sync {
            for executor in executors {
                executor.cleanupForUnregistration()
            }
        }
    }

    /// Test-only: Returns the execution history (session IDs in execution order) and clears it.
    /// Use this to verify round-robin fairness invariants.
    @objc func testGetAndClearExecutionHistory() -> [UInt64] {
        return lock.sync {
            let history = _testExecutionHistory
            _testExecutionHistory.removeAll()
            return history
        }
    }

    /// Test-only: Returns the current execution history without clearing it.
    @objc func testGetExecutionHistory() -> [UInt64] {
        return lock.sync {
            return _testExecutionHistory
        }
    }

    /// Test-only: Clears the execution history.
    @objc func testClearExecutionHistory() {
        lock.sync {
            _testExecutionHistory.removeAll()
        }
    }
}
#endif
