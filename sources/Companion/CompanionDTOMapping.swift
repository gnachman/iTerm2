//
//  CompanionDTOMapping.swift
//  iTerm2
//
//  Translates between iTerm2's chat model (Chat, Message) and the transport-
//  neutral wire DTOs the companion protocol speaks. Outbound mapping is
//  deliberately lossy: only content the phone can render is forwarded, and
//  internal bookkeeping messages map to nil so they never reach the phone.
//

import Foundation
import CompanionProtocol

enum CompanionDTOMapping {
    // MARK: Chat -> ChatDTO

    static func chatDTO(from chat: Chat, snippet: String?) -> ChatDTO {
        ChatDTO(id: chat.id,
                title: chat.title,
                creationDate: chat.creationDate,
                lastModifiedDate: chat.lastModifiedDate,
                orchestrationEnabled: chat.orchestrationEnabled,
                terminalSessionGuid: chat.terminalSessionGuid,
                snippet: snippet)
    }

    // MARK: Message -> MessageDTO (outbound)

    /// Returns nil for messages the phone should not see (internal/bookkeeping).
    static func messageDTO(from message: Message) -> MessageDTO? {
        guard let content = contentDTO(from: message.content) else {
            return nil
        }
        return MessageDTO(uniqueID: message.uniqueID,
                          author: participant(for: message),
                          content: content,
                          sentDate: message.sentDate)
    }

    private static func participant(for message: Message) -> ParticipantDTO {
        switch message.content {
        case .clientLocal, .watcherEvent:
            return .system
        default:
            return message.author == .user ? .user : .agent
        }
    }

    private static func contentDTO(from content: Message.Content) -> MessageDTO.ContentDTO? {
        switch content {
        case .plainText(let text, _):
            return .plainText(text)
        case .markdown(let text):
            return .markdown(text)
        case .multipart(let subparts, _):
            let mapped = subparts.compactMap(subpartDTO(from:))
            return mapped.isEmpty ? nil : .multipart(mapped)
        case .append(let string, let uuid):
            return .append(string: string, messageID: uuid)
        case .commit(let uuid):
            return .commit(messageID: uuid)
        case .terminalCommand(let command):
            return .terminalCommand(command: command.command, output: command.output)
        case .remoteCommandRequest(let payload, let safe):
            return .remoteCommandRequest(description: payload.markdownDescription, safe: safe)
        case .watcherEvent(let update):
            return .notice(update.detail)
        case .clientLocal(let clientLocal):
            switch clientLocal.action {
            case .notice(let text):
                return .notice(text)
            case .streamingChanged(let state):
                return .streamingChanged(active: state == .active)
            default:
                return nil
            }
        default:
            // Internal/bookkeeping content (remoteCommandResponse, renameChat,
            // setPermissions, vectorStoreCreated, userCommand, explanation*,
            // selectSessionRequest) is not forwarded.
            return nil
        }
    }

    private static func subpartDTO(from subpart: Message.Subpart) -> MessageDTO.SubpartDTO? {
        switch subpart {
        case .plainText(let text):
            return .plainText(text)
        case .markdown(let text):
            return .markdown(text)
        case .attachment(let attachment):
            switch attachment.type {
            case .code(let code):
                return .code(code)
            case .file(let file):
                return .attachment(name: file.name, mimeType: "")
            case .fileID(_, let name):
                return .attachment(name: name, mimeType: "")
            case .statusUpdate:
                // Ephemeral reasoning state; not shown on the phone.
                return nil
            }
        case .context:
            // Context is for the model, not for display.
            return nil
        }
    }

    // MARK: MessageDTO -> Message.Content (inbound)

    /// The phone only ever sends user text, so only those cases are accepted.
    static func messageContent(from content: MessageDTO.ContentDTO) -> Message.Content? {
        switch content {
        case .plainText(let text):
            return .plainText(text, context: nil)
        case .markdown(let text):
            return .markdown(text)
        default:
            return nil
        }
    }
}
