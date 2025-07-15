//
//  BrowserKeyValueStore.swift
//  iTerm2
//
//  Created by George Nachman on 7/11/25.
//

import Foundation

struct BrowserKeyValueStoreEntry {
    let area: String?
    let extensionId: String?
    let key: String
    var value: String
    var size: Int { key.utf8.count + value.utf8.count }
}

extension BrowserKeyValueStoreEntry: iTermDatabaseElement, iTermDatabaseResultSetInitializable {
    private static let table = "BrowserKeyValueStore"
    private var table: String { Self.table }

    enum Columns: String {
        case area
        case extensionId
        case key
        case value
        case size
    }

    static func schema() -> String {
        """
        create table if not exists \(table)
            (\(Columns.area.rawValue) text not null,
             \(Columns.extensionId.rawValue) text,
             \(Columns.key.rawValue) text not null,
             \(Columns.value.rawValue) text not null,
             \(Columns.size.rawValue) Int,
             PRIMARY KEY(area, extensionId, key));
        CREATE INDEX IF NOT EXISTS idx_browser_key_value_store_ext ON \(table)
            (\(Columns.area.rawValue), 
             \(Columns.extensionId.rawValue), 
             \(Columns.key.rawValue));
        CREATE UNIQUE INDEX IF NOT EXISTS idx_bkv_area_ext_key ON \(table)
            (\(Columns.area.rawValue),
             \(Columns.extensionId.rawValue),
             \(Columns.key.rawValue));
        """
    }

    static func migration(existingColumns: [String]) -> [Migration] {
        []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(\(table))"
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
            update \(table) set
                (\(Columns.area.rawValue) = ?,
                 \(Columns.extensionId.rawValue) = ?,
                 \(Columns.key.rawValue) = ?,
                 \(Columns.value.rawValue) = ?,
                 \(Columns.size.rawValue) = ?)
            where \(Columns.area) = ? AND \(Columns.extensionId) = ? AND \(Columns.key) = ?
            """,
         [
            area ?? NSNull(),
            extensionId ?? NSNull(),
            key,
            value,
            size,
            area ?? NSNull(),
            extensionId ?? NSNull(),
            key
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
            insert into \(table)
                (\(Columns.area.rawValue),
                 \(Columns.extensionId.rawValue),
                 \(Columns.key.rawValue),
                 \(Columns.value.rawValue),
                 \(Columns.size.rawValue))
            values (?, ?, ?, ?, ?)
            """,
         [
            area ?? NSNull(),
            extensionId ?? NSNull(),
            key,
            value,
            size
         ])
    }

    func removeQuery() -> (String, [Any?]) {
        ("""
         delete from \(table) where 
             \(Columns.area.rawValue) = ? AND 
             \(Columns.extensionId.rawValue) = ? AND 
             \(Columns.key.rawValue) = ?
         """,
         [
            area ?? NSNull(),
            extensionId ?? NSNull(),
            key
         ])
    }

    static func placeholders<T>(_ array: Array<T>) -> String {
        return "(" + Array(repeating: "?", count: array.count).joined(separator: ",") + ")"
    }

    static func placeholders(_ count: Int) -> String {
        return "(" + Array(repeating: "?", count: count).joined(separator: ",") + ")"
    }

    static func getQuery(area: String?, extensionId: String?, keys: [String]) -> (String, [Any?]) {
        ("""
        select * from \(table) where
            (\(Columns.area.rawValue) = ? AND
             \(Columns.extensionId.rawValue) = ? AND
             \(Columns.key.rawValue) in \(placeholders(keys)))
        """,
        [area ?? NSNull(), extensionId ?? NSNull()] + keys)
    }

    static func getQuery(area: String, extensionId: String) -> (String, [Any?]) {
        ("""
        select * from \(table) where
            (\(Columns.area.rawValue) = ? AND
             \(Columns.extensionId.rawValue) = ?)
        """,
        [area, extensionId])
    }

    static func removeQuery(area: String?, extensionId: String?, keys: [String]) -> (String, [Any?]) {
        ("""
         delete from \(table) where 
             \(Columns.area.rawValue) = ? AND 
             \(Columns.extensionId.rawValue) = ? AND 
             \(Columns.key.rawValue) in \(placeholders(keys))
         returning \(Columns.key.rawValue), \(Columns.value.rawValue)
         """,
         [
            area ?? NSNull(),
            extensionId ?? NSNull()
         ] + keys)
    }

    static func removeQuery(area: String?, extensionId: String?) -> (String, [Any?]) {
        ("""
         delete from \(table) where 
             \(Columns.area.rawValue) = ? AND 
             \(Columns.extensionId.rawValue) = ?
         returning \(Columns.key.rawValue), \(Columns.value.rawValue)
         """,
         [
            area ?? NSNull(),
            extensionId ?? NSNull()
         ])
    }

    static func removeQuery(extensionId: String?) -> (String, [Any?]) {
        ("""
         delete from \(table) where 
             \(Columns.extensionId.rawValue) = ?
         """,
         [
            extensionId ?? NSNull()
         ])
    }

    static func upsertAndReturnOriginalQuery(area: String?, extensionId: String?, kvps: [String: String]) -> [iTermParameterizedSQLStatement] {
        let keys = Array(kvps.keys)
        let insertPlaceholders = Array(repeating: placeholders(5),
                                       count: keys.count).joined(separator: ",\n  ")
        let insertArgs: [Any?] = kvps.keys.flatMap { key -> [Any?] in
            let value = kvps[key]!
            return [area,
                    extensionId,
                    key,
                    value,
                    key.utf8.count + value.utf8.count]
        }
        return [
            iTermParameterizedSQLStatement(
                sql: """
                    CREATE TEMP TABLE original (
                      area         TEXT,
                      extensionId  TEXT,
                      key          TEXT,
                      old_value    TEXT
                    );                   
                    """,
                args: []),
            iTermParameterizedSQLStatement(
                sql: """
                INSERT INTO original
                SELECT
                  area,
                  extensionId,
                  key,
                  value
                FROM
                  \(table)
                WHERE
                  area = ? AND extensionId = ? and key in \(placeholders(keys));
                """,
                args: [
                    area ?? NSNull(),
                    extensionId ?? NSNull()
                ] + keys),
            iTermParameterizedSQLStatement(
                sql: """
                INSERT INTO \(table) (area, extensionId, key, value, size)
                VALUES
                  \(insertPlaceholders)
                ON CONFLICT(area, extensionId, key) DO UPDATE
                SET
                  value = excluded.value,
                  size  = excluded.size;
                """,
                args: insertArgs.compactMap { $0 ?? NSNull() }),
            iTermParameterizedSQLStatement(
                sql: """
                    SELECT
                      key,
                      old_value as value
                    FROM
                      original;
                    """,
                args: [],
                isQuery: true),
            iTermParameterizedSQLStatement(
                sql: """
                    DROP TABLE original;
                    """,
                args: [])
        ]
    }

    static func usageQuery(area: String, extensionId: String) -> (String, [Any?]) {
        ("""
            select sum(size) as bytesUsed, count(*) as itemCount where
                \(Columns.area.rawValue) = ? AND
                \(Columns.extensionId.rawValue) = ?
        """,
        [ area,
          extensionId])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let key = result.string(forColumn: Columns.key.rawValue),
              let value = result.string(forColumn: Columns.value.rawValue)else {
            return nil
        }
        self.area = result.string(forColumn: Columns.area.rawValue)
        self.extensionId = result.string(forColumn: Columns.extensionId.rawValue)
        self.key = key
        self.value = value
    }
}
