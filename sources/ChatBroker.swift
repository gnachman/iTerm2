//
//  ChatBroker.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

// The ChatBroker bridges the imaginary line between client and server.
// It also ensure the model is up to date.
class ChatBroker {
    static let instance = ChatBroker()
    private var subs = [Subscription]()
    var processors = [(Message, String) -> (Message?)]()

    func create(chatWithTitle title: String, sessionGuid: String?) -> String {
        // Ensure the service is running
        _ = ChatService.instance

        let chat = Chat(title: title, messages: [], sessionGuid: sessionGuid)
        ChatListModel.instance.add(chat: chat)
        return chat.id
    }

    func publish(message: Message, toChatID chatID: String) {
        // Ensure the service is running
        _ = ChatService.instance

        var processed = message
        for processor in processors {
            if let temp = processor(processed, chatID) {
                processed = temp
            } else {
                DLog("Message processing squelched \(message)")
                return
            }
        }
        ChatListModel.instance.append(messages: [processed], toChatID: chatID)
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

    enum Update {
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

enum RemoteCommand: Codable {
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
}
