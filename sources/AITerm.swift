import CryptoKit
import JavaScriptCore

protocol AITermControllerDelegate: AnyObject {
    func aitermControllerWillSendRequest(_ sender: AITermController)
    func aitermController(_ sender: AITermController, offerChoices: [String])
    func aitermController(_ sender: AITermController, didFailWithErrorMessage: String)
    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ())
}

fileprivate func openAIModelIsLegacy(model: String) -> Bool {
    return !model.hasPrefix("gpt-")
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
    var error: String
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
            do {
                let temp = Result<Plugin, PluginError>.success(try Plugin())
                result = temp
                return temp
            } catch let error as PluginError {
                let temp = Result<Plugin, PluginError>.failure(error)
                DLog("\(error.reason)")
                result = temp
                return temp
            } catch {
                DLog("\(error.localizedDescription)")
                let temp = Result<Plugin, PluginError>.failure(PluginError(reason: error.localizedDescription))
                result = temp
                return temp
            }
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
            throw PluginError(reason: "The plugin's signature was incorrect. Reinstall the plugin or upgrade iTerm2.")
        }
        DLog("Signature is good")
    }

    func version() throws -> Decimal {
        let string: String = try PluginClient.instance.call(code: code,
                                                            functionName: "version",
                                                            request: nil as Optional<String>,
                                                            async: false)
        guard let decimal = Decimal(string: string) else {
            throw PluginError(reason: "Invalid version string: \(string)")
        }
        return decimal
    }

    func load(webRequest: WebRequest) throws -> WebResponse {
        DLog("load \(webRequest)")
        return try PluginClient.instance.call(code: code,
                                              functionName: "request",
                                              request: webRequest,
                                              async: true)
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
        switch Plugin.instance() {
        case .success(let plugin):
            guard let pluginVersion = try? plugin.version() else {
                throw PluginError(reason: "Unable to determine version of AI plugin. Reinstall it and upgrade iTerm2 if possible.")
            }

            guard pluginVersion == Decimal(string: requiredVersion) else {
                throw PluginError(reason: "Incorrect version of AI plugin found. It has version \(pluginVersion) but this version of iTerm2 expects \(requiredVersion). Upgrade the plugin and iTerm2 if possible.")
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

    func request(webRequest: WebRequest,
                 completion: @escaping (Result<WebResponse, PluginError>) -> ()) -> Cancellation {
        let cancellation = Cancellation()
        executionQueue.async {
            switch Plugin.instance() {
            case .success(let plugin):
                do {
                    let response = try plugin.load(webRequest: webRequest)
                    DispatchQueue.main.async {
                        completion(.success(response))
                    }
                } catch let error as PluginError {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(PluginError(reason: "Unexpected exception: \(error.localizedDescription)")))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
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
    static func check() -> Bool {
        DLog("check")
        if !iTermAdvancedSettingsModel.generativeAIAllowed() {
            iTermWarning.show(withTitle: "Generative AI features have been disabled. Check with your system administrator.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Feature Unavailable",
                              window: nil)
            return false
        }
        if !iTermAITermGatekeeper.pluginInstalled() {
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
            return false
        }
        if !SecureUserDefaults.instance.enableAI.value {
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
            return false
        }
        do {
            try iTermAIClient.instance.validate()
        } catch let error as PluginError {
            DLog("\(error.reason)")
            iTermWarning.show(withTitle: error.reason,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Feature Unavailable",
                              window: nil)
            return false
        } catch {
            iTermWarning.show(withTitle: error.localizedDescription,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Feature Unavailable",
                              window: nil)
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

@objc
class AITermControllerObjC: NSObject, AITermControllerDelegate, iTermObject {
    private struct CachedKey {
        var valid = false
        var value: String?
    }
    private let controller: AITermController
    private let handler: ([String]?, String?) -> ()
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
         handler: @escaping ([String]?, String?) -> ()) {
        let pleaseWait = PleaseWaitWindow(owningWindow: window,
                                          message: "Thinking…",
                                          image: NSImage.it_imageNamed("aiterm", for: AITermControllerObjC.self))
        self.pleaseWait = pleaseWait
        var cancel: (() -> ())?
        var shouldCancel = false
        self.handler = { choices, error in
            if !pleaseWait.canceled {
                handler(choices, error)
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

    func aitermControllerWillSendRequest(_ sender: AITermController) {
        pleaseWait.run()
    }

    func aitermController(_ sender: AITermController, offerChoices choices: [String]) {
        pleaseWait.stop()
        DispatchQueue.main.async {
            self.handler(choices, nil)
        }
    }

    func aitermController(_ sender: AITermController, didFailWithErrorMessage errorMessage: String) {
        pleaseWait.stop()
        DispatchQueue.main.async {
            self.handler(nil, errorMessage)
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
                handler(nil, nil)
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

fileprivate protocol AnyFunction {
    var typeErasedParameterType: Any.Type { get }
    var decl: ChatGPTFunctionDeclaration { get }
    func invoke(json: Data, llm: AITermController, completion: @escaping (Result<String, Error>) -> ())
}

struct Function<T: Codable>: AnyFunction {
    typealias Impl = (T, AITermController, @escaping (Result<String, Error>) -> ()) -> ()

    var decl: ChatGPTFunctionDeclaration
    var call: Impl
    var parameterType: T.Type

    var typeErasedParameterType: Any.Type { parameterType }
    func invoke(json: Data, llm: AITermController, completion: @escaping (Result<String, Error>) -> ()) {
        do {
            let value = try JSONDecoder().decode(parameterType, from: json)
            call(value, llm, completion)
        } catch {
            DLog("\(error.localizedDescription)")
            completion(.failure(error))
        }
    }
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
    var representedObject: String?
    private(set) fileprivate var functions = [AnyFunction]()
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
            case .initialized(query: let query): return "initialized(\(query))"
            case .initializedMessages(messages: let messages): return "initializedMessages(\(messages.count) messages)"
            case .querySent: return "querySent"
            }
        }
        case ground
        case initialized(query: String)
        case initializedMessages(messages: [Message])
        case querySent(messages: [Message])
    }

    enum Event: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .begin: return "begin"
            case .error(reason: let reason): return "error(\(reason))"
            case .pluginError(let error): return "pluginError(\(error.reason))"
            case .webResponse: return "webResponse"
            case .cancel: return "Cancel"
            }
        }
        case begin
        case error(reason: String)
        case pluginError(PluginError)
        case webResponse(WebResponse)
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

    func request(query: String) {
        precondition(state == .ground)
        state = .initialized(query: query)
        handle(event: .begin, legacy: false)
    }

    func request(messages: [Message]) {
        precondition(state == .ground)
        state = .initializedMessages(messages: messages)
        handle(event: .begin, legacy: false)
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration, arguments: T.Type, implementation: @escaping Function<T>.Impl) {
        functions.append(Function(decl: decl, call: implementation, parameterType: arguments))
    }

    fileprivate func define(functions: [AnyFunction]) {
        self.functions.append(contentsOf: functions)
    }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
    }

    private func handle(event: Event, legacy: Bool) {
        DLog("handle(\(event)) in state \(state)")
        switch state {
        case .ground:
            DLog("Ignore \(event) in ground state.")
            break

        case .initialized(query: let query):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    makeAPICall(query: query, registration: registration)
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .error(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
            case .pluginError(let error):
                DLog("plugin error: \(error.reason)")
                state = .ground
            case .webResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            case .cancel:
                DLog("Cancel")
                state = .ground
            }

        case .initializedMessages(messages: let messages):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    makeAPICall(messages: messages, registration: registration)
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .pluginError(let error):
                DLog("plugin error: \(error.reason)")
                state = .ground
            case .error(let reason):
                DLog("error: \(reason)")
                state = .ground
            case .webResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            case .cancel:
                DLog("Cancel")
                state = .ground
            }

        case .querySent:
            switch event {
            case .begin:
                fatalError()
            case .webResponse(let response):
                if !response.error.isEmpty {
                    let error = response.error
                    let provider =
                        if usingOpenAI {
                            "OpenAI"
                        } else {
                            modelURL?.host ?? "the API provider"
                        }
                    let decoder = JSONDecoder()
                    var message = "Error from \(provider): \(error)"
                    if let errorResponse = try? decoder.decode(ErrorResponse.self, from: response.data.lossyData), !errorResponse.error.message.isEmpty {
                        message += " " + errorResponse.error.message
                    }
                    handle(event: .error(reason: message), legacy: false)
                } else {
                    parseResponse(data: response.data.data(using: .utf8)!, legacy: legacy)
                }
            case .pluginError(let error):
                handle(event: .error(reason: error.reason), legacy: false)
            case .cancel:
                state = .ground
            case .error(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
                delegate?.aitermController(self, didFailWithErrorMessage: reason)
            }
        }
    }

    func hostIsOpenAIAPI(url: URL?) -> Bool {
        return url?.host == "api.openai.com"
    }

    var usingOpenAI: Bool {
        return hostIsOpenAIAPI(url: modelURL)
    }

    private func requestRegistration(continuation: State) {
        state = .ground
        delegate?.aitermControllerRequestRegistration(self) { [weak self] registration in
            self?.registration = registration
            self?.state = continuation
            self?.handle(event: .begin, legacy: false)
        }
    }

    private var settingsURL: URL {
        var value = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = iTermPreferences.defaultObject(forKey: kPreferenceKeyAITermURL) as! String
        }
        return URL(string: value) ?? URL(string: "about:empty")!
    }

    private func url(forModel model: String) -> URL? {
        let settingsURL = self.settingsURL
        if hostIsOpenAIAPI(url: settingsURL) &&
            !openAIModelIsLegacy(model: model) {
            return URL(string: "https://api.openai.com/v1/chat/completions")
        }
        return settingsURL
    }

    private func maxTokens(model: String,
                           query: String,
                           functions: [ChatGPTFunctionDeclaration]) -> Int {
        let encodedFunctions = {
            if functions.isEmpty {
                return ""
            }
            guard let data = try? JSONEncoder().encode(functions) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }()
        let naiveLimit = Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit)) - OpenAIMetadata.instance.tokens(in: query) - OpenAIMetadata.instance.tokens(in: encodedFunctions)
        if let responseLimit = OpenAIMetadata.instance.maxResponseTokens(modelName: model) {
            return min(responseLimit, naiveLimit)
        }
        return naiveLimit
    }

    private func legacyRequestBody(model: String, messages: [Message]) -> Data {
        struct LegacyBody: Codable {
            var model: String  // "text-davinci-003"
            var prompt: String
            var max_tokens: Int
            var temperature = 0
        }
        let query = messages.compactMap { $0.content }.joined(separator: "\n")
        let body = LegacyBody(model: model,
                              prompt: query,
                              max_tokens: maxTokens(model: model, query: query, functions: []))
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }

    struct Message: Codable, Equatable {
        var role = "user"
        var content: String?

        // For function calling
        var name: String?
        var function_call: FunctionCall?

        struct FunctionCall: Codable, Equatable {
            var name: String
            var arguments: String
        }

        enum CodingKeys: String, CodingKey {
            case role
            case name
            case content
            case function_call
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(role, forKey: .role)

            if let name {
                try container.encode(name, forKey: .name)
            }

            try container.encode(content, forKey: .content)

            if let function_call {
                try container.encode(function_call, forKey: .function_call)
            }
        }

        var approximateTokenCount: Int { OpenAIMetadata.instance.tokens(in: (content ?? "")) + 1 }
    }

    struct Body: Codable {
        var model: String  // "text-davinci-003"
        var messages = [Message]()
        var max_tokens: Int
        var temperature = 0
        var functions: [ChatGPTFunctionDeclaration]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
    }

    private func modernRequestBody(model: String, messages: [Message]) -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let query = messages.compactMap { $0.content }.joined(separator: "\n")
        let maybeDecls = functions.isEmpty ? nil : functions.map { $0.decl }
        let body = Body(model: model,
                        messages: messages,
                        max_tokens: maxTokens(model: model, query: query, functions: maybeDecls ?? []),
                        functions: maybeDecls,
                        function_call: functions.isEmpty ? nil : "auto")
        DLog("REQUEST:\n\(body)")
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }

    private func shouldUseLegacyAPI(_ model: String) -> Bool {
        if usingOpenAI {
            return openAIModelIsLegacy(model: model)
        } else {
            return iTermPreferences.bool(forKey: kPreferenceKeyAITermUseLegacyAPI)
        }
    }

    private func requestBody(model: String, messages: [Message]) -> Data {
        if shouldUseLegacyAPI(model) {
            return legacyRequestBody(model: model, messages: messages)
        }
        return modernRequestBody(model: model, messages: messages)
    }

    private func makeAPICall(query: String, registration: Registration) {
        makeAPICall(messages: [Message(role: "user", content: query)], registration: registration)
    }

    private var modelURL: URL? {
        let model = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-3.5-turbo"
        return url(forModel: model)
    }

    private let client = iTermAIClient()
    private var cancellation: iTermAIClient.Cancellation?

    private func makeAPICall(messages: [Message], registration: Registration) {
        let model = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-3.5-turbo"
        guard let url = url(forModel: model) else {
            handle(event: .error(reason: "Invalid URL for AI provider of \(self.settingsURL.absoluteString)"), legacy: false)
            return
        }
        let headers = ["Content-Type": "application/json",
                       "Authorization": "Bearer " + registration.apiKey]
        let request = WebRequest(headers: headers,
                                 method: "POST",
                                 body: requestBody(model: model, messages: messages).lossyString,
                                 url: url.absoluteString)
        let legacy = shouldUseLegacyAPI(model)
        cancellation = client.request(webRequest: request, completion: { [weak self] result in
            switch result {
            case .success(let response):
                self?.handle(event: .webResponse(response),
                             legacy: legacy)
            case .failure(let error):
                self?.handle(event: .pluginError(error),
                             legacy: legacy)
            }
        })
        state = .querySent(messages: messages)
    }

    struct ModernResponse: Codable {
        var id: String
        var object: String
        var created: Int
        var model: String
        var choices: [Choice]
        var usage: Usage

        struct Choice: Codable {
            var index: Int
            var message: Message
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }
    }

    struct ErrorResponse: Codable {
        var error: Error

        struct Error: Codable {
            var message: String
            var type: String?
            var code: String?
        }
    }

    struct LegacyResponse: Codable {
        var id: String
        var object: String
        var created: Int
        var model: String
        var choices: [Choice]
        var usage: Usage

        struct Choice: Codable {
            var text: String
            var index: Int?
            var logprobs: Int?
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }
    }

    private func parseResponse(data: Data, legacy: Bool) {
        do {
            let choices = legacy ? try parseLegacyResponse(data: data) : try parseModernResponse(data: data)
            if let choices {
                state = .ground
                delegate?.aitermController(self, offerChoices: choices)
            }
        } catch {
            let decoder = JSONDecoder()
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                handle(event: .error(reason: "Could not decode response: " + errorResponse.error.message),
                       legacy: legacy)
            } else {
                handle(event: .error(reason: "Failed to decode API response: \(error). Data is: \(data.stringOrHex)"),
                       legacy: legacy)
            }
        }
    }

    private func parseLegacyResponse(data: Data) throws -> [String] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyResponse.self, from: data)
        let choices = response.choices.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return choices
    }

    private func parseModernResponse(data: Data) throws -> [String]? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        let choices = response.choices.compactMap { choice -> String? in
            guard let content = choice.message.content else {
                return nil
            }
            return String(content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
        }
        if let firstChoice = response.choices.first,
           let functionCall = firstChoice.message.function_call {
            doFunctionCall(firstChoice.message, call: functionCall)
            return nil
        }
        return choices
    }

    private func doFunctionCall(_ message: Message, call functionCall: Message.FunctionCall) {
        switch state {
        case .ground, .initialized, .initializedMessages:
            DLog("Unexpected function call in state \(state)")
            return
        case .querySent(let messages):
            var amended = messages
            amended.append(message)
            if let impl = functions.first(where: { $0.decl.name == functionCall.name }) {
                DLog("Invoke function with arguments \(functionCall.arguments)")
                impl.invoke(json: functionCall.arguments.data(using: .utf8)!, llm: self) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        DLog("Response to function call with arguments \(functionCall.arguments): \(response)")
                        amended.append(Message(role: "function",
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
                        handle(event: .error(reason: error.localizedDescription),
                               legacy: false)
                        return
                    }
                }
                return
            }
            amended.append(Message(role: "user",
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

struct AIConversation {
    public struct AIError: Error, CustomStringConvertible {
        public internal(set) var message: String

        public init(_ message: String) {
            self.message = message
        }

        public var description: String {
            message
        }

        var localizedDescription: String {
            message
        }
    }

    private class Delegate: AITermControllerDelegate {
        private(set) var busy = false
        var completion: ((Result<String, Error>) -> ())?
        var registrationNeeded: ((@escaping (AITermController.Registration) -> ()) -> ())?

        func aitermControllerWillSendRequest(_ sender: AITermController) {
            busy = true
        }
        
        func aitermController(_ sender: AITermController, offerChoices: [String]) {
            busy = false
            if let choice = offerChoices.first {
                completion?(Result.success(choice))
            } else {
                completion?(Result.failure(AIError("Empty response from OpenAI")))
            }
        }
        
        func aitermController(_ sender: AITermController, didFailWithErrorMessage message: String) {
            busy = false
            completion?(Result.failure(AIError(message)))
        }
        
        func aitermControllerRequestRegistration(_ sender: AITermController,
                                                 completion: @escaping (AITermController.Registration) -> ()) {
            registrationNeeded?(completion)
        }
    }

    var messages: [AITermController.Message]
    private var controller: AITermController
    private var delegate = Delegate()
    private weak var window: NSWindow?
    var maxTokens: Int {
        return Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit) - iTermAdvancedSettingsModel.aiResponseMaxTokens())
    }
    var busy: Bool { delegate.busy }

    init(window: NSWindow,
         messages: [AITermController.Message] = []) {
        self.window = window
        self.messages = messages
        controller = AITermController(registration: AITermControllerRegistrationHelper.instance.registration)
        controller.delegate = delegate
        let maxTokens = self.maxTokens
        controller.truncate = { truncate(messages: $0, maxTokens: maxTokens) }
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration, 
                            arguments: T.Type,
                            implementation: @escaping Function<T>.Impl) {
        controller.define(function: decl, arguments: arguments, implementation: implementation)
    }

    mutating func add(text: String, role: String = "user") {
        messages.append(AITermController.Message(role: role, content: text))
    }

    mutating func complete(_ completion: @escaping (Result<AIConversation, Error>) -> ()) {
        precondition(!messages.isEmpty)
        precondition(!delegate.busy)
        let prior = messages
        guard let window = self.window else {
            completion(.failure(AIError("No window")))
            return
        }
        let controller = self.controller
        let messages = self.truncatedMessages
        delegate.registrationNeeded = { regCompletion in
            AITermControllerRegistrationHelper.instance.requestRegistration(in: window) { registration in
                if let registration {
                    regCompletion(registration)
                    controller.request(messages: messages)
                }
            }
        }

        delegate.completion = { result in
            switch result {
            case .success(let text):
                let message = AITermController.Message(role: "assistant", content: text)
                let amended = AIConversation(window: window, messages: prior + [message])
                amended.controller.define(functions: controller.functions)
                completion(.success(amended))
            break
            case .failure(let error):
                completion(.failure(error))
            break
            }
        }
        controller.request(messages: truncatedMessages)
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
        if messages[i].role == "system" {
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
