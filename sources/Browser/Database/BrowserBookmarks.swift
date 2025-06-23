//
//  BrowserBookmarks.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

import Foundation

struct BrowserBookmarks {
    var url: String
    var title: String?
    var dateAdded = Date()
    
    init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }
    
    init(url: String, title: String?, dateAdded: Date) {
        self.url = url
        self.title = title
        self.dateAdded = dateAdded
    }
}

extension BrowserBookmarks: iTermDatabaseElement {
    enum Columns: String {
        case url
        case title
        case dateAdded
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserBookmarks
            (\(Columns.url.rawValue) text primary key,
             \(Columns.title.rawValue) text,
             \(Columns.dateAdded.rawValue) integer not null);
        
        CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_title ON BrowserBookmarks(\(Columns.title.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_date ON BrowserBookmarks(\(Columns.dateAdded.rawValue) DESC);
        """
    }
    
    static func migrations(existingColumns: [String]) -> [Migration] {
        // Future migrations can be added here
        return []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserBookmarks)"
    }
    
    func removeQuery() -> (String, [Any?]) {
        ("delete from BrowserBookmarks where \(Columns.url.rawValue) = ?", [url])
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
        insert into BrowserBookmarks 
            (\(Columns.url.rawValue),
             \(Columns.title.rawValue), 
             \(Columns.dateAdded.rawValue))
        values (?, ?, ?)
        """,
         [
            url,
            title ?? NSNull(),
            dateAdded.timeIntervalSince1970
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
        update BrowserBookmarks set \(Columns.title.rawValue) = ?,
                                    \(Columns.dateAdded.rawValue) = ?
        where \(Columns.url.rawValue) = ?
        """,
        [
            title ?? NSNull(),
            dateAdded.timeIntervalSince1970,
            
            // where clause
            url
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let url = result.string(forColumn: Columns.url.rawValue),
              let dateAdded = result.date(forColumn: Columns.dateAdded.rawValue)
        else {
            return nil
        }
        
        self.url = url
        self.title = result.string(forColumn: Columns.title.rawValue)
        self.dateAdded = dateAdded
    }
}

// MARK: - Search and Query functionality

extension BrowserBookmarks {
    static func searchQuery(terms: String, offset: Int = 0, limit: Int = 50) -> (String, [Any?]) {
        let tokens = terms
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        let urlConditions = tokens.map { _ in "\(Columns.url.rawValue) LIKE ?" }
        let titleConditions = tokens.map { _ in "\(Columns.title.rawValue) LIKE ?" }
        let allConditions = urlConditions + titleConditions
        
        let whereClause = "WHERE " + allConditions.joined(separator: " OR ")
        let orderBy = "ORDER BY \(Columns.dateAdded.rawValue) DESC"
        let limitClause = "LIMIT ? OFFSET ?"
        
        let urlArgs = tokens.map { "%\($0)%" }
        let titleArgs = tokens.map { "%\($0)%" }
        let allArgs = urlArgs + titleArgs + [limit, offset]
        
        return ("SELECT * FROM BrowserBookmarks \(whereClause) \(orderBy) \(limitClause)", allArgs)
    }
    
    static func getAllBookmarksQuery(sortBy: BookmarkSortOption = .dateAdded, offset: Int = 0, limit: Int = 50) -> (String, [Any?]) {
        let sortColumn: String
        switch sortBy {
        case .dateAdded:
            sortColumn = "\(Columns.dateAdded.rawValue) DESC"
        case .title:
            sortColumn = "\(Columns.title.rawValue) ASC"
        case .url:
            sortColumn = "\(Columns.url.rawValue) ASC"
        }
        
        let query = """
        SELECT * FROM BrowserBookmarks 
        ORDER BY \(sortColumn)
        LIMIT ? OFFSET ?
        """
        return (query, [limit, offset])
    }
    
    static func getBookmarkQuery(url: String) -> (String, [Any?]) {
        ("SELECT * FROM BrowserBookmarks WHERE \(Columns.url.rawValue) = ?", [url])
    }
    
    static func deleteBookmarkQuery(url: String) -> (String, [Any?]) {
        ("DELETE FROM BrowserBookmarks WHERE \(Columns.url.rawValue) = ?", [url])
    }
    
    static func bookmarkSuggestionsQuery(prefix: String, limit: Int = 10) -> (String, [Any?]) {
        let query = """
        SELECT * FROM BrowserBookmarks 
        WHERE \(Columns.url.rawValue) LIKE ? OR \(Columns.title.rawValue) LIKE ?
        ORDER BY \(Columns.dateAdded.rawValue) DESC
        LIMIT ?
        """
        let searchTerm = "%\(prefix)%"
        return (query, [searchTerm, searchTerm, limit])
    }
}

enum BookmarkSortOption: String, CaseIterable {
    case dateAdded = "dateAdded"
    case title = "title"
    case url = "url"
    
    var displayName: String {
        switch self {
        case .dateAdded:
            return "Date Added"
        case .title:
            return "Title"
        case .url:
            return "URL"
        }
    }
}
