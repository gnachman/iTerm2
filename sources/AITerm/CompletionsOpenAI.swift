//
//  CompletionsOpenAI.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct ModernBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool

    private struct Tool: Codable {
        var type = "function"
        var function: ChatGPTFunctionDeclaration
    }

    private struct Body: Codable {
        var model: String?
        var messages = [CompletionsMessage]()
        var max_tokens: Int
        var temperature: Int? = 0
        var tools: [Tool]? = nil
        var tool_choice: String? = nil  // "none" and "auto" also allowed
        var stream: Bool
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        //
        // Use tools/tool_choice (modern) instead of functions/function_call
        // (deprecated 2023). OpenAI explicitly errors when both shapes are
        // sent in one request, so we have to pick. Modern servers respond
        // with `tool_calls` (which CompletionsMessage now decodes and
        // re-emits on echo); legacy-only servers would reject this, but
        // every current chat-completions provider supports the modern form.
        let maybeTools = functions.isEmpty ? nil : functions.map { Tool(function: $0.decl) }
        let body = Body(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            messages: messages.compactMap { CompletionsMessage($0) },
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            // Omit temperature for models that reject it (e.g. some reasoning
            // models), matching CompletionsAnthropic. nil drops the key.
            temperature: provider.model.supportsTemperature ? 0 : nil,
            tools: maybeTools,
            tool_choice: functions.isEmpty ? nil : "auto",
            stream: stream)
        DLog("REQUEST:\n\(body)")
        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData

    }
}

