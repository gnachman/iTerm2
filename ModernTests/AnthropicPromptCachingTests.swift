//
//  AnthropicPromptCachingTests.swift
//  iTerm2 ModernTests
//
//  Pure-unit tests for Anthropic prompt caching markers. Asserts the
//  wire shape of `system` and `tools` carries the cache_control
//  ephemeral marker on the right blocks.
//
//  Anthropic's cacheable prefix is ordered tools → system → messages.
//  Each cache_control marker covers everything from the start of that
//  order up through the marked element, so:
//
//      - A marker on the LAST tool covers [tools] only. This is the
//        fallback segment that survives a system change.
//      - A marker on the system block covers [tools + system]. This
//        is the common-case win; both stable, the whole prefix becomes
//        one cache_read.
//      - Tools other than the last do NOT carry the marker (each
//        cache_control creates a separate breakpoint and we're capped
//        at 4 per request).
//      - Empty system / empty tools paths still serialize cleanly with
//        no spurious cache_control fields.
//
//  These tests describe behavior the implementation MUST produce; the
//  feature is implemented in CompletionsAnthropic.swift's
//  AnthropicRequestBuilder.body().
//

import XCTest
@testable import iTerm2SharedARC

final class AnthropicPromptCachingTests: XCTestCase {

    // MARK: - Fixtures

    private func model() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == "claude-haiku-4-5" }) else {
            throw XCTSkip("claude-haiku-4-5 not in AIMetadata; test skipped")
        }
        return m
    }

    /// A trivial codable parameters payload for stub tool declarations.
    private struct EmptyToolArgs: Codable {}

    private func tool(named name: String) -> LLM.AnyFunction {
        return LLM.Function<EmptyToolArgs>(
            decl: ChatGPTFunctionDeclaration(
                name: name,
                description: "Test tool \(name).",
                parameters: JSONSchema(for: EmptyToolArgs(), descriptions: [:])),
            call: { _, _, _ in },
            parameterType: EmptyToolArgs.self)
    }

    private func userMessage(_ text: String) -> LLM.Message {
        return LLM.Message(responseID: nil, role: .user, content: text)
    }

    private func systemMessage(_ text: String) -> LLM.Message {
        return LLM.Message(responseID: nil, role: .system, content: text)
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Body is not a JSON object")
            return [:]
        }
        return obj
    }

    private func buildBody(messages: [LLM.Message],
                           tools: [LLM.AnyFunction]) throws -> [String: Any] {
        let provider = LLMProvider(model: try model())
        let builder = AnthropicRequestBuilder(messages: messages,
                                              provider: provider,
                                              functions: tools,
                                              stream: false)
        return try decode(try builder.body())
    }

    private let ephemeral: [String: String] = ["type": "ephemeral"]

    // MARK: - System block shape

    /// When a system message is present, the body must serialize
    /// `system` as the structured array form (a list of typed text
    /// blocks), not the legacy bare-string form. The single text block
    /// carries the user's system prompt verbatim.
    func testSystemSerializedAsArrayOfTextBlocks() throws {
        let json = try buildBody(
            messages: [systemMessage("Sys text"), userMessage("hi")],
            tools: [])
        guard let system = json["system"] as? [[String: Any]] else {
            XCTFail("Expected system to be an array of blocks, got \(String(describing: json["system"]))")
            return
        }
        XCTAssertEqual(system.count, 1, "Expected exactly one system text block")
        XCTAssertEqual(system[0]["type"] as? String, "text")
        XCTAssertEqual(system[0]["text"] as? String, "Sys text")
    }

    /// The system text block must carry an ephemeral cache_control
    /// marker. In Anthropic's tools → system → messages prefix order,
    /// this breakpoint covers [tools + system] — the common-case
    /// win when both are stable for the chat. Without it we'd at
    /// best fall back to caching tools alone (or nothing, if no
    /// tools are exposed).
    func testSystemBlockHasEphemeralCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("Sys text"), userMessage("hi")],
            tools: [])
        let system = (json["system"] as? [[String: Any]]) ?? []
        XCTAssertEqual(system.first?["cache_control"] as? [String: String],
                       ephemeral,
                       "system block missing cache_control: ephemeral")
    }

    /// Conversations with no system message must not synthesize one.
    /// The `system` field should be omitted entirely (or null) so we
    /// don't surprise Anthropic with an empty array.
    func testNoSystemMessage_OmitsSystemField() throws {
        let json = try buildBody(
            messages: [userMessage("hi")],
            tools: [])
        let value = json["system"]
        if value == nil { return }
        if value is NSNull { return }
        XCTFail("Expected system field to be omitted; got \(String(describing: value))")
    }

    // MARK: - Tools breakpoint

    /// When tools are present, the LAST tool in the array must carry an
    /// ephemeral cache_control marker. In Anthropic's tools → system
    /// → messages prefix order, this covers [tools] only — the
    /// fallback segment that still hits when the system prompt
    /// changes (because [tools] is a strict prefix of [tools +
    /// system] and remains valid even when the longer segment
    /// invalidates). Marking only the last tool also caches the
    /// entire tools array as one segment without burning extra
    /// breakpoints on the earlier tools.
    func testLastToolHasEphemeralCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("S"), userMessage("hi")],
            tools: [tool(named: "alpha"),
                    tool(named: "beta"),
                    tool(named: "gamma")])
        guard let tools = json["tools"] as? [[String: Any]] else {
            XCTFail("Expected tools array, got \(String(describing: json["tools"]))")
            return
        }
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools.last?["name"] as? String, "gamma",
                       "Tool order must be preserved")
        XCTAssertEqual(tools.last?["cache_control"] as? [String: String],
                       ephemeral,
                       "Last tool must carry cache_control: ephemeral")
    }

    /// Tools other than the last must NOT carry a cache_control marker.
    /// Anthropic only allows four cache breakpoints per request, and
    /// every marked tool burns one — we want the breakpoint count to
    /// stay bounded regardless of how many tools the chat exposes.
    func testNonLastToolsHaveNoCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("S"), userMessage("hi")],
            tools: [tool(named: "alpha"),
                    tool(named: "beta"),
                    tool(named: "gamma")])
        let tools = (json["tools"] as? [[String: Any]]) ?? []
        for nonLast in tools.dropLast() {
            XCTAssertNil(nonLast["cache_control"],
                         "Non-last tool \(nonLast["name"] ?? "?") must not carry cache_control")
        }
    }

    /// A single-tool request also marks that tool (it IS the last
    /// tool). The previous test trivially holds with zero non-last
    /// tools; this guarantees the last-element rule isn't accidentally
    /// shorthand for "more than one tool".
    func testSingleToolHasCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("S"), userMessage("hi")],
            tools: [tool(named: "only")])
        let tools = (json["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["cache_control"] as? [String: String], ephemeral)
    }

    /// Zero-tool requests must not include a `tools` field at all
    /// (matches the existing non-cached behavior); the cache_control
    /// pass should not invent an empty array or any other shape.
    func testNoTools_OmitsToolsField() throws {
        let json = try buildBody(
            messages: [systemMessage("S"), userMessage("hi")],
            tools: [])
        let value = json["tools"]
        if value == nil { return }
        if value is NSNull { return }
        XCTFail("Expected tools field to be omitted; got \(String(describing: value))")
    }

    // MARK: - Combined and no-prefix cases

    /// With both system and tools present, BOTH breakpoints fire.
    /// The two markers create nested cache segments per Anthropic's
    /// tools → system → messages prefix order:
    ///
    ///   - last-tool marker → [tools]  (fallback; survives a system change)
    ///   - system  marker → [tools + system]  (common-case longest match)
    ///
    /// Keep both. Dropping the last-tool marker as "redundant"
    /// because the system marker also covers tools would silently
    /// destroy the fallback: any system edit would invalidate
    /// everything and we'd pay cache_creation on tools again.
    func testSystemAndTools_BothCarryCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("S"), userMessage("hi")],
            tools: [tool(named: "alpha"), tool(named: "beta")])
        let system = (json["system"] as? [[String: Any]]) ?? []
        let tools = (json["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(system.first?["cache_control"] as? [String: String], ephemeral)
        XCTAssertEqual(tools.last?["cache_control"] as? [String: String], ephemeral)
    }

    /// A request with neither system nor tools (e.g. the rename
    /// sub-conversation) must produce no cache_control markers at all.
    /// The body must still serialize without error.
    func testNoSystemNoTools_NoCacheControl() throws {
        let json = try buildBody(
            messages: [userMessage("hi")],
            tools: [])
        XCTAssertNil(json["system"])
        XCTAssertNil(json["tools"])
    }

    // MARK: - Byte-exact determinism (the actual cache-key invariant)

    // Helpers for the determinism tests below. They take the JSON-
    // decoded dict so we can re-serialize the cacheable segments
    // (system / tools) under a canonical ordering. The point is to
    // assert "these bytes are equal", but we re-encode rather than
    // comparing the raw body bytes because the messages array is
    // expected to differ between the two requests we compare.
    private func canonicalJSON(_ value: Any) throws -> Data {
        return try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func systemSegment(_ json: [String: Any]) throws -> Data {
        let raw: Any = json["system"] as Any
        return try canonicalJSON(raw)
    }

    private func toolsSegment(_ json: [String: Any]) throws -> Data {
        let raw: Any = json["tools"] as Any
        return try canonicalJSON(raw)
    }

    /// Two requests built with the same system message and the same
    /// tools (but DIFFERENT message bodies) must produce byte-identical
    /// JSON for the system block. Anthropic keys the cache on exact
    /// prefix bytes; any non-determinism here means cache_creation
    /// gets billed every turn and cache_read never fires, silently
    /// nullifying the whole feature.
    func testSystemSegmentByteIdenticalAcrossRequests() throws {
        let json1 = try buildBody(
            messages: [systemMessage("Sys text"), userMessage("first turn")],
            tools: [tool(named: "alpha"), tool(named: "beta")])
        let json2 = try buildBody(
            messages: [systemMessage("Sys text"),
                       userMessage("first turn"),
                       LLM.Message(responseID: nil, role: .assistant, content: "answer"),
                       userMessage("second turn")],
            tools: [tool(named: "alpha"), tool(named: "beta")])
        XCTAssertEqual(try systemSegment(json1), try systemSegment(json2),
                       "system bytes drifted across requests; cache will never hit")
    }

    /// Same idea for the tools segment: two requests with the same
    /// tool definitions must serialize tools byte-identically. Loose
    /// iteration order (e.g. a Set somewhere along the build path) or
    /// any non-stable field ordering inside a tool would break this.
    func testToolsSegmentByteIdenticalAcrossRequests() throws {
        let tools = [tool(named: "alpha"), tool(named: "beta"), tool(named: "gamma")]
        let json1 = try buildBody(
            messages: [systemMessage("S"), userMessage("first")],
            tools: tools)
        let json2 = try buildBody(
            messages: [systemMessage("S"),
                       userMessage("first"),
                       LLM.Message(responseID: nil, role: .assistant, content: "ok"),
                       userMessage("second")],
            tools: tools)
        XCTAssertEqual(try toolsSegment(json1), try toolsSegment(json2),
                       "tools bytes drifted across requests; cache will never hit")
    }

    /// The same builder, run twice with the same inputs, must produce
    /// byte-identical bodies end-to-end. This is the strictest form of
    /// the determinism check; if it ever fails the cause is almost
    /// always JSONEncoder ordering of a struct's nested Codable
    /// dictionary rather than any property of the cache code itself.
    func testIdenticalInputsProduceIdenticalBodies() throws {
        let messages: [LLM.Message] = [
            systemMessage("System."),
            userMessage("Hi."),
            LLM.Message(responseID: nil, role: .assistant, content: "Hello!"),
            userMessage("Tool time."),
        ]
        let tools = [tool(named: "alpha"), tool(named: "beta")]
        let provider = LLMProvider(model: try model())
        let body1 = try AnthropicRequestBuilder(messages: messages,
                                                provider: provider,
                                                functions: tools,
                                                stream: false).body()
        let body2 = try AnthropicRequestBuilder(messages: messages,
                                                provider: provider,
                                                functions: tools,
                                                stream: false).body()
        XCTAssertEqual(body1, body2,
                       "Identical inputs produced different bytes; cache_read will never fire")
    }

    // MARK: - Conversation history caching (rolling breakpoint)

    // The orchestration chat re-sends the whole conversation every turn.
    // Without a breakpoint in `messages`, that history (tens of thousands
    // of tokens of accumulated tool results) is billed at full input rate
    // on every request. We place ONE ephemeral marker on the last content
    // block of the last message each turn. Anthropic excludes cache_control
    // from the cache key and reads the longest matching prefix, so the
    // marker "rolls" forward: the block marked this turn becomes a cache
    // read next turn once a newer turn is appended after it.

    /// The last content block of the last message must carry an ephemeral
    /// cache_control marker. This is the rolling history breakpoint.
    func testLastMessageCarriesCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("S"),
                       userMessage("first"),
                       LLM.Message(responseID: nil, role: .assistant, content: "answer"),
                       userMessage("second")],
            tools: [tool(named: "alpha")])
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        guard let last = messages.last,
              let content = last["content"] as? [[String: Any]],
              let lastBlock = content.last else {
            XCTFail("Last message should serialize content as an array of blocks; got \(String(describing: messages.last?["content"]))")
            return
        }
        XCTAssertEqual(lastBlock["cache_control"] as? [String: String], ephemeral,
                       "Last content block of the last message must carry cache_control: ephemeral")
    }

    /// A string-content last message must convert to a single text block
    /// carrying the marker, with the original text preserved verbatim.
    /// (String content has nowhere to hang a cache_control field.)
    func testStringLastMessageConvertsToTextBlockPreservingText() throws {
        let json = try buildBody(
            messages: [userMessage("only turn")],
            tools: [])
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        guard let last = messages.last,
              let content = last["content"] as? [[String: Any]],
              let block = content.last else {
            XCTFail("Expected array content on the last message; got \(String(describing: messages.last?["content"]))")
            return
        }
        XCTAssertEqual(block["type"] as? String, "text")
        XCTAssertEqual(block["text"] as? String, "only turn")
        XCTAssertEqual(block["cache_control"] as? [String: String], ephemeral)
    }

    /// Only the last message carries a marker. Marking earlier messages
    /// would burn extra breakpoints (capped at 4) and cache history that
    /// the rolling last-message marker already covers.
    func testNonLastMessagesCarryNoCacheControl() throws {
        let json = try buildBody(
            messages: [systemMessage("S"),
                       userMessage("hi"),
                       LLM.Message(responseID: nil, role: .assistant, content: "hello!"),
                       userMessage("what's 2+2?")],
            tools: [tool(named: "calc")])
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        XCTAssertGreaterThan(messages.count, 1)
        for msg in messages.dropLast() {
            XCTAssertNil(msg["cache_control"],
                         "Non-last message must not carry cache_control")
            if let content = msg["content"] as? [[String: Any]] {
                for block in content {
                    XCTAssertNil(block["cache_control"],
                                 "Non-last message content block must not carry cache_control")
                }
            }
        }
    }

    /// The rolling correctness invariant: a message that was the marked
    /// last message on one turn must carry NO cache_control once a later
    /// turn is appended and it is no longer last. Because cache_control is
    /// excluded from the cache key, its content bytes are then identical to
    /// what was cached, so the prior turn's prefix still produces a read.
    func testPreviouslyMarkedMessageRevertsWhenNoLongerLast() throws {
        let later = try buildBody(
            messages: [systemMessage("S"),
                       userMessage("first"),
                       userMessage("second"),
                       LLM.Message(responseID: nil, role: .assistant, content: "answer"),
                       userMessage("third")],
            tools: [])
        let messages = (later["messages"] as? [[String: Any]]) ?? []
        for msg in messages {
            let isSecond: Bool
            if let s = msg["content"] as? String {
                isSecond = (s == "second")
            } else if let arr = msg["content"] as? [[String: Any]] {
                isSecond = arr.contains { ($0["text"] as? String) == "second" }
            } else {
                isSecond = false
            }
            guard isSecond else { continue }
            XCTAssertNil(msg["cache_control"],
                         "A no-longer-last message must not carry cache_control")
            if let arr = msg["content"] as? [[String: Any]] {
                for block in arr {
                    XCTAssertNil(block["cache_control"],
                                 "A no-longer-last message's blocks must not carry cache_control")
                }
            }
        }
    }
}
