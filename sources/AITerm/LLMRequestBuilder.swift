//
//  LLMRequestBuilder.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LLMRequestBuilder {
    var provider: LLMProvider
    var apiKey: String
    var messages: [LLM.Message]
    var functions = [LLM.AnyFunction]()
    var stream = false
    var hostedTools: HostedTools
    var previousResponseID: String?
    var shouldThink: Bool?
    var reasoningEffort: ResponsesRequestBody.ReasoningOptions.Effort?
    var serviceTier: ResponsesRequestBody.ServiceTier?
    // Volatile per-turn context that the model must see (the orchestration
    // <workgroups> snapshot, the session-bound auto-provided terminal/screen
    // block). Only the PLACEMENT is vendor-specific: Anthropic appends it after
    // the prompt-cache breakpoint (via AnthropicRequestBuilder.trailingVolatileText)
    // so it doesn't invalidate the cached history prefix; every other vendor has
    // no cache-prefix concern and just gets it folded in as a trailing user
    // message (messagesWithVolatile). Dropping it for non-Anthropic vendors is a
    // functional regression, since the terminal-state/screen block is gated on a
    // user permission. See LLMRequestBuilderVolatileContextTests.
    var trailingVolatileText: String?

    // Blob-native replay: the chat's verbatim frozen-history wire messages (the
    // comma-joined inner element bytes of the stored blobs, no surrounding
    // brackets) that the per-vendor builder splices into its message array after
    // the system message(s). nil for the normal path, where `messages` carries the
    // whole conversation. Only the protocols whose builder supports it consume it.
    // Declared last so it is an optional trailing argument on the memberwise init.
    var frozenHistoryElements: Data? = nil

    // The message list with the volatile per-turn context folded in as a
    // trailing user message. Used by every builder EXCEPT Anthropic, which
    // places it itself so it lands after the cache breakpoint.
    private var messagesWithVolatile: [LLM.Message] {
        guard let trailingVolatileText, !trailingVolatileText.isEmpty else {
            return messages
        }
        return messages + [LLM.Message(role: .user, content: trailingVolatileText)]
    }

    var headers: [String: String] {
        var result = LLMAuthorizationProvider(provider: provider, apiKey: apiKey).headers
        result["Content-Type"] = "application/json"
        result = AICustomHeaders.merged(into: result)
        return result
    }

    var method: String { "POST" }

    func body() throws -> Data {
        switch provider.model.api {
        case .anthropic:
            try AnthropicRequestBuilder(messages: messages,
                                        provider: provider,
                                        functions: functions,
                                        stream: stream,
                                        trailingVolatileText: trailingVolatileText,
                                        frozenHistoryElements: frozenHistoryElements).body()
        case .completions:
            try LegacyBodyRequestBuilder(messages: messagesWithVolatile,
                                         provider: provider).body()
        case .chatCompletions:
            try ModernBodyRequestBuilder(messages: messagesWithVolatile,
                                         provider: provider,
                                         functions: functions,
                                         stream: stream,
                                         frozenHistoryElements: frozenHistoryElements).body()
        case .responses:
            // Pass the real messages and the volatile context SEPARATELY (not
            // pre-folded via messagesWithVolatile): the Responses builder applies
            // its previousResponseID suffix(1) truncation to the real messages
            // and appends the volatile context afterward, so the user's newest
            // turn is never the message that gets dropped. See the volatile-context
            // tests (test_responses_withPreviousResponseID_keepsNewestUserTurnAndVolatile).
            try ResponsesBodyRequestBuilder(messages: messages,
                                            provider: provider,
                                            functions: functions,
                                            stream: stream,
                                            hostedTools: hostedTools,
                                            previousResponseID: previousResponseID,
                                            shouldThink: shouldThink,
                                            reasoningEffort: reasoningEffort,
                                            serviceTier: serviceTier,
                                            trailingVolatileText: trailingVolatileText,
                                            frozenHistoryElements: frozenHistoryElements).body()
        case .earlyO1:
            try O1BodyRequestBuilder(messages: messagesWithVolatile,
                                     provider: provider,
                                     frozenHistoryElements: frozenHistoryElements).body()

        case .gemini:
            try GeminiRequestBuilder(messages: messagesWithVolatile,
                                     functions: functions,
                                     hostedTools: hostedTools,
                                     modelName: provider.model.name,
                                     frozenHistoryElements: frozenHistoryElements).body()

        case .llama:
            try LlamaBodyRequestBuilder(messages: messagesWithVolatile,
                                        provider: provider,
                                        functions: functions,
                                        stream: stream,
                                        frozenHistoryElements: frozenHistoryElements).body()
        case .deepSeek:
            try DeepSeekRequestBuilder(messages: messagesWithVolatile,
                                       provider: provider,
                                       functions: functions,
                                       stream: stream,
                                       shouldThink: shouldThink,
                                       frozenHistoryElements: frozenHistoryElements).body()
        case .appleIntelligence:
            // Apple Intelligence runs on-device via FoundationModels and never
            // builds an HTTP request. AITermController intercepts this provider
            // before reaching the request builder, so this is unreachable.
            throw AIError("Apple Intelligence does not use HTTP requests")
        @unknown default:
            it_fatalError()
        }
    }

    func webRequest() throws -> WebRequest {
        WebRequest(headers: headers,
                   method: method,
                   body: .string(try body().lossyString),
                   url: provider.url(apiKey: apiKey,
                                     streaming: stream).absoluteString)
    }
}
