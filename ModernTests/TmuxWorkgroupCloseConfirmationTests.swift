//
//  TmuxWorkgroupCloseConfirmationTests.swift
//  iTerm2 ModernTests
//
//  Closing a member of a workgroup in a tmux Integration tab ends the workgroup and kills its
//  other members' panes, but Cmd-W on one closed it without asking, where a local workgroup's
//  member asks first and says the workgroup will end. QA finding F-618.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWorkgroupCloseConfirmationTests: WorkgroupEntryTestBase {
    private var tmuxSessions = [PTYSession]()

    override func tearDown() {
        for session in tmuxSessions {
            if let task = session.shell as AnyObject as? iTermTask {
                TaskNotifier.sharedInstance().deregister(task)
            }
        }
        tmuxSessions = []
        super.tearDown()
    }

    private func enterRootWithSplit() throws -> PTYSession {
        let root = WGFix.makeRoot()
        let split = WGFix.makeSplit(parentID: root.uniqueIdentifier)
        enterWorkgroup(WGFix.wrap(name: "rootSplit", sessions: [root, split]))
        XCTAssertNotNil(instance)
        return try XCTUnwrap(spawner.session(forConfigID: split.uniqueIdentifier))
    }

    func testClosingATmuxMemberMustBeConfirmed() throws {
        let split = try enterRootWithSplit()
        split.setTmuxPane(1)
        tmuxSessions.append(split)
        XCTAssertTrue(PseudoTerminal.closingEndsTmuxWorkgroup([split]))
    }

    // With Find > Filter (or Instant Replay) open, Cmd-W closes the stand-in that shows the member.
    // QA finding F-801.
    func testClosingAFilteredTmuxMemberMustBeConfirmed() throws {
        let split = try enterRootWithSplit()
        split.setTmuxPane(1)
        tmuxSessions.append(split)
        let standIn = PTYSession(synthetic: true)!
        standIn.live = split
        XCTAssertTrue(PseudoTerminal.closingEndsTmuxWorkgroup([standIn]))
        XCTAssertNotNil(iTermWorkgroupInstance.closeCascadeWarning(forSessions: [standIn]),
                        "the confirmation says the workgroup will end")
        standIn.live = nil
    }

    // Local members ask as they always have, according to their profiles.
    func testClosingALocalMemberIsUnchanged() throws {
        let split = try enterRootWithSplit()
        XCTAssertFalse(PseudoTerminal.closingEndsTmuxWorkgroup([split]))
    }

    // Nothing else would close, so there is nothing to warn about.
    func testClosingTheWholeWorkgroupNeedsNoWarning() throws {
        let split = try enterRootWithSplit()
        split.setTmuxPane(1)
        tmuxSessions.append(split)
        XCTAssertFalse(PseudoTerminal.closingEndsTmuxWorkgroup([split, leader]))
    }
}
