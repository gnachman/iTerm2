//
//  MarkCommandSelectorTests.swift
//  iTerm2 ModernTests
//
//  Reproduces the 3.7.1 crash where clicking the bookmark command button raised
//  "-[VT100ScreenMark command]: unrecognized selector". VT100ScreenMark's
//  -command was renamed to -firstLineOfCommand (PR4) to force a per-callsite
//  audit, but the bookmark button's action block typed the mark as `id` and
//  still sent -command, so the compiler couldn't catch it and it trapped at
//  runtime.
//
//  These lock the contract: the removed selector is gone and firstLineOfCommand
//  is the replacement the callsite now uses.
//

import XCTest
@testable import iTerm2SharedARC

final class MarkCommandSelectorTests: XCTestCase {
    func testMarkDoesNotRespondToRenamedCommandSelector() {
        let mark = VT100ScreenMark()
        // The old callsite sent this selector; it must no longer exist, or the
        // `id`-typed send would trap again.
        XCTAssertFalse(mark.responds(to: Selector(("command"))),
                       "-command was renamed; a callsite still sending it would crash")
    }

    func testFirstLineOfCommandIsTheReplacement() {
        let mark = VT100ScreenMark()
        mark.firstLineOfCommand = "echo hello"
        // The bookmark button now reads firstLineOfCommand and toggles when
        // non-empty; verify the property the fix uses works.
        XCTAssertEqual(mark.firstLineOfCommand, "echo hello")
        XCTAssertTrue(mark.responds(to: Selector(("firstLineOfCommand"))))
    }
}
