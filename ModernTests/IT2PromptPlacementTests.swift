//
//  IT2PromptPlacementTests.swift
//  iTerm2 ModernTests
//
//  The prompt asking whether a host may use it2 used to go on the session that owns the ssh
//  connection. Once that session runs tmux -CC it is the gateway, which iTerm2 hides, so the
//  prompt was invisible and the first it2 call from a pane failed with nothing on screen. Now it
//  goes on the pane that asked; a pane in a hidden tmux window has no session until the window is
//  shown, so the prompt waits for it, as a buried session's prompt waits to be unburied.
//

import XCTest
@testable import iTerm2SharedARC

final class IT2PromptPlacementTests: XCTestCase {
    private typealias P = PTYSession.IT2PromptPlacement

    private func place(gateway: Bool = true,
                       callerPane: String? = nil,
                       sessions: [Int: String] = [:],
                       visible: String? = nil) -> P {
        return PTYSession.it2PromptPlacement(isTmuxGateway: gateway,
                                             callerTmuxPane: callerPane,
                                             sessionForPane: { sessions[$0] },
                                             visibleClientSession: visible)
    }

    // Not tmux: where it always went, whether that session is visible or buried.
    func testOrdinarySessionKeepsItsPrompt() {
        XCTAssertEqual(place(gateway: false, callerPane: "%3", sessions: [3: "s3"]), .ownSession)
    }

    func testThePaneThatAskedGetsIt() {
        XCTAssertEqual(place(callerPane: "%5", sessions: [5: "s5"], visible: "other"), .session("s5"))
    }

    // Its window is hidden: wait for the user to show it, rather than put it somewhere else.
    func testPaneInAHiddenWindowWaitsForIt() {
        XCTAssertEqual(place(callerPane: "%5", visible: "other"), .whenPaneAppears(5))
    }

    // A caller outside tmux, or one that did not say: any visible pane of this tmux client.
    func testUnknownPaneUsesAVisibleOne() {
        XCTAssertEqual(place(callerPane: nil, visible: "s9"), .session("s9"))
    }

    // Every window hidden, or none opened yet: the first one shown.
    func testNothingShownWaitsForTheFirstWindow() {
        XCTAssertEqual(place(callerPane: nil), .whenAnyPaneAppears)
    }

    func testMalformedPaneIsTreatedAsUnknown() {
        for pane in ["", "5", "%", "%x", "%-1"] {
            XCTAssertEqual(place(callerPane: pane, sessions: [5: "s5"], visible: "s9"), .session("s9"), pane)
        }
    }
}
