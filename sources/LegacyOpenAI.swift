//
//  LegacyOpenAI.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LegacyBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider

    private struct LegacyBody: Codable {
        var model: String?
        var prompt: String
        var max_tokens: Int
    }

    func body() throws -> Data {
        let query = messages.compactMap { $0.body.content }.joined(separator: "\n")
        let body = LegacyBody(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            prompt: query,
            max_tokens: provider.maxTokens(functions: [], messages: messages))
        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }
}

struct LLMLegacyResponseParser: LLMResponseParser {
    struct LegacyResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var id: String
        var object: String
        var created: Int
        var model: String
        var choices: [Choice]
        var usage: Usage?

        struct Choice: Codable {
            var text: String
            var index: Int?
            var logprobs: Int?
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }

        var choiceMessages: [LLM.Message] {
            return choices.map {
                return LLM.Message(role: .assistant, content: $0.text)
            }
        }
    }

    private(set) var parsedResponse: LegacyResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyResponse.self, from: data)
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct LLMLegacyStreamingResponseParser: LLMStreamingResponseParser {
    struct LegacyStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var newlyCreatedResponseID: String? { nil }
        var ignore: Bool { false }
        var isStreamingResponse: Bool { true }
        var model: String
        var created_at: String
        var response: String
        var done: Bool

        var choiceMessages: [LLM.Message] {
            return [LLM.Message(role: .assistant, content: response)]
        }
    }

    private(set) var parsedResponse: LegacyStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyStreamingResponse.self, from: data)
        if response.done {
            return nil
        }
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
        guard let newlineRange = input.range(of: "\n") else {
            return (nil, String(input))
        }

        // Extract the first line (up to, but not including, the newline)
        let firstLine = input[..<newlineRange.lowerBound]
        // Everything after the newline is the remainder.
        let remainder = input[newlineRange.upperBound...]

        // The line can optionally start with data:
        let prefixCandidates = ["data:", ""]
        var prefix = ""
        for candidate in prefixCandidates {
            if firstLine.hasPrefix(candidate) {
                prefix = candidate
                break
            }
        }

        // Remove the prefix and trim whitespace to get the JSON object.
        let jsonPart = firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

        return (String(jsonPart.removing(prefix: prefix)), String(remainder))
    }
}

struct LLMErrorParser {
    private(set) var error: LLM.ErrorResponse?

    mutating func parse(data: Data) -> String? {
        let decoder = JSONDecoder()
        error = try? decoder.decode(LLM.ErrorResponse.self, from: data)
        if error == nil {
            struct GoogleError: Codable {
                var error: ErrorBody
                struct ErrorBody: Codable {
                    var message: String
                }
            }
            if let message = try? decoder.decode(GoogleError.self, from: data) {
                error = LLM.ErrorResponse(
                    error: LLM.ErrorResponse.Error(
                        message: message.error.message))
            }
        }
        return error?.error.message
    }

    static func errorReason(data: Data) -> String? {
        var parser = LLMErrorParser()
        return parser.parse(data: data)
    }
}

