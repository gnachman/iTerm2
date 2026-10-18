//
//  SSHRecoveryBoundaryTests.swift
//  iTerm2 ModernTests
//
//  Once the parser enters conductor recovery mode, the boundary token that ends recovery has to
//  arrive even if the host prints nothing more. Until it does, the conductor cannot send
//  commands and framer panes cannot reattach.
//

import XCTest
@testable import iTerm2SharedARC

private final class ResynchronizeSpy: SpyingScreenDelegate {
    private(set) var resynchronized = 0
    override func screenDidResynchronizeSSH() {
        resynchronized += 1
    }
}

final class SSHRecoveryBoundaryTests: XCTestCase {
    private var screen: VT100Screen!
    private var delegate: ResynchronizeSpy!

    override func setUp() {
        super.setUp()
        delegate = ResynchronizeSpy()
        screen = VT100Screen()
        screen.delegate = delegate
        delegate.screen = screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            self.screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
        })
    }

    /// Puts the parser in recovery mode for a conductor with one framed process, as restoring
    /// or recovering does, and returns the mutable state for the caller to act on.
    private func enterRecoveryMode(then block: (VT100ScreenMutableState) -> Void) {
        screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            guard let terminal else {
                XCTFail("no terminal")
                return
            }
            terminal.framerRecoveryMode = .syncing
            terminal.framerBoundaryNumber = terminal.parser.startConductorRecoveryMode(
                withID: "dcs", tree: [NSNumber(value: 123): ["child-dcs", [:] as NSDictionary]], clientUniqueID: nil)
            block(mutableState)
        })
    }

    func testTheBoundaryArrivesWithoutMoreOutput() {
        enterRecoveryMode { mutableState in
            mutableState.flushParserAsynchronously()
        }
        let resynchronized = expectation(for: NSPredicate { [delegate] _, _ in
            // Side effects run when the threads are joined.
            self.screen.performBlock(joinedThreads: { _, _, _ in })
            return delegate!.resynchronized == 1
        }, evaluatedWith: nil)
        wait(for: [resynchronized], timeout: 30)
        screen.performBlock(joinedThreads: { terminal, _, _ in
            XCTAssertEqual(terminal?.framerRecoveryMode, VT100TerminalFramerRecoveryMode.none)
        })
    }
}
