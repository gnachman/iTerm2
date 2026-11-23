//
//  PTYSessionWaitingForACommandTests.swift
//  ModernTests
//
//  Whether a session is waiting at a shell prompt, which puts its tab in the
//  last section of a tab bar ordered by working directory.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionWaitingForACommandTests: XCTestCase {
    func testAShellInTheForegroundIsWaiting() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        session.genericScope.setValue("zsh", forVariableNamed: iTermVariableKeySessionJob)
        XCTAssertTrue(session.isWaitingForACommand)
        session.genericScope.setValue("make", forVariableNamed: iTermVariableKeySessionJob)
        XCTAssertFalse(session.isWaitingForACommand)
    }

    // ssh to a host without shell integration counts as a command.
    func testSshIsACommand() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        session.genericScope.setValue("ssh", forVariableNamed: iTermVariableKeySessionJob)
        XCTAssertFalse(session.isWaitingForACommand)
    }

    // Reporting the directory, as with OSC 7 alone, doesn't mark prompts, so
    // it can't tell whether the shell is at one.
    func testReportingTheDirectoryWithoutPromptMarksStillGoesByTheJob() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        session.genericScope.setValue("zsh", forVariableNamed: iTermVariableKeySessionJob)
        session.perform(NSSelectorFromString("didUpdateCurrentDirectory:"), with: "/tmp")
        XCTAssertTrue(session.isWaitingForACommand)
    }
}
