//
//  ChatListModel.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

struct Chat {
    var id = UUID().uuidString
    var title: String
    var creationDate = Date()
    var lastModifiedDate = Date()
    var sessionGuid: String?
}

extension Chat: iTermDatabaseElement {
    private enum Columns: String {
        case uuid
        case title
        case creationDate
        case lastModifiedDate
        case sessionGuid
    }
    static func schema() -> String {
        """
        create table if not exists Chat
            (\(Columns.uuid.rawValue) text,
             \(Columns.title.rawValue) text not null,
             \(Columns.creationDate.rawValue) integer not null,
             \(Columns.lastModifiedDate.rawValue) integer not null,
             \(Columns.sessionGuid.rawValue) text)
        """
    }

    static func fetchAllQuery() -> String {
        "select * from Chat order by \(Columns.lastModifiedDate) DESC"
    }

    func removeQuery() -> (String, [Any]) {
        ("delete from Chat where \(Columns.uuid.rawValue) = ?", [id])
    }

    func appendQuery() -> (String, [Any]) {
        ("""
        insert into Chat 
            (\(Columns.uuid.rawValue),
             \(Columns.title.rawValue), 
             \(Columns.creationDate.rawValue), 
             \(Columns.lastModifiedDate.rawValue), 
             \(Columns.sessionGuid.rawValue))
        values (?, ?, ?, ?, ?)
        """,
         [
            id,
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            sessionGuid ?? NSNull()
         ])
    }

    func updateQuery() -> (String, [Any]) {
        ("""
        update Chat set \(Columns.title.rawValue) = ?,
                        \(Columns.creationDate.rawValue) = ?,
                        \(Columns.lastModifiedDate.rawValue) = ?,
                        \(Columns.sessionGuid.rawValue) = ?
        where \(Columns.uuid.rawValue) = ?
        """,
        [
            title,
            creationDate.timeIntervalSince1970,
            lastModifiedDate.timeIntervalSince1970,
            sessionGuid ?? NSNull(),
            id
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let id = result.string(forColumn: Columns.uuid.rawValue),
              let title = result.string(forColumn: Columns.title.rawValue),
              let creationDate = result.date(forColumn: Columns.creationDate.rawValue),
              let lastModifiedDate = result.date(forColumn: Columns.lastModifiedDate.rawValue)
        else {
            return nil
        }
        self.id = id
        self.title = title
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.sessionGuid = result.string(forColumn: Columns.sessionGuid.rawValue)
    }
}

class ChatListModel: ChatListDataSource {
    static let metadataDidChange = Notification.Name("ChatListModelMetadataDidChange")
    private static var _instance: ChatListModel?
    static var instance: ChatListModel? {
        if _instance == nil {
            _instance =  ChatListModel()
        }
        return _instance
    }
    private var chatStorage: DatabaseBackedArray<Chat>
    private var messageStorage = [String: DatabaseBackedArray<Message>]()

    var count: Int { chatStorage.count }

    init?() {
        guard let chatDb = ChatDatabase.instance,
              let chats = chatDb.chats() else {
            return nil
        }
        chatStorage = chats
    }

    func numberOfChats(in chatListViewController: ChatListViewController) -> Int {
        return chatStorage.count
    }
    
    func chatListViewController(_ chatListViewController: ChatListViewController, chatAt index: Int) -> Chat {
        return chatStorage[index]
    }

    func chatListViewController(_ viewController: ChatListViewController,
                                indexOfChatID chatID: String) -> Int? {
        return index(of: chatID)
    }

    func add(chat: Chat) {
        chatStorage.prepend(chat)
        NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
    }

    private func bump(chatID: String) {
        if let i = chatStorage.firstIndex(where: { $0.id == chatID }) {
            var temp = chatStorage[i]
            chatStorage.remove(at: i)
            temp.lastModifiedDate = Date()
            chatStorage.prepend(temp)
            NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
        }
    }

    func messages(forChat chatID: String,
                  createIfNeeded: Bool) -> DatabaseBackedArray<Message>? {
        if let array = messageStorage[chatID] {
            return array
        }
        guard let db = ChatDatabase.instance else {
            return nil
        }
        if let array = db.messages(inChat: chatID) {
            messageStorage[chatID] = array
            return array
        }
        if createIfNeeded {
            let array = ChatDatabase.instance?.messages(inChat: chatID)
            messageStorage[chatID] = array
            return array
        }
        return nil
    }

    func index(ofMessageID messageID: UUID, inChat chatID: String) -> Int? {
        return messages(forChat: chatID,
                        createIfNeeded: false)?.firstIndex { $0.uniqueID == messageID }
    }

    func index(of chatID: String) -> Int? {
        return chatStorage.firstIndex {
            $0.id == chatID
        }
    }

    func setGuid(for chatID: String, to guid: String?) {
        if let i = index(of: chatID) {
            chatStorage[i].sessionGuid = guid
        }
    }

    func chat(id: String) -> Chat? {
        return chatStorage.first { $0.id == id }
    }

    func append(message: Message, toChatID chatID: String) {
        messages(forChat: chatID, createIfNeeded: true)?.append(message)
        bump(chatID: chatID)
    }

    func lastChat(guid: String) -> Chat? {
        return chatStorage.last { chat in
            chat.sessionGuid == guid
        }
    }
}

struct PersonChat: Hashable {
    var participant: Participant
    var chatID: String
}

class TypingStatusModel {
    static let instance = TypingStatusModel()

    private var typing = Set<PersonChat>()

    func set(isTyping: Bool, participant: Participant, chatID: String) {
        let pc = PersonChat(participant: participant, chatID: chatID)
        if isTyping {
            typing.insert(pc)
        } else {
            typing.remove(pc)
        }
    }

    func isTyping(participant: Participant, chatID: String) -> Bool {
        let pc = PersonChat(participant: participant, chatID: chatID)
        return typing.contains(pc)
    }
}
