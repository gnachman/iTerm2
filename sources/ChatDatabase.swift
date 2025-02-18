//
//  ChatDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 2/17/25.
//

class ChatDatabase {
    private static var _instance: ChatDatabase?
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

    init?(url: URL){
        db = iTermSqliteDatabaseImpl(url: url)
        if !db.lock() {
            #warning("TODO: Error handling")
            return nil
        }
        if !db.open() {
            return nil
        }

        if !createTables() {
            db.close()
            return
        }
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

    func chats() -> DatabaseBackedArray<Chat>? {
        return DatabaseBackedArray(db: db)
    }

    func messages(inChat chatID: String) -> DatabaseBackedArray<Message>? {
        let (query, args) = Message.query(forChatID: chatID)
        return DatabaseBackedArray(db: db,
                                   query: query,
                                   args: args)
    }
}

protocol iTermDatabaseElement {
    static func schema() -> String
    static func fetchAllQuery() -> String
    init?(dbResultSet: iTermDatabaseResultSet)
    func appendQuery() -> (String, [Any])
    func updateQuery() -> (String, [Any])
    func removeQuery() -> (String, [Any])
}

class DatabaseBackedArray<Element> where Element: iTermDatabaseElement {
    private var elements = [Element]()
    private let db: iTermDatabase

    var count: Int {
        elements.count
    }

    convenience init(db: iTermDatabase) {
        self.init(db: db, query: Element.fetchAllQuery(), args: [])
    }

    init(db: iTermDatabase, query: String, args: [Any]) {
        self.db = db
        if let resultSet = db.executeQuery(query, withArguments: args) {
            while resultSet.next() {
                if let element = Element(dbResultSet: resultSet) {
                    elements.append(element)
                }
            }
        }
    }

    subscript(_ i: Int) -> Element {
        get {
            elements[i]
        }
        set {
            elements[i] = newValue
            let (query, args) = newValue.updateQuery()
            db.executeUpdate(query, withArguments: args)
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
    }

    func insert(_ element: Element, atIndex i: Int) {
        let (query, args) = element.appendQuery()
        db.executeUpdate(query, withArguments: args)
        elements.insert(element, at: i)
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


