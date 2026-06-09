//
//  MessageDTO.swift
//  CompanionCore
//
//  Wire form of a chat message. This is a deliberately reduced projection of
//  the macOS Message.Content enum (which has ~18 cases tied to mac-only types
//  like RemoteCommand and AIExplanationRequest). The phone only needs to
//  render the conversation and send user turns, so the DTO models the content
//  the phone displays plus the streaming deltas it must apply. Content the
//  phone cannot act on is collapsed by the mac bridge into `.notice` or
//  `.unsupported` rather than leaking mac types onto the wire.
//

import Foundation

/// Who authored a message. Mirrors the mac Participant (user/agent) plus a
/// `system` case the bridge uses for notices and watcher events so the phone
/// can render them in the centered system-bubble style.
public enum ParticipantDTO: String, Codable, Equatable, Hashable {
    case user
    case agent
    case system
}

public struct MessageDTO: Codable, Equatable, Identifiable, Hashable {
    public var uniqueID: UUID
    public var author: ParticipantDTO
    public var content: ContentDTO
    public var sentDate: Date

    public var id: UUID { uniqueID }

    public init(uniqueID: UUID,
                author: ParticipantDTO,
                content: ContentDTO,
                sentDate: Date) {
        self.uniqueID = uniqueID
        self.author = author
        self.content = content
        self.sentDate = sentDate
    }

    /// A subpart of a multipart message.
    public enum SubpartDTO: Codable, Equatable, Hashable {
        case plainText(String)
        case markdown(String)
        case code(String)
        case attachment(name: String, mimeType: String)
    }

    public enum ContentDTO: Codable, Equatable, Hashable {
        case plainText(String)
        case markdown(String)
        case multipart([SubpartDTO])

        /// Streaming delta: append `string` to the message with `messageID`.
        case append(string: String, messageID: UUID)
        /// End of a streaming response for `messageID`.
        case commit(messageID: UUID)

        /// A system notice (maps from mac clientLocal .notice and similar).
        case notice(String)
        /// Whether the agent is currently sending commands automatically.
        case streamingChanged(active: Bool)

        /// A command the agent wants to run on the mac. The phone shows the
        /// description; approval/denial is actioned on the mac side. `safe`
        /// nil means the mac has not classified it.
        case remoteCommandRequest(description: String, safe: Bool?)
        /// A terminal command and its output, rendered as a command bubble.
        case terminalCommand(command: String, output: String?)

        /// Forward-compatibility sink: a content type this phone build does not
        /// model. `summary` is a human-readable one-liner the phone can show so
        /// the conversation does not silently drop a turn.
        case unsupported(summary: String)
    }

    /// The short text shown in the chat-list snippet, if any.
    public var snippetText: String? {
        switch content {
        case .plainText(let s), .markdown(let s), .notice(let s):
            return s
        case .multipart(let parts):
            for part in parts.reversed() {
                switch part {
                case .plainText(let s), .markdown(let s), .code(let s):
                    return s
                case .attachment(let name, _):
                    return "📄 " + name
                }
            }
            return nil
        case .terminalCommand(let command, _):
            return command
        case .remoteCommandRequest(let description, _):
            return description
        case .append, .commit, .streamingChanged:
            return nil
        case .unsupported(let summary):
            return summary
        }
    }
}
