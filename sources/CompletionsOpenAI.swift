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

    private struct Body: Codable {
        var model: String?
        var messages = [CompletionsMessage]()
        var max_tokens: Int
        var temperature: Int? = 0
        var functions: [ChatGPTFunctionDeclaration]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
        var stream: Bool
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let maybeDecls = functions.isEmpty ? nil : functions.map { $0.decl }
        let body = Body(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            messages: messages.compactMap { CompletionsMessage($0) },
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            functions: maybeDecls,
            function_call: functions.isEmpty ? nil : "auto",
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
