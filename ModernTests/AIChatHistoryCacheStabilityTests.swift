//
//  AIChatHistoryCacheStabilityTests.swift
//  iTerm2 ModernTests
//
//  Anthropic prompt caching is a prefix match: any byte change to an
//  already-cached message invalidates the cached prefix from that point
//  on. CompletionsAnthropic's rolling history breakpoint
//  (markLastMessageForCaching) is correct ONLY as long as a message's
//  serialized bytes are identical whether it is the newest turn or a
//  historical one. The orchestration chat re-sends the whole conversation
//  every turn, so a per-turn byte change to any historical message is a
//  real, recurring cache_creation cost.
//
//  This file tracked two mutators found by diffing an AIChatWire log where
//  cache_read repeatedly collapsed to the system+tools floor (14,882 tokens)
//  mid-conversation.
//
//    A. Ephemeral context injected on send, never persisted (both the
//       <workgroups> snapshot and the session-bound <terminal-state>/
//       <visible-screen> block). It landed inside the cached prefix, and
//       because it changes every turn it re-cached the whole history each
//       turn. FIXED: both sources now ride the trailing-volatile channel
//       (ChatAgent routes them to AnthropicRequestBuilder.trailingVolatileText,
//       appended after the cache breakpoint). The tests below now assert the
//       fixed behavior; the byte-stability payoff is asserted at the wire in
//       AIChatTrailingVolatileTests.
//    C. stabilizeSessionReferences (run by the real translate()) rewrites a
//       session guid in prose into @stableID via LIVE session resolution,
//       so a guid-bearing historical turn's bytes change as sessions appear
//       and die between turns. LATENT: this log used stable ids throughout,
//       so C did not fire here; it remains a mutator for chats that carry a
//       raw guid in free text, and is left as-is (documented, not fixed).
//
//  A CAUTION on method. "Wire bytes differ" does NOT by itself imply a
//  cache miss. markLastMessageForCaching promotes a string-content last
//  message to a one-element text-block array to hang cache_control, and the
//  rolling breakpoint is only correct if Anthropic treats a bare string and
//  its one-element text-block form as the SAME cache key. The source log's
//  healthy early cache reads (cache_read climbing 20K -> 53K turn over turn)
//  are empirical proof that it does. So a string vs. one-element-array
//  difference is cache-equivalent, not a break. The C test is immune to this
//  because its CONTENT genuinely differs; it does not rely on a shape
//  difference.
//
//  Hypothesis B (a multi-block assistant reply reshaping across turns) is
//  intentionally NOT tested here, because it is not confirmed as a distinct
//  mutator. See the note at the bottom of this file.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class AIChatHistoryCacheStabilityTests: XCTestCase {

    // MARK: - Fixtures

    private func model() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == "claude-haiku-4-5" }) else {
            throw XCTSkip("claude-haiku-4-5 not in AIMetadata; test skipped")
        }
        return m
    }

    private func storedUser(_ content: Message.Content) -> Message {
        Message(chatID: "chat",
                author: .user,
                content: content,
                sentDate: Date(timeIntervalSince1970: 1_700_000_000),
                uniqueID: UUID())
    }

    /// Serialize a message list the way a real request would, and return the
    /// `messages` array (system is hoisted into its own field by the builder).
    private func wireMessages(_ messages: [LLM.Message]) throws -> [[String: Any]] {
        let provider = LLMProvider(model: try model())
        let builder = AnthropicRequestBuilder(messages: messages,
                                              provider: provider,
                                              functions: [],
                                              stream: false)
        let obj = try JSONSerialization.jsonObject(with: try builder.body()) as? [String: Any]
        return (obj?["messages"] as? [[String: Any]]) ?? []
    }

    private func canonicalBytes(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value,
                                   options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Place `body` as a NON-last (already-cached) turn of `role` and return
    /// that turn's serialized wire dict. Comparing the two forms of the same
    /// logical turn through this proves the cached prefix drifts.
    private func historicalTurn(_ role: LLM.Role, _ body: LLM.Message.Body) throws -> [String: Any] {
        let msgs: [LLM.Message] = [
            LLM.Message(responseID: nil, role: .system, content: "S"),
            LLM.Message(responseID: nil, role: role, body: body),
            LLM.Message(responseID: nil, role: role == .user ? .assistant : .user, content: "x"),
            LLM.Message(responseID: nil, role: .user, content: "next turn"),
        ]
        let wire = try wireMessages(msgs)
        let match = wire.first { ($0["role"] as? String) == (role == .user ? "user" : "assistant") } ?? [:]
        return match
    }

    private func historicalBytes(_ role: LLM.Role, _ body: LLM.Message.Body) throws -> Data {
        try canonicalBytes(try historicalTurn(role, body))
    }

    // MARK: - A. Ephemeral context injected on send, dropped on replay

    /// FIXED (was mutator A, <workgroups> variant). The snapshot is no longer
    /// baked into the user body. Orchestration surfaces it as volatile context
    /// (OrchestrationToolProvider.volatileContext), which the agent routes to
    /// AnthropicRequestBuilder.trailingVolatileText -> appended after the cache
    /// breakpoint (byte-stability asserted at the wire in
    /// AIChatTrailingVolatileTests). So the persisted/replayed user turn carries
    /// no snapshot and cannot drift the cached prefix.
    func test_workgroupsSnapshot_ridesAsVolatileContext_notBakedIntoUserBody() throws {
        // Orchestration still surfaces the current snapshot...
        let orchestration = OrchestrationToolProvider.orchestration(externalInvoker: { _, _, _, _ in })
        XCTAssertTrue((orchestration.volatileContext() ?? "").contains("<workgroups>"),
                      "orchestration must surface the current snapshot as volatile context")
        // ...but only orchestration turns carry it.
        let sessionBound = OrchestrationToolProvider.sessionBound(
            enableRequestHandler: { _ in },
            externalInvoker: { _, _, _, _ in },
            offerWatchers: { false })
        XCTAssertNil(sessionBound.volatileContext(),
                     "non-orchestration turns carry no workgroups snapshot")
        // The persisted/replayed user turn contains no snapshot, so it cannot
        // drift the cached prefix the way the baked-in prepend did.
        let stored = storedUser(.markdown("Investigate the failing build."))
        let replayedBody = ChatAgent.translateForTesting([stored], resolve: { _ in nil })[0].body
        XCTAssertFalse(replayedBody.content.contains("<workgroups>"),
                       "the user turn must never carry the snapshot in history")
    }

    /// FIXED (was mutator A, <terminal-state>/<visible-screen> variant). The
    /// session-bound auto-provided context now rides the SAME trailing-volatile
    /// channel as the workgroups snapshot instead of being appended to the user
    /// body. ChatAgent.combinedVolatileText is the routing point: it merges the
    /// volatile sources (provider snapshot, auto-provided terminal/screen),
    /// drops nils/empties, and returns nil when there is nothing to add (so
    /// ordinary turns carry no trailing message). The byte-stability payoff is
    /// asserted at the wire in AIChatTrailingVolatileTests.
    func test_combinedVolatileText_mergesSourcesAndDropsEmpties() {
        // Both sources present (defensive combine): joined with a newline.
        XCTAssertEqual(ChatAgent.combinedVolatileText(["<workgroups>…</workgroups>",
                                                       "<terminal-state>…</terminal-state>"]),
                       "<workgroups>…</workgroups>\n<terminal-state>…</terminal-state>")
        // Only one source (the common case): passed through unchanged.
        XCTAssertEqual(ChatAgent.combinedVolatileText([nil, "<terminal-state>…</terminal-state>"]),
                       "<terminal-state>…</terminal-state>")
        // Nils and empties are dropped.
        XCTAssertEqual(ChatAgent.combinedVolatileText(["", nil, "x"]), "x")
        // Nothing to add -> nil -> no trailing volatile message at all.
        XCTAssertNil(ChatAgent.combinedVolatileText([nil, ""]))
        XCTAssertNil(ChatAgent.combinedVolatileText([]))
    }

    /// Negative control, routed through the FULL translate path (repair +
    /// stabilizeSessionReferences), not just structured replay. A plain user
    /// turn with no injected context and no guid replays byte-identically, so
    /// the drift in the A tests is caused by the injected-but-not-persisted
    /// context, not by the reload path mangling plain turns.
    func test_plainUserTurn_replaysByteIdentically() throws {
        let userText = "Plain question with no injected context and no ids."
        let stored = storedUser(.markdown(userText))
        let replayedBody = ChatAgent.translateForTesting([stored], resolve: { _ in nil })[0].body
        XCTAssertEqual(replayedBody, .text(userText))
        XCTAssertEqual(try historicalBytes(.user, .text(userText)),
                       try historicalBytes(.user, replayedBody),
                       "a plain turn must produce identical bytes fresh and replayed")
    }

    // MARK: - B. NOT CONFIRMED (see note)
    //
    // The log shows an assistant message whose wire form grows from a bare
    // string to a multi-.text-block array over successive requests (string
    // -> [text,text] -> ... -> six blocks; block[0] byte-stable, a new block
    // each request). It is tempting to call that a reshape mutator, but three
    // things must be resolved before a test can honestly confirm it, and none
    // is settled:
    //
    //   1. The originally-stated mechanism (committedMessage flattening a
    //      multi-block reply to .markdown(body.content), array -> string)
    //      cannot break the cache: committedMessage runs only for the
    //      non-streaming FINAL reply, whose multi-block form never reaches a
    //      request -- every turn starts with load() rebuilding from storage,
    //      so the first cached form of that reply is already the flattened
    //      string, and stable thereafter.
    //
    //   2. The observed direction is string -> array, and the array grows by
    //      genuinely NEW content each step. New content invalidates the prefix
    //      under ANY correct serialization; that is not evidence of a shape
    //      mutator. An equal-content isolation (joined "first\nsecond" vs a
    //      two-block ["first","second"]) is the only fair comparison, and it
    //      is beyond the string/one-array normalization the cache relies on --
    //      but see (3).
    //
    //   3. Whether that equal-content reshape ever actually drifts ACROSS
    //      turns is unknown. A stored message's shape settles when its own
    //      turn ends (streaming append/appendAttachment/commit + reasoning-
    //      subpart stripping all run during the stream). Whether the growing
    //      intermediate forms in the log reach the wire as separate requests
    //      depends on whether mid-turn tool-result re-entries build the next
    //      request from the reloaded conversation or from the in-flight
    //      controller's in-memory copy -- which this suite does not exercise.
    //
    // Confirming B requires driving the real accumulation path
    // (Message.append / appendAttachment / removeReasoningStatusSubparts) to
    // produce the stored .multipart, establishing that a mid-turn in-memory
    // form actually reaches a request, AND a live cache_read measurement to
    // prove the two forms are not cache-equivalent. Deferred until then; a
    // hand-built fixture asserting "bytes differ" would only re-state the
    // flatten mechanics in isolation, not the cost bug.

    // MARK: - C. Live session-guid resolution mutates historical turns

    /// CONFIRMS mutator C. The real reload path runs stabilizeSessionReferences,
    /// which rewrites a session guid in prose into an @stableID mention when
    /// (and only when) that guid resolves to a live session. So the SAME
    /// stored historical turn serializes to different bytes depending on live
    /// session state, and its bytes change across turns as sessions appear and
    /// die. The plain structured-replay seam cannot see this; the full
    /// translate path can.
    func test_guidBearingTurn_bytesDependOnLiveSessionResolution() throws {
        let guid = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let stableID = "ptys_9QK3ZM7WX4VBT"
        let stored = storedUser(.markdown("check session \(guid) then continue"))

        // Session absent -> guid stays verbatim.
        let whenAbsent = ChatAgent.translateForTesting([stored], resolve: { _ in nil })[0].body
        // Session live -> guid rewritten to @stableID.
        let whenLive = ChatAgent.translateForTesting([stored], resolve: { $0 == guid ? stableID : nil })[0].body

        XCTAssertTrue(whenAbsent.content.contains(guid))
        XCTAssertTrue(whenLive.content.contains("@\(stableID)"))
        XCTAssertNotEqual(try historicalBytes(.user, whenAbsent),
                          try historicalBytes(.user, whenLive),
                          "a guid-bearing historical turn's bytes depend on live session state -> cache miss")
    }
}
