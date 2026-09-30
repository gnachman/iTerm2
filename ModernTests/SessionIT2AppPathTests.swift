//
//  SessionIT2AppPathTests.swift
//  iTerm2 ModernTests
//
//  IT2_APP_PATH tells the it2 CLI which iTerm2 to ask for a cookie (CookieAuth
//  in it2cli). It is an AppleScript disambiguator for the case where several
//  builds share a bundle identifier, so pointing it at the wrong instance is
//  not a cosmetic error: the target hands out a cookie this instance rejects,
//  and every hook fails with "Authentication failed" having set nothing.
//
//  The variable was only ever ADDED, never removed, so a session inherited
//  whatever its parent carried. A dev build launched from a Nightly tab (where
//  the advanced setting is on) got the Nightly's bundle path and asked the
//  Nightly for its cookie. Seen again through a tmux server on 2026-09-27,
//  where a pane inherits the environment of whichever tab started the server,
//  possibly days and several builds ago.
//

import XCTest
@testable import iTerm2SharedARC

final class SessionIT2AppPathTests: XCTestCase {
    private let thisBundle = "/Applications/iTerm2-dev.app"
    private let stale = "/Applications/iTerm2-nightly.app"

    private func resolved(inherited: String?,
                          settingEnabled: Bool,
                          suiteName: String?) -> String? {
        let env = NSMutableDictionary()
        if let inherited {
            env["IT2_APP_PATH"] = inherited
        }
        PTYSession.applyIT2AppPath(to: env,
                                   suiteName: suiteName,
                                   settingEnabled: settingEnabled,
                                   bundlePath: thisBundle)
        return env["IT2_APP_PATH"] as? String
    }

    // The defect. Off means off: an inherited value has to be cleared, not left
    // in place, or the child asks the parent's iTerm2 for a cookie this one will
    // reject.
    func testInheritedValueIsRemovedWhenTheSettingIsOff() {
        XCTAssertNil(resolved(inherited: stale, settingEnabled: false, suiteName: nil))
    }

    // A suite name means more than one instance is running by definition, so the
    // ambiguity the setting exists to resolve is always present. Set it without
    // being asked.
    func testSuiteImpliesTheVariableEvenWithTheSettingOff() {
        XCTAssertEqual(resolved(inherited: nil, settingEnabled: false, suiteName: "claude-iterm2-alt7"),
                       thisBundle)
    }

    // The live failure: a stale inherited path plus a suite. This instance's
    // path must win rather than the one that came through the tmux server.
    func testSuiteOverridesAStaleInheritedValue() {
        XCTAssertEqual(resolved(inherited: stale, settingEnabled: false, suiteName: "claude-iterm2-alt7"),
                       thisBundle)
    }

    func testSettingOnSetsThisBundlePath() {
        XCTAssertEqual(resolved(inherited: nil, settingEnabled: true, suiteName: nil), thisBundle)
    }

    func testSettingOnOverridesAStaleInheritedValue() {
        XCTAssertEqual(resolved(inherited: stale, settingEnabled: true, suiteName: nil), thisBundle)
    }

    // No suite, setting off, nothing inherited: the key must not be invented.
    // Most users are in this case and have exactly one iTerm2, where an
    // AppleScript target of plain "iTerm2" is correct and cheaper.
    func testNothingIsSetWhenThereIsNoAmbiguity() {
        XCTAssertNil(resolved(inherited: nil, settingEnabled: false, suiteName: nil))
    }

    // An empty suite name is not a suite. iTermUserDefaults returns nil rather
    // than "" today, but the decision should not depend on that.
    func testEmptySuiteNameIsNotASuite() {
        XCTAssertNil(resolved(inherited: stale, settingEnabled: false, suiteName: ""))
    }

    // MARK: - What a local tmux gateway advertises

    // A pane cannot trust its inherited IT2_APP_PATH, so the attached iTerm2 publishes its own
    // bundle path on the tmux server and it2 prefers that (CookieAuth.appTarget). Without this
    // key the record can say which socket to use but not which instance issues the cookie, which
    // is exactly the half that was wrong.
    func testLocalGatewayRecordCarriesThisBundlePath() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let record = try XCTUnwrap(session.tmuxGatewayIT2ClientRecord())
        XCTAssertEqual(record["app"], Bundle.main.bundlePath)
        XCTAssertFalse((record["suite"] ?? "").isEmpty,
                       "the suite still has to be there; it is what picks the socket")
    }
}
