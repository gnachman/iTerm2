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
        // Gemini 3 returns this on functionCall parts and requires it back unchanged.
        var thoughtSignature: String?
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
            RLog("\(error)")
            return [:]
        }
    }

    private static func parametersForGemini(_ schema: JSONSchema) -> JSONSchema {
        do {
            let data = try JSONEncoder().encode(schema)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let sanitized = sanitizingFunctionParameterSchema(object) as? [String: Any] else {
                return schema
            }
            return JSONSchema(rawJSON: sanitized)
        } catch {
            DLog("Failed to sanitize Gemini function parameters: \(error)")
            return schema
        }
    }

    private static func sanitizingFunctionParameterSchema(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            var result = [String: Any]()
            for (key, value) in dictionary where key != "additionalProperties" {
                switch key {
                case "type":
                    if let typeNames = value as? [Any] {
                        let names = typeNames.compactMap { $0 as? String }
                        if let typeName = names.first(where: { $0 != "null" }) {
                            result[key] = typeName
                        }
                        if names.contains("null") {
                            result["nullable"] = true
                        }
                    } else {
                        result[key] = value
                    }
                case "items":
                    if let typeName = value as? String {
                        result[key] = ["type": typeName]
                    } else {
                        result[key] = sanitizingFunctionParameterSchema(value)
                    }
                case "properties", "$defs", "definitions", "patternProperties":
                    // These map member names to child schemas. A member name
                    // may itself be a JSON Schema keyword (e.g. a property
                    // literally named "type", "items", or "additionalProperties").
                    // Recurse each value as a schema and keep the member name
                    // verbatim so it is never reinterpreted as a keyword.
                    if let members = value as? [String: Any] {
                        var sanitizedMembers = [String: Any]()
                        for (memberName, memberSchema) in members {
                            sanitizedMembers[memberName] = sanitizingFunctionParameterSchema(memberSchema)
                        }
                        result[key] = sanitizedMembers
                    } else {
                        result[key] = sanitizingFunctionParameterSchema(value)
                    }
                case "enum", "const", "default", "examples":
                    // These carry literal data values, not subschemas. Recursing
                    // would treat an object-valued default/const/example as a
                    // schema and strip its additionalProperties or rewrite a
                    // "type" array member, corrupting the actual value. Copy
                    // verbatim. (Bites rawJSON-backed MCP/orchestrator schemas.)
                    result[key] = value
                default:
                    result[key] = sanitizingFunctionParameterSchema(value)
                }
            }
            return result
        }
        if let array = object as? [Any] {
            return array.map { sanitizingFunctionParameterSchema($0) }
        }
        return object
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
                    parameters: Self.parametersForGemini(function.decl.parameters))
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
        let rawContents = messages.compactMap { message -> Content? in
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
                                                     args: Self.encodedArgs(call.arguments)),
                          thoughtSignature: call.thoughtSignature)]
                } else {
                    []
                }
            case .functionOutput(name: let name, output: let output, id: _):
                [Part(functionResponse: FunctionResponse(name: name,
                                                         response: ["output": output]))]
            case .attachment:
                // TODO: Gemini's request builder drops top-level .attachment
                // bodies (no multipart wrapper). Production callers always
                // wrap user-sent attachments in a multipart with at least
                // their prompt text, so this hasn't bitten anyone, but a
                // stray bare-attachment body silently produces a request
                // with no contents. Mirror the multipart branch's
                // attachment handling here if we ever rely on this path.
                // Pinned by AIRequestBuilderAttachmentTests.testGemini_topLevelAttachment_isUnsupported.
                []
            case .multipart(let subparts):
                subparts.compactMap { subpart -> Part? in
                    switch subpart {
                    case .uninitialized:
                        return nil
                    case .text(let string):
                        return Part(text: string)
                    case .functionCall(let call, _):
                        // Mirror the top-level .functionCall handling: emit a
                        // functionCall Part carrying the per-call thoughtSignature,
                        // which Gemini 3 requires to be echoed back unchanged.
                        if let name = call.name {
                            return Part(functionCall: FunctionCall(
                                            name: name,
                                            args: Self.encodedArgs(call.arguments)),
                                        thoughtSignature: call.thoughtSignature)
                        }
                        return nil
                    case .functionOutput(name: let name, output: let output, id: _):
                        return Part(functionResponse: FunctionResponse(
                                        name: name,
                                        response: ["output": output]))
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let code):
                            return Part(text: code)
                        case .statusUpdate:
                            return nil
                        case .file(let file):
                            // Textual content (including image/svg+xml and
                            // application/xml) must go through a text Part,
                            // not inlineData. Gemini's inlineData validates
                            // the MIME against a binary-format allowlist and
                            // 400s on anything textual that's not text/plain.
                            // Pinned by AIRequestBuilderAttachmentTests.testGemini_svgAttachment_asText
                            // and the cross-vendor live attachment matrix.
                            if MIMETypeIsTextual(file.mimeType) {
                                return Part(text: file.content.lossyString)
                            }
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
        self.contents = Self.coalescingConsecutiveRoles(rawContents)
    }

    // A reloaded tool round-trip is replayed as a single folded assistant
    // transcript message (see ChatAgent.aiMessagesForTranscript), which can
    // leave two consecutive `model` turns: the folded transcript followed by
    // the model's final text reply. Gemini requires alternating user/model
    // turns and 400s on consecutive same-role turns, so merge adjacent
    // same-role Contents by concatenating their parts.
    private static func coalescingConsecutiveRoles(_ contents: [Content]) -> [Content] {
        var output: [Content] = []
        for content in contents {
            if let last = output.last, last.role == content.role {
                output[output.count - 1] = Content(role: last.role,
                                                   parts: last.parts + content.parts)
            } else {
                output.append(content)
            }
        }
        return output
    }

    func body() throws -> Data {
        return try! JSONEncoder().encode(self)
    }
}

struct LLMGeminiResponseParser: LLMResponseParser {
    struct GeminiResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var choiceMessages: [LLM.Message] {
            // Gemini returns one or more candidates; iTerm2 never requests
            // candidateCount > 1, so only the first candidate matters.
            // Within that candidate, parts is a list of consecutive pieces
            // of one assistant turn (e.g. [text preamble, functionCall +
            // thoughtSignature]). Collapse them into a single multipart-bodied
            // Message so AITerm sees the same shape as every other vendor.
            guard let candidate = candidates.first else { return [] }
            let role: LLM.Role = if let content = candidate.content {
                content.role == "model" ? .assistant : .user
            } else {
                .assistant  // failed, probably because of safety
            }
            let parts = candidate.content?.parts ?? []
            let bodies: [LLM.Message.Body] = parts.compactMap { part in
                if let text = part.text, !text.isEmpty {
                    return .text(text)
                }
                if let functionCall = part.functionCall {
                    return .functionCall(
                        LLM.FunctionCall(
                            name: functionCall.name,
                            arguments:
                                try! JSONEncoder().encode(functionCall.args).lossyString,
                            id: nil,
                            thoughtSignature: part.thoughtSignature),
                        id: nil)
                }
                return nil
            }
            if !bodies.isEmpty {
                let body: LLM.Message.Body = bodies.count == 1 ? bodies[0] : .multipart(bodies)
                return [LLM.Message(responseID: nil, role: role, body: body)]
            }
            // No usable parts. STOP/MAX_TOKENS are normal completions. Gemini
            // streams a final empty-text chunk with finishReason=STOP after a
            // function call, and Body.tryAppend would otherwise merge a synthetic
            // "Failed..." string into the function call's arguments and corrupt
            // the JSON. Return no message in those cases. Only emit a synthetic
            // message for genuine failure reasons (safety, recitation, etc.).
            guard let reason = candidate.finishReason else {
                return []
            }
            switch reason {
            case "STOP", "MAX_TOKENS", "FINISH_REASON_UNSPECIFIED":
                return []
            case "SAFETY":
                return [LLM.Message(role: role,
                                    content: "The request violated Gemini's safety rules.")]
            default:
                return [LLM.Message(role: role,
                                    content: "Failed to generate a response with reason: \(reason).")]
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
                    var thoughtSignature: String?
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
