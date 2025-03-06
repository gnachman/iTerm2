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

    func delete(chatID: String) {
        listModel.delete(chatID: chatID)
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

    func create(chatWithTitle title: String, sessionGuid: String?) -> String {
        // Ensure the service is running
        _ = ChatService.instance

        let chat = Chat(title: title, sessionGuid: sessionGuid, permissions: "")
        listModel.add(chat: chat)
        publish(message: Message(chatID: chat.id,
                                 author: .user,
                                 content: .setPermissions(defaultPermissions),
                                 sentDate: Date(),
                                 uniqueID: UUID()),
                toChatID: chat.id,
                partial: false)
        return chat.id
    }

    func publish(message: Message, toChatID chatID: String, partial: Bool) {
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
        listModel.append(message: processed, toChatID: chatID)
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
                    .createFile(CreateFile())
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
        // When adding a new command be sure to update allCases.

        enum PermissionCategory: String, Codable, CaseIterable {
            case checkTerminalState = "Check Terminal State"
            case runCommands = "Run Commands"
            case viewHistory = "View History"
            case writeToClipboard = "Write to the Clipboard"
            case typeForYou = "Type for You"
            case viewManpages = "View Manpages"
            case writeToFilesystem = "Write to the File System"
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
        }
    }
}

extension ChatBroker {
    func publishMessageFromAgent(chatID: String, content: Message.Content) {
        publish(message: Message(chatID: chatID,
                                 author: .agent,
                                 content: content,
                                 sentDate: Date(),
                                 uniqueID: UUID()),
                toChatID: chatID,
                partial: false)
    }

    func publishMessageFromUser(chatID: String, content: Message.Content) {
        publish(message: Message(chatID: chatID,
                                 author: .user,
                                 content: content,
                                 sentDate: Date(),
                                 uniqueID: UUID()),
                toChatID: chatID,
                partial: false)
    }

    func publishNotice(chatID: String, notice: String) {
        publish(message: Message(chatID: chatID,
                                 author: .agent,
                                 content: .clientLocal(.init(action: .notice(notice))),
                                 sentDate: Date(),
                                 uniqueID: UUID()),
                toChatID: chatID,
                partial: false)
    }
}
