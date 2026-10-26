//
//  DuplicateWindowLocationLockTests.swift
//  ModernTests
//
//  Window > Duplicate Window builds the copy from the original's arrangement, which included Lock
//  Location. The copy was locked to the original's frame, so it opened exactly on top of it and
//  snapped back there when moved (QA finding F-037).
//

import XCTest
@testable import iTerm2SharedARC

final class DuplicateWindowLocationLockTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    @MainActor
    func testDuplicateOfALockedWindowIsNotLocked() throws {
        let terminal = fixture.terminal
        terminal.perform(NSSelectorFromString("toggleLocationLocked:"), with: nil)
        // The window's own arrangement keeps the lock, so restoring it locks it again.
        let own = try XCTUnwrap(terminal.arrangement())
        XCTAssertNotNil(WindowLocationLock.lock(from: own), "Precondition: the window is locked")

        let duplicate = try XCTUnwrap(terminal.arrangementForDuplicateWindow())
        XCTAssertNil(WindowLocationLock.lock(from: duplicate))
    }
}
