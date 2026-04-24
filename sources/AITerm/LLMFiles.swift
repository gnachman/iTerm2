//
//  LLMFiles.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LLMFileUploader {
    var provider: LLMProvider
    var apiKey: String
    var responsesBuilder: ResponsesFileUploadBuilder

    init?(provider: LLMProvider, apiKey: String, fileName: String, content: Data) {
        self.provider = provider
        self.apiKey = apiKey
        switch provider.model.api {
        case .responses:
            responsesBuilder = ResponsesFileUploadBuilder(provider: provider,
                                                          apiKey: apiKey,
                                                          fileName: fileName,
                                                          content: content)
        case .completions, .chatCompletions, .gemini, .earlyO1, .llama, .deepSeek, .anthropic:
            return nil
        @unknown default:
            return nil
        }
    }

    var headers: [String: String] {
        return responsesBuilder.headers
    }

    var method: String { "POST" }

    func body() throws -> Data {
        return try responsesBuilder.body()
    }

    func webRequest() throws -> WebRequest {
        let body = try body()
        guard let url = provider.uploadURL() else {
            throw AIError("File upload is not supported with this LLM provider")
        }
        return WebRequest(headers: headers,
                          method: method,
                          body: .bytes(Array(body)),
                          url: url.absoluteString)
    }

    func idFromResponse(_ response: Data) throws -> String {
        return try responsesBuilder.idFromResponse(response)
    }
}

struct ResponsesFileUploadBuilder {
    var provider: LLMProvider
    var apiKey: String
    var fileName: String
    var content: Data
    let boundary = "Boundary-\(UUID().uuidString)"

    /// Constructs the Data to use as `httpBody` for a file‐upload `URLRequest`.
    func body() throws -> Data {
        let ext = fileName.pathExtension.lowercased()
        return try createMultipartBody(
            fileData: content,
            fieldName: "file",
            fileName: fileName,
            mimeType: openAIExtensionToMime[ext] ?? "application/octet-stream",
            parameters: ["purpose": "assistants"],
            boundary: boundary)
    }

    var headers: [String: String] {
        var result = LLMAuthorizationProvider(provider: provider,
                                              apiKey: apiKey).headers
        result["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        return result
    }

    func idFromResponse(_ response: Data) throws -> String {
        struct FileUploadResponse: Decodable {
            /// The unique identifier of the uploaded file
            let id: String

            /// There are other values but I don't care about them.
        }
        return try JSONDecoder().decode(FileUploadResponse.self,
                                        from: response).id
    }
}
