//
//  LLMModernProtocol.swift
//  iTerm2
//
//  Created by George Nachman on 5/31/25.
//
// This file relates to OpenAI's second API, also called "completions".

struct CompletionsMessage: Codable, Equatable {
    var role: LLM.Role? = .user
    var content: String?

    // For function calling
    var functionName: String?  // in the response only
    var function_call: LLM.FunctionCall?

    init(role: LLM.Role? = .user,
         content: String? = nil,
         name: String? = nil,
         function_call: LLM.FunctionCall? = nil) {
        self.role = role
        self.content = content
        self.functionName = name
        self.function_call = function_call
    }

    enum CodingKeys: String, CodingKey {
        case role
        case functionName = "name"
        case content
        case function_call
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(role, forKey: .role)

        if let functionName {
            try container.encode(functionName, forKey: .functionName)
        }

        try container.encode(content, forKey: .content)

        if let function_call {
            try container.encode(function_call, forKey: .function_call)
        }
    }

    var approximateTokenCount: Int { OpenAIMetadata.instance.tokens(in: (content ?? "")) + 1 }

    var trimmedString: String? {
        guard let content else {
            return nil
        }
        return String(content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
    }

    init?(_ llmMessage: LLM.Message) {
        role = llmMessage.role
        switch llmMessage.body {
        case .text(let text):
            content = text
        case .attachment(let attachment):
            switch attachment.type {
            case .code(let string):
                content = string
            case .statusUpdate(let statusUpdate):
                content = statusUpdate.displayString
            case .file(let file):
                content = file.content.lossyString
            case .fileID(_, let name):
                content = "A file named \(name)"  // If I add file support here then this must be fixed.
            }
        case .functionCall(let call, _):
            functionName = call.name
            function_call = call
            content = nil
        case .functionOutput(name: let name, output: let output, id: _):
            functionName = name
            content = output
        case .uninitialized:
            return nil
        case .multipart:
            // This is pretty crappy but I don't think it'll happen unless you continue an
            // existing conversation in an older API.
            content = llmMessage.body.content
        }
    }
    var llmMessage: LLM.Message {
        LLM.Message(role: role,
                    content: content,
                    name: functionName,
                    function_call: function_call)
    }
}

struct LLMModernResponseParser: LLMResponseParser {
    struct ModernResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var id: String
        var object: String
        var created: Int
        var model: String?
        var choices: [Choice]
        var usage: Usage?  // see issue 12134

        struct Choice: Codable {
            var index: Int
            var message: CompletionsMessage
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }

        var choiceMessages: [LLM.Message] {
            return choices.map {
                LLM.Message(role: $0.message.role,
                            content: $0.message.content,
                            name: $0.message.functionName,
                            function_call: $0.message.function_call)
            }
        }
    }

    var parsedResponse: ModernResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct LLMModernStreamingResponseParser: LLMStreamingResponseParser {
    struct ModernStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var newlyCreatedResponseID: String? { nil }
        var ignore: Bool { false }
        var isStreamingResponse: Bool { true }

        let id: String?
        let object: String?
        let created: TimeInterval?
        let model: String?
        let choices: [UpdateChoice]

        struct UpdateChoice: Codable {
            // The delta holds the incremental text update.
            let delta: CompletionsMessage
            let index: Int
            // For update chunks, finish_reason is nil.
            let finish_reason: String?
        }

        var choiceMessages: [LLM.Message] {
            return choices.compactMap {
                if $0.finish_reason == "function_call" &&
                    $0.delta.role == nil &&
                    $0.delta.content == nil &&
                    $0.delta.functionName == nil &&
                    $0.delta.function_call == nil {
                    // Sent at the end of a function call
                    return nil
                }
                return LLM.Message(role: .assistant,
                                   content: $0.delta.content ?? "",
                                   function_call: $0.delta.function_call)
            }
        }
    }
    var parsedResponse: ModernStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernStreamingResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}
