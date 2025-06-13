//
//  AITermControllerObjC.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//


@objc
class AITermControllerObjC: NSObject, AITermControllerDelegate, iTermObject {
    private struct CachedKey {
        var valid = false
        var value: String?
    }
    private let controller: AITermController
    private var handler: ((Result<String, Error>) -> ())?
    private let ownerWindow: NSWindow
    private let query: String
    private let pleaseWait: PleaseWaitWindow
    private static let apiKeyQueue = DispatchQueue(label: "com.iterm2.aiterm-set-key")
    private static var cachedKey = MutableAtomicObject(CachedKey())

    @objc static var haveCachedAPIKey: Bool {
        return cachedKey.value.valid
    }

    @objc static var apiKey: String? {
        get {
            if cachedKey.value.valid {
                return cachedKey.value.value
            }
            return apiKeyQueue.sync {
                if !cachedKey.value.valid {
                    let value = try? SSKeychain.password(forService: "iTerm2 API Keys",
                                                         account: "OpenAI API Key for iTerm2")
                    cachedKey.set(CachedKey(valid: true, value: value))
                }
                return cachedKey.value.value
            }
        }
        set {
            cachedKey.set(CachedKey(valid: true, value: newValue))
            apiKeyQueue.sync {
                cachedKey.set(CachedKey(valid: true, value: newValue))
                _ = SSKeychain.setPassword(newValue ?? "",
                                           forService: "iTerm2 API Keys",
                                           account: "OpenAI API Key for iTerm2")
            }
        }
    }

    @objc static func setAPIKeyAsync(_ key: String?) {
        cachedKey.set(CachedKey(valid: true, value: key))
        apiKeyQueue.async {
            cachedKey.set(CachedKey(valid: true, value: key))
            _ = SSKeychain.setPassword(key ?? "",
                                       forService: "iTerm2 API Keys",
                                       account: "OpenAI API Key for iTerm2")
        }
    }

    // handler([…], nil): Valid response
    // handler(nil, …): Error
    // handler(nil, nil): User canceled
    @objc(initWithQuery:scope:inWindow:completion:)
    init(query: String,
         scope: iTermVariableScope,
         window: NSWindow,
         handler: @escaping (iTermOr<NSString, NSError>) -> ()) {
        let pleaseWait = PleaseWaitWindow(owningWindow: window,
                                          message: "Thinking…",
                                          image: NSImage.it_imageNamed("aiterm", for: AITermControllerObjC.self))
        self.pleaseWait = pleaseWait
        var cancel: (() -> ())?
        var shouldCancel = false
        self.handler = { result in
            if !pleaseWait.canceled {
                result.handle { choice in
                    handler(iTermOr.first(choice as NSString))
                } failure: { error in
                    handler(iTermOr.second(error as NSError))
                }
            } else {
                shouldCancel = true
                cancel?()
            }
        }
        pleaseWait.didCancel = {
            shouldCancel = true
            cancel?()
        }
        self.ownerWindow = window
        self.query = query

        let registration = AITermControllerRegistrationHelper.instance.registration
        controller = AITermController(registration: registration)
        super.init()

        controller.delegate = self

        let template = iTermPreferences.string(forKey: kPreferenceKeyAIPrompt) ?? ""
        let sanitizedPrompt = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let myScope = scope.copy() as! iTermVariableScope
        let frame = iTermVariables(context: [], owner: self)
        myScope.add(frame, toScopeNamed: "ai")
        myScope.setValue(sanitizedPrompt, forVariableNamed: "ai.prompt")
        let swiftyString = iTermSwiftyString(string: template, scope: myScope)
        swiftyString.evaluateSynchronously(false, with: myScope) { maybeResult, maybeError, _ in
            if let prompt = maybeResult {
                Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
                    if !shouldCancel {
                        cancel = { [weak self] in
                            self?.controller.cancel()
                        }
                        self.controller.request(query: prompt)
                    }
                }
            }
        }
    }

    // Ensures handler will never be called.
    @objc func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        handler = nil
    }

    func aitermControllerWillSendRequest(_ sender: AITermController) {
        pleaseWait.run()
    }

    func aitermController(_ sender: AITermController, didStreamUpdate update: String?) {
        it_fatalError("Streaming not supported in the objective c interface")
    }

    func aitermController(_ sender: AITermController, didStreamAttachment: LLM.Message.Attachment) {
        it_fatalError("Streaming not supported in the objective C interface")
    }

    func aitermController(_ sender: AITermController, offerChoice choice: String) {
        pleaseWait.stop()
        DispatchQueue.main.async {
            self.handler?(.success(choice))
        }
    }

    func aitermController(_ sender: AITermController, didFailWithError error: Error) {
        pleaseWait.stop()
        DispatchQueue.main.async {
            self.handler?(.failure(error))
        }

    }

    // These aren't used by the non-streaming interfaces. They are only available through AIConversation.
    func aitermController(_ sender: AITermController, didCreateVectorStore id: String, withName name: String) {
        it_fatalError()
    }

    func aitermControllerDidAddFileToVectorStore(_ sender: AITermController) {
        it_fatalError()
    }

    func aitermControllerDidFailToAddFileToVectorStore(_ sender: AITermController, error: any Error) {
        it_fatalError()
    }

    func aitermController(_ sender: AITermController, didFailToCreateVectorStoreWithError: any Error) {
        it_fatalError()
    }

    func aitermController(_ sender: AITermController, didUploadFileWithID id: String) {
        it_fatalError()
    }

    func aitermController(_ sender: AITermController, didFailToUploadFileWithError: any Error) {
        it_fatalError()
    }

    func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController) {
        it_fatalError()
    }

    func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: any Error) {
        it_fatalError()
    }

    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: ownerWindow) { [weak self] registration in
            guard let self else {
                return
            }
            if let registration {
                completion(registration)
            } else {
                handler?(.failure(AIError("AI features are not enabled or the API key is missing.")))
            }
        }
    }

    func objectMethodRegistry() -> iTermBuiltInFunctions? {
        return nil
    }

    func objectScope() -> iTermVariableScope? {
        return nil
    }
}

