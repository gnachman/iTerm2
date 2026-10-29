//
//  PTYSessionProfileTypeTests.swift
//  iTerm2 ModernTests
//
//  A session's profile type (terminal or browser) is fixed when the session is
//  created. Changing the type of a shared profile in Settings must not reach
//  sessions already using it: they keep their type, and every other change to
//  the shared profile still applies to them.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionProfileTypeTests: XCTestCase {
    private var sharedGuids = [String]()
    private var sessions = [PTYSession]()

    override func tearDown() {
        for session in sessions {
            if session.isDivorced, let guid = session.profile?[KEY_GUID] as? String {
                ProfileModel.sessionsInstance().removeProfile(withGuid: guid)
            }
        }
        for guid in sharedGuids {
            ProfileModel.sharedInstance().removeProfile(withGuid: guid)
        }
        super.tearDown()
    }

    private func makeSharedProfile(customCommand: String) -> String {
        var profile = ProfileModel.sharedInstance().defaultBookmark() ?? [:]
        let guid = ProfileModel.freshGuid()!
        profile[KEY_GUID] = guid
        profile[KEY_NAME] = "PTYSessionProfileTypeTests \(guid)"
        profile[KEY_CUSTOM_COMMAND] = customCommand
        profile[KEY_BLINKING_CURSOR] = false
        profile.removeValue(forKey: KEY_ORIGINAL_GUID)
        ProfileModel.sharedInstance().addBookmark(profile)
        sharedGuids.append(guid)
        return guid
    }

    private func makeSession(guid: String) -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.profile = ProfileModel.sharedInstance().bookmark(withGuid: guid)
        sessions.append(session)
        return session
    }

    private func updateShared(guid: String, _ values: [String: Any]) {
        var profile = ProfileModel.sharedInstance().bookmark(withGuid: guid)!
        for (key, value) in values {
            profile[key] = value
        }
        ProfileModel.sharedInstance().setBookmark(profile, withGuid: guid)
    }

    private func customCommand(_ session: PTYSession) -> String? {
        return session.profile?[KEY_CUSTOM_COMMAND] as? String
    }

    func testTerminalSessionKeepsItsTypeWhenSharedProfileBecomesBrowser() {
        let guid = makeSharedProfile(customCommand: kProfilePreferenceCommandTypeLoginShellValue)
        let session = makeSession(guid: guid)
        XCTAssertFalse(session.isBrowserSession())

        updateShared(guid: guid, [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue,
                                  KEY_BLINKING_CURSOR: true])
        session.reloadProfile()

        XCTAssertFalse(session.isBrowserSession())
        XCTAssertEqual(customCommand(session), kProfilePreferenceCommandTypeLoginShellValue)
        XCTAssertEqual(session.profile?[KEY_BLINKING_CURSOR] as? Bool, true,
                       "Other changes to the shared profile must still apply")
    }

    func testTerminalSessionFollowsSharedProfileAgainAfterTypeIsSwitchedBack() {
        let guid = makeSharedProfile(customCommand: kProfilePreferenceCommandTypeLoginShellValue)
        let session = makeSession(guid: guid)

        updateShared(guid: guid, [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue])
        session.reloadProfile()
        updateShared(guid: guid, [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeLoginShellValue])
        session.reloadProfile()
        updateShared(guid: guid, [KEY_CUSTOM_COMMAND: "Yes"])
        session.reloadProfile()

        XCTAssertEqual(customCommand(session), "Yes",
                       "Once the types agree again, the session follows the shared command type")
    }

    func testBrowserSessionKeepsItsTypeWhenSharedProfileBecomesTerminal() {
        let guid = makeSharedProfile(customCommand: kProfilePreferenceCommandTypeBrowserValue)
        let session = makeSession(guid: guid)
        XCTAssertTrue(session.isBrowserSession())

        updateShared(guid: guid, [KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeLoginShellValue])
        session.reloadProfile()

        XCTAssertTrue(session.isBrowserSession())
        XCTAssertEqual(customCommand(session), kProfilePreferenceCommandTypeBrowserValue)
    }

    func testSessionSpecificValuesCannotChangeType() {
        let guid = makeSharedProfile(customCommand: kProfilePreferenceCommandTypeLoginShellValue)
        let session = makeSession(guid: guid)

        session.setSessionSpecificProfileValues([KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeBrowserValue,
                                                 KEY_BLINKING_CURSOR: true])

        XCTAssertFalse(session.isBrowserSession())
        XCTAssertEqual(customCommand(session), kProfilePreferenceCommandTypeLoginShellValue)
        XCTAssertEqual(session.profile?[KEY_BLINKING_CURSOR] as? Bool, true,
                       "Other session-specific values must still apply")
    }
}
