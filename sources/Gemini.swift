//
//  Gemini.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct GeminiRequestBuilder: Codable {
    let contents: [Content]

    struct Content: Codable {
        var role: String
        var parts: [Part]

        struct Part: Codable {
            let text: String
        }
    }

    init(messages: [LLM.Message]) {
        self.contents = messages.compactMap { message -> Content? in
            // NOTE: role changed when AI chat was added but I am not able to test it, so if someone complains it's probably a bug here.
            let role: String? = switch message.role {
            case .user: "user"
            case .assistant: "model"
            case .system: "system"
            case .function, .none: nil
            }
            guard let role else {
                return nil
            }
            return Content(role: role,
                           parts: [Content.Part(text: message.body.content)])
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
                    var text: String
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

