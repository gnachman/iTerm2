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

struct Message: Codable {
    let participant: Participant
    enum Content: Codable {
        case plainText(String)
        case markdown(String)
        case explanationRequest(request: AIExplanationRequest)
        case explanationResponse(AIAnnotationCollection)
        case remoteCommandRequest(RemoteCommand)
        case remoteCommandResponse(Result<String, AIError>, UUID)
    }
    let content: Content
    let date: Date
    let uniqueID: UUID
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
