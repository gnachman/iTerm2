//
//  LLM+Mac.swift
//  iTerm2
//
//  Mac-only parts of the LLM namespace: token counting, function invocation
//  (ChatGPT function declarations), server-side file metadata, and request
//  authorization. Split from LLM.swift, which is shared with the iOS
//  companion app.
//

import Foundation

extension LLM.Message {
    var approximateTokenCount: Int { AIMetadata.instance.tokens(in: (body.content)) + 1 }

    var trimmedString: String? {
        return String(body.content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
    }
}

extension LLM {
    protocol AnyFunction {
        var typeErasedParameterType: Any.Type { get }
        var decl: ChatGPTFunctionDeclaration { get }
        func invoke(message: LLM.Message,
                    json: Data,
                    completion: @escaping (Result<String, Error>) throws -> ())
    }

    struct Function<T: Codable>: AnyFunction {
        typealias Impl = (LLM.Message, T, @escaping (Result<String, Error>) throws -> ()) throws -> ()

        var decl: ChatGPTFunctionDeclaration
        var call: Impl
        var parameterType: T.Type

        var typeErasedParameterType: Any.Type { parameterType }
        func invoke(message: Message,
                    json: Data,
                    completion: @escaping (Result<String, Error>) throws -> ()) {
            do {
                var jsonString = json.lossyString
                if jsonString.isEmpty {
                    // Anthropic does this
                    jsonString = "{}"
                }
                let value = try JSONSerialization.parseTruncatedJSON(jsonString, as: parameterType)
                try call(message, value, completion)
            } catch {
                DLog("\(error.localizedDescription)")
                try? completion(.failure(AIError.wrapping(
                    error: error,
                    context: "While parsing a function call request")))
            }
        }
    }

    struct File {
        var id: String  // file_id
        var originalFilename: String
        var originalHost: SSHIdentity?
    }
}

struct LLMAuthorizationProvider {
    var provider: LLMProvider
    var apiKey: String
    var headers: [String: String] {
        switch provider.model.api {
        case .chatCompletions, .completions, .earlyO1, .responses, .deepSeek:
            if LLMMetadata.hostIsAzureAIAPI(url: URL(string: provider.model.url)) {
                ["api-key": apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ]
            } else {
                ["Authorization": "Bearer " + apiKey.trimmingCharacters(in: .whitespacesAndNewlines)]
            }
        case .anthropic:
            ["x-api-key": apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
             "anthropic-version": "2023-06-01"]
        case .gemini, .llama, .appleIntelligence:
            [:]
        @unknown default:
            [:]
        }
    }
}
