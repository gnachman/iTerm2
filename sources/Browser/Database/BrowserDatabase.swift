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

    static func makeEphemeralInstance() async -> BrowserDatabase {
        return await BrowserDatabase(url: URL(string: "file::memory:?mode=memory&cache=shared")!, userID: nil)!
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
        return try await withCheckedThrowingContinuation { continuation in
            databaseQueue.async {
                do {
                    let result = try operation(self._db)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func withDatabase<T>(_ operation: @escaping (iTermDatabase) -> T) async -> T {
        return await withCheckedContinuation { continuation in
            databaseQueue.async {
                let result = operation(self._db)
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

    private func executeUpdate(db: iTermDatabase, sql: String, withArguments args: [Any?]) -> Bool {
        do {
            try db.executeUpdate(sql, withArguments: args)
            return true
        } catch {
            DLog("\(sql): \(error)")
            return false
        }
    }

    @discardableResult
    private func executeQuery(db: iTermDatabase, sql: String, withArguments args: [Any?]) -> iTermDatabaseResultSet? {
        do {
            return try db.executeQuery(sql, withArguments: args)
        } catch {
            DLog("\(sql): \(error)")
            return nil
        }
    }

    private func createTables(db: iTermDatabase) -> Bool {
        // Create BrowserHistory table
        if !executeUpdate(db: db, sql: BrowserHistory.schema(), withArguments: []) {
            return false
        }

        let historyMigrations = BrowserHistory.migrations(existingColumns:
            listColumns(resultSet: executeQuery(db: db,
                                                sql: BrowserHistory.tableInfoQuery(),
                                                withArguments: [])))
        if !db.transaction({
            for migration in historyMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
        }

        // Create BrowserVisits table
        if !executeUpdate(db: db, sql: BrowserVisits.schema(), withArguments: []) {
            return false
        }

        let visitsMigrations = BrowserVisits.migrations(existingColumns:listColumns(resultSet: executeQuery(
            db: db,
            sql: BrowserVisits.tableInfoQuery(),
            withArguments: [])))
        if !db.transaction({
            for migration in visitsMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
        }
        // Create BrowserBookmarks table
        if !executeUpdate(db: db, sql: BrowserBookmarks.schema(), withArguments: []) {
            return false
        }

        let bookmarksMigrations = BrowserBookmarks.migrations(existingColumns: listColumns(
            resultSet: executeQuery(db: db,
                                    sql: BrowserBookmarks.tableInfoQuery(),
                                    withArguments: [])))
        if !db.transaction({
            for migration in bookmarksMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
        }

        // Create BrowserBookmarkTags table
        if !executeUpdate(db: db, sql: BrowserBookmarkTags.schema(), withArguments: []) {
            return false
        }

        let tagsMigrations = BrowserBookmarkTags.migrations(existingColumns: listColumns(
            resultSet: executeQuery(db: db,
                                    sql: BrowserBookmarkTags.tableInfoQuery(),
                                    withArguments: [])))
        if !db.transaction({
            for migration in tagsMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
        }

        // Create BrowserPermissions table
        if !executeUpdate(db: db, sql: BrowserPermissions.schema(), withArguments: []) {
            return false
        }

        let permissionsMigrations = BrowserPermissions.migrations(existingColumns: listColumns(
            resultSet: executeQuery(db: db,
                                    sql: BrowserPermissions.tableInfoQuery(),
                                    withArguments: [])))
        if !db.transaction({
            for migration in permissionsMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
        }

        // Create BrowserNamedMarks table
        if !executeUpdate(db: db, sql: BrowserNamedMarks.schema(), withArguments: []) {
            return false
        }

        let namedMarksMigrations = BrowserNamedMarks.migrations(existingColumns:listColumns(
            resultSet: executeQuery(db: db,
                                    sql: BrowserNamedMarks.tableInfoQuery(),
                                    withArguments: [])))
        if !db.transaction({
            for migration in namedMarksMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
        }

        // Create BrowserKeyValueStore table
        if !executeUpdate(db: db, sql: BrowserKeyValueStoreEntry.schema(), withArguments: []) {
            return false
        }
        let keyValueStoreMigrations = BrowserKeyValueStoreEntry.migration(existingColumns:listColumns(
            resultSet: executeQuery(db: db,
                                    sql: BrowserKeyValueStoreEntry.tableInfoQuery(),
                                    withArguments: [])))
        if !db.transaction({
            for migration in keyValueStoreMigrations {
                if !executeUpdate(db: db, sql: migration.query, withArguments: migration.args) {
                    return false
                }
            }
            return true
        }) {
            return false
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
            _ = self.executeUpdate(db: db, sql: historyQuery, withArguments: historyArgs)

            // Update or create entry in BrowserVisits
            self.updateVisitCount(db: db, url: url, title: title)
        }
    }

    private func updateVisitCount(db: iTermDatabase, url: String, title: String?) {
        let (hostname, path) = BrowserVisits.parseUrl(url)

        // Try to get existing visit record
        let selectQuery = "SELECT * FROM BrowserVisits WHERE hostname = ? AND path = ?"
        guard let resultSet = executeQuery(db: db, sql: selectQuery, withArguments: [hostname, path]) else {
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
                _ = executeUpdate(db: db, sql: updateQuery, withArguments: updateArgs)
            }
        } else {
            // Create new record
            let newVisit = BrowserVisits(hostname: hostname, path: path, title: title == "" ? nil : title, url: url)
            let (insertQuery, insertArgs) = newVisit.appendQuery()
            _ = executeUpdate(db: db, sql: insertQuery, withArguments: insertArgs)
        }

        resultSet.close()
    }

    // MARK: - Updating Titles

    func updateTitle(_ title: String, forUrl url: String) async {
        await withDatabase { db in
            do {
                let (sql, args) = BrowserHistory.updateTitleQuery(title, forUrl: url)
                _ = self.executeUpdate(db: db, sql: sql, withArguments: args)
            }
            do {
                let (sql, args) = BrowserVisits.updateTitleQuery(title, forUrl: url)
                _ = self.executeUpdate(db: db, sql: sql, withArguments: args)
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
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            _ = self.executeUpdate(db: db, sql: deleteHistoryQuery, withArguments: [date.timeIntervalSince1970])

            // Clean up orphaned visits (visits with no recent history)
            let cleanupVisitsQuery = """
            DELETE FROM BrowserVisits 
            WHERE normalizedUrl NOT IN (
                SELECT DISTINCT BrowserVisits.normalizeUrl(url) 
                FROM BrowserHistory 
                WHERE visitDate >= ?
            )
            """
            _ = self.executeUpdate(db: db, sql: cleanupVisitsQuery, withArguments: [date.timeIntervalSince1970])
        }
    }

    func deleteAllHistory() async {
        await withDatabase { db in
            _ = self.executeUpdate(db: db, sql: "DELETE FROM BrowserHistory", withArguments: [])
            _ = self.executeUpdate(db: db, sql: "DELETE FROM BrowserVisits", withArguments: [])
        }
    }

    func deleteHistoryEntry(id: String) async {
        await withDatabase { db in
            let (query, args) = BrowserHistory.deleteEntryQuery(id: id)
            _ = self.executeUpdate(db: db, sql: query, withArguments: args)
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

    func searchVisits(terms: String, maxAge: Int, minCount: Int, offset: Int = 0, limit: Int = 50) async -> [BrowserVisits] {
        if terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return await withDatabase { db in
            let tuple = BrowserVisits.searchQuery(terms: terms,
                                                          maxAge: maxAge,
                                                          minCount: minCount,
                                                          offset: offset,
                                                          limit: limit)
            guard let (query, args) = tuple else {
                return []
            }
            return self.executeVisitsQuery(db: db, query: query, args: args)
        }
    }


    // MARK: - Helper Methods

    private func executeHistoryQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserHistory] {
        guard let resultSet = executeQuery(db: db, sql: query, withArguments: args) else {
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

    private func executeVisitsQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserVisits] {
        guard let resultSet = executeQuery(db: db, sql: query, withArguments: args) else {
            return []
        }

        var results: [BrowserVisits] = []
        while resultSet.next() {
            if let visits = BrowserVisits(dbResultSet: resultSet) {
                results.append(visits)
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
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func removeBookmark(url: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.deleteBookmarkQuery(url: url)
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func isBookmarked(url: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserBookmarks.getBookmarkQuery(url: url)
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func removeTagFromBookmark(url: String, tag: String) async -> Bool {
        return await withDatabase { db in
            guard let rowId = self.getBookmarkRowId(db: db, url: url) else {
                return false
            }

            let bookmarkTag = BrowserBookmarkTags(bookmarkRowId: rowId, tag: tag)
            let (query, args) = bookmarkTag.removeQuery()
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func getTagsForBookmark(url: String) async -> [String] {
        return await withDatabase { db in
            guard let rowId = self.getBookmarkRowId(db: db, url: url) else {
                return []
            }

            let (query, args) = BrowserBookmarkTags.getTagsForBookmarkQuery(bookmarkRowId: rowId)
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            _ = self.executeUpdate(db: db, sql: "DELETE FROM BrowserBookmarks", withArguments: [])
            _ = self.executeUpdate(db: db, sql: "DELETE FROM BrowserBookmarkTags", withArguments: [])
        }
    }

    // MARK: - Helper Methods

    private func executeBookmarkQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserBookmarks] {
        guard let resultSet = executeQuery(db: db, sql: query, withArguments: args) else {
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
        guard let resultSet = executeQuery(db: db, sql: query, withArguments: [url]) else {
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

            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: [hostname, path]) else {
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

    func resetPermission(origin: String, permissionType: BrowserPermissionType) async {
        await withDatabase { db in
            let permission = BrowserPermissions(origin: origin, permissionType: permissionType, decision: .denied)
            let (query, args) = permission.removeQuery()
            _ = self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func savePermission(origin: String, permissionType: BrowserPermissionType, decision: BrowserPermissionDecision) async -> Bool {
        return await withDatabase { db in
            var permission = BrowserPermissions(origin: origin, permissionType: permissionType, decision: decision)

            // Check if permission already exists
            let (checkQuery, checkArgs) = BrowserPermissions.getPermissionQuery(origin: origin, permissionType: permissionType)
            if let resultSet = self.executeQuery(db: db, sql: checkQuery, withArguments: checkArgs), resultSet.next() {
                // Update existing permission
                permission.updatedAt = Date()
                let (updateQuery, updateArgs) = permission.updateQuery()
                resultSet.close()
                return self.executeUpdate(db: db, sql: updateQuery, withArguments: updateArgs)
            } else {
                // Insert new permission
                let (insertQuery, insertArgs) = permission.appendQuery()
                return self.executeUpdate(db: db, sql: insertQuery, withArguments: insertArgs)
            }
        }
    }

    func getPermission(origin: String, permissionType: BrowserPermissionType) async -> BrowserPermissions? {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.getPermissionQuery(origin: origin, permissionType: permissionType)
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func revokeAllPermissions(for origin: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserPermissions.deleteAllPermissionsForOriginQuery(origin: origin)
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    private func executePermissionQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserPermissions] {
        guard let resultSet = executeQuery(db: db, sql: query, withArguments: args) else {
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
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func removeNamedMark(guid: String) async -> Bool {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.deleteNamedMarkQuery(guid: guid)
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func getNamedMark(guid: String) async -> BrowserNamedMarks? {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.getNamedMarkQuery(guid: guid)
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
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

    func getPaginatedNamedMarksQuery(urlToSortFirst currentPageUrl: String?, offset: Int, limit: Int) async -> [BrowserNamedMarks] {
        return await withDatabase { db in
            let (query, args) = BrowserNamedMarks.getPaginatedNamedMarksQuery(urlToSortFirst: currentPageUrl, offset: offset, limit: limit)
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
            return self.executeUpdate(db: db, sql: query, withArguments: args)
        }
    }

    func deleteAllNamedMarks() async {
        await withDatabase { db in
            _ = self.executeUpdate(db: db, sql: "DELETE FROM BrowserNamedMarks", withArguments: [])
        }
    }

    private func executeNamedMarksQuery(db: iTermDatabase, query: String, args: [Any?]) -> [BrowserNamedMarks] {
        guard let resultSet = executeQuery(db: db, sql: query, withArguments: args) else {
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

    // MARK: - Key-value store

    func getKeyValueStoreEntries(area: String?, extensionId: String?, keys: Set<String>) async throws -> [String: String] {
        return try await withDatabase { db in
            let (query, args) = BrowserKeyValueStoreEntry.getQuery(area: area, extensionId: extensionId, keys: Array(keys))
            guard let resultSet = try db.executeQuery(query, withArguments: args) else {
                return [:]
            }

            var result = [String: String]()
            while resultSet.next() {
                if let entry = BrowserKeyValueStoreEntry(dbResultSet: resultSet) {
                    result[entry.key] = entry.value
                }
            }
            resultSet.close()
            return result
        }
    }

    func getKeyValueStoreEntries(area: String, extensionId: String) async throws -> [String: String] {
        return try await withDatabase { db in
            let (query, args) = BrowserKeyValueStoreEntry.getQuery(area: area, extensionId: extensionId)
            guard let resultSet = try db.executeQuery(query, withArguments: args) else {
                return [:]
            }

            var result = [String: String]()
            while resultSet.next() {
                if let entry = BrowserKeyValueStoreEntry(dbResultSet: resultSet) {
                    result[entry.key] = entry.value
                }
            }
            resultSet.close()
            return result
        }
    }

    func setKeyValueStoreEntries(area: String?, extensionId: String?, newValues: [String: String]) async throws -> [String: String] {
        return try await withDatabase { db in
            let statements = BrowserKeyValueStoreEntry.upsertAndReturnOriginalQuery(
                area: area, extensionId: extensionId, kvps: newValues)
            guard let rows: [BrowserKeyValueStoreEntry] = try db.executeStatements(statements) else {
                return [:]
            }

            var result = [String: String]()
            for entry in rows {
                result[entry.key] = entry.value
            }
            return result
        }
    }

    func clearKeyValueStore(area: String?, extensionId: String?, keys: Set<String>) async throws -> [String: String] {
        return try await withDatabase { db in
            let (query, args) = BrowserKeyValueStoreEntry.removeQuery(
                area: area, extensionId: extensionId, keys: Array(keys))
            guard let resultSet = try db.executeQuery(query, withArguments: args) else {
                return [:]
            }
            var result = [String: String]()
            while resultSet.next() {
                if let key = resultSet.string(forColumn: "key"),
                   let value = resultSet.string(forColumn: "value") {
                    result[key] = value
                }
            }
            return result
        }
    }

    func clearKeyValueStore(area: String?, extensionId: String?) async throws -> [String: String] {
        return try await withDatabase { db in
            let (query, args) = BrowserKeyValueStoreEntry.removeQuery(
                area: area, extensionId: extensionId)
            guard let resultSet = try db.executeQuery(query, withArguments: args) else {
                return [:]
            }
            var result = [String: String]()
            while resultSet.next() {
                if let key = resultSet.string(forColumn: "key"),
                   let value = resultSet.string(forColumn: "value") {
                    result[key] = value
                }
            }
            return result
        }
    }

    func clearKeyValueStore(extensionId: String?) async throws {
        return try await withDatabase { db in
            let (query, args) = BrowserKeyValueStoreEntry.removeQuery(extensionId: extensionId)
            _ = try db.executeUpdate(query, withArguments: args)
        }
    }

    struct KeyValueUsage {
        var bytesUsed: Int
        var itemCount: Int
    }
    func keyValueUsage(area: String,
                       extensionId: String) async -> KeyValueUsage {
        return await withDatabase { db in
            let (query, args) = BrowserKeyValueStoreEntry.usageQuery(area: area, extensionId: extensionId)
            var result = KeyValueUsage(bytesUsed: 0, itemCount: 0)
            guard let resultSet = self.executeQuery(db: db, sql: query, withArguments: args) else {
                return result
            }

            while resultSet.next() {
                result.bytesUsed = Int(resultSet.longLongInt(forColumn: "bytesUsed"))
                result.itemCount = Int(resultSet.longLongInt(forColumn: "itemCount"))
            }
            resultSet.close()
            return result
        }
    }
}
