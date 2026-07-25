//
//  ChatBlobStorageTests.swift
//  iTerm2 ModernTests
//
//  Phase 1 of the blob-based chat reconstruction: the SQLite storage for
//  per-chat wire-fragment blobs (ChatBlob), plus the two columns that link and
//  key them (Chat.blobProtocol, Message.firstBlobRef). Proves the verbatim bytes
//  survive a round-trip byte-identically (a blob is opaque wire bytes, so any
//  corruption would silently poison a real request), that seq is a delete-immune
//  splice ordinal, that blobs are chat-scoped, that a protocol-switch re-freeze
//  swaps a chat's blobs atomically, and that the new columns migrate onto legacy
//  databases and bind in the insert/update paths (mirrors the agentReasoning /
//  icon column tests).
//

import XCTest
@testable import iTerm2SharedARC

final class ChatBlobStorageTests: XCTestCase {

    private func makeTempDB() throws -> ChatDatabase {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatblobtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
    }

    // MARK: - ChatBlob schema / insertQuery (no database)

    func testChatBlobSchema_declaresSeqAutoincrement() {
        let schema = ChatBlob.schema().lowercased()
        XCTAssertTrue(schema.contains("seq integer primary key autoincrement"),
                      "ChatBlob.schema must declare seq as INTEGER PRIMARY KEY AUTOINCREMENT; got: \(ChatBlob.schema())")
    }

    /// insertQuery must NOT bind seq (the engine assigns it), exactly like Message.
    func testChatBlobInsertQuery_doesNotBindSeq() {
        let blob = ChatBlob(chatID: "c", blobProtocol: .anthropic, role: .user,
                            payload: Data("hi".utf8))
        let (sql, _) = blob.insertQuery()
        guard let open = sql.firstIndex(of: "("),
              let close = sql[open...].firstIndex(of: ")") else {
            XCTFail("no column list in \(sql)"); return
        }
        let columns = sql[sql.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertFalse(columns.contains(ChatBlob.Columns.seq.rawValue),
                       "insertQuery must not bind seq (autoincrement assigns it); columns: \(columns)")
    }

    // MARK: - Live round-trip

    func testAppendBlob_roundTripsAllFieldsIncludingBinaryPayload() throws {
        let db = try makeTempDB()
        // Bytes that are NOT valid UTF-8 and include a NUL, so a TEXT column or a
        // string round-trip would corrupt them: this pins that payload is a real
        // BLOB carried verbatim.
        let payload = Data([0x00, 0xFF, 0x10, 0x89, 0x50, 0x4E, 0x47, 0x00, 0xC3, 0x28])
        let blobID = UUID()
        let blob = ChatBlob(blobID: blobID, chatID: "chatA", blobProtocol: .responses,
                            role: .assistant, payload: payload, responseID: "resp_123")
        let seq = try XCTUnwrap(db.appendBlob(blob), "appendBlob must return the assigned seq")
        XCTAssertGreaterThan(seq, 0)

        let loaded = db.blobs(inChat: "chatA")
        XCTAssertEqual(loaded.count, 1)
        let got = try XCTUnwrap(loaded.first)
        XCTAssertEqual(got.blobID, blobID)
        XCTAssertEqual(got.chatID, "chatA")
        XCTAssertEqual(got.blobProtocol, .responses)
        XCTAssertEqual(got.role, .assistant)
        XCTAssertEqual(got.responseID, "resp_123")
        XCTAssertEqual(got.seq, seq)
        XCTAssertEqual(got.payload, payload,
                       "payload bytes must survive verbatim; got \(Array(got.payload)) want \(Array(payload))")
    }

    func testAppendBlob_nilResponseID_roundTripsAsNil() throws {
        let db = try makeTempDB()
        let blob = ChatBlob(chatID: "c", blobProtocol: .anthropic, role: .user,
                            payload: Data("u".utf8))
        db.appendBlob(blob)
        XCTAssertNil(try XCTUnwrap(db.blobs(inChat: "c").first).responseID)
    }

    func testBlobs_orderedBySeq_andScopedByChat() throws {
        let db = try makeTempDB()
        // Interleave two chats. Splice order within a chat is capture order.
        let a1 = UUID(), a2 = UUID(), a3 = UUID(), b1 = UUID()
        func put(_ chat: String, _ id: UUID, _ role: ChatBlob.Role) {
            db.appendBlob(ChatBlob(blobID: id, chatID: chat, blobProtocol: .anthropic,
                                   role: role, payload: Data(id.uuidString.utf8)))
        }
        put("A", a1, .user)
        put("B", b1, .user)
        put("A", a2, .assistant)
        put("A", a3, .user)

        XCTAssertEqual(db.blobs(inChat: "A").map { $0.blobID }, [a1, a2, a3],
                       "a chat's blobs must load oldest-first by seq")
        XCTAssertEqual(db.blobs(inChat: "B").map { $0.blobID }, [b1],
                       "blobs must be chat-scoped")
        XCTAssertTrue(db.blobs(inChat: "ZZZ").isEmpty)
    }

    func testBlobSeq_strictlyIncreasesAndIsDeleteImmune() throws {
        let db = try makeTempDB()
        let a = UUID(), b = UUID()
        let seqA = try XCTUnwrap(db.appendBlob(ChatBlob(blobID: a, chatID: "A",
                                                        blobProtocol: .anthropic, role: .user,
                                                        payload: Data("a".utf8))))
        let seqB = try XCTUnwrap(db.appendBlob(ChatBlob(blobID: b, chatID: "A",
                                                        blobProtocol: .anthropic, role: .assistant,
                                                        payload: Data("b".utf8))))
        XCTAssertGreaterThan(seqB, seqA)

        // Delete the newest row, then insert. A bare rowid would reuse the freed
        // value; AUTOINCREMENT must not (fork/splice ordering depends on it).
        try db.db.executeUpdate("delete from ChatBlob where blobID = ?", withArguments: [b.uuidString])
        let c = UUID()
        let seqC = try XCTUnwrap(db.appendBlob(ChatBlob(blobID: c, chatID: "A",
                                                        blobProtocol: .anthropic, role: .user,
                                                        payload: Data("c".utf8))))
        XCTAssertGreaterThan(seqC, seqB,
                             "seq after deleting the top row must exceed the old max (no reuse)")
    }

    func testReplaceBlobs_atomicallySwapsAChatsSequence() throws {
        let db = try makeTempDB()
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .chatCompletions, role: .user,
                               payload: Data("old1".utf8)))
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .chatCompletions, role: .assistant,
                               payload: Data("old2".utf8)))
        db.appendBlob(ChatBlob(chatID: "B", blobProtocol: .chatCompletions, role: .user,
                               payload: Data("keepB".utf8)))

        // A protocol switch re-freezes chat A under .responses.
        let fresh = [
            ChatBlob(chatID: "A", blobProtocol: .responses, role: .user, payload: Data("new1".utf8)),
            ChatBlob(chatID: "A", blobProtocol: .responses, role: .assistant, payload: Data("new2".utf8)),
        ]
        db.replaceBlobs(inChat: "A", with: fresh)

        let a = db.blobs(inChat: "A")
        XCTAssertEqual(a.map { $0.payload }, [Data("new1".utf8), Data("new2".utf8)],
                       "replaceBlobs must drop the old sequence and install the new one")
        XCTAssertEqual(a.map { $0.blobProtocol }, [.responses, .responses])
        XCTAssertEqual(db.blobs(inChat: "B").map { $0.payload }, [Data("keepB".utf8)],
                       "replaceBlobs must not touch other chats")
    }

    // MARK: - Chat.blobProtocol column

    private static let preBlobChatColumns = [
        "uuid", "title", "creationDate", "lastModifiedDate", "orchestrationEnabled",
        "sessionGuid", "browserSessionGuid", "permissions", "vectorStore", "modelName",
        "claimedScopes", "watchers", "icon"
    ]

    func testChatSchema_declaresBlobProtocol() {
        XCTAssertTrue(Chat.schema().contains("blobProtocol"),
                      "schema must declare blobProtocol; got: \(Chat.schema())")
    }

    func testChatMigrations_addsBlobProtocol_whenMissing() {
        let migrations = Chat.migrations(existingColumns: Self.preBlobChatColumns)
        XCTAssertTrue(migrations.contains { $0.query.contains("blobProtocol") },
                      "migrations must add blobProtocol when missing")
    }

    func testChatMigrations_skipsBlobProtocol_whenPresent() {
        let migrations = Chat.migrations(existingColumns: Self.preBlobChatColumns + ["blobProtocol"])
        XCTAssertFalse(migrations.contains { $0.query.contains("blobProtocol") },
                       "migrations must not re-add blobProtocol (SQLite throws duplicate column)")
    }

    /// NULL (not yet blob-migrated) must be distinguishable from protocol 0
    /// (completions). Stored as TEXT so the result-set string accessor returns nil
    /// for NULL, where the integer accessor would return 0 for both.
    func testChatBlobProtocol_nilVsZero_persistDistinctly() throws {
        let db = try makeTempDB()
        var legacy = Chat(title: "legacy", permissions: "")
        legacy.blobProtocol = nil
        var native = Chat(title: "native", permissions: "")
        native.blobProtocol = iTermAIAPI.completions.rawValue == 0 ? 0 : Int(iTermAIAPI.completions.rawValue)
        for chat in [legacy, native] {
            let (sql, args) = chat.appendQuery()
            try db.db.executeUpdate(sql, withArguments: args)
        }
        func readBlobProtocol(uuid: String) throws -> Int?? {
            let rs = try XCTUnwrap(try db.db.executeQuery("select * from Chat where uuid=?",
                                                          withArguments: [uuid]))
            defer { rs.close() }
            guard rs.next(), let chat = Chat(dbResultSet: rs) else { return nil }
            return .some(chat.blobProtocol)
        }
        XCTAssertEqual(try readBlobProtocol(uuid: legacy.id), .some(nil),
                       "a nil blobProtocol must read back as nil (needs migration)")
        XCTAssertEqual(try readBlobProtocol(uuid: native.id), .some(0),
                       "protocol 0 (completions) must read back as 0, not be confused with NULL")
    }

    func testChatUpdateQuery_bindsBlobProtocol() {
        var chat = Chat(title: "t", permissions: "")
        chat.blobProtocol = Int(iTermAIAPI.anthropic.rawValue)
        let (sql, args) = chat.updateQuery()
        XCTAssertTrue(sql.contains("blobProtocol"), "updateQuery must set blobProtocol")
        XCTAssertTrue(args.contains { ($0 as? String) == String(Int(iTermAIAPI.anthropic.rawValue)) },
                      "updateQuery args must include the blobProtocol raw value; got: \(args)")
    }

    // MARK: - Message.firstBlobRef column

    func testMessageSchema_declaresFirstBlobRef() {
        XCTAssertTrue(Message.schema().contains("firstBlobRef"),
                      "schema must declare firstBlobRef; got: \(Message.schema())")
    }

    func testMessageMigrations_addsFirstBlobRef_whenMissing() {
        let migrations = Message.migrations(existingColumns: ["uniqueID", "author", "chatID",
                                                              "content", "sentDate", "responseID",
                                                              "agentReasoning", "seq"])
        XCTAssertTrue(migrations.contains { $0.query.contains("firstBlobRef") },
                      "migrations must add firstBlobRef when missing")
    }

    func testMessageMigrations_skipsFirstBlobRef_whenPresent() {
        let migrations = Message.migrations(existingColumns: ["uniqueID", "author", "chatID",
                                                              "content", "sentDate", "responseID",
                                                              "agentReasoning", "firstBlobRef", "seq"])
        XCTAssertFalse(migrations.contains { $0.query.contains("firstBlobRef") },
                       "migrations must not re-add firstBlobRef")
    }

    func testMessageFirstBlobRef_roundTrips() throws {
        let db = try makeTempDB()
        let ref = UUID().uuidString
        var msg = Message(chatID: "A", author: .agent, content: .markdown("hi"),
                          sentDate: Date(), uniqueID: UUID())
        msg.firstBlobRef = ref
        let (sql, args) = msg.appendQuery()
        try db.db.executeUpdate(sql, withArguments: args)

        let rs = try XCTUnwrap(try db.db.executeQuery("select * from Message where uniqueID=?",
                                                      withArguments: [msg.uniqueID.uuidString]))
        defer { rs.close() }
        XCTAssertTrue(rs.next())
        let loaded = try XCTUnwrap(Message(dbResultSet: rs))
        XCTAssertEqual(loaded.firstBlobRef, ref)
    }
}
