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

    init?(url: URL){
        db = iTermSqliteDatabaseImpl(url: url, lockName: "chatdb-lock")
        if !db.lock() {
            return nil
        }
        if !db.open() {
            return nil
        }

        if !createTables() {
            DLog("FAILED TO CREATE TABLES, CLOSING CHAT DB")
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
                let migrations = Chat.migrations(existingColumns:
                                                    listColumns(
                                                        resultSet: try db.executeQuery(
                                                            Chat.tableInfoQuery(),
                                                            withArguments: [])))
                for migration in migrations {
                    try db.executeUpdate(migration.query, withArguments: migration.args)
                }
            }
            
            do {
                try db.executeUpdate(Message.schema(), withArguments: [])
                let migrations = Message.migrations(existingColumns:
                                                    listColumns(
                                                        resultSet: try db.executeQuery(
                                                            Message.tableInfoQuery(),
                                                            withArguments: [])))
                for migration in migrations {
                    try db.executeUpdate(migration.query, withArguments: migration.args)
                }
            }
            try db.executeUpdate(Message.schema(), withArguments: [])

            return true
        } catch {
            DLog("\(error)")
            return false
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
    }
    
    func databaseBackedArray(didRemoveElement chat: Chat) {
        if let guid = chat.terminalSessionGuid {
            terminalSessionToChatMap[guid]?.remove(chat.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
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
    }
}

