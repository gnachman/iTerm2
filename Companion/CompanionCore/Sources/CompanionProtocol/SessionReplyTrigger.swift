//
//  SessionReplyTrigger.swift
//  CompanionCore
//
//  Pure decision logic for when the live session view should post a local
//  notification for the agent's reply. Kept free of Message/UI types so it can
//  be unit-tested: the app maps each delivery / typing-status change to a
//  normalized Event and posts a notification whenever handle() returns .fire.
//
//  The subtlety it encodes: the Mac publishes typingStatus:false BEFORE the
//  final reply for a non-streaming model (ChatService stops typing, then
//  finishTurn publishes the reply), and streams growing whole-message snapshots
//  (all delivered non-partial) for others, so no single delivery means "the
//  reply is done". A normal turn therefore fires once we have BOTH a completed
//  turn (typing false) and reply text, whichever arrives second. A user-action
//  request (the agent blocking on the user) fires immediately, since no
//  typing-false follows it.
//

import Foundation

public struct SessionReplyTrigger {
    public enum Event: Equatable {
        /// A text-bearing agent reply delivery, as a raw accumulation chunk
        /// (`.begin` snapshot / `.appendText` / `.appendAttachment` delta, already
        /// cleaned of reasoning/status subparts). The trigger assembles the chunk
        /// into per-id text itself (see `accumulator`), so there is ONE id->text
        /// surface: the caller never assembles text separately and then has to key
        /// it the same way. The chunk's id keys the text so a turn that emits more
        /// than one substantive message (a real answer under id R plus a trailing
        /// note under id S) does not let the last delivery clobber the answer.
        case reply(chunk: StreamingReplyAccumulator.Chunk)
        /// The agent blocked on the user (remote-command / select-session
        /// request). `id` is the request MESSAGE's identity, so a genuinely-new
        /// request fires even when its description happens to match an earlier
        /// fire, while a re-delivery of the same request doesn't double-fire.
        /// `fallback` describes the request, used only when no reply text preceded.
        case userActionRequest(id: String, fallback: String)
        /// Agent typing status changed.
        case typing(Bool)
    }

    public enum Outcome: Equatable {
        case none
        case fire(body: String)
    }

    /// The single per-message-id reply-text surface. Streamed chunks are assembled
    /// here (begin snapshot + text/attachment deltas under a reused id), and this
    /// is the ONLY place that text lives - the trigger reads snapshots back via
    /// `accumulator.text(for:)` rather than keeping a second parallel [id: String]
    /// that had to stay keyed in lockstep by convention.
    private var accumulator = StreamingReplyAccumulator()
    /// The first-seen order of substantive ids, so the body composes the turn's
    /// messages in arrival order instead of dictionary order.
    private var replyOrder: [String] = []
    /// The text already conveyed by a prior fire this turn, per id, so a later
    /// fire shows only what is NEW. Tracking the notified TEXT (not just the id)
    /// means a message that GROWS under one reused id across an approval boundary
    /// still fires its new suffix ("Done, removed 12 files") instead of being
    /// dropped because its id was wholesale-latched.
    private var notifiedTextByID: [String: String] = [:]
    /// Whether a turn START (typing(true)) has been observed. The watch may
    /// subscribe to a chat that already has an unrelated turn in flight (a reused
    /// chat, or activity from another paired device); its trailing typing(false)
    /// must NOT be taken as "our turn ended", or the next delivery would fire a
    /// notification falsely attributed to the message the user just sent.
    private var turnStarted = false
    private var turnComplete = false
    /// Per-turn latch for a completed-turn text fire: fireIfReady fires at most
    /// one text notification per turn (so two growing whole-message snapshots
    /// after typing(false) don't double-fire). A userActionRequest does NOT set
    /// this, so a genuinely-new final answer after an approved remote command can
    /// still fire once.
    private var firedTextThisTurn = false
    /// Request message ids already fired this turn. A block-on-user request is a
    /// distinct actionable state, deduped on IDENTITY (not on body text, which
    /// would drop a real retry of the same command, or a request whose
    /// description equals a just-fired reply). "Any request fired this turn" is
    /// derived as !firedRequestIDs.isEmpty, so there is no separate Bool to keep
    /// in lockstep.
    private var firedRequestIDs: Set<String> = []

    public init() {}

    /// `shouldFire` is consulted with the candidate body BEFORE any latching, so a
    /// fire the caller suppresses (e.g. the chat is on-screen, so the reply was
    /// seen live) does NOT burn the turn's one-fire opportunity or mark text
    /// notified: a later off-screen message in the same turn can still fire.
    /// Defaults to always-fire so unit tests read cleanly.
    public mutating func handle(_ event: Event,
                                shouldFire: (String) -> Bool = { _ in true }) -> Outcome {
        switch event {
        case .typing(true):
            // A new turn started; forget the previous turn entirely. Turn
            // boundaries come from typing(true), which the Mac emits before any
            // of a turn's deliveries (ChatService.agentWorking), so a completed
            // but text-less turn's state is always cleared before the next turn's
            // text can arrive.
            reset()
            turnStarted = true
            return .none
        case .typing(false):
            guard turnStarted else { return .none }
            turnComplete = true
            return fireIfReady(shouldFire)
        case .reply(let chunk):
            // Assemble the chunk into this id's running snapshot, then record the id
            // in arrival order the first time it carries real text. An empty/
            // whitespace snapshot (reasoning-only / status content, under its own id)
            // is not ordered so it neither surfaces nor wipes a real message. Once an
            // id is ordered, later (growing) chunks just extend its accumulated text
            // with no re-scan of replyOrder.
            let id = chunk.id
            let text = accumulator.accumulate(chunk)
            if !replyOrder.contains(id), text.contains(where: { !$0.isWhitespace }) {
                replyOrder.append(id)
            }
            return fireIfReady(shouldFire)
        case .userActionRequest(let id, let fallback):
            // Fire even WITHOUT a preceding typing(true): a block-on-user request is
            // self-evidently actionable and demands user input, so (unlike a plain
            // text delivery) it can't be misattributed to the user's own send. This
            // is exactly the mid-turn-subscribe / reconnect case - when a stranded
            // approval request matters most - where turnStarted is false. Still
            // deduped on request identity so a re-delivery never double-fires.
            guard !firedRequestIDs.contains(id) else { return .none }
            let alreadyFired = firedTextThisTurn || !firedRequestIDs.isEmpty
            let body: String
            let markPreamble: Bool
            if alreadyFired {
                // Something already surfaced this turn: describe THIS request. Do
                // NOT mark reply text notified - the fallback isn't the reply, and
                // marking it would swallow the turn's real answer.
                body = fallback.replyTrimmed
                markPreamble = false
            } else {
                // First surfacing this turn: prefer the agent's preamble text, and
                // mark exactly that as notified. Fall back to the request itself.
                let preamble = unnotifiedBody()
                body = preamble.isEmpty ? fallback.replyTrimmed : preamble
                markPreamble = !preamble.isEmpty
            }
            // Check suppression BEFORE latching, so a suppressed request can still
            // fire (with a fresh id) after the user navigates away.
            guard !body.isEmpty, shouldFire(body) else { return .none }
            if markPreamble { markAllNotified() }
            firedRequestIDs.insert(id)
            return .fire(body: body)
        }
    }

    // Fires the turn's not-yet-notified text once the turn completes, then latches
    // (so growing post-typing(false) snapshots don't double-fire). unnotifiedBody
    // excludes text already conveyed by a userActionRequest preamble, so this
    // fires only genuinely-new text (e.g. a post-approval final answer). The latch
    // happens only when shouldFire accepts the body, so a suppressed fire doesn't
    // consume the turn.
    private mutating func fireIfReady(_ shouldFire: (String) -> Bool) -> Outcome {
        guard turnComplete, !firedTextThisTurn else { return .none }
        let body = unnotifiedBody()
        guard !body.isEmpty, shouldFire(body) else { return .none }
        firedTextThisTurn = true
        markAllNotified()
        return .fire(body: body)
    }

    /// The turn's substantive text not yet conveyed by a fire, in arrival order.
    /// For a growing id this is the NEW suffix beyond what was already notified;
    /// for a replaced (non-superset) id the whole text is treated as new.
    private func unnotifiedBody() -> String {
        replyOrder
            .compactMap { id -> String? in
                guard let full = accumulator.text(for: id) else { return nil }
                let notified = notifiedTextByID[id] ?? ""
                let trimmed: String
                if !notified.isEmpty, full.hasPrefix(notified) {
                    // The NEW suffix beyond what was already notified. The split can
                    // fall mid-sentence ("...answer is 6" | ". Done, removed 12
                    // files"), so strip the SEPARATOR that joined the prefix to the
                    // new text (". "/"\n\n") - but ONLY the separator, never content
                    // punctuation (a leading sign " -5", a version dot ".2", a
                    // markdown bullet "- item", an opening quote/paren).
                    trimmed = Self.strippingLeadingSeparator(full.dropFirst(notified.count))
                        .replyTrimmed
                } else {
                    // A whole (or replaced, non-superset) message: keep any leading
                    // punctuation, which is the message's own text, not a split
                    // artifact.
                    trimmed = full.replyTrimmed
                }
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
            .replyTrimmed
    }

    /// Strip only the SEPARATOR joining an already-notified prefix to its new
    /// suffix: leading whitespace, plus at most ONE dangling sentence/clause
    /// punctuation that is itself followed by whitespace (". Done" -> "Done",
    /// "; more" -> "more"). Content punctuation is preserved, because it is either
    /// not a sentence separator (a markdown bullet "-", an opening "(" or quote) or
    /// not followed by whitespace (a sign " -5" -> "-5", a version dot ".2"). This
    /// avoids a meaning-changing strip like " -5" -> "5".
    private static func strippingLeadingSeparator(_ suffix: Substring) -> String {
        let separators: Set<Character> = [".", ",", ";", ":", "!", "?"]
        var s = suffix.drop(while: { $0.isWhitespace })
        if let first = s.first, separators.contains(first),
           let second = s.dropFirst().first, second.isWhitespace {
            s = s.dropFirst().drop(while: { $0.isWhitespace })
        }
        return String(s)
    }

    private mutating func markAllNotified() {
        for id in replyOrder {
            if let text = accumulator.text(for: id) {
                notifiedTextByID[id] = text
            }
        }
    }

    private mutating func reset() {
        accumulator.reset()
        replyOrder.removeAll()
        notifiedTextByID.removeAll()
        firedRequestIDs.removeAll()
        turnStarted = false
        turnComplete = false
        firedTextThisTurn = false
    }
}

private extension String {
    var replyTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
