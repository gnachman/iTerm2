//
//  DeepSeek.swift
//  iTerm2
//
//  Created by George Nachman on 6/12/25.
//

struct DeepSeekRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool

    private struct Body: Codable {
        var model: String?
        var messages = [Message]()
        var max_tokens: Int
        var temperature: Int? = 0
        var tools: [Tool]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
        var stream: Bool
    }

    struct Message: Codable {
        var role: Role? = .user
        var tool_call_id: String?
        var content: String?
        var tool_calls: [ToolCall]?

        struct ToolCall: Codable {
            var id: String?
            var type = "function"
            var function: LLM.FunctionCall
        }
        enum Role: String, Codable {
            case user
            case assistant
            case system
            case tool
        }
        init?(_ message: LLM.Message) {
            role = switch message.role {
            case .user: .user
            case .assistant: .assistant
            case .system: .system
            case .function: .tool
            case .none: nil
            }
            switch message.body {
            case .uninitialized:
                break
            case .text(let text):
                content = text
            case .functionCall(let call, id: let id):
                tool_calls = [ToolCall(id: id?.callID, function: call)]
            case .functionOutput(name: _, output: let output, id: let id):
                tool_call_id = id?.callID
                content = output
            case .attachment:
                content = ""
            case .multipart(let parts):
                content = parts.compactMap { part in
                    switch part {
                    case .uninitialized:
                        return nil
                    case .text(let text):
                        return text
                    case .functionCall, .functionOutput:
                        return nil
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let text):
                            return text
                        case .statusUpdate:
                            return nil
                        case .file(let file):
                            var value = "<iterm2:attachment file=\"\(file.name)\" type=\"\(file.mimeType)\">\n"
                            value += file.content.lossyString
                            value += "\n</iterm2:attachment>"
                            return value
                        case .fileID(id: _, name: let name):
                            return "A file named \(name) (content unavailable)"
                        }
                    case .multipart(_):
                        return nil
                    }
                }.joined(separator: "\n")
            }
        }
    }

    struct Tool: Codable {
        var type = "function"
        var function: ChatGPTFunctionDeclaration
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let maybeDecls = functions.isEmpty ? nil : functions.map {
            Tool(function: $0.decl)
        }
        let body = Body(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            messages: messages.compactMap { Message($0) },
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            tools: maybeDecls,
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

struct DeepSeekResponseParser: LLMResponseParser {
    mutating func parse(data: Data) throws -> (any LLM.AnyResponse)? {
        var lastException: Error?
        for parser: LLMResponseParser in [LLMModernResponseParser(), LlamaResponseParser()] {
            do {
                var temp = parser
                return try temp.parse(data: data)
            } catch {
                lastException = error
            }
        }
        if let lastException {
            throw lastException
        } else {
            return nil
        }
    }
    
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct DeepSeekStreamingResponseParser: LLMStreamingResponseParser {
    struct DeepSeekStreamingResponse: Codable, LLM.AnyStreamingResponse {
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
            let delta: Delta
            let index: Int
            // For update chunks, finish_reason is nil.
            let finish_reason: String?

            struct Delta: Codable {
                var role: LLM.Role?
                var content: String?
                var tool_calls: [ToolCall]?

                struct ToolCall: Codable {
                    var index: Int
                    var id: String?
                    var type: String?  // "function"
                    var function: LLM.FunctionCall?
                }
            }
        }

        var choiceMessages: [LLM.Message] {
            return choices.compactMap { choice -> LLM.Message? in
                if choice.finish_reason == "tool_calls" {
                    // Sent at the end of a function call
                    return nil
                }

                if let call = choice.delta.tool_calls?.first {
                    let function = call.function
                    let functionCall = LLM.FunctionCall(
                        name: function?.name,
                        arguments: function?.arguments,
                        id: call.id)
                    return LLM.Message(
                        role: .assistant,
                        content: choice.delta.content,
                        functionCallID: call.id.map { .init(callID: $0, itemID: "") },
                        function_call: functionCall)
                } else {
                    return LLM.Message(
                        role: .assistant,
                        content: choice.delta.content)
                }
            }
        }
    }
    var parsedResponse: DeepSeekStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(DeepSeekStreamingResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}
