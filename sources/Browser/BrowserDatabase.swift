//
//  BrowserDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Foundation

actor BrowserDatabase {
    private static var _instance: BrowserDatabase?
    static var instanceIfExists: BrowserDatabase? { _instance }
    static var instance: BrowserDatabase? {
        get async {
            if let _instance {
                return _instance
            }
            let appDefaults = FileManager.default.applicationSupportDirectory()
            guard let appDefaults else {
                return nil
            }
            var url = URL(fileURLWithPath: appDefaults)
            url.appendPathComponent("browserdb.sqlite")
            _instance = await BrowserDatabase(url: url)
            return _instance
        }
    }

    let db: iTermDatabase
    
    init?(url: URL) async {
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
        
        // Create BrowserBookmarks table
        if !db.executeUpdate(BrowserBookmarks.schema(), withArguments: []) {
            return false
        }
        
        let bookmarksMigrations = BrowserBookmarks.migrations(existingColumns:
            listColumns(
                resultSet: db.executeQuery(
                    BrowserBookmarks.tableInfoQuery(),
                    withArguments: [])))
        for migration in bookmarksMigrations {
            if !db.executeUpdate(migration.query, withArguments: migration.args) {
                return false
            }
        }
        
        // Create BrowserBookmarkTags table
        if !db.executeUpdate(BrowserBookmarkTags.schema(), withArguments: []) {
            return false
        }
        
        let tagsMigrations = BrowserBookmarkTags.migrations(existingColumns:
            listColumns(
                resultSet: db.executeQuery(
                    BrowserBookmarkTags.tableInfoQuery(),
                    withArguments: [])))
        for migration in tagsMigrations {
            if !db.executeUpdate(migration.query, withArguments: migration.args) {
                return false
            }
        }

        return true
    }
    
    // MARK: - Recording Visits
    
    func recordVisit(url: String,
                     title: String? = nil,
                     sessionGuid: String? = nil,
                     referrerUrl: String? = nil,
                     transitionType: BrowserTransitionType = .other) async {
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
        updateVisitCount(url: url)
    }
    
    private func updateVisitCount(url: String) {
        let (hostname, path) = BrowserVisits.parseUrl(url)
        
        // Try to get existing visit record
        let selectQuery = "SELECT * FROM BrowserVisits WHERE hostname = ? AND path = ?"
        guard let resultSet = db.executeQuery(selectQuery, withArguments: [hostname, path]) else {
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
            let newVisit = BrowserVisits(hostname: hostname, path: path)
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
        let (query, args) = BrowserHistory.basicSearchQuery(terms: terms)
        return executeHistoryQuery(query: query, args: args)
    }
    
    func historyForSession(_ sessionGuid: String) -> [BrowserHistory] {
        let (query, args) = BrowserHistory.historyForSession(sessionGuid)
        return executeHistoryQuery(query: query, args: args)
    }
    
    func urlSuggestions(forPrefix prefix: String, limit: Int = 10) -> [String] {
        let (query, args) = BrowserVisits.suggestionsQuery(prefix: prefix, limit: limit)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [String] = []
        while resultSet.next() {
            if let visit = BrowserVisits(dbResultSet: resultSet) {
                results.append(visit.fullUrl)
            }
        }
        resultSet.close()
        return results
    }
    
    func getVisitSuggestions(forPrefix prefix: String, limit: Int = 10) -> [BrowserVisits] {
        let (query, args) = BrowserVisits.suggestionsQuery(prefix: prefix, limit: limit)
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
    
    func deleteAllHistory() async {
        _ = db.executeUpdate("DELETE FROM BrowserHistory", withArguments: [])
        _ = db.executeUpdate("DELETE FROM BrowserVisits", withArguments: [])
    }
    
    func deleteHistoryEntry(id: String) async {
        let (query, args) = BrowserHistory.deleteEntryQuery(id: id)
        _ = db.executeUpdate(query, withArguments: args)
    }
    
    func getRecentHistory(offset: Int = 0, limit: Int = 50) async -> [BrowserHistory] {
        let (query, args) = BrowserHistory.recentHistoryQuery(offset: offset, limit: limit)
        return executeHistoryQuery(query: query, args: args)
    }
    
    func searchHistory(terms: String, offset: Int = 0, limit: Int = 50) async -> [BrowserHistory] {
        let (query, args) = BrowserHistory.searchQuery(terms: terms, offset: offset, limit: limit)
        return executeHistoryQuery(query: query, args: args)
    }
    
    // MARK: - Helper Methods
    
    private func executeHistoryQuery(query: String, args: [Any]) -> [BrowserHistory] {
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
    
    // MARK: - Bookmark Management
    
    func addBookmark(url: String, title: String? = nil) async -> Bool {
        let bookmark = BrowserBookmarks(url: url, title: title)
        let (query, args) = bookmark.appendQuery()
        return db.executeUpdate(query, withArguments: args)
    }
    
    func removeBookmark(url: String) async -> Bool {
        let (query, args) = BrowserBookmarks.deleteBookmarkQuery(url: url)
        return db.executeUpdate(query, withArguments: args)
    }
    
    func isBookmarked(url: String) async -> Bool {
        let (query, args) = BrowserBookmarks.getBookmarkQuery(url: url)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return false
        }
        let exists = resultSet.next()
        resultSet.close()
        return exists
    }
    
    func getBookmark(url: String) async -> BrowserBookmarks? {
        let (query, args) = BrowserBookmarks.getBookmarkQuery(url: url)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return nil
        }
        
        var bookmark: BrowserBookmarks?
        if resultSet.next() {
            bookmark = BrowserBookmarks(dbResultSet: resultSet)
        }
        resultSet.close()
        return bookmark
    }
    
    func getAllBookmarks(sortBy: BookmarkSortOption = .dateAdded, offset: Int = 0, limit: Int = 50) async -> [BrowserBookmarks] {
        let (query, args) = BrowserBookmarks.getAllBookmarksQuery(sortBy: sortBy, offset: offset, limit: limit)
        return executeBookmarkQuery(query: query, args: args)
    }
    
    func searchBookmarks(terms: String, offset: Int = 0, limit: Int = 50) async -> [BrowserBookmarks] {
        let (query, args) = BrowserBookmarks.searchQuery(terms: terms, offset: offset, limit: limit)
        return executeBookmarkQuery(query: query, args: args)
    }
    
    func getBookmarkSuggestions(forPrefix prefix: String, limit: Int = 10) -> [BrowserBookmarks] {
        let (query, args) = BrowserBookmarks.bookmarkSuggestionsQuery(prefix: prefix, limit: limit)
        return executeBookmarkQuery(query: query, args: args)
    }
    
    // MARK: - Bookmark Tags Management
    
    func addTagToBookmark(url: String, tag: String) async -> Bool {
        // First get the bookmark's rowid
        guard let rowId = await getBookmarkRowId(url: url) else {
            return false
        }
        
        let bookmarkTag = BrowserBookmarkTags(bookmarkRowId: rowId, tag: tag)
        let (query, args) = bookmarkTag.appendQuery()
        return db.executeUpdate(query, withArguments: args)
    }
    
    func removeTagFromBookmark(url: String, tag: String) async -> Bool {
        guard let rowId = await getBookmarkRowId(url: url) else {
            return false
        }
        
        let bookmarkTag = BrowserBookmarkTags(bookmarkRowId: rowId, tag: tag)
        let (query, args) = bookmarkTag.removeQuery()
        return db.executeUpdate(query, withArguments: args)
    }
    
    func getTagsForBookmark(url: String) async -> [String] {
        guard let rowId = await getBookmarkRowId(url: url) else {
            return []
        }
        
        let (query, args) = BrowserBookmarkTags.getTagsForBookmarkQuery(bookmarkRowId: rowId)
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var tags: [String] = []
        while resultSet.next() {
            if let tag = BrowserBookmarkTags(dbResultSet: resultSet) {
                tags.append(tag.tag)
            }
        }
        resultSet.close()
        return tags
    }
    
    func getAllTags() async -> [String] {
        let (query, args) = BrowserBookmarkTags.getAllTagsQuery()
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var tags: [String] = []
        while resultSet.next() {
            if let tagName = resultSet.string(forColumn: "tag") {
                tags.append(tagName)
            }
        }
        resultSet.close()
        return tags
    }
    
    func searchBookmarksWithTags(searchTerms: String, tags: [String], offset: Int = 0, limit: Int = 50) async -> [BrowserBookmarks] {
        let (query, args) = BrowserBookmarkTags.searchBookmarksWithTagsQuery(searchTerms: searchTerms, tags: tags, offset: offset, limit: limit)
        return executeBookmarkQuery(query: query, args: args)
    }
    
    func deleteAllBookmarks() async {
        _ = db.executeUpdate("DELETE FROM BrowserBookmarks", withArguments: [])
        _ = db.executeUpdate("DELETE FROM BrowserBookmarkTags", withArguments: [])
    }
    
    // MARK: - Helper Methods
    
    private func executeBookmarkQuery(query: String, args: [Any]) -> [BrowserBookmarks] {
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [BrowserBookmarks] = []
        while resultSet.next() {
            if let bookmark = BrowserBookmarks(dbResultSet: resultSet) {
                results.append(bookmark)
            }
        }
        resultSet.close()
        return results
    }
    
    private func getBookmarkRowId(url: String) async -> Int64? {
        let query = "SELECT rowid FROM BrowserBookmarks WHERE url = ?"
        guard let resultSet = db.executeQuery(query, withArguments: [url]) else {
            return nil
        }
        
        var rowId: Int64?
        if resultSet.next() {
            rowId = resultSet.longLongInt(forColumn: "rowid")
        }
        resultSet.close()
        return rowId
    }
}
