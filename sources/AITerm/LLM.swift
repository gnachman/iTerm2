//
//  LLM.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/24.
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code (token counting, function
//  invocation, auth) lives in LLM+Mac.swift.
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

        // Gemini 3 attaches a per-call signature on functionCall parts. The server
        // requires it to be echoed back unchanged on subsequent requests; omitting
        // it triggers a 4xx validation error.
        var thoughtSignature: String?
    }


    protocol AnyResponse {
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
        var newlyCreatedResponseID: String? { get }
    }
}

extension LLM.AnyResponse {
    // Default for vendors that don't expose a server-side response ID for chaining.
    var newlyCreatedResponseID: String? { nil }
}

extension LLM {

    protocol AnyStreamingResponse {
        // Streaming parsers will sometimes have to parse messages that are just status updates
        // nobody cares about. Set ignore to true in that case.
        var ignore: Bool { get }
        var newlyCreatedResponseID: String? { get }
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
    }

    // This is a platform-independent representation of a message to or from an LLM.
    /// One reasoning item from an OpenAI Responses turn: the server-minted id
    /// plus the encrypted payload returned when the request asks for
    /// include: ["reasoning.encrypted_content"] with store:false. Replayed
    /// verbatim (id + encrypted_content) before the function_call items it
    /// produced. Foundation-only and Codable so it can persist inside the
    /// chat Message content JSON and cross the companion wire as an ignored
    /// unknown key on older peers.
    struct ReasoningItem: Codable, Equatable {
        var id: String
        var encryptedContent: String?
        /// Human-readable summary texts (when the API produced any); kept for
        /// fidelity, not required for replay.
        var summary: [String]?

        init(id: String, encryptedContent: String?, summary: [String]? = nil) {
            self.id = id
            self.encryptedContent = encryptedContent
            self.summary = summary
        }
    }

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
                                    id: combinedID,
                                    thoughtSignature: original.thoughtSignature ?? content.thoughtSignature),
                                id: originalID)
                            return true
                        }
                    case let .text(string):
                        // Anthropic does this. Preserve thoughtSignature in case
                        // a future provider (Gemini-shaped) ever streams partial
                        // function-call args as text deltas alongside a signature.
                        self = .functionCall(
                            LLM.FunctionCall(
                                name: original.name ?? "",
                                arguments: (original.arguments ?? "") + (string),
                                id: original.id,
                                thoughtSignature: original.thoughtSignature),
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
            case .multipart(let parts):
                // Parsers now collapse multi-part turns (text preamble +
                // tool_use, function tool call + assistant message, etc.)
                // into a single multipart-bodied Message. Surface the first
                // embedded function call so AITerm can detect and dispatch
                // it without inspecting the body shape.
                parts.lazy.compactMap { part -> FunctionCall? in
                    if case .functionCall(let call, _) = part { return call }
                    return nil
                }.first
            case .text, .uninitialized, .attachment, .functionOutput: nil
            }
        }
        var functionCallID: FunctionCallID? {
            switch body {
            case .functionCall(_, let id), .functionOutput(_, _, id: let id): id
            case .multipart(let parts):
                // Anthropic-style assistant turns can be [text preamble, function_call];
                // surface the first embedded function-call ID so callers don't need to
                // know whether the turn was wrapped in multipart.
                parts.lazy.compactMap { part -> FunctionCallID? in
                    if case .functionCall(_, let id) = part { return id }
                    if case .functionOutput(_, _, id: let id) = part { return id }
                    return nil
                }.first
            case .text, .uninitialized, .attachment: nil
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
             function_call: FunctionCall? = nil,
             reasoningContent: String? = nil) {
            self.responseID = responseID
            self.role = role
            self.reasoningContent = reasoningContent
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

        init(responseID: String? = nil,
             role: Role?,
             body: Body,
             reasoningContent: String? = nil,
             reasoningItems: [ReasoningItem]? = nil) {
            self.responseID = responseID
            self.role = role
            self.body = body
            self.reasoningContent = reasoningContent
            self.reasoningItems = reasoningItems
        }

        // DeepSeek v4 returns a `reasoning_content` field on assistant turns when
        // thinking mode is enabled, and its API requires the same content to be
        // echoed back on every subsequent request or the next turn 400s. Stored
        // here so the request builder can re-emit it without the rest of the
        // framework caring. Forward+backward Codable compatible: unknown to old
        // decoders, nil for old payloads. Display goes through the parallel
        // .statusUpdate(.reasoningSummaryUpdate) path so this field is purely
        // round-trip state, not a render input.
        var reasoningContent: String?

        /// OpenAI Responses reasoning items (id + encrypted payload) emitted
        /// alongside this assistant turn's function calls. The API requires
        /// them to be replayed, in order, before their function_call items
        /// whenever the conversation is re-sent (store:false / after a
        /// reload); without them a reasoning model 400s on the historical
        /// call. Persisted so a reloaded chat can keep using its tool
        /// history. Forward+backward Codable compatible like
        /// reasoningContent: unknown to old decoders, nil for old payloads.
        var reasoningItems: [ReasoningItem]?

        enum CodingKeys: String, CodingKey {
            case role, content, function_name, function_call_id, function_call, body, responseID, reasoningContent, reasoningItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
            let role = try container.decodeIfPresent(Role.self, forKey: .role)
            let reasoning = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
            let reasoningItems = try container.decodeIfPresent([ReasoningItem].self, forKey: .reasoningItems)
            if let body = try container.decodeIfPresent(Body.self, forKey: .body) {
                self = Message(responseID: responseID, role: role, body: body,
                               reasoningContent: reasoning, reasoningItems: reasoningItems)
            } else {
                // Legacy code path
                let content = try container.decodeIfPresent(String.self, forKey: .content)
                let functionName = try container.decodeIfPresent(String.self, forKey: .function_name)
                let functionCall = try container.decodeIfPresent(FunctionCall.self, forKey: .function_call)

                self = Message(role: role,
                               content: content,
                               name: functionName,
                               function_call: functionCall,
                               reasoningContent: reasoning)
                self.reasoningItems = reasoningItems
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encodeIfPresent(role, forKey: .role)
            try container.encode(body, forKey: .body)
            try container.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
            try container.encodeIfPresent(reasoningItems, forKey: .reasoningItems)
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

    struct VectorStore {
        var name: String
        // Unique identifier provided by the server
        var id: String
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


extension LLM.Message.StatusUpdate {
    static func subpartsForDisplay(_ subparts: [LLM.Message.StatusUpdate]) -> [LLM.Message.StatusUpdate] {
        // Keep the last "long" update plus everything after it
        var singlePartUpdates = subparts.flatMap { $0.exploded }

        let lastReasoningSummaryUpdateIndex = singlePartUpdates.lastIndex(where: { $0.isReasoningSummaryUpdate })
        let lastWebSearchFinishedIndex = singlePartUpdates.lastIndex(where: { $0.isWebSearchFinished })
        let lastCodeInterpreterFinishedIndex = singlePartUpdates.lastIndex(where: { $0 == .codeInterpreterFinished })
        let keepStart = [lastReasoningSummaryUpdateIndex,
                         lastWebSearchFinishedIndex,
                         lastCodeInterpreterFinishedIndex].compactMap { $0 }.max()
        if let keepStart {
            singlePartUpdates.removeSubrange(..<keepStart)
        }
        return singlePartUpdates
    }

    var displayString: String {
        switch self {
        case .webSearchStarted:
            "Searching the web…"
        case .webSearchFinished(let query):
            if let query {
                "Finished searching the web for \(query)."
            } else {
                "Finished searching the web."
            }
        case .codeInterpreterStarted:
            "Executing code…"
        case .codeInterpreterFinished:
            "Finished executing code"
        case .reasoningSummaryUpdate(let text): text
        case .multipart(let subparts):
            Self.subpartsForDisplay(subparts).map { $0.displayString }.joined(separator: "\n")
        }
    }
}
