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

    // The vendors worth prewarming: every provider that authenticates with a
    // keychain-stored key. Llama is included because a self-hosted deployment
    // can require a token; Apple Intelligence is omitted because it runs
    // on-device and needs no key.
    private static let prewarmableVendors: [iTermAIVendor] = [
        .openAI, .anthropic, .gemini, .deepSeek, .llama
    ]

    // Read every provider's key from the keychain into the in-memory cache.
    // Meant to run at launch, and on a fresh pairing, whenever a companion
    // device is paired: a query later driven from the away phone then serves
    // its key from cache and never blocks on, or prompts for, keychain access
    // with nobody present to approve it. Runs off the main thread on the same
    // serial queue that guards all key access; idempotent, since already-cached
    // vendors short circuit inside apiKeyOnQueue.
    @objc static func prewarmAPIKeyCache() {
        apiKeyQueue.async {
            for vendor in prewarmableVendors {
                _ = apiKeyOnQueue(for: vendor)
            }
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

    // Presence check for Settings' status row. Unlike apiKey(for:) it never performs the
    // legacy->vendor ACCOUNT migration (adopting the shared legacy key for a vendor), so a
    // status check can't durably adopt the wrong secret. It is NOT fully side-effect-free,
    // though: reading through iTermUpgradeSafeKeychain transparently copies a pre-migration
    // login-keychain value into the data-protection keychain (a safe, idempotent storage
    // migration) and reaps the login copy, so merely viewing Settings can trigger that
    // migration. A transient read error is not cached as "no key". Safe off the main thread.
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
        // Only the EFFECTIVE vendor can adopt the shared legacy key (see resolveAPIKey),
        // so read the legacy account ONLY then - mirroring objcApiKeyIsConfigured. Reading
        // it for other vendors is wasted work AND a correctness hazard: a hard error on
        // that throwaway read would (via the guard below) report a vendor whose OWN key is
        // present and readable as keyless, and leave it uncached.
        let legacy: KeychainReadResult
        if account != legacyKeychainAccount, vendor == LLMMetadata.effectiveVendor {
            legacy = readKeychainPassword(account: legacyKeychainAccount)
        } else {
            legacy = KeychainReadResult(value: nil, hardError: false)
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
            persistAPIKey(value, account: account)
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
        // Read from the data-protection keychain (entitlement-gated, so upgrades no
        // longer pop a confirmation prompt), transparently migrating a value that a
        // pre-migration build wrote via SSKeychain into the login keychain. Use
        // WhenUnlocked to PRESERVE the prior accessibility: iTerm never called
        // +[SSKeychain setAccessibilityType:], so SSKeychain omitted kSecAttrAccessible
        // and the item took the OS default, kSecAttrAccessibleWhenUnlocked. WhenUnlocked
        // is not this-device-only, so a Migration-Assistant transfer still carries the
        // key, while not widening when the plaintext key is readable.
        let (status, data) = iTermUpgradeSafeKeychain.copyGenericPassword(
            service: keychainService,
            account: account,
            accessible: kSecAttrAccessibleWhenUnlocked)
        switch status {
        case errSecSuccess:
            return KeychainReadResult(value: data.flatMap { String(data: $0, encoding: .utf8) },
                                      hardError: false)
        case errSecItemNotFound:
            // Not stored yet - a legitimate absence, not a failure.
            return KeychainReadResult(value: nil, hardError: false)
        default:
            // A real error (locked/denied keychain) we must not confuse with "no key".
            return KeychainReadResult(value: nil, hardError: true)
        }
    }

    // Persist an API key, or clear it. Clearing DELETES the item from both keychains
    // rather than storing an empty value: an empty kSecValueData does not round-trip,
    // and an empty tombstone or a lingering legacy copy would let a cleared key
    // resurrect via migration. Absent and "" are already equivalent to keyIsEmpty.
    private static func persistAPIKey(_ value: String?, account: String) {
        guard let value, !keyIsEmpty(value) else {
            iTermUpgradeSafeKeychain.deleteGenericPassword(service: keychainService, account: account)
            return
        }
        let status = iTermUpgradeSafeKeychain.setGenericPassword(
            Data(value.utf8),
            service: keychainService,
            account: account,
            accessible: kSecAttrAccessibleWhenUnlocked)
        if status != errSecSuccess {
            // The value is cached in memory for this session, but persistence failed,
            // so it may not survive a restart. Surface it rather than dropping silently.
            RLog("AITerm: failed to persist API key for account '\(account)': OSStatus \(status). Cached for this session but may not survive a restart.")
        }
    }

    private static func setAPIKeyOnQueue(_ key: String?, for vendor: iTermAIVendor) {
        let value = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = keyIsEmpty(value) ? nil : value
        cachedKeys[cacheKey(for: vendor)] = CachedKey(valid: true, value: normalized)
        persistAPIKey(normalized, account: keychainAccount(for: vendor))
        if vendor == .openAI {
            persistAPIKey(normalized, account: legacyKeychainAccount)
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
