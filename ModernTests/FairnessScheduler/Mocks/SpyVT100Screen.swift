//
//  SpyVT100Screen.swift
//  ModernTests
//
//  Spy VT100Screen that captures mutateAsynchronously blocks for testing PTYSession wiring.
//  Used to verify that PTYSession methods like taskDidChangePaused and shortcutNavigationDidComplete
//  correctly dispatch to the mutation queue and call scheduleTokenExecution.
//

import Foundation
@testable import iTerm2SharedARC

/// Type alias for the mutation block signature
typealias MutationBlock = (VT100Terminal?, VT100ScreenMutableState, (any VT100ScreenDelegate)?) -> Void

/// Spy VT100Screen that captures blocks passed to mutateAsynchronously.
/// This allows tests to verify PTYSession wiring without running the full mutation queue.
@objc final class SpyVT100Screen: VT100Screen {

    /// The most recently captured mutation block
    private(set) var capturedMutationBlock: MutationBlock?

    /// Number of times mutateAsynchronously was called
    private(set) var mutateAsynchronouslyCallCount = 0

    /// Captures the block instead of executing it asynchronously
    @objc override func mutateAsynchronously(_ block: @escaping (VT100Terminal?, VT100ScreenMutableState, (any VT100ScreenDelegate)?) -> Void) {
        mutateAsynchronouslyCallCount += 1
        capturedMutationBlock = block
    }

    /// Execute the captured block with a controlled mutableState for testing
    func executeCapturedBlock(with mutableState: VT100ScreenMutableState,
                               terminal: VT100Terminal? = nil,
                               delegate: (any VT100ScreenDelegate)? = nil) {
        capturedMutationBlock?(terminal, mutableState, delegate)
    }

    /// Reset the spy state
    func reset() {
        capturedMutationBlock = nil
        mutateAsynchronouslyCallCount = 0
    }
}
