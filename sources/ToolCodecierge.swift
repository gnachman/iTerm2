//
//  ToolCodecierge.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/5/23.
//

import AppKit

fileprivate protocol ToolCodeciergeSessionDelegate: AnyObject {
    func sessionBusyDidChange(session: ToolCodecierge.Session, busy: Bool)
    func session(session: ToolCodecierge.Session, didProduceText text: String)
    func session(session: ToolCodecierge.Session, didProduceAdditionalText text: String)
    func sessionDidReceiveCommand(session: ToolCodecierge.Session, command: String)
    func sessionEnabled(_ session: ToolCodecierge.Session) -> Bool
    func sessionAbort(_ session: ToolCodecierge.Session)
    var sessionWindow: NSWindow? { get }
}

struct TerminalCommand: Codable {
    var username: String?
    var hostname: String?
    var directory: String?
    var command: String
    var output: String
    var exitCode: Int32
    var url: URL
}

@objc(iTermToolCodecierge)
class ToolCodecierge: NSView, ToolbeltTool {
    private var onboardingView: CodeciergeOnboardingView!
    private var goalView: CodeciergeGoalView!
    private var suggestionView: CodeciergeSuggestionView!
    override var isFlipped: Bool { true }
    private var notificationObserver: (any NSObjectProtocol)?
    typealias Command = TerminalCommand

    private class SessionRegistry {
        static var instance = SessionRegistry()
        var sessions = [String: Session]()
        private var observer: (any NSObjectProtocol)?
        init() {
            observer = NotificationCenter.default.addObserver(forName: NSNotification.Name("PTYSessionDidDealloc"),
                                                   object: nil,
                                                              queue: nil) { [weak self] notification in
                self?.sessions.removeValue(forKey: notification.object as! String)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    static var supportedProfileTypes: ProfileType { .terminal }

    fileprivate enum State {
        case uninitialized
        case onboarding
        case goalSetting
        case running
    }

    fileprivate struct History {
        var commands: [Command] = []
    }

    fileprivate class Session {
        var guid: String
        var state: State = .uninitialized
        var history = History()
        var ghostRiding = false
        var pendingCompletion: ((Result<String, Error>) throws -> ())?

        var goal: String? {
            didSet {
                history = History()
                if let window = iTermController.sharedInstance().windowForSession(withGUID: guid)?.window(), let goal {
                    var initialMessages = [AITermController.Message]()
                    let format =
                    if ghostRiding {
                        iTermAdvancedSettingsModel.codeciergeGhostRidingPrompt()!
                    } else {
                        iTermAdvancedSettingsModel.codeciergeRegularPrompt()!
                    }
                    let content = format
                        .replacingOccurrences(of: "$GOAL", with: goal)
                        .replacingOccurrences(of: "$CONTEXT", with: contextualInfo)
                    initialMessages.append(AITermController.Message(role: .system, content: content))
                    conversation = AIConversation(registrationProvider: window,
                                                  messages: initialMessages)
                    if ghostRiding {
                        do {
                            // This struct defines inputs to the function call. The LLM will populate
                            // all the fields of the struct. Reflection is used to make this possible.
                            struct ExecuteCommand: Codable {
                                var command: String = ""
                            }
                            let schema = JSONSchema(for: ExecuteCommand(),
                                                    descriptions: ["command": "The command to run"])
                            let decl = ChatGPTFunctionDeclaration(
                                name: "execute",
                                description: "Execute a command at the shell. The output will be provided in a subsequent message from me.",
                                parameters: schema)
                            conversation?.define(
                                function: decl,
                                arguments: ExecuteCommand.self,
                                implementation: { [weak self] _, command, completion in
                                    guard let self,
                                          let session = iTermController.sharedInstance().session(withGUID: guid) else {
                                        try? completion(.failure(AIError("The session no longer exists")))
                                        return
                                    }
                                    session.writeTask(command.command.trimmingTrailingNewline + "\n")
                                    delegate?.session(session: self, didProduceAdditionalText: "Running `\(command.command.escapedForMarkdownCode)`\n")
                                    pendingCompletion = completion
                                })
                        }

                        do {
                            struct WriteCommand: Codable {
                                var filename: String = ""
                                var contents: String = ""
                            }
                            let schema = JSONSchema(for: WriteCommand(),
                                                    descriptions: ["filename": "The filename to write to. It may be relative or absolute.",
                                                                   "contents": "The contents of the file to be written."])
                            let decl = ChatGPTFunctionDeclaration(
                                name: "write",
                                description: "Write a file, replacing an existing file with the same name.",
                                parameters: schema)
                            conversation?.define(
                                function: decl,
                                arguments: WriteCommand.self,
                                implementation: { [weak self] _, command, completion in
                                    guard let self,
                                          let session = iTermController.sharedInstance().session(withGUID: guid) else {
                                        try? completion(.failure(AIError("The session no longer exists")))
                                        return
                                    }
                                    session.sendTextSlowly("cat > \(command.filename)\n")
                                    session.sendTextSlowly(command.contents)
                                    if !command.contents.hasSuffix("\n") {
                                        session.sendTextSlowly("\n")
                                    }
                                    session.sendTextSlowly("\u{0004}")
                                    delegate?.session(session: self, didProduceAdditionalText: "Writing to \(command.filename)\n")
                                    pendingCompletion = { result in
                                        switch result {
                                        case .success:
                                            try? completion(.success("Done"))
                                        case .failure(let error):
                                            try? completion(.failure(error))
                                        }
                                    }
                                })
                        }
                    }
                }
            }
        }
        private var contextualInfo: String {
            guard let session = iTermController.sharedInstance().session(withGUID: guid) else {
                return ""
            }
            let scope = session.genericScope
            let shell = scope?.value(forVariableName: "shell")
            let uname = scope?.value(forVariableName: "uname")
            if let shell, let uname {
                return "The shell is \(shell) and the system's `uname` is \(uname). "
            }
            if let shell {
                return "The shell is \(shell). "
            }
            if let uname {
                return "The system's `uname` is \(uname). "
            }
            return ""
        }
        var suggestion: String?
        fileprivate weak var delegate: ToolCodeciergeSessionDelegate?
        var running = false
        private var conversation: AIConversation?
        var busy: Bool { conversation?.busy ?? false }
        private var observer: (any NSObjectProtocol)?
        private var commandCount = 0

        init(_ guid: String) {
            self.guid = guid
            observer = NotificationCenter.default.addObserver(forName: Notification.Name.PTYCommandDidExit,
                                                   object: guid,
                                                   queue: nil) { [weak self] notif in
                guard let self, let delegate, delegate.sessionEnabled(self) else { return }
                guard let userInfo = notif.userInfo,
                      let command = userInfo[PTYCommandDidExitUserInfoKeyCommand] as? String else {
                    return
                }

                let exitCode = (userInfo[PTYCommandDidExitUserInfoKeyExitCode] as? Int32) ?? 0
                let directory = userInfo[PTYCommandDidExitUserInfoKeyDirectory] as? String
                let remoteHost = userInfo[PTYCommandDidExitUserInfoKeyRemoteHost] as? VT100RemoteHostReading
                let startLine = userInfo[PTYCommandDidExitUserInfoKeyStartLine] as! Int32
                let lineCount = userInfo[PTYCommandDidExitUserInfoKeyLineCount] as! Int32
                let snapshot = userInfo[PTYCommandDidExitUserInfoKeySnapshot] as! TerminalContentSnapshot
                let url = userInfo[PTYCommandDidExitUserInfoKeyURL] as! URL
                let extractor = iTermTextExtractor(dataSource: snapshot)
                let content = extractor.content(
                    in: VT100GridWindowedRange(
                        coordRange: VT100GridCoordRange(
                            start: VT100GridCoord(x: 0, y: startLine),
                            end: VT100GridCoord(x: 0, y: startLine + lineCount)),
                        columnWindow: VT100GridRange(location: 0, length: 0)),
                    attributeProvider: nil,
                    nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                    pad: false,
                    includeLastNewline: false,
                    trimTrailingWhitespace: true,
                    cappedAtSize: -1,
                    truncateTail: false,
                    continuationChars: nil,
                    coords: nil) as! String
                updateHistory(command: command,
                              exitCode: exitCode,
                              directory: directory,
                              output: content,
                              remoteHost: remoteHost,
                              url: url)
                delegate.sessionDidReceiveCommand(session: self, command: command)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func updateHistory(command: String,
                                   exitCode: Int32,
                                   directory: String?,
                                   output: String,
                                   remoteHost: VT100RemoteHostReading?,
                                   url: URL) {
            let command = Command(username: remoteHost?.username,
                                  hostname: remoteHost?.hostname,
                                  directory: directory,
                                  command: command,
                                  output: output,
                                  exitCode: exitCode,
                                  url: url)
            updateHistory(command: command)
            if running {
                commandCount += 1
                if commandCount >= iTermAdvancedSettingsModel.codeciergeCommandWarningCount() {
                    let selection =
                    iTermWarning.show(withTitle: "Your codecierge session has been going on for a long time. Are you still using it? If not, stop it to save money and privacy.",
                                      actions: ["Keep Going", "Stop Codecierge"],
                                      accessory: nil,
                                      identifier: "CodeciergeCommandWarning",
                                      silenceable: .kiTermWarningTypePermanentlySilenceable,
                                      heading: "Codecierge Usage Warning",
                                      window: delegate?.sessionWindow)
                    switch selection {
                    case .kiTermWarningSelection0:
                        commandCount = 0
                    case .kiTermWarningSelection1:
                        delegate?.sessionAbort(self)
                    default:
                        break
                    }
                }
            }
        }

        func updateHistory(command newCommand: Command?) {
            if let newCommand {
                history.commands.append(newCommand)
                if let pendingCompletion {
                    self.pendingCompletion = nil
                    try? pendingCompletion(.success(message(forCommand: newCommand)))
                    return
                }
            }
            if running, conversation != nil {
                let text = if let newCommand {
                    message(forCommand: newCommand)
                } else {
                    "Tell me how to get started."
                }
                enqueueCompletion(text) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let updated):
                        delegate?.session(session: self, didProduceText: updated.messages.last!.content ?? "")
                    case .failure(let error):
                        DLog("\(error)")
                        delegate?.session(session: self, didProduceText: "There was an error: \(error.localizedDescription)")
                    }
                }
            }
        }

        func sendTextMessage(_ text: String) {
            enqueueCompletion(text) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let updated):
                    self.conversation = updated
                    delegate?.session(session: self, didProduceAdditionalText: updated.messages.last!.content ?? "")
                case .failure(let error):
                    DLog("\(error)")
                    delegate?.session(session: self, didProduceAdditionalText: "There was an error: \(error.localizedDescription)")
                }
            }
        }

        private var queue = [(String, (Result<AIConversation, Error>) -> ())]()

        private func enqueueCompletion(_ text: String, _ closure: @escaping (Result<AIConversation, Error>) -> ()) {
            queue.append((text, closure))
            dequeueIfPossible()
        }

        private func dequeueIfPossible() {
            if conversation?.busy ?? false {
                return
            }
            guard !queue.isEmpty else { return }
            let (text, closure) = queue.removeFirst()
            conversation?.add(text: text)
            delegate?.sessionBusyDidChange(session: self, busy: true)
            conversation?.complete { [weak self] result in
                guard let self else { return }
                delegate?.sessionBusyDidChange(session: self, busy: false)
                switch result {
                case .success(let updated):
                    self.conversation = updated
                case .failure(let error):
                    DLog("\(error)")
                }
                closure(result)
                dequeueIfPossible()
            }
        }

        private func prompt(command: Command) -> String {
            var result = ""
            if let hostname = command.hostname {
                if let username = command.username {
                    result.append("\(username)@\(hostname)")
                }
            }
            if let directory = command.directory {
                if result.isEmpty {
                    result = directory
                } else {
                    result.append(":\(directory)")
                }
            }
            return result + "%"
        }

        private func message(forCommand command: Command) -> String {
            var lines = [String]()
            lines.append("\(prompt(command: command)) \(command.command)")
            lines.append(command.output)
            lines.append("-- end output --")
            if command.exitCode != 0 {
                lines.append("The command failed with exit code \(command.exitCode).")
            }
            if ghostRiding {
                lines.append("Briefly explain the output, especially if anything went wrong, and perform the next step.")
            } else {
                lines.append("Briefly explain the output, especially if anything went wrong, and suggest the next step. If there is another command to run, please state it.")
            }
            return lines.joined(separator: "\n")
        }
    }

    private var _state = State.uninitialized

    private var state: State {
        get { _state }
        set {
            switch _state {
            case .uninitialized:
                break
            case .onboarding:
                onboardingView.isHidden = true
            case .goalSetting:
                goalView.isHidden = true
            case .running:
                suggestionView.isHidden = true
            }

            _state = newValue
            currentSession()?.state = newValue

            switch _state {
            case .uninitialized:
                break
            case .onboarding:
                onboardingView.isHidden = false
                currentSession()?.running = false
            case .goalSetting:
                goalView.isHidden = false
                goalView.goal = currentSession()?.goal ?? ""
                currentSession()?.running = false
            case .running:
                currentSession()?.running = true
                suggestionView.isHidden = false
                let session = currentSession()
                suggestionView.goal = session?.goal ?? ""
                suggestionView.suggestion = session?.suggestion ?? ""
            }
        }
    }

    private var initialState: State {
        if AITermControllerRegistrationHelper.instance.registration == nil {
            return .onboarding
        } else {
            return .goalSetting
        }
    }

    static func isDynamic() -> Bool { false }

    required init!(frame: NSRect, url: URL!, identifier: String!) {
        it_fatalError()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)

        onboardingView = CodeciergeOnboardingView(startCallback: { [weak self] in
            guard let self, let window else {
                return
            }
            if AITermControllerRegistrationHelper.instance.registration != nil {
                state = .goalSetting
                return
            }
            AITermControllerRegistrationHelper.instance.requestRegistration(in: window) { [weak self] registration in
                guard let self else {
                    return
                }
                if registration != nil {
                    state = .goalSetting
                }
            }
        })
        addSubview(onboardingView)
        onboardingView.isHidden = true

        goalView = CodeciergeGoalView(startCallback: { [weak self] goal, autoRunCommands in
            guard let self, let session = currentSession() else {
                return
            }
            session.ghostRiding = autoRunCommands
            session.goal = goal
            session.suggestion = "Thinking…"
            self.state = .running
            session.updateHistory(command: nil)
        })
        goalView.goalDidChange = { [weak self] goal in
            self?.currentSession()?.goal = goal
        }
        addSubview(goalView)
        goalView.isHidden = true

        suggestionView = CodeciergeSuggestionView(goal: "",
                                                  suggestion: "",
                                                  endCallback: { [weak self] in
            self?.state = .goalSetting
        },
                                                  replyCallback: { [weak self] reply in
            self?.sendReply(reply)
        },
                                                  didCopyCallback: { [weak self] in
            self?.didCopy()
        })
        addSubview(suggestionView)
        suggestionView.isHidden = true

        layoutSubviews()
        state = initialState

        notificationObserver = NotificationCenter.default.addObserver(forName: iTermSecureUserDefaults.didChange,
                                                                      object: nil,
                                                                      queue: nil) { [weak self] _ in
            self?.updateAIAllowed()
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    private func updateAIAllowed() {
        if !iTermAITermGatekeeper.allowed {
            state = .onboarding
        }
    }

    private func didCopy() {
        toolWrapper()?.delegate?.delegate?.toolbeltMakeCurrentSessionFirstResponder()
    }

    @objc func relayout() {
        layoutSubviews()
    }

    private func layoutSubviews() {
        if let superview {
            frame = superview.bounds
        }
        do {
            let height = onboardingView.fittingSize.height
            onboardingView.frame = NSRect(x: 2,
                                          y: (bounds.height - height) / 2,
                                          width: bounds.width - 4,
                                          height: height)
        }
        do {
            let height = bounds.height
            goalView.frame = NSRect(x: 2,
                                    y: (bounds.height - height) / 2,
                                    width: bounds.width - 4,
                                    height: height)
        }
        do {
            suggestionView.frame = bounds.safeInsetBy(dx: 2, dy: 0)
        }
    }

    func minimumHeight() -> CGFloat {
        return 130.0
    }

    private func currentSession() -> Session? {
        guard let guid = toolWrapper()?.delegate?.delegate?.toolbeltCurrentSessionGUID() else {
            return nil
        }
        if let session = SessionRegistry.instance.sessions[guid] {
            session.delegate = self
            return session
        }
        let session = Session(guid)
        session.ghostRiding = true
        session.delegate = self
        session.state = initialState
        SessionRegistry.instance.sessions[guid] = session
        return session
    }

    @objc
    func currentSessionDidChange() {
        if let session = currentSession() {
            state = session.state
            suggestionView.busy = session.busy
        } else {
            suggestionView.busy = false
        }
    }

    private func setSuggestion(guid: String, suggestion: String) {
        SessionRegistry.instance.sessions[guid]?.suggestion = suggestion
        if let session = currentSession(), session.guid == guid {
            switch state {
            case .running:
                suggestionView.suggestion = suggestion
            default:
                break
            }
        }
    }

    private func appendToSuggestion(guid: String, suggestion: String) {
        if let existing = SessionRegistry.instance.sessions[guid]?.suggestion {
            setSuggestion(guid: guid, suggestion: existing + suggestion)
        } else {
            setSuggestion(guid: guid, suggestion: suggestion)
        }
        if let suggestionView = self.suggestionView {
            DispatchQueue.main.async {
                suggestionView.scrollToEnd()
            }
        }
    }

    private func sendReply(_ text: String) {
        switch state {
        case .uninitialized, .onboarding, .goalSetting:
            break
        case .running:
            if let session = currentSession() {
                appendToSuggestion(guid: session.guid, suggestion: "\n\n### 👤 You\n\(text)\n")
            }
            currentSession()?.sendTextMessage(text)
        }
    }
}

extension ToolCodecierge: ToolCodeciergeSessionDelegate {
    fileprivate func session(session: Session, didProduceText text: String) {
        setSuggestion(guid: session.guid, suggestion: "### 🔮 Assistant\n\(text)")
    }

    fileprivate func session(session: Session, didProduceAdditionalText text: String) {
        appendToSuggestion(guid: session.guid, suggestion: "\n\n### 🔮 Assistant\n\(text)")
    }

    fileprivate func sessionBusyDidChange(session: Session, busy: Bool) {
        if session.guid == currentSession()?.guid {
            suggestionView.busy = busy
        }
    }

    fileprivate func sessionDidReceiveCommand(session: Session, command: String) {
        let sanitizedCommand = command.escapedForMarkdownCode.truncatedWithTrailingEllipsis(to: 80)
        appendToSuggestion(guid: session.guid, suggestion: "\n\n### 💻 Terminal\n`\(sanitizedCommand)`")
        appendToSuggestion(guid: session.guid, suggestion: "\n\n### 🔮 Assistant\nThinking…")
    }

    fileprivate func sessionEnabled(_ session: ToolCodecierge.Session) -> Bool {
        return !isHiddenOrHasHiddenAncestor
    }

    fileprivate var sessionWindow: NSWindow? {
        return window
    }

    fileprivate func sessionAbort(_ session: Session) {
        state = .goalSetting
    }
}

extension String {
    var escapedForMarkdownCode: String {
        return replacingOccurrences(of: "`", with: "\\`")
    }
}

class CodeciergeOnboardingView: NSView {
    private let startCallback: () -> ()
    private let label: NSTextField
    private let startButton: NSButton
    private let revealButton: NSButton
    private let originalLabelText = "Codecierge uses AI to help you in your terminal."
    private var notificationObserver: (any NSObjectProtocol)?

    init(startCallback: @escaping () -> ()) {
        self.startCallback = startCallback
        label = NSTextField(labelWithString: originalLabelText)
        label.usesSingleLineMode = false
        label.lineBreakMode = .byWordWrapping
        label.alignment = .center
        startButton = NSButton(title: "Get Started", target: nil, action: nil)

        revealButton = NSButton(title: "Reveal Setting", target: nil, action: nil)
        revealButton.isHidden = true

        super.init(frame: .zero)

        addSubview(label)
        addSubview(startButton)
        addSubview(revealButton)

        startButton.target = self
        startButton.action = #selector(startButtonPressed)

        revealButton.target = self
        revealButton.action = #selector(revealButtonPressed)

        layoutSubviews()

        updateEnabled()
        notificationObserver = NotificationCenter.default.addObserver(forName: iTermSecureUserDefaults.didChange,
                                                                      object: nil,
                                                                      queue: nil) { [weak self] _ in
            self?.updateEnabled()
        }
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    private func updateEnabled() {
        if !iTermAdvancedSettingsModel.generativeAIAllowed() {
            label.stringValue = "Generative AI has been disabled by the system administrator."
            startButton.isEnabled = false
            startButton.isHidden = false
            revealButton.isHidden = true
        } else if !SecureUserDefaults.instance.enableAI.value {
            label.stringValue = "You must enable AI features to use Codecierge."
            startButton.isEnabled = false
            startButton.isHidden = true
            revealButton.isHidden = false
        } else {
            label.stringValue = originalLabelText
            startButton.isEnabled = true
            startButton.isHidden = false
            revealButton.isHidden = true
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }
    private func layoutSubviews() {
        let height = label.sizeThatFits(NSSize(width: bounds.width - 4, height: .infinity)).height
        label.frame = NSRect(x: 2, y: 0, width: bounds.width - 4, height: height)

        startButton.sizeToFit()
        startButton.frame = NSRect(x: (bounds.width - startButton.frame.width) / 2.0,
                                   y: label.frame.maxY + 8,
                                   width: startButton.bounds.width,
                                   height: startButton.bounds.height)

        revealButton.sizeToFit()
        revealButton.frame = NSRect(x: (bounds.width - revealButton.frame.width) / 2.0,
                                    y: label.frame.maxY + 8,
                                    width: revealButton.bounds.width,
                                    height: revealButton.bounds.height)
    }

    override var fittingSize: NSSize {
        layoutSubviews()
        return NSSize(width: label.bounds.width + 4, height: startButton.frame.maxY)
    }

    override var isFlipped: Bool { true }
    @objc private func startButtonPressed() {
        startCallback()
    }

    @objc private func revealButtonPressed() {
        PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyEnableAI)
    }
}

class CodeciergeGoalView: NSView, NSTextViewDelegate, NSControlTextEditingDelegate {
    private let startCallback: (String, Bool) -> ()
    private let label: NSTextField
    private let scrollView: NSScrollView
    private let textView: ShiftEnterTextView
    private let startButton: NSButton
    private let autoButton: NSButton
    var goalDidChange: ((String) -> ())?

    var goal: String {
        get { textView.string }
        set {
            textView.string = newValue
            updateEnabled()
        }
    }
    override var isFlipped: Bool { true }
    private let userDefaultsObserver: iTermUserDefaultsObserver

    init(startCallback: @escaping (String, Bool) -> ()) {
        self.startCallback = startCallback
        label = NSTextField(labelWithString: "What are you trying to do? I'll suggest commands and explain their output.")
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false

        textView = ShiftEnterTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        textView.it_placeholderString = "I want to…"
        textView.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.drawsBackground = false
        textView.textContainer?.widthTracksTextView = true
        textView.isRichText = false
        textView.importsGraphics = false

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let hasFunctionCalling = AITermController.provider?.model.features.contains(.functionCalling) ?? false
        autoButton = NSButton()
        autoButton.setButtonType(.switch)
        autoButton.title = "Run commands automatically"
        autoButton.state = .off
        autoButton.isEnabled = hasFunctionCalling
        userDefaultsObserver = iTermUserDefaultsObserver()
        startButton = NSButton(title: "Start", target: nil, action: nil)
        startButton.isEnabled = false

        super.init(frame: .zero)

        addSubview(label)
        addSubview(scrollView)
        addSubview(autoButton)
        addSubview(startButton)

        textView.delegate = self

        autoButton.target = self
        autoButton.action = #selector(autoToggled(_:))

        startButton.target = self
        startButton.action = #selector(startButtonPressed)

        textView.shiftEnterPressed = { [weak self] in
            self?.startButtonPressed()
        }
        layoutSubviews()

        userDefaultsObserver.observeKey(kPreferenceKeyAITermURL) { [weak self] in
            self?.autoButton.isEnabled = hasFunctionCalling
        }
        userDefaultsObserver.observeKey(kPreferenceKeyAIModel) { [weak self] in
            self?.autoButton.isEnabled = hasFunctionCalling
        }
        userDefaultsObserver.observeKey(kPreferenceKeyAITermAPI) { [weak self] in
            self?.autoButton.isEnabled = hasFunctionCalling
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    @objc func autoToggled(_ sender: Any) {
        if autoButton.state == .on {
            let selection = iTermWarning.show(withTitle: "This lets an AI completely control your computer. It could delete your files, do something stupid or dangerous, or lead to the downfall of humanity. Proceed with caution.",
                              actions: [ "OK", "Cancel" ],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Danger!",
                              window: window)
            if selection == .kiTermWarningSelection1 {
                autoButton.state = .off
            }
        }
    }

    private func layoutTextview() {
        let containerWidth = scrollView.documentVisibleRect.width
        textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let textBounds = textView.layoutManager?.usedRect(for: textView.textContainer!)
        let desiredHeight = textBounds?.height ?? 0

        textView.frame = CGRect(x: 0, y: 0, width: containerWidth, height: max(desiredHeight, scrollView.frame.size.height))
    }

    private func layoutSubviews() {
        let height = label.sizeThatFits(NSSize(width: bounds.width - 4, height: .infinity)).height
        label.frame = NSRect(x: 2, y: 0, width: bounds.width - 4, height: height)

        scrollView.frame = NSRect(x: 2, y: label.frame.maxY + 4, width: bounds.width - 4, height: bounds.height - 85)
        autoButton.sizeToFit()
        autoButton.frame = NSRect(x: 0, y: scrollView.frame.maxY + 4, width: autoButton.bounds.width, height: autoButton.bounds.height)
        startButton.sizeToFit()
        startButton.frame = NSRect(x: (bounds.width - startButton.bounds.width) / 2,
                                   y: autoButton.frame.maxY + 4,
                                   width: startButton.bounds.width,
                                   height: startButton.bounds.height)

        layoutTextview()
    }

    override var fittingSize: NSSize {
        layoutSubviews()
        return NSSize(width: label.bounds.width + 4, height: startButton.frame.maxY)
    }

    private let codeciergeWarningAcknowledgedUserDefaultsKey = "NoSyncCodeciergeWarningAcknowledged"

    @objc private func startButtonPressed() {
        if !UserDefaults.standard.bool(forKey: codeciergeWarningAcknowledgedUserDefaultsKey) {
            let option = iTermWarning.show(withTitle: "Everything that happens in your terminal while Codecierge is running will be sent to your AI provider. Don't send them confidential information!",
                              actions: [ "OK", "Cancel" ],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Privacy Warning",
                              window: window)
            if option == .kiTermWarningSelection0 {
                UserDefaults.standard.setValue(true, forKey: codeciergeWarningAcknowledgedUserDefaultsKey)
            } else {
                return
            }
        }
        startCallback(textView.string, autoButton.state == .on)
    }

    // TODO: Shift-enter to start
    @objc func textDidChange(_ notification: Notification) {
        updateEnabled()
        goalDidChange?(textView.string)
    }

    private func updateEnabled() {
        startButton.isEnabled = !textView.string.isEmpty
    }
}

class CodeciergeSuggestionView: NSView, NSTextFieldDelegate {
    private let endCallback: () -> ()
    private let replyCallback: (String) -> ()
    private let didCopyCallback: () -> ()
    private let activityIndicator = NSProgressIndicator()
    private let goalLabel: NSTextField
    private let scrollView: NSScrollView
    private let textView: ClickableTextView
    private let endButton: NSButton
    private let replyTextField: NSTextField
    private let replyButton: NSButton
    var busy: Bool = false {
        didSet {
            layoutSubviews()
        }
    }

    var goal: String {
        get {
            goalLabel.stringValue
        }
        set {
            goalLabel.stringValue = "Goal: " + newValue
            layoutSubviews()
        }
    }

    var suggestion: String {
        get {
            textView.string
        }
        set {
            let attributedString = AttributedStringForGPTMarkdown(newValue, linkColor: .linkColor, textColor: .textColor) { [weak self] in
                self?.didCopyCallback()
            }
            textView.textStorage?.setAttributedString(attributedString)
            layoutSubviews()
        }
    }
    override var isFlipped: Bool { true }

    init(goal: String, 
         suggestion: String,
         endCallback: @escaping () -> (),
         replyCallback: @escaping (String) -> (),
         didCopyCallback: @escaping () -> ()) {
        activityIndicator.isIndeterminate = true
        activityIndicator.style = .spinning
        activityIndicator.isHidden = true
        activityIndicator.controlSize = .small

        self.endCallback = endCallback
        self.replyCallback = replyCallback
        self.didCopyCallback = didCopyCallback
        goalLabel = NSTextField(labelWithString: ")")
        goalLabel.lineBreakMode = .byTruncatingTail

        textView = ClickableTextView()
        textView.isSelectable = true
        textView.isEditable = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        
        scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
        endButton = NSButton(title: "End Task", target: nil, action: nil)

        replyTextField = NSTextField()
        replyTextField.placeholderString = "Response"
        replyButton = NSButton()
        replyButton.isEnabled = false
        replyButton.isBordered = false
        if #available(macOS 11.0, *) {
            replyButton.image = NSImage(systemSymbolName: SFSymbol.paperplane.rawValue, accessibilityDescription: "Send reply")
        } else {
            replyButton.stringValue = "Send"
        }
        replyButton.action = #selector(send(_:))

        super.init(frame: .zero)

        scrollView.documentView = textView
        addSubview(activityIndicator)
        addSubview(goalLabel)
        addSubview(scrollView)
        addSubview(endButton)
        addSubview(replyTextField)
        addSubview(replyButton)
        replyButton.target = self

        replyTextField.delegate = self

        endButton.target = self
        endButton.action = #selector(endButtonPressed)
        self.goal = goal
        self.suggestion = suggestion
        layoutSubviews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    @objc func send(_ sender: AnyObject) {
        let text = replyTextField.stringValue
        guard !text.isEmpty else {
            return
        }
        replyTextField.stringValue = ""
        scrollToEnd()
        replyCallback(text)
    }

    var height: CGFloat {
        textView.bounds.height
    }

    func scrollToEnd() {
        textView.scrollToVisible(NSRect(x: 0, y: height - 1, width: 1, height: 1))
    }

    private func layoutSubviews() {
        var x = 2.0
        if busy {
            activityIndicator.sizeToFit()
            activityIndicator.startAnimation(nil)
            activityIndicator.frame = NSRect(x: x, y: 0, width: activityIndicator.bounds.size.width, height: activityIndicator.bounds.size.height)
            x += activityIndicator.bounds.width + 2
        } else {
            activityIndicator.stopAnimation(nil)
        }
        activityIndicator.isHidden = !busy
        goalLabel.sizeToFit()
        goalLabel.frame = NSRect(x: x, y: 0, width: bounds.width - x - 2, height: goalLabel.bounds.height)

        endButton.sizeToFit()
        endButton.frame = NSRect(x: bounds.width - 2 - endButton.bounds.width,
                                 y: bounds.height - endButton.bounds.height,
                                 width: endButton.bounds.width,
                                 height: endButton.bounds.height)

        let vmargin = if #available(macOS 26, *) {
            8.0
        } else {
            4.0
        }
        scrollView.frame = NSRect(x: 2,
                                  y: goalLabel.frame.maxY + 4.0,
                                  width: bounds.width - 4.0,
                                  height: max(4.0,
                                              endButton.frame.minY - goalLabel.frame.maxY - vmargin))
        if let textContainer = textView.textContainer {
            var frame = textView.frame
            frame.size.width = scrollView.contentSize.width
            textView.frame = frame

            let containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textContainer.containerSize = containerSize
        }
        textView.textContainerInset = NSMakeSize(4, 10)
        // Refresh layout
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        do {
            replyButton.sizeToFit()
            replyButton.frame = NSRect(x: endButton.frame.minX - replyButton.bounds.width - 4,
                                       y: endButton.frame.minY + (endButton.bounds.height - replyButton.bounds.height) / 2,
                                       width: replyButton.bounds.width,
                                       height: replyButton.bounds.height)

            let height = replyTextField.fittingSize.height
            replyTextField.frame = NSRect(x: 2, 
                                          y: endButton.frame.minY + (endButton.bounds.height - height) / 2,
                                          width: replyButton.frame.minX - 4,
                                          height: height)
        }
        if busy {
            textView.alphaValue = 0.75
        } else {
            textView.alphaValue = 1.0
        }
    }

    @objc private func endButtonPressed() {
        endCallback()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.userInfo?["NSTextMovement"] as? Int == NSTextMovement.return.rawValue {
            if replyButton.isEnabled {
                send(self)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        replyButton.isEnabled = !replyTextField.stringValue.isEmpty
    }
}

extension NSMutableAttributedString {
    func insertButton(withImage dynamicImage: DynamicImage, at index: Int, action: @escaping (NSPoint) -> Void) {
        let attachment = NSTextAttachment()
        attachment.image = dynamicImage.tinted(forDarkMode: NSApp.effectiveAppearance.it_isDark)

        let height: CGFloat
        let y: CGFloat
        if let font = self.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
            height = font.leading + font.ascender - font.descender
            y = font.descender
        } else {
            height = NSFont.systemFontSize
            y = 0.0
        }
        let aspectRatio = dynamicImage.image.size.width / dynamicImage.image.size.height
        let adjustedSize = NSSize(width: height * aspectRatio, height: height)
        attachment.bounds = NSRect(origin: NSPoint(x: 0, y: y), size: adjustedSize)

        let buttonAttributedString = NSAttributedString(attachment: attachment)
        self.insert(buttonAttributedString, at: index)

        // Add a custom attribute to mark this range as clickable
        let range = NSRange(location: index, length: buttonAttributedString.length)
        addAttribute(.init("ClickableAttribute"), value: action, range: range)
        addAttribute(.dynamicAttachment, value: dynamicImage, range: range)
        addAttribute(.cursor, value: NSCursor.arrow, range: range)
    }
}

class ClickableTextView: NSTextView, NSTextStorageDelegate {
    var clickedRange: NSRange?
    var wasHovering = false

    init() {
        super.init(frame: .zero)
        textStorage?.delegate = self
    }
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func mouseMoved(with event: NSEvent) {
        if overClickable(event: event) != nil || linkURLAt(event: event) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard let superview else {
            return
        }
        trackingArea = NSTrackingArea(rect: frame,
                                      options: [.mouseEnteredAndExited, .activeAlways],
                                      owner: superview,
                                      userInfo: nil)
        if let trackingArea {
            superview.addTrackingArea(trackingArea)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        let index = self.characterIndexForInsertion(at: point)

        if overClickable(event: event) != nil || linkURLAt(event: event) != nil {
            clickedRange = NSRange(location: index, length: 1)
        } else {
            clickedRange = nil
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let clickedRange = clickedRange else {
            super.mouseUp(with: event)
            return
        }

        let point = self.convert(event.locationInWindow, from: nil)
        let index = self.characterIndexForInsertion(at: point)

        // Check if the mouse up event is within the same clickable range as the mouse down event
        if let action = overClickable(event: event),
           event.clickCount == 1,
           let window,
           clickedRange.contains(index) {
            action(window.convertPoint(toScreen: event.locationInWindow))
        } else if let url = linkURLAt(event: event) {
            NSWorkspace.shared.it_open(url)
        }
        self.clickedRange = nil
        super.mouseUp(with: event)
    }

    private func linkURLAt(event: NSEvent) -> URL? {
        guard let window = self.window else {
            return nil
        }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let index = characterIndex(for: point)

        if let textStorage = self.textStorage,
           index != NSNotFound,
           index >= 0,
           index < textStorage.string.count,
           let string = textStorage.attributes(at: index, effectiveRange: nil)[.link] as? String {
            return URL(string: string)
        }
        return nil

    }

    private func overClickable(event: NSEvent) -> ((NSPoint) -> ())? {
        guard let window = self.window else {
            return nil
        }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let index = characterIndex(for: point)

        if let textStorage = self.textStorage,
           index != NSNotFound,
           index >= 0,
           index < textStorage.string.count,
           let closure = textStorage.attributes(at: index, effectiveRange: nil)[.init("ClickableAttribute")] {
            return closure as? ((NSPoint) -> ())
        }
        return nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        retint()
    }

    private func retint() {
        let dark = effectiveAppearance.it_isDark

        guard let textStorage = self.textStorage else {
            return
        }
        textStorage.enumerateAttribute(
            .dynamicAttachment,
            in: NSRange(location: 0, length: textStorage.string.count)) { value, range, stopPtr in
                guard let value else { return }
                let dynamicImage = value as! DynamicImage

                textStorage.enumerateAttribute(.attachment, in: range) { innerValue, _, _ in
                    guard let attachment = innerValue as? NSTextAttachment else {
                        return
                    }
                    attachment.image = dynamicImage.tinted(forDarkMode: dark)
                }
            }
    }

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        retint()
    }
}

extension NSAttributedString.Key {
    static let dynamicAttachment = NSAttributedString.Key("dynamicAttachment")
}

class DynamicImage {
    let image: NSImage
    let dark: NSColor
    let light: NSColor
    private static var darkCacheKey = NSString("DynamicImage.darkCacheKey")
    private static var lightCacheKey = NSString("DynamicImage.lightCacheKey")

    init(image: NSImage, dark: NSColor, light: NSColor) {
        self.image = image
        self.dark = dark
        self.light = light
    }

    func tinted(forDarkMode darkMode: Bool) ->  NSImage {
        let cacheKey: UnsafeMutableRawPointer
        if darkMode {
            cacheKey = Unmanaged.passUnretained(DynamicImage.darkCacheKey).toOpaque()
        } else {
            cacheKey = Unmanaged.passUnretained(DynamicImage.lightCacheKey).toOpaque()
        }
        return image.it_cachingImage(withTintColor: darkMode ? dark : light,
                                     key: cacheKey)
    }
}

