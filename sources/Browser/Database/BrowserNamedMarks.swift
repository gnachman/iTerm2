//
//  BrowserNamedMarks.swift
//  iTerm2
//
//  Created by Claude on 7/1/25.
//

import Foundation

struct BrowserNamedMarks {
    var guid: String
    var url: String
    var name: String
    var sort: Int64?  // Will be auto-assigned by SQLite
    var _text: String  // deprecated
    var dateAdded = Date()
    
    init(guid: String, url: String, name: String, text: String = "") {
        self.guid = guid
        self.url = url
        self.name = name
        self.sort = nil  // Let SQLite auto-assign
        self._text = text
    }
    
    init(guid: String, url: String, name: String, sort: Int64, text: String, dateAdded: Date) {
        self.guid = guid
        self.url = url
        self.name = name
        self.sort = sort
        self._text = text
        self.dateAdded = dateAdded
    }
}

extension BrowserNamedMarks: iTermDatabaseElement {
    enum Columns: String {
        case guid
        case url
        case name
        case sort
        case text
        case dateAdded
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserNamedMarks
            (\(Columns.sort.rawValue) integer primary key autoincrement,
             \(Columns.guid.rawValue) text unique not null,
             \(Columns.url.rawValue) text not null,
             \(Columns.name.rawValue) text not null,
             \(Columns.text.rawValue) text not null default '',
             \(Columns.dateAdded.rawValue) integer not null);
        
        CREATE INDEX IF NOT EXISTS idx_browser_named_marks_guid ON BrowserNamedMarks(\(Columns.guid.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_named_marks_url ON BrowserNamedMarks(\(Columns.url.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_named_marks_date ON BrowserNamedMarks(\(Columns.dateAdded.rawValue) DESC);
        """
    }
    
    static func migrations(existingColumns: [String]) -> [Migration] {
        // Future migrations can be added here
        return []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserNamedMarks)"
    }
    
    func removeQuery() -> (String, [Any?]) {
        ("delete from BrowserNamedMarks where \(Columns.guid.rawValue) = ?", [guid])
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
        insert into BrowserNamedMarks 
            (\(Columns.guid.rawValue),
             \(Columns.url.rawValue),
             \(Columns.name.rawValue), 
             \(Columns.text.rawValue),
             \(Columns.dateAdded.rawValue))
        values (?, ?, ?, ?, ?)
        """,
         [
            guid,
            url,
            name,
            _text,
            dateAdded.timeIntervalSince1970
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
        update BrowserNamedMarks set \(Columns.url.rawValue) = ?,
                                     \(Columns.name.rawValue) = ?,
                                     \(Columns.text.rawValue) = ?
        where \(Columns.guid.rawValue) = ?
        """,
        [
            url,
            name,
            _text,

            // where clause
            guid
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let guid = result.string(forColumn: Columns.guid.rawValue),
              let url = result.string(forColumn: Columns.url.rawValue),
              let name = result.string(forColumn: Columns.name.rawValue),
              let dateAdded = result.date(forColumn: Columns.dateAdded.rawValue)
        else {
            return nil
        }
        
        self.guid = guid
        self.url = url
        self.name = name
        self.sort = result.longLongInt(forColumn: Columns.sort.rawValue)
        self._text = result.string(forColumn: Columns.text.rawValue) ?? ""
        self.dateAdded = dateAdded
    }
}

// MARK: - Query helpers
extension BrowserNamedMarks {
    // Return all named marks paginated sorting those for `url` first.
    static func getPaginatedNamedMarksQuery(urlToSortFirst currentPageUrl: String?, offset: Int, limit: Int) -> (String, [Any?]) {
        let baseQuery = """
        SELECT * FROM BrowserNamedMarks
        ORDER BY 
        """
        
        // If we have a current page URL, sort marks for that page first
        let orderBy: String
        if let currentUrl = currentPageUrl {
            // Parse URL to compare without fragment
            let urlWithoutFragment = URL(string: currentUrl)?.withoutFragment?.absoluteString ?? currentUrl
            orderBy = """
            CASE 
                WHEN SUBSTR(\(Columns.url.rawValue), 1, LENGTH(?)) = ? THEN 0 
                ELSE 1 
            END,
            \(Columns.sort.rawValue) DESC
            """
            return ("\(baseQuery) \(orderBy) LIMIT ? OFFSET ?", [urlWithoutFragment, urlWithoutFragment, limit, offset])
        } else {
            orderBy = "\(Columns.sort.rawValue) DESC"
            return ("\(baseQuery) \(orderBy) LIMIT ? OFFSET ?", [limit, offset])
        }
    }

    // Return all named marks with `url` as a prefix.
    static func getNamedMarksForUrlQuery(url: String) -> (String, [Any?]) {
        // Get marks for the exact URL or URL without fragment
        let urlWithoutFragment = URL(string: url)?.withoutFragment?.absoluteString ?? url
        return ("""
        SELECT * FROM BrowserNamedMarks 
        WHERE \(Columns.url.rawValue) LIKE ? || '%'
        ORDER BY \(Columns.sort.rawValue) DESC
        """, [urlWithoutFragment])
    }
    
    static func searchNamedMarksQuery(terms: String, offset: Int = 0, limit: Int = 50) -> (String, [Any?]) {
        let searchPattern = "%\(terms)%"
        return ("""
        SELECT * FROM BrowserNamedMarks 
        WHERE \(Columns.name.rawValue) LIKE ? OR \(Columns.text.rawValue) LIKE ? OR \(Columns.url.rawValue) LIKE ?
        ORDER BY \(Columns.sort.rawValue) DESC
        LIMIT ? OFFSET ?
        """, [searchPattern, searchPattern, searchPattern, limit, offset])
    }
    
    static func deleteNamedMarkQuery(guid: String) -> (String, [Any?]) {
        ("DELETE FROM BrowserNamedMarks WHERE \(Columns.guid.rawValue) = ?", [guid])
    }
    
    static func getNamedMarkQuery(guid: String) -> (String, [Any?]) {
        ("SELECT * FROM BrowserNamedMarks WHERE \(Columns.guid.rawValue) = ?", [guid])
    }
    
    static func updateNamedMarkNameQuery(guid: String, name: String) -> (String, [Any?]) {
        ("""
        UPDATE BrowserNamedMarks 
        SET \(Columns.name.rawValue) = ? 
        WHERE \(Columns.guid.rawValue) = ?
        """, [name, guid])
    }
}

// URL extension to get URL without fragment
extension URL {
    var withoutFragment: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url
    }
}
