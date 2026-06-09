//
//  ChatBroker.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//
// Architecture diagram:
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
//                  ChatAgent (session-bound or orchestration mode)
//                            .-----------.
//                            | ChatAgent |
//                            `-----------'
//                                  |
//                                  V
//                              (AITerm)

// The ChatBroker bridges the imaginary line between client and server.
// It also ensure the model is up to date.
@MainActor
class ChatBroker {
    let listModel: ChatListModel
    private var subs = [Subscription]()
    var processors = [(message: Message, chatID: String, partial: Bool) -> (Message?)]()

    private static var _instance: ChatBroker?
    static var instance: ChatBroker? {
        if _instance == nil,
           let lm = ChatListModel.instance {
            _instance = ChatBroker(listModel: lm)
        }
        return _instance
    }

    init(listModel: ChatListModel) {
        self.listModel = listModel
    }

    // Boot the chat service so messages have somewhere to land, and
    // the orchestrator client so .remoteCommandRequest(.external(...))
    // messages have an app-side consumer. ChatService routes by
    // Chat.orchestrationEnabled once it's running; OrchestratorClient
    // listens for external tool calls regardless of the chat's mode
    // (a session-bound chat never emits them, but a chat that flips
    // to orchestration mid-conversation will).
    func ensureServiceRunning() {
        _ = ChatService.instance
        _ = OrchestratorClient.instance
    }

    // MARK: - Lifecycle

    func delete(chatID: String) throws {
        try listModel.delete(chatID: chatID)
    }

    // MARK: - Chat creation

    func create(chatWithTitle title: String,
                terminalSessionGuid: String?,
                browserSessionGuid: String?,
                permissions: String,  // use "" as default
                initialMessages: [Message]) throws -> String {
        ensureServiceRunning()

        let rce = RemoteCommandExecutor.instance
        let chat = Chat(title: title,
                        terminalSessionGuid: terminalSessionGuid,
                        browserSessionGuid: browserSessionGuid,
                        permissions: permissions,
                        modelName: AITermController.provider?.model.name)
        let permissionsDict = rce.permissionsDict(encoded: permissions) ?? rce.defaultPermissions(
            chatID: chat.id,
            terminalGuid: terminalSessionGuid,
            browserGuid: browserSessionGuid)
        try listModel.add(chat: chat)
        if !initialMessages.contains(where: { $0.content.isSetPermissions }) {
            try publish(message: Message(chatID: chat.id,
                                         author: .user,
                                         content: .setPermissions(
                                            rce.allowedCategories(dict: permissionsDict)),
                                         sentDate: Date(),
                                         uniqueID: UUID()),
                        toChatID: chat.id,
                        partial: false)
        }
        for message in initialMessages {
            do {
                var temp = message
                temp.chatID = chat.id
                try listModel.append(message: temp, toChatID: chat.id)
            } catch {
                DLog("While preloading messages: \(error)")
            }
        }
        return chat.id
    }

    // MARK: - Publish

    func publish(message: Message, toChatID chatID: String, partial: Bool) throws {
        DLog("Publish \(message.shortDescription)")
        ensureServiceRunning()

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
        let snapshot = subs
        for sub in snapshot {
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
        let snapshot = subs
        for sub in snapshot {
            if sub.chatID == chatID || sub.chatID == nil {
                sub.closure?(.typingStatus(typingStatus, participant))
            }
        }
    }

    func requestRegistration(chatID: String,
                             for vendor: iTermAIVendor,
                             completion: @escaping (AITermController.Registration?) -> ()) {
        for sub in subs {
            if sub.chatID == chatID, let provider = sub.registrationProvider {
                provider.registrationProviderRequestRegistration(for: vendor, completion)
                return
            }
        }
    }

    // MARK: - Subscriptions

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

// Convenience publishers

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
