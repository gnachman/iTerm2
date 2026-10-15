//
//  RestoreWorkingDirectoryLauncherTests.swift
//  ModernTests
//
//  Restoring a login-shell session swaps the login command for the shell
//  launcher so the shell starts in the saved directory. An arrangement saved
//  without a directory (a pane restored from an archive runs no process, so it
//  saves an empty one) must keep the login command; the shell launcher started
//  in “/” instead of the profile's directory. QA finding F-205.
//

import XCTest
@testable import iTerm2SharedARC

final class RestoreWorkingDirectoryLauncherTests: XCTestCase {
    func testEmptySavedDirectoryKeepsLoginCommand() {
        let login = ITAddressBookMgr.standardLoginCommand()
        XCTAssertFalse(PTYSession.shouldRestoreWorkingDirectory("", withShellLauncherInsteadOfProgram: login))
        XCTAssertFalse(PTYSession.shouldRestoreWorkingDirectory(nil, withShellLauncherInsteadOfProgram: login))
    }

    func testSavedDirectoryUsesShellLauncherForLoginCommand() {
        XCTAssertTrue(PTYSession.shouldRestoreWorkingDirectory("/tmp",
                                                               withShellLauncherInsteadOfProgram: ITAddressBookMgr.standardLoginCommand()))
        XCTAssertTrue(PTYSession.shouldRestoreWorkingDirectory("/tmp",
                                                               withShellLauncherInsteadOfProgram: ITAddressBookMgr.legacyStandardLoginCommand()))
    }

    func testCustomCommandIsNotReplaced() {
        XCTAssertFalse(PTYSession.shouldRestoreWorkingDirectory("/tmp", withShellLauncherInsteadOfProgram: "/bin/bash"))
        XCTAssertFalse(PTYSession.shouldRestoreWorkingDirectory("/tmp", withShellLauncherInsteadOfProgram: nil))
    }
}
