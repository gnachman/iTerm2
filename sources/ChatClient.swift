//
//  ChatClient.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

// High level interface for AI chat clients.
class ChatClient {
    static let instance = ChatClient()
    private let broker = ChatBroker.instance

    init() {
        broker.processors.append { [weak self] message, chatID in
            guard let self else {
                return message
            }
            return processMessage(message, chatID: chatID)
        }
    }

    // Transform Agent messages so they are useful to the client.
    private func processMessage(_ message: Message,
                                chatID: String) -> Message? {
        if message.participant == .user {
            return message
        }
        switch message.content {
        case .remoteCommandRequest(let request):
            return processRemoteCommandRequest(chatID: chatID, message: message, request: request)
        case .plainText, .markdown, .explanationRequest, .remoteCommandResponse:
            return message
        case .explanationResponse(let aIAnnotationCollection):
            guard let markdown = processExplanationResponse(annotations: aIAnnotationCollection,
                                                            chatID: chatID) else {
                return nil
            }
            return Message(participant: message.participant,
                           content: .markdown(markdown),
                           date: message.date,
                           uniqueID: message.uniqueID)
        }
    }

    func create(chatWithTitle title: String, sessionGuid: String?) -> String {
        return broker.create(chatWithTitle: title, sessionGuid: sessionGuid)
    }

    func subscribe(chatID: String?,
                   registrationProvider: AIRegistrationProvider?,
                   closure: @escaping (ChatBroker.Update) -> ()) -> ChatBroker.Subscription {
        broker.subscribe(chatID: chatID, registrationProvider: registrationProvider, closure: closure)
    }

    func publish(message: Message, toChatID chatID: String) {
        broker.publish(message: message, toChatID: chatID)
    }

    private func processRemoteCommandRequest(chatID: String,
                                             message: Message,
                                             request: RemoteCommand) -> Message? {
        guard let guid = ChatListModel.instance.chat(id: chatID)?.sessionGuid,
              let session = iTermController.sharedInstance().session(withGUID: guid) else {
            rejectRemoteCommandRequest(
                inChat: chatID,
                requestUUID: message.uniqueID,
                message: "The terminal session no longer exists so commands cannot be run in it.")
            return nil
        }
        switch RemoteCommandExecutor.init().permission(inSessionGuid: guid) {
        case .never:
            rejectRemoteCommandRequest(
                inChat: chatID,
                requestUUID: message.uniqueID,
                message: "The user denied permission to use function calling in this terminal session. Do not try again.")
            return nil
        case .always:
            session.execute(request) { [weak self] response in
                self?.respondSuccessfullyToRemoteCommandRequest(inChat: chatID,
                                                                requestUUID: message.uniqueID,
                                                                message: response)
            }
            return nil
        case .ask:
            return message
        }
    }

    private func rejectRemoteCommandRequest(inChat chatID: String,
                                            requestUUID: UUID,
                                            message: String) {
        broker.publish(message: Message(participant: .user,
                                        content: .remoteCommandResponse(
                                            .failure(AIError(message)),
                                            requestUUID),
                                        date: Date(),
                                        uniqueID: UUID()),
                       toChatID: chatID)
    }

    private func respondSuccessfullyToRemoteCommandRequest(inChat chatID: String,
                                                           requestUUID: UUID,
                                                           message: String) {
        broker.publish(message: Message(participant: .user,
                                        content: .remoteCommandResponse(
                                            .success(message),
                                            requestUUID),
                                        date: Date(),
                                        uniqueID: UUID()),
                       toChatID: chatID)
    }

    private enum ExplainUserInfoKeys: String {
        case context
    }

    // Request an AI explanation, create a chat, and reveal the chat window.
    func explain(_ request: AIExplanationRequest,
                 title: String,
                 guid: String,
                 baseOffset: Int64,
                 scope: iTermVariableScope) {
        let chatWindowController = ChatWindowController.instance

        var amended = request
        let context = ExplanationUserInfo(baseOffset: baseOffset,
                                          guid: guid,
                                          locatedString: request.originalString)
        amended.userInfo = [ExplainUserInfoKeys.context.rawValue: try! JSONEncoder().encode(context)]
        let initialMessage = Message(participant: .user,
                                     content: .explanationRequest(request: amended),
                                     date: Date(),
                                     uniqueID: UUID())
        let chatID = broker.create(chatWithTitle: title, sessionGuid: guid)
        broker.publish(message: initialMessage, toChatID: chatID)

        chatWindowController.showChatWindow()
        chatWindowController.select(chatID: chatID)
    }

    // Performs side-effects upon receiving an explanation and returns a transformed message
    // suitable for display.
    private func processExplanationResponse(annotations: AIAnnotationCollection,
                                            chatID: String) -> String? {
        guard let data = annotations.userInfo?[ExplainUserInfoKeys.context.rawValue] as? Data,
              let context = try? JSONDecoder().decode(ExplanationUserInfo.self, from: data),
              let session = iTermController.sharedInstance().session(withGUID: context.guid) else {
            return nil
        }
        let aiAnnotations = annotations.annotations.compactMap {
            AITermAnnotation(annotation: $0, locatedString: context.locatedString)
        }
        let urls = session.add(aiAnnotations: aiAnnotations,
                               baseOffset: context.baseOffset,
                               locatedString: context.locatedString)
        var bullets = [String]()
        for (annotation, url) in zip(aiAnnotations, urls) {
            guard let url else {
                continue
            }
            bullets.append("I [annotated](\(url.absoluteString)) “\(annotation.annotatedText)”: \(annotation.note)")
        }
        if !bullets.isEmpty {
            let epilogue = "\nYou can click on a link in this message or on a yellow underline in the terminal to reveal an annotation"
            if bullets.count  == 1 {
                return bullets.first! + epilogue
            } else {
                return "I added these annotations:\n" + bullets.map { "  * " + $0 }.joined(separator: "\n") + epilogue
            }
        }
        if let mainResponse = annotations.mainResponse {
            return mainResponse
        }
        return nil
    }
}

fileprivate struct ExplanationUserInfo: Codable {
    var baseOffset: Int64
    var guid: String
    var locatedString: iTermCodableLocatedString
}
