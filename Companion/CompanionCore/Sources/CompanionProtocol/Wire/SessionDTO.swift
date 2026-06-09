//
//  SessionDTO.swift
//  CompanionCore
//
//  Wire form of a terminal session, used by the Create screen when the user
//  binds a new chat to a single session. The guid matches a macOS PTYSession
//  guid (Chat.terminalSessionGuid on the mac side).
//

import Foundation

public struct SessionDTO: Codable, Equatable, Identifiable, Hashable {
    public var guid: String
    /// The session name (typically the running command or the user-set name).
    public var name: String
    /// Secondary line for the picker: the tab or window title. May be empty.
    public var subtitle: String

    public var id: String { guid }

    public init(guid: String, name: String, subtitle: String) {
        self.guid = guid
        self.name = name
        self.subtitle = subtitle
    }
}
