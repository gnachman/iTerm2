//
//  BrowserVisits.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Foundation

struct BrowserVisits {
    var normalizedUrl: String
    var visitCount: Int = 1
    var lastVisitDate = Date()
    var firstVisitDate = Date()
    
    init(normalizedUrl: String) {
        self.normalizedUrl = normalizedUrl
        self.firstVisitDate = Date()
        self.lastVisitDate = firstVisitDate
    }
    
    init(normalizedUrl: String, visitCount: Int, lastVisitDate: Date, firstVisitDate: Date) {
        self.normalizedUrl = normalizedUrl
        self.visitCount = visitCount
        self.lastVisitDate = lastVisitDate
        self.firstVisitDate = firstVisitDate
    }
}

extension BrowserVisits: iTermDatabaseElement {
    enum Columns: String {
        case normalizedUrl
        case visitCount
        case lastVisitDate
        case firstVisitDate
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserVisits
            (\(Columns.normalizedUrl.rawValue) text primary key,
             \(Columns.visitCount.rawValue) integer not null,
             \(Columns.lastVisitDate.rawValue) integer not null,
             \(Columns.firstVisitDate.rawValue) integer not null);
        
        CREATE INDEX IF NOT EXISTS idx_browser_visits_normalized_url ON BrowserVisits(\(Columns.normalizedUrl.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_visits_count ON BrowserVisits(\(Columns.visitCount.rawValue) DESC);
        """
    }
    
    static func migrations(existingColumns: [String]) -> [Migration] {
        // Future migrations can be added here
        return []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserVisits)"
    }
    
    func removeQuery() -> (String, [Any]) {
        ("delete from BrowserVisits where \(Columns.normalizedUrl.rawValue) = ?", [normalizedUrl])
    }

    func appendQuery() -> (String, [Any]) {
        ("""
        insert into BrowserVisits 
            (\(Columns.normalizedUrl.rawValue),
             \(Columns.visitCount.rawValue), 
             \(Columns.lastVisitDate.rawValue), 
             \(Columns.firstVisitDate.rawValue))
        values (?, ?, ?, ?)
        """,
         [
            normalizedUrl,
            visitCount,
            lastVisitDate.timeIntervalSince1970,
            firstVisitDate.timeIntervalSince1970
         ])
    }

    func updateQuery() -> (String, [Any]) {
        ("""
        update BrowserVisits set \(Columns.visitCount.rawValue) = ?,
                                 \(Columns.lastVisitDate.rawValue) = ?,
                                 \(Columns.firstVisitDate.rawValue) = ?
        where \(Columns.normalizedUrl.rawValue) = ?
        """,
        [
            visitCount,
            lastVisitDate.timeIntervalSince1970,
            firstVisitDate.timeIntervalSince1970,
            
            // where clause
            normalizedUrl
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let normalizedUrl = result.string(forColumn: Columns.normalizedUrl.rawValue),
              let lastVisitDate = result.date(forColumn: Columns.lastVisitDate.rawValue),
              let firstVisitDate = result.date(forColumn: Columns.firstVisitDate.rawValue)
        else {
            return nil
        }
        
        self.normalizedUrl = normalizedUrl
        self.visitCount = Int(result.longLongInt(forColumn: Columns.visitCount.rawValue))
        self.lastVisitDate = lastVisitDate
        self.firstVisitDate = firstVisitDate
    }
}

// MARK: - URL Normalization

extension BrowserVisits {
    static func normalizeUrl(_ url: String) -> String {
        guard let parsedUrl = URL(string: url) else {
            return url
        }
        
        var components = URLComponents(url: parsedUrl, resolvingAgainstBaseURL: false)
        
        // Remove fragment (anchor) for normalization
        components?.fragment = nil
        
        // Remove common tracking parameters
        if var queryItems = components?.queryItems {
            queryItems = queryItems.filter { item in
                // Remove common tracking parameters
                !["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
                  "fbclid", "gclid", "ref"].contains(item.name.lowercased())
            }
            components?.queryItems = queryItems.isEmpty ? nil : queryItems
        }
        
        return components?.url?.absoluteString ?? url
    }
    
    // MARK: - URL Bar Suggestion Queries
    
    static func suggestionsQuery(prefix: String, limit: Int = 10) -> (String, [Any]) {
        ("""
        SELECT * FROM BrowserVisits 
        WHERE \(Columns.normalizedUrl.rawValue) LIKE ? 
        ORDER BY \(Columns.visitCount.rawValue) DESC, \(Columns.lastVisitDate.rawValue) DESC 
        LIMIT ?
        """, ["\(prefix)%", limit])
    }
    
    static func topVisitedQuery(limit: Int = 20) -> (String, [Any]) {
        ("""
        SELECT * FROM BrowserVisits 
        ORDER BY \(Columns.visitCount.rawValue) DESC, \(Columns.lastVisitDate.rawValue) DESC 
        LIMIT ?
        """, [limit])
    }
}
