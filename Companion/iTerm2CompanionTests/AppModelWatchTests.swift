//
//  AppModelWatchTests.swift
//  iTerm2CompanionTests
//
//  Unit tests for AppModel's session-watch claim/restore/depart logic and the
//  derived typing indicator - the areas that repeatedly produced review findings
//  (a failed follow-up send tearing down a prior send's watch, restore reviving a
//  departed view's token, a stuck "typing…" indicator). These exercise the
//  SYNCHRONOUS state machine directly; the async subscribe/publish paths are not
//  covered here.
//

import XCTest
@testable import iTerm2Companion

@MainActor
final class AppModelWatchTests: XCTestCase {
    // MARK: Session-watch claim / restore / depart

    func test_restore_doesNotReviveDepartedToken() {
        let model = AppModel()
        let tokenA = UUID()
        let tokenB = UUID()
        _ = model.claimSessionWatch(token: tokenA)      // view A's send claims
        let claimB = model.claimSessionWatch(token: tokenB)  // view B claims (prior = A)
        model.endWatchingSessionChat(token: tokenA)     // view A departs
        model.restoreSessionWatchClaim(claimB)          // B's send fails -> restore
        // A departed, so its token must NOT be revived (would leak a watch for a
        // gone view whose onDisappear won't fire again).
        XCTAssertNil(model.testActiveWatchToken)
    }

    func test_restore_revivesLivePriorToken() {
        let model = AppModel()
        let tokenA = UUID()
        let tokenB = UUID()
        _ = model.claimSessionWatch(token: tokenA)
        let claimB = model.claimSessionWatch(token: tokenB)
        model.restoreSessionWatchClaim(claimB)          // A still present
        XCTAssertEqual(model.testActiveWatchToken, tokenA)
    }

    func test_restore_noOpWhenSuperseded() {
        let model = AppModel()
        let claimA = model.claimSessionWatch(token: UUID())
        let tokenB = UUID()
        _ = model.claimSessionWatch(token: tokenB)      // supersedes A (higher sequence)
        model.restoreSessionWatchClaim(claimA)          // A no longer the latest claim
        XCTAssertEqual(model.testActiveWatchToken, tokenB)
    }

    func test_claim_capturesPriorToken() {
        let model = AppModel()
        let tokenA = UUID()
        _ = model.claimSessionWatch(token: tokenA)
        let claimB = model.claimSessionWatch(token: UUID())
        XCTAssertEqual(claimB.priorToken, tokenA)
    }

    func test_reappear_unmarksDeparted_soRestoreRevives() {
        let model = AppModel()
        let tokenA = UUID()
        let tokenB = UUID()
        _ = model.claimSessionWatch(token: tokenA)
        let claimB = model.claimSessionWatch(token: tokenB)
        model.endWatchingSessionChat(token: tokenA)   // A's onDisappear marks Ta departed
        model.watchViewDidAppear(guid: "g1", token: tokenA)   // ...but A re-appeared (tab switch)
        model.restoreSessionWatchClaim(claimB)         // B fails -> restore Ta, now alive
        XCTAssertEqual(model.testActiveWatchToken, tokenA)
    }

    // MARK: Watch teardown on chat deletion (no un-openable notification)

    func test_deleteChat_tearsDownWatchForThatChat() {
        let model = AppModel()
        model.testInstallWatch(chatID: "chatX", token: UUID())
        model.deleteChat(chatID: "chatX")
        XCTAssertNil(model.testWatchedChatID)
    }

    func test_deleteChat_leavesWatchForADifferentChat() {
        let model = AppModel()
        model.testInstallWatch(chatID: "chatY", token: UUID())
        model.deleteChat(chatID: "chatX")
        XCTAssertEqual(model.testWatchedChatID, "chatY")
    }

    func test_deleteChat_clearsStaleTypingAndFailureEntries() {
        let model = AppModel()
        // Agent mid-turn (typing) with a prior refresh failure when the user
        // swipe-deletes the chat: both per-chat entries must be pruned here, not
        // linger until the Mac's delete echo pushes a fresh list.
        model.testSetAgentTyping("chatX", true)
        model.testSetRefreshFailure("chatX", 3)
        model.deleteChat(chatID: "chatX")
        XCTAssertFalse(model.testAgentTypingChats.contains("chatX"))
        XCTAssertFalse(model.testRefreshFailureChats.contains("chatX"))
    }

    // MARK: onDisappear must distinguish a tab switch from a pop (else switching
    // to the Chats tab to wait for a reply kills the watch that would notify).

    func test_sessionViewDisappear_keepsWatchWhenStillMounted() {
        let model = AppModel()
        let token = UUID()
        model.navigationPath = [.session(guid: "g1", title: "S", originatingChatID: nil)]
        model.watchViewDidAppear(guid: "g1", token: token)
        model.testInstallWatch(chatID: "chatX", token: token)
        model.sessionViewDidDisappear(guid: "g1", token: token)   // tab switch: still mounted
        XCTAssertEqual(model.testWatchedChatID, "chatX")
    }

    func test_sessionViewDisappear_tearsDownWhenPopped() {
        let model = AppModel()
        let token = UUID()
        model.navigationPath = []
        model.sessionsPath = []
        model.watchViewDidAppear(guid: "g1", token: token)
        model.testInstallWatch(chatID: "chatX", token: token)
        model.sessionViewDidDisappear(guid: "g1", token: token)   // genuine pop: gone
        XCTAssertNil(model.testWatchedChatID)
    }

    // The SAME guid mounted twice (two nav stacks, or twice in one stack): popping
    // the view that OWNS the watch must tear it down even though a co-mounted
    // duplicate of the guid is still on screen (else the watch + its Mac
    // subscription leak, firing reply notifications with no session view up).
    func test_sessionViewDisappear_duplicateGuid_popOwnerTearsDownWatch() {
        let model = AppModel()
        let tokenA = UUID()
        let tokenB = UUID()
        // Two SessionViews for g1 are mounted (e.g. one per tab); A owns the watch.
        model.navigationPath = [.session(guid: "g1", title: "S", originatingChatID: nil)]
        model.sessionsPath = [.session(guid: "g1", title: "S", originatingChatID: nil)]
        model.watchViewDidAppear(guid: "g1", token: tokenA)
        model.watchViewDidAppear(guid: "g1", token: tokenB)
        model.testInstallWatch(chatID: "chatX", token: tokenA)
        // A pops: its destination leaves one stack, so only one g1 remains mounted.
        model.navigationPath = []
        model.sessionViewDidDisappear(guid: "g1", token: tokenA)
        XCTAssertNil(model.testWatchedChatID)   // A's watch must not leak behind B
    }

    // The mirror: with a duplicate mounted, a NON-owner tab-switching away (its
    // destination still present) must NOT tear down the owner's watch.
    func test_sessionViewDisappear_duplicateGuid_tabSwitchKeepsWatch() {
        let model = AppModel()
        let tokenA = UUID()
        let tokenB = UUID()
        model.navigationPath = [.session(guid: "g1", title: "S", originatingChatID: nil)]
        model.sessionsPath = [.session(guid: "g1", title: "S", originatingChatID: nil)]
        model.watchViewDidAppear(guid: "g1", token: tokenA)
        model.watchViewDidAppear(guid: "g1", token: tokenB)
        model.testInstallWatch(chatID: "chatX", token: tokenA)
        // B's onDisappear fires (tab switch) but both destinations remain mounted.
        model.sessionViewDidDisappear(guid: "g1", token: tokenB)
        XCTAssertEqual(model.testWatchedChatID, "chatX")
    }

    // MARK: Duplicate conversation in a stack must survive popping one copy
    // (exercises the real stack->Set collapse in conversationIDs(in:), which the
    // pure SessionNavTeardown test can't reach with Set inputs).

    func test_duplicateConversationInStack_popOneCopy_isRetained() {
        let model = AppModel()
        model.openChatID = "A"
        // conv(A) at the root, a session pushed above it, then conv(A) again (an
        // @-mention reopened A over its own session). The stack collapses to {A}.
        let dupStack: [AppModel.Destination] = [
            .conversation(chatID: "A"),
            .session(guid: "g", title: "S", originatingChatID: nil),
            .conversation(chatID: "A"),
        ]
        model.navigationPath = dupStack
        // Pop only the top conv(A); the root copy remains, so A must NOT be torn
        // down. A teardown would clear the open-conversation display (openChatID=nil).
        model.navigationPath = Array(dupStack.dropLast())
        XCTAssertEqual(model.openChatID, "A")
    }

    // MARK: Derived typing indicator (per-chat, so a tab switch reflects the
    // right chat instead of a blanket reset).

    func test_isAgentTyping_reflectsOpenChat() {
        let model = AppModel()
        model.testSetAgentTyping("chatY", true)
        model.openChatID = "chatX"
        XCTAssertFalse(model.isAgentTyping)             // Y typing, X open
        model.openChatID = "chatY"
        XCTAssertTrue(model.isAgentTyping)              // switching to Y shows its state
    }

    func test_isAgentTyping_falseWhenNoOpenChat() {
        let model = AppModel()
        model.testSetAgentTyping("chatY", true)
        model.openChatID = "chatY"
        XCTAssertTrue(model.isAgentTyping)              // Y typing and open
        // Clearing the open chat flips it off even though Y is STILL typing: the
        // indicator is scoped to the open chat, not "any chat is typing". This
        // transition makes the typing setup load-bearing (a broken lookup that
        // returned !agentTypingChats.isEmpty would still show true here).
        model.openChatID = nil
        XCTAssertFalse(model.isAgentTyping)
    }
}
