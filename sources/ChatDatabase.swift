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
        return instance.sessionToChatMap[guid] ?? Set()
    }

    @objc(unlinkSessionGuid:)
    static func unlink(sessionGuid: String) {
        guard let instance = ChatDatabase.instance,
        let chats = instance.chats else {
            return
        }
        for i in 0..<chats.count {
            let chat = chats[i]
            if chat.sessionGuid == sessionGuid {
                var temp = chats[i]
                temp.sessionGuid = nil
                chats[i] = temp
                ChatBroker.instance?.publishNotice(
                    chatID: temp.id,
                    notice: "This chat is no longer linked to a terminal session.")
            }
        }
    }

    @objc(firstChatIDForSessionGuid:)
    static func firstChatID(forSessionGuid sessionGuid: String) -> String? {
        return ChatDatabase.instance?.chats?.first { $0.sessionGuid == sessionGuid }?.id
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
    fileprivate var sessionToChatMap = [String: Set<String>]()

    init?(url: URL){
        db = iTermSqliteDatabaseImpl(url: url)
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

    private func createTables() -> Bool {
        if !db.executeUpdate(Chat.schema(), withArguments: []) {
            return false
        }
        if !db.executeUpdate(Message.schema(), withArguments: []) {
            return false
        }

        return true
    }

    private func popuplateSessionToChatMap() {
        let sql =
        """
        SELECT
            \(Chat.Columns.sessionGuid),
            \(Chat.Columns.uuid.rawValue)
        FROM Chat
        WHERE
            \(Chat.Columns.sessionGuid.rawValue) IS NOT NULL
        """
        guard let resultSet = db.executeQuery(sql, withArguments: []) else {
            return
        }
        while resultSet.next() {
            guard let guid = resultSet.string(forColumn: Chat.Columns.sessionGuid.rawValue),
                  let chatID = resultSet.string(forColumn: Chat.Columns.uuid.rawValue) else {
                continue
            }
            sessionToChatMap[guid, default: Set()].insert(chatID)
        }
    }

    private var _chats: DatabaseBackedArray<Chat>?
    var chats: DatabaseBackedArray<Chat>? {
        if _chats == nil {
            let dba = DatabaseBackedArray<Chat>(db: db)
            dba.delegate = self
            _chats = dba
        }
        return _chats
    }

    func messages(inChat chatID: String) -> DatabaseBackedArray<Message>? {
        let (query, args) = Message.query(forChatID: chatID)
        return DatabaseBackedArray(db: db,
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
        guard let resultSet = db.executeQuery(query, withArguments: [chatID]) else {
            return MessageIterator(resultSet: nil)
        }
        return MessageIterator(resultSet: resultSet)
    }

    func searchResultSequence(forQuery query: String) -> AnySequence<ChatSearchResult> {
        return AnySequence {
            let tokens = query
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            let conditions = tokens.map { "content LIKE '%\($0)%'" }
            let whereClause = "WHERE " + conditions.joined(separator: " AND ")
            let resultSet = self.db.executeQuery("SELECT * from MESSAGE \(whereClause)", withArguments: tokens)
            return QueryIterator<ChatSearchResult>(resultSet: resultSet)
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
        if let guid = chat.sessionGuid {
            sessionToChatMap[guid, default: Set()].insert(chat.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
    }
    
    func databaseBackedArray(didRemoveElement chat: Chat) {
        if let guid = chat.sessionGuid {
            sessionToChatMap[guid]?.remove(chat.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
    }
    
    func databaseBackedArray(didModifyElement newValue: Chat, oldValue: Chat) {
        if let guid = oldValue.sessionGuid {
            sessionToChatMap[guid]?.remove(oldValue.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
        if let guid = newValue.sessionGuid {
            sessionToChatMap[guid, default: Set()].insert(newValue.id)
            NotificationCenter.default.post(name: ObjCChatDatabase.redrawTerminalsNotification, object: nil)
        }
    }
}

protocol iTermDatabaseInitializable {
    init?(dbResultSet: iTermDatabaseResultSet)
}

protocol iTermDatabaseElement: iTermDatabaseInitializable {
    static func schema() -> String
    static func fetchAllQuery() -> String
    func appendQuery() -> (String, [Any])
    func updateQuery() -> (String, [Any])
    func removeQuery() -> (String, [Any])
}

protocol DatabaseBackedArrayDelegate<Element>: AnyObject where Element: iTermDatabaseElement {
    associatedtype Element: iTermDatabaseElement
    func databaseBackedArray(didModifyElement: Element, oldValue: Element)
    func databaseBackedArray(didInsertElement: Element)
    func databaseBackedArray(didRemoveElement: Element)
}

class DatabaseBackedArray<Element> where Element: iTermDatabaseElement {
    private var elements = [Element]()
    private let db: iTermDatabase
    weak var delegate: (any DatabaseBackedArrayDelegate<Element>)?

    var count: Int {
        elements.count
    }
    var isEmpty: Bool { count == 0 }
    
    fileprivate convenience init(db: iTermDatabase) {
        self.init(db: db, query: Element.fetchAllQuery(), args: [])
    }

    fileprivate init(db: iTermDatabase, query: String, args: [Any]) {
        self.db = db
        if let resultSet = db.executeQuery(query, withArguments: args) {
            while resultSet.next() {
                if let element = Element(dbResultSet: resultSet) {
                    elements.append(element)
                }
            }
            resultSet.close()
        }
    }

    subscript(_ i: Int) -> Element {
        get {
            elements[i]
        }
        set {
            let oldValue = elements[i]
            elements[i] = newValue
            let (query, args) = newValue.updateQuery()
            db.executeUpdate(query, withArguments: args)
            delegate?.databaseBackedArray(didModifyElement: newValue, oldValue: oldValue)
        }
    }

    func append(_ element: Element) {
        insert(element, atIndex: elements.count)
    }

    func prepend(_ element: Element) {
        insert(element, atIndex: 0)
    }

    func remove(at i: Int) {
        let element = elements[i]
        let (query, args) = element.removeQuery()
        db.executeUpdate(query, withArguments: args)
        elements.remove(at: i)
        delegate?.databaseBackedArray(didRemoveElement: element)
    }

    func insert(_ element: Element, atIndex i: Int) {
        let (query, args) = element.appendQuery()
        db.executeUpdate(query, withArguments: args)
        elements.insert(element, at: i)
        delegate?.databaseBackedArray(didInsertElement: element)
    }

    func firstIndex(where test: (Element) -> Bool) -> Int? {
        return elements.firstIndex(where: test)
    }

    func first(where test: (Element) -> Bool) -> Element? {
        return elements.first(where: test)
    }
    func last(where test: (Element) -> Bool) -> Element? {
        return elements.last(where: test)
    }
}

extension DatabaseBackedArray: Sequence {
    func makeIterator() -> IndexingIterator<[Element]> {
        return elements.makeIterator()
    }
}


