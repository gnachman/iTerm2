//
//  BrowserDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Foundation

@objc(iTermBrowserDatabase)
class ObjCBrowserDatabase: NSObject {
    @objc static func recordVisit(url: String, title: String?, sessionGuid: String?, transitionType: Int) {
        BrowserDatabase.instance?.recordVisit(
            url: url,
            title: title,
            sessionGuid: sessionGuid,
            transitionType: BrowserTransitionType(rawValue: transitionType) ?? .other
        )
    }
    
    @objc static func updateTitle(_ title: String, forUrl url: String) {
        BrowserDatabase.instance?.updateTitle(title, forUrl: url)
    }
    
    @objc static func urlSuggestions(forPrefix prefix: String, limit: Int) -> [String] {
        return BrowserDatabase.instance?.urlSuggestions(forPrefix: prefix, limit: limit) ?? []
    }
}

class BrowserDatabase {
    private static var _instance: BrowserDatabase?
    static var instanceIfExists: BrowserDatabase? { _instance }
    static var instance: BrowserDatabase? {
        if let _instance {
            return _instance
        }
        let appDefaults = FileManager.default.applicationSupportDirectory()
        guard let appDefaults else {
            return nil
        }
        var url = URL(fileURLWithPath: appDefaults)
        url.appendPathComponent("browserdb.sqlite")
        _instance = BrowserDatabase(url: url)
        return _instance
    }

    let db: iTermDatabase
    
    init?(url: URL) {
        db = iTermSqliteDatabaseImpl(url: url)
        if !db.lock() {
            return nil
        }
        if !db.open() {
            return nil
        }

        if !createTables() {
            DLog("FAILED TO CREATE BROWSER TABLES, CLOSING BROWSER DB")
            db.close()
            return nil
        }
    }

    private func listColumns(resultSet: iTermDatabaseResultSet?) -> [String] {
        guard let resultSet else {
            return []
        }
        var results = [String]()
        while resultSet.next() {
            if let name = resultSet.string(forColumn: "name") {
                results.append(name)
            }
        }
        return results
    }

    private func createTables() -> Bool {
        // Create BrowserHistory table
        if !db.executeUpdate(BrowserHistory.schema(), withArguments: []) {
            return false
        }
        
        let historyMigrations = BrowserHistory.migrations(existingColumns:
            listColumns(
                resultSet: db.executeQuery(
                    BrowserHistory.tableInfoQuery(),
                    withArguments: [])))
        for migration in historyMigrations {
            if !db.executeUpdate(migration.query, withArguments: migration.args) {
                return false
            }
        }
        
        // Create BrowserVisits table
        if !db.executeUpdate(BrowserVisits.schema(), withArguments: []) {
            return false
        }
        
        let visitsMigrations = BrowserVisits.migrations(existingColumns:
            listColumns(
                resultSet: db.executeQuery(
                    BrowserVisits.tableInfoQuery(),
                    withArguments: [])))
        for migration in visitsMigrations {
            if !db.executeUpdate(migration.query, withArguments: migration.args) {
                return false
            }
        }

        return true
    }
    
    // MARK: - Recording Visits
    
    func recordVisit(url: String, title: String? = nil, sessionGuid: String? = nil, referrerUrl: String? = nil, transitionType: BrowserTransitionType = .other) {
        let normalizedUrl = BrowserVisits.normalizeUrl(url)
        
        // Record in BrowserHistory
        let historyEntry = BrowserHistory(
            id: UUID().uuidString,
            url: url,
            title: title,
            visitDate: Date(),
            sessionGuid: sessionGuid,
            referrerUrl: referrerUrl,
            transitionType: transitionType
        )
        
        let (historyQuery, historyArgs) = historyEntry.appendQuery()
        _ = db.executeUpdate(historyQuery, withArguments: historyArgs)
        
        // Update or create entry in BrowserVisits
        updateVisitCount(normalizedUrl: normalizedUrl)
    }
    
    private func updateVisitCount(normalizedUrl: String) {
        // Try to get existing visit record
        let selectQuery = "SELECT * FROM BrowserVisits WHERE normalizedUrl = ?"
        guard let resultSet = db.executeQuery(selectQuery, withArguments: [normalizedUrl]) else {
            return
        }
        
        if resultSet.next() {
            // Update existing record
            if let existingVisit = BrowserVisits(dbResultSet: resultSet) {
                var updatedVisit = existingVisit
                updatedVisit.visitCount += 1
                updatedVisit.lastVisitDate = Date()
                
                let (updateQuery, updateArgs) = updatedVisit.updateQuery()
                _ = db.executeUpdate(updateQuery, withArguments: updateArgs)
            }
        } else {
            // Create new record
            let newVisit = BrowserVisits(normalizedUrl: normalizedUrl)
            let (insertQuery, insertArgs) = newVisit.appendQuery()
            _ = db.executeUpdate(insertQuery, withArguments: insertArgs)
        }
        
        resultSet.close()
    }
    
    // MARK: - Updating Titles
    
    func updateTitle(_ title: String, forUrl url: String) {
        let updateQuery = """
        UPDATE BrowserHistory 
        SET title = ? 
        WHERE url = ? AND (title IS NULL OR title = '')
        """
        _ = db.executeUpdate(updateQuery, withArguments: [title, url])
    }
    
    // MARK: - Search and Suggestions
    
    func searchHistory(terms: String) -> [BrowserHistory] {
        let (query, args) = BrowserHistory.searchQuery(terms: terms)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [BrowserHistory] = []
        while resultSet.next() {
            if let history = BrowserHistory(dbResultSet: resultSet) {
                results.append(history)
            }
        }
        resultSet.close()
        return results
    }
    
    func historyForSession(_ sessionGuid: String) -> [BrowserHistory] {
        let (query, args) = BrowserHistory.historyForSession(sessionGuid)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [BrowserHistory] = []
        while resultSet.next() {
            if let history = BrowserHistory(dbResultSet: resultSet) {
                results.append(history)
            }
        }
        resultSet.close()
        return results
    }
    
    func urlSuggestions(forPrefix prefix: String, limit: Int = 10) -> [String] {
        let (query, args) = BrowserVisits.suggestionsQuery(prefix: prefix, limit: limit)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [String] = []
        while resultSet.next() {
            if let visit = BrowserVisits(dbResultSet: resultSet) {
                results.append(visit.normalizedUrl)
            }
        }
        resultSet.close()
        return results
    }
    
    func topVisitedUrls(limit: Int = 20) -> [BrowserVisits] {
        let (query, args) = BrowserVisits.topVisitedQuery(limit: limit)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [BrowserVisits] = []
        while resultSet.next() {
            if let visit = BrowserVisits(dbResultSet: resultSet) {
                results.append(visit)
            }
        }
        resultSet.close()
        return results
    }
    
    // MARK: - Maintenance
    
    func deleteHistoryBefore(date: Date) {
        let deleteHistoryQuery = "DELETE FROM BrowserHistory WHERE visitDate < ?"
        _ = db.executeUpdate(deleteHistoryQuery, withArguments: [date.timeIntervalSince1970])
        
        // Clean up orphaned visits (visits with no recent history)
        let cleanupVisitsQuery = """
        DELETE FROM BrowserVisits 
        WHERE normalizedUrl NOT IN (
            SELECT DISTINCT BrowserVisits.normalizeUrl(url) 
            FROM BrowserHistory 
            WHERE visitDate >= ?
        )
        """
        _ = db.executeUpdate(cleanupVisitsQuery, withArguments: [date.timeIntervalSince1970])
    }
    
    func deleteAllHistory() {
        _ = db.executeUpdate("DELETE FROM BrowserHistory", withArguments: [])
        _ = db.executeUpdate("DELETE FROM BrowserVisits", withArguments: [])
    }
}