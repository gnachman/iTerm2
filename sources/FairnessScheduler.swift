//
//  FairnessScheduler.swift
//  iTerm2SharedARC
//
//  Round-robin fair scheduler for token execution across PTY sessions.
//  See implementation.md for design details.
//
//  STUB: This is a minimal stub for test infrastructure. Implementation pending.
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
/// STUB: Not yet implemented.
@objc(iTermFairnessScheduler)
class FairnessScheduler: NSObject {

    /// Shared singleton instance
    @objc static let shared = FairnessScheduler()

    /// Session ID type - monotonically increasing counter
    typealias SessionID = UInt64

    /// Default token budget per turn
    static let defaultTokenBudget = 500

    // MARK: - Public API (STUBS)

    /// Register an executor with the scheduler. Returns a stable session ID.
    /// STUB: Returns incrementing ID but doesn't track anything.
    @objc func register(_ executor: FairnessSchedulerExecutor) -> SessionID {
        // STUB: Not implemented
        return 0
    }

    /// Unregister a session.
    /// STUB: Does nothing.
    @objc func unregister(sessionId: SessionID) {
        // STUB: Not implemented
    }

    /// Notify scheduler that a session has work to do.
    /// STUB: Does nothing.
    @objc func sessionDidEnqueueWork(_ sessionId: SessionID) {
        // STUB: Not implemented
    }
}
