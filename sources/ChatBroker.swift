//
//  ChatBroker.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//
// This is a diagram of the architecture of AI chat. There is a client and server side
// even though both run in the same process. This is to compartmentalize information so
// that the "agent" doesn't gain dependencies on the whole rest of the app.
// The ChatListModel also spans both client and "server" since it would be silly
// to keep two copies of messages.
//
//
//                                (App)
//                                  |
//   .--------------------.   .------------.   .---------------.   .--------------.
//   | ChatViewController |-->| ChatClient |-->| ChatListModel |-->| ChatDatabase |
//   `--------------------'   `------------'   `---------------'   `--------------'
//                  \               |              ^   ^
//                   \              |             /    |
//                    --------------)------------      |
//                                  |                 ,|
//                                  V      ,---------- |
//                              .--------./            |
//  ............................| Broker |.............|.................
//                              `--------'             |
//                                  ^                  |
//                                  |                  |
//                           .-------------.           |
//                           | ChatService |-----------'
//                           `-------------'
//                                  |
//                                  V
//                            .-----------.
//                            | ChatAgent |
//                            `-----------'
//                                  |
//                                  V
//                             nce  (AITerm)

// The ChatBroker bridges the imaginary line between client and server.
// It also ensure the model is up to date.
class ChatBroker {
    private static var _instance: ChatBroker?
    static var instance: ChatBroker? {
        if _instance == nil {
            _instance = ChatBroker()
        }
        return _instance
    }
    private var subs = [Subscription]()
    var processors = [(message: Message, chatID: String, partial: Bool) -> (Message?)]()
    private let listModel: ChatListModel

    init?() {
        guard let listModel = ChatListModel.instance else {
            return nil
        }
        self.listModel = listModel
    }

    func delete(chatID: String) throws {
        try listModel.delete(chatID: chatID)
    }

    private var defaultPermissions: Set<RemoteCommand.Content.PermissionCategory> {
        return Set(RemoteCommand.Content.PermissionCategory.allCases.filter { category in
            let rawValue = iTermPreferences.unsignedInteger(forKey: category.userDefaultsKey)
            guard let setting = iTermAIPermission(rawValue: rawValue) else {
                return false
            }
            return setting != .never
        })
    }

    func create(chatWithTitle title: String, terminalSessionGuid: String?, browserSessionGuid: String?) throws -> String {
        // Ensure the service is running
        _ = ChatService.instance

        let chat = Chat(title: title,
                        terminalSessionGuid: terminalSessionGuid,
                        browserSessionGuid: browserSessionGuid,
                        permissions: "")
        try listModel.add(chat: chat)
        try publish(message: Message(chatID: chat.id,
                                     author: .user,
                                     content: .setPermissions(defaultPermissions),
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chat.id,
                    partial: false)
        return chat.id
    }

    func publish(message: Message, toChatID chatID: String, partial: Bool) throws {
        DLog("Publish \(message.shortDescription)")
        // Ensure the service is running
        _ = ChatService.instance

        var processed = message
        for processor in processors {
            if let temp = processor(processed, chatID, partial) {
                processed = temp
            } else {
                DLog("Message processing squelched \(message)")
                return
            }
        }
        try listModel.append(message: processed, toChatID: chatID)
        for sub in subs {
            if sub.chatID == chatID || sub.chatID == nil {
                sub.closure?(.delivery(processed, chatID))
            }
        }
    }

    func publish(typingStatus: Bool,
                 of participant: Participant,
                 toChatID chatID: String) {
        TypingStatusModel.instance.set(isTyping: typingStatus,
                                       participant: participant,
                                       chatID: chatID)
        for sub in subs {
            if sub.chatID == chatID || sub.chatID == nil {
                sub.closure?(.typingStatus(typingStatus, participant))
            }
        }
    }

    func requestRegistration(chatID: String, completion: @escaping (AITermController.Registration?) -> ()) {
        for sub in subs {
            if sub.chatID == chatID, let provider = sub.registrationProvider {
                provider.registrationProviderRequestRegistration(completion)
                return
            }
        }
    }

    class Subscription {
        let chatID: String?
        let registrationProvider: AIRegistrationProvider?
        private(set) var closure: ((Update) -> ())?
        private var unsubscribeCallback: ((Subscription) -> ())?

        init(chatID: String?,
             registrationProvider: AIRegistrationProvider?,
             closure: @escaping (Update) -> (),
             unsubscribeCallback: @escaping (Subscription) -> ()) {
            self.chatID = chatID
            self.registrationProvider = registrationProvider
            self.closure = closure
            self.unsubscribeCallback = unsubscribeCallback
        }

        func publish(_ update: Update) {
            closure?(update)
        }

        func unsubscribe() {
            closure = nil
            if let callback = unsubscribeCallback {
                unsubscribeCallback = nil
                callback(self)
            }
        }
    }

    enum Update: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case let .typingStatus(typing, participant): "\(participant) typing=\(typing)"
            case let .delivery(message, chat): "Message in \(chat) - \(message.snippetText ?? "[empty]")"
            }
        }
        case typingStatus(Bool, Participant)
        case delivery(Message, String)
    }

    func subscribe(chatID: String?,
                   registrationProvider: AIRegistrationProvider?,
                   closure: @escaping (Update) -> ()) -> Subscription {
        let subscription = Subscription(chatID: chatID,
                                        registrationProvider: registrationProvider,
                                        closure: closure) { [weak self] sub in
            self?.subs.removeAll(where: { $0 === sub })
        }
        subs.append(subscription)
        return subscription
    }
}


extension ChatBroker {
    func publishMessageFromAgent(chatID: String, content: Message.Content) throws {
        try publish(message: Message(chatID: chatID,
                                     author: .agent,
                                     content: content,
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
    }

    func publishMessageFromUser(chatID: String, content: Message.Content) throws {
        try publish(message: Message(chatID: chatID,
                                     author: .user,
                                     content: content,
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
    }

    func publishNotice(chatID: String, notice: String) throws {
        try publish(message: Message(chatID: chatID,
                                     author: .agent,
                                     content: .clientLocal(.init(action: .notice(notice))),
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
    }
}
