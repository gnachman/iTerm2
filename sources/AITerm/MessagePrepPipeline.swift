//
//  MessagePrepPipeline.swift
//  iTerm2
//
//  Created by George Nachman on 8/18/25.
//

protocol MessagePrepPipelineDelegate: AnyObject {
    func uploadFile(name: String,
                    content: Data,
                    completion: @escaping (Result<String, Error>) -> ())

    func publishNotice(chatID: String, message: String) throws
    func publish(message: Message, toChatID chatID: String, partial: Bool) throws

    func createVectorStore(name: String, completion: @escaping (Result<String, Error>) -> ())
    func addFilesToVectorStore(fileIDs: [String],
                               vectorStoreID: String,
                               completion: @escaping (Error?) -> ())
    func fetchCompletion(userMessage: Message,
                         history: [Message],
                         cancelPendingUploads: Bool,
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) throws
}

class MessagePrepPipeline {
    private let chatID: String
    private var pipelineQueue = PipelineQueue<PipelineResult>()
    weak var delegate: MessagePrepPipelineDelegate?

    init(chatID: String) {
        self.chatID = chatID
    }
}

// MARK: - Public API

extension MessagePrepPipeline {
    func cancelAll() {
        pipelineQueue.cancelAll()
    }

    func handleMultipartUserMessage(userMessage: Message,
                                    history: [Message],
                                    streaming: ((StreamingUpdate) -> ())?,
                                    completion: @escaping (Message?) -> ()) throws -> Bool {
        switch userMessage.content {
        case .multipart(let parts, let maybeVectorStoreID):
            let uploads = uploadableFilesFromSubparts(parts)

            if uploads.isEmpty {
                return false
            }
            let text = textFromSubparts(parts)
            let inlineFiles = inlineFilesFromSubparts(parts)
            try scheduleMultipartFetch(uploadFiles: uploads,
                                       text: text,
                                       context: contextFromSubparts(parts),
                                       inlineFiles: inlineFiles,
                                       userMessage: userMessage,
                                       history: history,
                                       parts: parts,
                                       vectorStoreID: maybeVectorStoreID,
                                       streaming: streaming,
                                       completion: completion)
        default:
            it_fatalError()
        }
        return true
    }
}

private extension MessagePrepPipeline {
    enum PipelineResult {
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

    func uploadableFilesFromSubparts(_ parts: [Message.Subpart]) -> [LLM.Message.Attachment.AttachmentType.File] {
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
            case .markdown, .plainText, .context:
                return nil
            }
        }
    }

    func textFromSubparts(_ parts: [Message.Subpart]) -> String {
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
            case .context:
                return nil
            }
        }.joined(separator: "\n")
    }

    func contextFromSubparts(_ parts: [Message.Subpart]) -> String {
        return parts.compactMap { part -> String? in
            switch part {
            case .plainText, .markdown, .attachment:
                return nil
            case .context(let text):
                return text
            }
        }.joined(separator: "\n")
    }

    func inlineFilesFromSubparts(_ parts: [Message.Subpart]) -> [LLM.Message.Attachment.AttachmentType.File] {
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
            case .plainText, .markdown, .context:
                return nil
            }
        }
    }

    func uploadAction(chatID: String,
                      fileName: String,
                      fileContent: Data) -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] priorValues, completion in
            self?.delegate?.uploadFile(
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
    func uploadFinished(chatID: String,
                        fileName: String,
                        description: String,
                        result: Result<String, Error>,
                        completion: @escaping (Result<PipelineResult, Error>) throws -> Void) throws {
        switch result {
        case .success(let id):
            try delegate?.publishNotice(
                chatID: chatID,
                message: "Upload of \(description) finished.")
            try completion(.success(.fileUploaded(id: id, name: fileName)))
        case .failure(let error):
            try delegate?.publishNotice(
                chatID: chatID,
                message: "Failed to upload \(fileName): \(error.localizedDescription)")
            try completion(.failure(error))
        }
    }

    func createVectorStoreAction(chatID: String) throws -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] _, completion in
            guard let self else {
                try completion(.failure(AIError("Chat agent no longer exists")))
                return
            }
            delegate?.createVectorStore(
                name: "iTerm2.\(chatID)") { [weak self] result in
                    try? result.handle { id in
                        try self?.delegate?.publish(message: .init(
                            chatID: chatID,
                            author: .agent,
                            content: .vectorStoreCreated(id: id),
                            sentDate: Date(),
                            uniqueID: UUID()),
                                                    toChatID: chatID,
                                                    partial: false)
                        try? completion(.success(.vectorStoreCreated(id: id)))
                    } failure: { error in
                        try self?.delegate?.publishNotice(
                            chatID: chatID,
                            message: "There was a problem creating a vector store database: \(error.localizedDescription)")
                        try? completion(.failure(error))
                    }
                }
        }
    }

    func addFilesToVectorStoreAction(previousResults: [UUID: PipelineResult],
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
        delegate?.addFilesToVectorStore(fileIDs: fileIDs,
                                        vectorStoreID: justVectorStoreID,
                                        completion: { [weak self, chatID] error in
            if let error, error as? PluginError == .cancelled {
                try? completion(.failure(error))
                return
            }
            if let error {
                try? self?.delegate?.publishNotice(
                    chatID: chatID,
                    message: "There was a problem adding files to the vector store: \(error.localizedDescription)")
                try? completion(.failure(error))
            } else {
                try? completion(.success(.filesAddedToVectorStore))
            }
        })
    }

    func makeZipAction(files: [LLM.Message.Attachment.AttachmentType.File]) -> Pipeline<PipelineResult>.Action.Closure {
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

    static let zipName = "files.zip"

    func uploadZipAction(zipID: UUID, chatID: String) -> Pipeline<PipelineResult>.Action.Closure {
        return { [weak self] priorValues, completion in
            guard case let .zipCreated(url, data) = priorValues[zipID]! else {
                it_fatalError()
            }
            self?.delegate?.uploadFile(
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
    func ingestFiles(files: [LLM.Message.Attachment.AttachmentType.File],
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

    func scheduleMultipartFetch(uploadFiles files: [LLM.Message.Attachment.AttachmentType.File],
                                text: String,
                                context: String?,
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
            try delegate?.publishNotice(chatID: chatID, message: "Uploading…")
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
            var tweaked = userMessage
            var subparts = [.plainText(text)] + attachments
            if let context {
                subparts.append(.context(context))
            }
            tweaked.content = .multipart(subparts,
                                         vectorStoreID: nil)
            try self?.delegate?.fetchCompletion(
                userMessage: tweaked,
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

    func shouldUploadAnyParts(parts: [Message.Subpart]) -> Bool {
        return !uploadableFilesFromSubparts(parts).isEmpty
    }
}
