//
//  LLMVectorStore.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LLMVectorStoreBatchStatusChecker {
    var provider: LLMProvider
    var apiKey: String
    var vectorStoreID: String
    var batchID: String

    init?(provider: LLMProvider, apiKey: String, batchID: String, vectorStoreID: String) {
        switch provider.model.api {
        case .chatCompletions, .completions, .earlyO1, .gemini, .llama, .deepSeek, .anthropic:
            return nil
        case .responses:
            self.provider = provider
            self.apiKey = apiKey
            self.vectorStoreID = vectorStoreID
            self.batchID = batchID
        @unknown default:
            return nil
        }
    }

    var headers: [String: String] {
        return LLMAuthorizationProvider(provider: provider,
                                        apiKey: apiKey).headers
    }

    var method: String { "GET" }

    func body() throws -> Data {
        Data()
    }

    func webRequest() throws -> WebRequest {
        let body = try body()
        let url = URL(string: "https://api.openai.com/v1/vector_stores/\(vectorStoreID)/file_batches/\(batchID)")!
        return WebRequest(headers: headers,
                          method: method,
                          body: .string(body.lossyString),
                          url: url.absoluteString)
    }

    enum Status: String, Codable {
        case inProgress = "in_progress"
        case completed
        case cancelled
        case failed
    }

    struct Response: Codable {
        var status: Status
    }

    func statusFromResponse(_ response: Data) throws -> Status {
        return try JSONDecoder().decode(Response.self,
                                        from: response).status
    }
}

struct LLMVectorStoreAdder {
    var provider: LLMProvider
    var apiKey: String
    var vectorStoreID: String
    var fileIDs: [String]

    init?(provider: LLMProvider, apiKey: String, fileIDs: [String], vectorStoreID: String) {
        switch provider.model.api {
        case .chatCompletions, .completions, .earlyO1, .gemini, .llama, .deepSeek, .anthropic:
            return nil
        case .responses:
            self.provider = provider
            self.apiKey = apiKey
            self.vectorStoreID = vectorStoreID
            self.fileIDs = fileIDs
        @unknown default:
            return nil
        }
    }

    var headers: [String: String] {
        var result = LLMAuthorizationProvider(provider: provider,
                                              apiKey: apiKey).headers
        result["Content-Type"] = "application/json"
        return result
    }

    var method: String { "POST" }

    func body() throws -> Data {
        struct Request: Codable {
            var file_ids: [String]
        }
        return try JSONEncoder().encode(Request(file_ids: fileIDs))
    }

    func webRequest() throws -> WebRequest {
        let body = try body()
        guard let url = provider.addFileToVectorStoreURL(apiKey: apiKey, vectorStoreID: vectorStoreID) else {
            throw AIError("Adding to vector store is not supported with this LLM provider")
        }
        return WebRequest(headers: headers,
                          method: method,
                          body: .string(body.lossyString),
                          url: url.absoluteString)
    }

    enum Status: String, Codable {
        case inProgress = "in_progress"
        case completed
        case cancelled
        case failed
    }
    struct ErrorResponse: Codable {
        struct ErrorDetail: Codable {
            var message: String
        }
        var error: ErrorDetail
    }
    struct Response: Codable {
        var status: Status
        var id: String
    }

    func statusFromResponse(_ response: Data) throws -> Status {
        if let error = try? JSONDecoder().decode(ErrorResponse.self, from: response) {
            throw AIError("Failed to add files to vector store: \(error.error.message)")
        }
        return try JSONDecoder().decode(Response.self,
                                        from: response).status
    }

    func batchIDFromResponse(_ response: Data) throws -> String {
        return try JSONDecoder().decode(Response.self,
                                        from: response).id
    }
}

/*
 curl https://api.openai.com/v1/vector_stores \
   -H "Authorization: Bearer $OPENAI_API_KEY" \
   -H "Content-Type: application/json" \
   -d '{
     "name": "knowledge_base"
   }'
 */
struct LLMVectorStoreCreator {
    var name: String
    var provider: LLMProvider
    var apiKey: String
    var headers: [String: String] {
        var result = LLMAuthorizationProvider(provider: provider, apiKey: apiKey).headers
        result["Content-Type"] = "application/json"
        return result
    }
    var method: String { "POST" }

    func body() throws -> Data? {
        switch provider.model.api {
        case .chatCompletions, .completions, .earlyO1, .gemini, .llama, .deepSeek, .anthropic:
            return nil
        case .responses:
            let payload: [String: String] = ["name": name]
            let jsonData = try JSONEncoder().encode(payload)
            return jsonData
        @unknown default:
            return nil
        }
    }

    func webRequest() throws -> WebRequest {
        guard let body = try body(), let url = provider.createVectorStoreURL(apiKey: apiKey) else {
            if LLMMetadata.hostIsOpenAIAPI(url: provider.url(apiKey: apiKey, streaming: false)) {
                throw AIError("The vector store has not been enabled in settings")
            }
            throw AIError("No vector store is available for this LLM provider.")
        }
        return WebRequest(headers: headers,
                          method: method,
                          body: .string(body.lossyString),
                          url: url.absoluteString)
    }

    func idFromResponse(_ response: Data) throws -> String {
        struct VectorStoreResponse: Decodable {
            let id: String
            let object: String
            let name: String
            let created_at: Int
        }
        return try JSONDecoder().decode(VectorStoreResponse.self, from: response).id
    }
}

