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
    private static var cachedKeys = [UInt: CachedKey]()
    private static let keychainService = "iTerm2 API Keys"
    private static let legacyKeychainAccount = "OpenAI API Key for iTerm2"

    @objc static var haveCachedAPIKey: Bool {
        return apiKeyQueue.sync {
            cachedKeys[cacheKey(for: LLMMetadata.effectiveVendor)]?.valid == true
        }
    }

    @objc static var apiKey: String? {
        get {
            apiKey(for: LLMMetadata.effectiveVendor)
        }
        set {
            setAPIKey(newValue, for: LLMMetadata.effectiveVendor)
        }
    }

    @objc static func setAPIKeyAsync(_ key: String?) {
        let vendor = LLMMetadata.effectiveVendor
        apiKeyQueue.async {
            setAPIKeyOnQueue(key, for: vendor)
        }
    }

    static func apiKey(for vendor: iTermAIVendor) -> String? {
        apiKeyQueue.sync {
            apiKeyOnQueue(for: vendor)
        }
    }

    @objc(apiKeyForVendor:)
    static func objcApiKey(for vendor: iTermAIVendor) -> String? {
        apiKey(for: vendor)
    }

    // Read-only presence check for Settings' status row. Unlike apiKey(for:) it
    // never performs the legacy->vendor migration write, so merely viewing
    // Settings cannot mutate the keychain, and a transient read error is not
    // cached as "no key". Safe to call off the main thread.
    @objc(apiKeyIsConfiguredForVendor:)
    static func objcApiKeyIsConfigured(for vendor: iTermAIVendor) -> Bool {
        return apiKeyQueue.sync {
            if let cached = cachedKeys[cacheKey(for: vendor)], cached.valid {
                return !keyIsEmpty(cached.value)
            }
            let account = keychainAccount(for: vendor)
            let stored = readKeychainPassword(account: account)
            if !keyIsEmpty(stored.value) {
                return true
            }
            // The legacy shared key belongs to the effective vendor only, matching
            // resolveAPIKey. Read it to report status but never migrate/write here.
            if account != legacyKeychainAccount,
               vendor == LLMMetadata.effectiveVendor {
                let legacy = readKeychainPassword(account: legacyKeychainAccount)
                return !keyIsEmpty(legacy.value)
            }
            return false
        }
    }

    static func setAPIKey(_ key: String?, for vendor: iTermAIVendor) {
        apiKeyQueue.sync {
            setAPIKeyOnQueue(key, for: vendor)
        }
    }

    @objc(setAPIKey:forVendor:)
    static func objcSetAPIKey(_ key: String?, for vendor: iTermAIVendor) {
        setAPIKey(key, for: vendor)
    }

    @objc(apiKey:matchesVendor:)
    static func objcApiKey(_ key: String?, matches vendor: iTermAIVendor) -> Bool {
        guard let key else {
            return false
        }
        return !keyIsEmpty(key) && self.key(key, matches: vendor)
    }

    struct KeyResolution: Equatable {
        var value: String?
        // True when the legacy shared-account key should be copied into the
        // vendor's own keychain account.
        var migrateLegacyToVendorAccount: Bool
    }

    // Pure decision for which key a vendor should use, extracted so it can be
    // unit tested without touching the keychain.
    //
    // A key stored in the vendor's own account is always trusted as-is: it was
    // put there deliberately (possibly a proxy/gateway token that doesn't match
    // any vendor's canonical prefix), so we must not second-guess it by sniffing
    // its text.
    //
    // The legacy account held a single key under one shared account name in
    // builds before per-vendor storage. That key belongs to whatever the user's
    // default (effective) vendor is, so it is only adopted for the effective
    // vendor. Adopting it for any other vendor would, for example, hand an
    // OpenAI key to DeepSeek/Llama (whose key text is indistinguishable) and
    // durably persist the wrong secret.
    static func resolveAPIKey(vendorAccountKey: String?,
                              legacyKey: String?,
                              vendorUsesLegacyAccount: Bool,
                              vendorIsEffective: Bool) -> KeyResolution {
        if !keyIsEmpty(vendorAccountKey) {
            return KeyResolution(value: vendorAccountKey,
                                 migrateLegacyToVendorAccount: false)
        }
        if !vendorUsesLegacyAccount,
           vendorIsEffective,
           !keyIsEmpty(legacyKey) {
            return KeyResolution(value: legacyKey,
                                 migrateLegacyToVendorAccount: true)
        }
        return KeyResolution(value: nil, migrateLegacyToVendorAccount: false)
    }

    private static func apiKeyOnQueue(for vendor: iTermAIVendor) -> String? {
        let cacheKey = cacheKey(for: vendor)
        if let cached = cachedKeys[cacheKey], cached.valid {
            return cached.value
        }

        let account = keychainAccount(for: vendor)
        let stored = readKeychainPassword(account: account)
        let legacy: KeychainReadResult
        if account == legacyKeychainAccount {
            legacy = KeychainReadResult(value: nil, hardError: false)
        } else {
            legacy = readKeychainPassword(account: legacyKeychainAccount)
        }
        // A transient read failure (e.g. a locked keychain) must not be cached
        // as "no key" - that would durably serve a stale nil for the rest of
        // the session. Return best-effort nil now and leave the entry invalid
        // so the next access retries.
        if stored.hardError || legacy.hardError {
            return nil
        }
        let resolution = resolveAPIKey(
            vendorAccountKey: stored.value,
            legacyKey: legacy.value,
            vendorUsesLegacyAccount: account == legacyKeychainAccount,
            vendorIsEffective: vendor == LLMMetadata.effectiveVendor)
        if resolution.migrateLegacyToVendorAccount, let value = resolution.value {
            _ = SSKeychain.setPassword(value,
                                       forService: keychainService,
                                       account: account)
        }
        cachedKeys[cacheKey] = CachedKey(valid: true, value: resolution.value)
        return resolution.value
    }

    private struct KeychainReadResult {
        var value: String?
        // True only for a genuine read error (locked keychain, denied access,
        // etc.), NOT for a legitimately absent item.
        var hardError: Bool
    }

    private static func readKeychainPassword(account: String) -> KeychainReadResult {
        do {
            let value = try SSKeychain.password(forService: keychainService,
                                                account: account)
            return KeychainReadResult(value: value, hardError: false)
        } catch let error as NSError {
            // errSecItemNotFound means the item simply isn't stored yet - a
            // legitimate absence, not a failure. Any other status is a real
            // error we must not confuse with "no key".
            if error.code == Int(errSecItemNotFound) {
                return KeychainReadResult(value: nil, hardError: false)
            }
            return KeychainReadResult(value: nil, hardError: true)
        }
    }

    private static func setAPIKeyOnQueue(_ key: String?, for vendor: iTermAIVendor) {
        let value = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = keyIsEmpty(value) ? nil : value
        cachedKeys[cacheKey(for: vendor)] = CachedKey(valid: true, value: normalized)
        _ = SSKeychain.setPassword(normalized ?? "",
                                   forService: keychainService,
                                   account: keychainAccount(for: vendor))
        if vendor == .openAI {
            _ = SSKeychain.setPassword(normalized ?? "",
                                       forService: keychainService,
                                       account: legacyKeychainAccount)
        }
    }

    private static func cacheKey(for vendor: iTermAIVendor) -> UInt {
        return UInt(vendor.rawValue)
    }

    private static func keychainAccount(for vendor: iTermAIVendor) -> String {
        switch vendor {
        case .openAI:
            return legacyKeychainAccount
        case .anthropic:
            return "Anthropic API Key for iTerm2"
        case .gemini:
            return "Gemini API Key for iTerm2"
        case .deepSeek:
            return "DeepSeek API Key for iTerm2"
        case .llama:
            return "Llama API Key for iTerm2"
        case .apple:
            return "Apple Intelligence API Key for iTerm2"
        @unknown default:
            return "AI API Key for iTerm2"
        }
    }

    private static func keyIsEmpty(_ key: String?) -> Bool {
        key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func key(_ key: String, matches vendor: iTermAIVendor) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch vendor {
        case .anthropic:
            return trimmed.hasPrefix("sk-ant-")
        case .gemini:
            return trimmed.hasPrefix("AIza")
        case .openAI:
            return !trimmed.hasPrefix("sk-ant-") && !trimmed.hasPrefix("AIza")
        case .deepSeek:
            return !trimmed.hasPrefix("sk-ant-") && !trimmed.hasPrefix("AIza")
        case .llama, .apple:
            return true
        @unknown default:
            return true
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
                                          image: NSImage.it_imageNamed("aiterm", for: AITermControllerObjC.self)!)
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

        AIPromptTemplateEvaluator.evaluate(template,
                                           variables: [iTermAIPromptVariablePrompt: sanitizedPrompt],
                                           scope: scope,
                                           sideEffectsAllowed: true,
                                           synchronous: false) { maybeResult in
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
        if error as? PluginError == PluginError.cancelled {
            return
        }
        it_fatalError()
    }

    func aitermController(_ sender: AITermController, willInvokeFunction function: any LLM.AnyFunction) {
    }

    func aitermControllerDidCancelOutstandingRequest(_ sender: AITermController) {
    }


    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: ownerWindow,
                                                                        for: sender.requiredRegistrationVendor) { [weak self] registration in
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
