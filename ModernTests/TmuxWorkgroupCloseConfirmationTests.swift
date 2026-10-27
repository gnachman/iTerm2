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

    // Once confirmed, closing the stand-in kills the member's pane, as closing the member itself
    // does, so the workgroup ends as it would then. Closing only the stand-in left the pane on the
    // server and the workgroup half alive. QA finding F-830.
    func testClosingAFilteredTmuxMemberKillsItsPane() throws {
        let split = try enterRootWithSplit()
        split.setTmuxPane(1)
        tmuxSessions.append(split)
        // A tmux client installs a status bar monitor once it has a controller, which needs a
        // profile, so it becomes a client first.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 10)
        let tmux = TmuxRecordingGateway()
        let controller = try XCTUnwrap(TmuxController(gateway: tmux.gateway,
                                                      clientName: "close-filtered-member-test",
                                                      profile: [:],
                                                      profileModel: nil))
        defer {
            split.tmuxController = nil
            TmuxControllerRegistry.sharedInstance().setController(nil, forClient: controller.clientName)
        }
        split.tmuxController = controller
        let standIn = PTYSession(synthetic: true)!
        standIn.live = split
        XCTAssertTrue(PseudoTerminal.tmuxPaneSessionClosed(byClosing: standIn) === split)
        XCTAssertTrue(PseudoTerminal.tmuxPaneSessionClosed(byClosing: split) === split)
        standIn.live = nil
        XCTAssertNil(PseudoTerminal.tmuxPaneSessionClosed(byClosing: standIn))
    }

    // The confirmation names the session the stand-in shows, which is what closes, not the
    // stand-in. QA finding F-846.
    func testTheConfirmationNamesTheSessionAStandInShows() throws {
        let split = try enterRootWithSplit()
        let standIn = PTYSession(synthetic: true)!
        standIn.live = split
        XCTAssertEqual(PseudoTerminal.name(forClosing: standIn),
                       PseudoTerminal.name(forClosing: split))
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
