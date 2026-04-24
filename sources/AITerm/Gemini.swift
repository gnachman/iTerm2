//
//  Gemini.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct GeminiRequestBuilder: Codable {
    let system_instruction: SystemInstructions?
    let contents: [Content]
    let tools: [Tool]?

    struct SystemInstructions: Codable {
        var parts: [Part]
    }
    struct Content: Codable {
        var role: String
        var parts: [Part]
    }
    struct Part: Codable {
        var text: String?
        var inlineData: InlineData?
        var functionResponse: FunctionResponse?
        var functionCall: FunctionCall?
    }
    struct InlineData: Codable {
        var mime_type: String
        var data: String  // base64 encoded
    }
    struct FunctionResponse: Codable {
        var id: String?
        var name: String
        var response: [String: String]

        // For non-blocking function calls (not supported yet):
        var willContinue: Bool?
        var scheduling: String?
    }
    struct FunctionCall: Codable {
        var name: String
        var args: [String: AnyCodable]
    }
    struct Tool: Codable {
        var functionDeclarations: [FunctionDeclaration]?
        var code_execution: [String: String]?  // takes an empty value
    }

    struct FunctionDeclaration: Codable {
        var name: String
        var description: String
        var parameters: JSONSchema
    }

    private static func encodedArgs(_ args: String?) -> [String: AnyCodable] {
        guard let args else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: AnyCodable].self,
                                            from: args.lossyData)
        } catch {
            DLog("\(error)")
            return [:]
        }
    }

    init(messages: [LLM.Message],
         functions: [LLM.AnyFunction],
         hostedTools: HostedTools) {
        if let systemInstructions = messages.first(where: { $0.role == .system })?.body.content as? String {
            self.system_instruction = .init(parts: [.init(text: systemInstructions)])
        } else {
            self.system_instruction = nil
        }
        var tools: [Tool] = []
        if !functions.isEmpty {
            tools.append(Tool(functionDeclarations: functions.map { function in
                FunctionDeclaration(
                    name: function.decl.name,
                    description: function.decl.description,
                    parameters: function.decl.parameters)
            }))
        } else {
            // Gemini doesn't allow both functions and hosted tools in the same call yet.
            // You can work around it with some annoying hacks but it's not worth the
            // trouble at the moment.
            // https://github.com/google/adk-python/issues/53
            if hostedTools.codeInterpreter {
                tools.append(Tool(code_execution: [:]))
            }
        }
        if tools.isEmpty {
            self.tools = nil
        } else {
            self.tools = tools
        }
        self.contents = messages.compactMap { message -> Content? in
            let role: String? = switch message.role {
            case .user: "user"
            case .assistant: "model"
            case .system: nil
            case .function:
                if message.function_call != nil {
                    "model"  // model making a call
                } else {
                    "user"  // user responding to function call
                }
            case  .none: nil
            }
            guard let role else {
                return nil
            }

            let parts: [Part] = switch message.body {
            case .uninitialized:
                []
            case .text(let string):
                [Part(text: string)]
            case .functionCall(let call, _):
                if let name = call.name {
                    [Part(functionCall: FunctionCall(name: name,
                                                     args: Self.encodedArgs(call.arguments)))]
                } else {
                    []
                }
            case .functionOutput(name: let name, output: let output, id: _):
                [Part(functionResponse: FunctionResponse(name: name,
                                                         response: ["output": output]))]
            case .attachment:
                []
            case .multipart(let subparts):
                subparts.compactMap { subpart -> Part? in
                    switch subpart {
                    case .uninitialized:
                        return nil
                    case .text(let string):
                        return Part(text: string)
                    case .functionCall, .functionOutput:
                        return nil
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let code):
                            return Part(text: code)
                        case .statusUpdate:
                            return nil
                        case .file(let file):
                            return Part(inlineData: InlineData(
                                mime_type: file.mimeType,
                                data: file.content.base64EncodedString()))
                        case .fileID:
                            return nil
                        }
                    case .multipart:
                        return nil
                    }
                }
            }
            if parts.isEmpty {
                return nil
            }
            return Content(role: role,
                           parts: parts)
        }
    }

    func body() throws -> Data {
        return try! JSONEncoder().encode(self)
    }
}

struct LLMGeminiResponseParser: LLMResponseParser {
    struct GeminiResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var choiceMessages: [LLM.Message] {
            candidates.map {
                let role = if let content = $0.content {
                    content.role == "model" ? LLM.Role.assistant : LLM.Role.user
                } else {
                    LLM.Role.assistant  // failed, probably because of safety
                }
                return if let text = $0.content?.parts.first?.text {
                    LLM.Message(role: role, content: text)
                } else if let functionCall = $0.content?.parts.first?.functionCall {
                    LLM.Message(
                        responseID: nil,
                        role: role,
                        body: .functionCall(
                            LLM.FunctionCall(
                                name: functionCall.name,
                                arguments:
                                    try! JSONEncoder().encode(functionCall.args).lossyString),
                            id: nil))
                } else {
                    if $0.finishReason == "SAFETY" {
                        LLM.Message(role: role, content: "The request violated Gemini's safety rules.")
                    } else if let reason = $0.finishReason {
                        LLM.Message(role: role, content: "Failed to generate a response with reason: \(reason).")
                    } else {
                        LLM.Message(role: role, content: "Failed to generate a response for an unknown reason.")
                    }
                }
            }
        }

        let candidates: [Candidate]

        struct Candidate: Codable {
            var content: Content?

            struct Content: Codable {
                var parts: [Part]
                var role: String

                struct Part: Codable {
                    var text: String?
                    var functionCall: GeminiRequestBuilder.FunctionCall?
                }
            }
            var finishReason: String?
        }
    }
    private(set) var parsedResponse: GeminiResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(GeminiResponse.self, from: data)
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        // Streaming not implemented
        return (nil, "")
    }
}

struct LLMGeminiStreamingResponseParser: LLMStreamingResponseParser {
    var parsedResponse: GeminiStreamingResponse?

    struct GeminiStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var newlyCreatedResponseID: String? { nil }
        var isStreamingResponse: Bool { true }
        var ignore: Bool { false }
        var responseObject: LLMGeminiResponseParser.GeminiResponse
        var choiceMessages: [LLM.Message] {
            responseObject.choiceMessages
        }
    }
    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let guts = try decoder.decode(LLMGeminiResponseParser.GeminiResponse.self, from: data)
        let response = GeminiStreamingResponse(responseObject: guts)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}
