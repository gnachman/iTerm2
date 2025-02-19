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
        case explanationResponse(AIAnnotationCollection)
        case remoteCommandRequest(RemoteCommand)
        case remoteCommandResponse(Result<String, AIError>, UUID, String)
        case selectSessionRequest(Message)  // carries the original message that needs a session
        case clientLocal(ClientLocal)
        case renameChat(String)

        var shortDescription: String {
            switch self {
            case .plainText(let string), .markdown(let string):
                return string.truncatedWithTrailingEllipsis(to: 16)
            case .explanationRequest(request: let request):
                return "Explain \(request.originalString.string.truncatedWithTrailingEllipsis(to: 16))"
            case .explanationResponse(let response):
                return "Explanation: \(response.annotations.count) annotations: \(response.mainResponse?.truncatedWithTrailingEllipsis(to: 16) ?? "No main response")"
            case .remoteCommandRequest(let rc):
                return "Run remote command: \(rc.markdownDescription)"
            case .remoteCommandResponse(let result, _, let name):
                return "Response to remote command \(name): " + result.map(success: { $0.truncatedWithTrailingEllipsis(to: 16)},
                                                                           failure: { $0.localizedDescription.truncatedWithTrailingEllipsis(to: 16)})
            case .selectSessionRequest(let message):
                return "Select session: \(message)"
            case .clientLocal(let cl):
                switch cl.action {
                case .executingCommand(let rc):
                    return "Client-local: executing \(rc.markdownDescription)"
                case .pickingSession:
                    return "Client-local: picking session"
                }
            case .renameChat(let name):
                return "Rename chat to \(name)"
            }
        }
    }
    let content: Content
    let sentDate: Date
    let uniqueID: UUID

    var shortDescription: String {
        return "<Message from \(author.rawValue), id \(uniqueID.uuidString): \(content.shortDescription)>"
    }

    var visibleInClient: Bool {
        switch content {
        case .remoteCommandResponse, .renameChat: true
        case .selectSessionRequest, .remoteCommandRequest, .plainText, .markdown, .explanationResponse, .explanationRequest, .clientLocal: false
        }
    }

    // Client-local messages are ignored by the chat service
    var isClientLocal: Bool {
        switch content {
        case .clientLocal:
            true
        case .remoteCommandResponse, .selectSessionRequest, .remoteCommandRequest, .plainText,
                .markdown, .explanationResponse, .explanationRequest, .renameChat:
            false
        }
    }

    var snippetText: String? {
        let maxLength = 40
        switch content {
        case .plainText(let text): return text.truncatedWithTrailingEllipsis(to: maxLength)
        case .markdown(let text): return text.truncatedWithTrailingEllipsis(to: maxLength)
        case .explanationRequest(request: let request): return request.snippetText
        case .explanationResponse(let response):
            if let main = response.mainResponse {
                return main
            }
            if response.annotations.count > 1 {
                return "Added \(response.annotations.count) annotations"
            } else if response.annotations.count == 1{
                return "Added annotation"
            }
            return nil
        case .remoteCommandRequest(let command): return command.markdownDescription
        case .selectSessionRequest: return "Selecting session…"
        case .clientLocal(let cl):
            switch cl.action {
            case .executingCommand(let command): return command.markdownDescription
            case .pickingSession: return "Selecting session…"
            }
        case .renameChat: return nil
        case .remoteCommandResponse:
            return "Finished executing command"
        }
    }
}

extension Result: Codable where Success: Codable, Failure: Codable {
    enum CodingKeys: String, CodingKey {
        case success, failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.success) {
            let value = try container.decode(Success.self, forKey: .success)
            self = .success(value)
        } else if container.contains(.failure) {
            let error = try container.decode(Failure.self, forKey: .failure)
            self = .failure(error)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .success,
                in: container,
                debugDescription: "Expected either a success or failure key"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let value):
            try container.encode(value, forKey: .success)
        case .failure(let error):
            try container.encode(error, forKey: .failure)
        }
    }
}

extension Result {
    func map<T>(success: (Success) -> T, failure: (Failure) -> T) -> T {
        switch self {
        case .success(let s):
            return success(s)
        case .failure(let f):
            return failure(f)
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
