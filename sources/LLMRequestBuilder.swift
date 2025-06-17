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

    var headers: [String: String] {
        var result = LLMAuthorizationProvider(provider: provider, apiKey: apiKey).headers
        result["Content-Type"] = "application/json"
        return result
    }

    var method: String { "POST" }

    func body() throws -> Data {
        switch provider.model.api {
        case .anthropic:
            try AnthropicRequestBuilder(messages: messages,
                                        provider: provider,
                                        functions: functions,
                                        stream: stream).body()
        case .completions:
            try LegacyBodyRequestBuilder(messages: messages,
                                         provider: provider).body()
        case .chatCompletions:
            try ModernBodyRequestBuilder(messages: messages,
                                         provider: provider,
                                         functions: functions,
                                         stream: stream).body()
        case .responses:
            try ResponsesBodyRequestBuilder(messages: messages,
                                            provider: provider,
                                            functions: functions,
                                            stream: stream,
                                            hostedTools: hostedTools,
                                            previousResponseID: previousResponseID).body()
        case .earlyO1:
            try O1BodyRequestBuilder(messages: messages,
                                     provider: provider).body()

        case .gemini:
            try GeminiRequestBuilder(messages: messages,
                                     functions: functions,
                                     hostedTools: hostedTools).body()

        case .llama:
            try LlamaBodyRequestBuilder(messages: messages,
                                        provider: provider,
                                        functions: functions,
                                        stream: stream).body()
        case .deepSeek:
            try DeepSeekRequestBuilder(messages: messages,
                                       provider: provider,
                                       functions: functions,
                                       stream: stream).body()
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

