//
//  SessionReplyTriggerTests.swift
//  CompanionCore
//
//  Covers the reply-notification decision across the delivery orderings the Mac
//  actually produces: streaming (text before turn-ended), non-streaming (the
//  reply arrives AFTER turn-ended), user-action requests (no turn-ended at
//  all), and empty / tool-only turns.
//

import XCTest
@testable import CompanionProtocol

final class SessionReplyTriggerTests: XCTestCase {
    private typealias Event = SessionReplyTrigger.Event
    private typealias Outcome = SessionReplyTrigger.Outcome

    /// Feed a sequence and return the outcomes, so a test asserts exactly one
    /// .fire and its body.
    private func run(_ events: [Event]) -> [Outcome] {
        var trigger = SessionReplyTrigger()
        return events.map { trigger.handle($0) }
    }

    private func fires(_ outcomes: [Outcome]) -> [String] {
        outcomes.compactMap { if case .fire(let body) = $0 { return body } else { return nil } }
    }

    /// A whole-message (or growing-snapshot) text delivery for one message id. It
    /// arrives as a `.begin` chunk: the trigger owns the accumulation, so repeated
    /// growing snapshots under one id REPLACE (prefix growth) exactly as the Mac's
    /// whole-message-snapshot mode produces.
    private func text(_ s: String, id: String = "R") -> Event {
        .reply(chunk: .begin(id: id, preview: s, isLabel: false))
    }

    /// A block-on-user request. Each distinct request has its own id (a distinct
    /// request message), defaulting so single-request tests stay readable.
    private func request(_ fallback: String, id: String = "req") -> Event {
        .userActionRequest(id: id, fallback: fallback)
    }

    // MARK: Streaming (text accumulates BEFORE turn-ended)

    func test_streaming_firesOnTurnEnded_withLatestText() {
        let outcomes = run([
            .turnStarted,
            text("I"),
            text("I don't"),
            text("I don't have a reliable way"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["I don't have a reliable way"])
    }

    func test_streaming_committedMessageAfterTurnEnded_doesNotDoubleFire() {
        // finishTurn publishes a final non-partial message AFTER the turn-ended boundary; it
        // must not produce a second notification.
        let outcomes = run([
            .turnStarted,
            text("partial answer"),
            .turnEnded,
            text("partial answer"), // the committed echo (same id)
        ])
        XCTAssertEqual(fires(outcomes), ["partial answer"])
    }

    // MARK: Non-streaming (the ONLY reply arrives AFTER turn-ended)

    func test_nonStreaming_firesOnDeliveryAfterTurnEnded() {
        let outcomes = run([
            .turnStarted,
            .turnEnded,           // reply not here yet
            text("The whole answer"),
        ])
        XCTAssertEqual(fires(outcomes), ["The whole answer"])
    }

    func test_nonStreaming_turnEndedAlone_doesNotFire() {
        let outcomes = run([.turnStarted, .turnEnded])
        XCTAssertEqual(fires(outcomes), [])
    }

    // MARK: User-action request (no turn-ended follows)

    func test_userActionRequest_firesImmediately_withPrecedingText() {
        let outcomes = run([
            .turnStarted,
            text("Let me take a look at your terminal"),
            request("Run remote command: ls"),
        ])
        XCTAssertEqual(fires(outcomes), ["Let me take a look at your terminal"])
    }

    func test_userActionRequest_firesWithFallback_whenNoText() {
        let outcomes = run([
            .turnStarted,
            request("Run remote command: ls"),
        ])
        XCTAssertEqual(fires(outcomes), ["Run remote command: ls"])
    }

    // MARK: Empty / whitespace turns don't notify

    func test_emptyTextTurn_doesNotFire() {
        let outcomes = run([.turnStarted, text("   "), .turnEnded])
        XCTAssertEqual(fires(outcomes), [])
    }

    // MARK: A second turn in the same watch fires again

    func test_secondTurn_firesAgain() {
        let outcomes = run([
            .turnStarted, text("first"), .turnEnded,
            .turnStarted, text("second"), .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["first", "second"])
    }

    // MARK: Per-turn latch (no stale fire, no double fire)

    func test_textLessTurn_thenRealTurn_firesOnlyRealAnswer() {
        // A turn whose only deliveries were filtered (tool calls) forwards no
        // text; turnStarted for the next turn must clear the completed-but-empty
        // state so the next turn's partial can't fire prematurely.
        let outcomes = run([
            .turnStarted, .turnEnded,        // text-less completed turn
            .turnStarted,                        // next turn starts
            text("Sur"),                          // a partial, mid-turn
            text("Sure, here's the answer"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["Sure, here's the answer"])
    }

    func test_twoTextDeliveriesAfterSingleTurnEnded_firesExactlyOnce() {
        // Fire-once per turn: the first text after completion fires; a second
        // text-bearing delivery in the same turn does not double-fire.
        let outcomes = run([
            .turnStarted,
            .turnEnded,
            text("first message", id: "R1"),
            text("second message", id: "R2"),
        ])
        XCTAssertEqual(fires(outcomes), ["first message"])
    }

    // MARK: A turn we never saw start must not fire (reused chat, other device)

    func test_turnEndedWithoutStart_doesNotFire() {
        // Subscribed mid-turn: the trailing turnEnded + reply of an unrelated
        // in-flight turn must not be attributed to the user's send.
        let outcomes = run([
            .turnEnded,
            text("someone else's reply"),
        ])
        XCTAssertEqual(fires(outcomes), [])
    }

    func test_inFlightTurnIgnored_thenRealTurnFires() {
        let outcomes = run([
            .turnEnded,                       // unrelated in-flight turn ends
            text("unrelated reply", id: "R0"),
            .turnStarted,                        // the user's turn starts
            text("Your actual answer", id: "R1"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["Your actual answer"])
    }

    // MARK: A block-on-user request fires even after a text reply this turn

    func test_userActionRequest_firesAfterTextReplyInSameTurn() {
        let outcomes = run([
            .turnStarted,
            text("Here's what I found"),
            .turnEnded,                       // text reply fires
            request("Run remote command: rm x"),
        ])
        XCTAssertEqual(fires(outcomes), ["Here's what I found", "Run remote command: rm x"])
    }

    func test_userActionRequestThenTurnEnded_doesNotDuplicateReplyText() {
        // Preamble text then a remote command mid-turn, then turnEnded with no
        // further text: the request fires with the preamble; the trailing
        // turnEnded must NOT re-fire the same text.
        let outcomes = run([
            .turnStarted,
            text("Running ls"),
            request("Run remote command: ls"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["Running ls"])
    }

    func test_emptyThenNonEmptySameId_recordsWhenItGainsContent() {
        // An id whose first snapshot is empty (reasoning-only) then gains real text
        // (streamed reply) must be recorded once non-empty - the deferred-scan
        // optimization only skips the re-scan AFTER a non-empty snapshot is stored.
        let outcomes = run([
            .turnStarted,
            text("", id: "R"),
            text("The answer", id: "R"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["The answer"])
    }

    func test_emptyAgentTextAfterRealReply_doesNotWipeIt() {
        // A trailing reasoning/status delivery arrives as an empty snapshot under
        // its OWN message id; it must not clobber the real answer before turnEnded.
        let outcomes = run([
            .turnStarted,
            text("The real answer", id: "R"),
            text("   ", id: "S"),       // reasoning-only preview, stripped to empty
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["The real answer"])
    }

    func test_trailingSecondMessage_doesNotClobberTheAnswer() {
        // Two substantive messages under DIFFERENT ids in one turn: the
        // real answer (R) then a short trailing note (S). The notification must
        // keep the answer, not show S alone (the finding-3 regression).
        let outcomes = run([
            .turnStarted,
            text("The full detailed answer is 42", id: "R"),
            text("Let me know if that helps", id: "S"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes),
                       ["The full detailed answer is 42\n\nLet me know if that helps"])
    }

    func test_finalAnswerAfterApprovedCommand_growingSameId_stillNotifies() {
        // Same as test_finalAnswerAfterApprovedCommand but the Mac GROWS one reused
        // id across the approval boundary (whole-message-snapshot model) instead of
        // allocating a new id. The post-approval suffix must still fire, not be
        // dropped because the id was latched as notified.
        let outcomes = run([
            .turnStarted,
            text("I'll delete the temp files", id: "R"),
            request("Run remote command: rm -rf tmp"),
            text("I'll delete the temp files\n\nDone, removed 12 files", id: "R"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["I'll delete the temp files", "Done, removed 12 files"])
    }

    func test_growingSameId_stripsLeadingPunctuationFromSuffix() {
        // Like the growing-id case above, but the suffix split falls mid-sentence
        // after a period (not a "\n\n" boundary). The follow-up notification must
        // read "Done, removed 12 files", not ". Done, removed 12 files".
        let outcomes = run([
            .turnStarted,
            text("The answer is 6", id: "R"),
            request("Run remote command: rm -rf tmp"),
            text("The answer is 6. Done, removed 12 files", id: "R"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["The answer is 6", "Done, removed 12 files"])
    }

    func test_growingSameId_preservesLeadingSignInSuffix() {
        // The separator strip must NOT eat content punctuation: a suffix beginning
        // with a negative sign must keep it (" -5" -> "-5", not "5" - a sign flip).
        let outcomes = run([
            .turnStarted,
            text("Balance:", id: "R"),
            request("Run remote command: check"),
            text("Balance: -5", id: "R"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["Balance:", "-5"])
    }

    func test_growingSameId_preservesLeadingBulletInSuffix() {
        // A markdown bullet is content, not a separator: "\n- item one" -> "- item
        // one" (strip the leading newline, keep the bullet).
        let outcomes = run([
            .turnStarted,
            text("Here's the list:", id: "R"),
            request("Run remote command: list"),
            text("Here's the list:\n- item one", id: "R"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["Here's the list:", "- item one"])
    }

    func test_suppressedFireDoesNotBurnTurn_laterMessageStillFires() {
        // A fire suppressed for visibility (shouldFire=false, the chat was on
        // screen) must NOT latch: after the user navigates away, a later message in
        // the same turn still fires. Drive shouldFire from a mutable flag.
        var trigger = SessionReplyTrigger()
        var visible = true
        let should: (String) -> Bool = { _ in !visible }

        _ = trigger.handle(.turnStarted, shouldFire: should)
        _ = trigger.handle(.reply(chunk: .begin(id: "R", preview: "Seen live", isLabel: false)),
                           shouldFire: should)
        // Turn completes while visible -> the fire is suppressed and NOT latched.
        let suppressed = trigger.handle(.turnEnded, shouldFire: should)
        XCTAssertEqual(suppressed, .none)

        // User navigates away; a new-id message lands in the same turn. It fires,
        // including the earlier text (which was never marked notified).
        visible = false
        let fired = trigger.handle(.reply(chunk: .begin(id: "S", preview: "Now off-screen", isLabel: false)),
                                   shouldFire: should)
        XCTAssertEqual(fired, .fire(body: "Seen live\n\nNow off-screen"))
    }

    func test_requestWithoutPrecedingTurnStarted_stillFires() {
        // Mid-turn subscribe / reconnect: a block-on-user request arrives with no
        // preceding turnStarted. It must still fire (the user needs to act), unlike
        // a plain text delivery which is gated on turnStarted.
        let outcomes = run([
            request("Run remote command: rm x"),
        ])
        XCTAssertEqual(fires(outcomes), ["Run remote command: rm x"])
    }

    func test_plainTextWithoutTurnStart_stillDoesNotFire() {
        // The turnStarted gate remains for TEXT (a stray delivery must not be
        // attributed to the user's send); only requests bypass it.
        let outcomes = run([
            text("someone else's reply"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), [])
    }

    func test_twoApprovalRequestsInOneTurn_bothFire() {
        // Two safe==false commands in one turn: BOTH need the user.
        let outcomes = run([
            .turnStarted,
            text("I'll do two things"),
            request("Run remote command: rm a", id: "a"),
            request("Run remote command: rm b", id: "b"),
        ])
        XCTAssertEqual(fires(outcomes), ["I'll do two things", "Run remote command: rm b"])
    }

    func test_sameCommandRetriedInOneTurn_bothFire() {
        // The agent retries the IDENTICAL safe==false command (distinct request
        // messages, same description). The retry still needs the user, so it must
        // fire again - deduping on body text would silently drop it.
        let outcomes = run([
            .turnStarted,
            request("Run remote command: ls", id: "req1"),
            request("Run remote command: ls", id: "req2"),
        ])
        XCTAssertEqual(fires(outcomes),
                       ["Run remote command: ls", "Run remote command: ls"])
    }

    func test_requestWhoseDescriptionEqualsFiredReply_stillFires() {
        // Preamble text literally equal to the command it then requests. The text
        // fires on turnEnded; the block-on-user request is a distinct state
        // and must still fire (the user must know approval is now needed), even
        // though its body equals the just-fired reply.
        let outcomes = run([
            .turnStarted,
            text("Run remote command: ls"),
            .turnEnded,
            request("Run remote command: ls"),
        ])
        XCTAssertEqual(fires(outcomes),
                       ["Run remote command: ls", "Run remote command: ls"])
    }

    func test_requestFallbackAfterTextReply_doesNotSwallowLaterAnswer() {
        // A block-on-user request whose body is the FALLBACK (a prior request
        // already fired) must not mark the reply text notified, or the turn's real
        // final answer gets swallowed.
        let outcomes = run([
            .turnStarted,
            text("Working on it", id: "R"),
            request("Run cmd A", id: "a"),                                  // fires "Working on it"
            text("Working on it\n\nHere's my finding: 42", id: "R"),        // R grows
            request("Run cmd B", id: "b"),                                  // fires "Run cmd B" (fallback)
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes),
                       ["Working on it", "Run cmd B", "Here's my finding: 42"])
    }

    func test_finalAnswerAfterApprovedCommand_stillNotifies() {
        // The whole approve-and-continue turn shares one turnStarted..turnEnded span:
        // preamble -> block-on-user request (fires preamble) -> the agent runs the
        // command -> the NEW final answer -> turnEnded. The final answer must
        // fire with only the NEW text (the preamble was already notified).
        let outcomes = run([
            .turnStarted,
            text("I'll delete the temp files", id: "R"),
            request("Run remote command: rm -rf tmp"),
            text("Done, removed 12 files", id: "R2"),
            .turnEnded,
        ])
        XCTAssertEqual(fires(outcomes), ["I'll delete the temp files", "Done, removed 12 files"])
    }
}
