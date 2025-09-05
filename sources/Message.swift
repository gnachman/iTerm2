//
//  Message.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

enum Participant: String, Codable, Hashable {
    case user
    case agent
}

struct ClientLocal: Codable {
    enum Action: Codable {
        case pickingSession
        case executingCommand(RemoteCommand)
        case notice(String)
        case streamingChanged(StreamingState)

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
}

struct Message: Codable {
    let chatID: String
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
        case remoteCommandRequest(RemoteCommand)
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
            case .remoteCommandRequest(let rc):
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
            case .remoteCommandRequest(let command): return command.markdownDescription
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
                }
            case .renameChat, .append, .appendAttachment, .commit, .setPermissions,
                    .vectorStoreCreated, .userCommand:
                return nil
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
                .appendAttachment, .multipart:
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
                .vectorStoreCreated, .userCommand:
            false
        }
    }

    // This is the snippet shown in the chat list.
    var snippetText: String? {
        return content.snippetText
    }

    mutating func removeStatusUpdates() {
        if case .multipart(var subparts, let vectorStoreID) = content {
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
                .vectorStoreCreated, .userCommand:
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
                .userCommand:
            it_fatalError()
        }
    }
}

extension Message: iTermDatabaseElement {
    enum Columns: String {
        case author
        case content
        case sentDate
        case uniqueID
        case chatID
        case responseID
    }

    static func schema() -> String {
        """
        create table if not exists Message
            (\(Columns.uniqueID.rawValue) text,
             \(Columns.author.rawValue) text not null,
             \(Columns.chatID.rawValue) text not null,
             \(Columns.content.rawValue) text not null,
             \(Columns.sentDate.rawValue) integer not null,
             \(Columns.responseID.rawValue) text)
        """
    }

    static func migrations(existingColumns: [String]) -> [Migration] {
        var result = [Migration]()
        if !existingColumns.contains(Columns.responseID.rawValue) {
            result.append(.init(query: "ALTER TABLE Message ADD COLUMN \(Columns.responseID.rawValue) text", args: []))
        }
        return result
    }


    static func fetchAllQuery() -> String {
        "select * from Message"
    }

    static func query(forChatID chatID: String) -> (String, [Any?]) {
        ("select * from Message where chatID=?", [chatID])
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(Message)"
    }

    func appendQuery() -> (String, [Any?]) {
        let jsonData = try! JSONEncoder().encode(content)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return (
            """
            insert into Message (
                \(Columns.uniqueID.rawValue),
                \(Columns.author.rawValue), 
                \(Columns.chatID.rawValue),
                \(Columns.content.rawValue), 
                \(Columns.sentDate.rawValue),
                \(Columns.responseID.rawValue))
            values (?, ?, ?, ?, ?, ?)
            """,
            [
                uniqueID.uuidString,
                author.rawValue,
                chatID,
                jsonString,
                sentDate.timeIntervalSince1970,
                responseID
            ]
        )
    }

    func removeQuery() -> (String, [Any?]) {
        ("DELETE from Message where \(Columns.uniqueID.rawValue) = ?",
         [uniqueID.uuidString])
    }

    func updateQuery() -> (String, [Any?]) {
        let jsonData = try! JSONEncoder().encode(content)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return (
            """
            update Message set \(Columns.author.rawValue) = ?,
                                \(Columns.chatID.rawValue) = ?,
                                \(Columns.content.rawValue) = ?,
                                \(Columns.sentDate.rawValue) = ?,
                                \(Columns.responseID.rawValue) = ?
            where \(Columns.uniqueID.rawValue) = ?
            """,
            [
                author.rawValue,
                chatID,
                jsonString,
                sentDate.timeIntervalSince1970,
                responseID,
                uniqueID.uuidString,
            ]
        )
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let uniqueIDStr = result.string(forColumn: Columns.uniqueID.rawValue),
              let uniqueID = UUID(uuidString: uniqueIDStr),
              let authorStr = result.string(forColumn: Columns.author.rawValue),
              let chatID = result.string(forColumn: Columns.chatID.rawValue),
              let author = Participant(rawValue: authorStr),
              let contentJSON = result.string(forColumn: Columns.content.rawValue),
              let contentData = contentJSON.data(using: .utf8),
              let content = try? JSONDecoder().decode(Content.self, from: contentData),
              let sentDate = result.date(forColumn: Columns.sentDate.rawValue)
        else {
            return nil
        }
        self.uniqueID = uniqueID
        self.author = author
        self.chatID = chatID
        self.content = content
        self.sentDate = sentDate
        self.responseID = result.string(forColumn: Columns.responseID.rawValue)
    }
}
