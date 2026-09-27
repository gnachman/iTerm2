//
//  LLMRequestBuilderVolatileContextTests.swift
//  iTerm2 ModernTests
//
//  trailingVolatileText carries per-turn context the model MUST see: the
//  orchestration <workgroups> snapshot and the session-bound auto-provided
//  <terminal-state>/<visible-screen> block (the latter gated on a user
//  permission). LLMRequestBuilder dispatches to a per-vendor body builder, and
//  every vendor must fold that context into the request it sends. Only the
//  placement differs: Anthropic appends it after the prompt-cache breakpoint;
//  the others (which have no cache-prefix concern) just include it.
//
//  Regression these guard: routing the context exclusively through
//  trailingVolatileText and consuming it only in the Anthropic path silently
//  dropped it for OpenAI (chat + responses) / Gemini / DeepSeek / Llama / legacy
//  completions, so a permission-gated feature (send terminal state / screen
//  automatically) quietly stopped working off-Anthropic. One assertion per
//  vendor/api so a future single-provider change can't reintroduce the gap.
//
//  Each test overrides a real catalog model's `api` and asserts the marker
//  reaches the serialized body. body() serialization depends on the api, name,
//  and token budget, not on the model's URL, so overriding the api exercises
//  each dispatch branch deterministically without needing a catalog entry for
//  every vendor.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class LLMRequestBuilderVolatileContextTests: XCTestCase {

    private let marker = "VOLATILE_MARKER_XYZZY"

    private func baseModel() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first else {
            throw XCTSkip("empty AIMetadata catalog")
        }
        return m
    }

    private func bodyString(api: iTermAIAPI) throws -> String {
        var model = try baseModel()
        model.api = api
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model),
            apiKey: "test-key",
            messages: [LLM.Message(role: .system, content: "S"),
                       LLM.Message(role: .user, content: "hello")],
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil,
            reasoningEffort: nil,
            serviceTier: nil,
            trailingVolatileText: marker)
        return String(decoding: try builder.body(), as: UTF8.self)
    }

    private func assertIncludesVolatile(_ api: iTermAIAPI) throws {
        let body = try bodyString(api: api)
        XCTAssertTrue(body.contains(marker),
                      "volatile per-turn context was dropped for api \(api.rawValue); the model would not see the <workgroups> snapshot or the auto-provided terminal state / screen")
    }

    // Control: Anthropic already includes it (as a trailing message after the
    // cache breakpoint). Guards against the opposite regression.
    func test_anthropic_includesVolatileContext() throws {
        try assertIncludesVolatile(.anthropic)
    }

    func test_chatCompletions_includesVolatileContext() throws {
        try assertIncludesVolatile(.chatCompletions)
    }

    func test_responses_includesVolatileContext() throws {
        try assertIncludesVolatile(.responses)
    }

    func test_gemini_includesVolatileContext() throws {
        try assertIncludesVolatile(.gemini)
    }

    func test_deepSeek_includesVolatileContext() throws {
        try assertIncludesVolatile(.deepSeek)
    }

    func test_llama_includesVolatileContext() throws {
        try assertIncludesVolatile(.llama)
    }

    func test_legacyCompletions_includesVolatileContext() throws {
        try assertIncludesVolatile(.completions)
    }

    // The Responses API "send only the newest message" optimization (used when
    // previousResponseID lets the server hold the history) must keep the newest
    // REAL user turn, not the trailing volatile-context message that is folded
    // in AFTER it. Regression this guards: suffix(1) grabbed the volatile
    // <workgroups> block and dropped the user's actual instruction, so every
    // turn after the first reached the model as a bare context snapshot with no
    // request, and the model replied with things like "Ready when you are."
    func test_responses_withPreviousResponseID_keepsNewestUserTurnAndVolatile() throws {
        var model = try baseModel()
        model.api = .responses
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model),
            apiKey: "test-key",
            messages: [LLM.Message(role: .system, content: "S"),
                       LLM.Message(role: .user, content: "hello"),
                       LLM.Message(role: .assistant, content: "hi"),
                       LLM.Message(role: .user, content: "REAL_INSTRUCTION_ABC")],
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: "resp_prev",
            shouldThink: nil,
            reasoningEffort: nil,
            serviceTier: nil,
            trailingVolatileText: marker)
        let body = String(decoding: try builder.body(), as: UTF8.self)
        XCTAssertTrue(body.contains("REAL_INSTRUCTION_ABC"),
                      "the newest user turn was dropped by suffix(1); the model would receive only the volatile context and no actual request")
        XCTAssertTrue(body.contains(marker),
                      "the volatile per-turn context must still be included every turn")
    }
}
