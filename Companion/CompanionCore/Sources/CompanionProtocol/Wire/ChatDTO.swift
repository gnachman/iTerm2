//
//  ChatDTO.swift
//  CompanionCore
//
//  Wire form of a chat for the companion protocol. Decoupled from the macOS
//  app's Chat type (which is SQLite-backed via iTermDatabaseElement): the mac
//  bridge maps its Chat to/from this DTO. Only the fields the phone needs to
//  render the chat list and open a conversation are carried.
//

import Foundation

public struct ChatDTO: Codable, Equatable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var creationDate: Date
    public var lastModifiedDate: Date

    /// True when the chat is an orchestrator chat (can see all sessions); false
    /// when it is bound to a single session.
    public var orchestrationEnabled: Bool

    /// For session-bound chats, the terminal session this chat talks to. Nil
    /// for orchestrator chats.
    public var terminalSessionGuid: String?

    /// Last message snippet for the chat-list row. Nil if the chat is empty.
    public var snippet: String?

    public init(id: String,
                title: String,
                creationDate: Date,
                lastModifiedDate: Date,
                orchestrationEnabled: Bool,
                terminalSessionGuid: String?,
                snippet: String?) {
        self.id = id
        self.title = title
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.orchestrationEnabled = orchestrationEnabled
        self.terminalSessionGuid = terminalSessionGuid
        self.snippet = snippet
    }
}
