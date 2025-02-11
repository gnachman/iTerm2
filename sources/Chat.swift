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
    var sessionGuid: String?
    var permissions: String
}

extension Chat: iTermDatabaseElement {
    enum Columns: String {
        case uuid
        case title
        case creationDate
        case lastModifiedDate
        case sessionGuid
        case permissions
    }
    static func schema() -> String {
        """
        create table if not exists Chat
            (\(Columns.uuid.rawValue) text,
             \(Columns.title.rawValue) text not null,
             \(Columns.creationDate.rawValue) integer not null,
             \(Columns.lastModifiedDate.rawValue) integer not null,
             \(Columns.sessionGuid.rawValue) text,
             \(Columns.permissions.rawValue) text)
        """
    }

    static func fetchAllQuery() -> String {
        "select * from Chat order by \(Columns.lastModifiedDate) DESC"
    }

    func removeQuery() -> (String, [Any]) {
        ("delete from Chat where \(Columns.uuid.rawValue) = ?", [id])
    }

    func appendQuery() -> (String, [Any]) {
        ("""
        insert into Chat 
            (\(Columns.uuid.rawValue),
             \(Columns.title.rawValue), 
             \(Columns.creationDate.rawValue), 
             \(Columns.lastModifiedDate.rawValue), 
             \(Columns.sessionGuid.rawValue),
             \(Columns.permissions.rawValue))
        values (?, ?, ?, ?, ?, ?)
        """,
         [
            id,
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            sessionGuid ?? NSNull(),
            permissions
         ])
    }

    func updateQuery() -> (String, [Any]) {
        ("""
        update Chat set \(Columns.title.rawValue) = ?,
                        \(Columns.creationDate.rawValue) = ?,
                        \(Columns.lastModifiedDate.rawValue) = ?,
                        \(Columns.sessionGuid.rawValue) = ?,
                        \(Columns.permissions.rawValue) = ?
        where \(Columns.uuid.rawValue) = ?
        """,
        [
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            sessionGuid ?? NSNull(),
            permissions,

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
        self.sessionGuid = result.string(forColumn: Columns.sessionGuid.rawValue)
        self.permissions = result.string(forColumn: Columns.permissions.rawValue) ?? ""
    }
}

