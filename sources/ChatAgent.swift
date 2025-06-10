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
        case .remoteCommandRequest(let request):
            return request.llmMessage.function_call?.name
        case .remoteCommandResponse(_, _, let name, _):
            return name
        default:
            return nil
        }
    }

    var functionCall: LLM.FunctionCall? {
        switch content {
        case .remoteCommandRequest(let request):
            return request.llmMessage.function_call
        default:
            return nil
        }
    }

    var functionCallID: LLM.Message.FunctionCallID? {
        switch content {
        case .remoteCommandRequest(let request):
            return request.llmMessage.functionCallID
        case .remoteCommandResponse(_, _, _, let id):
            return id
        default:
            return nil
        }
    }
}
fileprivate struct MessageToPromptStateMachine {
    private enum Mode {
        case regular
        case initialExplanation
    }
    private var mode = Mode.regular

    mutating func body(message: Message) -> LLM.Message.Body {
        switch message.author {
        case .agent:
            body(agentMessage: message)
        case .user:
            body(userMessage: message)
        }
    }

    private mutating func body(agentMessage: Message) -> LLM.Message.Body {
        switch agentMessage.content {
        case .plainText(let value), .markdown(let value):
            return .text(value)
        case .explanationResponse(let annotations, _, _):
            return .text(annotations.rawResponse)
        case .remoteCommandRequest(let request):
            if let call = request.llmMessage.function_call {
                return .functionCall(call,
                                     id: request.llmMessage.functionCallID)
            } else {
                return .uninitialized
            }
        case .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .vectorStoreCreated, .terminalCommand, .appendAttachment,
                .explanationRequest:
            it_fatalError()
        case .multipart(let subparts, _):
            return .multipart(subparts.compactMap { subpart -> LLM.Message.Body? in
                switch subpart {
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let code):
                        return .text(code)
                    case .statusUpdate:
                        return nil
                    case .file, .fileID:
                        return .attachment(attachment)
                    }
                case .markdown(let string), .plainText(let string):
                    return .text(string)
                }
            })
        }
    }

    private func prompt(terminalCommand: TerminalCommand) -> String {
        var lines = [String]()
        lines.append("iTerm2 is sending you this message automatically because the user enabled sending terminal commands to AI for assistance. If you can provide useful non-obvious insights, respond with those. Do not restate information that is obvious from the output. If there is nothing important to say, just respond with \"Got it.\"")
        lines.append("I executed the following command line:")
        lines.append(terminalCommand.command)
        if let directory = terminalCommand.directory {
            lines.append("My current directory was:")
            lines.append(directory)
        }
        if let hostname = terminalCommand.hostname {
            if let username = terminalCommand.username {
                lines.append("I am logged in as \(username)@\(hostname)")
            } else {
                lines.append("The current hostname is \(hostname)")
            }
        }
        lines.append("The exit status of the command was \(terminalCommand.exitCode)")
        lines.append("It produced this output:")
        lines.append(terminalCommand.output)
        return lines.joined(separator: "\n")
    }

    private mutating func body(userMessage: Message) -> LLM.Message.Body {
        switch userMessage.content {
        case .plainText(let value), .markdown(let value):
            defer {
                mode = .regular
            }
            switch mode {
            case .regular:
                return .text(value)
            case .initialExplanation:
                return .text(AIExplanationRequest.conversationalPrompt(userPrompt: value))
            }
        case .explanationRequest(let request):
            mode = .initialExplanation
            return .text(request.prompt())
        case .multipart(let subparts, _):
            return .multipart(subparts.compactMap { subpart -> LLM.Message.Body? in
                switch subpart {
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let code):
                        return .text(code)
                    case .statusUpdate:
                        return nil
                    case .file, .fileID:
                        return .attachment(attachment)
                    }
                case .markdown(let string), .plainText(let string):
                    return .text(string)
                }
            })
        case .remoteCommandResponse(let result, _, let functionName, let functionCallID):
            let output = result.map { value in
                value
            } failure: { error in
                "I was unable to complete the function call: " + error.localizedDescription
            }
            return .functionOutput(name: functionName,
                                   output: output,
                                   id: functionCallID)
        case .terminalCommand(let cmd):
            return .text(prompt(terminalCommand: cmd))
        case .explanationResponse, .append, .appendAttachment, .remoteCommandRequest,
                .selectSessionRequest, .clientLocal, .renameChat, .commit, .setPermissions,
                .vectorStoreCreated:
            it_fatalError()
        }
    }
}

class ChatAgent {
    private var conversation: AIConversation
    private let chatID: String
    private var brokerSubscription: ChatBroker.Subscription?
    private var messageToPrompt = MessageToPromptStateMachine()
    private var pendingRemoteCommands = [UUID: (Result<String, Error>) -> ()]()
    private let broker: ChatBroker
    private var renameConversation: AIConversation?

    private enum PipelineResult {
        case fileUploaded(id: String, name: String)
        case vectorStoreCreated(id: String)
        case filesAddedToVectorStore
        case completed

        var vectorStoreID: String? {
            if case let .vectorStoreCreated(id) = self {
                id
            } else {
                nil
            }
        }
    }
    private var pipelineQueue = PipelineQueue<PipelineResult>()

    init(_ chatID: String,
         broker: ChatBroker,
         registrationProvider: AIRegistrationProvider,
         messages: [Message]) {
        self.chatID = chatID
        self.broker = broker
        conversation = AIConversation(registrationProvider: registrationProvider)
        conversation.hostedTools.codeInterpreter = true
        var permissions = Set<RemoteCommand.Content.PermissionCategory>()
        for message in messages {
            switch message.content {
            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .terminalCommand,
                    .multipart:
                conversation.add(aiMessage(from: message))
                break

            case .selectSessionRequest, .clientLocal, .renameChat, .append, .appendAttachment,
                    .commit, .vectorStoreCreated:
                break

            case .setPermissions(let updated):
                permissions = updated
            }
        }
        updateSystemMessage(permissions)
    }

    private func updateSystemMessage(_ permissions: Set<RemoteCommand.Content.PermissionCategory>) {
        if permissions.isEmpty {
            conversation.systemMessage = "You help the user in a terminal emulator."
        } else if permissions.contains(.runCommands) || permissions.contains(.typeForYou) {
            conversation.systemMessage = "You help the user in a terminal emulator. You have the ability to run commands on their behalf and perform various other operations in terminal sessions. Don't be shy about using them, especially if they are safe to do, because the user must always grant permission for these functions to run. You don't need to request permission: the app will do that for you."
        } else {
            conversation.systemMessage = "You help the user in a terminal emulator. You have some access to the user's state with function calling. Don't by shy about using it because the user must always grant permission for functions to run. You don't need to request permission: the app will do that for you."
        }

        defineFunctions(in: &conversation, allowedCategories: permissions)
    }

    deinit {
        brokerSubscription?.unsubscribe()
    }

    private func aiMessage(from message: Message) -> AITermController.Message {
        let body = messageToPrompt.body(message: message)
        return AITermController.Message(role: AITermController.Message.role(from: message),
                                        body: body)
    }

    enum StreamingUpdate {
        case begin(Message)
        case append(String, UUID)
        case appendAttachment(LLM.Message.Attachment, UUID)
    }

    var supportsStreaming: Bool {
        return conversation.supportsStreaming
    }

    private func publishNotice(chatID: String, message: String) {
        broker.publishMessageFromAgent(
            chatID: chatID,
            content: .clientLocal(.init(action: .notice(message))))
    }

    private func ingestableFilesFromSubparts(_ parts: [Message.Subpart]) -> [LLM.Message.Attachment.AttachmentType.File] {
        return parts.compactMap { subpart -> LLM.Message.Attachment.AttachmentType.File? in
            switch subpart {
            case .attachment(let attachment):
                switch attachment.type {
                case .code, .statusUpdate:
                    it_fatalError("Unsupported user-sent attachment type")
                case .file(let file):
                    return file
                case .fileID:
                    // No need for ingestion
                    return nil
                }
            case .markdown, .plainText:
                return nil
            }
        }
    }

    private func textFromSubparts(_ parts: [Message.Subpart]) -> String {
        return parts.compactMap {
            switch $0 {
            case .attachment: nil
            case .markdown(let text), .plainText(let text): text
            }
        }.joined(separator: "\n")
    }

    private func uploadAction(chatID: String,
                              file: LLM.Message.Attachment.AttachmentType.File) -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] priorValues, completion in
            self?.conversation.uploadFile(
                name: file.name,
                content: file.content) { result in
                    self?.uploadFinished(chatID: chatID,
                                         file: file,
                                         result: result,
                                         completion: completion)
                }
        }
    }

    // Result here is the result of the upload, while the completion block
    // is for the pipeline action.
    private func uploadFinished(chatID: String,
                                file: LLM.Message.Attachment.AttachmentType.File,
                                result: Result<String, Error>,
                                completion: @escaping (Result<PipelineResult, Error>) -> Void) {
        switch result {
        case .success(let id):
            publishNotice(
                chatID: chatID,
                message: "Upload of \(file.name.lastPathComponent) finished.")
            completion(.success(.fileUploaded(id: id, name: file.name)))
        case .failure(let error):
            publishNotice(
                chatID: chatID,
                message: "Failed to upload \(file.name): \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    private func createVectorStoreAction(chatID: String) -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] _, completion in
            guard let self else {
                completion(.failure(AIError("Chat agent no longer exists")))
                return
            }
            conversation.createVectorStore(
                name: "iTerm2.\(chatID)") { [broker] result in
                    result.handle { id in
                        broker.publish(message: .init(
                            chatID: chatID,
                            author: .agent,
                            content: .vectorStoreCreated(id: id),
                            sentDate: Date(),
                            uniqueID: UUID()),
                                       toChatID: chatID,
                                       partial: false)
                        completion(.success(.vectorStoreCreated(id: id)))
                    } failure: { error in
                        completion(.failure(error))
                    }
                }
        }
    }

    private func addFilesToVectorStoreAction(previousResults: [UUID: PipelineResult],
                                             vectorStoreID: String?,
                                             completion: @escaping (Result<PipelineResult, Error>) -> ()) {
        let fileIDs = previousResults.values.compactMap { value -> String? in
            switch value {
            case let .fileUploaded(id: fileID, name: _): return fileID
            default:
                return nil
            }
        }
        let newVectorStoreID = previousResults.values.compactMap { value -> String? in
            switch value {
            case .vectorStoreCreated(id: let id): id
            default: nil
            }
        }.first
        let justVectorStoreID: String
        if let vectorStoreID {
            justVectorStoreID = vectorStoreID
        } else if let newVectorStoreID {
            justVectorStoreID = newVectorStoreID
        } else {
            completion(.failure(AIError("Missing vector store ID")))
            return
        }
        conversation.addFilesToVectorStore(fileIDs: fileIDs,
                                           vectorStoreID: justVectorStoreID,
                                           completion: { [weak self, chatID] error in
            if let error {
                self?.publishNotice(
                    chatID: chatID,
                    message: "There was a problem adding files to the vector store: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                completion(.success(.filesAddedToVectorStore))
            }
        })
    }

    private func ingestFiles(files: [LLM.Message.Attachment.AttachmentType.File],
                             chatID: String,
                             vectorStoreID: String?,
                             builder: PipelineBuilder<PipelineResult>) -> PipelineBuilder<PipelineResult> {
        var currentBuilder = builder
        if vectorStoreID == nil {
            print("Need to create a vector store")
            currentBuilder.add(description: "Create vector store",
                               actionClosure: createVectorStoreAction(chatID: chatID))
            currentBuilder = currentBuilder.makeChild()
        }
        for file in files {
            print("Add upload action for \(file.name)")
            currentBuilder.add(description: "Upload \(file.name)",
                               actionClosure: uploadAction(
                chatID: chatID,
                file: file))
        }
        currentBuilder = currentBuilder.makeChild()

        currentBuilder.add(description: "Add files to vector store") { [weak self] previousResults, completion in
            self?.addFilesToVectorStoreAction(previousResults: previousResults,
                                              vectorStoreID: vectorStoreID,
                                              completion: completion)
        }
        return currentBuilder.makeChild()
    }

    private func scheduleMultipartFetch(userMessage: Message,
                                        parts: [Message.Subpart],
                                        vectorStoreID: String?,
                                        streaming: ((StreamingUpdate) -> ())?,
                                        completion: @escaping (Message?) -> ()) {
        print("qqq scheduling multipart fetch")
        let rootBuilder = PipelineBuilder<PipelineResult>()
        var currentBuilder = rootBuilder

        let files = ingestableFilesFromSubparts(parts)
        let text = textFromSubparts(parts)

        print("files=\(files.map(\.name).joined(separator: ", "))")
        print("text=\(text)")
        if !files.isEmpty {
            publishNotice(chatID: chatID, message: "Uploading…")
            currentBuilder = ingestFiles(files: files,
                                         chatID: userMessage.chatID,
                                         vectorStoreID: vectorStoreID,
                                         builder: currentBuilder)
        }
        currentBuilder.add(description: "Send message") { [weak self] values, actionCompletion in
            print("Ready to send the message now that all files are uploaded")
            let fileIDs = values.values.compactMap {
                switch $0 {
                case .fileUploaded(id: let fileID, name: let name): (fileID, name)
                default: nil
                }
            }
            let attachments = fileIDs.map {
                Message.Subpart.attachment(LLM.Message.Attachment(inline: false,
                                                                  id: $0.0,
                                                                  type: .fileID(id: $0.0, name: $0.1)))
            }
            self?.fetchCompletion(
                userMessage: Message(chatID: userMessage.chatID,
                                     author: userMessage.author,
                                     content: .multipart([.plainText(text)] + attachments,
                                                         vectorStoreID: nil),
                                     sentDate: userMessage.sentDate,
                                     uniqueID: userMessage.uniqueID),
                cancelPendingUploads: false,
                streaming: streaming,
                completion: completion)
        }
        print("Add to pipeline queue")
        pipelineQueue.append(rootBuilder.build(maxConcurrentActions: 2) { [chatID] disposition in
            switch disposition {
            case .pending:
                it_fatalError()
            case .success(_):
                return
            case .failure, .canceled:
                completion(Message(chatID: chatID,
                                   author: .agent,
                                   content: .clientLocal(.init(action: .notice(
                                    "Your message was not sent because of a problem with an attached file."))),
                                   sentDate: Date(),
                                   uniqueID: UUID()))
            }
        })
    }

    func fetchCompletion(userMessage: Message,
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) {
        fetchCompletion(userMessage: userMessage,
                        cancelPendingUploads: true,
                        streaming: streaming,
                        completion: completion)
    }

    private func multipartMessageIsSendable(parts: [Message.Subpart]) -> Bool {
        return parts.allSatisfy({ subpart in
            switch subpart {
            case .attachment(let attachment):
                switch attachment.type {
                case .fileID: true
                case .file(let file): file.mimeType != "application/pdf"
                default: false
                }
            case .plainText: true
            default: false
            }
        })
    }

    func fetchCompletion(userMessage: Message,
                         cancelPendingUploads: Bool,
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) {
        if cancelPendingUploads {
            pipelineQueue.cancelAll()
        }
        switch userMessage.content {
        case .multipart(let parts, let maybeVectorStoreID):
            if !multipartMessageIsSendable(parts: parts) {
                scheduleMultipartFetch(userMessage: userMessage,
                                       parts: parts,
                                       vectorStoreID: maybeVectorStoreID,
                                       streaming: streaming,
                                       completion: completion)
                return
            }
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .selectSessionRequest, .clientLocal, .commit,
                .terminalCommand:
            break
        case .renameChat, .append:
            return
        case .remoteCommandResponse(let result, let messageID, _, _):
            if let pending = pendingRemoteCommands[messageID] {
                NSLog("Agent handling remote command response to message \(messageID)")
                pendingRemoteCommands.removeValue(forKey: messageID)
                pending(Result(result))
                return
            }
        case .setPermissions(let allowedCategories):
            defineFunctions(in: &conversation,
                            allowedCategories: allowedCategories)
            updateSystemMessage(allowedCategories)
            completion(nil)
            return
        case .vectorStoreCreated:
            it_fatalError("User should not create vector store")
        case .appendAttachment:
            it_fatalError("User-sent attachments not supported")
        }

        let needsRenaming = !conversation.messages.anySatisfies({ $0.role == .user})
        if let configuration = userMessage.configuration {
            conversation.hostedTools.webSearch = configuration.hostedWebSearchEnabled
        }
#warning("TODO: Make this configurable maybe?")
        conversation.hostedTools.codeInterpreter = true
        if let vectorStoreIDs = userMessage.configuration?.vectorStoreIDs, !vectorStoreIDs.isEmpty {
            conversation.hostedTools.fileSearch = .init(vectorstoreIDs: vectorStoreIDs)
        }
        conversation.add(aiMessage(from: userMessage))
        var uuid: UUID?
        let streamingCallback: ((LLM.StreamingUpdate) -> ())?
        if let streaming {
            streamingCallback = { streamingUpdate in
                switch streamingUpdate {
                case .appendAttachment(let chunk):
                    if uuid == nil,
                       let initialMessage = Self.message(attachment: chunk,
                                                         userMessage: userMessage) {
                        streaming(.begin(initialMessage))
                        uuid = initialMessage.uniqueID
                    } else if let uuid {
                        streaming(.appendAttachment(chunk, uuid))
                    }
                case .append(let chunk):
                    if uuid == nil,
                       let initialMessage = Self.message(completionText: chunk,
                                                         userMessage: userMessage,
                                                         streaming: true) {
                        streaming(.begin(initialMessage))
                        uuid = initialMessage.uniqueID
                    } else if let uuid {
                        streaming(.append(chunk, uuid))
                    }
                }
            }
        } else {
            streamingCallback = nil
        }
        conversation.complete(streaming: streamingCallback) { [weak self] result in
            guard let self else {
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
        renameConversation = AIConversation(
            registrationProvider: nil,
            messages: conversation.messages + [AITermController.Message(role: .user, content: prompt)])
        var failed = false
        renameConversation?.complete { [weak self] (result: Result<AIConversation, Error>) in
            if let newName = result.successValue?.messages.last?.body.content {
                self?.renameChat(newName)
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
        return self.message(completionText: text, userMessage: userMessage, streaming: false)
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
                               content: .plainText("🛑 The text to analyze was too long. Select a portion of it and try again."),
                               sentDate: Date(),
                               uniqueID: UUID())
            }

            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .plainText("🛑 I ran into a problem: \(error.localizedDescription)"),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
    }

    // This is for a committed message or an initial message in a stream.
    private static func message(completionText text: String,
                                userMessage: Message,
                                streaming: Bool) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand, .remoteCommandResponse, .multipart:
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .markdown(text),
                           sentDate: Date(),
                           uniqueID: UUID())
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
                uniqueID: messageID)
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .appendAttachment, .vectorStoreCreated:
            it_fatalError()
        }
    }

    // Streaming only
    private static func message(attachment: LLM.Message.Attachment,
                                userMessage: Message) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand, .remoteCommandResponse, .multipart:
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .multipart(
                            [.attachment(attachment)],
                            vectorStoreID: nil),
                           sentDate: Date(),
                           uniqueID: UUID())
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
                uniqueID: messageID)
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .appendAttachment, .vectorStoreCreated:
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

extension RemoteCommand.Content {
    var functionName: String {
        switch self {
        case .isAtPrompt:
            "is_at_prompt"
        case .executeCommand:
            "execute_command"
        case .getLastExitStatus:
            "get_last_exit_status"
        case .getCommandHistory:
            "get_command_history"
        case .getLastCommand:
            "get_last_command"
        case .getCommandBeforeCursor:
            "get_command_before_cursor"
        case .searchCommandHistory:
            "search_command_history"
        case .getCommandOutput:
            "get_command_output"
        case .getTerminalSize:
            "get_terminal_size"
        case .getShellType:
            "get_shell_type"
        case .detectSSHSession:
            "detect_ssh_session"
        case .getRemoteHostname:
            "get_remote_hostname"
        case .getUserIdentity:
            "get_user_identity"
        case .getCurrentDirectory:
            "get_current_directory"
        case .setClipboard:
            "set_clipboard"
        case .insertTextAtCursor:
            "insert_text_at_cursor"
        case .deleteCurrentLine:
            "delete_current_line"
        case .getManPage:
            "get_man_page"
        case .createFile:
            "create_file"
        }
    }

    var argDescriptions: [String: String] {
        return switch self {
        case .isAtPrompt(_):
            [:]
        case .executeCommand(_):
            ["command": "The command to run"]
        case .getLastExitStatus(_):
            [:]
        case .getCommandHistory(_):
            ["limit": "Maximum number of history items to return."]
        case .getLastCommand(_):
            [:]
        case .getCommandBeforeCursor(_):
            [:]
        case .searchCommandHistory(_):
            ["query": "Search query for filtering command history."]
        case .getCommandOutput(_):
            ["id": "Unique identifier of the command whose output is requested."]
        case .getTerminalSize(_):
            [:]
        case .getShellType(_):
            [:]
        case .detectSSHSession(_):
            [:]
        case .getRemoteHostname(_):
            [:]
        case .getUserIdentity(_):
            [:]
        case .getCurrentDirectory(_):
            [:]
        case .setClipboard(_):
            ["text": "The text to copy to the clipboard."]
        case .insertTextAtCursor(_):
            ["text": "The text to insert at the cursor position. Consider whether execute_command would be a better choice, especially when running a command at the shell prompt since insert_text_at_cursor does not return the output to you."]
        case .deleteCurrentLine(_):
            [:]
        case .getManPage(_):
            ["cmd": "The command whose man page content is requested."]
        case .createFile:
            ["filename": "The name of the file you wish to create. It will be replaced if it already exists.",
             "content": "The content that will be written to the file."]
        }
    }

    var functionDescription: String {
        switch self {
        case .isAtPrompt(_):
            "Returns true if the terminal is at the command prompt, allowing safe command injection."
        case .executeCommand(_):
            "Runs a shell command and returns its output."
        case .getLastExitStatus(_):
            "Retrieves the exit status of the last executed command."
        case .getCommandHistory(_):
            "Returns the recent command history."
        case .getLastCommand(_):
            "Retrieves the most recent command."
        case .getCommandBeforeCursor(_):
            "Returns the current partially typed command before the cursor."
        case .searchCommandHistory(_):
            "Searches history for commands matching a query."
        case .getCommandOutput(_):
            "Returns the output of a previous command by its unique identifier."
        case .getTerminalSize(_):
            "Returns (columns, rows) of the terminal window."
        case .getShellType(_):
            "Detects the shell in use (e.g., bash, zsh, fish)."
        case .detectSSHSession(_):
            "Returns true if the user is SSH’ed into a remote host."
        case .getRemoteHostname(_):
            "Returns the remote hostname if in an SSH session."
        case .getUserIdentity(_):
            "Returns the logged-in user’s username."
        case .getCurrentDirectory(_):
            "Returns the current directory."
        case .setClipboard(_):
            "Copies text to the clipboard."
        case .insertTextAtCursor(_):
            "Inserts text into the terminal input at the cursor position."
        case .deleteCurrentLine(_):
            "Clears the current command line input (only at the prompt)."
        case .getManPage(_):
            "Returns the content of a command's man page."
        case .createFile:
            "Creates a file containing a specified string."
        }
    }
}

extension ChatAgent {
    func defineFunctions(in conversation: inout AIConversation,
                         allowedCategories: Set<RemoteCommand.Content.PermissionCategory>) {
        conversation.removeAllFunctions()
        for content in RemoteCommand.Content.allCases {
            guard allowedCategories.contains(content.permissionCategory) else {
                continue
            }
            switch content {
            case .isAtPrompt(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .isAtPrompt(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .executeCommand(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .executeCommand(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getLastExitStatus(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getLastExitStatus(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCommandHistory(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCommandHistory(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getLastCommand(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getLastCommand(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCommandBeforeCursor(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCommandBeforeCursor(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .searchCommandHistory(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .searchCommandHistory(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCommandOutput(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCommandOutput(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getTerminalSize(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getTerminalSize(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getShellType(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getShellType(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .detectSSHSession(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .detectSSHSession(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getRemoteHostname(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getRemoteHostname(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getUserIdentity(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getUserIdentity(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCurrentDirectory(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCurrentDirectory(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .setClipboard(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .setClipboard(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .insertTextAtCursor(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .insertTextAtCursor(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .deleteCurrentLine(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .deleteCurrentLine(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getManPage(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getManPage(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .createFile(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .createFile(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            }
        }
    }

    // MARK: - Function Calling Ingra

    private func renameChat(_ newName: String) {
        broker.publish(message: .init(chatID: chatID,
                                      author: .agent,
                                      content: .renameChat(newName),
                                      sentDate: Date(),
                                      uniqueID: UUID()),
                       toChatID: chatID,
                       partial: false)
    }

    private func runRemoteCommand(_ remoteCommand: RemoteCommand, completion: @escaping (Result<String, Error>) -> ()) {
        let requestID = UUID()
        pendingRemoteCommands[requestID] = completion
        broker.publish(message: .init(chatID: chatID,
                                      author: .agent,
                                      content: .remoteCommandRequest(remoteCommand),
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
