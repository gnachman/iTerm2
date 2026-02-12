//
//  SpyVT100Screen.swift
//  ModernTests
//
//  Spy VT100Screen that intercepts performBlock(joinedThreads:) calls for testing PTYSession wiring.
//  Used to verify that PTYSession methods like taskDidChangePaused and shortcutNavigationDidComplete
//  correctly dispatch through performBlock(joinedThreads:).
//

import Foundation
@testable import iTerm2SharedARC

/// Type alias for the joined-threads block signature
typealias JoinedThreadsBlock = (VT100Terminal?, VT100ScreenMutableState, (any VT100ScreenDelegate)?) -> Void

/// Spy VT100Screen that intercepts performBlock(joinedThreads:) calls.
/// Since performBlock(joinedThreads:) uses NS_NOESCAPE, the block executes synchronously.
/// The spy executes the block immediately with an injected spy mutableState, allowing
/// tests to verify state changes after the call returns.
@objc final class SpyVT100Screen: VT100Screen {

    /// The spy mutable state to pass to intercepted blocks.
    /// Set this before calling the method under test.
    @objc var spyMutableState: VT100ScreenMutableState?

    /// Number of times performBlock(joinedThreads:) was called
    private(set) var performBlockWithJoinedThreadsCallCount = 0

    /// Override performBlock(joinedThreads:) to execute the block with the spy mutableState
    /// instead of going through the real mutation queue machinery.
    @objc override func performBlock(joinedThreads block: (VT100Terminal?, VT100ScreenMutableState, (any VT100ScreenDelegate)?) -> Void) {
        performBlockWithJoinedThreadsCallCount += 1
        if let state = spyMutableState {
            block(nil, state, nil)
        }
    }

    /// Reset the spy state
    func reset() {
        performBlockWithJoinedThreadsCallCount = 0
    }
}
