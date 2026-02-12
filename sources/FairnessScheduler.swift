//
//  FairnessScheduler.swift
//  iTerm2SharedARC
//
//  Round-robin fair scheduler for token execution across PTY sessions.
//  See implementation.md for design details.
//
//  Thread Safety:
//  - ID allocation uses lock-free atomic increment
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
    ///
    /// Threading contract: This method is called on mutationQueue, and the completion
    /// callback MUST be invoked synchronously on mutationQueue before returning.
    /// FairnessScheduler relies on this guarantee to avoid unnecessary async dispatch.
    func executeTurn(tokenBudget: Int, completion: @escaping (TurnResult) -> Void)
}

/// Coordinates round-robin fair scheduling of token execution across all PTY sessions.
@objc(iTermFairnessScheduler)
class FairnessScheduler: NSObject {

    /// Shared singleton instance
    @objc static let shared = FairnessScheduler()

    /// Session ID type - monotonically increasing counter
    typealias SessionID = UInt64

    /// Default token budget per turn.
    ///
    /// Future enhancement: This could become adaptive based on session count,
    /// backpressure level, frame rate thresholds, or system load to balance
    /// responsiveness with throughput. Lower budgets yield more frequently
    /// (better responsiveness, lower throughput). Higher budgets process more
    /// per turn (better throughput, less responsive).
    static let defaultTokenBudget = 1000

    // MARK: - Private State

    /// Atomic counter for session ID allocation.
    /// Uses lock-free atomic increment for thread safety without blocking.
    /// Initialized to 0; first ID returned will be 1 (0 reserved as "not registered" sentinel).
    private let nextSessionIdAtomic = iTermAtomicInt64Create()

    deinit {
        iTermAtomicInt64Free(nextSessionIdAtomic)
    }

    // Access on mutation queue only
    private var sessions: [SessionID: SessionState] = [:]
    // Access on mutation queue only
    private var busyQueue = BusyQueue()

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

    /// Encapsulates the busy queue (round-robin order) with O(1) membership checks.
    /// Invariant: set and list always contain the same session IDs (modulo lazy cleanup).
    private struct BusyQueue {
        private var list: [SessionID] = []
        private var set: Set<SessionID> = []

        var isEmpty: Bool { list.isEmpty }
        var count: Int { list.count }

        mutating func enqueue(_ id: SessionID) {
            guard !set.contains(id) else {
                it_fatalError("Session \(id) already in busy queue")
            }
            set.insert(id)
            list.append(id)
        }

        mutating func dequeue() -> SessionID? {
            guard let id = list.first else { return nil }
            list.removeFirst()
            set.remove(id)
            return id
        }

        /// Remove from set only (list cleaned lazily during dequeue).
        mutating func removeFromSet(_ id: SessionID) {
            set.remove(id)
        }

        func contains(_ id: SessionID) -> Bool {
            set.contains(id)
        }

        mutating func removeAll() {
            list.removeAll()
            set.removeAll()
        }
    }

    // MARK: - Registration

    /// Register an executor with the scheduler. Returns a stable session ID.
    /// Thread-safe: may be called from any thread, including during joined blocks.
    @objc func register(_ executor: FairnessSchedulerExecutor) -> SessionID {
        // Allocate ID atomically (lock-free, instant)
        let sessionId = SessionID(iTermAtomicInt64Add(nextSessionIdAtomic, 1))

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
            guard self.sessions[sessionId] != nil else { return }
            self.sessions.removeValue(forKey: sessionId)
            self.busyQueue.removeFromSet(sessionId)
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

        if !busyQueue.contains(sessionId) {
            busyQueue.enqueue(sessionId)
            ensureExecutionScheduled()
        }
    }

    // MARK: - Execution

    /// Must be called on mutationQueue.
    private func ensureExecutionScheduled() {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
        guard !busyQueue.isEmpty else { return }
        executionJoiner.setNeedsUpdate { [weak self] in
            self?.executeNextTurn()
        }
    }

    /// Must be called on mutationQueue (via executionJoiner).
    private func executeNextTurn() {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
        guard let sessionId = busyQueue.dequeue() else { return }

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

        // Completion is called synchronously on mutationQueue (see protocol contract).
        // We rely on this to avoid an extra async dispatch per turn.
        executor.executeTurn(tokenBudget: Self.defaultTokenBudget) { [weak self] turnResult in
            #if ITERM_DEBUG
            dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
            #endif
            self?.sessionFinishedTurn(sessionId, result: turnResult)
        }
    }

    /// Must be called on mutationQueue.
    private func sessionFinishedTurn(_ sessionId: SessionID, result: TurnResult) {
        dispatchPrecondition(condition: .onQueue(iTermGCD.mutationQueue()))
        guard var state = sessions[sessionId] else {
            // Session was unregistered while its turn was executing.
            // Still need to pump the scheduler so other sessions in busyQueue make progress.
            ensureExecutionScheduled()
            return
        }

        state.isExecuting = false
        let workArrived = state.workArrivedWhileExecuting
        state.workArrivedWhileExecuting = false

        switch result {
        case .completed:
            if workArrived {
                busyQueue.enqueue(sessionId)
            }
        case .yielded:
            busyQueue.enqueue(sessionId)
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
            return busyQueue.count
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
            return busyQueue.contains(sessionId)
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
        // Reset ID counter atomically (set to 0, next ID will be 1)
        _ = iTermAtomicInt64GetAndReset(nextSessionIdAtomic)

        // Reset all other state on mutation queue
        iTermGCD.mutationQueue().sync {
            sessions.removeAll()
            busyQueue.removeAll()
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
