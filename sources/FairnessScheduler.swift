//
//  FairnessScheduler.swift
//  iTerm2SharedARC
//
//  Round-robin fair scheduler for token execution across PTY sessions.
//  See implementation.md for design details.
//
//  Thread Safety:
//  - ID allocation uses a lightweight Mutex (allows register() from joined blocks)
//  - All other state is synchronized via iTermGCD.mutationQueue
//  - Public methods dispatch async to avoid blocking callers
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
    static let defaultTokenBudget = 1000

    // MARK: - Private State

    /// Lock protecting only nextSessionId for ID allocation.
    /// This allows register() to be called from joined blocks without deadlock.
    private let idLock = Mutex()

    // Protected by idLock (only accessed during register)
    // Start at 1 so that 0 can be used as "not registered" sentinel value
    private var nextSessionId: SessionID = 1

    // Access on mutation queue only
    private var sessions: [SessionID: SessionState] = [:]
    // Access on mutation queue only
    private var busyList: [SessionID] = []       // Round-robin order
    // Access on mutation queue only
    private var busySet: Set<SessionID> = []     // O(1) membership check

    #if ITERM_DEBUG
    // Access on mutation queue only
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
        // Allocate ID under lock (instant, no queue dispatch needed)
        let sessionId = idLock.sync {
            let id = nextSessionId
            nextSessionId += 1
            return id
        }

        // Session creation dispatches async to mutation queue.
        // This avoids deadlock when called from joined blocks.
        // Safe because callers set isRegistered after this returns,
        // and schedule() also dispatches to mutation queue (ordering preserved).
        iTermGCD.mutationQueue().async {
            self.sessions[sessionId] = SessionState(executor: executor)
        }

        return sessionId
    }

    /// Unregister a session.
    /// Thread-safe: may be called from any thread.
    @objc func unregister(sessionId: SessionID) {
        iTermGCD.mutationQueue().async {
            guard let state = self.sessions[sessionId] else { return }
            let executor = state.executor

            self.sessions.removeValue(forKey: sessionId)
            self.busySet.remove(sessionId)
            // busyList cleaned lazily in executeNextTurn

            executor?.cleanupForUnregistration()
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
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
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
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
        guard !busyList.isEmpty else { return }
        executionJoiner.setNeedsUpdate { [weak self] in
            self?.executeNextTurn()
        }
    }

    /// Must be called on mutationQueue (via executionJoiner).
    private func executeNextTurn() {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
        guard !busyList.isEmpty else { return }

        let sessionId = busyList.removeFirst()
        busySet.remove(sessionId)

        guard var state = sessions[sessionId],
              let executor = state.executor else {
            // Dead session - clean up and try next
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

        executor.executeTurn(tokenBudget: Self.defaultTokenBudget) { [weak self] turnResult in
            // Completion may be called from any thread; dispatch back to mutationQueue
            iTermGCD.mutationQueue().async {
                self?.sessionFinishedTurn(sessionId, result: turnResult)
            }
        }
    }

    /// Must be called on mutationQueue.
    private func sessionFinishedTurn(_ sessionId: SessionID, result: TurnResult) {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
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
        // Reset ID counter under its lock
        idLock.sync {
            nextSessionId = 1
        }

        // Reset all other state on mutation queue
        iTermGCD.mutationQueue().sync {
            let executors = sessions.values.compactMap { $0.executor }
            sessions.removeAll()
            busyList.removeAll()
            busySet.removeAll()
            _testExecutionHistory.removeAll()

            for executor in executors {
                executor.cleanupForUnregistration()
            }
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
