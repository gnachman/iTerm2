//
//  NativeFloatingPaneInTmuxTabTests.swift
//  ModernTests
//
//  A session iTerm2 runs itself (a shell from an external open with the Floating Pane open style,
//  or a web page from Open URL in Floating Pane) used to be installed as a float in a tmux
//  integration tab. Its tmux pane id reads as 0, so the next %layout-change laid it out in place
//  of tmux pane %0, hiding %0 and sending its input to the native session.
//

import XCTest
@testable import iTerm2SharedARC

final class NativeFloatingPaneInTmuxTabTests: XCTestCase {
    // MARK: - Where a native float may go

    func testNativeFloatAllowedInNonTmuxTab() {
        XCTAssertTrue(PseudoTerminal.canInstallNativeFloatingPane(whenFloatsAllowed: true,
                                                                  currentTabIsTmux: false))
    }

    // tmux 3.8 and later: floats are allowed in the tab, but only tmux's own.
    func testNativeFloatRefusedInTmuxTabThatSupportsFloats() {
        XCTAssertFalse(PseudoTerminal.canInstallNativeFloatingPane(whenFloatsAllowed: true,
                                                                   currentTabIsTmux: true))
    }

    // Older tmux: no floats at all.
    func testNativeFloatRefusedInTmuxTabWithoutFloatSupport() {
        XCTAssertFalse(PseudoTerminal.canInstallNativeFloatingPane(whenFloatsAllowed: false,
                                                                   currentTabIsTmux: true))
    }

    // Layout lock, instant replay, and so on.
    func testNativeFloatRefusedWhenFloatsAreNotAllowed() {
        XCTAssertFalse(PseudoTerminal.canInstallNativeFloatingPane(whenFloatsAllowed: false,
                                                                   currentTabIsTmux: false))
    }

    // MARK: - A layout change doesn't adopt a native session

    private var tmuxSessions = [PTYSession]()

    override func tearDown() {
        // -setTmuxPane: registers the session's task with the shared notifier.
        for session in tmuxSessions {
            if let task = session.shell as AnyObject as? iTermTask {
                TaskNotifier.sharedInstance().deregister(task)
            }
        }
        tmuxSessions = []
        super.tearDown()
    }

    private func tmuxSession(pane: Int32) -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.setTmuxPane(pane)
        tmuxSessions.append(session)
        XCTAssertTrue(session.isTmuxClient)
        return session
    }

    private func nativeSession() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        XCTAssertFalse(session.isTmuxClient)
        // A native session's tmux pane id reads as 0, the same as tmux's first pane.
        XCTAssertEqual(session.tmuxPane, 0)
        return session
    }

    func testLayoutChangeIgnoresNativeSessionListedAfterPaneZero() {
        let pane0 = tmuxSession(pane: 0)
        let pane1 = tmuxSession(pane: 1)
        let native = nativeSession()
        let map = PTYTab.tiledSessionsByTmuxPane(from: [pane0, pane1, native], floatingPanes: [])!
        XCTAssertEqual(map.count, 2)
        XCTAssertTrue(map[0] === pane0)
        XCTAssertTrue(map[1] === pane1)
    }

    func testLayoutChangeIgnoresNativeSessionListedBeforePaneZero() {
        let native = nativeSession()
        let pane0 = tmuxSession(pane: 0)
        let map = PTYTab.tiledSessionsByTmuxPane(from: [native, pane0], floatingPanes: [])!
        XCTAssertEqual(map.count, 1)
        XCTAssertTrue(map[0] === pane0)
    }

    // A filtered tmux pane shows a synthetic session whose live session is the tmux one. Its view
    // must stay with its tmux pane.
    func testLayoutChangeKeepsFilteredTmuxPaneZero() {
        let pane0 = tmuxSession(pane: 0)
        let pane1 = tmuxSession(pane: 1)
        let filtered = PTYSession(synthetic: true)!
        filtered.live = pane0
        let map = PTYTab.tiledSessionsByTmuxPane(from: [filtered, pane1], floatingPanes: [])!
        XCTAssertEqual(map.count, 2)
        XCTAssertTrue(map[0] === filtered)
        XCTAssertTrue(map[1] === pane1)
    }

    func testLayoutChangeKeepsFilteredTmuxPaneOtherThanZero() {
        let pane0 = tmuxSession(pane: 0)
        let pane1 = tmuxSession(pane: 1)
        let filtered = PTYSession(synthetic: true)!
        filtered.live = pane1
        let map = PTYTab.tiledSessionsByTmuxPane(from: [pane0, filtered], floatingPanes: [])!
        XCTAssertEqual(map.count, 2)
        XCTAssertTrue(map[0] === pane0)
        XCTAssertTrue(map[1] === filtered)
    }

    func testLayoutChangeIgnoresFilteredNativeSession() {
        let pane0 = tmuxSession(pane: 0)
        let filtered = PTYSession(synthetic: true)!
        filtered.live = nativeSession()
        let map = PTYTab.tiledSessionsByTmuxPane(from: [pane0, filtered], floatingPanes: [])!
        XCTAssertEqual(map.count, 1)
        XCTAssertTrue(map[0] === pane0)
    }

    func testLayoutChangeLeavesOutPanesThatAreFloating() {
        let pane0 = tmuxSession(pane: 0)
        let pane1 = tmuxSession(pane: 1)
        let map = PTYTab.tiledSessionsByTmuxPane(from: [pane0, pane1], floatingPanes: [NSNumber(value: 1)])!
        XCTAssertEqual(map.count, 1)
        XCTAssertTrue(map[0] === pane0)
    }
}
