//
//  ChatListModel.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

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
              let chats = chatDb.chats else {
            return nil
        }
        chatStorage = chats
    }

    func chatSearchResultsIterator(query: String) -> AnySequence<ChatSearchResult> {
        return ChatDatabase.instance?.searchResultSequence(forQuery: query) ?? AnySequence([])
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

    func delete(chatID: String) throws {
        let i = chatStorage.firstIndex(where: {
            $0.id == chatID
        })
        guard let i else {
            return
        }
        try chatStorage.remove(at: i)
        NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
    }

    func add(chat: Chat) throws {
        try chatStorage.prepend(chat)
        NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
    }

    func setPermission(chat chatID: String,
                       permission: RemoteCommandExecutor.Permission,
                       guid: String,
                       category: RemoteCommand.Content.PermissionCategory) throws {
        let rce = RemoteCommandExecutor.instance
        rce.setPermission(chatID: chatID,
                          permission: permission,
                          guid: guid,
                          category: category)
        guard let i = self.index(of: chatID) else {
            return
        }
        var chat = chatStorage[i]
        chat.permissions = rce.encodedPermissions(chatID: chatID)
        try chatStorage.set(at: i, chat)
    }


    private func bump(chatID: String) throws {
        if let i = chatStorage.firstIndex(where: { $0.id == chatID }) {
            var temp = chatStorage[i]
            try chatStorage.remove(at: i)
            temp.lastModifiedDate = Date()
            try chatStorage.prepend(temp)
            NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
        }
    }

    private func rename(chatID: String, newName: String) throws {
        if let i = chatStorage.firstIndex(where: { $0.id == chatID }) {
            var temp = chatStorage[i]
            temp.title = newName
            try chatStorage.set(at: i, temp)
            NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
        }
    }

    private func setVectorStore(chatID: String, vectorStoreID: String) throws {
        if let i = chatStorage.firstIndex(where: { $0.id == chatID }) {
            var temp = chatStorage[i]
            temp.vectorStore = vectorStoreID
            try chatStorage.set(at: i, temp)
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

    func snippet(forChatID chatID: String) -> String? {
        if let array = messageStorage[chatID] {
            let message = array.last { $0.snippetText != nil }
            return message?.snippetText
        }
        guard let db = ChatDatabase.instance else {
            return nil
        }
        for message in db.messageReverseIterator(inChat: chatID) {
            if let snippet = message.snippetText {
                return snippet
            }
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

    func setTerminalGuid(for chatID: String, to guid: String?) throws {
        if let i = index(of: chatID) {
            try chatStorage.modify(at: i) { chat in
                chat.terminalSessionGuid = guid
            }
        }
    }

    func setBrowserGuid(for chatID: String, to guid: String?) throws {
        if let i = index(of: chatID) {
            try chatStorage.modify(at: i) { chat in
                chat.browserSessionGuid = guid
            }
        }
    }

    func chat(id: String) -> Chat? {
        let chat = chatStorage.first { $0.id == id }
        guard let chat else {
            return nil
        }
        RemoteCommandExecutor.instance.load(encodedPermissions: chat.permissions)
        return chat
    }

    func append(message: Message, toChatID chatID: String) throws {
        switch message.content {
        case let .append(string: chunk, uuid: uuid):
            if let i = index(ofMessageID: uuid, inChat: chatID),
               let messages =  messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                existing.append(chunk, useMarkdownIfAmbiguous: true)
                try messages.set(at: i, existing)
                return
            } else {
                DLog("Drop append “\(chunk)” of nonexistent message \(uuid)")
                return
            }
        case let .appendAttachment(attachment: attachment, uuid: uuid):
            if let i = index(ofMessageID: uuid, inChat: chatID),
               let messages =  messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                existing.append(attachment,
                                vectorStoreID: message.author == .user ? chat(id: chatID)?.vectorStore : nil)
                try messages.set(at: i, existing)
            } else {
                DLog("Drop append “\(attachment)” of nonexistent message \(uuid)")
            }
            return

        case let .explanationResponse(_, update, _):
            guard let update else {
                break
            }
            if let messageID = update.messageID,
               let i = index(ofMessageID: messageID, inChat: chatID),
               let messages =  messages(forChat: chatID, createIfNeeded: false) {
                var existing = messages[i]
                existing.content = message.content
                try messages.set(at: i, existing)
                return
            } else {
                DLog("Drop explanation response update \(update)")
                return
            }
        case .commit:
            return
        case .plainText, .markdown, .explanationRequest, .remoteCommandRequest,
                .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat,
                .setPermissions, .terminalCommand, .multipart, .vectorStoreCreated:
            break
        }
        try messages(forChat: chatID, createIfNeeded: true)?.append(message)
        switch message.content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .remoteCommandResponse, .selectSessionRequest, .clientLocal,
                .append, .commit, .setPermissions, .terminalCommand, .appendAttachment,
                .multipart:
            try bump(chatID: chatID)
        case .renameChat(let string):
            try rename(chatID: chatID, newName: string)
        case .vectorStoreCreated(let id):
            try setVectorStore(chatID: chatID, vectorStoreID: id)
        }
    }

    func lastChat(guid: String) -> Chat? {
        return chatStorage.last { chat in
            (chat.terminalSessionGuid == guid || chat.browserSessionGuid == guid)
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
