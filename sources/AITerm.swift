import CryptoKit
import JavaScriptCore

protocol AITermControllerDelegate: AnyObject {
    func aitermControllerWillSendRequest(_ sender: AITermController)
    func aitermController(_ sender: AITermController, offerChoice: String)
    // update will be nil upon completion
    func aitermController(_ sender: AITermController, didStreamUpdate update: String?)
    func aitermController(_ sender: AITermController, didFailWithError: Error)
    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ())
}


struct WebRequest: Codable, CustomDebugStringConvertible {
    var debugDescription: String {
        return "\(method) \(url)\n\(headers.debugDescription)\n\n\(body)"
    }
    var headers: [String: String]
    var method: String
    var body: String
    var url: String
}

struct WebResponse: Codable {
    var data: String
    var error: String?
}

struct PluginError: Error, CustomDebugStringConvertible {
    var debugDescription: String {
        return "<PluginError \(reason)>"
    }
    var localizedDescription: String {
        reason
    }
    var reason: String
}


struct Plugin {
    static private var _instance = MutableAtomicObject<Result<Plugin, PluginError>?>(nil)
    private static let publicKeyB64 = "fYLUx58QwucuPJRYxBjp7M//uVM0vTfgUo7d6u4TQR8="

    static func instance() -> Result<Plugin, PluginError> {
        return _instance.mutableAccess { result in
            switch result {
            case .success(let plugin):
                return .success(plugin)
            case .failure, .none:
                break
            }
            let temp = load()
            result = temp
            return temp
        }
    }

    private static func load() -> Result<Plugin, PluginError> {
        do {
            return  Result<Plugin, PluginError>.success(try Plugin())
        } catch let error as PluginError {
            let temp = Result<Plugin, PluginError>.failure(error)
            DLog("\(error.reason)")
            return temp
        } catch {
            DLog("\(error.localizedDescription)")
            let temp = Result<Plugin, PluginError>.failure(PluginError(reason: error.localizedDescription))
            return temp
        }
    }
    static func reload() {
        _instance.mutableAccess { result in
            result = load()
        }
    }

    private let bundleID = "com.googlecode.iterm2.iTermAI"
    private let code: String
    init() throws {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw PluginError(reason: "Plugin not found")
        }
        let jsURL = bundleURL.appendingPathComponent("Contents/Resources/iTermAIPlugin.js")
        guard let codeData = try? Data(contentsOf: jsURL) else {
            throw PluginError(reason: "Plugin missing from app bundle or not readable")
        }
        guard let code = String(data: codeData, encoding: .utf8) else {
            throw PluginError(reason: "Plugin code not valid UTF-8")
        }
        let signatureURL = bundleURL.appendingPathComponent("Contents/Resources/iTermAIPlugin.sig")
        guard let signatureB64 = try? String(contentsOf: signatureURL) else {
            throw PluginError(reason: "Signature missing from app bundle or not readable")
        }
        guard let signatureData = Data(base64Encoded: signatureB64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PluginError(reason: "Signature of AI plugin is malformed")
        }
        try Plugin.checkSignature(message: codeData, signature: signatureData)
        self.code = code
    }

    private static func checkSignature(message: Data, signature: Data) throws {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKeyB64)!)
        guard publicKey.isValidSignature(signature, for: message) else {
            throw PluginError(reason: "The plugin's signature is invalid. Reinstall the plugin or upgrade iTerm2.")
        }
        DLog("Signature is good")
    }

    func version() throws -> Decimal {
        let string: String = try PluginClient.instance.call(code: code,
                                                            functionName: "version",
                                                            request: nil as Optional<String>,
                                                            async: false,
                                                            stream: nil)
        guard let decimal = Decimal(string: string) else {
            throw PluginError(reason: "Invalid version string: \(string)")
        }
        return decimal
    }

    func load(webRequest: WebRequest, stream: ((String) -> ())?) throws -> WebResponse {
        DLog("load \(webRequest)")
        return try PluginClient.instance.call(code: code,
                                              functionName: "request",
                                              request: webRequest,
                                              async: true,
                                              stream: stream)
    }
}

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

class iTermAIClient {
    private let executionQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-execution")
    private let outputQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-output")
    static let instance = iTermAIClient()

    var available: Bool {
        return Plugin.instance().isSuccess
    }

    func version() throws -> Decimal {
        DLog("version")
        switch Plugin.instance() {
        case .success(let plugin):
            return try plugin.version()
        case .failure(let error):
            throw error
        }
    }

    // A Cancellation provides a way to cancel an asynchronous operation. The function to implement
    // cancellation can be provided after creation.
    // It safe to use concurrently.
    // It guarantees that the code to perform cancellation is executed exactly once if canceled.
    class Cancellation {
        private var lock = Mutex()
        private var _impl: (() -> ())?
        private var _canceled = false

        // Set this to a closure that implements cancellation. You can reassign to this as needed.
        // If this was canceled prior to setting impl for the first time, the setter may run the
        // closure synchronously.
        var impl: (() -> ())? {
            set {
                lock.sync {
                    if let f = newValue, _impl == nil, _canceled {
                        // Canceled before the first impl was set so cancel immediately.
                        DLog("already canceled")
                        f()
                    } else {
                        _impl = newValue
                    }
                }
            }
            get {
                lock.sync { _impl }
            }
        }

        // Has cancel() ever been called?
        var canceled: Bool {
            lock.sync { _canceled }
        }

        // Idempotent. Runs the cancellation handler eventually.
        func cancel() {
            DLog("cancel")
            lock.sync {
                guard !_canceled else {
                    return
                }
                _canceled = true
                let f = _impl
                _impl = nil
                f?()
            }
        }
    }

    private let requiredVersion = "1.1"

    // Runs on any queue. Throws a PluginError or does nothing.
    func validate() throws {
        DLog("validate")
        if (!iTermAdvancedSettingsModel.generativeAIAllowed()) {
            throw PluginError(reason: "Plugin not allowed by administator.")
        }
        switch Plugin.instance() {
        case .success(let plugin):
            guard let pluginVersion = try? plugin.version() else {
                throw PluginError(reason: "Unable to determine version of AI plugin. Reinstall it and upgrade iTerm2 if possible.")
            }

            guard pluginVersion == Decimal(string: requiredVersion) else {
                throw PluginError(reason: "Plugin has version \(pluginVersion) but iTerm2 expects \(requiredVersion). Upgrade one or both.")
            }
            return
        case .failure(let error):
            DLog("\(error)")
            throw error
        }
    }

    func validate(_ completion: @escaping (String?) -> ()) {
        executionQueue.async {
            do {
                try self.validate()
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error as PluginError {
                DispatchQueue.main.async {
                    completion(error.reason)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error.localizedDescription)
                }
            }
        }
    }

    func reload(_ completion: @escaping () -> ()) {
        executionQueue.async {
            do {
                Plugin.reload()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    func request(webRequest: WebRequest,
                 stream: ((String) -> ())?,
                 completion: @escaping (Result<WebResponse, PluginError>) -> ()) -> Cancellation {
        let cancellation = Cancellation()
        executionQueue.async {
            switch Plugin.instance() {
            case .success(let plugin):
                do {
                    let response = try plugin.load(webRequest: webRequest, stream: stream)
                    DispatchQueue.main.async {
                        if !cancellation.canceled {
                            completion(.success(response))
                        }
                    }
                } catch let error as PluginError {
                    DispatchQueue.main.async {
                        if !cancellation.canceled {
                            completion(.failure(error))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        if !cancellation.canceled {
                            completion(.failure(PluginError(reason: "Unexpected exception: \(error.localizedDescription)")))
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    if !cancellation.canceled {
                        completion(.failure(error))
                    }
                }
            }
        }
        return cancellation
    }
}

@objc
class iTermAITermGatekeeper: NSObject {
    @objc
    static func validatePlugin(_ completion: @escaping (String?) -> ()) {
        DLog("validatePlugin")
        iTermAIClient.instance.validate(completion)
    }

    @objc
    static func reloadPlugin(_ completion: @escaping () -> ()) {
        DLog("reloadPlugin")
        iTermAIClient.instance.reload(completion)
    }

    @objc(checkSilently:)
    static func check(silent: Bool = false) -> Bool {
        DLog("check")
        if !iTermAdvancedSettingsModel.generativeAIAllowed() {
            if !silent {
                iTermWarning.show(withTitle: "Generative AI features have been disabled. Check with your system administrator.",
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Feature Unavailable",
                                  window: nil)
            }
            return false
        }
        if !iTermAITermGatekeeper.pluginInstalled() {
            if !silent {
                let selection = iTermWarning.show(withTitle: "You must install the AI plugin before you can use this feature.",
                                                  actions: ["Reveal in Settings", "Cancel"],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: "Plugin Missing",
                                                  window: nil)
                if selection == .kiTermWarningSelection0 {
                    PreferencePanel.sharedInstance().openToPreference(withKey: kPhonyPreferenceKeyInstallAIPlugin)
                }
            }
            return false
        }
        if !SecureUserDefaults.instance.enableAI.value {
            if !silent {
                let selection = iTermWarning.show(withTitle: "You must enable AI features in settings before you can use this feature.",
                                                  actions: ["Reveal", "Cancel"],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: "Feature Unavailable",
                                                  window: nil)
                if selection == .kiTermWarningSelection0 {
                    PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyEnableAI)
                }
            }
            return false
        }
        do {
            try iTermAIClient.instance.validate()
        } catch let error as PluginError {
            DLog("\(error.reason)")
            if !silent {
                iTermWarning.show(withTitle: error.reason,
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Feature Unavailable",
                                  window: nil)
            }
            return false
        } catch {
            if !silent {
                iTermWarning.show(withTitle: error.localizedDescription,
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Feature Unavailable",
                                  window: nil)
            }
            return false
        }
        return true
    }

    @objc
    static func pluginInstalled() -> Bool {
        switch Plugin.instance() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    @objc
    static var allowed: Bool {
        DLog("allowed")
        return iTermAdvancedSettingsModel.generativeAIAllowed() && SecureUserDefaults.instance.enableAI.value
    }
}

class AITermControllerRegistrationHelper {
    static var instance = AITermControllerRegistrationHelper()

    var registration: AITermController.Registration? {
        if !iTermAITermGatekeeper.allowed {
            return nil
        }
        return AITermController.Registration(apiKey: AITermControllerObjC.apiKey)
    }

    func setKey(_ key: String) {
        AITermControllerObjC.apiKey = key
    }

    func requestRegistration(in window: NSWindow, completion: @escaping (AITermController.Registration?) -> ()) {
        if !iTermAITermGatekeeper.check() {
            completion(nil)
            return
        }
        let windowController = AITermRegistrationWindowController.create()
        window.beginSheet(windowController.window!) { [weak self] response in
            windowController.window?.orderOut(nil)
            if response == .OK, let key = windowController.apiKey {
                self?.setKey(key)
            }
            if response == .OK, let registration = AITermController.Registration(apiKey: windowController.apiKey) {
                completion(registration)
            } else {
                completion(nil)
            }
        }
    }
}

extension NSWindow: AIRegistrationProvider {
    func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: self,
                                                                        completion: completion)
    }
}

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

    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: ownerWindow) { [weak self] registration in
            guard let self else {
                return
            }
            if let registration {
                completion(registration)
            } else {
                handler?(.failure(AIError("You must provide a valid API key to use AI features in iTerm2.")))
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

protocol AnyOptional {
    static var wrappedType: Any.Type { get }
}

extension Optional: AnyOptional {
    static var wrappedType: Any.Type {
        return Wrapped.self
    }
}

struct JSONSchema: Codable {
    var type = "object"
    var properties: [String: Property] = [:]
    var required: [String] = []

    struct Property: Codable {
        var type: String  // e.g., "string"
        var description: String?  // Documentation
        var `enum`: [String]?
    }

    init<T>(for instance: T,
            descriptions: [String: String]) {
        let mirror = Mirror(reflecting: instance)

        for child in mirror.children {
            guard let label = child.label else { continue }

            let type = Swift.type(of: child.value)
            let fieldType = JSONSchema.extractFieldType(type)

            var property = Property(type: fieldType)
            property.description = descriptions[label]

            properties[label] = property
            if !(child.value is AnyOptional.Type) {
                required.append(label)
            }
        }
    }

    private static func extractFieldType(_ type: Any.Type) -> String {
        if type == Int.self || type == UInt.self || type == Int8.self || type == UInt8.self ||
            type == Int16.self || type == UInt16.self || type == Int32.self || type == UInt32.self ||
            type == Int64.self || type == UInt64.self || type == Float.self || type == Double.self {
            return "number"
        } else if type == String.self {
            return "string"
        } else if type == Bool.self {
            return "boolean"
        } else if let optionalType = type as? AnyOptional.Type {
            return extractFieldType(optionalType.wrappedType)
        } else {
            return "object"
        }
    }

}

struct ChatGPTFunctionDeclaration: Codable {
    var name: String
    var description: String
    var parameters: JSONSchema
}

enum AIPluginStatus {
    case pluginNotFound
    case executionError
    case status(Int)
    case badOutput
    case runtimeError
    case canceled
}

class AITermController {
    typealias Message = LLM.Message
    var representedObject: String?
    private(set) fileprivate var functions = [LLM.AnyFunction]()
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

    enum State: Equatable, CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .ground: return "ground"
            case .initialized(query: let query, stream: let stream): return "initialized(\(query), stream=\(stream)"
            case .initializedMessages(messages: let messages, stream: let stream): return "initializedMessages(\(messages.count) messages, stream=\(stream)"
            case .querySent: return "querySent"
            }
        }
        case ground
        case initialized(query: String, stream: Bool)
        case initializedMessages(messages: [Message], stream: Bool)
        // streamParserState is nil if streaming is unsupported, otherwise it will be nonnil but perhaps empty
        case querySent(messages: [Message], streamParserState: StreamParserState?)
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

    func request(query: String, stream: Bool = false) {
        state = .initialized(query: query, stream: stream)
        handle(event: .begin)
    }

    func request(messages: [Message], stream: Bool = false) {
        state = .initializedMessages(messages: messages, stream: stream)
        handle(event: .begin)
    }

    func removeAllFunctions() {
        functions.removeAll()
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration, arguments: T.Type, implementation: @escaping LLM.Function<T>.Impl) {
        functions.append(LLM.Function(decl: decl, call: implementation, parameterType: arguments))
    }

    fileprivate func define(functions: [LLM.AnyFunction]) {
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

        case .initialized(query: let query, stream: let stream):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    makeAPICall(query: query,
                                registration: registration,
                                stream: stream ? { [weak self] word in
                        self?.handle(event: .word(word))
                    } : nil)
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .error(let error):
                DLog("error: \(error)")
                state = .ground
                delegate?.aitermController(self, didFailWithError: error)
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
                    makeAPICall(messages: messages,
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
                    let provider = llmProvider.displayName
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

    private func makeAPICall(query: String, registration: Registration, stream: ((String) -> ())?) {
        makeAPICall(messages: [Message(role: .user, content: query)],
                    registration: registration,
                    stream: stream)
    }

    private let client = iTermAIClient()
    private var cancellation: iTermAIClient.Cancellation?

    static var provider: LLMProvider {
        let model = LLMMetadata.model()
        let platform = LLMMetadata.platform()
        return LLMProvider(platform: platform, model: model)
    }

    private var llmProvider: LLMProvider {
        Self.provider
    }

    private func makeAPICall(messages: [Message], registration: Registration, stream: ((String) -> ())?) {
        var builder = LLMRequestBuilder(provider: llmProvider,
                                        apiKey: registration.apiKey,
                                        messages: messages,
                                        functions: functions)
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

    struct StreamParserState: Equatable {
        var message: LLM.Message
        var buffer: Data
    }

    private func parseStreamingResponse(data: Data, final: Bool, parserState: StreamParserState) -> StreamParserState? {
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
        var (first, rest) = llmProvider.responseParser(stream: true).splitFirstJSONEvent(from: string)

        let drain = {
            if let string = accumulatingMessage.content, !string.isEmpty {
                DLog("drain with content: \(accumulatingMessage)")
                self.delegate?.aitermController(self, didStreamUpdate: string)
                accumulatingMessage.content = nil
            }
        }
        do {
            defer { drain() }
            while first != nil {
                if let first, let firstData = first.data(using: .utf8) {
                    if first == "[DONE]" {
                        break
                    }
                    do {
                        var parser = llmProvider.responseParser(stream: true)
                        let response = try parser.parse(data: firstData)
                        guard let response else {
                            DLog("Stream finished")
                            break
                        }
                        guard let choice = response.choiceMessages.first else {
#if DEBUG
                            it_fatalError("Unexpected choiceless message \(firstData.stringOrHex)")
#endif
                            continue
                        }
                        if let role = choice.role {
                            accumulatingMessage.role = role
                        }
                        if let functionCall = choice.function_call {
                            drain()
                            if accumulatingMessage.function_call == nil {
                                accumulatingMessage.function_call = .init(name: "", arguments: "")
                            }
                            accumulatingMessage.function_call!.name! += (functionCall.name ?? "")
                            accumulatingMessage.function_call!.arguments! += (functionCall.arguments ?? "")
                        }
                        if let additionalContent = choice.content {
                            if accumulatingMessage.content == nil {
                                accumulatingMessage.content = ""
                            }
                            accumulatingMessage.content! += additionalContent
                        }
                    } catch {
                        drain()
                        if let reason = LLMErrorParser.errorReason(data: firstData) {
                            handle(event: .error(AIError("Could not decode response: " + reason)))
                            return nil
                        } else {
                            handle(event: .error(AIError("Failed to decode API response: \(error). Data is: \(first)")))
                            return nil
                        }
                    }
                }
                (first, rest) = llmProvider.responseParser(stream: true).splitFirstJSONEvent(from: rest)
            }
        }

        return StreamParserState(message: accumulatingMessage, buffer: rest.data(using: .utf8)!)
    }

    private func parseNonStreamingResponse(data: Data) {
        do {
            var parser = llmProvider.responseParser(stream: false)
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

    private func doFunctionCall(_ message: Message, call functionCall: Message.FunctionCall) {
        switch state {
        case .ground, .initialized, .initializedMessages:
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
                                               name: functionCall.name))
                        state = .ground
                        if let truncate {
                            amended = truncate(amended)
                        }
                        request(messages: amended)
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
            request(messages: amended)
        }
    }
}

@objc
class AITermRegistrationWindowController: NSWindowController {
    @IBOutlet var message: NSTextView!
    @IBOutlet var okButton: NSButton!
    @IBOutlet var textField: NSTextField!
    @IBOutlet var titleImageView: NSImageView!
    private(set) var apiKey: String?

    static func create() -> AITermRegistrationWindowController {
        return AITermRegistrationWindowController(windowNibName: NSNib.Name("AITerm"))
    }

    override func awakeFromNib() {
        var temp = message.string
        let urls = ["https://openai.com/join/",
                    "https://platform.openai.com/api-keys",
                    "https://iterm2.com/aiterm"]
        for (i, url) in urls.enumerated() {
            temp = temp.replacingOccurrences(of: "$\(i + 1)", with: url)
        }

        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let attributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: NSColor.textColor,
        ]

        let attributed = NSMutableAttributedString(string: temp, attributes: attributes)
        attributed.makeLinks()
        message.textStorage?.setAttributedString(attributed)
        super.awakeFromNib()
        okButton.isEnabled = !textField.stringValue.isEmpty
        titleImageView.image?.isTemplate = true
        
        DispatchQueue.main.async { [self] in
            self.window?.makeFirstResponder(textField)
        }
    }

    @IBAction func ok(_ sender: Any) {
        apiKey = textField.stringValue
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @IBAction func cancel(_ sender: Any) {
        apiKey = nil
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }
}

extension AITermRegistrationWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        DLog("\(link)")
        return true
    }
}

extension AITermRegistrationWindowController: NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        okButton.isEnabled = !textField.stringValue.isEmpty
    }
}

extension NSMutableAttributedString {
    func makeLinks() {
        let baseAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single,
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.cursor: NSCursor.pointingHand
        ]
        while let info = firstAnchorInfo() {
            if let url = URL(string: info.href) {
                var attributes = baseAttributes
                attributes[.link] = url
                replace(range: info.range,
                        with: info.anchorText,
                        attributes:attributes)
            }
        }
    }

    private func replace(range: Range<Int>, with replacement: String, attributes: [NSAttributedString.Key: Any]) {
        self.replaceAttributes(in: NSRange(range), withAttributes: attributes)
        self.replaceCharacters(in: NSRange(range), with: replacement)
    }

    private struct AnchorInfo {
        var range: Range<Int>
        var href: String
        var anchorText: String
    }

    private func firstAnchorInfo() -> AnchorInfo? {
        let pattern = #"(<a[^>]+href=\"(.*?)\"[^>]*>)(.*?)(</a>)"#
        guard let regex = try? RegexCache.instance.get(pattern) else {
            return nil
        }
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: string.count)) else {
            return nil
        }

        let hrefRange = match.range(at: 2)
        let anchorRange = match.range(at: 3)
        return AnchorInfo(range: Range(match.range)!,
                          href: string.substring(nsrange: hrefRange),
                          anchorText: string.substring(nsrange: anchorRange))
    }
}

class AITermRegistrationWindow: NSWindow {
    override var acceptsFirstResponder: Bool {
        true
    }
    override var canBecomeKey: Bool {
        true
    }
    override var canBecomeMain: Bool {
        true
    }
}

@objc public class iTermAIError: NSObject {
    @objc static let domain = "com.iterm2.ai"
    @objc(iTermAIErrorType) public enum ErrorType: Int, Codable {
        case generic = 0
        case requestTooLarge = 1
    }
}

public struct AIError: LocalizedError, CustomStringConvertible, CustomNSError, Codable {
    public internal(set) var message: String
    public internal(set) var type = iTermAIError.ErrorType.generic

    public init(_ message: String) {
        self.message = message
    }

    public init(_ message: String, type: iTermAIError.ErrorType) {
        self.message = message
        self.type = type
    }

    public var errorDescription: String? {
        message
    }

    public var description: String {
        message
    }

    var localizedDescription: String {
        message
    }

    static var requestTooLarge: AIError {
        AIError("AI token limit exceeded because the conversation reached its maximum length", type: .requestTooLarge)
    }

    static func wrapping(error: Error, context: String) -> AIError {
        return AIError(context + ": " + error.localizedDescription)
    }

    public static var errorDomain: String { iTermAIError.domain }
    public var errorCode: Int { type.rawValue }
}

protocol AIRegistrationProvider: AnyObject {
    func registrationProviderRequestRegistration(
        _ completion: @escaping (AITermController.Registration?) -> ())
}

struct AIConversation {
    private class Delegate: AITermControllerDelegate {
        private(set) var busy = false
        var completion: ((Result<String, Error>) -> ())?
        var streaming: ((String) -> ())?
        var registrationNeeded: ((@escaping (AITermController.Registration) -> ()) -> ())?

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
                streaming?(update)
            } else {
                completion?(.success(""))
            }
        }
    }

    var messages: [AITermController.Message]
    private var controller: AITermController
    private var delegate = Delegate()
    private(set) weak var registrationProvider: AIRegistrationProvider?
    var maxTokens: Int {
        return Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit) - iTermAdvancedSettingsModel.aiResponseMaxTokens())
    }
    var busy: Bool { delegate.busy }

    init(registrationProvider: AIRegistrationProvider?,
         messages: [AITermController.Message] = []) {
        self.registrationProvider = registrationProvider
        self.messages = messages
        controller = AITermController(registration: AITermControllerRegistrationHelper.instance.registration)
        controller.delegate = delegate
        let maxTokens = self.maxTokens
        controller.truncate = { truncate(messages: $0, maxTokens: maxTokens) }
    }

    func removeAllFunctions() {
        controller.removeAllFunctions()
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration,
                            arguments: T.Type,
                            implementation: @escaping LLM.Function<T>.Impl) {
        controller.define(function: decl, arguments: arguments, implementation: implementation)
    }

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
    mutating func add(_ aiMessage: AITermController.Message) {
        while messages.last?.role == aiMessage.role {
            messages.removeLast()
        }
        messages.append(aiMessage)
    }
    
    mutating func add(text: String, role: LLM.Message.Role = .user) {
        add(AITermController.Message(role: role, content: text))
    }

    mutating func complete(_ completion: @escaping (Result<AIConversation, Error>) -> ()) {
        complete(streaming: nil, completion: completion)
    }

    mutating func complete(streaming: ((String) -> ())?,
                           completion: @escaping (Result<AIConversation, Error>) -> ()) {
        precondition(!messages.isEmpty)

        if delegate.busy {
            controller.cancel()
            delegate.completion = { _ in }
            delegate.streaming = nil
            delegate.registrationNeeded = { _ in }
        }

        let prior = messages
        let controller = self.controller
        let messages = self.truncatedMessages
        delegate.registrationNeeded = { [weak registrationProvider] regCompletion in
            if let registrationProvider {
                registrationProvider.registrationProviderRequestRegistration() { registration in
                    if let registration {
                        regCompletion(registration)
                        controller.request(messages: messages)
                    } else {
                        completion(.failure(AIError("You must provide a valid API key to use AI features in iTerm2.")))
                    }
                }
            } else {
                DLog("No registration provider found")
                completion(.failure(AIError("You must provide a valid API key to use AI features in iTerm2")))
            }
        }

        var accumulator = ""
        if let streaming {
            delegate.streaming = { update in
                accumulator += update
                streaming(update)
            }
        }

        delegate.completion = { [weak registrationProvider] result in
            switch result {
            case .success(let text):
                let message = AITermController.Message(role: .assistant,
                                                       content: accumulator + text)
                let amended = AIConversation(registrationProvider: registrationProvider,
                                             messages: prior + [message])
                amended.controller.define(functions: controller.functions)
                completion(.success(amended))
            break
            case .failure(let error):
                completion(.failure(error))
            break
            }
        }
        controller.request(messages: truncatedMessages, stream: streaming != nil)
    }

    private var truncatedMessages: [AITermController.Message] {
        return truncate(messages: messages, maxTokens: maxTokens)
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
                messagesToSend[j].content = head + "…[truncated]…" + tail
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

extension String {
    var halved: (String, String) {
        let middleIndex = index(startIndex, offsetBy: count / 2)
        let head = String(prefix(upTo: middleIndex))
        let tail = String(suffix(from: middleIndex))
        return (head, tail)
    }
}

extension String {
    var lossyData: Data {
        return Data(utf8)
    }
}

extension Data {
    var lossyString: String {
        return String(decoding: self, as: UTF8.self)
    }
}

extension Result {
    func handle<T>(success: (Success) throws -> (T), failure: (Failure) throws -> (T)) rethrows -> T {
        switch self {
        case .success(let value):
            try success(value)
        case .failure(let value):
            try failure(value)
        }
    }

    var successValue: Success? {
        switch self {
        case .success(let value): value
        case .failure(_): nil
        }
    }
    var failureValue: Failure? {
        switch self {
        case .success: nil
        case .failure(let failure): failure
        }
    }
}
