//
//  CompanionSubscribeSnapshotTests.swift
//  iTerm2 ModernTests
//
//  When a phone subscribes to a chat, handleSubscribe snapshots the current live
//  state (not just history) so a turn already in flight is reflected. Two snapshots,
//  both sent ONLY when BOTH ends are at turnLifecycleRevision (a phone that treats
//  typing as spinner-only and consumes turnLifecycle):
//    - typingStatus(true): re-seeds the spinner (from TypingStatusModel).
//    - turnLifecycle(.started): arms the phone's reply trigger for a turn it joined
//      mid-flight (from TurnStatusModel, which stays true across a park, unlike
//      typing) - so a phone subscribing DURING a park still fires when the turn
//      eventually ends, instead of dropping the reply on the trigger's turnStarted
//      guard. A legacy phone would mis-arm from a typing snapshot, so it gets
//      nothing (pre-snapshot behavior). subscribeSnapshotMessages is the pure
//      decision of which unsolicited state messages to send.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionSubscribeSnapshotTests: XCTestCase {
    // turnLifecycleRevision is 8 (CompanionProtocolVersion); ModernTests can't link
    // the CompanionProtocol module, so the boundary is spelled out here.
    private let rev = 8

    private func messages(agentTyping: Bool = false,
                          turnInProgress: Bool = false,
                          local: Int,
                          peer: Int) -> [CompanionHostMessage] {
        CompanionHostBridge.subscribeSnapshotMessages(
            chatID: "c", agentTyping: agentTyping, turnInProgress: turnInProgress,
            localRevision: local, peerRevision: peer)
    }

    private func isTypingSnapshot(_ m: CompanionHostMessage?) -> Bool {
        if case .typingStatus(true, .agent, "c") = m { return true }
        return false
    }
    private func isTurnStartedSeed(_ m: CompanionHostMessage?) -> Bool {
        if case .turnLifecycle(.started, "c") = m { return true }
        return false
    }

    func testTypingSnapshotSentWhenTypingAndBothRev8() {
        let msgs = messages(agentTyping: true, local: rev, peer: rev)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertTrue(isTypingSnapshot(msgs.first))
    }

    func testTurnLifecycleSeedSentWhenParkedMidTurn() {
        // The parked-mid-turn case: typing is off (park cleared it) but the turn is
        // in flight - seed turnLifecycle(.started), NOT typing.
        let msgs = messages(turnInProgress: true, local: rev, peer: rev)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertTrue(isTurnStartedSeed(msgs.first))
    }

    func testBothSnapshotsWhenTypingAndTurnInProgress() {
        let msgs = messages(agentTyping: true, turnInProgress: true, local: rev, peer: rev)
        XCTAssertEqual(msgs.count, 2)
        XCTAssertTrue(msgs.contains(where: isTypingSnapshot))
        XCTAssertTrue(msgs.contains(where: isTurnStartedSeed))
    }

    func testNoSnapshotToLegacyPeer() {
        XCTAssertTrue(messages(agentTyping: true, turnInProgress: true,
                               local: rev, peer: rev - 1).isEmpty)
    }

    func testNoSnapshotWhenMacIsLegacy() {
        // A rev-8 phone against a rev-7 mac drives its trigger from typing, so the
        // mac must send neither snapshot.
        XCTAssertTrue(messages(agentTyping: true, turnInProgress: true,
                               local: rev - 1, peer: rev).isEmpty)
    }

    func testNoSnapshotWhenIdle() {
        XCTAssertTrue(messages(local: rev, peer: rev).isEmpty)
    }

    // The ONE predicate both the subscribe-seed (turnLifecycle(.started)) and the
    // live-forward (turnLifecycle(.ended)) gate on, so a phone can't be seeded
    // .started yet never receive the live .ended (or vice versa). Requires BOTH ends
    // at turnLifecycleRevision.
    func testPeerConsumesTurnLifecycleRequiresBothEnds() {
        XCTAssertTrue(CompanionHostBridge.peerConsumesTurnLifecycle(localRevision: rev, peerRevision: rev))
        XCTAssertFalse(CompanionHostBridge.peerConsumesTurnLifecycle(localRevision: rev, peerRevision: rev - 1))
        XCTAssertFalse(CompanionHostBridge.peerConsumesTurnLifecycle(localRevision: rev - 1, peerRevision: rev))
        XCTAssertFalse(CompanionHostBridge.peerConsumesTurnLifecycle(localRevision: rev - 1, peerRevision: rev - 1))
    }
}
