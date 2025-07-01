//
//  BrowserDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Foundation

actor BrowserDatabase {
    // Serial queue to ensure all SQLite operations happen on the same thread
    private let databaseQueue = DispatchQueue(label: "com.iterm2.browser-db", qos: .utility)
    let userID: String?

    private static var _instances = [iTermBrowserUser: BrowserDatabase]()

    static func instance(for user: iTermBrowserUser) async -> BrowserDatabase? {
        if let instance = _instances[user] {
            return instance
        }
        guard let url = url(for: user) else {
            return nil
        }
        let userID: String? = switch user {
        case .devNull: nil
        case .regular(id: let id): id.uuidString
        }
        let instance = await BrowserDatabase(url: url, userID: userID)
        _instances[user] = instance
        return instance
    }

    static func url(for user: iTermBrowserUser) -> URL? {
        switch user {
        case .devNull:
            return URL(string: "file::memory:?mode=memory&cache=shared")
        case .regular(id: let userID):
            let appDefaults = FileManager.default.applicationSupportDirectory()
            guard let appDefaults else {
                return nil
            }
            var url = URL(fileURLWithPath: appDefaults)
            url.appendPathComponent("browserdb-\(userID).sqlite")
            return url
        }
    }

    static var allPersistentInstances: [BrowserDatabase] {
        get async {
            var instances = [BrowserDatabase]()
            guard let appDefaults = FileManager.default.applicationSupportDirectory() else {
                return instances
            }
            let supportURL = URL(fileURLWithPath: appDefaults)
            let fileManager = FileManager.default
            do {
                let files = try fileManager.contentsOfDirectory(
                    at: supportURL,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                for fileURL in files {
                    guard fileURL.pathExtension == "sqlite" else {
                        continue
                    }
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    guard name.hasPrefix("browserdb-") else {
                        continue
                    }
                    guard let idPart = UUID(uuidString: String(name.dropFirst("browserdb-".count))) else {
                        continue
                    }
                    let user = iTermBrowserUser.regular(id: idPart)
                    if let db = await BrowserDatabase.instance(for: user) {
                        instances.append(db)
                    }
                }
            } catch {
                DLog("\(error)")
            }
            return instances
        }
    }

    private let _db: iTermDatabase
    
    // Helper methods to run database operations on the same thread
    private func withDatabase<T>(_ operation: @escaping (iTermDatabase) throws -> T) async throws -> T {
        let db = _db
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let result = try operation(db)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func withDatabase<T>(_ operation: @escaping (iTermDatabase) -> T) async -> T {
        let db = _db
        return await withCheckedContinuation { continuation in
            databaseQueue.async {
                let result = operation(db)
                continuation.resume(returning: result)
            }
        }
    }
    
    private init?(url: URL, userID: String?) async {
        self.userID = userID
        let lockName = userID.map { "browserdb-lock-\($0)" }
        _db = iTermSqliteDatabaseImpl(url: url, lockName: lockName)

        // Ensure database initialization happens on the same thread as all operations
        let initResult = await withDatabase { db in
            if !db.lock() {
                return false
            }
            if !db.open() {
                return false
            }
            if !self.createTables(db: db) {
                DLog("FAILED TO CREATE BROWSER TABLES, CLOSING BROWSER DB")
                db.close()
                return false
            }
            return true
        }
        
        if !initResult {
            return nil
        }
    }

    func erase() async -> Bool {
        return await withDatabase { db in
            db.unlock()
            db.close()
            db.unlink()
            if !db.lock() {
                DLog("LOCK FAILED")
                return false
            }
            if !db.open() {
                DLog("OPEN FAILED")
                return false
            }
            if !self.createTables(db: db) {
                DLog("FAILED TO CREATE BROWSER TABLES, CLOSING BROWSER DB")
                db.close()
                return false
            }
            return true
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

    private func createTables(db: iTermDatabase) -> Bool {
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
        
        // Create BrowserPermissions table
        if !db.executeUpdate(BrowserPermissions.schema(), withArguments: []) {
            return false
        }
        
        let permissionsMigrations = BrowserPermissions.migrations(existingColumns:
            listColumns(
                resultSet: db.executeQuery(
                    BrowserPermissions.tableInfoQuery(),
                    withArguments: [])))
        for migration in permissionsMigrations {
            if !db.executeUpdate(migration.query, withArguments: migration.args) {
                return false
            }
        }

        // Create BrowserNamedMarks table
        if !db.executeUpdate(BrowserNamedMarks.schema(), withArguments: []) {
            return false
        }
        
        let namedMarksMigrations = BrowserNamedMarks.migrations(existingColumns:
            listColumns(
                resultSet: db.executeQuery(
                    BrowserNamedMarks.tableInfoQuery(),
                    withArguments: [])))
        for migration in namedMarksMigrations {
            if !db.executeUpdate(migration.query, withArguments: migration.args) {
                return false
            }
        }

        return true
    }
    
    // MARK: - Recording Visits
    
    func recordVisit(url: String,
                     title: String?,
                     sessionGuid: String?,
                     referrerUrl: String?,
                     transitionType: BrowserTransitionType = .other) async {
        await withDatabase { db in
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
            self.updateVisitCount(db: db, url: url, title: title)
        }
    }
    
    private func updateVisitCount(db: iTermDatabase, url: String, title: String?) {
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
                if let title, !title.isEmpty {
                    updatedVisit.title = title
                }
                let (updateQuery, updateArgs) = updatedVisit.updateQuery()
                _ = db.executeUpdate(updateQuery, withArguments: updateArgs)
            }
        } else {
            // Create new record
            let newVisit = BrowserVisits(hostname: hostname, path: path, title: title == "" ? nil : title)
            let (insertQuery, insertArgs) = newVisit.appendQuery()
            _ = db.executeUpdate(insertQuery, withArguments: insertArgs)
        }
        
        resultSet.close()
    }
    
    // MARK: - Updating Titles
    
    func updateTitle(_ title: String, forUrl url: String) async {
        await withDatabase { db in
            do {
                let (sql, args) = BrowserHistory.updateTitleQuery(title, forUrl: url)
                _ = db.executeUpdate(sql, withArguments: args)
            }
            do {
                let (sql, args) = BrowserVisits.updateTitleQuery(title, forUrl: url)
                _ = db.executeUpdate(sql, withArguments: args)
            }
        }
    }
    
    // MARK: - Search and Suggestions
    
    func searchHistory(terms: String) async -> [BrowserHistory] {
        return await withDatabase { db in
            let (query, args) = BrowserHistory.basicSearchQuery(terms: terms)
            return self.executeHistoryQuery(db: db, query: query, args: args)
        }
    }
    
    func historyForSession(_ sessionGuid: String) async -> [BrowserHistory] {
        return await withDatabase { db in
            let (query, args) = BrowserHistory.historyForSession(sessionGuid)
            return self.executeHistoryQuery(db: db, query: query, args: args)
        }
    }
    
    func urlSuggestions(forPrefix prefix: String, limit: Int = 10) async -> [String] {
        return await withDatabase { db in
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
    }
    
    func getVisitSuggestions(forPrefix prefix: String, limit: Int = 10) async -> [BrowserVisits] {
        return await withDatabase { db in
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
    }
    
    func topVisitedUrls(limit: Int = 20) async -> [BrowserVisits] {
        return await withDatabase { db in
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
    }
    
    // MARK: - Maintenance
    
    func deleteHistoryBefore(date: Date) async {
        await withDatabase { db in
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
    }
    
    func deleteAllHistory() async {
        await withDatabase { db in
            _ = db.executeUpdate("DELETE FROM BrowserHistory", withArguments: [])
            _ = db.executeUpdate("DELETE FROM BrowserVisits", withArguments: [])
        }
    }
    
    func deleteHistoryEntry(id: String) async {
        await withDatabase { db in
            let (query, args) = BrowserHistory.deleteEntryQuery(id: id)
            _ = db.executeUpdate(query, withArguments: args)
        }
    }
    
    func getRecentHistory(offset: Int = 0, limit: Int = 50) async -> [BrowserHistory] {
        return await withDatabase { db in
            let (query, args) = BrowserHistory.recentHistoryQuery(offset: offset, limit: limit)
            return self.executeHistoryQuery(db: db, query: query, args: args)
        }
    }
    
    func searchHistory(terms: String, offset: Int = 0, limit: Int = 50) async -> [BrowserHistory] {
        return await withDatabase { db in
            let (query, args) = BrowserHistory.searchQuery(terms: terms, offset: offset, limit: limit)
            return self.executeHistoryQuery(db: db, query: query, args: args)
        }
    }
    
    // MARK: - Helper Methods
    
    private func executeHistoryQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserHistory] {
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
        return await withDatabase { db in
            let bookmark = BrowserBookmarks(url: url, title: title)
            let (query, args) = bookmark.appendQuery()
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func removeBookmark(url: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.deleteBookmarkQuery(url: url)
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func isBookmarked(url: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.getBookmarkQuery(url: url)
            guard let resultSet = db.executeQuery(query, withArguments: args) else {
                return false
            }
            let exists = resultSet.next()
            resultSet.close()
            return exists
        }
    }
    
    func getBookmark(url: String) async -> BrowserBookmarks? {
        return await withDatabase { db in
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
    }
    
    func getAllBookmarks(sortBy: BookmarkSortOption = .dateAdded, offset: Int = 0, limit: Int = 50) async -> [BrowserBookmarks] {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.getAllBookmarksQuery(sortBy: sortBy, offset: offset, limit: limit)
            return self.executeBookmarkQuery(db: db, query: query, args: args)
        }
    }
    
    func searchBookmarks(terms: String, offset: Int = 0, limit: Int = 50) async -> [BrowserBookmarks] {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.searchQuery(terms: terms, offset: offset, limit: limit)
            return self.executeBookmarkQuery(db: db, query: query, args: args)
        }
    }
    
    func getBookmarkSuggestions(forPrefix prefix: String, limit: Int = 10) async -> [BrowserBookmarks] {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.bookmarkSuggestionsQuery(prefix: prefix, limit: limit)
            return self.executeBookmarkQuery(db: db, query: query, args: args)
        }
    }
    
    // MARK: - Bookmark Tags Management
    
    func addTagToBookmark(url: String, tag: String) async -> Bool {
        return await withDatabase { db in
            // First get the bookmark's rowid
            guard let rowId = self.getBookmarkRowId(db: db, url: url) else {
                return false
            }
            
            let bookmarkTag = BrowserBookmarkTags(bookmarkRowId: rowId, tag: tag)
            let (query, args) = bookmarkTag.appendQuery()
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func removeTagFromBookmark(url: String, tag: String) async -> Bool {
        return await withDatabase { db in
            guard let rowId = self.getBookmarkRowId(db: db, url: url) else {
                return false
            }
            
            let bookmarkTag = BrowserBookmarkTags(bookmarkRowId: rowId, tag: tag)
            let (query, args) = bookmarkTag.removeQuery()
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func getTagsForBookmark(url: String) async -> [String] {
        return await withDatabase { db in
            guard let rowId = self.getBookmarkRowId(db: db, url: url) else {
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
    }
    
    func getAllTags() async -> [String] {
        return await withDatabase { db in
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
    }
    
    func searchBookmarksWithTags(searchTerms: String, tags: [String], offset: Int = 0, limit: Int = 50) async -> [BrowserBookmarks] {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarkTags.searchBookmarksWithTagsQuery(searchTerms: searchTerms, tags: tags, offset: offset, limit: limit)
            return self.executeBookmarkQuery(db: db, query: query, args: args)
        }
    }
    
    func deleteAllBookmarks() async {
        await withDatabase { db in
            _ = db.executeUpdate("DELETE FROM BrowserBookmarks", withArguments: [])
            _ = db.executeUpdate("DELETE FROM BrowserBookmarkTags", withArguments: [])
        }
    }
    
    // MARK: - Helper Methods
    
    private func executeBookmarkQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserBookmarks] {
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
    
    private func getBookmarkRowId(db: iTermDatabase, url: String) -> Int64? {
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
    
    func getVisitCount(for url: String) async -> Int {
        return await withDatabase { db in
            let (hostname, path) = BrowserVisits.parseUrl(url)
            let query = "SELECT visitCount FROM BrowserVisits WHERE hostname = ? AND path = ?"
            
            guard let resultSet = db.executeQuery(query, withArguments: [hostname, path]) else {
                return 0
            }
            
            var visitCount = 0
            if resultSet.next() {
                visitCount = Int(resultSet.longLongInt(forColumn: "visitCount"))
            }
            resultSet.close()
            return visitCount
        }
    }
    
    // MARK: - Permission Management
    
    func savePermission(origin: String, permissionType: BrowserPermissionType, decision: BrowserPermissionDecision) async -> Bool {
        return await withDatabase { db in
            var permission = BrowserPermissions(origin: origin, permissionType: permissionType, decision: decision)
            
            // Check if permission already exists
            let (checkQuery, checkArgs) = BrowserPermissions.getPermissionQuery(origin: origin, permissionType: permissionType)
            if let resultSet = db.executeQuery(checkQuery, withArguments: checkArgs), resultSet.next() {
                // Update existing permission
                permission.updatedAt = Date()
                let (updateQuery, updateArgs) = permission.updateQuery()
                resultSet.close()
                return db.executeUpdate(updateQuery, withArguments: updateArgs)
            } else {
                // Insert new permission
                let (insertQuery, insertArgs) = permission.appendQuery()
                return db.executeUpdate(insertQuery, withArguments: insertArgs)
            }
        }
    }
    
    func getPermission(origin: String, permissionType: BrowserPermissionType) async -> BrowserPermissions? {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.getPermissionQuery(origin: origin, permissionType: permissionType)
            guard let resultSet = db.executeQuery(query, withArguments: args) else {
                return nil
            }
            
            var permission: BrowserPermissions?
            if resultSet.next() {
                permission = BrowserPermissions(dbResultSet: resultSet)
            }
            resultSet.close()
            return permission
        }
    }
    
    func getPermissions(for origin: String) async -> [BrowserPermissions] {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.getPermissionsForOriginQuery(origin: origin)
            return self.executePermissionQuery(db: db, query: query, args: args)
        }
    }
    
    func getPermissions(for permissionType: BrowserPermissionType) async -> [BrowserPermissions] {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.getPermissionsByTypeQuery(permissionType: permissionType)
            return self.executePermissionQuery(db: db, query: query, args: args)
        }
    }
    
    func getGrantedPermissions(for permissionType: BrowserPermissionType) async -> [BrowserPermissions] {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.getGrantedPermissionsQuery(permissionType: permissionType)
            return self.executePermissionQuery(db: db, query: query, args: args)
        }
    }
    
    func getAllPermissions() async -> [BrowserPermissions] {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.getAllPermissionsQuery()
            return self.executePermissionQuery(db: db, query: query, args: args)
        }
    }
    
    func revokePermission(origin: String, permissionType: BrowserPermissionType) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.deletePermissionQuery(origin: origin, permissionType: permissionType)
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func revokeAllPermissions(for origin: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.deleteAllPermissionsForOriginQuery(origin: origin)
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    private func executePermissionQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserPermissions] {
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [BrowserPermissions] = []
        while resultSet.next() {
            if let permission = BrowserPermissions(dbResultSet: resultSet) {
                results.append(permission)
            }
        }
        resultSet.close()
        return results
    }
    
    // MARK: - Named Marks Management
    
    func addNamedMark(guid: String, url: String, name: String, text: String = "") async -> Bool {
        return await withDatabase { db in
            let namedMark = BrowserNamedMarks(guid: guid, url: url, name: name, text: text)
            let (query, args) = namedMark.appendQuery()
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func removeNamedMark(guid: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.deleteNamedMarkQuery(guid: guid)
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func getNamedMark(guid: String) async -> BrowserNamedMarks? {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.getNamedMarkQuery(guid: guid)
            guard let resultSet = db.executeQuery(query, withArguments: args) else {
                return nil
            }
            
            var namedMark: BrowserNamedMarks?
            if resultSet.next() {
                namedMark = BrowserNamedMarks(dbResultSet: resultSet)
            }
            resultSet.close()
            return namedMark
        }
    }
    
    func getAllNamedMarks(sortBy currentPageUrl: String? = nil, offset: Int = 0, limit: Int = 100) async -> [BrowserNamedMarks] {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.getAllNamedMarksQuery(sortBy: currentPageUrl, offset: offset, limit: limit)
            return self.executeNamedMarksQuery(db: db, query: query, args: args)
        }
    }
    
    func getNamedMarksForUrl(_ url: String) async -> [BrowserNamedMarks] {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.getNamedMarksForUrlQuery(url: url)
            return self.executeNamedMarksQuery(db: db, query: query, args: args)
        }
    }
    
    func searchNamedMarks(terms: String, offset: Int = 0, limit: Int = 50) async -> [BrowserNamedMarks] {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.searchNamedMarksQuery(terms: terms, offset: offset, limit: limit)
            return self.executeNamedMarksQuery(db: db, query: query, args: args)
        }
    }
    
    func updateNamedMarkName(guid: String, name: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.updateNamedMarkNameQuery(guid: guid, name: name)
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    func updateNamedMarkText(guid: String, text: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.updateNamedMarkTextQuery(guid: guid, text: text)
            return db.executeUpdate(query, withArguments: args)
        }
    }
    
    
    func deleteAllNamedMarks() async {
        await withDatabase { db in
            _ = db.executeUpdate("DELETE FROM BrowserNamedMarks", withArguments: [])
        }
    }
    
    private func executeNamedMarksQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserNamedMarks] {
        guard let resultSet = db.executeQuery(query, withArguments: args) else {
            return []
        }
        
        var results: [BrowserNamedMarks] = []
        while resultSet.next() {
            if let namedMark = BrowserNamedMarks(dbResultSet: resultSet) {
                results.append(namedMark)
            }
        }
        resultSet.close()
        return results
    }
}
