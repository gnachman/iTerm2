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

extension BrowserKeyValueStoreEntry: iTermDatabaseElement {
    enum Columns: String {
        case area
        case extensionId
        case key
        case value
        case size
    }

    static func schema() -> String {
        """
        create table if not exists BrowserKeyValueStore
            (\(Columns.area.rawValue) text,
             \(Columns.extensionId.rawValue) text,
             \(Columns.key.rawValue) text not null,
             \(Columns.value.rawValue) text not null,
             \(Columns.size.rawValue) Int);
        CREATE INDEX IF NOT EXISTS idx_browser_key_value_store_ext ON BrowserHistory
            (\(Columns.area.rawValue), 
             \(Columns.extensionId.rawValue), 
             \(Columns.key.rawValue));
        CREATE UNIQUE INDEX IF NOT EXISTS idx_bkv_area_ext_key ON BrowserKeyValueStore
            (\(Columns.area.rawValue),
             \(Columns.extensionId.rawValue),
             \(Columns.key.rawValue));
        """
    }

    static func migration(existingColumns: [String]) -> [Migration] {
        []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserKeyValueStore)"
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
            update BrowserKeyValueStore set
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
            insert into BrowserKeyValueStore
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
         delete from BrowserKeyValueStore where 
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

    static func getQuery(area: String?, extensionId: String?, keys: [String]) -> (String, [Any?]) {
        ("""
        select * from BrowserKeyValueStore where
            (\(Columns.area.rawValue) = ? AND
             \(Columns.extensionId.rawValue) = ? AND
             \(Columns.key.rawValue) in ?
        """,
        [area ?? NSNull(), extensionId ?? NSNull(), keys])
    }

    static func getQuery(area: String, extensionId: String) -> (String, [Any?]) {
        ("""
        select * from BrowserKeyValueStore where
            (\(Columns.area.rawValue) = ? AND
             \(Columns.extensionId.rawValue) = ?
        """,
        [area, extensionId])
    }

    static func removeQuery(area: String?, extensionId: String?, keys: [String]) -> (String, [Any?]) {
        ("""
         delete from BrowserKeyValueStore where 
             \(Columns.area.rawValue) = ? AND 
             \(Columns.extensionId.rawValue) = ? AND 
             \(Columns.key.rawValue) in ?
         returning \(Columns.key.rawValue), \(Columns.value.rawValue)
         """,
         [
            area ?? NSNull(),
            extensionId ?? NSNull(),
            keys
         ])
    }

    static func removeQuery(area: String?, extensionId: String?) -> (String, [Any?]) {
        ("""
         delete from BrowserKeyValueStore where 
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
         delete from BrowserKeyValueStore where 
             \(Columns.extensionId.rawValue) = ?
         """,
         [
            extensionId ?? NSNull()
         ])
    }

    static func upsertAndReturnOriginalQuery(area: String?, extensionId: String?, kvps: [String: String]) -> (String, [Any?]) {
        let insertQuestionMarks = Array(Array(repeating: "(?, ?, ?, ?, ?)", count: kvps.count)).joined(separator: "\n")
        let insertArgs: [Any?] = kvps.keys.flatMap { key -> [Any?] in
            let value = kvps[key]!
            return [area,
                    extensionId,
                    key,
                    value,
                    key.utf8.count + value.utf8.count]
        }
        var allArgs = [Any]()
        allArgs.append(area ?? NSNull())
        allArgs.append(extensionId ?? NSNull())
        allArgs.append(contentsOf: Array(kvps.keys))
        allArgs.append(contentsOf: insertArgs.compactMap { $0 ?? NSNull() })

        return ("""
        BEGIN TRANSACTION;

        CREATE TEMP TABLE original (
          area         TEXT,
          extensionId  TEXT,
          key          TEXT,
          old_value    TEXT
        );

        INSERT INTO original
        SELECT
          area,
          extensionId,
          key,
          value
        FROM
          BrowserKeyValueStore
        WHERE
          area = ? AND extensionId = ? and key in ?;

        INSERT INTO BrowserKeyValueStore (area, extensionId, key, value, size)
        VALUES
          \(insertQuestionMarks)
        ON CONFLICT(area, extensionId, key) DO UPDATE
        SET
          value = excluded.value,
          size  = excluded.size;

        SELECT
          key,
          old_value
        FROM
          original;

        DROP TABLE original;

        COMMIT;
        """,
         allArgs
        )
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
