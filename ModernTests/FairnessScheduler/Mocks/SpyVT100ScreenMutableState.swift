//
//  SpyVT100ScreenMutableState.swift
//  ModernTests
//
//  Spy VT100ScreenMutableState that tracks scheduleTokenExecution calls.
//  Used to verify that PTYSession wiring correctly invokes scheduleTokenExecution
//  when unpausing or completing shortcut navigation.
//

import Foundation
@testable import iTerm2SharedARC

/// Spy VT100ScreenMutableState that tracks calls to scheduleTokenExecution.
/// Use this to verify that PTYSession methods correctly re-kick the scheduler.
@objc final class SpyVT100ScreenMutableState: VT100ScreenMutableState {

    /// Number of times scheduleTokenExecution was called
    @objc private(set) var scheduleTokenExecutionCallCount: Int = 0

    /// Tracks the call and forwards to super
    @objc override func scheduleTokenExecution() {
        scheduleTokenExecutionCallCount += 1
        super.scheduleTokenExecution()
    }

    /// Reset call counts
    @objc func resetSpyCounts() {
        scheduleTokenExecutionCallCount = 0
    }
}
