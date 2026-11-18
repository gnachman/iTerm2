//
//  DuplicateTabSavedProgramTests.swift
//  ModernTests
//
//  Issue 13216: Duplicate Tab lost the source session's command and $$VAR$$ substitutions. Tab
//  arrangements encoded without contents stopped including the session's environment, and
//  restoration treated a missing environment as a sign of a legacy arrangement, so it ignored the
//  saved command and recomputed it from the profile without prompting.
//

import XCTest
@testable import iTerm2SharedARC

final class DuplicateTabSavedProgramTests: XCTestCase {
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

    private var session: PTYSession {
        guard let session = fixture.terminal.currentSession() else {
            it_fatalError("No session")
        }
        return session
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    // Gives the session the launch state a profile command like `/usr/bin/top -l $$COUNT$$`
    // leaves behind after the user answers the prompt with 5. These properties are private to
    // PTYSession, so set them through key-value coding.
    private func launchCommandWithSubstitution() {
        session.setValue("/usr/bin/top -l 5", forKey: "program")
        session.setValue(["COUNT": "5"], forKey: "substitutions")
    }

    // The tab's root view is a splitter even when it holds one session, so search the view tree.
    private func sessionArrangement(in tabArrangement: [AnyHashable: Any]) -> [AnyHashable: Any] {
        func find(_ node: [AnyHashable: Any]) -> [AnyHashable: Any]? {
            if let session = node["Session"] as? [AnyHashable: Any] {
                return session
            }
            let subviews = node["Subviews"] as? [[AnyHashable: Any]] ?? []
            return subviews.lazy.compactMap(find).first
        }
        guard let root = tabArrangement["Root"] as? [AnyHashable: Any],
              let sessionArrangement = find(root) else {
            it_fatalError("Tab arrangement has no session: \(tabArrangement)")
        }
        return sessionArrangement
    }

    func test_duplicationArrangement_keepsSavedProgram() {
        launchCommandWithSubstitution()
        let arrangement = sessionArrangement(in: tab.arrangementForDuplication())

        XCTAssertTrue(PTYSession.arrangementHasSavedProgramData(arrangement),
                      "Duplicate Tab must reuse the saved command: \(arrangement)")
        let program = arrangement["Program"] as? [AnyHashable: Any]
        XCTAssertEqual(program?["Command"] as? String, "/usr/bin/top -l 5")
        XCTAssertEqual(arrangement["Substitutions"] as? [String: String], ["COUNT": "5"])
    }

    // A window arrangement saved without contents also goes through restoration and should
    // reuse the saved command, even though it deliberately omits the environment.
    func test_arrangementWithoutContents_keepsSavedProgram() {
        launchCommandWithSubstitution()
        let arrangement = sessionArrangement(in: tab.arrangement(withContents: false))

        XCTAssertNil(arrangement["Environment"])
        XCTAssertTrue(PTYSession.arrangementHasSavedProgramData(arrangement),
                      "Restoration must reuse the saved command: \(arrangement)")
    }

    // The environment is in memory only when duplicating, so keep it as 3.6 did.
    func test_duplicationArrangement_includesEnvironment() {
        launchCommandWithSubstitution()
        let arrangement = sessionArrangement(in: tab.arrangementForDuplication())

        XCTAssertNotNil(arrangement["Environment"])
    }

    // Arrangements from before iTerm2 saved the program have none of these keys and must still
    // recompute the command from the profile.
    func test_legacyArrangementWithoutProgram_hasNoSavedProgramData() {
        let arrangement: [AnyHashable: Any] = ["Columns": 80, "Rows": 25]

        XCTAssertFalse(PTYSession.arrangementHasSavedProgramData(arrangement))
    }
}
