import Foundation

protocol AITermControllerDelegate: AnyObject {
    func aitermControllerWillSendRequest(_ sender: AITermController)
    func aitermController(_ sender: AITermController, offerChoice: String)
    // update will be nil upon completion
    func aitermController(_ sender: AITermController, didStreamUpdate update: String?)
    func aitermController(_ sender: AITermController, didStreamAttachment: LLM.Message.Attachment)
    func aitermController(_ sender: AITermController, didFailWithError: Error)
    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ())
    func aitermController(_ sender: AITermController,
                          didCreateVectorStore id: String,
                          withName name: String)
    func aitermController(_ sender: AITermController,
                          didFailToCreateVectorStoreWithError: Error)

    func aitermController(_ sender: AITermController,
                          didUploadFileWithID id: String)
    func aitermController(_ sender: AITermController,
                          didFailToUploadFileWithError: Error)
    func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController)
    func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: Error)
}

struct ChatGPTFunctionDeclaration: Codable {
    var name: String
    var description: String
    var parameters: JSONSchema
}

class AITermController {
    typealias Message = LLM.Message
    var representedObject: String?
    private(set) var functions = [LLM.AnyFunction]()
    var truncate: (([Message]) -> ([Message]))?

    struct Registration {
        var apiKey: String

        init?(apiKey: String?) {
            guard let apiKey else {
                return nil
            }
            guard !apiKey.trimmingLeadingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            self.apiKey = apiKey
        }
    }

    enum Query: Equatable {
        case completion(String)
        case createVectorStore(name: String)
        case fileUpload(name: String, content: Data)
        case addFilesToVectorStore(fileIDs: [String], vectorStoreID: String)
    }

    enum State: Equatable, CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .ground: return "ground"
            case .initialized(query: let query, stream: let stream): return "initialized(\(query), stream=\(stream)"
            case .initializedMessages(messages: let messages, stream: let stream): return "initializedMessages(\(messages.count) messages, stream=\(stream)"
            case .querySent: return "querySent"
            case .creatingVectorStore: return "creatingVectorStore"
            case .uploadingFile: return "uploadingFile"
            case .addingFileToVectorStore: return "addingFileToVectorStore"
            }
        }
        case ground
        case initialized(query: Query, stream: Bool)
        case initializedMessages(messages: [Message], stream: Bool)
        // streamParserState is nil if streaming is unsupported, otherwise it will be nonnil but perhaps empty
        case querySent(messages: [Message], streamParserState: StreamParserState?)
        case creatingVectorStore
        case uploadingFile
        case addingFileToVectorStore
    }

    enum Event: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .begin: return "begin"
            case .error(reason: let reason): return "error(\(reason))"
            case .pluginError(let error): return "pluginError(\(error.reason))"
            case .webResponse: return "webResponse"
            case .word(let word): return "<stream \(word)>"
            case .cancel: return "Cancel"
            }
        }
        case begin
        case error(any Error)
        case pluginError(PluginError)
        case webResponse(WebResponse)
        case word(String)
        case cancel
    }

    private var state: State {
        didSet {
            DLog("\(oldValue) -> \(self)")
        }
    }

    var registration: Registration?
    weak var delegate: AITermControllerDelegate?

    init(registration: Registration?) {
        state = .ground
        self.registration = registration
    }

    var supportsStreaming: Bool {
        return llmProvider?.supportsStreaming ?? false
    }

    func request(query: String, stream: Bool = false) {
        state = .initialized(query: .completion(query), stream: stream)
        handle(event: .begin)
    }

    func request(messages: [Message], stream: Bool) {
        state = .initializedMessages(messages: messages, stream: stream)
        handle(event: .begin)
    }

    func request(createVectorStoreNamed name: String) {
        state = .initialized(query: .createVectorStore(name: name), stream: false)
        handle(event: .begin)
    }

    func request(addFiles fileIDs: [String], toVectorStore vectorStoreID: String) {
        state = .initialized(
            query: .addFilesToVectorStore(fileIDs: fileIDs,
                                          vectorStoreID: vectorStoreID),
            stream: false)
        handle(event: .begin)
    }

    func request(uploadFileNamed name: String, content: Data) {
        state = .initialized(query: .fileUpload(name: name, content: content), stream: false)
        handle(event: .begin)
    }

    func removeAllFunctions() {
        functions.removeAll()
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration, arguments: T.Type, implementation: @escaping LLM.Function<T>.Impl) {
        if llmProvider?.model.features.contains(.functionCalling) != true {
            return
        }
        functions.append(LLM.Function(decl: decl, call: implementation, parameterType: arguments))
    }

    var hostedTools = HostedTools()
    var previousResponseID: String?

    func define(functions: [LLM.AnyFunction]) {
        if llmProvider?.model.features.contains(.functionCalling) != true {
            return
        }
        self.functions.append(contentsOf: functions)
    }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
        state = .ground
    }

    private func handle(event: Event) {
        DLog("handle(\(event)) in state \(state)")
        switch state {
        case .ground:
            DLog("Ignore \(event) in ground state.")
            break

        case .creatingVectorStore:
            switch event {
            case .begin, .pluginError, .cancel, .word:
                it_fatalError()
            case .webResponse:
                state = .ground
            case .error(let error):
                self.delegate?.aitermController(
                    self,
                    didFailToCreateVectorStoreWithError: error)
            }

        case .uploadingFile:
            switch event {
            case .begin, .pluginError, .cancel, .word:
                it_fatalError()
            case .webResponse:
                state = .ground
            case .error(let error):
                self.delegate?.aitermController(
                    self,
                    didFailToUploadFileWithError: error)
            }

        case .addingFileToVectorStore:
            switch event {
            case .begin, .pluginError, .cancel, .word:
                it_fatalError()
            case .webResponse:
                state = .ground
            case .error(let error):
                self.delegate?.aitermControllerDidFailToAddFilesToVectorStore(self, error: error)
            }

        case .initialized(query: let query, stream: let stream):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    switch query {
                    case .completion(let prompt):
                        requestCompletion(query: prompt,
                                    registration: registration,
                                    stream: stream ? { [weak self] word in
                            self?.handle(event: .word(word))
                        } : nil)

                    case .createVectorStore(name: let name):
                        requestCreateVectorStore(name: name,
                                                 registration: registration)
                    case let .fileUpload(name: name, content: content):
                        requestFileUpload(name: name,
                                          content: content,
                                          registration: registration)
                    case let .addFilesToVectorStore(fileIDs: fileIDs, vectorStoreID: vectorStoreID):
                        requestAddFilesToVectorStore(fileIDs: fileIDs,
                                                     vectorStoreID: vectorStoreID,
                                                     registration: registration)
                    }
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .error(let error):
                DLog("error: \(error)")
                state = .ground
                switch query {
                case .completion(_):
                    delegate?.aitermController(self, didFailWithError: error)
                case .createVectorStore:
                    delegate?.aitermController(self,
                                               didFailToCreateVectorStoreWithError: error)
                case .fileUpload:
                    delegate?.aitermController(self, didFailToUploadFileWithError: error)
                case .addFilesToVectorStore:
                    delegate?.aitermControllerDidFailToAddFilesToVectorStore(self,
                                                                             error: error)
                }
            case .pluginError(let error):
                DLog("plugin error: \(error.reason)")
                state = .ground
            case .webResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            case .cancel:
                DLog("Cancel")
                state = .ground
            case .word:
                DLog("Ignore unexpected word")
                break
            }

        case .initializedMessages(messages: let messages, stream: let stream):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    requestCompletion(messages: messages,
                                registration: registration,
                                stream: stream ? { [weak self] word in
                        self?.handle(event: .word(word))
                    } : nil)
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .pluginError(let error):
                DLog("plugin error: \(error.reason)")
                state = .ground
            case .error(let error):
                DLog("error: \(error)")
                state = .ground
                delegate?.aitermController(self, didFailWithError: error)
                state = .ground
            case .webResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            case .cancel:
                DLog("Cancel")
                state = .ground
            case .word:
                DLog("Ignore unexpected word")
                break
            }

        case .querySent(messages: let messages, streamParserState: let streamParserState):
            switch event {
            case .begin:
                it_fatalError()
            case .webResponse(let response):
                if let error = response.error, !error.isEmpty {
                    let provider = llmProvider?.displayName ?? "server"
                    var message = "Error from \(provider): \(error)"
                    if let reason = LLMErrorParser.errorReason(data: response.data.lossyData), !reason.isEmpty {
                        message += " " + reason
                    }
                    handle(event: .error(AIError(message)))
                } else if let streamParserState {
                    _ = parseStreamingResponse(data: response.data.data(using: .utf8)!,
                                               final: true,
                                               parserState: streamParserState)
                } else {
                    parseNonStreamingResponse(data: response.data.data(using: .utf8)!)
                }
            case .pluginError(let error):
                handle(event: .error(error))
            case .cancel:
                state = .ground
            case .error(let error):
                DLog("error: \(error)")
                state = .ground
                if streamParserState != nil {
                    delegate?.aitermController(self, didStreamUpdate: "An error ocurred: \(error.localizedDescription)")
                }
                delegate?.aitermController(self, didFailWithError: error)
            case .word(let word):
                DLog("stream \(word)")
                let updated = parseStreamingResponse(
                    data: word.data(using: .utf8)!,
                    final: false,
                    parserState: streamParserState ?? StreamParserState(message: LLM.Message(role: nil),
                                                                        buffer: Data()))
                if let updated {
                    state = .querySent(messages: messages, streamParserState: updated)
                }
            }
        }
    }

    private func requestRegistration(continuation: State) {
        state = .ground
        delegate?.aitermControllerRequestRegistration(self) { [weak self] registration in
            self?.registration = registration
            self?.state = continuation
            self?.handle(event: .begin)
        }
    }

    private var settingsURL: URL {
        var value = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = iTermPreferences.defaultObject(forKey: kPreferenceKeyAITermURL) as! String
        }
        return URL(string: value) ?? URL(string: "about:empty")!
    }

    private func requestCompletion(query: String, registration: Registration, stream: ((String) -> ())?) {
        requestCompletion(messages: [Message(role: .user, content: query)],
                    registration: registration,
                    stream: stream)
    }

    private let client = iTermAIClient()
    private var cancellation: Cancellation?

    static var provider: LLMProvider? {
        if let model = LLMMetadata.model() {
            return LLMProvider(model: model)
        }
        return nil
    }

    private var llmProvider: LLMProvider? {
        Self.provider
    }

    private func requestCompletion(messages: [Message], registration: Registration, stream: ((String) -> ())?) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        var builder = LLMRequestBuilder(provider: llmProvider,
                                        apiKey: registration.apiKey,
                                        messages: messages,
                                        functions: functions,
                                        hostedTools: hostedTools,
                                        previousResponseID: previousResponseID)
        builder.stream = stream != nil
        guard llmProvider.urlIsValid else {
            handle(event: .error(AIError("Invalid URL for AI provider of \(iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? "(nil)")")))
            return
        }
        let request: WebRequest
        do {
            request = try builder.webRequest()
        } catch {
            handle(event: .error(error))
            return
        }
        cancellation = client.request(webRequest: request, stream: stream) { [weak self] result in
            switch result {
            case .success(let response):
                self?.handle(event: .webResponse(response))
            case .failure(let error):
                self?.handle(event: .pluginError(error))
            }
        }
        state = .querySent(messages: messages,
                           streamParserState: stream == nil ? nil : StreamParserState(message: LLM.Message(role: nil),
                                                                                      buffer: Data()))
    }

    private func requestCreateVectorStore(name: String,
                                          registration: Registration) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        let builder = LLMVectorStoreCreator(name: name,
                                            provider: llmProvider,
                                            apiKey: registration.apiKey)
        let request: WebRequest
        do {
            request = try builder.webRequest()
        } catch {
            handle(event: .error(error))
            return
        }
        state = .creatingVectorStore
        _ = client.request(webRequest: request, stream: nil, completion: { [weak self] result in
            guard let self else { return }
            do {
                switch result {
                case .success(let webResponse):
                    if let error = webResponse.error, !error.isEmpty {
                        let provider = llmProvider.displayName
                        var message = "Error from \(provider): \(error)"
                        if let reason = LLMErrorParser.errorReason(data: webResponse.data.lossyData), !reason.isEmpty {
                            message += " " + reason
                        }
                        handle(event: .error(AIError(message)))
                        return
                    }
                    let id = try builder.idFromResponse(webResponse.data.lossyData)
                    handle(event: .webResponse(webResponse))
                    self.delegate?.aitermController(
                        self,
                        didCreateVectorStore: id,
                        withName: name)
                case .failure(let error):
                    handle(event: .error(error))
                }
            } catch {
                handle(event: .error(error))
            }
        })
    }

    private func requestAddFilesToVectorStore(fileIDs: [String],
                                             vectorStoreID: String,
                                             registration: Registration) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        guard let builder = LLMVectorStoreAdder(provider: llmProvider,
                                                apiKey: registration.apiKey,
                                                fileIDs: fileIDs,
                                                vectorStoreID: vectorStoreID) else {
            handle(event: .error(AIError("Vector stores are not supported with this LLM vendor")))
            return
        }
        let request: WebRequest
        do {
            request = try builder.webRequest()
        } catch {
            handle(event: .error(error))
            return
        }
        state = .addingFileToVectorStore
        _ = client.request(webRequest: request, stream: nil, completion: { [weak self] result in
            guard let self else { return }
            do {
                switch result {
                case .success(let webResponse):
                    if let error = webResponse.error, !error.isEmpty {
                        let provider = llmProvider.displayName
                        var message = "Error from \(provider): \(error)"
                        if let reason = LLMErrorParser.errorReason(data: webResponse.data.lossyData), !reason.isEmpty {
                            message += " " + reason
                        }
                        handle(event: .error(AIError(message)))
                        return
                    }

                    let status = try builder.statusFromResponse(webResponse.data.lossyData)
                    switch status {
                    case .completed:
                        state = .ground
                        delegate?.aitermControllerDidAddFilesToVectorStore(self)
                    case .inProgress:
                        state = .ground
                        scheduleVectorStorePoll(vectorStoreID: vectorStoreID,
                                                batchID: try builder.batchIDFromResponse(webResponse.data.lossyData),
                                                registration: registration)
                    case .cancelled, .failed:
                        handle(event: .error(AIError("Adding file to vector store failed")))
                    }
                case .failure(let error):
                    handle(event: .error(error))
                }
            } catch {
                handle(event: .error(error))
            }
        })
    }

    private func scheduleVectorStorePoll(vectorStoreID: String, batchID: String, registration: Registration) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: { [weak self] in
            self?.checkVectorStoreReadiness(vectorStoreID: vectorStoreID,
                                            batchID: batchID,
                                            registration: registration)
        })
    }

    private func checkVectorStoreReadiness(vectorStoreID: String,
                                           batchID: String,
                                           registration: Registration) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        guard let builder = LLMVectorStoreBatchStatusChecker(provider: llmProvider,
                                                             apiKey: registration.apiKey,
                                                             batchID: batchID,
                                                             vectorStoreID: vectorStoreID) else {
            handle(event: .error(AIError("Vector stores are not supported with this LLM vendor")))
            return
        }
        let request: WebRequest
        do {
            request = try builder.webRequest()
        } catch {
            handle(event: .error(error))
            return
        }
        _ = client.request(webRequest: request, stream: nil) { [weak self] result in
            guard let self else { return }
            do {
                switch result {
                case .success(let webResponse):
                    if let error = webResponse.error, !error.isEmpty {
                        let provider = llmProvider.displayName
                        var message = "Error from \(provider): \(error)"
                        if let reason = LLMErrorParser.errorReason(data: webResponse.data.lossyData), !reason.isEmpty {
                            message += " " + reason
                        }
                        handle(event: .error(AIError(message)))
                        return
                    }

                    let status = try builder.statusFromResponse(webResponse.data.lossyData)
                    switch status {
                    case .cancelled, .failed:
                        state = .ground
                        handle(event: .error(AIError("An error ocurred while ingesting files to vector storage")))
                        delegate?.aitermControllerDidFailToAddFilesToVectorStore(self, error: AIError("The file may not be well formed."))
                    case .completed:
                        delegate?.aitermControllerDidAddFilesToVectorStore(self)
                        state = .ground
                    case .inProgress:
                        scheduleVectorStorePoll(vectorStoreID: vectorStoreID, batchID: batchID, registration: registration)
                    }
                case .failure(let error):
                    state = .ground
                    handle(event: .error(error))
                    delegate?.aitermControllerDidFailToAddFilesToVectorStore(self, error: error)
                }
            } catch {
                state = .ground
                handle(event: .error(error))
                delegate?.aitermControllerDidFailToAddFilesToVectorStore(self, error: error)
            }
        }
    }

    private func requestFileUpload(name: String,
                                   content: Data,
                                   registration: Registration) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        guard let builder = LLMFileUploader(provider: llmProvider,
                                            apiKey: registration.apiKey,
                                            fileName: name,
                                            content: content) else {
            handle(event: .error(AIError("File upload not supported with this LLM vendor")))
            return
        }
        let request: WebRequest
        do {
            request = try builder.webRequest()
        } catch {
            handle(event: .error(error))
            return
        }
        state = .uploadingFile
        _ = client.request(webRequest: request, stream: nil, completion: { [weak self] result in
            guard let self else { return }
            do {
                switch result {
                case .success(let webResponse):
                    if let error = webResponse.error, !error.isEmpty {
                        let provider = llmProvider.displayName
                        var message = "Error from \(provider): \(error)"
                        if let reason = LLMErrorParser.errorReason(data: webResponse.data.lossyData), !reason.isEmpty {
                            message += " " + reason
                        }
                        handle(event: .error(AIError(message)))
                        return
                    }

                    let id = try builder.idFromResponse(webResponse.data.lossyData)
                    handle(event: .webResponse(webResponse))
                    delegate?.aitermController(self, didUploadFileWithID: id)
                case .failure(let error):
                    handle(event: .error(error))
                    state = .ground
                }
            } catch {
                handle(event: .error(error))
                state = .ground
            }
        })
    }

    struct StreamParserState: Equatable {
        var message: LLM.Message
        var buffer: Data
    }

    private func parseStreamingResponse(data: Data, final: Bool, parserState: StreamParserState) -> StreamParserState? {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return nil
        }
        var accumulatingMessage = parserState.message
        if final {
            if let functionCall = accumulatingMessage.function_call {
                doFunctionCall(accumulatingMessage, call: functionCall)
            } else {
                delegate?.aitermController(self, didStreamUpdate: nil)
            }
            state = .ground
            return nil
        }
        DLog("------- parse new stream response of length \(data.count) -------------")
        let string = String(data: parserState.buffer + data, encoding: .utf8) ?? ""
        guard let parser = llmProvider.streamingResponseParser(stream: true) else {
            handle(event: .error(AIError("Streaming is not supported by this language model in iTerm2. You can disable streaming in Settings > General > AI.")))
            return nil
        }
        var (first, rest) = parser.splitFirstJSONEvent(from: string)

        let drain = {
            switch accumulatingMessage.body {
            case .uninitialized:
                break
            case .text(let string):
                if !string.isEmpty {
                    DLog("drain with content: \(accumulatingMessage)")
                    self.delegate?.aitermController(self, didStreamUpdate: string)
                }
                accumulatingMessage.body = .uninitialized
            case .attachment(let attachment):
                DLog("drain attachment \(attachment)")
                self.delegate?.aitermController(self, didStreamAttachment: attachment)
            case .functionCall(let call, _):
                self.doFunctionCall(accumulatingMessage, call: call)
                accumulatingMessage.body = .uninitialized
            case .functionOutput:
                it_fatalError("Server should not send function output")
            case .multipart:
                it_fatalError("Should not accumulate multipart")
            }
            accumulatingMessage.body = .uninitialized
        }
        do {
            defer {
                switch accumulatingMessage.body {
                case .uninitialized, .functionCall, .functionOutput, .multipart:
                    break
                case .text, .attachment:
                    drain()
                }
            }
            while first != nil {
                if let first, let firstData = first.data(using: .utf8) {
                    if first == "[DONE]" {
                        break
                    }
                    do {
                        guard var parser = llmProvider.streamingResponseParser(stream: true) else {
                            handle(event: .error(AIError("Streaming is not supported by this language model in iTerm2. You can disable streaming in Settings > General > AI.")))
                            return nil
                        }
                        let response = try parser.parse(data: firstData)
                        guard let response else {
                            DLog("Stream finished")
                            break
                        }
                        if !response.ignore {
                            if let id = response.newlyCreatedResponseID {
                                previousResponseID = id
                            }
                            // The Responses API can have choiceless messages, such as type=response.created
                            if let choice = response.choiceMessages.first {
                                if let role = choice.role {
                                    accumulatingMessage.role = role
                                }
                                if !accumulatingMessage.tryAppend(choice.body) {
                                    drain()
                                    accumulatingMessage = LLM.Message(role: choice.role,
                                                                      body: choice.body)
                                }
                            }
                        }
                    } catch {
                        drain()
                    }
                }
                guard let parser = llmProvider.streamingResponseParser(stream: true) else {
                    handle(event: .error(AIError("Streaming is not supported by this language model in iTerm2. You can disable streaming in Settings > General > AI.")))
                    return nil
                }

                (first, rest) = parser.splitFirstJSONEvent(from: rest)
            }
        }

        return StreamParserState(message: accumulatingMessage, buffer: rest.data(using: .utf8)!)
    }

    private func parseNonStreamingResponse(data: Data) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        do {
            var parser = llmProvider.responseParser()
            guard let response = try parser.parse(data: data) else {
                delegate?.aitermController(self, didFailWithError: AIError("Unexpected end of file from server"))
                return
            }
            if let topChoice = response.choiceMessages.first, let functionCall = topChoice.function_call {
                doFunctionCall(topChoice, call: functionCall)
                return
            }
            let choices = response.choiceMessages.compactMap { $0.trimmedString }
            guard let choice = choices.first else {
                delegate?.aitermController(self, didFailWithError: AIError("Empty response from server"))
                return
            }
            state = .ground
            delegate?.aitermController(self, offerChoice: choice)
        } catch {
            if let reason = LLMErrorParser.errorReason(data: data) {
                handle(event: .error(AIError("Could not decode response: " + reason)))
            } else {
                handle(event: .error(AIError("Failed to decode API response: \(error). Data is: \(data.stringOrHex)")))
            }
        }
    }

    private func doFunctionCall(_ message: Message, call functionCall: LLM.FunctionCall) {
        guard let llmProvider else {
            handle(event: .error(AIError("No AI model configured in settings.")))
            return
        }
        switch state {
        case .ground, .initialized, .initializedMessages, .creatingVectorStore,
                .uploadingFile, .addingFileToVectorStore:
            DLog("Unexpected function call in state \(state)")
            return
        case .querySent(let messages, _):
            var amended = messages
            amended.append(message)
            if let impl = functions.first(where: { $0.decl.name == functionCall.name }) {
                DLog("Invoke function with arguments \(functionCall.arguments ?? "")")
                impl.invoke(message: message,
                            json: (functionCall.arguments ?? "").data(using: .utf8)!) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        DLog("Response to function call with arguments \(functionCall.arguments ?? ""): \(response)")
                        amended.append(Message(role: .function,
                                               content: response,
                                               name: functionCall.name,
                                               functionCallID: message.functionCallID))
                        state = .ground
                        if let truncate {
                            amended = truncate(amended)
                        }
                        request(messages: amended, stream: llmProvider.supportsStreaming)
                        return
                    case .failure(let error):
                        DLog("Trouble invoking a ChatGPT function: \(error.localizedDescription)")
                        handle(event: .error(error))
                        return
                    }
                }
                return
            }
            amended.append(Message(role: .user,
                                   content: "There is no registered function by that name. Try again."))
            request(messages: amended, stream: llmProvider.supportsStreaming)
        }
    }
}

extension LLM {
    enum StreamingUpdate {
        case append(String)
        case appendAttachment(LLM.Message.Attachment)
    }
}

func truncate(messages: [AITermController.Message], maxTokens: Int) -> [AITermController.Message] {
    var tokens = messages.map { $0.approximateTokenCount }.reduce(0, +)

    var messagesToSend = messages
    var j = 0
    for i in 0..<messagesToSend.count {
        defer {
            j += 1
        }
        if tokens < maxTokens {
            break
        }
        if messages[i].role == .system {
            continue
        }
        if i == messages.count - 1 {
            var (head, tail) = (messagesToSend[j].content ?? "").halved

            while tokens >= maxTokens {
                (head, _) = head.halved
                (_, tail) = tail.halved
                tokens -= messagesToSend[j].approximateTokenCount
                switch messagesToSend[j].body {
                case .text, .attachment, .multipart:
                    messagesToSend[j].body = .text(head + "…[truncated]…" + tail)
                case .functionOutput(name: let name, output: _, id: let id):
                    messagesToSend[j].body = .functionOutput(name: name, output: head + "…[truncated]…" + tail, id: id)
                case .uninitialized, .functionCall:
                    break
                }
                tokens += messagesToSend[j].approximateTokenCount
            }
        } else {
            tokens -= messages[i].approximateTokenCount
            messagesToSend.remove(at: j)
            j -= 1
        }
    }
    return messagesToSend
}

