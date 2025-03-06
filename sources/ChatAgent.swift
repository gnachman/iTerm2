//
//  ChatAgent.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

fileprivate extension AITermController.Message {
    static func role(from message: Message) -> LLM.Message.Role {
        switch message.author {
        case .user: .user
        case .agent: .assistant
        }
    }
}

extension Message {
    var functionCallName: String? {
        switch content {
        case .remoteCommandRequest(let request):
            return request.llmMessage.function_call?.name
        case .remoteCommandResponse(_, _, let name):
            return name
        default:
            return nil
        }
    }

    var functionCall: LLM.Message.FunctionCall? {
        switch content {
        case .remoteCommandRequest(let request):
            return request.llmMessage.function_call
        default:
            return nil
        }
    }
}
fileprivate struct MessageToPromptStateMachine {
    private enum Mode {
        case regular
        case initialExplanation
    }
    private var mode = Mode.regular

    mutating func prompt(message: Message) -> String? {
        switch message.author {
        case .agent:
            prompt(agentMessage: message)
        case .user:
            prompt(userMessage: message)
        }
    }

    private mutating func prompt(agentMessage: Message) -> String? {
        switch agentMessage.content {
        case .plainText(let value), .markdown(let value):
            return value
        case .explanationResponse(let annotations, _, _):
            return annotations.rawResponse
        case .explanationRequest:
            it_fatalError()
        case .remoteCommandRequest:
            return nil
        case .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .terminalCommand:
            it_fatalError()
        }
    }

    private func prompt(terminalCommand: TerminalCommand) -> String {
        var lines = [String]()
        lines.append("iTerm2 is sending you this message automatically because the user enabled sending terminal commands to AI for assistance. If you can provide useful non-obvious insights, respond with those. Do not restate information that is obvious from the output. If there is nothing important to say, just respond with \"Got it.\"")
        lines.append("I executed the following command line:")
        lines.append(terminalCommand.command)
        if let directory = terminalCommand.directory {
            lines.append("My current directory was:")
            lines.append(directory)
        }
        if let hostname = terminalCommand.hostname {
            if let username = terminalCommand.username {
                lines.append("I am logged in as \(username)@\(hostname)")
            } else {
                lines.append("The current hostname is \(hostname)")
            }
        }
        lines.append("The exit status of the command was \(terminalCommand.exitCode)")
        lines.append("It produced this output:")
        lines.append(terminalCommand.output)
        return lines.joined(separator: "\n")
    }

    private mutating func prompt(userMessage: Message) -> String {
        switch mode {
        case .regular:
            switch userMessage.content {
            case .plainText(let value), .markdown(let value):
                return value
            case .explanationRequest(let request):
                mode = .initialExplanation
                return request.prompt()
            case .explanationResponse, .append:
                it_fatalError()
            case .remoteCommandResponse(let result, _, _):
                return result.map { value in
                    value
                } failure: { error in
                    "I was unable to complete the function call: " + error.localizedDescription
                }
            case .terminalCommand(let cmd):
                return prompt(terminalCommand: cmd)
            case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .commit,
                    .setPermissions:
                it_fatalError()
            }
        case .initialExplanation:
            switch userMessage.content {
            case .plainText(let value), .markdown(let value):
                mode = .regular
                return AIExplanationRequest.conversationalPrompt(userPrompt: value)
            case .explanationResponse, .explanationRequest, .append, .remoteCommandRequest,
                    .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat,
                    .commit, .setPermissions:
                it_fatalError()
            case .terminalCommand(let cmd):
                return prompt(terminalCommand: cmd)
            }
        }
    }
}

class ChatAgent {
    private var conversation: AIConversation
    private let chatID: String
    private var brokerSubscription: ChatBroker.Subscription?
    private var messageToPrompt = MessageToPromptStateMachine()
    private var pendingRemoteCommands = [UUID: (Result<String, Error>) -> ()]()
    private let broker: ChatBroker
    private var renameConversation: AIConversation?

    init(_ chatID: String,
         broker: ChatBroker,
         registrationProvider: AIRegistrationProvider,
         messages: [Message]) {
        self.chatID = chatID
        self.broker = broker
        conversation = AIConversation(registrationProvider: registrationProvider)
        var permissions = Set<RemoteCommand.Content.PermissionCategory>()
        for message in messages {
            switch message.content {
            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse, .terminalCommand:
                conversation.add(aiMessage(from: message))
                break

            case .selectSessionRequest, .clientLocal, .renameChat, .append, .commit:
                break

            case .setPermissions(let updated):
                permissions = updated
            }
        }
        updateSystemMessage(permissions)
    }

    private func updateSystemMessage(_ permissions: Set<RemoteCommand.Content.PermissionCategory>) {
        if permissions.isEmpty {
            conversation.systemMessage = "You help the user in a terminal emulator."
        } else if permissions.contains(.runCommands) || permissions.contains(.typeForYou) {
            conversation.systemMessage = "You help the user in a terminal emulator. You have the ability to run commands on their behalf and perform various other operations in terminal sessions. Don't be shy about using them, especially if they are safe to do, because the user must always grant permission for these functions to run. You don't need to request permission: the app will do that for you."
        } else {
            conversation.systemMessage = "You help the user in a terminal emulator. You have some access to the user's state with function calling. Don't by shy about using it because the user must always grant permission for functions to run. You don't need to request permission: the app will do that for you."
        }

        defineFunctions(in: &conversation, allowedCategories: permissions)
    }

    deinit {
        brokerSubscription?.unsubscribe()
    }

    private func aiMessage(from message: Message) -> AITermController.Message {
        AITermController.Message(role: AITermController.Message.role(from: message),
                                 content: messageToPrompt.prompt(message: message),
                                 name: message.functionCallName,
                                 function_call: message.functionCall)
    }

    enum StreamingUpdate {
        case begin(Message)
        case append(String, UUID)
    }

    func fetchCompletion(userMessage: Message,
                         streaming: ((StreamingUpdate) -> ())?,
                         completion: @escaping (Message?) -> ()) {
        switch userMessage.content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .selectSessionRequest, .clientLocal, .commit,
                .terminalCommand:
            break
        case .renameChat, .append:
            return
        case .remoteCommandResponse(let result, let messageID, _):
            if let pending = pendingRemoteCommands[messageID] {
                NSLog("Agent handling remote command response to message \(messageID)")
                pendingRemoteCommands.removeValue(forKey: messageID)
                pending(Result(result))
                return
            }
        case .setPermissions(let allowedCategories):
            defineFunctions(in: &conversation,
                            allowedCategories: allowedCategories)
            updateSystemMessage(allowedCategories)
            completion(nil)
            return
        }

        let needsRenaming = !conversation.messages.anySatisfies({ $0.role == .user})
        conversation.add(aiMessage(from: userMessage))
        var uuid: UUID?
        let streamingCallback: ((String) -> ())?
        if let streaming {
            streamingCallback = { chunk in
                if uuid == nil,
                    let initialMessage = Self.message(completionText: chunk,
                                                      userMessage: userMessage,
                                                      streaming: true) {
                    streaming(.begin(initialMessage))
                    uuid = initialMessage.uniqueID
                } else if let uuid {
                    streaming(.append(chunk, uuid))
                }
            }
        } else {
            streamingCallback = nil
        }
        conversation.complete(streaming: streamingCallback) { [weak self] result in
            guard let self else {
                return
            }
            if let updated = result.successValue {
                self.conversation = updated
                if needsRenaming {
                    self.requestRenaming()
                }
            } else {
                self.conversation.messages.removeLast()
            }
            let message = Self.committedMessage(forResult: result,
                                                userMessage: userMessage,
                                                streamID: uuid)
            completion(message)
        }
    }

    private func requestRenaming() {
        let prompt = "Please assign a short, specific name to this chat, less than 30 characters in length, but descriptive. It will be shown in a chat list UI. Respond with only the name of the chat."
        renameConversation = AIConversation(
            registrationProvider: nil,
            messages: conversation.messages + [AITermController.Message(role: .user, content: prompt)])
        var failed = false
        renameConversation?.complete { [weak self] (result: Result<AIConversation, Error>) in
            if let newName = result.successValue?.messages.last?.content {
                self?.renameChat(newName)
                self?.renameConversation = nil
            } else {
                failed = true
            }
        }
        if failed {
            renameConversation = nil
        }
    }

    private static func committedMessage(respondingTo userMessage: Message,
                                         fromLastMessageIn conversation: AIConversation) -> Message? {
        guard let text = conversation.messages.last!.content else {
            return nil
        }
        return self.message(completionText: text, userMessage: userMessage, streaming: false)
    }

    // Return a new message from the agent containing the content of the last message in result.
    private static func committedMessage(forResult result: Result<AIConversation, any Error>,
                                         userMessage: Message,
                                         streamID: UUID?) -> Message? {
        if let streamID {
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .commit(streamID),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
        return result.handle { (updated: AIConversation) -> Message? in
            return committedMessage(respondingTo: userMessage,
                                    fromLastMessageIn: updated)
        } failure: { error in
            let nserror = error as NSError
            if userMessage.isExplanationRequest &&
                nserror.domain == iTermAIError.domain &&
                nserror.code == iTermAIError.ErrorType.requestTooLarge.rawValue {
                return Message(chatID: userMessage.chatID,
                               author: .agent,
                               content: .plainText("🛑 The text to analyze was too long. Select a portion of it and try again."),
                               sentDate: Date(),
                               uniqueID: UUID())
            }

            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .plainText("🛑 I ran into a problem: \(error.localizedDescription)"),
                           sentDate: Date(),
                           uniqueID: UUID())
        }
    }

    // This is for a committed message or an initial message in a stream.
    private static func message(completionText text: String,
                                userMessage: Message,
                                streaming: Bool) -> Message? {
        switch userMessage.content {
        case .plainText, .markdown, .explanationResponse, .terminalCommand:
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .markdown(text),
                           sentDate: Date(),
                           uniqueID: UUID())
        case .explanationRequest(let explanationRequest):
            let messageID = UUID()
            return Message(
                chatID: userMessage.chatID,
                author: .agent,
                content: .explanationResponse(
                    ExplanationResponse(text: text,
                                        request: explanationRequest,
                                        final: streaming == false),
                    streaming ? ExplanationResponse.Update(final: false, messageID: messageID) : nil,
                    markdown: ""),  // markdown is added by the client.
                sentDate: Date(),
                uniqueID: messageID)
        case .remoteCommandResponse:
            return Message(chatID: userMessage.chatID,
                           author: .agent,
                           content: .markdown(text),
                           sentDate: Date(),
                           uniqueID: UUID())
        case .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions:
            it_fatalError()
        }
    }
}


extension Message {
    var isExplanationRequest: Bool {
        switch content {
        case .explanationRequest: true
        default: false
        }
    }
}

extension RemoteCommand.Content {
    var functionName: String {
        switch self {
        case .isAtPrompt:
            "is_at_prompt"
        case .executeCommand:
            "execute_command"
        case .getLastExitStatus:
            "get_last_exit_status"
        case .getCommandHistory:
            "get_command_history"
        case .getLastCommand:
            "get_last_command"
        case .getCommandBeforeCursor:
            "get_command_before_cursor"
        case .searchCommandHistory:
            "search_command_history"
        case .getCommandOutput:
            "get_command_output"
        case .getTerminalSize:
            "get_terminal_size"
        case .getShellType:
            "get_shell_type"
        case .detectSSHSession:
            "detect_ssh_session"
        case .getRemoteHostname:
            "get_remote_hostname"
        case .getUserIdentity:
            "get_user_identity"
        case .getCurrentDirectory:
            "get_current_directory"
        case .setClipboard:
            "set_clipboard"
        case .insertTextAtCursor:
            "insert_text_at_cursor"
        case .deleteCurrentLine:
            "delete_current_line"
        case .getManPage:
            "get_man_page"
        case .createFile:
            "create_file"
        }
    }

    var argDescriptions: [String: String] {
        return switch self {
        case .isAtPrompt(_):
            [:]
        case .executeCommand(_):
            ["command": "The command to run"]
        case .getLastExitStatus(_):
            [:]
        case .getCommandHistory(_):
            ["limit": "Maximum number of history items to return."]
        case .getLastCommand(_):
            [:]
        case .getCommandBeforeCursor(_):
            [:]
        case .searchCommandHistory(_):
            ["query": "Search query for filtering command history."]
        case .getCommandOutput(_):
            ["id": "Unique identifier of the command whose output is requested."]
        case .getTerminalSize(_):
            [:]
        case .getShellType(_):
            [:]
        case .detectSSHSession(_):
            [:]
        case .getRemoteHostname(_):
            [:]
        case .getUserIdentity(_):
            [:]
        case .getCurrentDirectory(_):
            [:]
        case .setClipboard(_):
            ["text": "The text to copy to the clipboard."]
        case .insertTextAtCursor(_):
            ["text": "The text to insert at the cursor position. Consider whether execute_command would be a better choice, especially when running a command at the shell prompt since insert_text_at_cursor does not return the output to you."]
        case .deleteCurrentLine(_):
            [:]
        case .getManPage(_):
            ["cmd": "The command whose man page content is requested."]
        case .createFile:
            ["filename": "The name of the file you wish to create. It will be replaced if it already exists.",
             "content": "The content that will be written to the file."]
        }
    }

    var functionDescription: String {
        switch self {
        case .isAtPrompt(_):
            "Returns true if the terminal is at the command prompt, allowing safe command injection."
        case .executeCommand(_):
            "Runs a shell command and returns its output."
        case .getLastExitStatus(_):
            "Retrieves the exit status of the last executed command."
        case .getCommandHistory(_):
            "Returns the recent command history."
        case .getLastCommand(_):
            "Retrieves the most recent command."
        case .getCommandBeforeCursor(_):
            "Returns the current partially typed command before the cursor."
        case .searchCommandHistory(_):
            "Searches history for commands matching a query."
        case .getCommandOutput(_):
            "Returns the output of a previous command by its unique identifier."
        case .getTerminalSize(_):
            "Returns (columns, rows) of the terminal window."
        case .getShellType(_):
            "Detects the shell in use (e.g., bash, zsh, fish)."
        case .detectSSHSession(_):
            "Returns true if the user is SSH’ed into a remote host."
        case .getRemoteHostname(_):
            "Returns the remote hostname if in an SSH session."
        case .getUserIdentity(_):
            "Returns the logged-in user’s username."
        case .getCurrentDirectory(_):
            "Returns the current directory."
        case .setClipboard(_):
            "Copies text to the clipboard."
        case .insertTextAtCursor(_):
            "Inserts text into the terminal input at the cursor position."
        case .deleteCurrentLine(_):
            "Clears the current command line input (only at the prompt)."
        case .getManPage(_):
            "Returns the content of a command's man page."
        case .createFile:
            "Creates a file containing a specified string."
        }
    }
}

extension ChatAgent {
    func defineFunctions(in conversation: inout AIConversation,
                         allowedCategories: Set<RemoteCommand.Content.PermissionCategory>) {
        conversation.removeAllFunctions()
        for content in RemoteCommand.Content.allCases {
            guard allowedCategories.contains(content.permissionCategory) else {
                continue
            }
            switch content {
            case .isAtPrompt(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .isAtPrompt(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .executeCommand(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .executeCommand(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getLastExitStatus(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getLastExitStatus(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCommandHistory(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCommandHistory(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getLastCommand(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getLastCommand(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCommandBeforeCursor(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCommandBeforeCursor(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .searchCommandHistory(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .searchCommandHistory(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCommandOutput(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCommandOutput(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getTerminalSize(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getTerminalSize(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getShellType(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getShellType(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .detectSSHSession(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .detectSSHSession(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getRemoteHostname(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getRemoteHostname(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getUserIdentity(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getUserIdentity(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getCurrentDirectory(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getCurrentDirectory(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .setClipboard(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .setClipboard(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .insertTextAtCursor(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .insertTextAtCursor(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .deleteCurrentLine(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .deleteCurrentLine(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .getManPage(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .getManPage(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            case .createFile(let args):
                conversation.define(
                    function: ChatGPTFunctionDeclaration(
                        name: content.functionName,
                        description: content.functionDescription,
                        parameters: JSONSchema(for: args,
                                               descriptions: content.argDescriptions)),
                    arguments: type(of: args),
                    implementation: { [weak self] llmMessage, command, completion in
                        let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                          content: .createFile(command))
                        self?.runRemoteCommand(remoteCommand, completion: completion)
                    })
            }
        }
    }

    // MARK: - Function Calling Ingra

    private func renameChat(_ newName: String) {
        broker.publish(message: .init(chatID: chatID,
                                      author: .agent,
                                      content: .renameChat(newName),
                                      sentDate: Date(),
                                      uniqueID: UUID()),
                       toChatID: chatID,
                       partial: false)
    }

    private func runRemoteCommand(_ remoteCommand: RemoteCommand, completion: @escaping (Result<String, Error>) -> ()) {
        let requestID = UUID()
        pendingRemoteCommands[requestID] = completion
        broker.publish(message: .init(chatID: chatID,
                                      author: .agent,
                                      content: .remoteCommandRequest(remoteCommand),
                                      sentDate: Date(),
                                      uniqueID: requestID),
                       toChatID: chatID,
                       partial: false)
    }
}

extension Result where Failure == Error {
    // Upcast Result<Success,SpecificFailure> to Result<Success,Error>.
    init<SpecificFailure: Error>(_ result: Result<Success, SpecificFailure>) {
        self = result.mapError { $0 }
    }
}
