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
    let participant: Participant
    indirect enum Content: Codable {
        case plainText(String)
        case markdown(String)
        case explanationRequest(request: AIExplanationRequest)
        case explanationResponse(AIAnnotationCollection)
        case remoteCommandRequest(RemoteCommand)
        case remoteCommandResponse(Result<String, AIError>, UUID)
        case selectSessionRequest(Message)  // carries the original message that needs a session
        case clientLocal(ClientLocal)

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
            case .remoteCommandResponse(let result, _):
                return "Response to remote command: " + result.map(success: { $0.truncatedWithTrailingEllipsis(to: 16)},
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
            }
        }
    }
    let content: Content
    let date: Date
    let uniqueID: UUID

    var shortDescription: String {
        return "<Message from \(participant.rawValue), id \(uniqueID.uuidString): \(content.shortDescription)>"
    }
    // Transient messages are not saved in the chatlist model on the client.
    var isTransient: Bool {
        switch content {
        case .remoteCommandResponse: true
        case .selectSessionRequest, .remoteCommandRequest, .plainText, .markdown, .explanationResponse, .explanationRequest, .clientLocal: false
        }
    }

    // Client-local messages are ignored by the chat service
    var isClientLocal: Bool {
        switch content {
        case .clientLocal:
            true
        case .remoteCommandResponse, .selectSessionRequest, .remoteCommandRequest, .plainText,
                .markdown, .explanationResponse, .explanationRequest:
            false
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
