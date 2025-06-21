//
//  BookmarkTags.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

import Foundation

struct BrowserBookmarkTags {
    var bookmarkRowId: Int64
    var tag: String
    
    init(bookmarkRowId: Int64, tag: String) {
        self.bookmarkRowId = bookmarkRowId
        self.tag = tag
    }
}

extension BrowserBookmarkTags: iTermDatabaseElement {
    enum Columns: String {
        case bookmarkRowId
        case tag
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserBookmarkTags
            (\(Columns.bookmarkRowId.rawValue) integer not null,
             \(Columns.tag.rawValue) text not null,
             PRIMARY KEY (\(Columns.bookmarkRowId.rawValue), \(Columns.tag.rawValue)),
             FOREIGN KEY (\(Columns.bookmarkRowId.rawValue)) REFERENCES BrowserBookmarks(rowid) ON DELETE CASCADE);
        
        CREATE INDEX IF NOT EXISTS idx_browser_bookmark_tags_rowid ON BrowserBookmarkTags(\(Columns.bookmarkRowId.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_bookmark_tags_tag ON BrowserBookmarkTags(\(Columns.tag.rawValue));
        """
    }
    
    static func migrations(existingColumns: [String]) -> [Migration] {
        // Future migrations can be added here
        return []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserBookmarkTags)"
    }
    
    func removeQuery() -> (String, [Any]) {
        ("delete from BrowserBookmarkTags where \(Columns.bookmarkRowId.rawValue) = ? AND \(Columns.tag.rawValue) = ?", [bookmarkRowId, tag])
    }

    func appendQuery() -> (String, [Any]) {
        ("""
        insert into BrowserBookmarkTags 
            (\(Columns.bookmarkRowId.rawValue),
             \(Columns.tag.rawValue))
        values (?, ?)
        """,
         [bookmarkRowId, tag])
    }

    func updateQuery() -> (String, [Any]) {
        // Tags don't need updating - they're either added or removed
        return removeQuery()
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let tag = result.string(forColumn: Columns.tag.rawValue) else {
            return nil
        }
        
        self.bookmarkRowId = result.longLongInt(forColumn: Columns.bookmarkRowId.rawValue)
        self.tag = tag
    }
}

// MARK: - Tag management functionality

extension BrowserBookmarkTags {
    static func getTagsForBookmarkQuery(bookmarkRowId: Int64) -> (String, [Any]) {
        let query = """
        SELECT * FROM BrowserBookmarkTags 
        WHERE \(Columns.bookmarkRowId.rawValue) = ?
        ORDER BY \(Columns.tag.rawValue) ASC
        """
        return (query, [bookmarkRowId])
    }
    
    static func getAllTagsQuery() -> (String, [Any]) {
        let query = """
        SELECT DISTINCT \(Columns.tag.rawValue) FROM BrowserBookmarkTags 
        ORDER BY \(Columns.tag.rawValue) ASC
        """
        return (query, [])
    }
    
    static func deleteAllTagsForBookmarkQuery(bookmarkRowId: Int64) -> (String, [Any]) {
        ("DELETE FROM BrowserBookmarkTags WHERE \(Columns.bookmarkRowId.rawValue) = ?", [bookmarkRowId])
    }
    
    static func getBookmarksWithTagQuery(tag: String) -> (String, [Any]) {
        let query = """
        SELECT b.* FROM BrowserBookmarks b
        INNER JOIN BrowserBookmarkTags t ON b.rowid = t.\(Columns.bookmarkRowId.rawValue)
        WHERE t.\(Columns.tag.rawValue) = ?
        ORDER BY b.dateAdded DESC
        """
        return (query, [tag])
    }
    
    static func searchBookmarksWithTagsQuery(searchTerms: String, tags: [String], offset: Int = 0, limit: Int = 50) -> (String, [Any]) {
        var conditions: [String] = []
        var args: [Any] = []
        
        // Add search term conditions
        if !searchTerms.isEmpty {
            let tokens = searchTerms
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            
            let urlConditions = tokens.map { _ in "b.url LIKE ?" }
            let titleConditions = tokens.map { _ in "b.title LIKE ?" }
            let searchConditions = urlConditions + titleConditions
            
            if !searchConditions.isEmpty {
                conditions.append("(" + searchConditions.joined(separator: " OR ") + ")")
                let urlArgs = tokens.map { "%\($0)%" }
                let titleArgs = tokens.map { "%\($0)%" }
                args.append(contentsOf: urlArgs + titleArgs)
            }
        }
        
        var query = "SELECT DISTINCT b.* FROM BrowserBookmarks b"
        
        // Add tag filtering
        if !tags.isEmpty {
            query += " INNER JOIN BrowserBookmarkTags t ON b.rowid = t.\(Columns.bookmarkRowId.rawValue)"
            let tagConditions = tags.map { _ in "t.\(Columns.tag.rawValue) = ?" }
            conditions.append("(" + tagConditions.joined(separator: " OR ") + ")")
            args.append(contentsOf: tags)
        }
        
        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }
        
        query += " ORDER BY b.dateAdded DESC LIMIT ? OFFSET ?"
        args.append(contentsOf: [limit, offset])
        
        return (query, args)
    }
}