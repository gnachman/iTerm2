//
//  MockTokenExecutorDelegate.swift
//  ModernTests
//
//  Mock implementation of TokenExecutorDelegate for testing.
//  Provides configurable behavior and call tracking for token execution tests.
//

import Foundation
@testable import iTerm2SharedARC

/// Mock implementation of TokenExecutorDelegate for testing.
final class MockTokenExecutorDelegate: NSObject, TokenExecutorDelegate {

    // MARK: - Configuration

    /// When true, tokenExecutorShouldQueueTokens() returns true (simulates paused/blocked state)
    var shouldQueueTokens = false

    /// When true, tokenExecutorShouldDiscard() returns true
    var shouldDiscardTokens = false

    /// Callback invoked when tokenExecutorWillExecuteTokens is called.
    /// Use this to fulfill expectations in tests.
    var onWillExecute: (() -> Void)?

    // MARK: - Call Tracking

    private let lock = NSLock()
    private var _executedLengths: [(total: Int, excluding: Int, throughput: Int)] = []
    private var _syncCount = 0
    private var _willExecuteCount = 0
    private var _handledFlags: [Int64] = []

    var executedLengths: [(total: Int, excluding: Int, throughput: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return _executedLengths
    }

    var syncCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _syncCount
    }

    var willExecuteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _willExecuteCount
    }

    var handledFlags: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return _handledFlags
    }

    // MARK: - TokenExecutorDelegate

    func tokenExecutorShouldQueueTokens() -> Bool {
        return shouldQueueTokens
    }

    func tokenExecutorShouldDiscard(token: VT100Token, highPriority: Bool) -> Bool {
        return shouldDiscardTokens
    }

    func tokenExecutorDidExecute(lengthTotal: Int, lengthExcludingInBandSignaling: Int, throughput: Int) {
        lock.lock()
        _executedLengths.append((lengthTotal, lengthExcludingInBandSignaling, throughput))
        lock.unlock()
    }

    func tokenExecutorCursorCoordString() -> NSString {
        return "(0,0)" as NSString
    }

    func tokenExecutorSync() {
        lock.lock()
        _syncCount += 1
        lock.unlock()
    }

    func tokenExecutorHandleSideEffectFlags(_ flags: Int64) {
        lock.lock()
        _handledFlags.append(flags)
        lock.unlock()
    }

    func tokenExecutorWillExecuteTokens() {
        lock.lock()
        _willExecuteCount += 1
        lock.unlock()
        onWillExecute?()
    }

    // MARK: - Test Helpers

    func reset() {
        lock.lock()
        shouldQueueTokens = false
        shouldDiscardTokens = false
        _executedLengths = []
        _syncCount = 0
        _willExecuteCount = 0
        _handledFlags = []
        onWillExecute = nil
        lock.unlock()
    }
}

/// TokenExecutorDelegate that tracks execution order for ordering tests.
/// Provides callbacks when tokens are executed to verify priority ordering.
final class OrderTrackingTokenExecutorDelegate: NSObject, TokenExecutorDelegate {

    private let lock = NSLock()
    private var _willExecuteCount = 0
    private var _totalExecutedLength = 0

    /// Callback invoked with lengthTotal when tokenExecutorDidExecute is called
    var onExecute: ((Int) -> Void)?

    var willExecuteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _willExecuteCount
    }

    var totalExecutedLength: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalExecutedLength
    }

    // MARK: - TokenExecutorDelegate

    func tokenExecutorShouldQueueTokens() -> Bool {
        return false  // Allow execution
    }

    func tokenExecutorShouldDiscard(token: VT100Token, highPriority: Bool) -> Bool {
        return false  // Don't discard
    }

    func tokenExecutorDidExecute(lengthTotal: Int, lengthExcludingInBandSignaling: Int, throughput: Int) {
        lock.lock()
        _totalExecutedLength += lengthTotal
        lock.unlock()
        onExecute?(lengthTotal)
    }

    func tokenExecutorCursorCoordString() -> NSString {
        return "(0,0)" as NSString
    }

    func tokenExecutorSync() {
        // Not used in ordering tests
    }

    func tokenExecutorHandleSideEffectFlags(_ flags: Int64) {
        // Not used in ordering tests
    }

    func tokenExecutorWillExecuteTokens() {
        lock.lock()
        _willExecuteCount += 1
        lock.unlock()
    }
}
