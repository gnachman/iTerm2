//
//  LLM.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/24.
//

import Foundation

enum LLM {
    enum Role: String, Codable {
        case user
        case assistant
        case system
        case function
    }
    struct FunctionCall: Codable, Equatable {
        // These are optional because they can be omitted when streaming. Otherwise they are always present.
        var name: String?
        var arguments: String?

        // Deep seek uses this, maybe others too?
        var id: String?
    }


    protocol AnyResponse {
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
    }

    protocol AnyStreamingResponse {
        // Streaming parsers will sometimes have to parse messages that are just status updates
        // nobody cares about. Set ignore to true in that case.
        var ignore: Bool { get }
        var newlyCreatedResponseID: String? { get }
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
    }

    // This is a platform-independent representation of a message to or from an LLM.
    struct Message: Codable, Equatable {
        var responseID: String?
        var role: Role? = .user

        enum StatusUpdate: Codable, Equatable {
            case webSearchStarted
            case webSearchFinished(String?)
            case codeInterpreterStarted
            case codeInterpreterFinished
            case reasoningSummaryUpdate(String)
            case multipart([StatusUpdate])

            var exploded: [LLM.Message.StatusUpdate] {
                switch self {
                case .multipart(let parts): parts.flatMap { $0.exploded }
                default: [self]
                }
            }

            var isReasoningSummaryUpdate: Bool {
                if case .reasoningSummaryUpdate(_) = self {
                    return true
                }
                return false
            }
            var isWebSearchFinished: Bool {
                if case .webSearchFinished(_) = self {
                    return true
                }
                return false
            }
        }

        struct FunctionCallID: Codable, Equatable {
            var callID: String
            var itemID: String
        }

        struct Attachment: Codable, Equatable {
            enum AttachmentType: Codable, Equatable {
                case code(String)
                case statusUpdate(StatusUpdate)

                struct File: Codable, Equatable {
                    var name: String
                    var content: Data
                    var mimeType: String
                    var localPath: String?
                }
                case file(File)
                case fileID(id: String, name: String)
            }
            var inline: Bool
            var id: String //  e.g., ci_xxx for code interpreter
            var type: AttachmentType

            func appending(_ other: Attachment) -> Attachment? {
                // Status updates can always merge. This keep it from spamming the window with a bunch of status updates.
                if case .statusUpdate(let lhs) = type, case .statusUpdate(let rhs) = other.type {
                    var result = self
                    result.type = .statusUpdate(.multipart(lhs.exploded + rhs.exploded))
                    return result
                }
                if other.id != id {
                    return nil
                }
                switch type {
                case .code(let lhs):
                    switch other.type {
                    case .code(let rhs):
                        return .init(inline: inline, id: id, type: .code(lhs + rhs))
                    case .statusUpdate, .file, .fileID:
                        return nil
                    }
                case .file(let lhs):
                    switch other.type {
                    case .statusUpdate, .code, .fileID:
                        return nil
                    case .file(let rhs):
                        return .init(inline: inline,
                                     id: id,
                                     type: .file(.init(name: lhs.name + rhs.name,
                                                       content: lhs.content + rhs.content,
                                                       mimeType: lhs.mimeType + rhs.mimeType,
                                                       localPath: String?.concat(lhs.localPath, rhs.localPath))))
                    }
                case .statusUpdate, .fileID:
                    return nil
                }
            }
        }

        enum Body: Codable, Equatable {
            case uninitialized
            case text(String)
            case functionCall(FunctionCall, id: FunctionCallID?)
            case functionOutput(name: String, output: String, id: FunctionCallID?)
            case attachment(Attachment)
            case multipart([Body])

            var maybeContent: String? {
                switch self {
                case .multipart(let bodies):
                    return bodies.compactMap { $0.maybeContent }.joined(separator: "\n")
                case .text(let content),
                        .functionOutput(name: _, output: let content, _):
                    return content
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let string): return string
                    case .statusUpdate: return nil
                    case .file, .fileID: return nil
                    }
                case .functionCall, .uninitialized:
                    return nil
                }
            }

            var content: String {
                maybeContent ?? ""
            }

            func appending(_ additionalContent: Body) -> Self {
                var result = self
                result.append(additionalContent)
                return result
            }

            mutating func append(_ additionalContent: Body) {
                if tryAppend(additionalContent) {
                    return
                }
                if self == .uninitialized {
                    self = additionalContent
                } else {
                    self = .multipart([self, additionalContent])
                }
            }

            // Will never create multipart, but if self is already multipart will always succeed.
            mutating func tryAppend(_ additionalContent: Body) -> Bool {
                switch self {
                case .uninitialized:
                    return false
                case .text(let original):
                    if case let .text(content) = additionalContent {
                        self = .text(original + content)
                        return true
                    }
                case .functionCall(let original, id: let originalID):
                    // Only compare item IDs because OpenAI doesn't give a call ID for arguments when streaming. Deep seek does not provide any IDs after the first streaming response for a particular function call.
                    switch additionalContent {
                    case let .functionCall(content, id):
                        if (id?.itemID == originalID?.itemID || id == nil) {
                            let combinedName = (original.name ?? "") + (content.name ?? "")
                            let combinedArgs = (original.arguments ?? "") + (content.arguments ?? "")
                            let combinedID: String? = if original.id != nil || content.id != nil {
                                (original.id ?? "") + (content.id ?? "")
                            } else {
                                nil
                            }
                            self = .functionCall(
                                LLM.FunctionCall(
                                    name: combinedName,
                                    arguments: combinedArgs,
                                    id: combinedID),
                                id: originalID)
                            return true
                        }
                    case let .text(string):
                        // Anthropic does this
                        self = .functionCall(
                            LLM.FunctionCall(
                                name: original.name ?? "",
                                arguments: (original.arguments ?? "") + (string),
                                id: original.id),
                            id: originalID)
                        return true
                    case .uninitialized, .functionOutput, .attachment, .multipart:
                        break
                    }
                case let .functionOutput(name: originalName,
                                         output: originalOutput,
                                         id: originalID):
                    if case let .functionOutput(name: name, output: output, id: id) = additionalContent,
                       id == originalID {
                        self = .functionOutput(name: originalName + name,
                                               output: originalOutput + output,
                                               id: id)
                        return true
                    }
                case .attachment(let originalAttachment):
                    if case let .attachment(additionalAttachment) = additionalContent,
                       let combined = originalAttachment.appending(additionalAttachment) {
                        self = .attachment(combined)
                        return true
                    }
                case .multipart(let original):
                    if original.isEmpty {
                        self = .multipart([additionalContent])
                    } else {
                        var last = original.last!
                        if last.tryAppend(additionalContent) {
                            self = .multipart(original.dropLast() + [last])
                        } else {
                            self = .multipart(original + [additionalContent])
                        }
                    }
                    return true
                }
                return false
            }
        }
        var body: Body

        // Backward-compatibility methods
        var function_call: FunctionCall? {
            switch body {
            case .functionCall(let call, _): call
            default: nil
            }
        }
        var functionCallID: FunctionCallID? {
            switch body {
            case .functionCall(_, let id), .functionOutput(_, _, id: let id): id
            case .text, .uninitialized, .attachment, .multipart: nil
            }
        }
        var content: String? {
            body.maybeContent
        }

        init(responseID: String? = nil,
             role: Role? = .user,
             content: String? = nil,
             name: String? = nil,
             functionCallID: FunctionCallID? = nil,
             function_call: FunctionCall? = nil) {
            self.responseID = responseID
            self.role = role
            if let name, let content {
                body = .functionOutput(name: name, output: content, id: functionCallID)
            } else if let function_call {
                body = .functionCall(function_call, id: functionCallID)
            } else if let content {
                body = .text(content)
            } else {
                body = .uninitialized
            }
        }

        init(responseID: String?, role: Role?, body: Body) {
            self.responseID = responseID
            self.role = role
            self.body = body
        }

        var approximateTokenCount: Int { AIMetadata.instance.tokens(in: (body.content)) + 1 }

        var trimmedString: String? {
            return String(body.content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
        }

        enum CodingKeys: String, CodingKey {
            case role, content, function_name, function_call_id, function_call, body, responseID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
            let role = try container.decodeIfPresent(Role.self, forKey: .role)
            if let body = try container.decodeIfPresent(Body.self, forKey: .body) {
                self = Message(responseID: responseID, role: role, body: body)
            } else {
                // Legacy code path
                let content = try container.decodeIfPresent(String.self, forKey: .content)
                let functionName = try container.decodeIfPresent(String.self, forKey: .function_name)
                let functionCall = try container.decodeIfPresent(FunctionCall.self, forKey: .function_call)

                self = Message(role: role,
                               content: content,
                               name: functionName,
                               function_call: functionCall)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encodeIfPresent(role, forKey: .role)
            try container.encode(body, forKey: .body)
        }

        mutating func tryAppend(_ additionalContent: Body) -> Bool {
            return body.tryAppend(additionalContent)
        }
    }

    struct ErrorResponse: Codable {
        var error: Error

        struct Error: Codable {
            var message: String
            var type: String?
            var code: String?
        }
    }

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

    struct VectorStore {
        var name: String
        // Unique identifier provided by the server
        var id: String
    }

    struct File {
        var id: String  // file_id
        var originalFilename: String
        var originalHost: SSHIdentity?
    }
}

struct HostedTools {
    struct FileSearch {
        var vectorstoreIDs: [String]  // cannot be empty
    }
    var fileSearch: FileSearch?
    var webSearch = false
    var codeInterpreter = false
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
        case .gemini, .llama:
            [:]
        @unknown default:
            [:]
        }
    }
}


protocol LLMResponseParser {
    // Throw on error, return nil on EOF (used by streaming parsers where EOF is in the message, not in the metadata like OpenAI's modern API)
    mutating func parse(data: Data) throws -> LLM.AnyResponse?
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String)
}

protocol LLMStreamingResponseParser {
    // Throw on error, return nil on EOF (used by streaming parsers where EOF is in the message, not in the metadata like OpenAI's modern API)
    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse?
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String)
}


