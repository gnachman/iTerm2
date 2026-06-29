//
//  LazyLoadingTestHelpers.swift
//  iTerm2
//
//  Created by George Nachman on 3/18/26.
//

import Foundation
@testable import iTerm2SharedARC

// MARK: - MockiTermLargeContentProvider

/// Mock implementation of LargeContentProvider for testing lazy loading behavior.
@objc class MockiTermLargeContentProvider: NSObject, iTermLargeContentProvider {
    /// Number of times loadLargeContent was called
    var loadCallCount = 0

    /// Row IDs that were requested for loading
    var loadedRowIDs: [NSNumber] = []

    /// Content to return for each row ID
    var contentToReturn: [NSNumber: [AnyHashable: Any]] = [:]

    /// If true, loadLargeContent returns nil
    var shouldReturnNil = false

    /// Thread on which loadLargeContent was called (for thread safety tests)
    var loadThread: Thread?

    func loadLargeContent(withMetadata metadata: [AnyHashable: Any]) -> [AnyHashable: Any]? {
        loadCallCount += 1
        loadThread = Thread.current

        // The method expects [AnyHashable: Any] but we have it already
        guard let rowid = iTermLargeContentMetadata.rowid(from: metadata) else {
            return nil
        }
        loadedRowIDs.append(rowid)

        if shouldReturnNil {
            return nil
        }
        return contentToReturn[rowid]
    }

    /// Convenience method to set up content for a specific row ID
    func setContent(_ content: [AnyHashable: Any], forRowID rowid: NSNumber) {
        contentToReturn[rowid] = content
    }
}

// MARK: - LegacyDatabaseBuilder

/// Helper to create databases at various schema versions for testing migration.
class LegacyDatabaseBuilder {

    /// Schema version 0: Original schema (key, identifier, parent, data)
    static func createV0Schema(in db: FMDatabase) -> Bool {
        return db.executeUpdate(
            "CREATE TABLE IF NOT EXISTS Node (key TEXT NOT NULL, identifier TEXT NOT NULL, parent INTEGER NOT NULL, data BLOB)",
            withArgumentsIn: []
        )
    }

    /// Schema version 1: Has both generation and large_data columns (current schema)
    static func createV1Schema(in db: FMDatabase) -> Bool {
        guard createV0Schema(in: db) else { return false }
        guard db.executeUpdate(
            "ALTER TABLE Node ADD COLUMN generation INTEGER DEFAULT 0",
            withArgumentsIn: []
        ) else { return false }
        return db.executeUpdate(
            "ALTER TABLE Node ADD COLUMN large_data BLOB",
            withArgumentsIn: []
        )
    }

    /// Insert a node using legacy encoding (all data in `data` column)
    @discardableResult
    static func insertLegacyNode(
        db: FMDatabase,
        key: String,
        identifier: String,
        parent: Int64,
        data: Data,
        generation: Int = 0
    ) -> Int64? {
        let success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation) VALUES (?, ?, ?, ?, ?)",
            withArgumentsIn: [key, identifier, parent, data, generation]
        )
        return success ? db.lastInsertRowId : nil
    }

    /// Insert a node with large data in the large_data column (current schema)
    @discardableResult
    static func insertNodeWithLargeData(
        db: FMDatabase,
        key: String,
        identifier: String,
        parent: Int64,
        smallData: Data,
        largeData: Data?,
        generation: Int = 0
    ) -> Int64? {
        let success = db.executeUpdate(
            "INSERT INTO Node (key, identifier, parent, data, generation, large_data) VALUES (?, ?, ?, ?, ?, ?)",
            withArgumentsIn: [key, identifier, parent, smallData, generation, largeData as Any]
        )
        return success ? db.lastInsertRowId : nil
    }

    /// Create test POD data suitable for serialization
    static func createTestPOD(extraKeys: [String: Any] = [:]) -> [String: Any] {
        var pod: [String: Any] = [
            "testKey": "testValue",
            "testNumber": 42
        ]
        for (key, value) in extraKeys {
            pod[key] = value
        }
        return pod
    }

    /// Serialize a dictionary to Data for storage
    static func serializePOD(_ pod: [String: Any]) -> Data? {
        var error: NSError?
        let data = NSData.it_data(withSecurelyArchivedObject: pod as NSDictionary, error: &error)
        return error == nil ? data : nil
    }

    /// Create FoldMark-like large content dictionary
    static func createFoldMarkLargeContent(savedLinesCount: Int) -> [AnyHashable: Any] {
        var lines: [[AnyHashable: Any]] = []
        for i in 0..<savedLinesCount {
            lines.append([
                "line": i,
                "content": "Line \(i) content"
            ])
        }
        return [
            "saved lines": lines,
            "saved ITOs": []
        ]
    }
}

// MARK: - Test Data Generators

/// Extension to generate test data for lazy loading tests
extension GraphDatabaseTestHelpers {

    /// Creates a FoldMark-like large content dictionary
    static func createLargeContent(lineCount: Int) -> [AnyHashable: Any] {
        return LegacyDatabaseBuilder.createFoldMarkLargeContent(savedLinesCount: lineCount)
    }

    /// Creates metadata that would be returned for lazy loading
    static func createLazyMetadata(rowid: NSNumber) -> [AnyHashable: Any] {
        return iTermLargeContentMetadata.metadata(forRowID: rowid)
    }

    /// Verify that metadata is valid lazy loading metadata
    static func isLazyMetadata(_ dict: [AnyHashable: Any]) -> Bool {
        return iTermLargeContentMetadata.isLargeContentMetadata(dict)
    }
}

// MARK: - iTermEncoderGraphRecord Extension

extension iTermEncoderGraphRecord {

    /// Creates a test record with support for lazy loading parameters
    static func testRecordWithLargeData(
        key: String,
        identifier: String,
        generation: Int = 0,
        rowid: NSNumber? = nil,
        pod: [String: Any]? = nil,
        hasLargeData: Bool = false,
        children: [iTermEncoderGraphRecord] = []
    ) -> iTermEncoderGraphRecord {
        let podDict: [String: Any] = pod ?? [:]
        let record = iTermEncoderGraphRecord.withPODs(
            podDict,
            graphs: children,
            generation: generation,
            key: key,
            identifier: identifier,
            rowid: rowid
        )
        record.hasLargeData = hasLargeData
        return record
    }
}

// MARK: - In-Memory Database Helper

/// Helper for creating in-memory databases for testing
class InMemoryDatabaseHelper {

    /// Create an FMDatabase backed by an in-memory SQLite database
    static func createInMemoryDatabase() -> FMDatabase {
        // ":memory:" creates an in-memory database
        let db = FMDatabase(path: ":memory:")
        _ = db.open()
        return db
    }

    /// Create an in-memory database with v1 schema (current)
    static func createInMemoryDatabaseWithCurrentSchema() -> FMDatabase {
        let db = createInMemoryDatabase()
        _ = LegacyDatabaseBuilder.createV1Schema(in: db)
        return db
    }

    /// Create an in-memory database with v0 schema (original, for migration tests)
    static func createInMemoryDatabaseWithV0Schema() -> FMDatabase {
        let db = createInMemoryDatabase()
        _ = LegacyDatabaseBuilder.createV0Schema(in: db)
        return db
    }

    /// Check if a column exists in the Node table
    static func columnExists(_ columnName: String, in db: FMDatabase) -> Bool {
        guard let rs = db.executeQuery("PRAGMA table_info(Node)", withArgumentsIn: []) else {
            return false
        }
        defer { rs.close() }

        while rs.next() {
            if rs.string(forColumn: "name") == columnName {
                return true
            }
        }
        return false
    }
}

// MARK: - Test Synchronization Helpers

/// Helpers for testing concurrent access
class ConcurrencyTestHelper {

    /// Execute a block multiple times concurrently and wait for completion
    static func executeConcurrently(
        iterations: Int,
        block: @escaping (Int) -> Void
    ) {
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "com.iterm2.test.concurrent",
            attributes: .concurrent
        )

        for i in 0..<iterations {
            group.enter()
            queue.async {
                block(i)
                group.leave()
            }
        }

        group.wait()
    }

    /// Execute a block and ensure it completes within the timeout
    static func executeWithTimeout(
        seconds: TimeInterval,
        block: @escaping () -> Void
    ) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.iterm2.test.timeout")

        queue.async {
            block()
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + seconds)
        return result == .success
    }
}
