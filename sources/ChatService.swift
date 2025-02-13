//
//  ChatService.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

// Imaginary server
class ChatService {
    static let instance = ChatService()
    private var agents = [String: ChatAgent]()
    private var registrationContexts = [RegistrationContext]()

    init() {
        _ = ChatBroker.instance.subscribe(chatID: nil, registrationProvider: nil) { [weak self] update in
            self?.handle(update)
        }
    }

    private func handle(_ update: ChatBroker.Update) {
        switch update {
        case .typingStatus:
            break
        case let .delivery(message, chatID):
            switch message.participant {
            case .agent:
                // Ignore messages from myself
                break
            case .user:
                handleUserMessage(message, inChat: chatID)
            }
        }
    }

    private func handleUserMessage(_ message: Message, inChat chatID: String) {
        ChatBroker.instance.publish(typingStatus: true,
                                    of: .agent,
                                    toChatID: chatID)
        let agent = if let existing = agents[chatID] {
            existing
        } else {
            // Exclude the last message because it's added to the model before the broker publishes
            // it.
            newAgent(forChatID: chatID,
                     messages: Array(ChatListModel.instance.chat(id: chatID)?.messages.dropLast() ?? []))
        }
        agent.fetchCompletion(userMessage: message) { replyMessage in
            ChatBroker.instance.publish(typingStatus: false,
                                        of: .agent,
                                        toChatID: chatID)
            if let replyMessage {
                ChatBroker.instance.publish(message: replyMessage, toChatID: chatID)
            }
        }
    }

    private func newAgent(forChatID chatID: String,
                          messages: [Message]) -> ChatAgent {
        it_assert(agents[chatID] == nil)

        let reg = RegistrationContext(chatID: chatID)
        registrationContexts.append(reg)
        let agent = ChatAgent(
            chatID,
            registrationProvider: reg,
            messages: messages)
        self.agents[chatID] = agent
        return agent
    }

    private class RegistrationContext: AIRegistrationProvider {
        private let chatID: String

        init(chatID: String) {
            self.chatID = chatID
        }
        func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
            ChatBroker.instance.requestRegistration(chatID: chatID, completion: completion)
        }
    }
}
