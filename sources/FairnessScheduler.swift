//
//  FairnessScheduler.swift
//  iTerm2SharedARC
//
//  Round-robin fair scheduler for token execution across PTY sessions.
//  See implementation.md for design details.
//
//  Thread Safety: All state access is synchronized via iTermGCD.mutationQueue.
//  Public methods dispatch to mutationQueue; callers may invoke from any thread.
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

    // Start at 1 so that 0 can be used as "not registered" sentinel value
    private var nextSessionId: SessionID = 1
    private var sessions: [SessionID: SessionState] = [:]
    private var busyList: [SessionID] = []       // Round-robin order
    private var busySet: Set<SessionID> = []     // O(1) membership check

    #if ITERM_DEBUG
    /// Test-only: Records session IDs in the order they executed, for verifying round-robin fairness.
    private var _testExecutionHistory: [SessionID] = []
    #endif
    private var executionScheduled = false

    private struct SessionState {
        weak var executor: FairnessSchedulerExecutor?
        var isExecuting: Bool = false
        var workArrivedWhileExecuting: Bool = false
    }

    // MARK: - Registration

    /// Register an executor with the scheduler. Returns a stable session ID.
    /// Thread-safe: may be called from any thread, EXCEPT the mutation queue
    /// (would deadlock due to sync dispatch).
    @objc func register(_ executor: FairnessSchedulerExecutor) -> SessionID {
        // Catch deadlock-prone pattern: calling sync from within mutation queue
        dispatchPrecondition(condition: .notOnQueue(iTermGCD.mutationQueue()))
        return iTermGCD.mutationQueue().sync {
            let sessionId = nextSessionId
            nextSessionId += 1
            sessions[sessionId] = SessionState(executor: executor)
            return sessionId
        }
    }

    /// Unregister a session.
    /// Thread-safe: may be called from any thread.
    @objc func unregister(sessionId: SessionID) {
        iTermGCD.mutationQueue().async {
            if let state = self.sessions[sessionId], let executor = state.executor {
                executor.cleanupForUnregistration()
            }
            self.sessions.removeValue(forKey: sessionId)
            self.busySet.remove(sessionId)
            // busyList cleaned lazily in executeNextTurn
        }
    }

    // MARK: - Work Notification

    /// Notify scheduler that a session has work to do.
    /// Thread-safe: may be called from any thread.
    @objc func sessionDidEnqueueWork(_ sessionId: SessionID) {
        iTermGCD.mutationQueue().async {
            self.sessionDidEnqueueWorkOnQueue(sessionId)
        }
    }

    /// Internal implementation - must be called on mutationQueue.
    private func sessionDidEnqueueWorkOnQueue(_ sessionId: SessionID) {
        guard var state = sessions[sessionId] else { return }

        if state.isExecuting {
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

    // MARK: - Execution

    /// Must be called on mutationQueue.
    private func ensureExecutionScheduled() {
        guard !busyList.isEmpty else { return }
        guard !executionScheduled else { return }

        executionScheduled = true

        // Async dispatch to avoid deep recursion while staying on mutationQueue
        iTermGCD.mutationQueue().async { [weak self] in
            self?.executeNextTurn()
        }
    }

    /// Must be called on mutationQueue.
    private func executeNextTurn() {
        executionScheduled = false

        guard !busyList.isEmpty else { return }

        let sessionId = busyList.removeFirst()
        busySet.remove(sessionId)

        guard var state = sessions[sessionId],
              let executor = state.executor else {
            // Dead session - clean up
            sessions.removeValue(forKey: sessionId)
            ensureExecutionScheduled()
            return
        }

        state.isExecuting = true
        state.workArrivedWhileExecuting = false
        sessions[sessionId] = state

        #if ITERM_DEBUG
        _testExecutionHistory.append(sessionId)
        #endif

        executor.executeTurn(tokenBudget: Self.defaultTokenBudget) { [weak self] result in
            // Completion may be called from any thread; dispatch back to mutationQueue
            iTermGCD.mutationQueue().async {
                self?.sessionFinishedTurn(sessionId, result: result)
            }
        }
    }

    /// Must be called on mutationQueue.
    private func sessionFinishedTurn(_ sessionId: SessionID, result: TurnResult) {
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
        ensureExecutionScheduled()
    }
}

// MARK: - Testing Hooks

#if ITERM_DEBUG
extension FairnessScheduler {
    /// Test-only: Returns whether a session ID is currently registered.
    /// Must be called from mutationQueue or uses sync dispatch.
    @objc func testIsSessionRegistered(_ sessionId: SessionID) -> Bool {
        return iTermGCD.mutationQueue().sync {
            return sessions[sessionId] != nil
        }
    }

    /// Test-only: Returns the count of sessions in the busy list.
    @objc var testBusySessionCount: Int {
        return iTermGCD.mutationQueue().sync {
            return busyList.count
        }
    }

    /// Test-only: Returns the total count of registered sessions.
    @objc var testRegisteredSessionCount: Int {
        return iTermGCD.mutationQueue().sync {
            return sessions.count
        }
    }

    /// Test-only: Returns whether a session is currently in the busy list.
    @objc func testIsSessionInBusyList(_ sessionId: SessionID) -> Bool {
        return iTermGCD.mutationQueue().sync {
            return busySet.contains(sessionId)
        }
    }

    /// Test-only: Returns whether a session is currently executing.
    @objc func testIsSessionExecuting(_ sessionId: SessionID) -> Bool {
        return iTermGCD.mutationQueue().sync {
            return sessions[sessionId]?.isExecuting ?? false
        }
    }

    /// Test-only: Reset state for clean test runs.
    /// WARNING: Only call this in test teardown, never in production.
    @objc func testReset() {
        iTermGCD.mutationQueue().sync {
            // Call cleanup on all registered executors
            for state in sessions.values {
                state.executor?.cleanupForUnregistration()
            }
            sessions.removeAll()
            busyList.removeAll()
            busySet.removeAll()
            executionScheduled = false
            nextSessionId = 1
            _testExecutionHistory.removeAll()
        }
    }

    /// Test-only: Returns the execution history (session IDs in execution order) and clears it.
    /// Use this to verify round-robin fairness invariants.
    @objc func testGetAndClearExecutionHistory() -> [UInt64] {
        return iTermGCD.mutationQueue().sync {
            let history = _testExecutionHistory
            _testExecutionHistory.removeAll()
            return history
        }
    }

    /// Test-only: Returns the current execution history without clearing it.
    @objc func testGetExecutionHistory() -> [UInt64] {
        return iTermGCD.mutationQueue().sync {
            return _testExecutionHistory
        }
    }

    /// Test-only: Clears the execution history.
    @objc func testClearExecutionHistory() {
        iTermGCD.mutationQueue().sync {
            _testExecutionHistory.removeAll()
        }
    }
}
#endif
