//
//  ChatService.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

// Imaginary server
class ChatService {
    private static var _instance: ChatService?
    static var instance: ChatService? {
        if _instance == nil {
            _instance = ChatService()
        }
        return _instance
    }
    private var agents = [String: ChatAgent]()
    private var registrationContexts = [RegistrationContext]()
    private let listModel: ChatListModel
    private let broker: ChatBroker

    init?() {
        guard let listModel = ChatListModel.instance, let broker = ChatBroker.instance else {
            return nil
        }
        self.listModel = listModel
        self.broker = broker
        _ = broker.subscribe(chatID: nil, registrationProvider: nil) { [weak self] update in
            self?.handle(update)
        }
    }

    private func handle(_ update: ChatBroker.Update) {
        switch update {
        case .typingStatus:
            break
        case let .delivery(message, chatID):
            switch message.author {
            case .agent:
                // Ignore messages from myself
                break
            case .user:
                handleUserMessage(message, inChat: chatID)
            }
        }
    }

    private func handleUserMessage(_ message: Message, inChat chatID: String) {
        if message.isClientLocal {
            return
        }
        agentWorking(chatID: chatID) { stopTyping in
            let agent = if let existing = agents[chatID] {
                existing
            } else {
                // Exclude the last message because it's added to the model before the broker publishes
                // it.
                newAgent(forChatID: chatID, messages: messages(chatID: chatID).dropLast())
            }
            agent.fetchCompletion(userMessage: message,
                                  streaming: { [weak self] update in
                switch update {
                case .begin(let message):
                    self?.broker.publish(message: message, toChatID: chatID, partial: true)
                case .append(let chunk, let uuid):
                    self?.broker.publish(message: Message(chatID: chatID,
                                                          author: .agent,
                                                          content: .append(string: chunk, uuid: uuid),
                                                          sentDate: Date(),
                                                          uniqueID: UUID()),
                                         toChatID: chatID,
                                         partial: true)
                }
            }, completion: { [weak self] replyMessage in
                stopTyping()
                if let replyMessage {
                    self?.broker.publish(message: replyMessage, toChatID: chatID, partial: false)
                }
            })
        }
    }

    // Exclude client-local messages because the agent only knows about them because  it shares a
    // model with the client, which it probably shouldn't.
    private func messages(chatID: String) -> [Message] {
        guard let dbArray = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return []
        }
        return Array(dbArray.filter { !$0.isClientLocal })
    }

    private func newAgent(forChatID chatID: String,
                          messages: ArraySlice<Message>) -> ChatAgent {
        it_assert(agents[chatID] == nil)

        let reg = RegistrationContext(chatID: chatID, broker: broker)
        registrationContexts.append(reg)
        let agent = ChatAgent(
            chatID,
            broker: broker,
            registrationProvider: reg,
            messages: Array(messages))
        self.agents[chatID] = agent
        return agent
    }

    private class RegistrationContext: AIRegistrationProvider {
        private let chatID: String
        private let broker: ChatBroker

        init(chatID: String, broker: ChatBroker) {
            self.chatID = chatID
            self.broker = broker
        }
        func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
            broker.requestRegistration(chatID: chatID, completion: completion)
        }
    }

    func agentWorking(chatID: String, closure: (@escaping () -> ()) -> ()) {
        broker.publish(typingStatus: true, of: .agent, toChatID: chatID)
        closure() {
            self.broker.publish(typingStatus: false, of: .agent, toChatID: chatID)
        }
    }
}
