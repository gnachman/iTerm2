//
//  ClaudeCodeStatusOverlayTests.swift
//  ModernTests
//
//  What a session shows when Claude Code reports its own status (OSC 7501) and its hook is also
//  running. The report is the base; the hook adds two things Claude Code does not say: that the
//  turn is over while work it started keeps running, and the turn's last message.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeStatusOverlayTests: XCTestCase {
    private typealias Overlay = ClaudeCodeStatusOverlay
    private let allStates: [ProgramStatusReport.State] = [.idle, .working, .blocked, .done, .error]

    private func facts(turnOpen: Bool?, count: Int, message: String? = nil) -> ClaudeCodeHookFacts {
        return ClaudeCodeHookFacts(turnOpen: turnOpen, backgroundTasks: count, lastMessage: message)
    }

    // The turn is over and work is counted: that is background, whatever Claude Code calls it.
    // With background agents it keeps saying working; with background shells it says done.
    func testClosedTurnWithWorkCountedIsBackground() {
        for state in [ProgramStatusReport.State.working, .done, .idle] {
            XCTAssertEqual(Overlay.resolve(state: state, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 2)),
                           .background(count: 2), "\(state)")
            XCTAssertEqual(Overlay.resolve(state: state, isRoot: true, hasMessage: true, facts: facts(turnOpen: false, count: 1)),
                           .background(count: 1), "\(state) with a message")
        }
    }

    // Something that needs the user is never covered.
    func testBlockedAndErrorAreNeverOverlaid() {
        for state in [ProgramStatusReport.State.blocked, .error] {
            for hasMessage in [false, true] {
                XCTAssertEqual(Overlay.resolve(state: state, isRoot: true, hasMessage: hasMessage,
                                               facts: facts(turnOpen: false, count: 3, message: "last")),
                               .asReported, "\(state) hasMessage=\(hasMessage)")
            }
        }
    }

    // An open turn is Claude Code's to describe, and so is one the hook has said nothing about:
    // unknown is not closed.
    func testOpenOrUnknownTurnIsNeverBackground() {
        for turnOpen in [true, nil] as [Bool?] {
            for state in allStates {
                let resolution = Overlay.resolve(state: state, isRoot: true, hasMessage: true, facts: facts(turnOpen: turnOpen, count: 4))
                XCTAssertEqual(resolution, .asReported, "\(state) turnOpen=\(String(describing: turnOpen))")
            }
        }
    }

    func testClosedTurnWithNothingCountedIsNotBackground() {
        for state in allStates {
            XCTAssertEqual(Overlay.resolve(state: state, isRoot: true, hasMessage: true, facts: facts(turnOpen: false, count: 0)),
                           .asReported, "\(state)")
        }
    }

    // Claude Code's done carries no message; the hook's last message fills in.
    func testDoneWithoutAMessageTakesTheHooks() {
        XCTAssertEqual(Overlay.resolve(state: .done, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 0, message: "All set.")),
                       .detail("All set."))
    }

    // The message belongs to the turn the hook saw end. If the hook's word on the turn is open
    // or unknown, the done being shown is some other turn's, and a message held from before
    // would be shown as its result.
    func testTheLastMessageNeedsAClosedTurn() {
        for turnOpen in [true, nil] as [Bool?] {
            XCTAssertEqual(Overlay.resolve(state: .done, isRoot: true, hasMessage: false,
                                           facts: facts(turnOpen: turnOpen, count: 0, message: "All set.")),
                           .asReported, "turnOpen=\(String(describing: turnOpen))")
        }
    }

    // The message is the session's own turn's. An agent's record that says done is that
    // agent's, and gets none of it.
    func testAnAgentsDoneDoesNotTakeTheSessionsLastMessage() {
        XCTAssertEqual(Overlay.resolve(state: .done, isRoot: false, hasMessage: false,
                                       facts: facts(turnOpen: false, count: 0, message: "All set.")),
                       .asReported)
    }

    // Background describes the session, whichever of its records is the most urgent.
    func testAnAgentsRecordStillShowsBackground() {
        XCTAssertEqual(Overlay.resolve(state: .working, isRoot: false, hasMessage: true,
                                       facts: facts(turnOpen: false, count: 1)),
                       .background(count: 1))
    }

    // Every combination, against the rules written out independently.
    func testEveryCombinationAgainstTheRules() {
        let states: [ProgramStatusReport.State] = [.idle, .working, .blocked, .done, .error, .clear]
        for state in states {
            for isRoot in [true, false] {
                for hasMessage in [true, false] {
                    for turnOpen in [true, false, nil] as [Bool?] {
                        for count in [0, 1, 7] {
                            for message in [nil, "", "Last."] as [String?] {
                                let expected: Overlay.Resolution
                                let overlayable = state == .working || state == .done || state == .idle
                                if overlayable && turnOpen == false && count > 0 {
                                    expected = .background(count: count)
                                } else if (state == .done || state == .idle) && isRoot && !hasMessage && turnOpen == false && message == "Last." {
                                    expected = .detail("Last.")
                                } else {
                                    expected = .asReported
                                }
                                let actual = Overlay.resolve(state: state, isRoot: isRoot, hasMessage: hasMessage,
                                                             facts: facts(turnOpen: turnOpen, count: count, message: message))
                                XCTAssertEqual(actual, expected,
                                               "\(state) root=\(isRoot) hasMessage=\(hasMessage) turnOpen=\(String(describing: turnOpen)) count=\(count) message=\(String(describing: message))")
                            }
                        }
                    }
                }
            }
        }
    }

    // If Claude Code ever sends its own, it wins.
    func testDoneWithItsOwnMessageKeepsIt() {
        XCTAssertEqual(Overlay.resolve(state: .done, isRoot: true, hasMessage: true, facts: facts(turnOpen: false, count: 0, message: "All set.")),
                       .asReported)
    }

    func testDoneWithNoMessageAnywhereIsAsReported() {
        XCTAssertEqual(Overlay.resolve(state: .done, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 0)),
                       .asReported)
        XCTAssertEqual(Overlay.resolve(state: .done, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 0, message: "")),
                       .asReported)
    }

    // Done becomes idle when the user has seen the result, and the message is still that
    // turn's.
    func testAnIdleRecordAfterAClosedTurnKeepsTheLastMessage() {
        XCTAssertEqual(Overlay.resolve(state: .idle, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 0, message: "All set.")),
                       .detail("All set."))
    }

    func testTheLastMessageOnlyGoesWithAFinishedTurn() {
        for state in [ProgramStatusReport.State.working, .blocked, .error] {
            XCTAssertEqual(Overlay.resolve(state: state, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 0, message: "All set.")),
                           .asReported, "\(state)")
        }
    }

    // Background wins over the done detail: the message belongs to a turn that is not the news.
    func testBackgroundWinsOverTheDoneDetail() {
        XCTAssertEqual(Overlay.resolve(state: .done, isRoot: true, hasMessage: false, facts: facts(turnOpen: false, count: 1, message: "Started it.")),
                       .background(count: 1))
    }

    func testNoFactsMeansAsReported() {
        for state in allStates {
            XCTAssertEqual(Overlay.resolve(state: state, isRoot: true, hasMessage: false, facts: .none), .asReported, "\(state)")
        }
    }
}
