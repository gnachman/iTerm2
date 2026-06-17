//
//  Chat+Database.swift
//  iTerm2
//
//  Mac-only persistence for Chat (sqlite via iTermDatabaseElement). Split from
//  Chat.swift, which is shared with the iOS companion app.
//

import Foundation

extension Chat: iTermDatabaseElement {
    enum Columns: String {
        case uuid
        case title
        case creationDate
        case lastModifiedDate
        case orchestrationEnabled
        case terminalSessionGuid = "sessionGuid"
        case browserSessionGuid
        case permissions
        case vectorStore
        case claimedScopes
        case watchers
        case icon
    }
    static func schema() -> String {
        """
        create table if not exists Chat
            (\(Columns.uuid.rawValue) text,
             \(Columns.title.rawValue) text not null,
             \(Columns.creationDate.rawValue) integer not null,
             \(Columns.lastModifiedDate.rawValue) integer not null,
             \(Columns.orchestrationEnabled.rawValue) integer DEFAULT 0,
             \(Columns.terminalSessionGuid.rawValue) text,
             \(Columns.browserSessionGuid.rawValue) text,
             \(Columns.permissions.rawValue) text,
             \(Columns.vectorStore.rawValue) text,
             \(Columns.claimedScopes.rawValue) text,
             \(Columns.watchers.rawValue) text,
             \(Columns.icon.rawValue) blob)
        """
    }
    static func migrations(existingColumns: [String]) -> [Migration] {
        var result = [Migration]()
        if !existingColumns.contains(Columns.vectorStore.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.vectorStore.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.terminalSessionGuid.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.terminalSessionGuid.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.browserSessionGuid.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.browserSessionGuid.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.claimedScopes.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.claimedScopes.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.watchers.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.watchers.rawValue) text", args: []))
        }
        if !existingColumns.contains(Columns.icon.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.icon.rawValue) blob", args: []))
        }
        if !existingColumns.contains(Columns.orchestrationEnabled.rawValue) {
            result.append(.init(query: "ALTER TABLE Chat ADD COLUMN \(Columns.orchestrationEnabled.rawValue) integer DEFAULT 0", args: []))
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
             \(Columns.orchestrationEnabled.rawValue),
             \(Columns.terminalSessionGuid.rawValue),
             \(Columns.browserSessionGuid.rawValue),
             \(Columns.permissions.rawValue),
             \(Columns.vectorStore.rawValue),
             \(Columns.claimedScopes.rawValue),
             \(Columns.watchers.rawValue),
             \(Columns.icon.rawValue))
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
         [
            id,
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            orchestrationEnabled ? 1 : 0,
            terminalSessionGuid ?? NSNull(),
            browserSessionGuid ?? NSNull(),
            permissions,
            vectorStore ?? NSNull(),
            Self.encodeIDList(claimedScopes),
            Self.encodeWatchers(watchers),
            icon ?? NSNull(),
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
        update Chat set \(Columns.title.rawValue) = ?,
                        \(Columns.creationDate.rawValue) = ?,
                        \(Columns.lastModifiedDate.rawValue) = ?,
                        \(Columns.orchestrationEnabled.rawValue) = ?,
                        \(Columns.terminalSessionGuid.rawValue) = ?,
                        \(Columns.browserSessionGuid.rawValue) = ?,
                        \(Columns.permissions.rawValue) = ?,
                        \(Columns.vectorStore.rawValue) = ?,
                        \(Columns.claimedScopes.rawValue) = ?,
                        \(Columns.watchers.rawValue) = ?,
                        \(Columns.icon.rawValue) = ?
        where \(Columns.uuid.rawValue) = ?
        """,
        [
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            orchestrationEnabled ? 1 : 0,
            terminalSessionGuid ?? NSNull(),
            browserSessionGuid ?? NSNull(),
            permissions,
            vectorStore ?? NSNull(),
            Self.encodeIDList(claimedScopes),
            Self.encodeWatchers(watchers),
            icon ?? NSNull(),

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
        self.orchestrationEnabled =
            result.longLongInt(forColumn: Columns.orchestrationEnabled.rawValue) != 0
        self.terminalSessionGuid = result.string(forColumn: Columns.terminalSessionGuid.rawValue)
        self.browserSessionGuid = result.string(forColumn: Columns.browserSessionGuid.rawValue)
        self.permissions = result.string(forColumn: Columns.permissions.rawValue) ?? ""
        self.vectorStore = result.string(forColumn: Columns.vectorStore.rawValue)
        self.claimedScopes = Self.decodeIDList(
            result.string(forColumn: Columns.claimedScopes.rawValue))
        self.watchers = Self.decodeWatchers(
            result.string(forColumn: Columns.watchers.rawValue))
        self.icon = result.data(forColumn: Columns.icon.rawValue)
    }

    // Workgroup IDs don't contain newlines (they're stable identifiers,
    // not user-supplied strings), so newline-join is a safe encoding
    // without escaping. it_assert pins the invariant in case a future
    // code path ever swaps in a user-controlled string by mistake;
    // without it, an embedded \n would silently split one ID into two
    // on the next read.
    private static func encodeIDList(_ ids: [String]) -> String {
        for id in ids {
            it_assert(!id.contains("\n"),
                      "Chat.encodeIDList: id contains newline; the newline-separated encoding would split it on read.")
        }
        return ids.joined(separator: "\n")
    }

    private static func decodeIDList(_ encoded: String?) -> [String] {
        guard let encoded, !encoded.isEmpty else { return [] }
        return encoded.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private static func encodeWatchers(_ watchers: [WorkgroupWatcher]) -> String {
        if watchers.isEmpty { return "" }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            let data = try encoder.encode(watchers)
            guard let str = String(data: data, encoding: .utf8) else {
                DLog("encodeWatchers: utf8 decode of JSON bytes failed")
                return ""
            }
            return str
        } catch {
            // Silent return-"" here is silent data loss: persisted
            // watchers would vanish on next encode round-trip. Log so
            // future schema changes don't disappear watchers without
            // any user-visible diagnostic.
            DLog("encodeWatchers failed: \(error)")
            return ""
        }
    }

    private static func decodeWatchers(_ encoded: String?) -> [WorkgroupWatcher] {
        guard let encoded, !encoded.isEmpty,
              let data = encoded.data(using: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode([WorkgroupWatcher].self, from: data)
        } catch {
            DLog("decodeWatchers failed (\(encoded.count) bytes): \(error)")
            return []
        }
    }
}
