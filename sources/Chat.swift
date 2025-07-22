//
//  Chat.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

struct Chat {
    var id = UUID().uuidString
    var title: String
    var creationDate = Date()
    var lastModifiedDate = Date()
    var terminalSessionGuid: String?
    var browserSessionGuid: String?
    var permissions: String
    var vectorStore: String?
}

extension Chat: iTermDatabaseElement {
    enum Columns: String {
        case uuid
        case title
        case creationDate
        case lastModifiedDate
        case terminalSessionGuid = "sessionGuid"
        case browserSessionGuid
        case permissions
        case vectorStore
    }
    static func schema() -> String {
        """
        create table if not exists Chat
            (\(Columns.uuid.rawValue) text,
             \(Columns.title.rawValue) text not null,
             \(Columns.creationDate.rawValue) integer not null,
             \(Columns.lastModifiedDate.rawValue) integer not null,
             \(Columns.terminalSessionGuid.rawValue) text,
             \(Columns.browserSessionGuid.rawValue) text,
             \(Columns.permissions.rawValue) text,
             \(Columns.vectorStore.rawValue) text)
        """
    }
    static func migrations(existingColumns: [String]) -> [Migration] {
        var result = [Migration]()
        if !existingColumns.contains(Columns.vectorStore.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.vectorStore.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.browserSessionGuid.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.browserSessionGuid.rawValue) text", args: []))
        }
        return result
    }

    static func fetchAllQuery() -> String {
        "select * from Chat order by \(Columns.lastModifiedDate) DESC"
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(Chat)"
    }
    
    func removeQuery() -> (String, [Any?]) {
        ("delete from Chat where \(Columns.uuid.rawValue) = ?", [id])
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
        insert into Chat 
            (\(Columns.uuid.rawValue),
             \(Columns.title.rawValue), 
             \(Columns.creationDate.rawValue), 
             \(Columns.lastModifiedDate.rawValue), 
             \(Columns.terminalSessionGuid.rawValue),
             \(Columns.browserSessionGuid.rawValue),
             \(Columns.permissions.rawValue),
             \(Columns.vectorStore.rawValue))
        values (?, ?, ?, ?, ?, ?, ?, ?)
        """,
         [
            id,
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            terminalSessionGuid ?? NSNull(),
            browserSessionGuid ?? NSNull(),
            permissions,
            vectorStore ?? NSNull()
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
        update Chat set \(Columns.title.rawValue) = ?,
                        \(Columns.creationDate.rawValue) = ?,
                        \(Columns.lastModifiedDate.rawValue) = ?,
                        \(Columns.terminalSessionGuid.rawValue) = ?,
                        \(Columns.browserSessionGuid.rawValue) = ?,
                        \(Columns.permissions.rawValue) = ?,
                        \(Columns.vectorStore.rawValue) = ?
        where \(Columns.uuid.rawValue) = ?
        """,
        [
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            terminalSessionGuid ?? NSNull(),
            browserSessionGuid ?? NSNull(),
            permissions,
            vectorStore ?? NSNull(),

            // where clause
            id
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let id = result.string(forColumn: Columns.uuid.rawValue),
              let title = result.string(forColumn: Columns.title.rawValue),
              let creationDate = result.date(forColumn: Columns.creationDate.rawValue),
              let lastModifiedDate = result.date(forColumn: Columns.lastModifiedDate.rawValue)
        else {
            return nil
        }
        self.id = id
        self.title = title
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.terminalSessionGuid = result.string(forColumn: Columns.terminalSessionGuid.rawValue)
        self.browserSessionGuid = result.string(forColumn: Columns.browserSessionGuid.rawValue)
        self.permissions = result.string(forColumn: Columns.permissions.rawValue) ?? ""
        self.vectorStore = result.string(forColumn: Columns.vectorStore.rawValue)
    }
}

