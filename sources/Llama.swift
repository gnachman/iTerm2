//
//  Llama.swift
//  iTerm2
//
//  Created by George Nachman on 6/11/25.
//

struct LlamaResponseParser: LLMResponseParser {
    var parsedResponse: LlamaResponse<LlamaNonStreamingValue>?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LlamaResponse<LlamaNonStreamingValue>.self,
                                          from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct LlamaStreamingResponseParser: LLMStreamingResponseParser {
    var parsedResponse: LlamaResponse<LlamaStreamingValue>?

    mutating func parse(data: Data) throws -> (any LLM.AnyStreamingResponse)? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LlamaResponse<LlamaStreamingValue>.self,
                                          from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitNDJSON(from: rawInput)
    }
}

protocol LlamaStreaming {
    static var streaming: Bool { get }
}

struct LlamaStreamingValue: LlamaStreaming {
    static var streaming: Bool { true }
}

struct LlamaNonStreamingValue: LlamaStreaming {
    static var streaming: Bool { false }
}

struct LlamaResponse<Streaming: LlamaStreaming>: Codable {
    var model: String  // llama3.2
    var message: Message
    struct Message: Codable {
        var role: String  // assistant
        var content: String
        var tool_calls: [ToolCall]?

        struct ToolCall: Codable {
            var function: Function

            struct Function: Codable {
                var name: String  // get_current_weather
                var arguments: [String: String]
            }
        }
    }

    var done: Bool  // false while streaming
}

extension LlamaResponse: LLM.AnyResponse {
    var choiceMessages: [LLM.Message] {
        if done && Streaming.streaming {
            return []
        }
        let body = if let toolCall = message.tool_calls?.first {
            LLM.Message.Body.functionCall(
                .init(
                    name: toolCall.function.name,
                    arguments: try? JSONEncoder().encode(
                        toolCall.function.arguments).lossyString),
                id: nil)
        } else {
            LLM.Message.Body.text(message.content)
        }
        return [LLM.Message(responseID: nil,
                            role: .assistant,
                            body: body)]
    }
    var isStreamingResponse: Bool {
        Streaming.streaming
    }
}

extension LlamaResponse: LLM.AnyStreamingResponse {
    var ignore: Bool {
        message.content == "" && message.tool_calls == nil
    }
    
    var newlyCreatedResponseID: String? {
        nil
    }
}

func SplitNDJSON(from rawInput: String) -> (json: String?, remainder: String) {
    let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
    guard let newlineRange = input.range(of: "\n") else {
        return (nil, String(input))
    }

    // Extract the first line (up to, but not including, the newline)
    let firstLine = input[..<newlineRange.lowerBound]
    // Everything after the newline is the remainder.
    let remainder = input[newlineRange.upperBound...]

    return (String(firstLine), String(remainder))
}

// MARK: - Request

struct LlamaBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool

    private struct Body: Codable {
        var model: String?
        var messages = [CompletionsMessage]()
        var max_tokens: Int
        var tools: [LlamaFunctionDeclaration]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
        var stream: Bool
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let maybeDecls = functions.isEmpty ? nil : functions.map { LlamaFunctionDeclaration($0.decl) }

        // See the note about streaming function calling in Llama in AIMetadata.swift
        let body = Body(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            messages: messages.compactMap { CompletionsMessage($0) },
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            tools: stream ? nil : maybeDecls,
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

struct LlamaFunctionDeclaration: Codable {
    var type = "function"
    var function: ChatGPTFunctionDeclaration

    init(_ decl: ChatGPTFunctionDeclaration) {
        self.function = decl
    }
}
