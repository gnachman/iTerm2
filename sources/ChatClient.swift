//
//  ChatClient.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

// High level interface for AI chat clients.
class ChatClient {
    private static var _instance: ChatClient?
    static var instance: ChatClient? {
        if _instance == nil {
            _instance = ChatClient()
        }
        return _instance
    }
    private let broker: ChatBroker
    let model: ChatListModel

    init?() {
        guard let model = ChatListModel.instance,
        let broker = ChatBroker.instance else {
            return nil
        }
        self.model = model
        self.broker = broker
        broker.processors.append { [weak self] message, chatID, partial in
            guard let self else {
                return message
            }
            return processMessage(message, chatID: chatID, partial: partial)
        }
    }

    // Transform Agent messages so they are useful to the client.
    private func processMessage(_ message: Message,
                                chatID: String,
                                partial: Bool) -> Message? {
        if message.author == .user {
            return message
        }
        switch message.content {
        case .remoteCommandRequest(let request):
            it_assert(!partial)
            return processRemoteCommandRequest(chatID: chatID, message: message, request: request)
        case .plainText, .markdown, .explanationRequest, .remoteCommandResponse,
                .selectSessionRequest, .clientLocal, .renameChat, .setPermissions,
                .terminalCommand:
            return message
        case let .append(string: string, uuid: uuid):
            it_assert(partial)
            return processAppend(appendMessage: message, string: string, uuid: uuid, chatID: chatID)
        case .commit(let uuid):
            return processCommit(finalMessage: message, messageID: uuid, chatID: chatID)
        case .explanationResponse(let response, let update, let markdown):
            // This is either the entire message or the initial in a streaming rsponse.
            guard let newMarkdown = markdownForExplanationResponse(response: response,
                                                                   update: update,
                                                                   chatID: chatID,
                                                                   messageID: message.uniqueID) else {
                return nil
            }
            var temp = message
            temp.content = .explanationResponse(response, nil, markdown: markdown + newMarkdown)
            return temp
        }
    }

    func create(chatWithTitle title: String, sessionGuid: String?) -> String {
        return broker.create(chatWithTitle: title, sessionGuid: sessionGuid)
    }

    func delete(chatID: String) {
        broker.delete(chatID: chatID)
    }

    func subscribe(chatID: String?,
                   registrationProvider: AIRegistrationProvider?,
                   closure: @escaping (ChatBroker.Update) -> ()) -> ChatBroker.Subscription {
        broker.subscribe(chatID: chatID, registrationProvider: registrationProvider, closure: closure)
    }

    func publish(message: Message, toChatID chatID: String, partial: Bool) {
        broker.publish(message: message, toChatID: chatID, partial: partial)
    }

    func publishMessageFromUser(chatID: String, content: Message.Content) {
        broker.publishMessageFromUser(chatID: chatID, content: content)
    }

    func publishMessageFromAgent(chatID: String, content: Message.Content) {
        broker.publishMessageFromAgent(chatID: chatID, content: content)
    }
    
    private func processRemoteCommandRequest(chatID: String,
                                             message: Message,
                                             request: RemoteCommand) -> Message? {
        guard let guid = model.chat(id: chatID)?.sessionGuid,
              let session = iTermController.sharedInstance().session(withGUID: guid) else {
            return Message(chatID: chatID,
                           author: .agent,
                           content: .selectSessionRequest(message),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
        switch RemoteCommandExecutor.instance.permission(chatID: chatID,
                                                         inSessionGuid: guid,
                                                         category: request.content.permissionCategory) {
        case .never:
            respondSuccessfullyToRemoteCommandRequest(
                inChat: chatID,
                requestUUID: message.uniqueID,
                message: "The user denied permission to use function calling in this terminal session. Do not try again.",
                functionCallName: message.functionCallName ?? "Unknown function call name",
                userNotice: "AI will not execute this command.")
            return nil
        case .always:
            performRemoteCommand(request,
                                 in: session,
                                 chatID: chatID,
                                 messageUniqueID: message.uniqueID)
            return nil
        case .ask:
            return message
        }
    }

    func publishClientLocalMessage(chatID: String,
                                   action: ClientLocal.Action) {
        broker.publishMessageFromAgent(chatID: chatID,
                                       content: .clientLocal(.init(action: action)))
    }

    func publishUserMessage(chatID: String,
                            content: Message.Content) {
        broker.publish(message: .init(chatID: chatID,
                                      author: .user,
                                      content: content,
                                      sentDate: Date(),
                                      uniqueID: UUID()),
                       toChatID: chatID,
                       partial: false)
    }

    func publishNotice(chatID: String, notice: String) {
        broker.publishNotice(chatID: chatID, notice: notice)
    }

    func performRemoteCommand(_ request: RemoteCommand,
                              in session: PTYSession,
                              chatID: String,
                              messageUniqueID: UUID) {
        var done = false
        broker.publishNotice(chatID: chatID, notice: "\(request.markdownDescription)…")
        session.execute(request) { [weak self] response, userNotice in
            done = true
            self?.respondSuccessfullyToRemoteCommandRequest(inChat: chatID,
                                                            requestUUID: messageUniqueID,
                                                            message: response,
                                                            functionCallName: request.llmMessage.function_call?.name ?? "Unknown function call name",
                                                            userNotice: userNotice)
        }
        if !done {
            publish(message: Message(chatID: chatID,
                                     author: .agent,
                                     content: .clientLocal(ClientLocal(action: .executingCommand(request))),
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
        }
    }

    func respondSuccessfullyToRemoteCommandRequest(inChat chatID: String,
                                                   requestUUID: UUID,
                                                   message: String,
                                                   functionCallName: String,
                                                   userNotice: String?) {
        if let userNotice {
            broker.publishNotice(chatID: chatID, notice: userNotice)
        }
        broker.publish(message: Message(chatID: chatID,
                                        author: .user,
                                        content: .remoteCommandResponse(
                                            .success(message),
                                            requestUUID,
                                            functionCallName),
                                        sentDate: Date(),
                                        uniqueID: UUID()),
                       toChatID: chatID,
                       partial: false)
    }

    private enum ExplainUserInfoKeys: String {
        case context
    }

    // Request an AI explanation, create a chat, and reveal the chat window.
    func explain(_ request: AIExplanationRequest,
                 title: String,
                 scope: iTermVariableScope) {
        guard let chatWindowController = ChatWindowController.instance(showErrors: false) else {
            return
        }
        chatWindowController.showChatWindow()
        guard let window = chatWindowController.window else {
            return
        }
        if AITermControllerRegistrationHelper.instance.registration == nil {
            AITermControllerRegistrationHelper.instance.requestRegistration(in: window) { [weak self] _ in
                if (AITermControllerRegistrationHelper.instance.registration != nil) {
                    self?.explain(request, title: title, scope: scope)
                } else {
                    ChatWindowController.instance(showErrors: false)?.window?.performClose(nil)
                }
            }
            return
        }
        let chatID = broker.create(chatWithTitle: title,
                                   sessionGuid: request.context.sessionID)
        let initialMessage = Message(chatID: chatID,
                                     author: .user,
                                     content: .explanationRequest(request: request),
                                     sentDate: Date(),
                                     uniqueID: UUID())
        broker.publish(message: initialMessage, toChatID: chatID, partial: false)

        chatWindowController.select(chatID: chatID)
    }

    private func processAppend(appendMessage: Message,
                               string: String,
                               uuid: UUID,
                               chatID: String) -> Message? {
        guard let messages = model.messages(forChat: chatID, createIfNeeded: false),
              let i = model.index(ofMessageID: uuid, inChat: chatID) else {
            return appendMessage
        }
        let original = messages[i]
        switch original.content {
        case .plainText, .markdown, .explanationRequest, .remoteCommandResponse, .clientLocal,
                .renameChat, .append, .commit, .remoteCommandRequest, .selectSessionRequest,
                .setPermissions, .terminalCommand:
            // These are impossible or just normal streaming messages.
            return appendMessage

        case .explanationResponse(var response, _, let accumulatedMarkdown):
            // The case has no second value because this is where second values *come* from.
            // The initial is always empty.

            // append() will modify response in place so it is always complete.
            var update = response.append(string, final: false)
            update.messageID = uuid

            guard let newMarkdown = markdownForExplanationResponse(response: response,
                                                                   update: update,
                                                                   chatID: chatID,
                                                                   messageID: original.uniqueID) else {
                return nil
            }
            return Message(chatID: chatID,
                           author: original.author,
                           content: .explanationResponse(response,
                                                         update,
                                                         markdown: accumulatedMarkdown + newMarkdown),
                           sentDate: appendMessage.sentDate,
                           uniqueID: UUID())
        }
    }

    private func processCommit(finalMessage: Message, messageID: UUID, chatID: String) -> Message? {
        guard let messages = model.messages(forChat: chatID, createIfNeeded: false),
              let i = model.index(ofMessageID: messageID, inChat: chatID) else {
            return finalMessage
        }
        let original = messages[i]
        switch original.content {
        case .plainText, .markdown, .explanationRequest, .remoteCommandResponse, .clientLocal,
                .renameChat, .append, .commit, .remoteCommandRequest, .selectSessionRequest,
                .setPermissions, .terminalCommand:
            // These are impossible or just normal streaming messages.
            return finalMessage

        case .explanationResponse(let response, _, let accumulatedMarkdown):
            // The case has no second value because the initial, which is still in the original message,
            // is always empty.
            let marginal = markdownForExplanationResponse(
                response: response,
                update: ExplanationResponse.Update(final: true, messageID: messageID),
                chatID: chatID,
                messageID: messageID)
            if let marginal {
                return Message(
                    chatID: chatID,
                    author: original.author,
                    content: .explanationResponse(response,
                                                  .init(final: true, messageID: messageID),
                                                  markdown: accumulatedMarkdown + marginal),
                    sentDate: finalMessage.sentDate,
                    uniqueID: UUID())
            } else {
                return nil
            }
        }
    }

    // Performs side-effects upon receiving an explanation and returns a transformed message
    // suitable for display. Returns the marginal markdown to append.
    private func markdownForExplanationResponse(response: ExplanationResponse,
                                                update: ExplanationResponse.Update?,
                                                chatID: String,
                                                messageID: UUID) -> String? {
        let value = update ?? ExplanationResponse.Update(response)
        guard let session = iTermController.sharedInstance().session(withGUID: response.request.context.sessionID) else {
            return nil
        }
        let aiAnnotations = value.annotations.compactMap {
            AITermAnnotation(annotation: $0, locatedString: response.request.originalString)
        }
        let urls = session.add(aiAnnotations: aiAnnotations,
                               baseOffset: response.request.context.baseOffset,
                               locatedString: response.request.originalString)
        var bullets = [String]()
        for (annotation, url) in zip(aiAnnotations, urls) {
            guard let url else {
                continue
            }
            bullets.append("I [annotated](\(url.absoluteString)) “\(annotation.annotatedText)”: \(annotation.note)")
        }
        var result = ""
        result += bullets.map { "  * " + $0 }.joined(separator: "\n")
        if !bullets.isEmpty {
            result += "\n"
        }
        if value.final && !response.annotations.isEmpty {
            result += "\nYou can click on a link in this message or on a yellow underline in the terminal to reveal an annotation."
        }
        if let mainResponse = value.mainResponse {
            if !result.isEmpty {
                result += "\n"
            }
            result += mainResponse
        }
        return result
    }
}

