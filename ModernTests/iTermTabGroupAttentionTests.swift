//
//  iTermTabGroupAttentionTests.swift
//  iTerm2XCTests
//
//  A collapsed tab group's chip shows the most urgent indicator among its
//  member tabs. These tests pin down how members are ranked.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupAttentionTests: XCTestCase {
    private func candidate(_ kind: TabIconKind,
                           priority: Int = 0,
                           dead: Bool? = nil,
                           bell: Bool? = nil) -> TabAttentionCandidate {
        return TabAttentionCandidate(kind: kind,
                                     statusPriority: priority,
                                     isDead: dead ?? (kind == .dead),
                                     ringingBell: bell ?? (kind == .bell))
    }

    private func winner(_ candidates: [TabAttentionCandidate]) -> Int {
        return TabGroupAttention.mostUrgent(candidates)?.index ?? NSNotFound
    }

    private func kind(_ candidates: [TabAttentionCandidate]) -> TabIconKind {
        return TabGroupAttention.mostUrgent(candidates)?.kind ?? .none
    }

    func testEmptyGroupHasNoWinner() {
        XCTAssertNil(TabGroupAttention.mostUrgent([]))
    }

    func testNoIndicatorsHasNoWinner() {
        XCTAssertEqual(winner([candidate(.none), candidate(.none)]), NSNotFound)
    }

    // "Idle" is a background tab whose new output has stopped arriving. It is
    // still unseen output, and the tab shows the same new-output icon, so it
    // counts the same as new output.
    func testIdleCountsAsNewOutput() {
        XCTAssertEqual(winner([candidate(.none), candidate(.idle)]), 1)
        XCTAssertEqual(kind([candidate(.none), candidate(.idle)]), .idle)
        XCTAssertEqual(winner([candidate(.idle), candidate(.newOutput)]), 0, "same tier: first wins")
        XCTAssertEqual(winner([candidate(.idle), candidate(.bell)]), 1)
    }

    // Status, then dead, then bell, then new output: the precedence a single
    // tab uses in -[PTYTab updateIcon].
    func testStatusBeatsDeadBeatsBellBeatsNewOutput() {
        XCTAssertEqual(winner([candidate(.newOutput), candidate(.bell)]), 1)
        XCTAssertEqual(winner([candidate(.dead), candidate(.dead, bell: true)]), 0)
        XCTAssertEqual(winner([candidate(.status, priority: 5), candidate(.status, priority: 5, dead: true)]), 0)
        XCTAssertEqual(winner([candidate(.newOutput),
                               candidate(.idle),
                               candidate(.status, priority: 3),
                               candidate(.bell)]), 2)
    }

    // A group is dead only when every member is. One finished job among
    // several running ones isn't worth flagging the whole group.
    func testDeadOnlyWhenEveryMemberIsDead() {
        XCTAssertEqual(winner([candidate(.none), candidate(.dead)]), NSNotFound)
        XCTAssertEqual(winner([candidate(.dead), candidate(.dead)]), 0)
        XCTAssertEqual(kind([candidate(.dead), candidate(.dead)]), .dead)
        XCTAssertEqual(winner([candidate(.newOutput), candidate(.dead)]), 0)
    }

    // A member showing a status dot still counts as dead if its session ended.
    func testDeadMemberShowingStatusCountsTowardAllDead() {
        let members = [candidate(.dead), candidate(.status, priority: 1, dead: true)]
        XCTAssertEqual(winner(members), 1)
        XCTAssertEqual(kind(members), .status)
    }

    // Any member's bell lights the group, even one whose own icon shows
    // something else because it died. The chip then shows a bell.
    func testBellFromAnyMember() {
        let members = [candidate(.newOutput), candidate(.none), candidate(.dead, bell: true)]
        XCTAssertEqual(winner(members), 2)
        XCTAssertEqual(kind(members), .bell)
    }

    // Statuses are ranked by iTermStatusPrioritySettings, where a lower number
    // is more urgent.
    func testLowerStatusPriorityWins() {
        XCTAssertEqual(winner([candidate(.status, priority: 4),
                               candidate(.status, priority: 1),
                               candidate(.status, priority: 2)]), 1)
    }

    // Ties go to the earliest member so the chip does not flip between tabs
    // that are equally urgent.
    func testTieGoesToFirstMember() {
        XCTAssertEqual(winner([candidate(.bell), candidate(.bell)]), 0)
        XCTAssertEqual(winner([candidate(.none),
                               candidate(.status, priority: 2),
                               candidate(.status, priority: 2)]), 1)
    }
}
