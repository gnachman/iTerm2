//
//  O1OpenAI.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

// There were minor changes to the API for O1 and it doesn't support functions.
struct O1BodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var frozenHistoryElements: Data? = nil  // blob-native replay; see LLMRequestBuilder

    private struct Body: Codable {
        var model: String?
        var messages = [CompletionsMessage]()
        var max_completion_tokens: Int
    }

    func body() throws -> Data {
        // O1 doesn't support "system", so replace it with user.
        let modifiedMessages = messages.map { message in
            if message.role != .system {
                return message
            }
            var temp = message
            temp.role = .user
            return temp
        }
        let body = Body(model: provider.model.name,
                        messages: modifiedMessages.compactMap { CompletionsMessage($0) },
                        max_completion_tokens: provider.maxTokens(functions: [], messages: messages))
        if body.max_completion_tokens < 2 {
            throw AIError.requestTooLarge
        }
        DLog("REQUEST:\n\(body)")
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        // o1 converts each system message to a user message but keeps its position,
        // so the frozen history still splices after that many leading elements.
        return try ChatBlobAssembler.spliceFrozenHistory(
            frozenHistoryElements, into: bodyData, arrayKey: "messages",
            afterCount: messages.filter { $0.role == .system }.count)

    }
}

