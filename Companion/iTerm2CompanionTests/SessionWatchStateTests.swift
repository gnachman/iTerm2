//
//  SessionWatchStateTests.swift
//  iTerm2CompanionTests
//
//  Direct tests for the extracted session-view reply-watch ownership state. This
//  is the value type that concentrates the token/tab/chatID/claim-sequence/
//  departed-token transitions that used to be scattered inline across AppModel.
//

import XCTest
@testable import iTerm2Companion

final class SessionWatchStateTests: XCTestCase {
    private typealias Tab = AppModel.AppTab

    // MARK: Claim / restore

    func test_restore_revivesLivePrior() {
        var s = SessionWatchState()
        let a = UUID(), b = UUID()
        _ = s.claim(token: a, tab: .chats)
        let claimB = s.claim(token: b, tab: .sessions)
        s.restore(claimB)
        XCTAssertEqual(s.activeToken, a)
    }

    func test_restore_refusesDepartedPrior() {
        var s = SessionWatchState()
        let a = UUID(), b = UUID()
        _ = s.claim(token: a, tab: .chats)
        let claimB = s.claim(token: b, tab: .chats)
        _ = s.depart(token: a)          // A's view popped
        s.restore(claimB)
        XCTAssertNil(s.activeToken)      // must not revive a gone view's token
    }

    func test_restore_noOpWhenSuperseded() {
        var s = SessionWatchState()
        let claimA = s.claim(token: UUID(), tab: .chats)
        let b = UUID()
        _ = s.claim(token: b, tab: .chats)   // supersedes A
        s.restore(claimA)
        XCTAssertEqual(s.activeToken, b)
    }

    // MARK: Finding 6 - departed set is bounded (cleared on each claim)

    func test_claim_clearsDepartedSet_boundingGrowth() {
        var s = SessionWatchState()
        // Simulate many pop-then-new-send visits.
        for _ in 0..<100 {
            let token = UUID()
            _ = s.claim(token: token, tab: .chats)
            _ = s.depart(token: token)       // view pops -> token departed
        }
        // Only the most recent departure can still be relevant to a restore; the
        // set must not accumulate one UUID per visit for the life of the pairing.
        XCTAssertLessThanOrEqual(s.departedCount, 1)
    }

    // MARK: Reuse / install / teardown

    func test_reuseIfSameChat_transfersOwnershipNoInstall() {
        var s = SessionWatchState()
        let a = UUID(), b = UUID()
        _ = s.claim(token: a, tab: .chats)
        s.install(chatID: "X", subscribedHere: true, token: a)
        _ = s.claim(token: b, tab: .sessions)
        XCTAssertTrue(s.reuseIfSameChat("X", token: b))
        XCTAssertTrue(s.owns(b))            // ownership transferred to the newer view
        XCTAssertTrue(s.isWatching("X"))    // same watch, no fresh install
    }

    func test_unwindFailedSend_onlyWhenInstalledAndOwned() {
        var s = SessionWatchState()
        let a = UUID(), b = UUID()
        let claim = s.claim(token: a, tab: .chats)
        s.install(chatID: "X", subscribedHere: true, token: a)
        // A follow-up send (token a) that did NOT install must not tear down.
        XCTAssertNil(s.unwindFailedSend(installedWatch: false, token: a, claimSequence: claim.sequence))
        XCTAssertTrue(s.isWatching("X"))
        // A different view's token must not tear down A's watch.
        XCTAssertNil(s.unwindFailedSend(installedWatch: true, token: b, claimSequence: claim.sequence))
        XCTAssertTrue(s.isWatching("X"))
        // The installing send unwinding its own (still the latest claim) tears down.
        XCTAssertEqual(s.unwindFailedSend(installedWatch: true, token: a, claimSequence: claim.sequence)?.chatID, "X")
        XCTAssertNil(s.watchedChatID)
    }

    func test_unwindFailedSend_supersededByNewerReuse_doesNotTearDown() {
        var s = SessionWatchState()
        let token = UUID()   // same per-view token for both sends
        let s1 = s.claim(token: token, tab: .chats)
        s.install(chatID: "C", subscribedHere: true, token: token)
        // S2 (same view) claims (bumps sequence) and REUSES the watch, then succeeds.
        _ = s.claim(token: token, tab: .chats)
        XCTAssertTrue(s.reuseIfSameChat("C", token: token))
        // S1 fails, but it is no longer the latest claim -> must NOT tear down.
        XCTAssertNil(s.unwindFailedSend(installedWatch: true, token: token, claimSequence: s1.sequence))
        XCTAssertTrue(s.isWatching("C"))   // S2's reused watch survives
    }

    // MARK: handOffIfOpening must not clear an unrelated in-flight intent

    func test_handOffIfOpening_preservesUnrelatedIntent() {
        var s = SessionWatchState()
        let a = UUID(), b = UUID()
        _ = s.claim(token: a, tab: .chats)
        s.install(chatID: "C", subscribedHere: true, token: a)
        _ = s.claim(token: b, tab: .chats)              // View B's send supersedes the claim
        XCTAssertTrue(s.recordIntent(chatID: "D", token: b))   // B's in-flight intent targets D
        // Opening C drops the C watch but must NOT clear B's intent, which targets a
        // DIFFERENT chat (D). Keying the cancel off the installed watch's chat (C)
        // instead of activeChatID (D) would wrongly drop D's intent.
        XCTAssertTrue(s.handOffIfOpening("C"))
        XCTAssertTrue(s.isActiveOwner(b))
        XCTAssertTrue(s.needsSubscription("D"))         // D's intent survived (fails if wrongly cleared)
        XCTAssertNil(s.watchedChatID)
    }

    // MARK: removeWatch clears the in-flight intent for its own token (else a
    // deleted watched chat's subscription leaks via needsSubscription).

    func test_removeWatch_clearsIntentForItsOwnToken() {
        var s = SessionWatchState()
        let a = UUID()
        _ = s.claim(token: a, tab: .chats)
        XCTAssertTrue(s.recordIntent(chatID: "C", token: a))
        s.install(chatID: "C", subscribedHere: true, token: a)
        // Steady state after a successful send: activeChatID == C. Tearing down the
        // watch (e.g. chat C deleted) must also clear the intent, or needsSubscription
        // keeps reporting true and the caller skips unsubscribing the dead chat.
        XCTAssertNotNil(s.removeWatch())
        XCTAssertFalse(s.needsSubscription("C"))
    }

    func test_removeWatch_keepsANewerSendsIntent() {
        var s = SessionWatchState()
        let a = UUID(), b = UUID()
        _ = s.claim(token: a, tab: .chats)
        s.install(chatID: "C", subscribedHere: true, token: a)
        // A newer send (view B) is in flight toward a different chat D while C's watch
        // still exists; removing C's watch must not clear B's unrelated intent.
        _ = s.claim(token: b, tab: .chats)
        XCTAssertTrue(s.recordIntent(chatID: "D", token: b))
        _ = s.removeWatch()
        XCTAssertTrue(s.needsSubscription("D"))
    }

    func test_handOffIfOpening_clearsIntentForThatChat() {
        var s = SessionWatchState()
        let a = UUID()
        _ = s.claim(token: a, tab: .chats)
        _ = s.recordIntent(chatID: "C", token: a)   // intent IS for C
        _ = s.handOffIfOpening("C")
        XCTAssertNil(s.activeToken)                  // the matching intent is cancelled
    }

    func test_depart_marksAndTearsDownOwnedWatch() {
        var s = SessionWatchState()
        let a = UUID()
        _ = s.claim(token: a, tab: .chats)
        s.install(chatID: "X", subscribedHere: false, token: a)
        XCTAssertEqual(s.depart(token: a)?.chatID, "X")
        XCTAssertNil(s.watchedChatID)
        XCTAssertNil(s.activeToken)
    }

    func test_needsSubscription_coversWatchAndInFlightIntent() {
        var s = SessionWatchState()
        let a = UUID()
        _ = s.claim(token: a, tab: .chats)
        XCTAssertTrue(s.recordIntent(chatID: "Y", token: a))
        XCTAssertTrue(s.needsSubscription("Y"))   // in-flight intent
        s.install(chatID: "Y", subscribedHere: true, token: a)
        XCTAssertTrue(s.needsSubscription("Y"))   // installed watch
        XCTAssertFalse(s.needsSubscription("Z"))
    }
}
