//
//  SpyPTYTask.swift
//  ModernTests
//
//  Spy PTYTask that tracks updateReadSourceState calls.
//  Used to verify that PTYSession correctly wires the backpressureReleaseHandler
//  to call updateReadSourceState on the task.
//

import Foundation
@testable import iTerm2SharedARC

/// Spy PTYTask that tracks calls to updateReadSourceState.
/// Use this to verify that backpressure release correctly triggers read source updates.
@objc final class SpyPTYTask: PTYTask {

    /// Number of times updateReadSourceState was called
    @objc private(set) var updateReadSourceStateCallCount: Int = 0

    /// Tracks the call (does not call super to avoid dispatch source operations)
    @objc override func updateReadSourceState() {
        updateReadSourceStateCallCount += 1
        // Don't call super - we don't have a real dispatch source
    }

    /// Reset call counts
    @objc func resetSpyCounts() {
        updateReadSourceStateCallCount = 0
    }
}
