//
//  BrowserVisits.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Foundation

struct BrowserVisits {
    var hostname: String
    var path: String
    var visitCount: Int = 1
    var lastVisitDate = Date()
    var firstVisitDate = Date()
    var title: String?

    init(hostname: String, path: String = "") {
        self.hostname = hostname
        self.path = path
        self.firstVisitDate = Date()
        self.lastVisitDate = firstVisitDate
    }
    
    init(hostname: String, path: String, visitCount: Int, lastVisitDate: Date, firstVisitDate: Date, title: String?) {
        self.hostname = hostname
        self.path = path
        self.visitCount = visitCount
        self.lastVisitDate = lastVisitDate
        self.firstVisitDate = firstVisitDate
        self.title = title
    }
    
    var fullUrl: String {
        let cleanHostname = hostname.hasPrefix(".") ? String(hostname.dropFirst()) : hostname
        return path.isEmpty ? cleanHostname : "\(cleanHostname)\(path)"
    }
}

extension BrowserVisits: iTermDatabaseElement {
    enum Columns: String {
        case hostname
        case path
        case visitCount
        case lastVisitDate
        case firstVisitDate
        case title
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserVisits
            (\(Columns.hostname.rawValue) text not null,
             \(Columns.path.rawValue) text not null,
             \(Columns.visitCount.rawValue) integer not null,
             \(Columns.lastVisitDate.rawValue) integer not null,
             \(Columns.firstVisitDate.rawValue) integer not null,
             \(Columns.title.rawValue) text,
             PRIMARY KEY (\(Columns.hostname.rawValue), \(Columns.path.rawValue)));
        
        CREATE INDEX IF NOT EXISTS idx_browser_visits_hostname ON BrowserVisits(\(Columns.hostname.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_visits_path ON BrowserVisits(\(Columns.path.rawValue));
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
    
    func removeQuery() -> (String, [Any?]) {
        ("delete from BrowserVisits where \(Columns.hostname.rawValue) = ? AND \(Columns.path.rawValue) = ?", [hostname, path])
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
        insert into BrowserVisits 
            (\(Columns.hostname.rawValue),
             \(Columns.path.rawValue),
             \(Columns.visitCount.rawValue), 
             \(Columns.lastVisitDate.rawValue), 
             \(Columns.firstVisitDate.rawValue),)
             \(Columns.title.rawValue)
        values (?, ?, ?, ?, ?)
        """,
         [
            hostname,
            path,
            visitCount,
            lastVisitDate.timeIntervalSince1970,
            firstVisitDate.timeIntervalSince1970,
            title
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
        update BrowserVisits set \(Columns.visitCount.rawValue) = ?,
                                 \(Columns.lastVisitDate.rawValue) = ?,
                                 \(Columns.firstVisitDate.rawValue) = ?,
                                 \(Columns.title.rawValue) = ?,
        where \(Columns.hostname.rawValue) = ? AND \(Columns.path.rawValue) = ?
        """,
        [
            visitCount,
            lastVisitDate.timeIntervalSince1970,
            firstVisitDate.timeIntervalSince1970,
            
            // where clause
            hostname,
            path,
            title
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let hostname = result.string(forColumn: Columns.hostname.rawValue),
              let path = result.string(forColumn: Columns.path.rawValue),
              let lastVisitDate = result.date(forColumn: Columns.lastVisitDate.rawValue),
              let firstVisitDate = result.date(forColumn: Columns.firstVisitDate.rawValue)
        else {
            return nil
        }
        
        self.hostname = hostname
        self.path = path
        self.visitCount = Int(result.longLongInt(forColumn: Columns.visitCount.rawValue))
        self.lastVisitDate = lastVisitDate
        self.firstVisitDate = firstVisitDate
        self.title = result.string(forColumn: Columns.title.rawValue)
    }
}

// MARK: - URL Normalization

extension BrowserVisits {
    static func parseUrl(_ url: String) -> (hostname: String, path: String) {
        guard let parsedUrl = URL(string: url) else {
            return (hostname: url, path: "")
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
        
        // Extract hostname (without scheme) and prepend period for domain component matching
        let hostname = "." + (components?.host ?? "")
        
        // Extract path (including query if present)
        var path = components?.path ?? ""
        if let query = components?.query, !query.isEmpty {
            path += "?" + query
        }
        
        return (hostname: hostname, path: path)
    }
    
    // MARK: - URL Bar Suggestion Queries
    
    static func suggestionsQuery(prefix: String, limit: Int = 10) -> (String, [Any?]) {
        // Parse the query to determine if it has a path component
        let (queryHostname, queryPath) = parseUrl(prefix.contains("://") ? prefix : "//\(prefix)")
        
        if queryPath.isEmpty {
            // Just hostname query - search for hostnames with domain component starting with prefix
            return ("""
            SELECT * FROM BrowserVisits 
            WHERE \(Columns.hostname.rawValue) LIKE ? 
            ORDER BY \(Columns.visitCount.rawValue) DESC, \(Columns.lastVisitDate.rawValue) DESC 
            LIMIT ?
            """, ["%\(queryHostname)%", limit])
        } else {
            // Query has path - match hostname suffix and path prefix
            return ("""
            SELECT * FROM BrowserVisits 
            WHERE \(Columns.hostname.rawValue) LIKE ? 
              AND \(Columns.path.rawValue) LIKE ? 
            ORDER BY \(Columns.visitCount.rawValue) DESC, \(Columns.lastVisitDate.rawValue) DESC 
            LIMIT ?
            """, ["%\(queryHostname)", "\(queryPath)%", limit])
        }
    }
    
    static func topVisitedQuery(limit: Int = 20) -> (String, [Any?]) {
        ("""
        SELECT * FROM BrowserVisits 
        ORDER BY \(Columns.visitCount.rawValue) DESC, \(Columns.lastVisitDate.rawValue) DESC 
        LIMIT ?
        """, [limit])
    }
}
