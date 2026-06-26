//
//  CompanionSyncWindowTests.swift
//  iTerm2 ModernTests
//
//  The DB primitives the contentless-wakeup floor logic rests on: the global
//  message window's ASC/DESC ordering (ASC drains oldest-first so a truncated
//  window never buries the tail; DESC is the first-run teaser), and the alert
//  store's ASC window + bounded prune. Exercised against a real on-disk chat DB.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionSyncWindowTests: XCTestCase {
    private func tempDB() throws -> ChatDatabase {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syncwin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
    }

    @discardableResult
    private func insert(_ database: ChatDatabase, chatID: String) throws -> UUID {
        let uuid = UUID()
        let msg = Message(chatID: chatID, author: .agent,
                          content: .markdown("body"), sentDate: Date(), uniqueID: uuid)
        let (sql, args) = msg.appendQuery()
        try database.db.executeUpdate(sql, withArguments: args)
        return uuid
    }

    func testGlobalWindowAscendingReturnsOldestAboveFloor() throws {
        let database = try tempDB()
        for _ in 0..<5 { try insert(database, chatID: "A") }   // seq 1..5 in insert order
        // ASC window of 3 above floor 0 -> the THREE LOWEST seqs, ascending.
        let asc = try XCTUnwrap(database.messagesSinceGlobal(sinceSeq: 0, windowLimit: 3, ascending: true))
        XCTAssertEqual(asc.rows.map(\.seq), [1, 2, 3], "ASC window returns the lowest seqs, oldest first")
        XCTAssertEqual(asc.maxSeq, 5, "maxSeq is the global tip regardless of the window")
        // The host advances the floor only to the window's covered max (3), so seq
        // 4 and 5 are NOT buried - the next fetch (seq > 3) returns them.
        let next = try XCTUnwrap(database.messagesSinceGlobal(sinceSeq: 3, windowLimit: 3, ascending: true))
        XCTAssertEqual(next.rows.map(\.seq), [4, 5], "the tail drains on the next window")
    }

    func testGlobalWindowDescendingIsTheFirstRunTeaser() throws {
        let database = try tempDB()
        for _ in 0..<5 { try insert(database, chatID: "A") }
        // DESC window of 2 -> the TWO HIGHEST seqs (newest first), for the first-run
        // teaser; the floor then jumps to the tip (maxSeq), skipping the backlog.
        let desc = try XCTUnwrap(database.messagesSinceGlobal(sinceSeq: 0, windowLimit: 2, ascending: false))
        XCTAssertEqual(desc.rows.map(\.seq), [5, 4])
        XCTAssertEqual(desc.maxSeq, 5)
    }

    func testGlobalWindowSpansChats() throws {
        let database = try tempDB()
        try insert(database, chatID: "A")   // 1
        try insert(database, chatID: "B")   // 2
        try insert(database, chatID: "A")   // 3
        let asc = try XCTUnwrap(database.messagesSinceGlobal(sinceSeq: 0, windowLimit: 10, ascending: true))
        XCTAssertEqual(asc.rows.map { $0.message.chatID }, ["A", "B", "A"])
        XCTAssertEqual(asc.rows.map(\.seq), [1, 2, 3])
    }

    func testAlertsAreReturnedOldestFirstAndCapped() throws {
        let database = try tempDB()
        for i in 0..<4 {
            let rec = CompanionAlertRecord(seq: 0, uniqueID: UUID(), threadKey: "s\(i)",
                                           title: "t\(i)", body: "b\(i)", createdDate: Date())
            XCTAssertNotNil(database.insertAlert(rec))
        }
        let win = try XCTUnwrap(database.alertsSince(sinceSeq: 0, limit: 2))
        XCTAssertEqual(win.alerts.map(\.threadKey), ["s0", "s1"], "alerts drain oldest-first (ASC)")
        XCTAssertEqual(win.maxSeq, 4, "maxSeq is the global alert tip")
        let next = try XCTUnwrap(database.alertsSince(sinceSeq: 2, limit: 10))
        XCTAssertEqual(next.alerts.map(\.threadKey), ["s2", "s3"], "the tail drains next window")
    }

    func testAlertInsertDedupesByUniqueID() throws {
        let database = try tempDB()
        let uuid = UUID()
        let rec = CompanionAlertRecord(seq: 0, uniqueID: uuid, threadKey: "s",
                                       title: "t", body: "b", createdDate: Date())
        let first = database.insertAlert(rec)
        let second = database.insertAlert(rec)   // same uniqueID
        XCTAssertEqual(first, second, "a retried enqueue of the same alert returns the existing seq")
        let all = try XCTUnwrap(database.alertsSince(sinceSeq: 0, limit: 10))
        XCTAssertEqual(all.alerts.count, 1, "no duplicate row")
    }

    func testAlertPruneKeepsNewest() throws {
        let database = try tempDB()
        for i in 0..<5 {
            let rec = CompanionAlertRecord(seq: 0, uniqueID: UUID(), threadKey: "s\(i)",
                                           title: "t", body: "b", createdDate: Date())
            database.insertAlert(rec, keepNewest: 3)
        }
        let all = try XCTUnwrap(database.alertsSince(sinceSeq: 0, limit: 10))
        XCTAssertEqual(all.alerts.map(\.threadKey), ["s2", "s3", "s4"], "prune keeps the newest `keepNewest`")
    }
}
