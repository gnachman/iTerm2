//
//  AIChatTrailingVolatileTests.swift
//  iTerm2 ModernTests
//
//  TDD spec for the fix to mutator A (the orchestration <workgroups>
//  snapshot invalidating the prompt cache every turn). The chosen design is
//  "trailing volatile": the snapshot must reach the model but must NOT sit
//  inside the cached prefix. It is regenerated fresh each turn and never
//  persisted, so if it lived inside a cache-marked message its bytes would
//  differ turn over turn and break the cache (that is the bug documented in
//  AIChatHistoryCacheStabilityTests).
//
//  The contract these tests pin down, at the AnthropicRequestBuilder wire
//  level:
//    - AnthropicRequestBuilder gains a `trailingVolatileText` input.
//    - When set, it is appended as an UNMARKED trailing message, placed
//      AFTER the rolling history breakpoint (markLastMessageForCaching).
//    - The snapshot is still present (the model sees current state).
//    - Adding it does not change a single byte of the cached prefix, so the
//      frozen history stays byte-stable across turns and the cache holds.
//
//  These are written before the implementation. With the current stub (the
//  builder ignores trailingVolatileText) the placement/presence tests are
//  RED; they go green once body() appends the trailing message.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class AIChatTrailingVolatileTests: XCTestCase {

    private let workgroups = "<workgroups>\n[ { \"role\" : \"Chat\" } ]\n</workgroups>"

    // MARK: - Fixtures

    private func model() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == "claude-haiku-4-5" }) else {
            throw XCTSkip("claude-haiku-4-5 not in AIMetadata; test skipped")
        }
        return m
    }

    private func sys(_ t: String) -> LLM.Message { LLM.Message(responseID: nil, role: .system, content: t) }
    private func user(_ t: String) -> LLM.Message { LLM.Message(responseID: nil, role: .user, content: t) }
    private func asst(_ t: String) -> LLM.Message { LLM.Message(responseID: nil, role: .assistant, content: t) }

    private func wire(_ messages: [LLM.Message], volatile: String?) throws -> [[String: Any]] {
        let builder = AnthropicRequestBuilder(messages: messages,
                                              provider: LLMProvider(model: try model()),
                                              functions: [],
                                              stream: false,
                                              trailingVolatileText: volatile)
        let obj = try JSONSerialization.jsonObject(with: try builder.body()) as? [String: Any]
        return (obj?["messages"] as? [[String: Any]]) ?? []
    }

    private func blocks(_ m: [String: Any]) -> [[String: Any]] {
        if let s = m["content"] as? String { return [["type": "text", "text": s]] }
        return (m["content"] as? [[String: Any]]) ?? []
    }
    private func blockText(_ b: [String: Any]) -> String { (b["text"] as? String) ?? "" }
    private func isMarked(_ b: [String: Any]) -> Bool { b["cache_control"] != nil }

    /// Canonical bytes of a message with cache_control stripped and a
    /// one-element text-block array normalized to its bare string. Anthropic
    /// treats those two shapes as the same cache key (the rolling breakpoint
    /// in markLastMessageForCaching relies on exactly that), so the cache-key
    /// contribution of a turn must be compared modulo those.
    private func cacheKeyBytes(_ m: [String: Any]) throws -> Data {
        var normalized: [String: Any] = ["role": m["role"] as Any]
        let bs = blocks(m).map { b -> [String: Any] in
            var b = b; b.removeValue(forKey: "cache_control"); return b
        }
        if bs.count == 1, (bs[0]["type"] as? String) == "text" {
            normalized["content"] = bs[0]["text"] as Any
        } else {
            normalized["content"] = bs
        }
        return try JSONSerialization.data(withJSONObject: normalized,
                                          options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func firstTurn(withText text: String, in wire: [[String: Any]]) -> [String: Any]? {
        wire.first { m in blocks(m).contains { blockText($0).contains(text) && !blockText($0).contains("<workgroups>") } }
    }

    // MARK: - The snapshot still reaches the model

    func test_volatileSnapshotIsPresentInRequest() throws {
        let msgs = try wire([sys("S"), user("hi")], volatile: workgroups)
        let all = msgs.flatMap { blocks($0) }.map { blockText($0) }.joined(separator: "\n")
        XCTAssertTrue(all.contains("<workgroups>"),
                      "the current snapshot must still be sent so the model sees live state")
    }

    // MARK: - Placement: unmarked trailing message, frozen turn keeps the marker

    func test_volatile_isAppendedAsUnmarkedTrailingMessage() throws {
        let msgs = try wire([sys("S"), user("hi")], volatile: workgroups)
        guard let last = msgs.last else { return XCTFail("no messages") }
        XCTAssertTrue(blocks(last).contains { blockText($0).contains("<workgroups>") },
                      "the snapshot must be the trailing message")
        XCTAssertFalse(blocks(last).contains { isMarked($0) },
                       "the volatile trailing message must NOT carry a cache_control breakpoint")
    }

    func test_frozenUserTurnKeepsTheRollingBreakpoint() throws {
        let msgs = try wire([sys("S"), user("hi")], volatile: workgroups)
        let hi = firstTurn(withText: "hi", in: msgs) ?? [:]
        XCTAssertTrue(blocks(hi).contains { isMarked($0) && blockText($0) == "hi" },
                      "the frozen user turn (not the snapshot) must carry the rolling breakpoint")
    }

    // MARK: - The snapshot does not perturb the cached prefix

    func test_volatile_doesNotChangeAnyCachedPrefixByte() throws {
        let convo: [LLM.Message] = [sys("S"), user("hi"), asst("ok"), user("hi2")]
        let withNil = try wire(convo, volatile: nil)
        let withWG = try wire(convo, volatile: workgroups)
        XCTAssertEqual(withWG.count, withNil.count + 1,
                       "the snapshot must add exactly one trailing message")
        let prefix = try JSONSerialization.data(withJSONObject: Array(withWG.dropLast()),
                                                options: [.sortedKeys, .withoutEscapingSlashes])
        let baseline = try JSONSerialization.data(withJSONObject: withNil,
                                                  options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertEqual(prefix, baseline,
                       "adding the volatile snapshot must not change any cached-prefix byte")
    }

    // MARK: - Payoff: the frozen turn is byte-stable across turns

    /// The whole point. Turn N sends "hi" as the current turn (with a fresh
    /// snapshot); turn N+1 sends the same "hi" as history (with a different
    /// fresh snapshot). Because the snapshot is a separate trailing message,
    /// the "hi" turn's cache-key bytes are identical across the two turns, so
    /// the cached prefix is read instead of re-created. (With the old prepend
    /// the snapshot lived inside the "hi" block and this drifted -> cache
    /// miss; see AIChatHistoryCacheStabilityTests.)
    func test_frozenTurnByteStableAcrossTurns() throws {
        let turnN = try wire([sys("S"), user("hi")],
                             volatile: "\(workgroups) <!-- turn N -->")
        let turnN1 = try wire([sys("S"), user("hi"), asst("ok"), user("hi2")],
                              volatile: "\(workgroups) <!-- turn N+1 -->")
        guard let hiN = firstTurn(withText: "hi", in: turnN),
              let hiN1 = firstTurn(withText: "hi", in: turnN1) else {
            return XCTFail("could not locate the 'hi' turn in both requests")
        }
        XCTAssertEqual(try cacheKeyBytes(hiN), try cacheKeyBytes(hiN1),
                       "the frozen 'hi' turn must serialize identically whether current or historical")
    }
}
