//
//  BrowserSessionTitleTests.swift
//  ModernTests
//
//  Validates the two browser-title findings:
//   1. A settled (finished-loading) page with a blank <title> must fall back to the
//      host, not keep the previous page's title. The pre-fix logic always kept the
//      current name, making the host tier dead code and stranding page A's title on a
//      titleless page B.
//   2. A terminal-only Session Title component that is currently selected on a browser
//      profile must stay visible so the user can deselect it (the pre-fix logic hid it
//      unconditionally, leaving a checked-but-invisible component).
//

import XCTest
@testable import iTerm2SharedARC

final class BrowserSessionTitleTests: XCTestCase {
    private typealias Title = iTermBrowserSessionTitle

    // MARK: - Finding 1: settled blank title -> host fallback

    func testNonBlankTitleIsUsed() {
        XCTAssertEqual(Title.resolvedName(pageTitle: "GitHub",
                                          host: "github.com",
                                          profileName: "Web Browser",
                                          navigationSettled: false),
                       "GitHub")
    }

    func testTransientBlankTitleKeepsCurrentName() {
        // During load (not settled), a blank title is transient (pre-parse); keep the
        // current name to avoid flickering to the host.
        XCTAssertNil(Title.resolvedName(pageTitle: "",
                                        host: "example.org",
                                        profileName: "Web Browser",
                                        navigationSettled: false))
    }

    func testSettledBlankTitleFallsBackToHost() {
        // A page that has finished loading with no <title> should show its host, not the
        // previous page's title. (Fails pre-fix: returns nil, keeping the old title.)
        XCTAssertEqual(Title.resolvedName(pageTitle: "",
                                          host: "example.org",
                                          profileName: "Web Browser",
                                          navigationSettled: true),
                       "example.org")
    }

    func testSettledNilTitleFallsBackToHost() {
        XCTAssertEqual(Title.resolvedName(pageTitle: nil,
                                          host: "example.org",
                                          profileName: "Web Browser",
                                          navigationSettled: true),
                       "example.org")
    }

    func testSettledBlankTitleWithNoHostFallsBackToProfileName() {
        XCTAssertEqual(Title.resolvedName(pageTitle: "  ",
                                          host: nil,
                                          profileName: "Web Browser",
                                          navigationSettled: true),
                       "Web Browser")
    }

    // MARK: - Finding 2: selected terminal-only component stays visible for a browser

    func testUnselectedTerminalOnlyComponentIsHiddenForBrowser() {
        // Job (tag 2) not selected -> hidden for a browser profile.
        XCTAssertTrue(Title.shouldHideTitleComponentMenuItem(
            tag: Int(iTermTitleComponents.job.rawValue),
            isBrowser: true,
            selectedComponents: iTermTitleComponents.sessionName.rawValue))
    }

    func testSelectedTerminalOnlyComponentStaysVisibleForBrowser() {
        // Job (tag 2) IS selected -> must stay visible so the user can turn it off.
        // (Fails pre-fix: hidden unconditionally.)
        let selected = iTermTitleComponents([.sessionName, .job]).rawValue
        XCTAssertFalse(Title.shouldHideTitleComponentMenuItem(
            tag: Int(iTermTitleComponents.job.rawValue),
            isBrowser: true,
            selectedComponents: selected))
    }

    func testNameComponentIsNeverHidden() {
        XCTAssertFalse(Title.shouldHideTitleComponentMenuItem(
            tag: Int(iTermTitleComponents.sessionName.rawValue),
            isBrowser: true,
            selectedComponents: iTermTitleComponents.sessionName.rawValue))
    }

    func testTerminalOnlyComponentIsVisibleForTerminalProfile() {
        XCTAssertFalse(Title.shouldHideTitleComponentMenuItem(
            tag: Int(iTermTitleComponents.job.rawValue),
            isBrowser: false,
            selectedComponents: iTermTitleComponents.job.rawValue))
    }
}
