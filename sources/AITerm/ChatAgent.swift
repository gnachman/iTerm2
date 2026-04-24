//
//  ChatAgent.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

fileprivate extension AITermController.Message {
    static func role(from message: Message) -> LLM.Role {
        switch message.author {
        case .user: .user
        case .agent: .assistant
        }
    }
}

extension Message {
    var functionCallName: String? {
        switch content {
        case .remoteCommandRequest(let request, safe: _):
            return request.llmMessage.function_call?.name
        case .remoteCommandResponse(_, _, let name, _):
            return name
        default:
            return nil
        }
    }

    var functionCall: LLM.FunctionCall? {
        switch content {
        case .remoteCommandRequest(let request, safe: _):
            return request.llmMessage.function_call
        default:
            return nil
        }
    }

    var functionCallID: LLM.Message.FunctionCallID? {
        switch content {
        case .remoteCommandRequest(let request, safe: _):
            return request.llmMessage.functionCallID
        case .remoteCommandResponse(_, _, _, let id):
            return id
        default:
            return nil
        }
    }
}

class ChatAgent {
    private var conversation: AIConversation!
    private let chatID: String
    private var brokerSubscription: ChatBroker.Subscription?
    private var messageToPrompt = MessageToPromptStateMachine()
    private var pendingRemoteCommands = [UUID: PendingRemoteCommand]()
    private let broker: ChatBroker
    private var renameConversation: AIConversation?
    private let prepPipeline: MessagePrepPipeline
    private var lastSystemMessage: String?

    struct PendingRemoteCommand {
        var completion: (Result<String, Error>) throws -> ()
        var responseID: String?
    }

    private var permissions: Set<RemoteCommand.Content.PermissionCategory>!
    private let registrationProvider: AIRegistrationProvider

    init(_ chatID: String,
         broker: ChatBroker,
         registrationProvider: AIRegistrationProvider,
         messages: [Message]) {
        self.chatID = chatID
        self.broker = broker
        self.registrationProvider = registrationProvider
        self.prepPipeline = MessagePrepPipeline(chatID: chatID)
        permissions = Set<RemoteCommand.Content.PermissionCategory>()
        conversation = AIConversation(registrationProvider: registrationProvider)
        conversation.hostedTools.codeInterpreter = true
        prepPipeline.delegate = self
        load(messages: messages)
    }

    private func load(messages: [Message]) {
        let aiMessages = messages.compactMap { message in
            switch message.content {
            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .terminalCommand,
                    .multipart:
                return aiMessage(from: message)
                
            case .selectSessionRequest, .clientLocal, .renameChat, .append, .appendAttachment,
                    .commit, .vectorStoreCreated, .userCommand:
                return nil
                
            case .setPermissions(let updated):
                permissions = updated
                return nil
            }
        }
        conversation.messages = aiMessages
        updateSystemMessage(permissions)
    }

    private func updateSystemMessage(_ permissions: Set<RemoteCommand.Content.PermissionCategory>) {
        self.permissions = permissions
        var parts = [String]()

        let key = if AITermController.provider?.functionsSupported != true || permissions.isEmpty {
            kPreferenceKeyAIPromptAIChat
        } else {
            if permissions.contains(.actInWebBrowser) {
                if permissions.contains(.runCommands) || permissions.contains(.typeForYou) {
                    kPreferenceKeyAIPromptAIChatReadWriteTerminalBrowser
                } else {
                    kPreferenceKeyAIPromptAIChatReadOnlyTerminalBrowser
                }
            } else {
                if permissions.contains(.runCommands) || permissions.contains(.typeForYou) {
                    kPreferenceKeyAIPromptAIChatReadWriteTerminal
                } else {
                    kPreferenceKeyAIPromptAIChatReadOnlyTerminal
                }
            }
        }
        parts.append(iTermPreferences.string(forKey: key))
        parts.append("If a zip file is provided (this is rare), you should extract it and analyze the contents in the context of the accompanying messages.")

        conversation.systemMessage = parts.joined(separator: " ")
        if conversation.systemMessage != lastSystemMessage {
            // Force the whole conversation to be re-sent
            conversation.systemMessageDirty = true
            lastSystemMessage = conversation.systemMessage
        }
        defineFunctions(in: &conversation, allowedCategories: permissions)
    }

    deinit {
        brokerSubscription?.unsubscribe()
    }

    private func aiMessage(from message: Message) -> AITermController.Message {
        let body = messageToPrompt.body(message: message)
        return AITermController.Message(
            responseID: message.responseID,
            role: AITermController.Message.role(from: message),
            body: body)
    }


    var supportsStreaming: Bool {
        return conversation.supportsStreaming
    }



    func fetchCompletion(userMessage: Message,
                         history: [Message],
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) throws {
        try fetchCompletion(userMessage: userMessage,
                            history: history,
                            cancelPendingUploads: true,
                            streaming: streaming,
                            completion: completion)
    }

    private func cancelPendingCommands() {
        if !pendingRemoteCommands.isEmpty {
            let saved = pendingRemoteCommands.values
            pendingRemoteCommands.removeAll()
            for item in saved {
                try? item.completion(.failure(PendingCommandCanceled()))
                if let id = item.responseID {
                    conversation.deleteResponse(id) { error in
                        DLog("Deleted \(id): \(error.d)")
                    }
                }
            }
        }
    }

    func stop() {
        cancelPendingCommands()
        conversation.stop()
    }

    func fetchCompletion(userMessage: Message,
                         history: [Message],
                         cancelPendingUploads: Bool,
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) throws {
        load(messages: history)

        // Remove items that won't have a previous response ID.
        let filteredHistory = history.filter { message in
            switch message.content {
            case .setPermissions, .renameChat, .selectSessionRequest, .clientLocal,
                    .append, .appendAttachment, .commit, .vectorStoreCreated, .userCommand:
                false

            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .terminalCommand, .multipart:
                true
            }
        }
        if cancelPendingUploads {
            prepPipeline.cancelAll()
        }
        switch userMessage.content {
        case .multipart:
            if try prepPipeline.handleMultipartUserMessage(userMessage: userMessage,
                                                           history: filteredHistory,
                                                           streaming: streaming,
                                                           completion: completion) {
                return
            }
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .selectSessionRequest, .clientLocal, .commit,
                .terminalCommand:
            break
        case .renameChat, .append:
            return
        case .remoteCommandResponse(let result, let messageID, _, _):
            if handleRemoteCommandResponse(messageID: messageID,
                                           result: result) {
                return
            }
        case .setPermissions(let allowedCategories):
            handleSetPermission(allowedCategories: allowedCategories,
                                completion: completion)
            return
        case .userCommand:
            it_fatalError("User commands should not reach fetchCompletion")
        case .vectorStoreCreated:
            it_fatalError("User should not create vector store")
        case .appendAttachment:
            it_fatalError("User-sent attachments not supported")
        }
        fetchCompletionForRegularMessage(userMessage: userMessage,
                                         history: filteredHistory,
                                         streaming: streaming,
                                         completion: completion)
    }

    private func handleRemoteCommandResponse(messageID: UUID,
                                             result: Result<String, AIError>) -> Bool {
        if let pending = pendingRemoteCommands[messageID] {
            NSLog("Agent handling remote command response to message \(messageID)")
            pendingRemoteCommands.removeValue(forKey: messageID)
            try? pending.completion(Result(result))
            return true
        }
        return false
    }

    private func handleSetPermission(allowedCategories: Set<RemoteCommand.Content.PermissionCategory>,
                                     completion: @escaping (Message?) -> ()) {
        defineFunctions(in: &conversation,
                        allowedCategories: allowedCategories)
        updateSystemMessage(allowedCategories)
        completion(nil)
    }

    private func fetchCompletionForRegularMessage(userMessage: Message,
                                                  history: [Message],
                                                  streaming: ((StreamingUpdate) -> ())?,
                                                  completion: @escaping (Message?) -> ()) {
        cancelPendingCommands()

        let needsRenaming = !conversation.messages.anySatisfies({ $0.role == .user})
        if LLMMetadata.model()?.features.contains(.hostedWebSearch) == true,
           let configuration = userMessage.configuration {
            conversation.hostedTools.webSearch = configuration.hostedWebSearchEnabled
        } else {
            conversation.hostedTools.webSearch = false
        }

        let useCodeInterpeter = (LLMMetadata.model()?.features.contains(.hostedCodeInterpreter) == true)
        conversation.hostedTools.codeInterpreter = useCodeInterpeter

        if LLMMetadata.model()?.features.contains(.hostedFileSearch) == true,
           let vectorStoreIDs = userMessage.configuration?.vectorStoreIDs, !vectorStoreIDs.isEmpty {
            conversation.hostedTools.fileSearch = .init(vectorstoreIDs: vectorStoreIDs)
        } else {
            conversation.hostedTools.fileSearch = nil
        }

        if let responseID = userMessage.inResponseTo {
            conversation.deleteMessages(after: responseID)
        }
        conversation.add(aiMessage(from: userMessage))
        conversation.model = userMessage.configuration?.model
        conversation.shouldThink = userMessage.configuration?.shouldThink

        var uuid: UUID?
        let streamingCallback: ((LLM.StreamingUpdate, String?) -> ())?
        if let streaming {
            streamingCallback = { streamingUpdate, responseID in
                switch streamingUpdate {
                case .appendAttachment(let chunk):
                    if uuid == nil,
                       let initialMessage = Self.message(attachment: chunk,
                                                         userMessage: userMessage,
                                                         responseID: responseID) {
                        streaming(.begin(initialMessage))
                        uuid = initialMessage.uniqueID
                    } else if let uuid {
                        streaming(.appendAttachment(chunk, uuid))
                    }
                case .append(let chunk):
                    if uuid == nil,
                       let initialMessage = Self.message(completionText: chunk,
                                                         userMessage: userMessage,
                                                         streaming: true,
                                                         responseID: responseID) {
                        streaming(.begin(initialMessage))
                        uuid = initialMessage.uniqueID
                    } else if let uuid {
                        streaming(.append(chunk, uuid))
                    }
                case .willInvoke(_):
                    break
                }
            }
        } else {
            streamingCallback = nil
        }
        if conversation.busy {
            conversation.cancelOutstandingOperation()
        }
        conversation.complete(streaming: streamingCallback) { [weak self] result in
            guard let self else {
                return
            }
            if result.failureValue is PendingCommandCanceled {
                completion(nil)
                return
            }
            if let updated = result.successValue {
                self.conversation = updated
                if needsRenaming {
                    self.requestRenaming()
                }
            }
            let message = Self.committedMessage(forResult: result,
                                                userMessage: userMessage,
                                                streamID: uuid)
            completion(message)
        }
    }

    private func requestRenaming() {
        let prompt = "Please assign a short, specific name to this chat, less than 30 characters in length, but descriptive. It will be shown in a chat list UI. Respond with only the name of the chat."
        var history = conversation.messages + [AITermController.Message(role: .user, content: prompt)]
        // Remove response IDs so we don't pollute the conversation's history
        history = history.map { value in
            var temp = value
            temp.responseID = nil
            return temp
        }
        renameConversation = AIConversation(
            registrationProvider: nil,
            messages: history)
        renameConversation?.shouldThink = false
        var failed = false
        renameConversation?.complete { [weak self] (result: Result<AIConversation, Error>) in
            if let newName = result.successValue?.messages.last?.body.content {
                try? self?.renameChat(newName)
                self?.renameConversation = nil
            } else {
                failed = true
            }
        }
        if failed {
            renameConversation = nil
        }
    }

    private static func committedMessage(respondingTo userMessage: Message,
                                         fromLastMessageIn conversation: AIConversation) -> Message? {
        guard let text = conversation.messages.last?.body.content else {
            return nil
        }
        return self.message(completionText: text,
                            userMessage: userMessage,
                            streaming: false,
                            responseID: conversation.messages.last?.responseID)
    }

    // Return a new message from the agent containing the content of the last message in result.
    private static func committedMessage(forResult result: Result<AIConversation, any Error>,
                                         userMessage: Message,
                                         streamID: UUID?) -> Message? {
        if let streamID {
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .commit(streamID),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
        return result.handle { (updated: AIConversation) -> Message? in
            return committedMessage(respondingTo: userMessage,
                                    fromLastMessageIn: updated)
        } failure: { error in
            let nserror = error as NSError
            if userMessage.isExplanationRequest &&
                nserror.domain == iTermAIError.domain &&
                nserror.code == iTermAIError.ErrorType.requestTooLarge.rawValue {
                return Message(chatID: userMessage.chatID,
                               author: .agent,
                               content: .plainText("🛑 The text to analyze was too long. Select a portion of it and try again.",
                                                   context: nil),
                               sentDate: Date(),
                               uniqueID: UUID())
            }

            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .plainText("🛑 I ran into a problem: \(error.localizedDescription)",
                                               context: nil),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
    }

    // This is for a committed message or an initial message in a stream.
    private static func message(completionText text: String,
                                userMessage: Message,
                                streaming: Bool,
                                responseID: String?) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand, .remoteCommandResponse, .multipart:
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .markdown(text),
                           sentDate: Date(),
                           uniqueID: UUID(),
                           responseID: responseID)
        case .explanationRequest(let explanationRequest):
            let messageID = UUID()
            return Message(
                chatID: userMessage.chatID,
                author: .agent,
                content: .explanationResponse(
                    ExplanationResponse(text: text,
                                        request: explanationRequest,
                                        final: streaming == false),
                    streaming ? ExplanationResponse.Update(final: false, messageID: messageID) : nil,
                    markdown: ""),  // markdown is added by the client.
                sentDate: Date(),
                uniqueID: messageID,
                responseID: responseID)
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .appendAttachment, .vectorStoreCreated, .userCommand:
            it_fatalError()
        }
    }

    // Streaming only
    private static func message(attachment: LLM.Message.Attachment,
                                userMessage: Message,
                                responseID: String?) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand, .remoteCommandResponse, .multipart:
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .multipart(
                            [.attachment(attachment)],
                            vectorStoreID: nil),
                           sentDate: Date(),
                           uniqueID: UUID(),
                           responseID: responseID)
        case .explanationRequest(let explanationRequest):
            let messageID = UUID()
            return Message(
                chatID: userMessage.chatID,
                author: .agent,
                content: .explanationResponse(
                    // TODO: Support attachments in explanations
                    ExplanationResponse(text: attachment.contentString,
                                        request: explanationRequest,
                                        final: false),
                    ExplanationResponse.Update(final: false, messageID: messageID),
                    markdown: ""),  // markdown is added by the client.
                sentDate: Date(),
                uniqueID: messageID,
                responseID: responseID)
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .appendAttachment, .vectorStoreCreated, .userCommand:
            it_fatalError()
        }
    }
}

extension LLM.Message.Attachment {
    var contentString: String {
        switch type {
        case .code(let code): code
        case .statusUpdate(let statusUpdate): statusUpdate.displayString
        case .file(let file):
            file.content.lossyString
        case .fileID: "[Attached file]"
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

extension ChatAgent {
    private func define<T: Codable>(in conversation: inout AIConversation, content: RemoteCommand.Content, prototype: T) {
        let f = ChatGPTFunctionDeclaration(name: content.functionName,
                                           description: content.functionDescription,
                                           parameters: JSONSchema(for: prototype, descriptions: content.argDescriptions))
        let argsType = type(of: prototype)
        conversation.define(
            function: f,
            arguments: argsType) { [weak self] llmMessage, command, completion in
                let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                  content: content.withValue(command))
                try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
            }
    }
    func defineFunctions(in conversation: inout AIConversation,
                         allowedCategories: Set<RemoteCommand.Content.PermissionCategory>) {
        conversation.removeAllFunctions()
        for content in RemoteCommand.Content.allCases {
            guard allowedCategories.contains(content.permissionCategory) else {
                continue
            }
            switch content {
            case .isAtPrompt(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .executeCommand(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getLastExitStatus(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCommandHistory(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getLastCommand(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCommandBeforeCursor(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .searchCommandHistory(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCommandOutput(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getTerminalSize(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getShellType(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .detectSSHSession(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getRemoteHostname(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getUserIdentity(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCurrentDirectory(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .setClipboard(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .insertTextAtCursor(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .deleteCurrentLine(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getManPage(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .createFile(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .searchBrowser(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .loadURL(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .webSearch(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getURL(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .readWebPage(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            }
        }
    }

    // MARK: - Function Calling Infra

    private func renameChat(_ newName: String) throws {
        try broker.publish(message: .init(chatID: chatID,
                                          author: .agent,
                                          content: .renameChat(newName),
                                          sentDate: Date(),
                                          uniqueID: UUID()),
                           toChatID: chatID,
                           partial: false)
    }

    private func runRemoteCommand(_ remoteCommand: RemoteCommand,
                                  _ responseID: String?,
                                  completion: @escaping (Result<String, Error>) throws -> ()) throws {
        if remoteCommand.needsSafetyCheck {
            Task { @MainActor in
                let safe = await remoteCommand.isSafe()
                do {
                    try reallyRunCommand(remoteCommand,
                                         responseID,
                                         safe: safe,
                                         completion: completion)
                } catch {
                    Task { @MainActor in
                        try? completion(.failure(error))
                    }
                }
            }
        } else {
            try reallyRunCommand(remoteCommand, responseID, safe: nil, completion: completion)
        }
    }

    private func reallyRunCommand(_ remoteCommand: RemoteCommand,
                                  _ responseID: String?,
                                  safe: Bool?,
                                  completion: @escaping (Result<String, Error>) throws -> ()) throws {
        let requestID = UUID()
        pendingRemoteCommands[requestID] = .init(completion: completion,
                                                 responseID: responseID)
        try broker.publish(message: .init(chatID: chatID,
                                          author: .agent,
                                          content: .remoteCommandRequest(remoteCommand, safe: safe),
                                          sentDate: Date(),
                                          uniqueID: requestID),
                           toChatID: chatID,
                           partial: false)
    }
}

extension Result where Failure == Error {
    // Upcast Result<Success,SpecificFailure> to Result<Success,Error>.
    init<SpecificFailure: Error>(_ result: Result<Success, SpecificFailure>) {
        self = result.mapError { $0 }
    }
}

extension ChatAgent: MessagePrepPipelineDelegate {
    func uploadFile(name: String,
                    content: Data,
                    completion: @escaping (Result<String, any Error>) -> ()) {
        conversation.uploadFile(name: name,
                                content: content,
                                completion: completion)
    }
    
    func publish(message: Message, toChatID chatID: String, partial: Bool) throws {
        try broker.publish(message: message, toChatID: chatID, partial: partial)
    }
    
    func createVectorStore(name: String, completion: @escaping (Result<String, any Error>) -> ()) {
        conversation.createVectorStore(name: name,
                                       completion: completion)
    }
    
    func addFilesToVectorStore(fileIDs: [String],
                               vectorStoreID: String,
                               completion: @escaping ((any Error)?) -> ()) {
        conversation.addFilesToVectorStore(fileIDs: fileIDs,
                                           vectorStoreID: vectorStoreID,
                                           completion: completion)
    }
    
    func publishNotice(chatID: String, message: String) throws {
        try broker.publishMessageFromAgent(
            chatID: chatID,
            content: .clientLocal(.init(action: .notice(message))))
    }
}
