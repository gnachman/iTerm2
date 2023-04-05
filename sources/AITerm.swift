protocol AITermControllerDelegate: AnyObject {
    func aitermControllerWillSendRequest(_ sender: AITermController)
    func aitermController(_ sender: AITermController, offerChoices: [String])
    func aitermController(_ sender: AITermController, didFailWithErrorMessage: String)
    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: (AITermController.Registration) -> ())
}

@objc
class AITermControllerObjC: NSObject, AITermControllerDelegate, iTermObject {
    private static let apiKeyUserDefaultsKey = "NoSyncOpenAIAPIKey"
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

        let maybeApiKey = UserDefaults.standard.string(forKey: Self.apiKeyUserDefaultsKey)
        let registration = AITermController.Registration(apiKey: maybeApiKey)
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
                                             completion: (AITermController.Registration) -> ()) {
        let windowController = AITermRegistrationWindowController.create()
        ownerWindow.beginSheet(windowController.window!) { [weak self] response in
            windowController.window?.orderOut(nil)
            if response == .OK, let key = windowController.apiKey {
                UserDefaults.standard.set(key, forKey: Self.apiKeyUserDefaultsKey)
            }
            if response == .OK, let controller = self?.controller, let query = self?.query {
                controller.registration = AITermController.Registration(apiKey: windowController.apiKey)
                controller.request(query: query)
            } else {
                self?.handler(nil, nil)
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

class AITermController {
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
            case .querySent(query: let query): return "querySent(\(query))"
            }
        }
        case ground
        case initialized(query: String)
        case querySent(query: String)
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
        handle(event: .begin)
    }

    private func handle(event: Event) {
        DLog("handle(\(event)) in state \(state)")
        switch state {
        case .ground:
            DLog("Ignore \(event) in ground state.")
            break

        case .initialized(query: let query):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration()
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

        case .querySent(_):
            switch event {
            case .begin:
                fatalError()
            case .apiResponse(data: let data, response: _, error: let error):
                DLog("Unexpected event \(event) in \(state)")
                if let error {
                    handle(event: .error(reason: "HTTP error from server: \(error)"))
                    return
                }
                guard let data else {
                    handle(event: .error(reason: "Neither error nor data. This shouldn't happen."))
                    return
                }
                parseResponse(data: data)
            case .error(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
                delegate?.aitermController(self, didFailWithErrorMessage: "Error from OpenAI: \(reason)")
            }
        }
    }

    private func requestRegistration() {
        state = .ground
        delegate?.aitermControllerRequestRegistration(self) { [weak self] registration in
            self?.registration = registration
            self?.handle(event: .begin)
        }
    }

    private func url(forModel model: String) -> URL? {
        if model.hasPrefix("gpt-") {
            return URL(string: "https://api.openai.com/v1/chat/completions")
        }
        return URL(string: "https://api.openai.com/v1/completions")
    }

    private func makeAPICall(query: String, registration: Registration) {
        let model = iTermAdvancedSettingsModel.aiModel()!
        guard let url = url(forModel: model) else {
            handle(event: .error(reason: "Invalid URL"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let headers = [("Content-Type", "application/json"),
                       ("Authorization", "Bearer " + registration.apiKey)]
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        struct Body: Codable {
            var model: String  // "text-davinci-003"
            var prompt: String
            var max_tokens: Int
            var temperature = 0
        }

        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let body = Body(model: model,
                        prompt: query,
                        max_tokens: max(Int(iTermAdvancedSettingsModel.aiMaxTokens()),
                                        query.count / 2))
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        request.httpBody = bodyData

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handle(event: .apiResponse(data: data, response: response, error: error))
            }
        }
        state = .querySent(query: query)
        task.resume()
    }

    struct Response: Codable {
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

    private func parseResponse(data: Data) {
        let decoder = JSONDecoder()
        do {
            let response = try decoder.decode(Response.self, from: data)
            state = .ground
            let choices = response.choices.map {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            delegate?.aitermController(self, offerChoices: choices)
        } catch {
            handle(event: .error(reason: "Failed to decode API response: \(error). Data is: \(data.stringOrHex)"))
        }
    }
}

@objc
class AITermRegistrationWindowController: NSWindowController {
    @IBOutlet var message: NSTextView!
    @IBOutlet var okButton: NSButton!
    @IBOutlet var textField: NSTextField!
    private(set) var apiKey: String?

    static func create() -> AITermRegistrationWindowController {
        return AITermRegistrationWindowController(windowNibName: NSNib.Name("AITerm"))
    }

    override func awakeFromNib() {
        var temp = message.string
        let urls = ["https://openai.com/join/",
                    "https://beta.openai.com/account/api-keys",
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

