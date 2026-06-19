//
//  ChatDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 2/17/25.
//

@objc(iTermChatDatabase)
class ObjCChatDatabase: NSObject {
    @objc static let redrawTerminalsNotification = Notification.Name("iTermChatDatabaseRedrawTerminals")

    @objc(chatIDsForSession:)
    static func chatIDsForSession(withGUID guid: String) -> Set<String> {
        guard let instance = ChatDatabase.instanceIfExists else {
            return []
        }
        return instance.terminalSessionToChatMap[guid] ?? Set()
    }

    @objc(unlinkSessionGuid:)
    static func unlink(sessionGuid: String) {
        MainActor.assumeIsolated {
            guard let instance = ChatDatabase.instance,
            let chats = instance.chats else {
                return
            }
            for i in 0..<chats.count {
                let chat = chats[i]
                if chat.terminalSessionGuid == sessionGuid || chat.browserSessionGuid == sessionGuid {
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
        return ChatDatabase.instance?.chats?.first { $0.terminalSessionGuid == sessionGuid }?.id
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
            DLog("FAILED TO CREATE TABLES, CLOSING CHAT DB at \(url.path)")
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
        // Throwing transaction: begins, runs the closure, commits; any throw
        // from executeUpdate rolls back and rethrows, so a failure leaves the
        // original Message table intact.
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
                select \(copiedColumns) from Message order by rowid
                """, withArguments: [])
            try db.executeUpdate("drop table Message", withArguments: [])
            try db.executeUpdate("alter table Message_new rename to Message", withArguments: [])
        }
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

