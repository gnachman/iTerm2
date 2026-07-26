//
//  PTYSessionEndActionTests.swift
//  iTerm2 ModernTests
//
//  PTYSession.forceDefaultEndAction is the durable pin that keeps a
//  workgroup-spawned member (peer, split, or tab) from ever reporting a
//  Close end action, no matter what the profile's "Close Sessions On End"
//  (KEY_SESSION_END_ACTION) setting is or how a later profile sync
//  reconciles it. Without the pin, a member could quietly flip to Close and
//  auto-close when its program exits (e.g. a Diff pane whose difftool
//  finishes), which tears the whole workgroup down.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionEndActionTests: XCTestCase {
    func testDefaultSessionReportsItsAppliedEndAction() {
        let s = PTYSession(synthetic: false)!
        XCTAssertFalse(s.forceDefaultEndAction,
                       "A plain session must not pin the end action")
        s.endAction = .close
        XCTAssertEqual(s.endAction, .close,
                       "Baseline: endAction reflects the applied Close setting")
    }

    func testForceDefaultEndActionOverridesCloseSetting() {
        let s = PTYSession(synthetic: false)!
        s.endAction = .close
        s.forceDefaultEndAction = true
        XCTAssertEqual(s.endAction, .default,
                       "forceDefaultEndAction must override a Close end action")
    }

    func testPinSurvivesALaterProfileSyncToClose() {
        let s = PTYSession(synthetic: false)!
        s.forceDefaultEndAction = true
        // setPreferencesFromAddressBookEntry drives self.endAction = <profile
        // value> on a profile sync; simulate that reconciling the key back to
        // Close. The pin must win.
        s.endAction = .close
        XCTAssertEqual(s.endAction, .default,
                       "The pin must survive a later setEndAction(.close)")
    }
}
