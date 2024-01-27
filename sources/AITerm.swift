protocol AITermControllerDelegate: AnyObject {
    func aitermControllerWillSendRequest(_ sender: AITermController)
    func aitermController(_ sender: AITermController, offerChoices: [String])
    func aitermController(_ sender: AITermController, didFailWithErrorMessage: String)
    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ())
}

fileprivate func isLegacy(model: String) -> Bool {
    return !model.hasPrefix("gpt-")
}

class AITermControllerRegistrationHelper {
    static var instance = AITermControllerRegistrationHelper()
    private static let apiKeyUserDefaultsKey = "NoSyncOpenAIAPIKey"

    var registration: AITermController.Registration? {
        let maybeApiKey = UserDefaults.standard.string(forKey: Self.apiKeyUserDefaultsKey)
        return AITermController.Registration(apiKey: maybeApiKey)
    }

    func setKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: Self.apiKeyUserDefaultsKey)
    }

    func requestRegistration(in window: NSWindow, completion: @escaping (AITermController.Registration?) -> ()) {
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
    private let controller: AITermController
    private let handler: ([String]?, String?) -> ()
    private let ownerWindow: NSWindow
    private let query: String
    private let pleaseWait: PleaseWaitWindow

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
        self.handler = { choices, error in
            if !pleaseWait.canceled {
                handler(choices, error)
            }
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
                    self.controller.request(query: prompt)
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
            completion(.failure(error))
        }
    }
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
            case .apiResponse(data: let data, response: _, error: let error):
                if let error {
                    return "apiResponse(error=\(error))"
                }
                if let data {
                    return "apiResponse(data=\(data.stringOrHex))"
                }
                return "apiResponse(neither data nor error)"
            }
        }
        case begin
        case error(reason: String)
        case apiResponse(data: Data?, response: URLResponse?, error: Error?)
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
            case .apiResponse:
                DLog("Unexpected event \(event) in \(state)")
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
            case .error(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
            case .apiResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            }

        case .querySent:
            switch event {
            case .begin:
                fatalError()
            case .apiResponse(data: let data, response: _, error: let error):
                DLog("Unexpected event \(event) in \(state)")
                if let error {
                    handle(event: .error(reason: "HTTP error from server: \(error)"), legacy: false)
                    return
                }
                guard let data else {
                    handle(event: .error(reason: "Neither error nor data. This shouldn't happen."), legacy: false)
                    return
                }
                parseResponse(data: data, legacy: legacy)
            case .error(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
                delegate?.aitermController(self, didFailWithErrorMessage: "Error from OpenAI: \(reason)")
            }
        }
    }

    private func requestRegistration(continuation: State) {
        state = .ground
        delegate?.aitermControllerRequestRegistration(self) { [weak self] registration in
            self?.registration = registration
            self?.state = continuation
            self?.handle(event: .begin, legacy: false)
        }
    }

    private func url(forModel model: String) -> URL? {
        if !isLegacy(model: model) {
            return URL(string: "https://api.openai.com/v1/chat/completions")
        }
        return URL(string: iTermAdvancedSettingsModel.aitermURL())
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
        print("REQUEST:\n\(body)")
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }

    private func requestBody(model: String, messages: [Message]) -> Data {
        if isLegacy(model: model) {
            return legacyRequestBody(model: model, messages: messages)
        }
        return modernRequestBody(model: model, messages: messages)
    }

    private func makeAPICall(query: String, registration: Registration) {
        makeAPICall(messages: [Message(role: "user", content: query)], registration: registration)
    }

    private func makeAPICall(messages: [Message], registration: Registration) {
        let model = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-3.5-turbo"
        guard let url = url(forModel: model) else {
            handle(event: .error(reason: "Invalid URL"), legacy: false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let headers = [("Content-Type", "application/json"),
                       ("Authorization", "Bearer " + registration.apiKey)]
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let bodyData = requestBody(model: model, messages: messages)
        request.httpBody = bodyData

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handle(event: .apiResponse(data: data, response: response, error: error),
                             legacy: isLegacy(model: model))
            }
        }
        state = .querySent(messages: messages)
        task.resume()
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
            var index: Int
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
                handle(event: .error(reason: errorResponse.error.message),
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
        print("RESPONSE:\n\(response)")
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
        print(link)
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
