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
    }
    let content: Content
    let date: Date
    let uniqueID: UUID
}

