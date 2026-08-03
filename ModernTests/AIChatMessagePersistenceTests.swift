//
//  AIChatMessagePersistenceTests.swift
//  iTerm2 ModernTests
//
//  Offline tests for chat-layer Message persistence of vendor-required
//  thinking state. DeepSeek v4 requires `reasoning_content` to be echoed back
//  on every subsequent request; iTerm2 stores it on the durable
//  `Message.agentReasoning` field (round-tripped through Codable JSON in
//  SQLite) and harvests streamed reasoning out of ephemeral statusUpdate
//  subparts in `removeReasoningStatusSubparts`. These tests anchor that contract so it
//  can't silently regress.
//

import XCTest
@testable import iTerm2SharedARC

final class AIChatMessagePersistenceTests: XCTestCase {

    // MARK: - Codable round-trip

    func testMessage_agentReasoning_survivesCodableRoundTrip() throws {
        var original = Message(
            chatID: "chat-123",
            author: .agent,
            content: .markdown("the visible reply"),
            sentDate: Date(timeIntervalSince1970: 1_700_000_000),
            uniqueID: UUID())
        original.agentReasoning = "I thought about this carefully."

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.agentReasoning, "I thought about this carefully.")
        XCTAssertEqual(decoded.chatID, "chat-123")
        XCTAssertEqual(decoded.author, .agent)
    }

    /// Old persisted chats (encoded before agentReasoning existed) must still
    /// decode cleanly with a nil agentReasoning. Hand-rolled JSON — NOT
    /// `JSONEncoder().encode(freshMessage)` — because the encode side would
    /// silently absorb a regression (e.g. switching from encodeIfPresent to
    /// encode would write `agentReasoning: null`, which the decoder still
    /// reads as nil, and the test would pass without exercising true legacy
    /// shape). The literal JSON below is what a build from before this
    /// change set could have written to disk.
    func testMessage_legacyJSON_decodesWithNilAgentReasoning() throws {
        let json = """
        {
            "chatID": "chat-456",
            "author": "agent",
            "content": {"markdown": {"_0": "legacy reply"}},
            "sentDate": 1600000000,
            "uniqueID": "550E8400-E29B-41D4-A716-446655440000"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Message.self, from: json)
        XCTAssertNil(decoded.agentReasoning)
        XCTAssertEqual(decoded.chatID, "chat-456")
        XCTAssertEqual(decoded.author, .agent)
    }

    // MARK: - Forward compatibility (unknown content types)

    /// A message whose content discriminator this build doesn't know (a
    /// newer iTerm2 added a Content or ClientLocal.Action case) must
    /// decode to .unsupported rather than throwing. Otherwise the
    /// Companion's whole-frame decode drops the message, and a history
    /// batch containing it loses every sibling too. Hand-rolled JSON in
    /// the exact synthesized enum shape ({"caseName": {...}}) with a case
    /// name no build emits.
    func testMessage_unknownContentType_decodesAsUnsupported() throws {
        let json = """
        {
            "chatID": "chat-fc",
            "author": "agent",
            "content": {"someFutureMessageType": {"_0": "payload this build can't read"}},
            "sentDate": 1700000000,
            "uniqueID": "550E8400-E29B-41D4-A716-446655440000"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Message.self, from: json)
        guard case .unsupported = decoded.content else {
            return XCTFail("expected .unsupported, got \(decoded.content)")
        }
        // The surrounding fields must still be intact so the placeholder
        // renders in the right place in the transcript.
        XCTAssertEqual(decoded.chatID, "chat-fc")
        XCTAssertEqual(decoded.author, .agent)
    }

    /// The history transport ships [Message]; decoding the array calls
    /// Message.init(from:) per element, so one unknown element must
    /// degrade to .unsupported while its siblings decode normally. This
    /// is the case that, without per-message tolerance, would blank out
    /// an entire chat's history on an older client.
    func testMessage_unknownContentInArray_preservesSiblings() throws {
        let json = """
        [
            {
                "chatID": "c",
                "author": "user",
                "content": {"plainText": {"_0": "before", "context": null}},
                "sentDate": 1700000000,
                "uniqueID": "11111111-1111-1111-1111-111111111111"
            },
            {
                "chatID": "c",
                "author": "agent",
                "content": {"someFutureMessageType": {}},
                "sentDate": 1700000001,
                "uniqueID": "22222222-2222-2222-2222-222222222222"
            },
            {
                "chatID": "c",
                "author": "agent",
                "content": {"markdown": {"_0": "after"}},
                "sentDate": 1700000002,
                "uniqueID": "33333333-3333-3333-3333-333333333333"
            }
        ]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([Message].self, from: json)
        XCTAssertEqual(decoded.count, 3)
        guard case .plainText(let before, _) = decoded[0].content else {
            return XCTFail("expected .plainText, got \(decoded[0].content)")
        }
        XCTAssertEqual(before, "before")
        guard case .unsupported = decoded[1].content else {
            return XCTFail("expected .unsupported, got \(decoded[1].content)")
        }
        guard case .markdown(let after) = decoded[2].content else {
            return XCTFail("expected .markdown, got \(decoded[2].content)")
        }
        XCTAssertEqual(after, "after")
    }

    /// The tolerant decoder must not weaken decoding of known content: a
    /// genuinely well-formed message still round-trips to its real case,
    /// not to .unsupported.
    func testMessage_knownContent_doesNotBecomeUnsupported() throws {
        let original = Message(
            chatID: "chat-known",
            author: .user,
            content: .plainText("hello", context: "ctx"),
            sentDate: Date(timeIntervalSince1970: 1_700_000_000),
            uniqueID: UUID())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        guard case .plainText(let text, let context) = decoded.content else {
            return XCTFail("expected .plainText, got \(decoded.content)")
        }
        XCTAssertEqual(text, "hello")
        XCTAssertEqual(context, "ctx")
    }

    // MARK: - Streaming harvest at removeReasoningStatusSubparts

    /// During streaming, reasoning arrives as one or more statusUpdate
    /// subparts. The first text chunk to arrive triggers removeReasoningStatusSubparts;
    /// the harvested reasoning must move into agentReasoning before the
    /// statusUpdate subparts are stripped, or the reasoning is lost from the
    /// persisted message and the next turn 400s.
    func testRemoveStatusUpdates_harvestsReasoningIntoAgentReasoning() {
        let part1 = LLM.Message.Attachment(
            inline: true,
            id: "deepseek-reasoning",
            type: .statusUpdate(.reasoningSummaryUpdate("First, ")))
        let part2 = LLM.Message.Attachment(
            inline: true,
            id: "deepseek-reasoning-2",
            type: .statusUpdate(.reasoningSummaryUpdate("then the conclusion.")))
        var message = Message(
            chatID: "chat-789",
            author: .agent,
            content: .multipart([
                .markdown("visible body"),
                .attachment(part1),
                .attachment(part2),
            ], vectorStoreID: nil),
            sentDate: Date(),
            uniqueID: UUID())

        message.removeReasoningStatusSubparts()

        XCTAssertEqual(message.agentReasoning, "First, then the conclusion.")
        // Status updates should be gone; visible body remains.
        guard case .multipart(let subparts, _) = message.content else {
            XCTFail("expected multipart, got \(message.content)")
            return
        }
        XCTAssertEqual(subparts.count, 1)
        if case .markdown(let body) = subparts[0] {
            XCTAssertEqual(body, "visible body")
        } else {
            XCTFail("expected markdown subpart, got \(subparts[0])")
        }
    }

    /// A second harvest must append, not replace. Streaming runs may emit
    /// status updates in batches, separated by removeReasoningStatusSubparts calls.
    func testRemoveStatusUpdates_appendsReasoningAcrossCalls() {
        let firstWave = LLM.Message.Attachment(
            inline: true,
            id: "deepseek-reasoning",
            type: .statusUpdate(.reasoningSummaryUpdate("wave one. ")))
        var message = Message(
            chatID: "chat-app",
            author: .agent,
            content: .multipart([.attachment(firstWave)], vectorStoreID: nil),
            sentDate: Date(),
            uniqueID: UUID())
        message.removeReasoningStatusSubparts()
        XCTAssertEqual(message.agentReasoning, "wave one. ")

        let secondWave = LLM.Message.Attachment(
            inline: true,
            id: "deepseek-reasoning-2",
            type: .statusUpdate(.reasoningSummaryUpdate("wave two.")))
        if case .multipart(let subparts, let vsid) = message.content {
            message.content = .multipart(subparts + [.attachment(secondWave)],
                                         vectorStoreID: vsid)
        }
        message.removeReasoningStatusSubparts()
        XCTAssertEqual(message.agentReasoning, "wave one. wave two.")
    }

    /// removeReasoningStatusSubparts must not invent agentReasoning when no
    /// reasoningSummaryUpdate subparts are present, even if other
    /// statusUpdate kinds (e.g. webSearchStarted) are.
    func testRemoveStatusUpdates_doesNotSetAgentReasoning_forUnrelatedStatusUpdates() {
        let webSearch = LLM.Message.Attachment(
            inline: true,
            id: "ws",
            type: .statusUpdate(.webSearchStarted))
        var message = Message(
            chatID: "chat-ws",
            author: .agent,
            content: .multipart([.attachment(webSearch)], vectorStoreID: nil),
            sentDate: Date(),
            uniqueID: UUID())
        message.removeReasoningStatusSubparts()
        XCTAssertNil(message.agentReasoning)
    }

    // MARK: - SQLite round-trip

    /// The schema must declare an agentReasoning column, otherwise the
    /// migration / appendQuery / updateQuery / init?(dbResultSet:) plumbing
    /// targets a non-existent column.
    func testMessageSchema_declaresAgentReasoningColumn() {
        let schema = Message.schema()
        XCTAssertTrue(schema.contains("agentReasoning"),
                      "schema must declare agentReasoning column; got: \(schema)")
    }

    /// Existing databases (without an agentReasoning column) must get a
    /// migration step that adds it. Without this migration step, upgrades
    /// from an iTerm2 build that predates this change would fail to persist
    /// reasoning even though the new code writes to the column.
    func testMessageMigrations_addsAgentReasoning_whenColumnMissing() {
        let migrations = Message.migrations(existingColumns: ["uniqueID", "author", "chatID", "content", "sentDate", "responseID"])
        XCTAssertTrue(migrations.contains { $0.query.contains("agentReasoning") },
                      "migrations must add agentReasoning when missing; got: \(migrations.map { $0.query })")
    }

    /// And the migration must NOT re-add the column on databases that
    /// already have it (otherwise SQLite throws "duplicate column name").
    func testMessageMigrations_skipsAgentReasoning_whenColumnPresent() {
        let migrations = Message.migrations(existingColumns: ["uniqueID", "author", "chatID", "content", "sentDate", "responseID", "agentReasoning"])
        XCTAssertFalse(migrations.contains { $0.query.contains("agentReasoning") },
                       "migrations must not re-add agentReasoning when already present")
    }

    /// appendQuery() must emit the agentReasoning value as a bound parameter
    /// — otherwise on first persist the value is lost even with the column
    /// present.
    func testMessageAppendQuery_bindsAgentReasoning() {
        var msg = Message(
            chatID: "chat-x",
            author: .agent,
            content: .markdown("hello"),
            sentDate: Date(),
            uniqueID: UUID())
        msg.agentReasoning = "the saved reasoning"
        let (sql, args) = msg.appendQuery()
        XCTAssertTrue(sql.contains("agentReasoning"),
                      "appendQuery must reference the agentReasoning column; got: \(sql)")
        XCTAssertTrue(args.contains { ($0 as? String) == "the saved reasoning" },
                      "appendQuery args must include the agentReasoning value; got: \(args)")
    }

    /// updateQuery() must also bind agentReasoning so subsequent UPDATEs
    /// don't silently drop the value back to NULL when the rest of the row
    /// is touched.
    func testMessageUpdateQuery_bindsAgentReasoning() {
        var msg = Message(
            chatID: "chat-y",
            author: .agent,
            content: .markdown("hello"),
            sentDate: Date(),
            uniqueID: UUID())
        msg.agentReasoning = "updated reasoning"
        let (sql, args) = msg.updateQuery()
        XCTAssertTrue(sql.contains("agentReasoning"),
                      "updateQuery must reference the agentReasoning column; got: \(sql)")
        XCTAssertTrue(args.contains { ($0 as? String) == "updated reasoning" },
                      "updateQuery args must include the agentReasoning value; got: \(args)")
    }

    /// And nil agentReasoning must serialize as NULL (Swift's optional-to-Any
    /// boxing in the args array), not as the literal string "nil" or be
    /// silently elided. This protects messages from old chats that have no
    /// reasoning from inadvertently inheriting some neighbor's value.
    func testMessageAppendQuery_bindsNilAgentReasoning_whenUnset() throws {
        let msg = Message(
            chatID: "chat-z",
            author: .user,
            content: .plainText("hi", context: nil),
            sentDate: Date(),
            uniqueID: UUID())
        let arg = try Self.appendQueryArg(msg, forColumn: "agentReasoning")
        XCTAssertNil(arg as? String,
                     "agentReasoning must serialize as nil when unset; got: \(String(describing: arg))")
    }

    /// Extracts the bound arg for a named column from appendQuery() by
    /// parsing the column list out of the INSERT SQL. Robust to column
    /// reordering or future columns being added — a positional `args[6]`
    /// check would silently shift its meaning.
    private static func appendQueryArg(_ message: Message, forColumn name: String) throws -> Any? {
        let (sql, args) = message.appendQuery()
        guard let listStart = sql.firstIndex(of: "("),
              let listEnd = sql[listStart...].firstIndex(of: ")") else {
            throw NSError(domain: "appendQueryArg", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not find column list in SQL: \(sql)"])
        }
        let columnList = sql[sql.index(after: listStart)..<listEnd]
        let columns = columnList.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let index = columns.firstIndex(of: name) else {
            throw NSError(domain: "appendQueryArg", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "no \(name) column in: \(columns)"])
        }
        guard index < args.count else {
            throw NSError(domain: "appendQueryArg", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "args (count=\(args.count)) shorter than column list (count=\(columns.count))"])
        }
        return args[index]
    }

    /// Reload path: init?(dbResultSet:) must read the agentReasoning column
    /// off the result set and store it on the reconstructed Message.
    /// Without this, persisted reasoning never reaches reloaded conversations.
    func testMessageInitDbResultSet_readsAgentReasoning() throws {
        let uniqueID = UUID()
        let sentDate = Date(timeIntervalSince1970: 1_700_000_000)
        let contentData = try JSONEncoder().encode(Message.Content.markdown("body"))
        let contentJSON = String(data: contentData, encoding: .utf8)!
        let result = FakeMessageResultSet(values: [
            "uniqueID": uniqueID.uuidString,
            "author": Participant.agent.rawValue,
            "chatID": "chat-r",
            "content": contentJSON,
            "responseID": nil,
            "agentReasoning": "reloaded reasoning",
        ], dates: [
            "sentDate": sentDate
        ])
        let msg = try XCTUnwrap(Message(dbResultSet: result))
        XCTAssertEqual(msg.agentReasoning, "reloaded reasoning")
    }

    /// And missing agentReasoning (column present but NULL) must decode as
    /// nil, not crash. Covers pre-migration rows in upgraded databases.
    func testMessageInitDbResultSet_acceptsMissingAgentReasoning() throws {
        let uniqueID = UUID()
        let sentDate = Date(timeIntervalSince1970: 1_700_000_001)
        let contentData = try JSONEncoder().encode(Message.Content.markdown("body"))
        let contentJSON = String(data: contentData, encoding: .utf8)!
        let result = FakeMessageResultSet(values: [
            "uniqueID": uniqueID.uuidString,
            "author": Participant.agent.rawValue,
            "chatID": "chat-r2",
            "content": contentJSON,
            "responseID": nil,
            "agentReasoning": nil,
        ], dates: [
            "sentDate": sentDate
        ])
        let msg = try XCTUnwrap(Message(dbResultSet: result))
        XCTAssertNil(msg.agentReasoning)
    }
}

/// Minimal iTermDatabaseResultSet stub for offline tests. Only implements the
/// reading methods Message.init?(dbResultSet:) calls; the rest are
/// unreachable in this context and trap if invoked, which catches future
/// regressions where the init path starts depending on more of the protocol.
final class FakeMessageResultSet: NSObject, iTermDatabaseResultSet {
    private let values: [String: String?]
    private let dates: [String: Date]

    init(values: [String: String?], dates: [String: Date]) {
        self.values = values
        self.dates = dates
    }

    func next() -> Bool { false }
    func close() {}

    func string(forColumn columnName: String) -> String? {
        // Treat "column entry exists with nil value" and "column entry
        // absent" both as NULL — matches FMResultSet's stringForColumn
        // behavior, which returns nil in both cases.
        values[columnName] ?? nil
    }

    func longLongInt(forColumn columnName: String) -> Int64 {
        it_fatalError("longLongInt not stubbed for column \(columnName)")
    }

    func data(forColumn columnName: String) -> Data? {
        it_fatalError("data not stubbed for column \(columnName)")
    }

    func date(forColumn columnName: String) -> Date? {
        dates[columnName]
    }
}
