//
//  PTYSessionScreenWindowIndexTests.swift
//  ModernTests
//
//  -[PTYSession screenWindowIndex] returns the index of the session's window
//  among iTermController's terminal windows, as an int. For a session whose
//  window is not registered, -[iTermController indexOfTerminal:] returns
//  NSNotFound, which the int return used to truncate implicitly to -1. It is
//  -1 explicitly now, the value every caller passes on to
//  iTermNotificationController, which treats a negative index as no window.
//  See docs/swift-migration/integer-findings.md section 4.8.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionScreenWindowIndexTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture?

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    func testSessionWithoutAWindowReportsMinusOne() {
        let session = PTYSession(synthetic: false)!
        XCTAssertEqual(session.screenWindowIndex(), -1)
    }

    func testSessionInARegisteredWindowReportsItsIndex() {
        let fixture = TerminalWindowTestFixture()
        self.fixture = fixture
        guard let session = fixture.terminal.currentSession(),
              let controller = iTermController.sharedInstance() else {
            XCTFail("No session or controller")
            return
        }
        let index = controller.index(of: fixture.terminal)
        XCTAssertNotEqual(Int(index), NSNotFound)
        XCTAssertEqual(Int(session.screenWindowIndex()), Int(index))
    }
}
