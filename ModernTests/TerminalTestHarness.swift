//
//  TerminalTestHarness.swift
//  iTerm2
//
//  Created for testing working directory flow.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

/// Test harness for terminal escape sequence processing.
/// Provides convenient setup for testing VT100Screen flow.
class TerminalTestHarness {
    let screen: VT100Screen
    let delegate: SpyingScreenDelegate

    init(width: Int = 80, height: Int = 24) {
        delegate = SpyingScreenDelegate()
        screen = VT100Screen()

        screen.delegate = delegate
        delegate.screen = screen

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.terminalEnabled = true
            mutableState?.terminal?.termType = "xterm"
            self.screen.destructivelySetScreenWidth(Int32(width),
                                                    height: Int32(height),
                                                    mutableState: mutableState)
        })
    }

    /// Send OSC 7 working directory escape sequence
    func sendOSC7(path: String, host: String? = nil) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            if let host = host {
                mutableState?.setWorkingDirectoryFromURLString("file://\(host)\(path)")
            } else {
                mutableState?.setWorkingDirectoryFromURLString("file://\(path)")
            }
        })
    }

    /// Send shell integration: Set remote host (FinalTerm OSC 1337)
    func sendRemoteHost(user: String, host: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.setRemoteHostFrom("\(user)@\(host)")
        })
    }

    /// Send shell integration: Set current directory (FinalTerm OSC 1337)
    func sendCurrentDirectory(path: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.currentDirectoryDidChange(to: path, completion: {})
        })
    }

    /// Send window title change escape sequence
    /// This triggers the directory polling logic
    func sendWindowTitle(_ title: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // VT100ScreenMutableState conforms to VT100TerminalDelegate
            mutableState?.terminalSetWindowTitle(title)
        })
    }

    /// Synchronize threads and execute pending side effects
    func sync() {
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    /// Reset the delegate's call records
    func resetCalls() {
        delegate.reset()
    }

    /// Get the current working directory from the screen state
    var currentPath: String? {
        // Match VT100ScreenState.currentWorkingDirectory behavior (line 1328-1330)
        return screen.workingDirectory(onLine: screen.numberOfLines())
    }

    /// Check if shouldExpectWorkingDirectoryUpdates is set
    var expectsWorkingDirectoryUpdates: Bool {
        return screen.shouldExpectWorkingDirectoryUpdates()
    }
}
