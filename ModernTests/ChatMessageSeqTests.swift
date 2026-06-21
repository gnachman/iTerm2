//
//  ChatMessageSeqTests.swift
//  iTerm2 ModernTests
//
//  The Message table's global, delete-immune `seq` column (INTEGER PRIMARY KEY
//  AUTOINCREMENT) that the relay-push watermark depends on. Covers the schema
//  declaration, that appendQuery leaves seq to the engine, the AUTOINCREMENT
//  delete-immunity guarantee on a live database, and the pre-seq -> seq
//  table-rebuild migration (column added, rows preserved, seq backfilled in
//  arrival order).
//

import XCTest
@testable import iTerm2SharedARC

final class ChatMessageSeqTests: XCTestCase {

    // MARK: - Schema / appendQuery (no database)

    func testMessageSchema_declaresSeqAutoincrement() {
        let schema = Message.schema().lowercased()
        XCTAssertTrue(schema.contains("seq integer primary key autoincrement"),
                      "schema must declare seq as INTEGER PRIMARY KEY AUTOINCREMENT; got: \(Message.schema())")
    }

    /// appendQuery must NOT list seq in its column list, so SQLite assigns it.
    func testMessageAppendQuery_doesNotBindSeq() {
        let msg = Message(chatID: "c", author: .user,
                          content: .markdown("hi"),
                          sentDate: Date(), uniqueID: UUID())
        let (sql, _) = msg.appendQuery()
        guard let open = sql.firstIndex(of: "("),
              let close = sql[open...].firstIndex(of: ")") else {
            XCTFail("no column list in \(sql)"); return
        }
        let columns = sql[sql.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertFalse(columns.contains(Message.Columns.seq.rawValue),
                       "appendQuery must not bind seq (autoincrement assigns it); columns: \(columns)")
    }

    // MARK: - Live database

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatseqtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func insertMessage(_ db: iTermDatabase, chatID: String, uniqueID: UUID) throws {
        let msg = Message(chatID: chatID, author: .user,
                          content: .markdown("body"),
                          sentDate: Date(), uniqueID: uniqueID)
        let (sql, args) = msg.appendQuery()
        try db.executeUpdate(sql, withArguments: args)
    }

    private func readSeqs(_ db: iTermDatabase) throws -> [(seq: Int64, uniqueID: String)] {
        guard let rs = try db.executeQuery("select seq, uniqueID from Message order by seq",
                                           withArguments: []) else { return [] }
        var out = [(seq: Int64, uniqueID: String)]()
        while rs.next() {
            out.append((rs.longLongInt(forColumn: "seq"),
                        rs.string(forColumn: "uniqueID") ?? ""))
        }
        rs.close()
        return out
    }

    func testSeq_strictlyIncreasesAndIsDeleteImmune() throws {
        let dir = try makeTempDir()
        let chatdb = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        let a = UUID(), b = UUID(), c = UUID()
        try insertMessage(chatdb.db, chatID: "chatA", uniqueID: a)
        try insertMessage(chatdb.db, chatID: "chatA", uniqueID: b)
        try insertMessage(chatdb.db, chatID: "chatA", uniqueID: c)

        var rows = try readSeqs(chatdb.db)
        XCTAssertEqual(rows.map { $0.uniqueID }, [a, b, c].map { $0.uuidString })
        XCTAssertTrue(zip(rows, rows.dropFirst()).allSatisfy { $0.seq < $1.seq },
                      "seq must strictly increase; got \(rows.map { $0.seq })")
        let maxBefore = rows.map { $0.seq }.max()!

        // Delete the newest (highest-seq) row, then insert. A bare rowid would
        // reuse the freed value; AUTOINCREMENT must not.
        try chatdb.db.executeUpdate("delete from Message where uniqueID = ?",
                                    withArguments: [c.uuidString])
        let d = UUID()
        try insertMessage(chatdb.db, chatID: "chatA", uniqueID: d)

        rows = try readSeqs(chatdb.db)
        let seqD = try XCTUnwrap(rows.first { $0.uniqueID == d.uuidString }).seq
        XCTAssertGreaterThan(seqD, maxBefore,
                             "seq after deleting the top row must exceed the old max (no reuse); got \(seqD) vs \(maxBefore)")
    }

    func testMigration_addsSeqAndBackfillsInRowidOrder() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("chatdb.sqlite")
        let a = UUID(), b = UUID(), c = UUID()

        // Phase 1: seed a pre-seq Message table (old schema) with rows.
        do {
            let raw = iTermSqliteDatabaseImpl(url: url, lockName: nil)
            XCTAssertTrue(raw.lock())
            XCTAssertTrue(raw.open())
            try raw.executeUpdate("""
                create table Message
                    (uniqueID text, author text not null, chatID text not null,
                     content text not null, sentDate integer not null,
                     responseID text, agentReasoning text)
                """, withArguments: [])
            for uid in [a, b, c] {
                try raw.executeUpdate("""
                    insert into Message (uniqueID, author, chatID, content, sentDate, responseID, agentReasoning)
                    values (?, ?, ?, ?, ?, ?, ?)
                    """, withArguments: [uid.uuidString, "user", "chatA",
                                         "{\"markdown\":{\"_0\":\"x\"}}", 1000.0, nil, nil])
            }
            raw.close()
        }

        // Phase 2: opening ChatDatabase runs the seq rebuild migration.
        let chatdb = try XCTUnwrap(ChatDatabase(url: url))
        let rows = try readSeqs(chatdb.db)
        XCTAssertEqual(rows.map { $0.uniqueID }, [a, b, c].map { $0.uuidString },
                       "rows must survive the rebuild in arrival (rowid) order")
        XCTAssertEqual(rows.map { $0.seq }, [1, 2, 3],
                       "seq must backfill 1..N in rowid order; got \(rows.map { $0.seq })")
    }

    func testMessagesSince_scopedNewestFirstWindowedWithMaxSeq() throws {
        let dir = try makeTempDir()
        let chatdb = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        // Interleave two chats so we exercise the chatID scope. Resulting seqs:
        // a1=1, b1=2, a2=3, a3=4.
        let a1 = UUID(), a2 = UUID(), a3 = UUID(), b1 = UUID()
        try insertMessage(chatdb.db, chatID: "A", uniqueID: a1)
        try insertMessage(chatdb.db, chatID: "B", uniqueID: b1)
        try insertMessage(chatdb.db, chatID: "A", uniqueID: a2)
        try insertMessage(chatdb.db, chatID: "A", uniqueID: a3)

        // All of A, newest first; maxSeq is A's tip (4), not B's.
        let all = try XCTUnwrap(chatdb.messagesSince(chatID: "A", sinceSeq: 0, windowLimit: 10))
        XCTAssertEqual(all.messages.map { $0.uniqueID }, [a3, a2, a1])
        XCTAssertEqual(all.maxSeq, 4)

        // windowLimit caps the row count (still newest first).
        let windowed = try XCTUnwrap(chatdb.messagesSince(chatID: "A", sinceSeq: 0, windowLimit: 2))
        XCTAssertEqual(windowed.messages.map { $0.uniqueID }, [a3, a2])

        // sinceSeq is a strict watermark: seq > 3 excludes a2 (seq 3) and a1.
        let since = try XCTUnwrap(chatdb.messagesSince(chatID: "A", sinceSeq: 3, windowLimit: 10))
        XCTAssertEqual(since.messages.map { $0.uniqueID }, [a3])

        // A chat with no rows is a SUCCESS with an empty result (not nil): a
        // non-nil ([], 0) is how the caller tells "genuinely empty" from a query
        // failure (which returns nil and must not be read as a rewind).
        let empty = try XCTUnwrap(chatdb.messagesSince(chatID: "ZZZ", sinceSeq: 0, windowLimit: 10),
                                  "an empty chat must return a non-nil empty result, not a failure")
        XCTAssertTrue(empty.messages.isEmpty)
        XCTAssertEqual(empty.maxSeq, 0)
    }
}
