//
//  Message+Database.swift
//  iTerm2
//
//  Mac-only persistence for Message (sqlite via iTermDatabaseElement). Split
//  from Message.swift, which is shared with the iOS companion app.
//

import Foundation

extension Message: iTermDatabaseElement {
    enum Columns: String {
        case author
        case content
        case sentDate
        case uniqueID
        case chatID
        case responseID
        case agentReasoning
    }

    static func schema() -> String {
        """
        create table if not exists Message
            (\(Columns.uniqueID.rawValue) text,
             \(Columns.author.rawValue) text not null,
             \(Columns.chatID.rawValue) text not null,
             \(Columns.content.rawValue) text not null,
             \(Columns.sentDate.rawValue) integer not null,
             \(Columns.responseID.rawValue) text,
             \(Columns.agentReasoning.rawValue) text)
        """
    }

    static func migrations(existingColumns: [String]) -> [Migration] {
        var result = [Migration]()
        if !existingColumns.contains(Columns.responseID.rawValue) {
            result.append(.init(query: "ALTER TABLE Message ADD COLUMN \(Columns.responseID.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.agentReasoning.rawValue) {
            result.append(.init(query: "ALTER TABLE Message ADD COLUMN \(Columns.agentReasoning.rawValue) text", args: []))
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
                \(Columns.responseID.rawValue),
                \(Columns.agentReasoning.rawValue))
            values (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                uniqueID.uuidString,
                author.rawValue,
                chatID,
                jsonString,
                sentDate.timeIntervalSince1970,
                responseID,
                agentReasoning
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
                                \(Columns.responseID.rawValue) = ?,
                                \(Columns.agentReasoning.rawValue) = ?
            where \(Columns.uniqueID.rawValue) = ?
            """,
            [
                author.rawValue,
                chatID,
                jsonString,
                sentDate.timeIntervalSince1970,
                responseID,
                agentReasoning,
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
        self.agentReasoning = result.string(forColumn: Columns.agentReasoning.rawValue)
    }
}
