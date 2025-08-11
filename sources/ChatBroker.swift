//
//  ChatBroker.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//
// This is a diagram of the architecture of AI chat. There is a client and server side
// even though both run in the same process. This is to compartmentalize information so
// that the "agent" doesn't gain dependencies on the whole rest of the app.
// The ChatListModel also spans both client and "server" since it would be silly
// to keep two copies of messages.
//
//
//                                (App)
//                                  |
//   .--------------------.   .------------.   .---------------.   .--------------.
//   | ChatViewController |-->| ChatClient |-->| ChatListModel |-->| ChatDatabase |
//   `--------------------'   `------------'   `---------------'   `--------------'
//                  \               |              ^   ^
//                   \              |             /    |
//                    --------------)------------      |
//                                  |                  |
//                                  V                  |
//                              .--------.             |
//  ............................| Broker |.............|.................
//                              `--------'             |
//                                  ^                  |
//                                  |                  |
//                           .-------------.           |
//                           | ChatService |-----------'
//                           `-------------'
//                                  |
//                                  V
//                            .-----------.
//                            | ChatAgent |
//                            `-----------'
//                                  |
//                                  V
//                             nce  (AITerm)

// The ChatBroker bridges the imaginary line between client and server.
// It also ensure the model is up to date.
class ChatBroker {
    private static var _instance: ChatBroker?
    static var instance: ChatBroker? {
        if _instance == nil {
            _instance = ChatBroker()
        }
        return _instance
    }
    private var subs = [Subscription]()
    var processors = [(message: Message, chatID: String, partial: Bool) -> (Message?)]()
    private let listModel: ChatListModel

    init?() {
        guard let listModel = ChatListModel.instance else {
            return nil
        }
        self.listModel = listModel
    }

    func delete(chatID: String) throws {
        try listModel.delete(chatID: chatID)
    }

    private var defaultPermissions: Set<RemoteCommand.Content.PermissionCategory> {
        return Set(RemoteCommand.Content.PermissionCategory.allCases.filter { category in
            let rawValue = iTermPreferences.unsignedInteger(forKey: category.userDefaultsKey)
            guard let setting = iTermAIPermission(rawValue: rawValue) else {
                return false
            }
            return setting != .never
        })
    }

    func create(chatWithTitle title: String, terminalSessionGuid: String?, browserSessionGuid: String?) throws -> String {
        // Ensure the service is running
        _ = ChatService.instance

        let chat = Chat(title: title,
                        terminalSessionGuid: terminalSessionGuid,
                        browserSessionGuid: browserSessionGuid,
                        permissions: "")
        try listModel.add(chat: chat)
        try publish(message: Message(chatID: chat.id,
                                     author: .user,
                                     content: .setPermissions(defaultPermissions),
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chat.id,
                    partial: false)
        return chat.id
    }

    func publish(message: Message, toChatID chatID: String, partial: Bool) throws {
        DLog("Publish \(message.shortDescription)")
        // Ensure the service is running
        _ = ChatService.instance

        var processed = message
        for processor in processors {
            if let temp = processor(processed, chatID, partial) {
                processed = temp
            } else {
                DLog("Message processing squelched \(message)")
                return
            }
        }
        try listModel.append(message: processed, toChatID: chatID)
        for sub in subs {
            if sub.chatID == chatID || sub.chatID == nil {
                sub.closure?(.delivery(processed, chatID))
            }
        }
    }

    func publish(typingStatus: Bool,
                 of participant: Participant,
                 toChatID chatID: String) {
        TypingStatusModel.instance.set(isTyping: typingStatus,
                                       participant: participant,
                                       chatID: chatID)
        for sub in subs {
            if sub.chatID == chatID || sub.chatID == nil {
                sub.closure?(.typingStatus(typingStatus, participant))
            }
        }
    }

    func requestRegistration(chatID: String, completion: @escaping (AITermController.Registration?) -> ()) {
        for sub in subs {
            if sub.chatID == chatID, let provider = sub.registrationProvider {
                provider.registrationProviderRequestRegistration(completion)
                return
            }
        }
    }

    class Subscription {
        let chatID: String?
        let registrationProvider: AIRegistrationProvider?
        private(set) var closure: ((Update) -> ())?
        private var unsubscribeCallback: ((Subscription) -> ())?

        init(chatID: String?,
             registrationProvider: AIRegistrationProvider?,
             closure: @escaping (Update) -> (),
             unsubscribeCallback: @escaping (Subscription) -> ()) {
            self.chatID = chatID
            self.registrationProvider = registrationProvider
            self.closure = closure
            self.unsubscribeCallback = unsubscribeCallback
        }

        func publish(_ update: Update) {
            closure?(update)
        }

        func unsubscribe() {
            closure = nil
            if let callback = unsubscribeCallback {
                unsubscribeCallback = nil
                callback(self)
            }
        }
    }

    enum Update: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case let .typingStatus(typing, participant): "\(participant) typing=\(typing)"
            case let .delivery(message, chat): "Message in \(chat) - \(message.snippetText ?? "[empty]")"
            }
        }
        case typingStatus(Bool, Participant)
        case delivery(Message, String)
    }

    func subscribe(chatID: String?,
                   registrationProvider: AIRegistrationProvider?,
                   closure: @escaping (Update) -> ()) -> Subscription {
        let subscription = Subscription(chatID: chatID,
                                        registrationProvider: registrationProvider,
                                        closure: closure) { [weak self] sub in
            self?.subs.removeAll(where: { $0 === sub })
        }
        subs.append(subscription)
        return subscription
    }
}

struct RemoteCommand: Codable {
    struct IsAtPrompt: Codable {}
    struct ExecuteCommand: Codable { var command: String = "" }
    struct GetLastExitStatus: Codable {}

    struct GetCommandHistory: Codable { var limit: Int = 100 }
    struct GetLastCommand: Codable {}
    struct GetCommandBeforeCursor: Codable {}
    struct SearchCommandHistory: Codable { var query: String = "" }
    struct GetCommandOutput: Codable { var id: String = "" }

    struct GetTerminalSize: Codable {}
    struct GetShellType: Codable {}
    struct DetectSSHSession: Codable {}
    struct GetRemoteHostname: Codable {}
    struct GetUserIdentity: Codable {}
    struct GetCurrentDirectory: Codable {}

    struct SetClipboard: Codable { var text: String = "" }
    struct InsertTextAtCursor: Codable { var text: String = "" }
    struct DeleteCurrentLine: Codable {}
    struct GetManPage: Codable { var cmd: String = "" }
    struct CreateFile: Codable {
        var filename: String=""
        var content: String=""
    }
    struct SearchBrowser: Codable { var query: String = "" }
    struct LoadURL: Codable { var url: String = "" }
    struct WebSearch: Codable { var query: String = "" }
    struct GetURL: Codable {}
    struct ReadWebPage: Codable {
        var startingLineNumber: Int = 0
        var numberOfLines: Int = 0
    }

    struct DiscoverForms: Codable {
        var frameId: String = ""
        var visibility: String = "visible" // "visible" or "any"
        var maxForms: Int = 50
    }

    struct DescribeForm: Codable {
        var frameId: String = ""
        var formId: String = ""
        var includeOptions: Bool = true
        var includeAria: Bool = true
        var includeCss: Bool = false
    }

    struct GetFormState: Codable {
        var formId: String = ""
        var maskSecrets: Bool = true
    }

    struct SetFieldValue: Codable {
        var frameId: String = ""
        var fieldId: String = ""
        var value = JSONSchemaAnyCodable.placeholder // Any JSON value: string, boolean, array, or null
        var mode: String = "type" // "type", "set", or "paste"
        var clearFirst: Bool = true
        var delayMsPerChar: Int = 0
        var ensureVisible: Bool = true
        var selectAfter: Bool = false
    }

    struct ChooseOption: Codable {
        var fieldId: String = ""
        var by: String = "value" // "value", "label", or "index"
        var choice = JSONSchemaStringNumberOrStringArray.placeholder // String, number, or string array
        var deselectOthers: Bool = true
    }

    struct ToggleCheckbox: Codable {
        var fieldId: String = ""
        var checked: Bool = true
    }

    struct UploadFile: Codable {
        struct FileRef: Codable {
            var fileHandle: String = ""
            var name: String = ""
        }

        var fieldId: String = ""
        var files: [FileRef] = [.init()]
        var replace: Bool = true
    }

    struct ClickNode: Codable {
        var frameId: String = ""
        var nodeId: String = ""
        var ensureVisible: Bool = true
        var button: String = "left" // "left", "middle", or "right"
        var clickCount: Int = 1
    }

    struct SubmitForm: Codable {
        var frameId: String = ""
        var formId: String = ""
        var submitterNodeId: String = ""
        var wait: Bool = false
        var timeoutMs: Int = 10_000
    }

    struct ValidateForm: Codable {
        var formId: String = ""
    }

    struct InferSemantics: Codable {
        var formId: String = ""
        var locale: String = "en-US"
    }

    struct FocusField: Codable {
        var fieldId: String = ""
    }

    struct BlurField: Codable {
        var fieldId: String = ""
    }

    struct ScrollIntoView: Codable {
        var nodeId: String = ""
        var align: String = "nearest" // "nearest", "center", "start", or "end"
    }

    struct DetectChallenge: Codable {
        var frameId: String = ""
        var formId: String = ""
    }

    struct MapNodesForActions: Codable {
        var frameId: String = ""
        var formId: String = ""
    }
    enum Content: Codable, CaseIterable {
        static var allCases: [RemoteCommand.Content] {
            return [.isAtPrompt(IsAtPrompt()),
                    .executeCommand(ExecuteCommand()),
                    .getLastExitStatus(GetLastExitStatus()),
                    .getCommandHistory(GetCommandHistory()),
                    .getLastCommand(GetLastCommand()),
                    .getCommandBeforeCursor(GetCommandBeforeCursor()),
                    .searchCommandHistory(SearchCommandHistory()),
                    .getCommandOutput(GetCommandOutput()),
                    .getTerminalSize(GetTerminalSize()),
                    .getShellType(GetShellType()),
                    .detectSSHSession(DetectSSHSession()),
                    .getRemoteHostname(GetRemoteHostname()),
                    .getUserIdentity(GetUserIdentity()),
                    .getCurrentDirectory(GetCurrentDirectory()),
                    .setClipboard(SetClipboard()),
                    .insertTextAtCursor(InsertTextAtCursor()),
                    .deleteCurrentLine(DeleteCurrentLine()),
                    .getManPage(GetManPage()),
                    .createFile(CreateFile()),
                    .searchBrowser(SearchBrowser()),
                    .loadURL(LoadURL()),
                    .webSearch(WebSearch()),
                    .getURL(GetURL()),
                    .readWebPage(ReadWebPage()),

                .discoverForms(DiscoverForms()),
                .describeForm(DescribeForm()),
                .getFormState(GetFormState()),
                .setFieldValue(SetFieldValue()),
                .chooseOption(ChooseOption()),
                .toggleCheckbox(ToggleCheckbox()),
                .uploadFile(UploadFile()),
                .clickNode(ClickNode()),
                .submitForm(SubmitForm()),
                .validateForm(ValidateForm()),
                .inferSemantics(InferSemantics()),
                .focusField(FocusField()),
                .blurField(BlurField()),
                .scrollIntoView(ScrollIntoView()),
                .detectChallenge(DetectChallenge()),
                .mapNodesForActions(MapNodesForActions())

            ]
        }

        case isAtPrompt(IsAtPrompt)
        case executeCommand(ExecuteCommand)
        case getLastExitStatus(GetLastExitStatus)
        case getCommandHistory(GetCommandHistory)
        case getLastCommand(GetLastCommand)
        case getCommandBeforeCursor(GetCommandBeforeCursor)
        case searchCommandHistory(SearchCommandHistory)
        case getCommandOutput(GetCommandOutput)
        case getTerminalSize(GetTerminalSize)
        case getShellType(GetShellType)
        case detectSSHSession(DetectSSHSession)
        case getRemoteHostname(GetRemoteHostname)
        case getUserIdentity(GetUserIdentity)
        case getCurrentDirectory(GetCurrentDirectory)
        case setClipboard(SetClipboard)
        case insertTextAtCursor(InsertTextAtCursor)
        case deleteCurrentLine(DeleteCurrentLine)
        case getManPage(GetManPage)
        case createFile(CreateFile)
        case searchBrowser(SearchBrowser)
        case loadURL(LoadURL)
        case webSearch(WebSearch)
        case getURL(GetURL)
        case readWebPage(ReadWebPage)

        case discoverForms(DiscoverForms)
        case describeForm(DescribeForm)
        case getFormState(GetFormState)
        case setFieldValue(SetFieldValue)
        case chooseOption(ChooseOption)
        case toggleCheckbox(ToggleCheckbox)
        case uploadFile(UploadFile)
        case clickNode(ClickNode)
        case submitForm(SubmitForm)
        case validateForm(ValidateForm)
        case inferSemantics(InferSemantics)
        case focusField(FocusField)
        case blurField(BlurField)
        case scrollIntoView(ScrollIntoView)
        case detectChallenge(DetectChallenge)
        case mapNodesForActions(MapNodesForActions)

        // When adding a new command be sure to update allCases.

        enum PermissionCategory: String, Codable, CaseIterable {
            case checkTerminalState = "Check Terminal State"
            case runCommands = "Run Commands"
            case viewHistory = "View History"
            case writeToClipboard = "Write to the Clipboard"
            case typeForYou = "Type for You"
            case viewManpages = "View Manpages"
            case writeToFilesystem = "Write to the File System"
            case actInWebBrowser = "Act in Web Browser"

            var isBrowserSpecific: Bool {
                switch self {
                case .checkTerminalState, .runCommands, .viewHistory, .writeToClipboard,
                        .typeForYou, .viewManpages, .writeToFilesystem:
                    false
                case .actInWebBrowser:
                    true
                }
            }
        }

        var permissionCategory: PermissionCategory {
            switch self {
            case .isAtPrompt, .getLastExitStatus, .getTerminalSize, .getShellType,
                    .detectSSHSession, .getRemoteHostname, .getUserIdentity, .getCurrentDirectory:
                    .checkTerminalState
            case .executeCommand:
                    .runCommands
            case .getCommandHistory, .getLastCommand, .getCommandBeforeCursor,
                    .searchCommandHistory, .getCommandOutput:
                    .viewHistory
            case .setClipboard:
                    .writeToClipboard
            case .insertTextAtCursor, .deleteCurrentLine:
                    .typeForYou
            case .getManPage:
                    .viewManpages
            case .createFile:
                    .writeToFilesystem
            case .searchBrowser, .loadURL, .webSearch, .getURL, .readWebPage,
                    .discoverForms, .describeForm, .getFormState, .setFieldValue,
                    .chooseOption, .toggleCheckbox, .uploadFile, .clickNode,
                    .submitForm, .validateForm, .inferSemantics, .focusField,
                    .blurField, .scrollIntoView, .detectChallenge,
                    .mapNodesForActions:
                    .actInWebBrowser
            }
        }

        var args: Any {
            switch self {
            case .isAtPrompt(let args): args
            case .executeCommand(let args): args
            case .getLastExitStatus(let args): args
            case .getCommandHistory(let args): args
            case .getLastCommand(let args): args
            case .getCommandBeforeCursor(let args): args
            case .searchCommandHistory(let args): args
            case .getCommandOutput(let args): args
            case .getTerminalSize(let args): args
            case .getShellType(let args): args
            case .detectSSHSession(let args): args
            case .getRemoteHostname(let args): args
            case .getUserIdentity(let args): args
            case .getCurrentDirectory(let args): args
            case .setClipboard(let args): args
            case .insertTextAtCursor(let args): args
            case .deleteCurrentLine(let args): args
            case .getManPage(let args): args
            case .createFile(let args): args
            case .searchBrowser(let args): args
            case .loadURL(let args): args
            case .webSearch(let args): args
            case .getURL(let args): args
            case .readWebPage(let args): args

            case .discoverForms(let args): args
            case .describeForm(let args): args
            case .getFormState(let args): args
            case .setFieldValue(let args): args
            case .chooseOption(let args): args
            case .toggleCheckbox(let args): args
            case .uploadFile(let args): args
            case .clickNode(let args): args
            case .submitForm(let args): args
            case .validateForm(let args): args
            case .inferSemantics(let args): args
            case .focusField(let args): args
            case .blurField(let args): args
            case .scrollIntoView(let args): args
            case .detectChallenge(let args): args
            case .mapNodesForActions(let args): args
            }
        }
    }


    var llmMessage: LLM.Message
    var content: Content

    var markdownDescription: String {
        switch content {
        case .isAtPrompt:
            "Checking if you're at a shell prompt"
        case let .executeCommand(args):
            "Executing `\(args.command.escapedForMarkdownCode.truncatedWithTrailingEllipsis(to: 32))`"
        case .getLastExitStatus:
            "Checking the exit status of the last command"
        case .getCommandHistory:
            "Reviewing the history of commands you have run in this session"
        case .getLastCommand:
            "Viewing the last command you ran in this session"
        case .getCommandBeforeCursor:
            "Reading your current command prompt"
        case .searchCommandHistory:
            "Searching the history of commands you have run in this session"
        case .getCommandOutput:
            "Fetching the output of a previously run command"
        case .getTerminalSize:
            "Querying the size of your terminal window"
        case .getShellType:
            "Determining which shell you use"
        case .detectSSHSession:
            "Checking if you are using SSH"
        case .getRemoteHostname:
            "Getting the current host name of this terminal session"
        case .getUserIdentity:
            "Checking your username"
        case .getCurrentDirectory:
            "Discovering your current directory"
        case .setClipboard:
            "Pasting to the clipboard"
        case let .insertTextAtCursor(args):
            "Typing `\(args.text.escapedForMarkdownCode.truncatedWithTrailingEllipsis(to: 32))` into the current session"
        case .deleteCurrentLine:
            "Erasing the current command line"
        case let .getManPage(args):
            "Checking the manpage for `\(args.cmd.escapedForMarkdownCode.truncatedWithTrailingEllipsis(to: 32))`"
        case let .createFile(args):
            "Creating \(args.filename)"
        case let .searchBrowser(args):
            "Search in browser for \(args.query)"
        case let .loadURL(args):
            "Navigate to \(args.url)"
        case let .webSearch(args):
            "Search the web for “\(args.query)”"
        case .getURL:
            "Get the current URL"
        case .readWebPage:
            "View the current web page"

        case .discoverForms:
            "Enumerate forms and controls on the page"
        case .describeForm:
            "Get detailed metadata for a form"
        case .getFormState:
            "Read current values for all fields in a form"
        case let .setFieldValue(args):
            "Set value for field \(args.fieldId)"
        case let .chooseOption(args):
            "Choose option in \(args.fieldId) by \(args.by)"
        case let .toggleCheckbox(args):
            "Set checkbox \(args.fieldId) to \(args.checked ? "checked" : "unchecked")"
        case let .uploadFile(args):
            "Attach \(args.files.count) file(s) to \(args.fieldId)"
        case let .clickNode(args):
            "Click a button"
        case let .submitForm(args):
            if args.wait {
                "Submit form and wait"
            } else {
                "Submit form"
            }
        case .validateForm:
            "Validate form and list field errors"
        case .inferSemantics:
            "Infer semantic roles for fields"
        case let .focusField(args):
            "Focus field \(args.fieldId)"
        case let .blurField(args):
            "Blur field \(args.fieldId)"
        case .scrollIntoView:
            "Scroll element into view"
        case .detectChallenge:
            "Detect CAPTCHA/OTP or related challenges"
        case .mapNodesForActions:
            "Find likely Next/Submit/Continue buttons"
        }
    }

    var permissionDescription: String {
        switch content {
        case .isAtPrompt:
            "The AI Agent would like to check if you're at a shell prompt"
        case let .executeCommand(args):
            "The AI Agent would like to execute `\(args.command.escapedForMarkdownCode)`"
        case .getLastExitStatus:
            "The AI Agent would like to check the exit status of the last command"
        case .getCommandHistory:
            "The AI Agent would like to review the history of commands you have run in this session"
        case .getLastCommand:
            "The AI Agent would like to view the last command you ran in this session"
        case .getCommandBeforeCursor:
            "The AI Agent would like to read your current command prompt"
        case .searchCommandHistory:
            "The AI Agent would like to search the history of commands you have run in this session"
        case .getCommandOutput:
            "The AI Agent would like to fetch the output of a previously run command"
        case .getTerminalSize:
            "The AI Agent would like to query the size of your terminal window"
        case .getShellType:
            "The AI Agent would like to determine which shell you use"
        case .detectSSHSession:
            "The AI Agent would like to check if you are using SSH"
        case .getRemoteHostname:
            "The AI Agent would like to get the current host name of this terminal session"
        case .getUserIdentity:
            "The AI Agent would like to check your username"
        case .getCurrentDirectory:
            "The AI Agent would like to know your current directory"
        case .setClipboard:
            "The AI Agent would like to paste to the clipboard"
        case let .insertTextAtCursor(args):
            "The AI Agent would like to type `\(args.text.escapedForMarkdownCode.truncatedWithTrailingEllipsis(to: 32))` into the current session"
        case .deleteCurrentLine:
            "The AI Agent would like to erase the current command line"
        case let .getManPage(args):
            "The AI Agent would like to check the manpage for `\(args.cmd.escapedForMarkdownCode)`"
        case let .createFile(args):
            "The AI Agent would like to create a file named `\(args.filename)`"
        case let .searchBrowser(args):
            "The AI agent would like to search the current web page for “\(args.query)”"
        case let .loadURL(args):
            "The AI agent would like to navigate to \(args.url)"
        case let .webSearch(args):
            "The AI agent would like to write to search the web for “\(args.query)”"
        case .getURL:
            "The AI agent would like to write to get the current URL"
        case .readWebPage:
            "The AI agent would like to read the current web page"

        case .discoverForms:
            "The AI Agent would like to enumerate forms and controls on the current web page"
        case .describeForm:
            "The AI Agent would like to get detailed metadata for a form"
        case .getFormState:
            "The AI Agent would like to read the current values for all fields in a form"
        case let .setFieldValue(args):
            "The AI Agent would like to set the value of the field `\(args.fieldId)`"
        case let .chooseOption(args):
            "The AI Agent would like to choose an option in the field `\(args.fieldId)` by \(args.by)"
        case let .toggleCheckbox(args):
            "The AI Agent would like to set the checkbox `\(args.fieldId)` to \(args.checked ? "checked" : "unchecked")"
        case let .uploadFile(args):
            "The AI Agent would like to attach \(args.files.count) file(s) to the field `\(args.fieldId)`"
        case let .clickNode(args):
            "The AI Agent would like to click the node `\(args.nodeId)`"
        case let .submitForm(args):
            "The AI Agent would like to submit the form `\(args.formId)`"
        case .validateForm:
            "The AI Agent would like to validate a form and list any field errors"
        case .inferSemantics:
            "The AI Agent would like to infer semantic roles for fields in a form"
        case let .focusField(args):
            "The AI Agent would like to focus the field `\(args.fieldId)`"
        case let .blurField(args):
            "The AI Agent would like to blur the field `\(args.fieldId)`"
        case .scrollIntoView:
            "The AI Agent would like to scroll an element into view"
        case .detectChallenge:
            "The AI Agent would like to detect CAPTCHA, OTP, or similar challenges on the page"
        case .mapNodesForActions:
            "The AI Agent would like to identify likely Next, Submit, or Continue buttons on the page"

        }
    }

    var shouldPublishNotice: Bool {
        switch content {
        case .executeCommand:
            false
        case .isAtPrompt, .getLastExitStatus, .getCommandHistory, .getLastCommand,
                .getCommandBeforeCursor, .searchCommandHistory, .getCommandOutput, .getTerminalSize,
                .getShellType, .detectSSHSession, .getRemoteHostname, .getUserIdentity,
                .getCurrentDirectory, .setClipboard, .insertTextAtCursor, .deleteCurrentLine,
                .getManPage, .createFile, .searchBrowser, .loadURL,
                .webSearch, .getURL, .readWebPage, .discoverForms, .describeForm, .getFormState,
                .setFieldValue, .chooseOption, .toggleCheckbox, .uploadFile, .clickNode,
                .submitForm, .validateForm, .inferSemantics, .focusField,
                .blurField, .scrollIntoView, .detectChallenge,
                .mapNodesForActions:
            true
        }
    }
}

extension RemoteCommand.Content.PermissionCategory {
    var userDefaultsKey: String {
        switch self {
        case .checkTerminalState: kPreferenceKeyAIPermissionCheckTerminalState
        case .runCommands: kPreferenceKeyAIPermissionRunCommands
        case .viewHistory: kPreferenceKeyAIPermissionViewHistory
        case .writeToClipboard: kPreferenceKeyAIPermissionWriteToClipboard
        case .typeForYou: kPreferenceKeyAIPermissionTypeForYou
        case .viewManpages: kPreferenceKeyAIPermissionViewManpages
        case .writeToFilesystem: kPreferenceKeyAIPermissionWriteToFilesystem
        case .actInWebBrowser: kPreferenceKeyAIPermissionActInWebBrowser
        }
    }
}

extension ChatBroker {
    func publishMessageFromAgent(chatID: String, content: Message.Content) throws {
        try publish(message: Message(chatID: chatID,
                                     author: .agent,
                                     content: content,
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
    }

    func publishMessageFromUser(chatID: String, content: Message.Content) throws {
        try publish(message: Message(chatID: chatID,
                                     author: .user,
                                     content: content,
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
    }

    func publishNotice(chatID: String, notice: String) throws {
        try publish(message: Message(chatID: chatID,
                                     author: .agent,
                                     content: .clientLocal(.init(action: .notice(notice))),
                                     sentDate: Date(),
                                     uniqueID: UUID()),
                    toChatID: chatID,
                    partial: false)
    }
}
