//
//  BrowserHistory.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Foundation

enum BrowserTransitionType: Int, CaseIterable {
    case typed = 0       // User typed URL in address bar
    case link = 1        // User clicked a link
    case reload = 2      // Page reload
    case backForward = 3 // Back/forward navigation
    case redirect = 4    // Server redirect
    case formSubmit = 5  // Form submission
    case other = 6       // Other navigation types
}

struct BrowserHistory {
    var id = UUID().uuidString
    var url: String
    var title: String?
    var visitDate = Date()
    var sessionGuid: String?
    var referrerUrl: String?
    var transitionType: BrowserTransitionType = .other
}

extension BrowserHistory: iTermDatabaseElement {
    enum Columns: String {
        case id
        case url
        case title
        case visitDate
        case sessionGuid
        case referrerUrl
        case transitionType
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserHistory
            (\(Columns.id.rawValue) text primary key,
             \(Columns.url.rawValue) text not null,
             \(Columns.title.rawValue) text,
             \(Columns.visitDate.rawValue) integer not null,
             \(Columns.sessionGuid.rawValue) text,
             \(Columns.referrerUrl.rawValue) text,
             \(Columns.transitionType.rawValue) integer not null);
        
        CREATE INDEX IF NOT EXISTS idx_browser_history_url ON BrowserHistory(\(Columns.url.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_history_date ON BrowserHistory(\(Columns.visitDate.rawValue) DESC);
        CREATE INDEX IF NOT EXISTS idx_browser_history_session ON BrowserHistory(\(Columns.sessionGuid.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_history_title ON BrowserHistory(\(Columns.title.rawValue));
        """
    }
    
    static func migrations(existingColumns: [String]) -> [Migration] {
        // Future migrations can be added here
        return []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserHistory)"
    }
    
    func removeQuery() -> (String, [Any]) {
        ("delete from BrowserHistory where \(Columns.id.rawValue) = ?", [id])
    }

    func appendQuery() -> (String, [Any]) {
        ("""
        insert into BrowserHistory 
            (\(Columns.id.rawValue),
             \(Columns.url.rawValue), 
             \(Columns.title.rawValue), 
             \(Columns.visitDate.rawValue), 
             \(Columns.sessionGuid.rawValue),
             \(Columns.referrerUrl.rawValue),
             \(Columns.transitionType.rawValue))
        values (?, ?, ?, ?, ?, ?, ?)
        """,
         [
            id,
            url,
            title ?? NSNull(),
            visitDate.timeIntervalSince1970,
            sessionGuid ?? NSNull(),
            referrerUrl ?? NSNull(),
            transitionType.rawValue
         ])
    }

    func updateQuery() -> (String, [Any]) {
        ("""
        update BrowserHistory set \(Columns.url.rawValue) = ?,
                                  \(Columns.title.rawValue) = ?,
                                  \(Columns.visitDate.rawValue) = ?,
                                  \(Columns.sessionGuid.rawValue) = ?,
                                  \(Columns.referrerUrl.rawValue) = ?,
                                  \(Columns.transitionType.rawValue) = ?
        where \(Columns.id.rawValue) = ?
        """,
        [
            url,
            title ?? NSNull(),
            visitDate.timeIntervalSince1970,
            sessionGuid ?? NSNull(),
            referrerUrl ?? NSNull(),
            transitionType.rawValue,
            
            // where clause
            id
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let id = result.string(forColumn: Columns.id.rawValue),
              let url = result.string(forColumn: Columns.url.rawValue),
              let visitDate = result.date(forColumn: Columns.visitDate.rawValue)
        else {
            return nil
        }
        
        self.id = id
        self.url = url
        self.title = result.string(forColumn: Columns.title.rawValue)
        self.visitDate = visitDate
        self.sessionGuid = result.string(forColumn: Columns.sessionGuid.rawValue)
        self.referrerUrl = result.string(forColumn: Columns.referrerUrl.rawValue)
        
        let transitionValue = result.longLongInt(forColumn: Columns.transitionType.rawValue)
        self.transitionType = BrowserTransitionType(rawValue: Int(transitionValue)) ?? .other
    }
}

// MARK: - Search functionality

extension BrowserHistory {
    static func basicSearchQuery(terms: String) -> (String, [Any]) {
        let tokens = terms
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        let urlConditions = tokens.map { _ in "\(Columns.url.rawValue) LIKE ?" }
        let titleConditions = tokens.map { _ in "\(Columns.title.rawValue) LIKE ?" }
        let allConditions = urlConditions + titleConditions
        
        let whereClause = "WHERE " + allConditions.joined(separator: " OR ")
        let orderBy = "ORDER BY \(Columns.visitDate.rawValue) DESC"
        
        let urlArgs = tokens.map { "%\($0)%" }
        let titleArgs = tokens.map { "%\($0)%" }
        let allArgs = urlArgs + titleArgs
        
        return ("SELECT * FROM BrowserHistory \(whereClause) \(orderBy)", allArgs)
    }
    
    static func historyForSession(_ sessionGuid: String) -> (String, [Any]) {
        ("SELECT * FROM BrowserHistory WHERE \(Columns.sessionGuid.rawValue) = ? ORDER BY \(Columns.visitDate.rawValue) DESC", [sessionGuid])
    }
    
    static func recentHistoryQuery(offset: Int = 0, limit: Int = 50) -> (String, [Any]) {
        let query = """
        SELECT * FROM BrowserHistory 
        ORDER BY \(Columns.visitDate.rawValue) DESC 
        LIMIT ? OFFSET ?
        """
        return (query, [limit, offset])
    }
    
    static func searchQuery(terms: String, offset: Int = 0, limit: Int = 50) -> (String, [Any]) {
        let tokens = terms
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        let urlConditions = tokens.map { _ in "\(Columns.url.rawValue) LIKE ?" }
        let titleConditions = tokens.map { _ in "\(Columns.title.rawValue) LIKE ?" }
        let allConditions = urlConditions + titleConditions
        
        let whereClause = "WHERE " + allConditions.joined(separator: " OR ")
        let orderBy = "ORDER BY \(Columns.visitDate.rawValue) DESC"
        let limitClause = "LIMIT ? OFFSET ?"
        
        let urlArgs = tokens.map { "%\($0)%" }
        let titleArgs = tokens.map { "%\($0)%" }
        let allArgs = urlArgs + titleArgs + [limit, offset]
        
        return ("SELECT * FROM BrowserHistory \(whereClause) \(orderBy) \(limitClause)", allArgs)
    }
    
    static func deleteEntryQuery(id: String) -> (String, [Any]) {
        ("DELETE FROM BrowserHistory WHERE \(Columns.id.rawValue) = ?", [id])
    }
}
