//
//  ChatAgent.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

fileprivate extension AITermController.Message {
    static func role(from message: Message) -> String {
        switch message.participant {
        case .user: "user"
        case .agent: "assistant"
        }
    }
}

fileprivate struct MessageToPromptStateMachine {
    private enum Mode {
        case regular
        case initialExplanation
    }
    private var mode = Mode.regular

    mutating func prompt(message: Message) -> String {
        switch message.participant {
        case .agent:
            prompt(agentMessage: message)
        case .user:
            prompt(userMessage: message)
        }
    }

    private mutating func prompt(agentMessage: Message) -> String {
        switch agentMessage.content {
        case .plainText(let value), .markdown(let value):
            value
        case .explanationResponse(let annotations):
            annotations.rawResponse
        case .explanationRequest:
            it_fatalError()
        }
    }

    private mutating func prompt(userMessage: Message) -> String {
        switch mode {
        case .regular:
            switch userMessage.content {
            case .plainText(let value), .markdown(let value):
                return value
            case .explanationRequest(let request):
                mode = .initialExplanation
                return request.prompt()
            case .explanationResponse:
                it_fatalError()
            }
        case .initialExplanation:
            switch userMessage.content {
            case .plainText(let value), .markdown(let value):
                mode = .regular
                return AIExplanationRequest.conversationalPrompt(userPrompt: value)
            case .explanationResponse, .explanationRequest:
                it_fatalError()
            }
        }
    }
}

class ChatAgent {
    private var conversation: AIConversation
    private let chatID: String
    private var brokerSubscription: ChatBroker.Subscription?
    private var messageToPrompt = MessageToPromptStateMachine()

    init(_ chatID: String, registrationProvider: AIRegistrationProvider, messages: [Message]) {
        self.chatID = chatID
        conversation = AIConversation(registrationProvider: registrationProvider)
        for message in messages {
            conversation.add(aiMessage(from: message))
        }
    }

    deinit {
        brokerSubscription?.unsubscribe()
    }

    private func aiMessage(from message: Message) -> AITermController.Message {
        AITermController.Message(role: AITermController.Message.role(from: message),
                                                 content: messageToPrompt.prompt(message: message))
    }

    // TODO: I think we need to handle cancellations to keep the conversation correct.
    func fetchCompletion(userMessage: Message,
                         completion: @escaping (Message?) -> ()) {
        conversation.add(aiMessage(from: userMessage))
        conversation.complete { result in
            if let updated = result.successValue {
                self.conversation = updated
            } else {
                self.conversation.messages.removeLast()
            }
            let message = Self.message(forResult: result, userMessage: userMessage)
            completion(message)
        }
    }

    private static func message(forResult result: Result<AIConversation, any Error>,
                                userMessage: Message) -> Message? {
        return result.handle { updated -> Message? in
            guard let text = updated.messages.last!.content else {
                return nil
            }
            switch userMessage.content {
            case .plainText, .markdown, .explanationResponse:
                return Message(participant: .agent,
                               content: .markdown(text),
                               date: Date(),
                               uniqueID: UUID())
            case .explanationRequest(let explanationRequest):
                return Message(
                    participant: .agent,
                    content: .explanationResponse(
                        AIAnnotationCollection(text, request: explanationRequest)),
                    date: Date(),
                    uniqueID: UUID())
            }
        } failure: { error in
            #warning("TODO: This code path will leave things in a broken state if it happens in the first two messages of an explanation")
            let nserror = error as NSError
            if userMessage.isExplanationRequest &&
                nserror.domain == iTermAIError.domain &&
                nserror.code == iTermAIError.ErrorType.requestTooLarge.rawValue {
                return Message(participant: .agent,
                               content: .plainText("🛑 The text to analyze was too long. Select a portion of it and try again."),
                               date: Date(),
                               uniqueID: UUID())
            }

            return Message(participant: .agent,
                           content: .plainText("🛑 I ran into a problem: \(error.localizedDescription)"),
                           date: Date(),
                           uniqueID: UUID())
        }
    }
}


extension Message {
    var isExplanationRequest: Bool {
        switch content {
        case .explanationRequest: true
        default: false
        }
    }
}
