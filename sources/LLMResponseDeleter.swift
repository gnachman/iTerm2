//
//  LLMResponseDeleter.swift
//  iTerm2
//
//  Created by George Nachman on 6/12/25.
//

struct LLMResponseDeleter {
    var provider: LLMProvider
    var apiKey: String
    var builder: ResponsesDeleterBuilder
    var responseID: String

    init?(provider: LLMProvider, apiKey: String, responseID: String) {
        self.provider = provider
        self.apiKey = apiKey
        self.responseID = responseID

        switch provider.model.api {
        case .responses:
            builder = ResponsesDeleterBuilder(provider: provider,
                                              apiKey: apiKey,
                                              responseID: responseID)
        case .completions, .chatCompletions, .gemini, .earlyO1, .llama, .deepSeek:
            return nil
        @unknown default:
            return nil
        }
    }

    var headers: [String: String] {
        return builder.headers
    }

    var method: String { "DELETE" }

    func body() throws -> Data {
        return try builder.body()
    }

    func webRequest() throws -> WebRequest {
        let body = try body()
        return WebRequest(headers: headers,
                          method: method,
                          body: .bytes(Array(body)),
                          url: builder.url)
    }
}

struct ResponsesDeleterBuilder {
    var provider: LLMProvider
    var apiKey: String
    var responseID: String

    func body() throws -> Data {
        Data()
    }

    var headers: [String: String] {
        var result = LLMAuthorizationProvider(provider: provider,
                                              apiKey: apiKey).headers
        result["Content-Type"] = "application/json"
        return result
    }

    var url: String {
        "https://api.openai.com/v1/responses/\(responseID)"
    }
}
