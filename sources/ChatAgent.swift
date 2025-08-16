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
                .explanationRequest, .userCommand:
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
                .vectorStoreCreated, .userCommand:
            it_fatalError()
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

    struct PendingRemoteCommand {
        var completion: (Result<String, Error>) throws -> ()
        var responseID: String?
    }

    private enum PipelineResult {
        case fileUploaded(id: String, name: String)
        case zipCreated(URL, Data)
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
    private var permissions: Set<RemoteCommand.Content.PermissionCategory>!
    private let registrationProvider: AIRegistrationProvider

    init(_ chatID: String,
         broker: ChatBroker,
         registrationProvider: AIRegistrationProvider,
         messages: [Message]) {
        self.chatID = chatID
        self.broker = broker
        self.registrationProvider = registrationProvider
        permissions = Set<RemoteCommand.Content.PermissionCategory>()
        conversation = AIConversation(registrationProvider: registrationProvider)
        conversation.hostedTools.codeInterpreter = true
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

    enum StreamingUpdate {
        case begin(Message)
        case append(String, UUID)
        case appendAttachment(LLM.Message.Attachment, UUID)
    }

    var supportsStreaming: Bool {
        return conversation.supportsStreaming
    }

    private func publishNotice(chatID: String, message: String) throws {
        try broker.publishMessageFromAgent(
            chatID: chatID,
            content: .clientLocal(.init(action: .notice(message))))
    }

    private func uploadableFilesFromSubparts(_ parts: [Message.Subpart]) -> [LLM.Message.Attachment.AttachmentType.File] {
        guard let provider = AITermController.provider else {
            return []
        }
        if provider.model.vectorStoreConfig == .disabled {
            return []
        }
        return parts.compactMap { subpart -> LLM.Message.Attachment.AttachmentType.File? in
            switch subpart {
            case .attachment(let attachment):
                switch attachment.type {
                case .code, .statusUpdate:
                    it_fatalError("Unsupported user-sent attachment type")
                case .file(let file):
                    if provider.shouldInlineBase64EncodedFile(mimeType: file.mimeType) == true {
                        return nil
                    }
                    if MIMETypeIsTextual(file.mimeType) {
                        return nil
                    }
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
        return parts.compactMap { part -> String? in
            switch part {
            case .attachment(let attachment):
                switch attachment.type {
                case .code(let text):
                    return text
                case .statusUpdate:
                    return nil
                case .file(let file):
                    if !MIMETypeIsTextual(file.mimeType) {
                        return nil
                    }
                    return file.content.lossyString
                case .fileID: return nil
                }
            case .plainText(let text), .markdown(let text):
                return text
            }
        }.joined(separator: "\n")
    }

    private func inlineFilesFromSubparts(_ parts: [Message.Subpart]) -> [LLM.Message.Attachment.AttachmentType.File] {
        return parts.compactMap { part -> LLM.Message.Attachment.AttachmentType.File? in
            switch part {
            case .attachment(let attachment):
                switch attachment.type {
                case .code, .statusUpdate, .fileID:
                    return nil
                case .file(let file):
                    if let provider = AITermController.provider,
                       provider.shouldInlineBase64EncodedFile(mimeType: file.mimeType) == true {
                        return file
                    }
                    return nil
                }
            case .plainText, .markdown:
                return nil
            }
        }
    }

    private func uploadAction(chatID: String,
                              fileName: String,
                              fileContent: Data) -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] priorValues, completion in
            self?.conversation.uploadFile(
                name: fileName,
                content: fileContent) { result in
                    try? self?.uploadFinished(chatID: chatID,
                                              fileName: fileName,
                                              description: fileName.lastPathComponent,
                                              result: result,
                                              completion: completion)
                }
        }
    }

    // Result here is the result of the upload, while the completion block
    // is for the pipeline action.
    private func uploadFinished(chatID: String,
                                fileName: String,
                                description: String,
                                result: Result<String, Error>,
                                completion: @escaping (Result<PipelineResult, Error>) throws -> Void) throws {
        switch result {
        case .success(let id):
            try publishNotice(
                chatID: chatID,
                message: "Upload of \(description) finished.")
            try completion(.success(.fileUploaded(id: id, name: fileName)))
        case .failure(let error):
            try publishNotice(
                chatID: chatID,
                message: "Failed to upload \(fileName): \(error.localizedDescription)")
            try completion(.failure(error))
        }
    }

    private func createVectorStoreAction(chatID: String) throws -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] _, completion in
            guard let self else {
                try completion(.failure(AIError("Chat agent no longer exists")))
                return
            }
            conversation.createVectorStore(
                name: "iTerm2.\(chatID)") { [weak self, broker] result in
                    try? result.handle { id in
                        try broker.publish(message: .init(
                            chatID: chatID,
                            author: .agent,
                            content: .vectorStoreCreated(id: id),
                            sentDate: Date(),
                            uniqueID: UUID()),
                                       toChatID: chatID,
                                       partial: false)
                        try? completion(.success(.vectorStoreCreated(id: id)))
                    } failure: { error in
                        try self?.publishNotice(
                            chatID: chatID,
                            message: "There was a problem creating a vector store database: \(error.localizedDescription)")
                        try? completion(.failure(error))
                    }
                }
        }
    }

    private func addFilesToVectorStoreAction(previousResults: [UUID: PipelineResult],
                                             vectorStoreID: String?,
                                             completion: @escaping (Result<PipelineResult, Error>) throws -> ()) {
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
            try? completion(.failure(AIError("Missing vector store ID")))
            return
        }
        conversation.addFilesToVectorStore(fileIDs: fileIDs,
                                           vectorStoreID: justVectorStoreID,
                                           completion: { [weak self, chatID] error in
            if let error, error as? PluginError == .cancelled {
                try? completion(.failure(error))
                return
            }
            if let error {
                try? self?.publishNotice(
                    chatID: chatID,
                    message: "There was a problem adding files to the vector store: \(error.localizedDescription)")
                try? completion(.failure(error))
            } else {
                try? completion(.success(.filesAddedToVectorStore))
            }
        })
    }

    private func makeZipAction(files: [LLM.Message.Attachment.AttachmentType.File]) -> Pipeline<PipelineResult>.Action.Closure {
        return { _, completion in
            let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: stagingDir,
                                                     withIntermediateDirectories: true, attributes: nil)
            var usedNames = Set<String>()
            var sourceURLs = [URL]()
            for file in files {
                var name = file.name
                var i = 1
                while usedNames.contains(name) {
                    name = name.deletingPathExtension + " (\(i))" + name.pathExtension
                    i += 1
                }
                usedNames.insert(name)
                let dest = stagingDir.appendingPathComponent(name)
                do {
                    try file.content.write(to: dest)
                    sourceURLs.append(URL(fileURLWithPath: name,
                                          relativeTo: stagingDir))
                } catch {
                    DLog("\(error)")
                }
            }
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let zipURL = tempDir.appendingPathComponent(Self.zipName)
            iTermCommandRunner.zip(sourceURLs,
                                   arguments: [],
                                   toZip: zipURL,
                                   relativeTo: stagingDir,
                                   callbackQueue: .main) { ok in
                if !ok {
                    try? completion(.failure(AIError("Failed to zip attached files")))
                    return
                }
                do {
                    let data = try Data(contentsOf: zipURL)
                    try? completion(.success(.zipCreated(zipURL, data)))
                } catch {
                    try? completion(.failure(error))
                }
            }
        }
    }

    private static let zipName = "files.zip"

    private func uploadZipAction(zipID: UUID, chatID: String) -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] priorValues, completion in
            guard case let .zipCreated(url, data) = priorValues[zipID]! else {
                it_fatalError()
            }
            self?.conversation.uploadFile(
                name: Self.zipName,
                content: data) { result in
                    try? self?.uploadFinished(chatID: chatID,
                                              fileName: url.path,
                                              description: "attachments",
                                              result: result,
                                              completion: completion)
                }
        }
    }

    // Upload and maybe add to vector store.
    private func ingestFiles(files: [LLM.Message.Attachment.AttachmentType.File],
                             chatID: String,
                             addToVectorStore: Bool,
                             vectorStoreID: String?,
                             builder: PipelineBuilder<PipelineResult>) throws -> PipelineBuilder<PipelineResult> {
        var currentBuilder = builder
        if addToVectorStore {
            if vectorStoreID == nil {
                DLog("Need to create a vector store")
                try currentBuilder.add(description: "Create vector store",
                                       actionClosure: createVectorStoreAction(chatID: chatID))
                currentBuilder = currentBuilder.makeChild()
            }
            for file in files {
                DLog("Add upload action for \(file.name)")
                _ = try currentBuilder.add(description: "Upload \(file.name)",
                                           actionClosure: uploadAction(
                                            chatID: chatID,
                                            fileName: file.name,
                                            fileContent: file.content))
            }
            currentBuilder = currentBuilder.makeChild()
            try currentBuilder.add(description: "Add files to vector store") { [weak self] previousResults, completion in
                self?.addFilesToVectorStoreAction(previousResults: previousResults,
                                                  vectorStoreID: vectorStoreID,
                                                  completion: completion)
            }
        } else {
            // Uploading for code interpreter. First zip the files, then upload them.
            let zipID = try currentBuilder.add(description: "Zip files",
                                               actionClosure: makeZipAction(files: files))
            currentBuilder = currentBuilder.makeChild()
            DLog("Add upload action for zip file")
            try currentBuilder.add(description: "Upload zip file",
                                   actionClosure: uploadZipAction(zipID: zipID,
                                                                  chatID: chatID))
        }

        return currentBuilder.makeChild()
    }

    private func scheduleMultipartFetch(uploadFiles files: [LLM.Message.Attachment.AttachmentType.File],
                                        text: String,
                                        inlineFiles: [LLM.Message.Attachment.AttachmentType.File],
                                        userMessage: Message,
                                        history: [Message],
                                        parts: [Message.Subpart],
                                        vectorStoreID: String?,
                                        streaming: ((StreamingUpdate) -> ())?,
                                        completion: @escaping (Message?) -> ()) throws {
        DLog("scheduling multipart fetch")
        let rootBuilder = PipelineBuilder<PipelineResult>()
        var currentBuilder = rootBuilder

        DLog("files=\(files.map(\.name).joined(separator: ", "))")
        DLog("text=\(text)")
        if !files.isEmpty {
            try publishNotice(chatID: chatID, message: "Uploading…")
            currentBuilder = try ingestFiles(files: files,
                                             chatID: userMessage.chatID,
                                             addToVectorStore: false,
                                             vectorStoreID: vectorStoreID,
                                             builder: currentBuilder)
        }
        try currentBuilder.add(description: "Send message") { [weak self] values, actionCompletion in
            DLog("Ready to send the message now that all files are uploaded")
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
            } + inlineFiles.map {
                Message.Subpart.attachment(LLM.Message.Attachment(inline: true,
                                                                  id: UUID().uuidString,
                                                                  type: .file($0)))
            }
            try self?.fetchCompletion(
                userMessage: Message(chatID: userMessage.chatID,
                                     author: userMessage.author,
                                     content: .multipart([.plainText(text)] + attachments,
                                                         vectorStoreID: nil),
                                     sentDate: userMessage.sentDate,
                                     uniqueID: userMessage.uniqueID),
                history: history,
                cancelPendingUploads: false,
                streaming: streaming,
                completion: completion)
        }
        DLog("Add to pipeline queue")
        pipelineQueue.append(rootBuilder.build(maxConcurrentActions: 2) { [chatID] disposition in
            switch disposition {
            case .success:
                break
            default:
                completion(nil)
            }
            DLog("disposition for \(chatID) is \(disposition)")
        })
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

    private func shouldUploadAnyParts(parts: [Message.Subpart]) -> Bool {
        return !uploadableFilesFromSubparts(parts).isEmpty
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
        if cancelPendingUploads {
            pipelineQueue.cancelAll()
        }
        switch userMessage.content {
        case .multipart(let parts, let maybeVectorStoreID):
            let uploads = uploadableFilesFromSubparts(parts)

            if !uploads.isEmpty {
                let text = textFromSubparts(parts)
                let inlineFiles = inlineFilesFromSubparts(parts)
                try scheduleMultipartFetch(uploadFiles: uploads,
                                           text: text,
                                           inlineFiles: inlineFiles,
                                           userMessage: userMessage,
                                           history: history,
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
                try? pending.completion(Result(result))
                return
            }
        case .setPermissions(let allowedCategories):
            defineFunctions(in: &conversation,
                            allowedCategories: allowedCategories)
            updateSystemMessage(allowedCategories)
            completion(nil)
            return
        case .userCommand:
            it_fatalError("User commands should not reach fetchCompletion")
        case .vectorStoreCreated:
            it_fatalError("User should not create vector store")
        case .appendAttachment:
            it_fatalError("User-sent attachments not supported")
        }

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
        var uuid: UUID?
        let streamingCallback: ((LLM.StreamingUpdate, String?) -> ())?
        if let streaming {
            streamingCallback = { streamingUpdate, responseID in
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
        renameConversation = AIConversation(
            registrationProvider: nil,
            messages: conversation.messages + [AITermController.Message(role: .user, content: prompt)])
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
        case .searchBrowser:
            "find_on_page"
        case .loadURL:
            "load_url"
        case .webSearch:
            "web_search_in_browser"
        case .getURL:
            "get_current_url"
        case .readWebPage:
            "read_web_page_section"
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
        case .searchBrowser(_):
            ["query": "The text to search for on the current page."]
        case .loadURL(_):
            ["url": "The URL to load. Must use https scheme."]
        case .webSearch(_):
            ["query": "The web search query"]
        case .getURL(_):
            [:]
        case .readWebPage(_):
            ["startingLineNumber": "The line number to start reading at.",
             "numberOfLines": "The number of lines to return."]
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
            "Creates a file containing a specified string on the user's computer and then reveals it in Finder."
        case .loadURL:
            "Loads the specified URL in the associated web browser"
        case .webSearch:
            "Performs a web search using the currently configured search engine in the associated web browser"
        case .getURL:
            "Returns the current URL of the associated web browser"
        case .readWebPage:
            "Returns some of the content (in markdown format) of the page visible in the associated web browser."
        case .searchBrowser(_):
            "Searches the current web page in the associated web browser (after converting to markdown format) for a substring."
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
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
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
                    })
            case .searchBrowser(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .searchBrowser(command))
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
                    })
            case .loadURL(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .loadURL(command))
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
                    })
            case .webSearch(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .webSearch(command))
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
                    })
            case .getURL(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getURL(command))
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
                    })
            case .readWebPage(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .readWebPage(command))
                        try self?.runRemoteCommand(remoteCommand, llmMessage.responseID, completion: completion)
                    })
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
        let requestID = UUID()
        pendingRemoteCommands[requestID] = .init(completion: completion,
                                                 responseID: responseID)
        try broker.publish(message: .init(chatID: chatID,
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
