//
//  MacOS13RequirementNoticeTests.swift
//  ModernTests
//
//  Phase 0 of the uv Python-runtime migration: before the deployment target is
//  bumped from macOS 12 to 13, a beta that still runs on macOS 12 shows those
//  users a one-time notice that future betas will require macOS 13. The pure
//  decision (show iff running macOS < 13 and not yet shown) is the tested seam;
//  the iTermWarning presentation and the NoSync flag write are a thin, untested
//  caller. See docs/uv-python-runtime-migration.md.
//

import XCTest
@testable import iTerm2SharedARC

final class MacOS13RequirementNoticeTests: XCTestCase {
    func testShowsOnMacOS12WhenNotYetShown() {
        XCTAssertTrue(iTermMacOS13RequirementNotice.shouldShow(majorVersion: 12, alreadyShown: false))
    }

    func testDoesNotShowOnMacOS12WhenAlreadyShown() {
        // One-time only: once the notice has been shown it never recurs.
        XCTAssertFalse(iTermMacOS13RequirementNotice.shouldShow(majorVersion: 12, alreadyShown: true))
    }

    func testDoesNotShowOnMacOS13() {
        // 13+ users are unaffected by the coming drop, so never notify them.
        XCTAssertFalse(iTermMacOS13RequirementNotice.shouldShow(majorVersion: 13, alreadyShown: false))
    }

    func testDoesNotShowOnNewerMacOS() {
        XCTAssertFalse(iTermMacOS13RequirementNotice.shouldShow(majorVersion: 26, alreadyShown: false))
    }

    func testShowsOnOlderMacOS() {
        // Defensive: the function is correct for any pre-13 major even though the
        // deployment target keeps the app off macOS 11 and older.
        XCTAssertTrue(iTermMacOS13RequirementNotice.shouldShow(majorVersion: 11, alreadyShown: false))
    }
}
