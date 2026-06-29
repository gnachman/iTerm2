//
//  AIChatToolCallRepairTests.swift
//  iTerm2 ModernTests
//
//  Offline tests for tool-call repair when an AI chat prompt is rebuilt from
//  the persisted transcript. Two distinct vendor families have to be satisfied
//  on every reload:
//
//    - Id-based (Anthropic, OpenAI Responses): every tool_result must have a
//      matching tool_use of the same id earlier in the conversation.
//      Auto-approved commands historically dropped the request from the
//      transcript while keeping the response, leaving an orphan tool_result
//      that 400s the next turn.
//    - Position-based (Gemini, legacy OpenAI function_call): the deserializer
//      sets both the inner FunctionCall.id and the wrapper FunctionCallID to
//      nil (Gemini.swift parser), and the vendor pairs the functionResponse
//      with the functionCall by adjacency. A nil-id result without an adjacent
//      preceding tool_use is rejected.
//
//  The decisive tests here exercise the actual wire format, not just the
//  in-memory shape: testOrphanRepair_serializesAsAnthropicToolUse builds the
//  Anthropic body and asserts a tool_use block (keyed off the *inner*
//  FunctionCall.id, not the wrapper) is paired with the result;
//  testOrphanRepair_serializesAsGeminiFunctionCall builds the Gemini body and
//  asserts the synthesized functionCall Part lands immediately before the
//  functionResponse Part. Structural tests alone passed cleanly while the
//  Anthropic inner-id bug shipped, so the wire-level checks are not optional.
//

import XCTest
@testable import iTerm2SharedARC

final class AIChatToolCallRepairTests: XCTestCase {

    // MARK: - Fixtures

    private func fcid(_ s: String) -> LLM.Message.FunctionCallID {
        LLM.Message.FunctionCallID(callID: s, itemID: s)
    }

    /// A tool_use message. Pass `nil` for `id` to model what the Gemini and
    /// legacy-OpenAI deserializers produce (both inner and wrapper id nil).
    private func toolUse(_ id: String?,
                         name: String = "execute_command",
                         args: String = "{}") -> LLM.Message {
        LLM.Message(role: .assistant,
                    body: .functionCall(LLM.FunctionCall(name: name,
                                                         arguments: args,
                                                         id: id,
                                                         thoughtSignature: nil),
                                        id: id.map { fcid($0) }))
    }

    /// A tool_result message. Pass `nil` for `id` for the position-paired
    /// (Gemini / legacy OpenAI) shape; this is exactly what the deserializer
    /// puts into a persisted `.remoteCommandResponse` for those vendors.
    private func toolResult(_ id: String?,
                            name: String = "execute_command",
                            output: String = "output") -> LLM.Message {
        LLM.Message(role: .user,
                    body: .functionOutput(name: name,
                                          output: output,
                                          id: id.map { fcid($0) }))
    }

    private func text(_ s: String, role: LLM.Role) -> LLM.Message {
        LLM.Message(role: role, body: .text(s))
    }

    // MARK: - Inspection helpers

    /// The id the Anthropic serializer would actually emit for a tool_use:
    /// the inner FunctionCall.id, not the wrapper.
    private func emittedToolUseID(_ m: LLM.Message) -> String? {
        if case .functionCall(let call, _) = m.body { return call.id }
        return nil
    }

    private func isToolUse(_ m: LLM.Message) -> Bool {
        if case .functionCall = m.body { return true }
        return false
    }

    private func isToolResult(_ m: LLM.Message, id: String) -> Bool {
        if case .functionOutput(_, _, let fid) = m.body { return fid?.callID == id }
        return false
    }

    /// Walk the messages and assert every tool_result is paired according to
    /// the rule the vendor actually uses:
    ///   - id-set: a prior tool_use with the same id exists.
    ///   - id-nil: the immediately preceding message is a tool_use.
    private func assertEveryToolResultIsPaired(_ messages: [LLM.Message],
                                               file: StaticString = #file,
                                               line: UInt = #line) {
        var seenCallIDs = Set<String>()
        for (i, m) in messages.enumerated() {
            if case .functionCall(let call, let wrapper) = m.body {
                if let inner = call.id { seenCallIDs.insert(inner) }
                else if let w = wrapper?.callID { seenCallIDs.insert(w) }
            }
            if case .functionOutput(_, _, let id) = m.body {
                if let cid = id?.callID {
                    XCTAssertTrue(seenCallIDs.contains(cid),
                                  "tool_result \(cid) has no preceding tool_use",
                                  file: file, line: line)
                } else {
                    // Position-based: the preceding emitted message must itself
                    // be a tool_use.
                    XCTAssertGreaterThan(i, 0,
                                         "a nil-id tool_result cannot be the first message",
                                         file: file, line: line)
                    XCTAssertTrue(isToolUse(messages[i - 1]),
                                  "nil-id tool_result at index \(i) has no adjacent preceding tool_use",
                                  file: file, line: line)
                }
            }
        }
    }

    private func anthropicModel() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == "claude-haiku-4-5" }) else {
            throw XCTSkip("claude-haiku-4-5 not in AIMetadata; test skipped")
        }
        return m
    }

    private func geminiModel() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == "gemini-2.5-flash" }) else {
            throw XCTSkip("gemini-2.5-flash not in AIMetadata; test skipped")
        }
        return m
    }

    // MARK: - Id-based pairing (Anthropic / OpenAI Responses)

    /// The reported bug: an auto-approved command left a tool_result with no
    /// matching tool_use. Repair must synthesize a tool_use immediately before
    /// the orphan, and its inner FunctionCall.id must be set (see file header).
    func testIdBasedOrphan_synthesizesPrecedingToolUse() {
        let input = [
            text("Hi", role: .user),
            text("Let me check.", role: .assistant),
            toolResult("toolu_orphan"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)

        guard let resultIndex = output.firstIndex(where: { isToolResult($0, id: "toolu_orphan") }) else {
            XCTFail("orphan tool_result vanished")
            return
        }
        XCTAssertGreaterThan(resultIndex, 0, "result cannot be first; a tool_use must precede it")
        XCTAssertEqual(emittedToolUseID(output[resultIndex - 1]), "toolu_orphan",
                       "a matching tool_use (with inner id set) must precede the orphan result")
    }

    /// The synthesized tool_use uses the result's function name, empty (valid)
    /// arguments, and the matching inner id.
    func testIdBasedOrphan_synthesizedCallShape() {
        let input = [toolResult("toolu_x", name: "get_current_directory")]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        let synth = output.first { emittedToolUseID($0) == "toolu_x" }
        guard case .functionCall(let call, let wrapper)? = synth?.body else {
            XCTFail("expected a synthesized functionCall, got \(String(describing: synth?.body))")
            return
        }
        XCTAssertEqual(call.name, "get_current_directory")
        XCTAssertEqual(call.arguments, "{}")
        XCTAssertEqual(call.id, "toolu_x", "inner FunctionCall.id must be set")
        XCTAssertEqual(wrapper?.callID, "toolu_x", "wrapper id must match")
    }

    /// A well-formed id-based request/response pair must be left exactly as-is.
    func testIdBasedPair_isUnchanged() {
        let input = [
            toolUse("toolu_ok", args: "{\"command\":\"ls\"}"),
            toolResult("toolu_ok"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        XCTAssertEqual(output.count, 2, "no message should be added to a well-formed pair")
        XCTAssertEqual(emittedToolUseID(output[0]), "toolu_ok")
        XCTAssertTrue(isToolResult(output[1], id: "toolu_ok"))
    }

    /// Two id-based orphans in a row must each get their own synthesized
    /// tool_use.
    func testIdBasedMultipleOrphans_eachRepairedIndependently() {
        let input = [
            toolResult("toolu_a"),
            toolResult("toolu_b"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        assertEveryToolResultIsPaired(output)
        XCTAssertTrue(output.contains { emittedToolUseID($0) == "toolu_a" })
        XCTAssertTrue(output.contains { emittedToolUseID($0) == "toolu_b" })
    }

    /// End-to-end shape of the reported failure (messages.4 in the bug report):
    /// a first well-formed call, then assistant text, then an orphan result.
    func testIdBasedReportedScenario_isMadeValid() {
        let input = [
            text("Although my zshrc sources .p10k.zsh...", role: .user),
            toolUse("toolu_first", args: "{\"command\":\"echo a\"}"),
            toolResult("toolu_first"),
            text("The output got cut off. Let me confirm:", role: .assistant),
            toolResult("toolu_second"),  // orphan, the auto-approved command
            text("There's the problem.", role: .assistant),
            text("Can you load it just in this session?", role: .user),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        assertEveryToolResultIsPaired(output)
        XCTAssertTrue(output.contains { emittedToolUseID($0) == "toolu_second" },
                      "the orphaned second call must gain a synthesized tool_use")
        XCTAssertEqual(output.filter { emittedToolUseID($0) == "toolu_first" }.count, 1)
    }

    // MARK: - Position-based pairing (Gemini / legacy OpenAI)

    /// A nil-id Gemini/legacy-OpenAI paired call+response must pass through
    /// untouched: both vendors pair by adjacency, and the deserializer
    /// already gave us the adjacent pair.
    func testNilIdPair_isUnchanged() {
        let input = [
            toolUse(nil, name: "execute_command", args: "{\"command\":\"ls\"}"),
            toolResult(nil, name: "execute_command", output: "file1\nfile2"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        XCTAssertEqual(output.count, 2, "no message should be added to a well-formed nil-id pair")
        XCTAssertTrue(isToolUse(output[0]))
        guard case .functionOutput = output[1].body else {
            XCTFail("expected the second message to remain a functionOutput")
            return
        }
        assertEveryToolResultIsPaired(output)
    }

    /// An auto-approved nil-id result (Gemini-style: no preceding request
    /// stored) used to be silently dropped, which made the rebuilt prompt
    /// 400 elsewhere. The repair must instead synthesize a nil-id tool_use
    /// immediately before it so the vendor sees a functionCall → functionResponse
    /// adjacency.
    func testNilIdOrphan_synthesizesAdjacentNilIdToolUse() {
        let input = [
            text("hello", role: .user),
            toolResult(nil, name: "execute_command", output: "the output"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        XCTAssertEqual(output.count, 3,
                       "must keep the user text, synthesize a tool_use, and keep the result")
        XCTAssertEqual(output[0].body.maybeContent, "hello")
        guard case .functionCall(let call, let wrapper) = output[1].body else {
            XCTFail("expected a synthesized nil-id functionCall at index 1, got \(output[1].body)")
            return
        }
        XCTAssertNil(call.id, "Gemini-shaped synth must keep inner id nil")
        XCTAssertNil(wrapper, "Gemini-shaped synth must keep wrapper id nil")
        XCTAssertEqual(call.name, "execute_command")
        guard case .functionOutput = output[2].body else {
            XCTFail("expected the nil-id result preserved at index 2"); return
        }
        assertEveryToolResultIsPaired(output)
    }

    /// Two nil-id orphans in a row must each get their own adjacent
    /// synthesized tool_use.
    func testNilIdMultipleOrphans_eachRepairedIndependently() {
        let input = [
            toolResult(nil, name: "execute_command"),
            toolResult(nil, name: "execute_command"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolResults(input)
        // Expected: synth, result, synth, result.
        XCTAssertEqual(output.count, 4)
        assertEveryToolResultIsPaired(output)
    }

    // MARK: - Orphan tool_call (call with no result) — GitLab #12883

    /// An id-based tool_use whose result never arrived, followed by later
    /// messages, must gain a synthesized tool_result IMMEDIATELY after the
    /// call. Leaving the call unanswered (or deferring the result past the
    /// trailing messages) 400s DeepSeek/OpenAI chat-completions with
    /// "insufficient tool messages following tool_calls message".
    func testIdBasedOrphanCall_synthesizesAdjacentResult() {
        let input = [
            text("run a command", role: .user),
            toolUse("toolu_orphan", args: "{\"command\":\"ls\"}"),
            text("actually never mind, let's chat", role: .user),
            text("Sure!", role: .assistant),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolCalls(input)
        guard let callIndex = output.firstIndex(where: { emittedToolUseID($0) == "toolu_orphan" }) else {
            XCTFail("tool_use vanished")
            return
        }
        XCTAssertLessThan(callIndex + 1, output.count, "orphan call has nothing after it")
        XCTAssertTrue(isToolResult(output[callIndex + 1], id: "toolu_orphan"),
                      "the orphan tool_use's result must immediately follow it")
    }

    /// A well-formed id-based pair must be left untouched by the call repair.
    func testIdBasedPair_callRepairLeavesUnchanged() {
        let input = [
            toolUse("toolu_ok", args: "{\"command\":\"ls\"}"),
            toolResult("toolu_ok"),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolCalls(input)
        XCTAssertEqual(output.count, 2, "no message should be added to a well-formed pair")
    }

    /// The synthesized result must carry role .function so DeepSeek serializes
    /// it as a "tool" message; a .user role would re-trigger the 400.
    func testIdBasedOrphanCall_synthesizedResultRoleIsFunction() {
        let input = [toolUse("toolu_x", name: "get_current_directory")]
        let output = AIChatToolCallRepair.repairingOrphanedToolCalls(input)
        guard let resultIndex = output.firstIndex(where: { isToolResult($0, id: "toolu_x") }) else {
            XCTFail("expected a synthesized tool_result")
            return
        }
        XCTAssertEqual(output[resultIndex].role, .function,
                       "synthesized tool_result must be role .function")
        if case .functionOutput(let name, _, _) = output[resultIndex].body {
            XCTAssertEqual(name, "get_current_directory")
        } else {
            XCTFail("expected a functionOutput body")
        }
    }

    /// A nil-id (Gemini / legacy OpenAI) call with no adjacent result gets a
    /// nil-id result inserted right after it, preserving adjacency pairing.
    func testNilIdOrphanCall_synthesizesAdjacentNilIdResult() {
        let input = [
            toolUse(nil, name: "execute_command", args: "{\"command\":\"ls\"}"),
            text("ok thanks", role: .user),
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolCalls(input)
        guard case .functionCall = output[0].body else {
            XCTFail("expected the call preserved at index 0"); return
        }
        guard case .functionOutput(_, _, let id) = output[1].body else {
            XCTFail("expected a synthesized functionOutput at index 1, got \(output[1].body)"); return
        }
        XCTAssertNil(id, "Gemini-shaped synth result must keep its id nil")
    }

    /// Two orphan calls interleaved with text each get their own adjacent
    /// result, and repairingOrphanedToolPairs heals both directions at once.
    func testRepairPairs_mixedOrphans_allHealed() {
        let input = [
            toolUse("toolu_call_only"),          // orphan call
            text("hmm", role: .assistant),
            toolResult("toolu_result_only"),     // orphan result
        ]
        let output = AIChatToolCallRepair.repairingOrphanedToolPairs(input)
        assertEveryToolResultIsPaired(output)
        // The orphan call gained a following result...
        guard let callIdx = output.firstIndex(where: { emittedToolUseID($0) == "toolu_call_only" }) else {
            XCTFail("orphan call vanished"); return
        }
        XCTAssertTrue(isToolResult(output[callIdx + 1], id: "toolu_call_only"),
                      "orphan call must be answered immediately after it")
        // ...and the orphan result gained a preceding call.
        XCTAssertTrue(output.contains { emittedToolUseID($0) == "toolu_result_only" },
                      "orphan result must gain a synthesized tool_use")
    }

    // MARK: - Anthropic wire format (the decisive id-based test)

    /// Build the real Anthropic request body from a repaired orphan and assert
    /// it actually contains a tool_use block whose id matches the tool_result's
    /// tool_use_id, with the tool_use appearing before the result. Catches a
    /// nil inner FunctionCall.id, which passes every structural test above but
    /// produces a body with a tool_result and no paired tool_use.
    func testOrphanRepair_serializesAsAnthropicToolUse() throws {
        let model = try anthropicModel()
        let repaired = AIChatToolCallRepair.repairingOrphanedToolResults([
            text("Let me check.", role: .assistant),
            toolResult("toolu_orphan", output: "the command output"),
        ])
        let bodyData = try AnthropicRequestBuilder(
            messages: repaired,
            provider: LLMProvider(model: model),
            functions: [],
            stream: false).body()

        guard let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            XCTFail("Anthropic body is not the expected JSON shape")
            return
        }

        // Walk every content block in order, collecting where each tool_use id
        // and tool_result tool_use_id appears.
        var toolUseIndexByID = [String: Int]()
        var toolResultIndexByID = [String: Int]()
        var blockIndex = 0
        for message in messages {
            guard let blocks = message["content"] as? [[String: Any]] else { continue }
            for block in blocks {
                defer { blockIndex += 1 }
                switch block["type"] as? String {
                case "tool_use":
                    if let id = block["id"] as? String { toolUseIndexByID[id] = blockIndex }
                case "tool_result":
                    if let id = block["tool_use_id"] as? String { toolResultIndexByID[id] = blockIndex }
                default:
                    break
                }
            }
        }

        let resultIndex = try XCTUnwrap(toolResultIndexByID["toolu_orphan"],
                                        "the tool_result must still serialize")
        let useIndex = try XCTUnwrap(toolUseIndexByID["toolu_orphan"],
                                     "a tool_use block with the matching id must be emitted; a nil inner FunctionCall.id would skip this and reproduce the 400")
        XCTAssertLessThan(useIndex, resultIndex,
                          "the tool_use must come before its tool_result")
    }

    // MARK: - Gemini wire format (the decisive position-based test)

    /// Build the real Gemini request body from a repaired nil-id orphan and
    /// assert it contains a functionCall Part immediately preceding the
    /// functionResponse Part. Catches a repair that drops the nil-id result
    /// (the previous behavior) or that emits a functionCall but isn't adjacent
    /// to the response.
    func testOrphanRepair_serializesAsGeminiFunctionCall() throws {
        _ = try geminiModel()  // skip if Gemini support is unbundled
        let repaired = AIChatToolCallRepair.repairingOrphanedToolResults([
            text("Run it", role: .user),
            toolResult(nil, name: "execute_command", output: "the command output"),
        ])
        let bodyData = try GeminiRequestBuilder(
            messages: repaired,
            functions: [],
            hostedTools: HostedTools()).body()

        guard let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let contents = json["contents"] as? [[String: Any]] else {
            XCTFail("Gemini body is not the expected JSON shape")
            return
        }

        // Flatten parts in order and find the indices of the first functionCall
        // and the first functionResponse. They must be adjacent (functionCall
        // immediately before functionResponse), since Gemini pairs by position.
        struct PartTag { let kind: String; let name: String? }
        var flat = [PartTag]()
        for content in contents {
            guard let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let fc = part["functionCall"] as? [String: Any] {
                    flat.append(PartTag(kind: "functionCall", name: fc["name"] as? String))
                } else if let fr = part["functionResponse"] as? [String: Any] {
                    flat.append(PartTag(kind: "functionResponse", name: fr["name"] as? String))
                } else if part["text"] != nil {
                    flat.append(PartTag(kind: "text", name: nil))
                }
            }
        }
        guard let callIdx = flat.firstIndex(where: { $0.kind == "functionCall" }) else {
            XCTFail("Gemini body has no functionCall Part; the nil-id orphan must produce one. flat=\(flat)")
            return
        }
        guard let respIdx = flat.firstIndex(where: { $0.kind == "functionResponse" }) else {
            XCTFail("Gemini body has no functionResponse Part; the nil-id result must survive. flat=\(flat)")
            return
        }
        XCTAssertEqual(respIdx, callIdx + 1,
                       "Gemini pairs by adjacency: the synthesized functionCall must immediately precede the functionResponse. flat=\(flat)")
        XCTAssertEqual(flat[callIdx].name, "execute_command")
        XCTAssertEqual(flat[respIdx].name, "execute_command")
    }
}
