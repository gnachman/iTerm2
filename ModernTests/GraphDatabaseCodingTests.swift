//
//  GraphDatabaseCodingTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermCodingTests.m. The legacy tests drove
//  iTermGraphDatabase with a mock database and compared the SQL it issued.
//  iTermDatabase has variadic requirements a Swift mock cannot satisfy, so these
//  tests use a real SQLite file in a per-test temporary directory and assert on
//  the resulting Node rows and on the record that round-trips through disk.
//

import XCTest
@testable import iTerm2SharedARC

final class GraphDatabaseCodingTests: XCTestCase {
    private var tempDir: URL!
    private var sqlite: iTermSqliteDatabaseImpl?
    private var graphDatabase: iTermGraphDatabase?

    private var databaseURL: URL {
        return tempDir.appendingPathComponent("graph.sqlite")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphDatabaseCodingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        closeGraphDatabase()
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private struct NodeRow: Equatable {
        var key: String
        var identifier: String
        var parent: Int64
        var rowid: Int64
        var generation: Int64
        var pod: NSDictionary
    }

    private func closeGraphDatabase() {
        graphDatabase = nil
        sqlite?.close()
        sqlite = nil
    }

    // Opens (or reopens) a graph database on the per-test file and waits for it to load.
    private func openGraphDatabase() -> iTermGraphDatabase {
        closeGraphDatabase()
        let db = iTermSqliteDatabaseImpl(url: databaseURL, lockName: nil)
        sqlite = db
        let graph = iTermGraphDatabase(database: db)
        graph.waitUntilReady()
        graphDatabase = graph
        return graph
    }

    private func update(_ graph: iTermGraphDatabase,
                        file: StaticString = #filePath,
                        line: UInt = #line,
                        _ block: (iTermGraphEncoder) -> Void) {
        let accepted = graph.updateSynchronously(true, block: block, completion: nil)
        XCTAssertTrue(accepted, "update was rejected", file: file, line: line)
    }

    private func nodeRows() throws -> [NodeRow] {
        let db = try XCTUnwrap(sqlite)
        let rs = try XCTUnwrap(db.executeQuery("select key, identifier, parent, rowid, data, generation from Node order by rowid",
                                               withArguments: []))
        defer { rs.close() }
        var rows = [NodeRow]()
        while rs.next() {
            let data = rs.data(forColumn: "data") ?? Data()
            let pod: NSDictionary
            if data.isEmpty {
                pod = [:]
            } else {
                pod = try XCTUnwrap(try (data as NSData).it_unarchivedObjectOfBasicClasses() as? NSDictionary)
            }
            rows.append(NodeRow(key: rs.string(forColumn: "key") ?? "",
                                identifier: rs.string(forColumn: "identifier") ?? "",
                                parent: rs.longLongInt(forColumn: "parent"),
                                rowid: rs.longLongInt(forColumn: "rowid"),
                                generation: rs.longLongInt(forColumn: "generation"),
                                pod: pod))
        }
        return rows
    }

    private func columnNames() throws -> [String] {
        let db = try XCTUnwrap(sqlite)
        let rs = try XCTUnwrap(db.executeQuery("PRAGMA table_info(Node)", withArguments: []))
        defer { rs.close() }
        var names = [String]()
        while rs.next() {
            names.append(rs.string(forColumn: "name") ?? "")
        }
        return names
    }

    private func serialize(_ pod: [String: Any]) throws -> Data {
        return NSData.it_data(withSecurelyArchivedObject: pod as NSDictionary, error: nil)
    }

    // Saves wrapper > mynode { World: Hello } into a fresh database and checks the rows.
    private func saveWrapperAndMynode() throws -> iTermGraphDatabase {
        let graph = openGraphDatabase()
        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 1) { wrapper in
                return wrapper.encodeChild(withKey: "mynode", identifier: "", generation: 1) { mynode in
                    mynode.encode("Hello", forKey: "World")
                    return true
                }
            }
        }
        XCTAssertEqual(try nodeRows(), [
            NodeRow(key: "", identifier: "", parent: 0, rowid: 1, generation: 1, pod: [:]),
            NodeRow(key: "wrapper", identifier: "", parent: 1, rowid: 2, generation: 1, pod: [:]),
            NodeRow(key: "mynode", identifier: "", parent: 2, rowid: 3, generation: 1, pod: ["World": "Hello"]),
        ])
        return graph
    }

    // MARK: - Initialization and loading

    func testInitializationCreatesNodeTableWithCurrentSchema() throws {
        _ = openGraphDatabase()
        let names = try columnNames()
        for expected in ["key", "identifier", "parent", "data", "generation", "large_data"] {
            XCTAssertTrue(names.contains(expected), "Missing column \(expected) in \(names)")
        }
        XCTAssertEqual(try nodeRows(), [])
    }

    func testLoadsRecordFromExistingLegacySchemaDatabase() throws {
        // Seed a database using the original four-column schema so loading also
        // exercises the migration that adds generation and large_data.
        let pod: [String: Any] = ["color": "red", "number": 123]
        do {
            let raw = iTermSqliteDatabaseImpl(url: databaseURL, lockName: nil)
            XCTAssertTrue(raw.lock())
            XCTAssertTrue(raw.open())
            try raw.executeUpdate("create table Node (key text not null, identifier text not null, parent integer not null, data blob)",
                                  withArguments: [])
            try raw.executeUpdate("insert into Node (key, identifier, parent, data) values (?, ?, ?, ?)",
                                  withArguments: ["", "", 0, Data()])
            try raw.executeUpdate("insert into Node (key, identifier, parent, data) values (?, ?, ?, ?)",
                                  withArguments: ["mynode", "", 1, try serialize(pod)])
            raw.close()
        }

        let graph = openGraphDatabase()
        XCTAssertTrue(try columnNames().contains("generation"))

        let mynode = iTermEncoderGraphRecord.withPODs(pod,
                                                      graphs: [],
                                                      generation: 0,
                                                      key: "mynode",
                                                      identifier: "",
                                                      rowid: 2)
        let expected = iTermEncoderGraphRecord.withPODs([:],
                                                        graphs: [mynode],
                                                        generation: 0,
                                                        key: "",
                                                        identifier: "",
                                                        rowid: 1)
        XCTAssertEqual(graph.record, expected)
    }

    // MARK: - Incremental saves

    func testFirstSaveInsertsEveryNode() throws {
        _ = try saveWrapperAndMynode()
    }

    func testDeletingChildRemovesItsRow() throws {
        let graph = try saveWrapperAndMynode()

        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 2) { _ in true }
        }

        XCTAssertEqual(try nodeRows(), [
            NodeRow(key: "", identifier: "", parent: 0, rowid: 1, generation: 2, pod: [:]),
            NodeRow(key: "wrapper", identifier: "", parent: 1, rowid: 2, generation: 2, pod: [:]),
        ])
    }

    func testInsertingSiblingAddsOnlyOneRow() throws {
        let graph = try saveWrapperAndMynode()

        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 2) { wrapper in
                _ = wrapper.encodeChild(withKey: "mynode", identifier: "", generation: 1) { mynode in
                    mynode.encode("Hello", forKey: "World")
                    return true
                }
                return wrapper.encodeChild(withKey: "othernode", identifier: "", generation: 1) { othernode in
                    othernode.encode("Goodbye", forKey: "Everybody")
                    return true
                }
            }
        }

        XCTAssertEqual(try nodeRows(), [
            NodeRow(key: "", identifier: "", parent: 0, rowid: 1, generation: 2, pod: [:]),
            NodeRow(key: "wrapper", identifier: "", parent: 1, rowid: 2, generation: 2, pod: [:]),
            NodeRow(key: "mynode", identifier: "", parent: 2, rowid: 3, generation: 1, pod: ["World": "Hello"]),
            NodeRow(key: "othernode", identifier: "", parent: 2, rowid: 4, generation: 1, pod: ["Everybody": "Goodbye"]),
        ])
    }

    func testChangingValueUpdatesRowInPlace() throws {
        let graph = try saveWrapperAndMynode()

        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 2) { wrapper in
                return wrapper.encodeChild(withKey: "mynode", identifier: "", generation: 2) { mynode in
                    mynode.encode("Goodbye", forKey: "World")
                    return true
                }
            }
        }

        XCTAssertEqual(try nodeRows(), [
            NodeRow(key: "", identifier: "", parent: 0, rowid: 1, generation: 2, pod: [:]),
            NodeRow(key: "wrapper", identifier: "", parent: 1, rowid: 2, generation: 2, pod: [:]),
            NodeRow(key: "mynode", identifier: "", parent: 2, rowid: 3, generation: 2, pod: ["World": "Goodbye"]),
        ])
    }

    func testAddingValueUpdatesRowInPlace() throws {
        let graph = try saveWrapperAndMynode()

        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 2) { wrapper in
                return wrapper.encodeChild(withKey: "mynode", identifier: "", generation: 2) { mynode in
                    mynode.encode("Hello", forKey: "World")
                    mynode.encode("Goodbye", forKey: "Everybody")
                    return true
                }
            }
        }

        let rows = try nodeRows()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.rowid, 3)
        XCTAssertEqual(rows.last?.generation, 2)
        XCTAssertEqual(rows.last?.pod, ["World": "Hello", "Everybody": "Goodbye"])
    }

    func testRemovingValueUpdatesRowWithEmptyData() throws {
        let graph = try saveWrapperAndMynode()

        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 2) { wrapper in
                return wrapper.encodeChild(withKey: "mynode", identifier: "", generation: 2) { _ in true }
            }
        }

        let rows = try nodeRows()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.rowid, 3)
        XCTAssertEqual(rows.last?.generation, 2)
        XCTAssertEqual(rows.last?.pod, [:])
    }

    func testUnchangedGenerationLeavesRowAlone() throws {
        let graph = try saveWrapperAndMynode()

        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "wrapper", identifier: "", generation: 1) { _ in
                XCTFail("Block should not run when the generation is unchanged")
                return true
            }
        }

        let rows = try nodeRows()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.pod, ["World": "Hello"])
    }

    // MARK: - Round trips through disk

    func testPropertyListRoundTripsThroughSQLite() throws {
        let root: [String: Any] = [
            "key": "value",
            "array": [3, 2, 1],
        ]
        let dict: NSDictionary = ["root": root]

        let graph = openGraphDatabase()
        update(graph) { encoder in
            encoder.encode(root, withKey: "root", generation: 1)
        }

        let reopened = openGraphDatabase()
        XCTAssertEqual(reopened.record.propertyListValue as? NSDictionary, dict)
    }

    func testManualArrayRoundTripsAndAppliesDeltaAfterReload() throws {
        let graph = openGraphDatabase()
        update(graph) { encoder in
            _ = encoder.encodeChild(withKey: "root", identifier: "", generation: 1) { root in
                root.encode("string", forKey: "STRING")
                root.encodeArray(withKey: "values", generation: 1, identifiers: ["i1", "i2"], options: []) { identifier, _, item, _ in
                    item.encode(String(repeating: identifier, count: 10), forKey: identifier)
                    return true
                }
                return true
            }
        }

        let reopened = openGraphDatabase()
        update(reopened) { encoder in
            _ = encoder.encodeChild(withKey: "root", identifier: "", generation: 2) { root in
                root.encode("string", forKey: "STRING")
                root.encodeArray(withKey: "values", generation: 2, identifiers: ["i2", "i3"], options: []) { identifier, _, item, _ in
                    item.encode(String(repeating: identifier, count: 10), forKey: identifier)
                    return true
                }
                return true
            }
        }

        // The root child has a nonzero generation and no identifier, so the implicit
        // dictionary also carries its generation under a suffixed key.
        let expected: NSDictionary = [
            "root": [
                "STRING": "string",
                "values": [
                    ["i2": "i2i2i2i2i2i2i2i2i2i2"],
                    ["i3": "i3i3i3i3i3i3i3i3i3i3"],
                ],
            ],
            "root" + iTermEncoderGraphRecordGenerationKeySuffix: 2,
        ]
        XCTAssertEqual(reopened.record.propertyListValue as? NSDictionary, expected)

        let reloaded = openGraphDatabase()
        XCTAssertEqual(reloaded.record.propertyListValue as? NSDictionary, expected)
    }

    private func journalMode() throws -> String {
        let db = try XCTUnwrap(sqlite)
        let rs = try XCTUnwrap(db.executeQuery("PRAGMA journal_mode", withArguments: []))
        defer { rs.close() }
        XCTAssertTrue(rs.next(), "PRAGMA journal_mode returned no row")
        return (rs.string(forColumn: "journal_mode") ?? "").lowercased()
    }

    // MARK: - Journal mode

    // iTermGraphDatabase createTables: (sources/StateRestoration/iTermGraphDatabase.m) issues
    // `PRAGMA journal_mode=WAL` through executeQuery and closes the result set without
    // calling next. FMDB's executeQuery only prepares and binds; sqlite3_step happens in
    // FMResultSet next, so the pragma never runs and a fresh database stays in the default
    // rollback-journal (delete) mode. Introduced by commit fc83f8a5c, which switched the
    // statement from executeUpdate (which did step) to executeQuery. doHousekeeping has the
    // same pattern for `pragma wal_checkpoint`.
    func testFreshDatabaseUsesWALJournalMode() throws {
        _ = openGraphDatabase()
        let mode = try journalMode()
        XCTExpectFailure("iTermGraphDatabase createTables: runs PRAGMA journal_mode=WAL via executeQuery without next, so the pragma never executes (commit fc83f8a5c)") {
            XCTAssertEqual(mode, "wal")
        }
    }

    // MARK: - iTermGraphEncoderAdapter

    func testAdapterArraysRoundTripThroughSQLite() throws {
        let myArray: NSArray = [2, 4, 6, 8]
        let arrayOfDicts: NSArray = [["x": "X"], ["y": "Y"]]

        let graph = openGraphDatabase()
        update(graph) { encoder in
            let adapter = iTermGraphEncoderAdapter(graphEncoder: encoder)
            adapter.setObject(myArray, forKey: "myArray")
            adapter.setObject(arrayOfDicts, forKey: "arrayOfDicts")
        }

        let reopened = openGraphDatabase()
        let plist = try XCTUnwrap(reopened.record.propertyListValue as? NSDictionary)
        XCTAssertEqual(plist["myArray"] as? NSArray, myArray)
        XCTAssertEqual(plist["arrayOfDicts"] as? NSArray, arrayOfDicts)
    }

    func testAdapterNestedDictionariesAndArraysRoundTripThroughSQLite() throws {
        let graph = openGraphDatabase()
        update(graph) { encoder in
            let adapter = iTermGraphEncoderAdapter(graphEncoder: encoder)
            adapter.encodeArray(withKey: "Tabs",
                                identifiers: ["tab1"],
                                generation: iTermGenerationAlwaysEncode) { tab, _, _, _ in
                return tab.encodeDictionary(withKey: "Root", generation: iTermGenerationAlwaysEncode) { root in
                    root.encodeArray(withKey: "Subviews",
                                     identifiers: ["view1"],
                                     generation: iTermGenerationAlwaysEncode) { subview, _, _, _ in
                        return subview.encodeDictionary(withKey: "session", generation: iTermGenerationAlwaysEncode) { session in
                            return session.encodeDictionary(withKey: "contents", generation: iTermGenerationAlwaysEncode) { contents in
                                contents.merge([
                                    "cll": [2, 4, 6, 8],
                                    "metadata": [1, "foo"],
                                ])
                                return true
                            }
                        }
                    }
                    return true
                }
            }
        }

        let reopened = openGraphDatabase()
        let plist = try XCTUnwrap(reopened.record.propertyListValue as? NSDictionary)
        let tabs = try XCTUnwrap(plist["Tabs"] as? [NSDictionary])
        let tab = try XCTUnwrap(tabs.first)
        let root = try XCTUnwrap(tab["Root"] as? NSDictionary)
        let subviews = try XCTUnwrap(root["Subviews"] as? [NSDictionary])
        let subview = try XCTUnwrap(subviews.first)
        let session = try XCTUnwrap(subview["session"] as? NSDictionary)
        let contents = try XCTUnwrap(session["contents"] as? NSDictionary)
        XCTAssertEqual(contents["cll"] as? NSArray, [2, 4, 6, 8])
        XCTAssertEqual(contents["metadata"] as? NSArray, [1, "foo"])
    }
}
