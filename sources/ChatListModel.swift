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
    var messages: [Message]
    var sessionGuid: String?
}

class ChatListModel: ChatListDataSource {
    static let metadataDidChange = Notification.Name("ChatListModelMetadataDidChange")
    static let instance = ChatListModel()
    private var storage = [Chat]()

    func numberOfChats(in chatListViewController: ChatListViewController) -> Int {
        return storage.count
    }
    
    func chatListViewController(_ chatListViewController: ChatListViewController, chatAt index: Int) -> Chat {
        return storage[index]
    }
    
    func add(chat: Chat) {
        storage.append(chat)
        NotificationCenter.default.post(name: Self.metadataDidChange, object: nil)
    }

    func chat(id: String) -> Chat? {
        return storage.first { $0.id == id }
    }

    func append(messages: [Message], toChatID chatID: String) {
        guard let i = storage.firstIndex(where: { $0.id == chatID }) else {
            return
        }
        storage[i].messages += messages
    }

    func lastChat(guid: String) -> Chat? {
        return storage.last { chat in
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
