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
        // A global, monotonic, delete-immune sequence the relay-push feature
        // uses as a watermark cursor. INTEGER PRIMARY KEY AUTOINCREMENT: SQLite
        // assigns it on every insert and (unlike bare rowid or a plain INTEGER
        // PRIMARY KEY) never reuses a value, even after the top row is deleted.
        // It is a DB-only column: not present on the shared Message struct and
        // not bound by appendQuery/updateQuery, so the engine owns it.
        case seq
    }

    static func schema() -> String {
        """
        create table if not exists Message
            (\(Columns.seq.rawValue) integer primary key autoincrement,
             \(Columns.uniqueID.rawValue) text,
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

    /// Newest-first window of a chat's rows with seq greater than `seq`, for the
    /// relay-push messagesSince responder. Over-fetches (windowLimit) because
    /// hiddenFromClient is a computed property and cannot be filtered in SQL;
    /// the responder drops hidden rows and keeps the newest visible ones.
    static func messagesSinceQuery(chatID: String, seq: Int64, windowLimit: Int) -> (String, [Any?]) {
        ("""
         select * from Message
         where \(Columns.chatID.rawValue)=? and \(Columns.seq.rawValue)>?
         order by \(Columns.seq.rawValue) desc limit ?
         """,
         [chatID, seq, windowLimit])
    }

    /// The chat's highest seq (0 if the chat has no rows). The watermark jumps
    /// to this tip so a backlog can't re-notify.
    static func maxSeqQuery(chatID: String) -> (String, [Any?]) {
        ("select max(\(Columns.seq.rawValue)) as maxseq from Message where \(Columns.chatID.rawValue)=?",
         [chatID])
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
