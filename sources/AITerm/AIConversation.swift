//
//  AIConversation.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

struct AIConversation {
    private class Delegate: AITermControllerDelegate {
        private(set) var busy = false
        var completion: ((Result<String, Error>) -> ())?
        var streaming: ((LLM.StreamingUpdate) -> ())?
        var registrationNeeded: ((@escaping (AITermController.Registration) -> ()) -> ())?
        var createVectorStoreCompletion: ((Result<String, Error>) -> ())?
        var uploadFileCompletion: ((Result<String, Error>) -> ())?
        var addFilesToVectorStoreCompletion: ((Error?) -> ())?
        // Stashed by didReceiveReasoning so the completion closure can attach
        // it to the assistant Message it appends to AIConversation.messages.
        // Required so DeepSeek's reasoning_content can round-trip across user
        // turns on plain-text (non-tool-call) replies.
        var pendingReasoning: String?

        func aitermController(_ sender: AITermController, didReceiveReasoning reasoning: String) {
            pendingReasoning = reasoning
        }

        func aitermControllerDidCancelOutstandingRequest(_ sender: AITermController) {
            guard busy else {
                return
            }
            busy = false
            completion?(Result.failure(PendingCommandCanceled()))
        }

        func aitermControllerWillSendRequest(_ sender: AITermController) {
            busy = true
        }

        func aitermController(_ sender: AITermController, offerChoice choice: String) {
            busy = false
            completion?(Result.success(choice))
        }

        func aitermController(_ sender: AITermController, didFailWithError error: Error) {
            busy = false
            completion?(Result.failure(error))
        }

        func aitermControllerRequestRegistration(_ sender: AITermController,
                                                 completion: @escaping (AITermController.Registration) -> ()) {
            registrationNeeded?(completion)
        }

        func aitermController(_ sender: AITermController, didStreamUpdate update: String?) {
            if let update {
                streaming?(.append(update))
            } else {
                completion?(.success(""))
            }
        }

        func aitermController(_ sender: AITermController, didStreamAttachment attachment: LLM.Message.Attachment) {
            streaming?(.appendAttachment(attachment))
        }

        func aitermController(_ sender: AITermController,
                              didCreateVectorStore id: String,
                              withName name: String) {
            busy = false
            createVectorStoreCompletion?(Result.success(id))
        }

        func aitermController(_ sender: AITermController,
                              didFailToCreateVectorStoreWithError error: Error) {
            busy = false
            createVectorStoreCompletion?(Result.failure(error))

        }

        func aitermController(_ sender: AITermController,
                              didUploadFileWithID id: String) {
            busy = false
            uploadFileCompletion?(Result.success(id))
        }
        func aitermController(_ sender: AITermController,
                              didFailToUploadFileWithError error: Error) {
            busy = false
            uploadFileCompletion?(Result.failure(error))
        }
        func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController) {
            busy = false
            addFilesToVectorStoreCompletion?(nil)
        }

        func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: Error) {
            busy = false
            addFilesToVectorStoreCompletion?(error)
        }

        func aitermController(_ sender: AITermController, willInvokeFunction function: any LLM.AnyFunction) {
            streaming?(.willInvoke(function))
        }
    }
    var responseID: String? {
        controller.previousResponseID
    }

    var messages: [AITermController.Message]
    // Selects the model by name, resolved against the public catalog
    // (AIMetadata.instance.models) at request time. Use this when the catalog's
    // own endpoint is what you want.
    var model: String?
    // A fully-specified model to use instead of `model`/the configured provider.
    // Unlike `model` (a name that gets re-resolved to the catalog's public
    // endpoint), this is used verbatim, so it preserves a custom url/api/auth.
    // Callers that must not leak the API key past a user's custom base URL (e.g.
    // the economy-model path) set this rather than `model`. Takes precedence over
    // `model`. Not carried by the AIConversation(_:) copy initializer.
    var modelOverride: AIMetadata.Model?
    var shouldThink: Bool? = nil {
        didSet {
            controller.shouldThink = shouldThink
        }
    }
    private(set) var controller: AITermController
    private var delegate = Delegate()
    private(set) weak var registrationProvider: AIRegistrationProvider?
    var maxTotalTokens: Int {
        Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit))
    }
    var maxResponseTokens: Int {
        return min(maxTotalTokens / 2,
                   Int(iTermPreferences.int(forKey: kPreferenceKeyAIResponseTokenLimit)))
    }
    var maxTokens: Int {
        return Int(maxTotalTokens - maxResponseTokens)
    }
    var busy: Bool { delegate.busy }
    init(_ other: AIConversation) {
        self.init(registrationProvider: other.registrationProvider,
                  messages: other.messages,
                  previousResponseID: other.controller.previousResponseID)
        controller.define(functions: other.controller.functions)
    }

    init(registrationProvider: AIRegistrationProvider?,
         messages: [AITermController.Message] = [],
         previousResponseID: String? = nil) {
        self.registrationProvider = registrationProvider
        self.messages = messages
        controller = AITermController(registration: AITermControllerRegistrationHelper.instance.registration)
        controller.previousResponseID = previousResponseID
        controller.delegate = delegate
        let maxTokens = self.maxTokens
        controller.truncate = { truncate(messages: $0, maxTokens: maxTokens) }
    }

    var supportsStreaming: Bool {
        return controller.supportsStreaming
    }
    func removeAllFunctions() {
        controller.removeAllFunctions()
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration,
                            arguments: T.Type,
                            implementation: @escaping LLM.Function<T>.Impl) {
        controller.define(function: decl, arguments: arguments, implementation: implementation)
    }

    var hostedTools: HostedTools {
        get {
            controller.hostedTools
        }
        set {
            controller.hostedTools = newValue
        }
    }

    var systemMessageDirty = false

    var systemMessage: String? {
        didSet {
            if messages.first?.role == .system {
                messages.removeFirst()
            }
            if let systemMessage {
                messages.insert(LLM.Message(role: .system,
                                            content: systemMessage),
                                at: 0)
            }
        }
    }

    // Deletes from the first user message on after the given response ID. Used when editing
    // a conversation. The next completion will therefore be in response to this message.
    mutating func deleteMessages(after responseID: String) {
        if var i = messages.firstIndex(where: { $0.responseID == responseID}) {
            while i < messages.count && messages[i].role != .user {
                i += 1
            }
            if i < messages.count {
                messages.removeSubrange(i...)
            }
            controller.previousResponseID = responseID
        }
    }

    mutating func add(_ aiMessage: AITermController.Message) {
        while messages.last?.role == aiMessage.role {
            messages.removeLast()
        }
        messages.append(aiMessage)
    }

    mutating func add(text: String, role: LLM.Role = .user) {
        add(AITermController.Message(role: role, content: text))
    }

    mutating func deleteResponse(_ id: String, completion: @escaping (Error?) -> ()) {
        if id == controller.previousResponseID {
            controller.previousResponseID = messages.last {
                $0.responseID != nil && $0.responseID != id
            }?.responseID
        }
        messages.removeAll { $0.responseID == id }
    }

    func cancelOutstandingOperation() {
        controller.cancelOutstandingOperation()
        // controller.cancelOutstandingOperation routes through
        // handle(.cancel), which the state machine ignores in
        // .ground state (AITerm.swift:227-229). We can be in
        // .ground because parseStreamingResponse(final:true) moved
        // here after dispatching a function_call that's still
        // parked in the function-dispatch layer (the
        // pendingRemoteCommands map in ChatAgent). The delegate
        // callback never fired so our completion is stuck. Fire it
        // directly if the delegate still thinks there's a request
        // in flight. Idempotent: aitermControllerDidCancelOutstandingRequest
        // is a no-op when busy is already false.
        if delegate.busy {
            delegate.aitermControllerDidCancelOutstandingRequest(controller)
        }
    }
    private func cancel() {
        controller.cancel()
        delegate.completion = { _ in }
        delegate.streaming = nil
        delegate.registrationNeeded = { _ in }
        delegate.createVectorStoreCompletion = nil
        delegate.uploadFileCompletion = nil
        delegate.addFilesToVectorStoreCompletion = nil
    }

    func prepare(completion: @escaping (Error?) -> ()) {
        if delegate.busy {
            cancel()
        }
        delegate.registrationNeeded = { [weak registrationProvider] regCompletion in
            if let registrationProvider {
                registrationProvider.registrationProviderRequestRegistration() { registration in
                    if let registration {
                        regCompletion(registration)
                        completion(nil)
                    } else {
                        completion(AIError("You must provide a valid API key to use AI features in iTerm2."))
                    }
                }
            } else {
                RLog("No registration provider found")
                completion(AIError("You must provide a valid API key to use AI features in iTerm2"))
            }
        }
    }

    func createVectorStore(name: String, completion: @escaping (Result<String, Error>) -> ()) {
        if delegate.busy {
            cancel()
        }
        prepare { error in
            if let error {
                completion(.failure(error))
            } else {
                controller.request(createVectorStoreNamed: name)
            }
        }
        delegate.createVectorStoreCompletion = completion
        controller.request(createVectorStoreNamed: name)
    }

    func uploadFile(name: String,
                    content: Data,
                    completion: @escaping (Result<String, Error>) -> ()) {
        if delegate.busy {
            cancel()
        }
        prepare { error in
            if let error {
                completion(.failure(error))
            } else {
                controller.request(uploadFileNamed: name, content: content)
            }
        }
        delegate.uploadFileCompletion = completion
        controller.request(uploadFileNamed: name, content: content)
    }

    func addFilesToVectorStore(fileIDs: [String],
                               vectorStoreID: String,
                               completion: @escaping (Error?) -> ()) {
        if delegate.busy {
            cancel()
        }
        prepare { error in
            if let error {
                completion(error)
            } else {
                controller.request(addFiles: fileIDs, toVectorStore: vectorStoreID)
            }
        }
        delegate.addFilesToVectorStoreCompletion = completion
        controller.request(addFiles: fileIDs, toVectorStore: vectorStoreID)
    }

    mutating func complete(_ completion: @escaping (Result<AIConversation, Error>) -> ()) {
        complete(streaming: nil, completion: completion)
    }

    mutating func complete(streaming: ((LLM.StreamingUpdate, String?) -> ())?,
                           completion: @escaping (Result<AIConversation, Error>) -> ()) {
        precondition(!messages.isEmpty)

        // Wipe any reasoning carried over from a prior request on this same
        // Delegate. The upfront wipe is the single source of truth for both
        // success and failure paths (neither branch of the completion below
        // touches pendingReasoning); without it a subsequent turn whose
        // vendor/model emits no reasoning would inherit the prior turn's text.
        delegate.pendingReasoning = nil
        let controller = self.controller
        let messages = self.truncatedMessages
        prepare { error in
            if let error {
                completion(.failure(error))
            } else {
                // Called after registration completes.
                controller.request(
                    messages: messages,
                    stream: streaming != nil && controller.supportsStreaming)
            }
        }

        var amended = AIConversation(self)
        var accumulator = LLM.Message.Body.uninitialized
        if let streaming {
            delegate.streaming = { [weak controller] update in
                if let previousResponseID = controller?.previousResponseID {
                    amended.controller.previousResponseID = previousResponseID
                }
                switch update {
                case .append(let string):
                    accumulator.append(.text(string))
                case .appendAttachment(let attachment):
                    accumulator.append(.attachment(attachment))
                case .willInvoke:
                    break
                }
                streaming(update, controller?.previousResponseID)
            }
        }

        delegate.completion = { [weak controller, weak delegate] result in
            switch result {
            case .success(let text):
                if !text.isEmpty {
                    accumulator.append(.text(text))
                }
                if let previousResponseID = controller?.previousResponseID {
                    amended.controller.previousResponseID = previousResponseID
                }
                let message = AITermController.Message(
                    responseID: controller?.previousResponseID,
                    role: .assistant,
                    body: accumulator,
                    reasoningContent: delegate?.pendingReasoning)
                amended.messages.append(message)
                completion(.success(amended))
                break
            case .failure(let error):
                completion(.failure(error))
            break
            }
        }
        let lastAssistantMessage = self.messages.last { $0.role == .assistant }
        if let modelOverride {
            // Used verbatim: preserves the caller's url/api/auth (see the
            // economy-model path in ScreenWatchPoller).
            controller.providerOverride = LLMProvider(model: modelOverride)
        } else if let modelName = model, let model = AIMetadata.instance.models.first(where: { $0.name == modelName }) {
            controller.providerOverride = LLMProvider(model: model)
        } else {
            controller.providerOverride = nil
        }
        if systemMessageDirty {
            // Force it to send the whole conversation over again.
            controller.previousResponseID = nil
            systemMessageDirty = false
        } else {
            controller.previousResponseID = lastAssistantMessage?.responseID
        }
        // This won't do anything if registration is needed. See the completion callback to
        // prepare() above for that case.
        controller.request(messages: truncatedMessages, stream: streaming != nil)
    }

    private var truncatedMessages: [AITermController.Message] {
        if controller.supportsPreviousResponseID && controller.previousResponseID != nil,
           let lastMessage = messages.last {
            return truncate(messages: [lastMessage], maxTokens: maxTokens)
        }
        return truncate(messages: messages, maxTokens: maxTokens)
    }
}

// MARK: - One-shot completion

// Retention for fire-and-forget conversations: AIConversation is a value
// type that owns a controller doing async work, so somebody must keep a
// copy alive until the completion runs. Main-thread only.
private enum AIConversationOneShotRetention {
    static var retained = [UUID: AIConversation]()
}

extension AIConversation {
    // Completes a fire-and-forget conversation, retaining it (and the
    // controller it owns) until the completion has run. Use this instead
    // of a hand-rolled stored property or static dictionary: complete is
    // mutating and can run its callback synchronously (e.g. when no
    // registration exists), so a caller that stores the conversation and
    // then mutates that same storage from inside the callback traps under
    // exclusivity enforcement. This helper calls complete on a local
    // copy, stores it afterward, and releases on the next runloop turn,
    // which keeps the ordering correct in the synchronous case too. Call
    // on the main thread.
    static func completeOneShot(_ conversation: AIConversation,
                                completion: @escaping (Result<AIConversation, Error>) -> ()) {
        dispatchPrecondition(condition: .onQueue(.main))
        var mutable = conversation
        let token = UUID()
        mutable.complete { result in
            DispatchQueue.main.async {
                AIConversationOneShotRetention.retained.removeValue(forKey: token)
            }
            completion(result)
        }
        AIConversationOneShotRetention.retained[token] = mutable
    }
}
