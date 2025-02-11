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

struct Message: Codable {
    let chatID: String
    let author: Participant
    indirect enum Content: Codable {
        case plainText(String)
        case markdown(String)
        case explanationRequest(request: AIExplanationRequest)
        // The first value is empty for streaming responses and contains the entire value for
        // non-streaming responses.
        // For streaming resposnes, the update will be nonnull and gives the delta.
        // markdown is empty on the agent side. The client modifies the message to set markdown
        // as it sees fit.
        case explanationResponse(ExplanationResponse, ExplanationResponse.Update?, markdown: String)
        case remoteCommandRequest(RemoteCommand)
        case remoteCommandResponse(Result<String, AIError>, UUID, String)
        case selectSessionRequest(Message)  // carries the original message that needs a session
        case clientLocal(ClientLocal)
        case renameChat(String)
        case append(string: String, uuid: UUID)  // for streaming responses
        case commit(UUID)  // end of streaming response
        case setPermissions(Set<RemoteCommand.Content.PermissionCategory>)
        case terminalCommand(TerminalCommand)

        var shortDescription: String {
            let maxLength = 256
            switch self {
            case .plainText(let string), .markdown(let string):
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
            case .remoteCommandResponse(let result, _, let name):
                return "Response to remote command \(name): " + result.map(success: { $0.truncatedWithTrailingEllipsis(to: maxLength)},
                                                                           failure: { $0.localizedDescription.truncatedWithTrailingEllipsis(to: maxLength)})
            case .selectSessionRequest(let message):
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
            case .commit(let uuid):
                return "Commit \(uuid.uuidString)"
            case .setPermissions(let categories):
                return "Allow \(Array(categories).map { $0.rawValue }.joined(separator: " + "))"
            case .terminalCommand(let command):
                return "Terminal command \(command.command)"
            }
        }
    }
    var content: Content
    let sentDate: Date
    let uniqueID: UUID

    var shortDescription: String {
        return "<Message from \(author.rawValue), id \(uniqueID.uuidString): \(content.shortDescription)>"
    }

    // Not shown as separate messages in chat
    var hiddenFromClient: Bool {
        switch content {
        case .remoteCommandResponse, .renameChat, .commit, .setPermissions: true
        case .selectSessionRequest, .remoteCommandRequest, .plainText, .markdown, .explanationResponse, .explanationRequest, .clientLocal, .append,
                .terminalCommand: false
        }
    }

    // Client-local messages are ignored by the chat service
    var isClientLocal: Bool {
        switch content {
        case .clientLocal:
            true
        case .remoteCommandResponse, .selectSessionRequest, .remoteCommandRequest, .plainText,
                .markdown, .explanationResponse, .explanationRequest, .renameChat, .append,
                .commit, .setPermissions, .terminalCommand:
            false
        }
    }

    // This is the snippet shown in the chat list.
    var snippetText: String? {
        let maxLength = 40
        switch content {
        case .plainText(let text): return text.truncatedWithTrailingEllipsis(to: maxLength)
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
        case .renameChat, .append, .commit, .setPermissions: return nil
        case .remoteCommandResponse:
            return "Finished executing command"
        case .terminalCommand(let cmd):
            return "Ran `\(cmd.command.truncatedWithTrailingEllipsis(to: maxLength - 4))`"
        }
    }

    mutating func append(_ chunk: String) {
        switch content {
        case .plainText(let string):
            content = .plainText(string + chunk)
        case .markdown(let string):
            content = .markdown(string + chunk)
        case .explanationRequest, .explanationResponse, .remoteCommandRequest,
                .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .terminalCommand:
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
    }

    static func schema() -> String {
        """
        create table if not exists Message
            (\(Columns.uniqueID.rawValue) text,
             \(Columns.author.rawValue) text not null,
             \(Columns.chatID.rawValue) text not null,
             \(Columns.content.rawValue) text not null,
             \(Columns.sentDate.rawValue) integer not null)
        """
    }

    static func fetchAllQuery() -> String {
        "select * from Message"
    }

    static func query(forChatID chatID: String) -> (String, [Any]) {
        ("select * from Message where chatID=?", [chatID])
    }

    func appendQuery() -> (String, [Any]) {
        let jsonData = try! JSONEncoder().encode(content)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return (
            """
            insert into Message (
                \(Columns.uniqueID.rawValue),
                \(Columns.author.rawValue), 
                \(Columns.chatID.rawValue),
                \(Columns.content.rawValue), 
                \(Columns.sentDate.rawValue))
            values (?, ?, ?, ?, ?)
            """,
            [
                uniqueID.uuidString,
                author.rawValue,
                chatID,
                jsonString,
                sentDate.timeIntervalSince1970
            ]
        )
    }

    func removeQuery() -> (String, [Any]) {
        ("remove from Message where \(Columns.uniqueID.rawValue) = ?",
         [uniqueID.uuidString])
    }

    func updateQuery() -> (String, [Any]) {
        let jsonData = try! JSONEncoder().encode(content)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return (
            """
            update Message set \(Columns.author.rawValue) = ?,
                                \(Columns.chatID.rawValue) = ?,
                                \(Columns.content.rawValue) = ?,
                                \(Columns.sentDate.rawValue) = ?
            where \(Columns.uniqueID.rawValue) = ?
            """,
            [
                author.rawValue,
                chatID,
                jsonString,
                sentDate.timeIntervalSince1970,
                uniqueID.uuidString
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
    }
}
