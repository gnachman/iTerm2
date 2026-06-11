//
//  Message.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in a sibling file
//  (the database conformance lives in Message+Database.swift).
//

import Foundation

enum Participant: String, Codable, Hashable {
    case user
    case agent
}

// Carried by Message.Content.watcherEvent. Synthesized by iTerm2
// (currently: the orchestrator's watcher subsystem) and delivered
// into the chat as a user-side message so the agent can react. The
// structured payload lets both the chat UI and the agent's
// LLM-message translator render their own text without re-parsing a
// free-form string.
//
// Distinct from Message.Body.Attachment.AttachmentType.statusUpdate,
// which is an inline subpart carrying ephemeral DeepSeek reasoning
// text — unrelated concepts despite the prior naming collision.
struct StatusUpdate: Codable, Equatable {
    enum Reason: String, Codable {
        case stateReached     // a registered state-watcher fired
        case conditionMet     // a plain-English condition watcher fired
        case watcherDropped   // the watched session is gone (e.g. failed to restore)
        case watchTimedOut    // a screen-observation watcher gave up after its time cap
    }
    var watcherID: String
    var workgroupID: String
    var workgroupName: String
    var roleID: String
    var roleName: String
    var reason: Reason
    // Concrete state name for stateReached (e.g. "idle"). Empty for
    // the other reasons: conditionMet carries its condition in detail,
    // and for watcherDropped / watchTimedOut no state was reached.
    var stateReached: String
    var timestamp: Date
    // Free-form human-readable detail, used both as the chat-UI body
    // and as the inner text of the agent-side <status_update> tag.
    var detail: String
    // Whether iTerm2 already pushed a notification to the paired phone
    // for this event (the watcher was registered with notify_user).
    // true = sent; false = asked for but undeliverable; nil = not
    // requested. Drives the agent-side guidance so the model neither
    // double-notifies nor stays silent when it shouldn't.
    var pushed: Bool? = nil
}

struct ClientLocal: Codable {
    enum Action: Codable {
        case pickingSession
        case executingCommand(RemoteCommand)
        case notice(String)
        case streamingChanged(StreamingState)
        case offerLink(terminal: Bool, guid: String, name: String?)
        // Published when a new chat is created without a session to
        // link to (e.g. the user hit New Chat with no current
        // terminal, so the .offerLink bubble doesn't apply). Rendered
        // as a system-message bubble with a single Enable
        // Orchestration button; tapping it routes through the same
        // confirmation alert as the menu-driven toggle.
        case offerOrchestration
        case permissions(terminal: Bool, guid: String)
        // Inline workgroup-claim prompt published by the orchestrator
        // dispatcher. Rendered as a bubble with Approve / Deny
        // buttons. The user's choice comes back as a
        // UserCommand.workgroupPermissionResponse with the same
        // requestID. Carrying the workgroup name (resolved at publish
        // time) means the renderer doesn't need to look it up later
        // and the message still makes sense if the workgroup is
        // torn down before the user answers.
        case workgroupPermissionRequest(requestID: String,
                                      workgroupID: String,
                                      workgroupName: String,
                                      summary: String)

        // The agent has asked the user to switch this chat into
        // orchestration mode. Rendered as a system-message bubble
        // with an explanation of what orchestration grants and
        // Enable / Not Now buttons; the user's choice comes back as
        // UserCommand.enableOrchestrationResponse with the same
        // requestID. Published by the request_orchestration_enable
        // tool, registered only in session-bound mode.
        case enableOrchestrationRequest(requestID: String)

        enum StreamingState: String, Codable {
            case stopped
            case active
            case stoppedAutomatically
        }
    }
    var action: Action
}

enum UserCommand: Codable {
    case stop
    // Response to a ClientLocal.Action.workgroupPermissionRequest. Routed
    // through the broker so the orchestrator dispatcher (subscribed on
    // its chat's broker channel) can resume the parked tool-call
    // continuation. Goes through UserCommand rather than a fresh
    // Message.Content case so the chat service's existing
    // "skip-userCommand" filter keeps it from looping back to the LLM.
    case workgroupPermissionResponse(requestID: String, approved: Bool)
    // Response to a ClientLocal.Action.enableOrchestrationRequest.
    // ChatService routes it to the ChatAgent, which resumes the
    // parked tool-call continuation (the agent's
    // request_orchestration_enable tool) and, when approved, flips
    // the chat's orchestrationEnabled flag and transitions itself
    // in place to orchestration mode.
    case enableOrchestrationResponse(requestID: String, approved: Bool)
}

struct Message: Codable {
    var chatID: String
    let author: Participant

    enum Subpart: Codable {
        case plainText(String)
        case markdown(String)
        case attachment(LLM.Message.Attachment)
        // Extra info in user-sent messages to add to context
        case context(String)
    }

    indirect enum Content: Codable {
        case plainText(String, context: String?)
        case markdown(String)
        case explanationRequest(request: AIExplanationRequest)
        // The first value is empty for streaming responses and contains the entire value for
        // non-streaming responses.
        // For streaming resposnes, the update will be nonnull and gives the delta.
        // markdown is empty on the agent side. The client modifies the message to set markdown
        // as it sees fit.
        case explanationResponse(ExplanationResponse, ExplanationResponse.Update?, markdown: String)
        // Payload is generic over the stack that produced the call.
        // Session-bound mode publishes .classic(RemoteCommand); the
        // orchestrator publishes .external(ExternalRemoteCommand).
        // The wrapper carries the LLM message, tool name, and markdown
        // description in a stack-agnostic way; readers that need the
        // typed RemoteCommand reach for `payload.classic`.
        case remoteCommandRequest(RemoteCommandPayload, safe: Bool?)
        // Async watcher event from iTerm2 to the agent
        // (orchestration-only). Synthesized when a registered watcher
        // fires (or fails to re-arm on restart). Routed like a
        // user-author message so the chat service kicks off an agent
        // turn, but rendered distinctively in the chat UI
        // (system-message style) so the user can tell it didn't come
        // from them.
        case watcherEvent(StatusUpdate)
        // Output/Error, message unique ID, function name, function call ID (used by Responses API but not older APIs)
        case remoteCommandResponse(Result<String, AIError>, UUID, String, LLM.Message.FunctionCallID?)
        case selectSessionRequest(Message, terminal: Bool)  // carries the original message that needs a session
        case clientLocal(ClientLocal)
        case renameChat(String)
        case append(string: String, uuid: UUID)  // for streaming responses
        case appendAttachment(attachment: LLM.Message.Attachment, uuid: UUID)  // for streaming responses
        case commit(UUID)  // end of streaming response
        case userCommand(UserCommand)
        case setPermissions(Set<RemoteCommand.Content.PermissionCategory>)
        case vectorStoreCreated(id: String)
        case terminalCommand(TerminalCommand)

        // The vector store ID here gives the store to save files to. If not specified one will be
        // created.
        case multipart([Subpart], vectorStoreID: String?)

        func clone(_ uuidMap: [UUID: UUID], messages: [UUID: Message]) -> Content {
            switch self {
            case .plainText, .markdown, .explanationRequest, .remoteCommandRequest, .clientLocal,
                    .renameChat, .userCommand, .setPermissions, .vectorStoreCreated,
                    .terminalCommand, .multipart, .watcherEvent:
                return self
            case .explanationResponse(let response, var update, let markdown):
                if let updateID = update?.messageID, let replacement = uuidMap[updateID] {
                    update?.messageID = replacement
                }
                return .explanationResponse(response, update, markdown: markdown)
            case .remoteCommandResponse(let result, let uuid, let functionName, let functionCallID):
                return .remoteCommandResponse(result, uuidMap[uuid] ?? uuid, functionName, functionCallID)
            case .selectSessionRequest(let originalMessage, terminal: let terminal):
                let message: Message
                if let newID = uuidMap[originalMessage.uniqueID] {
                    message = messages[newID] ?? originalMessage
                } else {
                    message = originalMessage
                }
                return .selectSessionRequest(message, terminal: terminal)
            case .append(string: let string, uuid: let uuid):
                return .append(string: string, uuid: uuidMap[uuid] ?? uuid)
            case .appendAttachment(attachment: let attachment, uuid: let uuid):
                return .appendAttachment(attachment: attachment, uuid: uuidMap[uuid] ?? uuid)
            case .commit(let uuid):
                return .commit(uuidMap[uuid] ?? uuid)
            }
        }

        var isSetPermissions: Bool {
            switch self {
            case .setPermissions: true
            default: false
            }
        }

        var shortDescription: String {
            let maxLength = 256
            switch self {
            case .plainText(let string, _), .markdown(let string):
                return string.truncatedWithTrailingEllipsis(to: maxLength)
            case .explanationRequest(request: let request):
                return "Explain \(request.originalString.string.truncatedWithTrailingEllipsis(to: maxLength))"
            case .explanationResponse(let response, let update, _):
                if let update {
                    return "Explanation (streaming): \(update.annotations.count) annotations: \(update.mainResponse?.truncatedWithTrailingEllipsis(to: maxLength) ?? "No main response")"
                } else {
                    return "Explanation: \(response.annotations.count) annotations: \(response.mainResponse?.truncatedWithTrailingEllipsis(to: maxLength) ?? "No main response")"
                }
            case .remoteCommandRequest(let rc, safe: _):
                return "Run remote command: \(rc.markdownDescription)"
            case .remoteCommandResponse(let result, _, let name, _):
                return "Response to remote command \(name): " + result.map(success: { $0.truncatedWithTrailingEllipsis(to: maxLength)},
                                                                           failure: { $0.localizedDescription.truncatedWithTrailingEllipsis(to: maxLength)})
            case .selectSessionRequest(let message, _):
                return "Select session: \(message)"
            case .clientLocal(let cl):
                switch cl.action {
                case .executingCommand(let rc):
                    return "Client-local: executing \(rc.markdownDescription)"
                case .pickingSession:
                    return "Client-local: picking session"
                case .notice(let string):
                    return "Client-local: notice=\(string)"
                case .streamingChanged(let state):
                    return "Client-local: streaming=\(state.rawValue)"
                case let .offerLink(terminal: terminal, guid: guid, name: name):
                    return "Client-local: offerLink terminal=\(terminal) guid=\(guid) name=\(name.d)"
                case .offerOrchestration:
                    return "Client-local: offerOrchestration"
                case let .permissions(terminal: terminal, guid: guid):
                    return "Client-local: permissions terminal=\(terminal) guid=\(guid)"
                case let .workgroupPermissionRequest(requestID, workgroupID, workgroupName, _):
                    return "Client-local: workgroup permission request \(requestID) workgroup=\(workgroupName) (\(workgroupID))"
                case .enableOrchestrationRequest(let requestID):
                    return "Client-local: enable orchestration request \(requestID)"
                }
            case .renameChat(let name):
                return "Rename chat to \(name)"
            case let .append(string: chunk, uuid: uuid):
                return "Append \(chunk) to \(uuid.uuidString)"
            case let .appendAttachment(attachment: attachment, uuid: uuid):
                return "Append attachment \(attachment) to \(uuid.uuidString)"
            case .commit(let uuid):
                return "Commit \(uuid.uuidString)"
            case .setPermissions(let categories):
                return "Allow \(Array(categories).map { $0.rawValue }.joined(separator: " + "))"
            case .vectorStoreCreated(id: let id):
                return "Client-local: vector store created with id \(id)"
            case .terminalCommand(let command):
                return "Terminal command \(command.command)"
            case .multipart:
                return "Multipart message"
            case .userCommand(let command):
                return "User command \(command)"
            case .watcherEvent(let update):
                return "Watcher event (\(update.reason.rawValue)): \(update.detail.truncatedWithTrailingEllipsis(to: maxLength))"
            }
        }

        var snippetText: String? {
            let maxLength = 40
            switch self {
            case .plainText(let text, _): return text.truncatedWithTrailingEllipsis(to: maxLength)
            case .markdown(let text): return text.truncatedWithTrailingEllipsis(to: maxLength)
            case .explanationRequest(request: let request): return request.snippetText
            case .explanationResponse(_, _, let markdown):
                return markdown.truncatedWithTrailingEllipsis(to: maxLength)
            case .remoteCommandRequest(let command, safe: _): return command.markdownDescription
            case .selectSessionRequest: return "Selecting session…"
            case .clientLocal(let cl):
                switch cl.action {
                case .executingCommand(let command): return command.markdownDescription
                case .pickingSession: return "Selecting session…"
                case .notice(let message): return message
                case .streamingChanged(let state):
                    return switch state {
                    case .stopped, .stoppedAutomatically:
                        "Stopped sending commands to AI"
                    case .active:
                        "Sending commands to AI automatically"
                    }
                case .offerLink, .offerOrchestration, .permissions, .workgroupPermissionRequest,
                        .enableOrchestrationRequest:
                    return nil
                }
            case .renameChat, .append, .appendAttachment, .commit, .setPermissions,
                    .vectorStoreCreated, .userCommand:
                return nil
            case .watcherEvent(let update):
                return update.detail.truncatedWithTrailingEllipsis(to: maxLength)
            case .remoteCommandResponse:
                return "Finished executing command"
            case .terminalCommand(let cmd):
                return "Ran `\(cmd.command.truncatedWithTrailingEllipsis(to: maxLength - 4))`"
            case .multipart(let subparts, _):
                for subpart in subparts.reversed() {
                    switch subpart {
                    case .plainText(let text), .markdown(let text):
                        return text.truncatedWithTrailingEllipsis(to: maxLength)
                    case .attachment(let attachment):
                        switch attachment.type {
                        case .code(let text):
                            return text.truncatedWithTrailingEllipsis(to: maxLength)
                        case .statusUpdate(let statusUpdate):
                            return statusUpdate.displayString
                        case .file(let file):
                            return "📄 " + file.name
                        case .fileID(_, let name):
                            return "📄 " + name
                        }
                    case .context(_):
                        break
                    }
                }
                return "Empty message"
            }
        }
    }
    var content: Content
    let sentDate: Date
    var uniqueID: UUID
    var inResponseTo: String?  // This is a responseID, not a uniqueID. Not all AI providers support response IDs.
    var responseID: String?
    // Opaque vendor-required thinking-mode state captured on agent messages.
    // Currently populated for DeepSeek v4 (its API requires this be echoed
    // back on every subsequent turn or it returns 400). Stored alongside
    // content rather than as a subpart because its lifetime, visibility, and
    // wire treatment are all distinct from the displayed body: never rendered
    // directly (the reasoning text is shown ephemerally via
    // .statusUpdate(.reasoningSummaryUpdate) subparts that get stripped at
    // persist time), but always round-tripped on resend.
    // Forward+backward Codable compatible: an old build decoding this field
    // ignores it (JSONDecoder ignores unknown keys); a new build decoding old
    // history gets nil and behaves as before.
    var agentReasoning: String?

    // This is only present in user-sent messages.
    struct Configuration: Codable {
        var hostedWebSearchEnabled = false
        // Vector stores to search.
        var vectorStoreIDs: [String]
        var model: String?
        var shouldThink: Bool
    }
    var configuration: Configuration?

    var shortDescription: String {
        return "<Message from \(author.rawValue), id \(uniqueID.uuidString): \(content.shortDescription)>"
    }

    // Not shown as separate messages in chat
    var hiddenFromClient: Bool {
        switch content {
        case .remoteCommandResponse, .renameChat, .commit, .setPermissions, .vectorStoreCreated, .userCommand:
            true
        case .selectSessionRequest, .remoteCommandRequest, .plainText, .markdown,
                .explanationResponse, .explanationRequest, .clientLocal, .append, .terminalCommand,
                .appendAttachment, .multipart, .watcherEvent:
            false
        }
    }

    // Client-local messages are ignored by the chat service
    var isClientLocal: Bool {
        switch content {
        case .clientLocal:
            true
        case .remoteCommandResponse, .selectSessionRequest, .remoteCommandRequest, .plainText,
                .markdown, .explanationResponse, .explanationRequest, .renameChat, .append,
                .commit, .setPermissions, .terminalCommand, .appendAttachment, .multipart,
                .vectorStoreCreated, .userCommand, .watcherEvent:
            false
        }
    }

    // This is the snippet shown in the chat list.
    var snippetText: String? {
        return content.snippetText
    }

    // Strip the AttachmentType.statusUpdate subparts (DeepSeek
    // reasoning summary updates) from a multipart message,
    // distilling any reasoning text into agentReasoning first.
    //
    // Unrelated to Message.Content.watcherEvent — that's a separate
    // top-level message type, not an attachment subpart, and is
    // persisted as its own row.
    mutating func removeReasoningStatusSubparts() {
        if case .multipart(var subparts, let vectorStoreID) = content {
            // Distill reasoning-summary status updates into
            // agentReasoning before stripping them. The status-update
            // path is ephemeral display state and gets removed at
            // persist time; agentReasoning is durable and required by
            // DeepSeek's API on every subsequent turn. Without this
            // distillation step, streaming reasoning would vanish the
            // first time a follow-up text chunk arrives (because the
            // chat list model calls this before appending each chunk).
            var harvestedReasoning = ""
            for subpart in subparts {
                guard case .attachment(let attachment) = subpart,
                      case .statusUpdate(let update) = attachment.type else { continue }
                for piece in update.exploded {
                    if case .reasoningSummaryUpdate(let text) = piece {
                        harvestedReasoning.append(text)
                    }
                }
            }
            if !harvestedReasoning.isEmpty {
                agentReasoning = (agentReasoning ?? "") + harvestedReasoning
            }
            subparts.removeAll { subpart in
                switch subpart {
                case .attachment(let attachment):
                    if case .statusUpdate = attachment.type {
                        return true
                    }
                    return false
                case .plainText, .markdown, .context:
                    return false
                }
            }
            content = .multipart(subparts, vectorStoreID: vectorStoreID)
        }
    }

    mutating func append(_ attachment: LLM.Message.Attachment, vectorStoreID: String?) {
        switch content {
        case .plainText(let string, _):
            content = .multipart([.plainText(string),
                                  .attachment(attachment)],
                                 vectorStoreID: vectorStoreID)
        case .markdown(let string):
            content = .multipart([.markdown(string),
                                  .attachment(attachment)],
                                 vectorStoreID: vectorStoreID)
        case .multipart(var subparts, let vectorStoreID):
            if let lastPart = subparts.last,
               case let .attachment(existingAttachment) = lastPart,
               let combined = existingAttachment.appending(attachment) {
                subparts[subparts.count - 1] = .attachment(combined)
                content = .multipart(subparts, vectorStoreID: vectorStoreID)
            } else {
                content = .multipart(subparts + [.attachment(attachment)], vectorStoreID: vectorStoreID)
            }
            // TODO: Handle attachments in some of these like explanationResponse
        case .explanationRequest, .explanationResponse, .remoteCommandRequest,
                .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat,
                .append, .appendAttachment, .commit, .setPermissions, .terminalCommand,
                .vectorStoreCreated, .userCommand, .watcherEvent:
            it_fatalError()
        }
    }

    mutating func append(_ chunk: String, useMarkdownIfAmbiguous: Bool) {
        switch content {
        case .plainText(let string, _):
            content = .plainText(string + chunk, context: nil)
        case .markdown(let string):
            content = .markdown(string + chunk)
        case .multipart(let subparts, vectorStoreID: let vectorStoreID):
            if let lastSubpart = subparts.last {
                switch lastSubpart {
                case .markdown(let existingMarkdown):
                    content = .multipart(subparts.dropLast() +
                                         [.markdown(existingMarkdown + chunk)],
                                         vectorStoreID: vectorStoreID)
                    return
                case .plainText(let existingPlainText):
                    content = .multipart(subparts.dropLast() +
                                         [.plainText(existingPlainText + chunk)],
                                         vectorStoreID: vectorStoreID)
                    return
                case .attachment, .context:
                    break
                }
            }
            if useMarkdownIfAmbiguous {
                content = .multipart(subparts + [.markdown(chunk)],
                                     vectorStoreID: vectorStoreID)
            } else {
                content = .multipart(subparts + [.plainText(chunk)],
                                     vectorStoreID: vectorStoreID)
            }
        case .explanationRequest, .explanationResponse, .remoteCommandRequest,
                .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .terminalCommand, .appendAttachment, .vectorStoreCreated,
                .userCommand, .watcherEvent:
            it_fatalError()
        }
    }

    func clone(_ uuidMap: inout [UUID: UUID], messages: [UUID: Message]) -> Message {
        var copy = self
        copy.uniqueID = UUID()
        uuidMap[uniqueID] = copy.uniqueID
        copy.content = content.clone(uuidMap, messages: messages)
        return copy
    }
}
