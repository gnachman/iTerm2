//
//  ChatDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 2/17/25.
//

enum ChatDatabaseQueryError: Error {
    case nilResultSet
}

@objc(iTermChatDatabase)
class ObjCChatDatabase: NSObject {
    @objc static let redrawTerminalsNotification = Notification.Name("iTermChatDatabaseRedrawTerminals")

    @objc(chatIDsForSessionGuid:stableID:)
    static func chatIDsForSession(guid: String, stableID: String?) -> Set<String> {
        guard let instance = ChatDatabase.instanceIfExists else {
            return []
        }
        // A chat is indexed under whichever reference it stored (stableID or
        // legacy guid). The caller passes the session's own {guid, stableID}
        // pair, so this stays a plain map lookup on the draw hot path instead of
        // re-resolving the guid through the whole session tree.
        var result = Set<String>()
        for key in [guid, stableID].compactMap({ $0 }) {
            if let ids = instance.terminalSessionToChatMap[key] {
                result.formUnion(ids)
            }
        }
        return result
    }

    @objc(unlinkSessionGuid:)
    static func unlink(sessionGuid: String) {
        MainActor.assumeIsolated {
            guard let instance = ChatDatabase.instance,
            let chats = instance.chats else {
                return
            }
            let keys = iTermSessionReferenceKeys(forGuid: sessionGuid)
            for i in 0..<chats.count {
                let chat = chats[i]
                if chat.isLinked(toReferenceIn: keys) {
                    var temp = chats[i]
                    let wasTerminal = temp.terminalSessionGuid != nil
                    temp.terminalSessionGuid = nil
                    temp.browserSessionGuid = nil
                    do {
                        try chats.set(at: i, temp)
                        try? ChatBroker.instance?.publishNotice(
                            chatID: temp.id,
                            notice: "This chat is no longer linked to a \(wasTerminal ? "terminal" : "web browser") session.")
                    } catch {
                        DLog("\(error)")
                    }
                }
            }
        }
    }

    @objc(firstChatIDForSessionGuid:)
    static func firstChatID(forSessionGuid sessionGuid: String) -> String? {
        // Terminal-only: the sole caller (the "reveal AI chat for session" deep
        // link) passes a terminal session guid, so match only the terminal
        // binding (isLinked(toReferenceIn:) would also match browser bindings).
        let keys = iTermSessionReferenceKeys(forGuid: sessionGuid)
        return ChatDatabase.instance?.chats?.first {
            guard let terminal = $0.terminalSessionGuid else { return false }
            return keys.contains(terminal)
        }?.id
    }
}

class ChatDatabase {
    private static var _instance: ChatDatabase?
    static var instanceIfExists: ChatDatabase? { _instance }
    static var instance: ChatDatabase? {
        if let _instance {
            return _instance
        }
        let appDefaults = FileManager.default.applicationSupportDirectory()
        guard let appDefaults else {
            return nil
        }
        var url = URL(fileURLWithPath: appDefaults)
        url.appendPathComponent("chatdb.sqlite")
        _instance = ChatDatabase(url: url)
        return _instance
    }

    let db: iTermDatabase
    fileprivate var terminalSessionToChatMap = [String: Set<String>]()
    fileprivate var browserSessionToChatMap = [String: Set<String>]()

    init?(url: URL) {
        db = iTermSqliteDatabaseImpl(url: url, lockName: "chatdb-lock")
        if !db.lock() {
            return nil
        }
        if !db.open() {
            return nil
        }

        if !createTables() {
            RLog("FAILED TO CREATE TABLES, CLOSING CHAT DB at \(url.path)")
            db.close()
            return nil
        }
        popuplateSessionToChatMap()
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
        do {
            do {
                try db.executeUpdate(Chat.schema(), withArguments: [])
                let chatMigrations = Chat.migrations(existingColumns:
                                                         listColumns(
                                                             resultSet: try db.executeQuery(
                                                                 Chat.tableInfoQuery(),
                                                                 withArguments: [])))
                for migration in chatMigrations {
                    try db.executeUpdate(migration.query, withArguments: migration.args)
                }
            }

            try db.executeUpdate(Message.schema(), withArguments: [])

            do {
                // Read the existing columns once: it drives both the plain
                // ADD COLUMN migrations and the seq rebuild below. For a brand
                // new database schema() just created the table WITH seq, so this
                // already contains "seq" and the rebuild is skipped.
                let existingColumns = listColumns(
                    resultSet: try db.executeQuery(Message.tableInfoQuery(),
                                                   withArguments: []))
                let messageMigrations = Message.migrations(existingColumns: existingColumns)
                for migration in messageMigrations {
                    try db.executeUpdate(migration.query, withArguments: migration.args)
                }
                // The seq column (INTEGER PRIMARY KEY AUTOINCREMENT) cannot be
                // added with ALTER TABLE, so pre-seq databases need a table
                // rebuild. Run it AFTER the ADD COLUMN migrations above so the
                // copied rows already have responseID/agentReasoning.
                if !existingColumns.isEmpty && !existingColumns.contains(Message.Columns.seq.rawValue) {
                    try migrateAddSeqColumnToMessage()
                }
            }

            // Index the push path's per-chat scans (messagesSince window + maxSeq)
            // and the per-chat history fetch. Only seq (the PK) is indexed
            // otherwise, so these full-scan the Message table, growing with total
            // messages across all chats. IF NOT EXISTS: cheap on every open.
            try db.executeUpdate(
                "create index if not exists Message_chatID_seq on Message "
                + "(\(Message.Columns.chatID.rawValue), \(Message.Columns.seq.rawValue))",
                withArguments: [])

            // The contentless-wakeup push (revision >= 2) alert store. A separate
            // table with its own AUTOINCREMENT seq, so the phone tracks an alert
            // floor independent of the message floor.
            try db.executeUpdate(CompanionAlertRecord.schema(), withArguments: [])

            return true
        } catch {
            DLog("\(error)")
            return false
        }
    }

    // Rebuild the Message table to add the seq AUTOINCREMENT primary key
    // (SQLite forbids adding one with ALTER TABLE). The whole rebuild runs in
    // ONE transaction: SQLite DDL is transactional, so a crash or error
    // mid-migration rolls back to the intact original table rather than leaving
    // a half-built or emptied one. Rows are copied in rowid order so seq is
    // backfilled in arrival order; the engine assigns 1..N and tracks the max
    // in sqlite_sequence, so subsequent inserts never reuse a value.
    private func migrateAddSeqColumnToMessage() throws {
        let c = Message.Columns.self
        let copiedColumns = [
            c.uniqueID, c.author, c.chatID, c.content,
            c.sentDate, c.responseID, c.agentReasoning
        ].map { $0.rawValue }.joined(separator: ", ")
        // The SELECT coalesces the NOT NULL columns so a single legacy row with a
        // NULL (the old schema also declares these NOT NULL, so this shouldn't
        // exist, but a corrupt row would otherwise fail the INSERT and roll back
        // the whole migration - bricking the DB, since every reopen re-runs and
        // re-fails). A coerced bad row degrades gracefully instead.
        let selectColumns = [
            c.uniqueID.rawValue,
            "coalesce(\(c.author.rawValue), 'user')",
            "coalesce(\(c.chatID.rawValue), '')",
            "coalesce(\(c.content.rawValue), '')",
            "coalesce(\(c.sentDate.rawValue), 0)",
            c.responseID.rawValue,
            c.agentReasoning.rawValue
        ].joined(separator: ", ")
        // Throwing transaction: begins, runs the closure, commits; any throw
        // from executeUpdate rolls back and rethrows, so a failure leaves the
        // original Message table intact.
        do {
            try db.transaction {
                try db.executeUpdate("""
                    create table Message_new
                        (\(c.seq.rawValue) integer primary key autoincrement,
                         \(c.uniqueID.rawValue) text,
                         \(c.author.rawValue) text not null,
                         \(c.chatID.rawValue) text not null,
                         \(c.content.rawValue) text not null,
                         \(c.sentDate.rawValue) integer not null,
                         \(c.responseID.rawValue) text,
                         \(c.agentReasoning.rawValue) text)
                    """, withArguments: [])
                try db.executeUpdate("""
                    insert into Message_new (\(copiedColumns))
                    select \(selectColumns) from Message order by rowid
                    """, withArguments: [])
                try db.executeUpdate("drop table Message", withArguments: [])
                try db.executeUpdate("alter table Message_new rename to Message", withArguments: [])
            }
        } catch {
            // Surface loudly: a persistent failure here re-runs and re-fails on
            // every open, so the chat DB would never open again.
            RLog("Message seq migration FAILED (chat DB will not open): \(error)")
            throw error
        }
    }

    /// For the relay-push messagesSince responder: a newest-first window of a
    /// chat's messages with seq greater than `sinceSeq`, plus the chat's current
    /// max seq. Decodes Message rows (which ignore the seq column); the caller
    /// drops hidden rows and trims to previews. `windowLimit` over-fetches so
    /// hidden rows don't crowd out visible ones.
    ///
    /// Returns nil on a query FAILURE - distinct from a genuinely empty result
    /// (`([], 0)`). The caller must not treat a failure as an empty/rewound chat:
    /// a maxSeq of 0 from a transient error would otherwise look like a chat-DB
    /// rewind (seq > maxSeq) and force the phone's watermark down to 0.
    func messagesSince(chatID: String,
                       sinceSeq: Int64,
                       windowLimit: Int) -> (messages: [Message], maxSeq: Int64)? {
        var messages = [Message]()
        var maxSeqValue: Int64 = 0
        // One transaction so the window read and the maxSeq read are a single
        // snapshot. Otherwise a write between them could advance maxSeq past a
        // message not in the returned window, and the phone would advance its
        // watermark past an un-previewed message and never notify it. All callers
        // are @MainActor today, but this invariant must not rest on that.
        do {
            try db.transaction {
                let (sql, args) = Message.messagesSinceQuery(chatID: chatID, seq: sinceSeq, windowLimit: windowLimit)
                guard let rs = try db.executeQuery(sql, withArguments: args) else {
                    throw ChatDatabaseQueryError.nilResultSet
                }
                while rs.next() {
                    if let message = Message(dbResultSet: rs) {
                        messages.append(message)
                    }
                }
                rs.close()
                let (maxSQL, maxArgs) = Message.maxSeqQuery(chatID: chatID)
                guard let maxRS = try db.executeQuery(maxSQL, withArguments: maxArgs) else {
                    throw ChatDatabaseQueryError.nilResultSet
                }
                defer { maxRS.close() }
                if maxRS.next() {
                    maxSeqValue = maxRS.longLongInt(forColumn: "maxseq")
                }
            }
        } catch {
            // Surface the cause (e.g. a missing seq column if the migration were
            // ever skipped) so a phone that mysteriously stops getting previews is
            // diagnosable. Return nil (failure), NOT ([], 0): the caller must be
            // able to tell a transient error from an empty chat.
            RLog("Companion: messagesSince failed for chat \(chatID): \(error); returning nil")
            return nil
        }
        return (messages, maxSeqValue)
    }

    /// The chat's current max seq (0 if it has no messages or on a read error).
    func maxSeq(chatID: String) -> Int64 {
        let (sql, args) = Message.maxSeqQuery(chatID: chatID)
        do {
            guard let rs = try db.executeQuery(sql, withArguments: args) else { return 0 }
            defer { rs.close() }
            if rs.next() {
                return rs.longLongInt(forColumn: "maxseq")
            }
        } catch {
            RLog("Companion: maxSeq failed for chat \(chatID): \(error)")
        }
        return 0
    }

    // MARK: Contentless-wakeup (syncSince) reads

    /// Stateless "would the next syncSince return anything the NSE renders?" check,
    /// used by the wakeup coordinator INSTEAD of a drifting mac-side high-water mark.
    /// Reuses the ONE render predicate (Message.isCompanionRenderable) plus the
    /// caller's muted-chat set, and scans the SAME oldest-first window the responder
    /// drains, so "outstanding" here agrees with "the fetch shows something". Bounded
    /// by `windowLimit`: if more than that many non-renderable rows sit above the
    /// message floor before any renderable one, it under-reports (a later check or the
    /// next fetch catches it) - the same boundedness the responder's own window has.
    /// A failed/empty read is reported as "nothing" (no push; self-heals next time).
    func hasRenderableContentSince(messageSeq: Int64,
                                   alertSeq: Int64,
                                   mutedChatIDs: Set<String>,
                                   windowLimit: Int = 400) -> Bool {
        if let probe = messagesSinceGlobal(sinceSeq: max(messageSeq, 0),
                                           windowLimit: windowLimit,
                                           ascending: true) {
            let answered = Message.answeredRequestIDs(in: probe.rows.lazy.map { $0.message })
            for row in probe.rows where !mutedChatIDs.contains(row.message.chatID) {
                if row.message.isCompanionRenderable
                    && !row.message.isResolvedClassicRequest(answeredRequestIDs: answered) {
                    return true
                }
            }
        }
        // Any alert above the alert floor renders (alerts have no per-chat mute).
        if let alertProbe = alertsSince(sinceSeq: max(alertSeq, 0), limit: 1),
           !alertProbe.alerts.isEmpty {
            return true
        }
        return false
    }

    /// For the unified syncSince responder: a newest-first window of rows ACROSS
    /// ALL CHATS with seq greater than `sinceSeq`, each paired with its seq (the
    /// Message struct drops the seq column, but the per-chat watermark gate needs
    /// it), plus the global max seq. One transaction so the window and the max are
    /// a single snapshot (see messagesSince for why). Returns nil on FAILURE,
    /// distinct from an empty result.
    func messagesSinceGlobal(sinceSeq: Int64,
                             windowLimit: Int,
                             ascending: Bool) -> (rows: [(seq: Int64, message: Message)], maxSeq: Int64)? {
        var rows = [(seq: Int64, message: Message)]()
        var maxSeqValue: Int64 = 0
        do {
            try db.transaction {
                let (sql, args) = Message.messagesSinceGlobalQuery(seq: sinceSeq, windowLimit: windowLimit, ascending: ascending)
                guard let rs = try db.executeQuery(sql, withArguments: args) else {
                    throw ChatDatabaseQueryError.nilResultSet
                }
                while rs.next() {
                    if let message = Message(dbResultSet: rs) {
                        rows.append((seq: rs.longLongInt(forColumn: Message.Columns.seq.rawValue),
                                     message: message))
                    }
                }
                rs.close()
                let (maxSQL, maxArgs) = Message.maxSeqGlobalQuery()
                guard let maxRS = try db.executeQuery(maxSQL, withArguments: maxArgs) else {
                    throw ChatDatabaseQueryError.nilResultSet
                }
                defer { maxRS.close() }
                if maxRS.next() {
                    maxSeqValue = maxRS.longLongInt(forColumn: "maxseq")
                }
            }
        } catch {
            RLog("Companion: messagesSinceGlobal failed: \(error); returning nil")
            return nil
        }
        return (rows, maxSeqValue)
    }

    /// Append a terminal alert and return its assigned seq, pruning the store to a
    /// bounded size. Returns nil on failure. Dedups by uniqueID (a retried enqueue
    /// of the same alert is a no-op that returns the existing row's seq).
    @discardableResult
    func insertAlert(_ record: CompanionAlertRecord, keepNewest: Int = 200) -> Int64? {
        do {
            var assignedSeq: Int64 = 0
            try db.transaction {
                // Dedup: if a row with this uniqueID already exists, reuse its seq.
                let existing = try db.executeQuery(
                    "select \(CompanionAlertRecord.Columns.seq.rawValue) as seq from CompanionAlert where \(CompanionAlertRecord.Columns.uniqueID.rawValue)=?",
                    withArguments: [record.uniqueID.uuidString])
                if let existing, existing.next() {
                    assignedSeq = existing.longLongInt(forColumn: "seq")
                    existing.close()
                    return
                }
                existing?.close()
                let (sql, args) = record.insertQuery()
                try db.executeUpdate(sql, withArguments: args)
                assignedSeq = db.lastInsertRowId()?.int64Value ?? 0
                let (pruneSQL, pruneArgs) = CompanionAlertRecord.pruneQuery(keep: keepNewest)
                try db.executeUpdate(pruneSQL, withArguments: pruneArgs)
            }
            return assignedSeq
        } catch {
            RLog("Companion: insertAlert failed: \(error)")
            return nil
        }
    }

    /// Oldest-first (ASC) window of alerts with seq greater than `sinceSeq`, plus
    /// the store's max alert seq. ASC so the alert floor drains contiguously from
    /// the bottom. nil on failure (distinct from empty), like messagesSince.
    func alertsSince(sinceSeq: Int64,
                     limit: Int) -> (alerts: [CompanionAlertRecord], maxSeq: Int64)? {
        var alerts = [CompanionAlertRecord]()
        var maxSeqValue: Int64 = 0
        do {
            try db.transaction {
                let (sql, args) = CompanionAlertRecord.alertsSinceQuery(seq: sinceSeq, limit: limit)
                guard let rs = try db.executeQuery(sql, withArguments: args) else {
                    throw ChatDatabaseQueryError.nilResultSet
                }
                while rs.next() {
                    if let alert = CompanionAlertRecord(dbResultSet: rs) {
                        alerts.append(alert)
                    }
                }
                rs.close()
                let (maxSQL, maxArgs) = CompanionAlertRecord.maxSeqQuery()
                guard let maxRS = try db.executeQuery(maxSQL, withArguments: maxArgs) else {
                    throw ChatDatabaseQueryError.nilResultSet
                }
                defer { maxRS.close() }
                if maxRS.next() {
                    maxSeqValue = maxRS.longLongInt(forColumn: "maxseq")
                }
            }
        } catch {
            RLog("Companion: alertsSince failed: \(error); returning nil")
            return nil
        }
        return (alerts, maxSeqValue)
    }

    private func popuplateSessionToChatMap() {
        let sql =
        """
        SELECT
            \(Chat.Columns.terminalSessionGuid.rawValue),
            \(Chat.Columns.browserSessionGuid.rawValue),
            \(Chat.Columns.uuid.rawValue)
        FROM Chat
        WHERE
            \(Chat.Columns.terminalSessionGuid.rawValue) IS NOT NULL OR
            \(Chat.Columns.browserSessionGuid.rawValue) IS NOT NULL
        """
        do {
            guard let resultSet = try db.executeQuery(sql, withArguments: []) else {
                return
            }
            while resultSet.next() {
                if let terminalGuid = resultSet.string(forColumn: Chat.Columns.terminalSessionGuid.rawValue),
                      let chatID = resultSet.string(forColumn: Chat.Columns.uuid.rawValue) {
                    terminalSessionToChatMap[terminalGuid, default: Set()].insert(chatID)
                }
                if let browserGuid = resultSet.string(forColumn: Chat.Columns.browserSessionGuid.rawValue),
                      let chatID = resultSet.string(forColumn: Chat.Columns.uuid.rawValue) {
                    browserSessionToChatMap[browserGuid, default: Set()].insert(chatID)
                }
            }
        } catch {
            DLog("\(error)")
            return
        }
    }

    private var _chats: DatabaseBackedArray<Chat>?
    var chats: DatabaseBackedArray<Chat>? {
        if _chats == nil {
            guard let dba = try? DatabaseBackedArray<Chat>(db: db, query: Chat.fetchAllQuery()) else {
                return nil
            }
            dba.delegate = self
            _chats = dba
        }
        return _chats
    }

    func messages(inChat chatID: String) -> DatabaseBackedArray<Message>? {
        let (query, args) = Message.query(forChatID: chatID)
        return try? DatabaseBackedArray(db: db,
                                        query: query,
                                        args: args)
    }

    struct QueryIterator<T>: Sequence, IteratorProtocol where T: iTermDatabaseInitializable {
        fileprivate var resultSet: iTermDatabaseResultSet?
        mutating func next() -> T? {
            guard let resultSet else {
                return nil
            }
            if resultSet.next() {
                return T(dbResultSet: resultSet)
            }
            resultSet.close()
            self.resultSet = nil
            return nil
        }
        func makeIterator() -> any IteratorProtocol {
            return self
        }
    }
    typealias MessageIterator = QueryIterator<Message>

    func messageReverseIterator(inChat chatID: String) -> MessageIterator {
        let query = "SELECT * FROM Message WHERE chatID=? ORDER BY sentDate DESC"
        do {
            guard let resultSet = try db.executeQuery(query, withArguments: [chatID]) else {
                return MessageIterator(resultSet: nil)
            }
            return MessageIterator(resultSet: resultSet)
        } catch {
            DLog("\(error)")
            return MessageIterator(resultSet: nil)
        }
    }

    func searchResultSequence(forQuery query: String) -> AnySequence<ChatSearchResult> {
        return AnySequence {
            let tokens = query
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            let conditions = tokens.map { "content LIKE '%\($0)%'" }
            let whereClause = "WHERE " + conditions.joined(separator: " AND ")
            do {
                let resultSet = try self.db.executeQuery("SELECT * from MESSAGE \(whereClause)", withArguments: tokens)
                return QueryIterator<ChatSearchResult>(resultSet: resultSet)
            } catch {
                DLog("\(error)")
                return QueryIterator<ChatSearchResult>(resultSet: nil)
            }
        }
    }
}

extension ChatSearchResult: iTermDatabaseInitializable {
    init?(dbResultSet resultSet: any iTermDatabaseResultSet) {
        guard let chatID = resultSet.string(forColumn: Message.Columns.chatID.rawValue),
              let message = Message(dbResultSet: resultSet) else {
            return nil
        }
        self.chatID = chatID
        self.message = message
    }
}

extension ChatDatabase: DatabaseBackedArrayDelegate {
    func databaseBackedArray(didInsertElement chat: Chat) {
        if let guid = chat.terminalSessionGuid {
            terminalSessionToChatMap[guid, default: Set()].insert(chat.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
        if let guid = chat.browserSessionGuid {
            browserSessionToChatMap[guid, default: Set()].insert(chat.id)
        }
    }

    func databaseBackedArray(didRemoveElement chat: Chat) {
        if let guid = chat.terminalSessionGuid {
            terminalSessionToChatMap[guid]?.remove(chat.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
        if let guid = chat.browserSessionGuid {
            browserSessionToChatMap[guid]?.remove(chat.id)
        }
    }

    func databaseBackedArray(didModifyElement newValue: Chat, oldValue: Chat) {
        if let guid = oldValue.terminalSessionGuid {
            terminalSessionToChatMap[guid]?.remove(oldValue.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
        if let guid = newValue.terminalSessionGuid {
            terminalSessionToChatMap[guid, default: Set()].insert(newValue.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
        if let guid = oldValue.browserSessionGuid {
            browserSessionToChatMap[guid]?.remove(oldValue.id)
        }
        if let guid = newValue.browserSessionGuid {
            browserSessionToChatMap[guid, default: Set()].insert(newValue.id)
        }
    }
}

