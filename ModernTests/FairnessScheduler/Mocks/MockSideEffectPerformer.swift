//
//  MockSideEffectPerformer.swift
//  ModernTests
//
//  Mock implementation of VT100ScreenSideEffectPerforming for testing.
//  Used to create VT100ScreenMutableState instances without a real PTYSession.
//

import Foundation
@testable import iTerm2SharedARC

/// Mock implementation of VT100ScreenSideEffectPerforming for testing VT100ScreenMutableState.
/// Returns nil for delegates which is acceptable for test scenarios (init/deinit don't use them).
@objc final class MockSideEffectPerformer: NSObject, VT100ScreenSideEffectPerforming {

    // MARK: - VT100ScreenSideEffectPerforming

    @objc func sideEffectPerformingScreenDelegate() -> (any VT100ScreenDelegate)! {
        return nil
    }

    @objc func sideEffectPerformingIntervalTreeObserver() -> (any iTermIntervalTreeObserver)! {
        return nil
    }
}
