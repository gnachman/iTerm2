//
//  ChatAgent.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/25.
//

fileprivate extension AITermController.Message {
    static func role(from message: Message) -> String {
        switch message.author {
        case .user: "user"
        case .agent: "assistant"
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
        case .explanationResponse(let annotations):
            return annotations.rawResponse
        case .explanationRequest:
            it_fatalError()
        case .remoteCommandRequest:
            return nil
        case .remoteCommandResponse, .selectSessionRequest, .clientLocal:
            it_fatalError()
        }
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
            case .explanationResponse:
                it_fatalError()
            case .remoteCommandResponse(let result, _, _):
                return result.map { value in
                    value
                } failure: { error in
                    "I was unable to complete the function call: " + error.localizedDescription
                }

            case .remoteCommandRequest, .selectSessionRequest, .clientLocal:
                it_fatalError()
            }
        case .initialExplanation:
            switch userMessage.content {
            case .plainText(let value), .markdown(let value):
                mode = .regular
                return AIExplanationRequest.conversationalPrompt(userPrompt: value)
            case .explanationResponse, .explanationRequest:
                it_fatalError()
            case .remoteCommandRequest, .remoteCommandResponse, .selectSessionRequest, .clientLocal:
                it_fatalError()
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

    init(_ chatID: String,
         broker: ChatBroker,
         registrationProvider: AIRegistrationProvider,
         messages: [Message]) {
        self.chatID = chatID
        self.broker = broker
        conversation = AIConversation(registrationProvider: registrationProvider)
        defineFunctions(&conversation)
        for message in messages {
            switch message.content {
            case .plainText, .markdown, .explanationRequest, .explanationResponse,
                    .remoteCommandRequest, .remoteCommandResponse:
                conversation.add(aiMessage(from: message))
                break

            case .selectSessionRequest, .clientLocal:
                break
            }
        }
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

    // TODO: I think we need to handle cancellations to keep the conversation correct.
    func fetchCompletion(userMessage: Message,
                         completion: @escaping (Message?) -> ()) {
        switch userMessage.content {
        case .plainText, .markdown, .explanationRequest, .explanationResponse,
                .remoteCommandRequest, .selectSessionRequest, .clientLocal:
            break
        case .remoteCommandResponse(let result, let messageID, let functionCallName):
            if let pending = pendingRemoteCommands[messageID] {
                NSLog("Agent handling remote command response to message \(messageID)")
                pendingRemoteCommands.removeValue(forKey: messageID)
                pending(Result(result))
                return
            }
        }

        conversation.add(aiMessage(from: userMessage))
        conversation.complete { result in
            if let updated = result.successValue {
                self.conversation = updated
            } else {
                self.conversation.messages.removeLast()
            }
            let message = Self.message(forResult: result, userMessage: userMessage)
            completion(message)
        }
    }

    // Return a new message from the agent containing the content of the last message in result.
    private static func message(forResult result: Result<AIConversation, any Error>,
                                userMessage: Message) -> Message? {
        return result.handle { updated -> Message? in
            guard let text = updated.messages.last!.content else {
                return nil
            }
            switch userMessage.content {
            case .plainText, .markdown, .explanationResponse:
                return Message(chatID: userMessage.chatID,
                               author: .agent,
                               content: .markdown(text),
                               sentDate: Date(),
                               uniqueID: UUID())
            case .explanationRequest(let explanationRequest):
                return Message(
                    chatID: userMessage.chatID,
                    author: .agent,
                    content: .explanationResponse(
                        AIAnnotationCollection(text, request: explanationRequest)),
                    sentDate: Date(),
                    uniqueID: UUID())
            case .remoteCommandResponse:
                return Message(chatID: userMessage.chatID,
                               author: .agent,
                               content: .markdown(text),
                               sentDate: Date(),
                               uniqueID: UUID())
            case .remoteCommandRequest, .selectSessionRequest, .clientLocal:
                it_fatalError()
            }
        } failure: { error in
            #warning("TODO: This code path will leave things in a broken state if it happens in the first two messages of an explanation")
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
}


extension Message {
    var isExplanationRequest: Bool {
        switch content {
        case .explanationRequest: true
        default: false
        }
    }
}

extension ChatAgent {
    // Moved struct definitions

    func defineFunctions(_ conversation: inout AIConversation) {
        // Command Execution & Inspection
        let schemaIsAtPrompt = JSONSchema(for: RemoteCommand.IsAtPrompt(), descriptions: [:])
        let declIsAtPrompt = ChatGPTFunctionDeclaration(
            name: "is_at_prompt",
            description: "Returns true if the terminal is at the command prompt, allowing safe command injection.",
            parameters: schemaIsAtPrompt
        )
        conversation.define(
            function: declIsAtPrompt,
            arguments: RemoteCommand.IsAtPrompt.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .isAtPrompt(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaExecuteCommand = JSONSchema(for: RemoteCommand.ExecuteCommand(), descriptions: ["command": "The command to run"])
        let declExecuteCommand = ChatGPTFunctionDeclaration(
            name: "execute_command",
            description: "Runs a shell command and returns its output.",
            parameters: schemaExecuteCommand
        )
        conversation.define(
            function: declExecuteCommand,
            arguments: RemoteCommand.ExecuteCommand.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .executeCommand(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetLastExitStatus = JSONSchema(for: RemoteCommand.GetLastExitStatus(), descriptions: [:])
        let declGetLastExitStatus = ChatGPTFunctionDeclaration(
            name: "get_last_exit_status",
            description: "Retrieves the exit status of the last executed command.",
            parameters: schemaGetLastExitStatus
        )
        conversation.define(
            function: declGetLastExitStatus,
            arguments: RemoteCommand.GetLastExitStatus.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getLastExitStatus(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetCommandHistory = JSONSchema(for: RemoteCommand.GetCommandHistory(), descriptions: ["limit": "Maximum number of history items to return."])
        let declGetCommandHistory = ChatGPTFunctionDeclaration(
            name: "get_command_history",
            description: "Returns the recent command history.",
            parameters: schemaGetCommandHistory
        )
        conversation.define(
            function: declGetCommandHistory,
            arguments: RemoteCommand.GetCommandHistory.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getCommandHistory(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetLastCommand = JSONSchema(for: RemoteCommand.GetLastCommand(), descriptions: [:])
        let declGetLastCommand = ChatGPTFunctionDeclaration(
            name: "get_last_command",
            description: "Retrieves the most recent command.",
            parameters: schemaGetLastCommand
        )
        conversation.define(
            function: declGetLastCommand,
            arguments: RemoteCommand.GetLastCommand.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getLastCommand(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetCommandBeforeCursor = JSONSchema(for: RemoteCommand.GetCommandBeforeCursor(), descriptions: [:])
        let declGetCommandBeforeCursor = ChatGPTFunctionDeclaration(
            name: "get_command_before_cursor",
            description: "Returns the current partially typed command before the cursor.",
            parameters: schemaGetCommandBeforeCursor
        )
        conversation.define(
            function: declGetCommandBeforeCursor,
            arguments: RemoteCommand.GetCommandBeforeCursor.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getCommandBeforeCursor(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaSearchCommandHistory = JSONSchema(for: RemoteCommand.SearchCommandHistory(), descriptions: ["query": "Search query for filtering command history."])
        let declSearchCommandHistory = ChatGPTFunctionDeclaration(
            name: "search_command_history",
            description: "Searches history for commands matching a query.",
            parameters: schemaSearchCommandHistory
        )
        conversation.define(
            function: declSearchCommandHistory,
            arguments: RemoteCommand.SearchCommandHistory.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .searchCommandHistory(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetCommandOutput = JSONSchema(for: RemoteCommand.GetCommandOutput(), descriptions: ["id": "Unique identifier of the command whose output is requested."])
        let declGetCommandOutput = ChatGPTFunctionDeclaration(
            name: "get_command_output",
            description: "Returns the output of a previous command by its unique identifier.",
            parameters: schemaGetCommandOutput
        )
        conversation.define(
            function: declGetCommandOutput,
            arguments: RemoteCommand.GetCommandOutput.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getCommandOutput(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetTerminalSize = JSONSchema(for: RemoteCommand.GetTerminalSize(), descriptions: [:])
        let declGetTerminalSize = ChatGPTFunctionDeclaration(
            name: "get_terminal_size",
            description: "Returns (columns, rows) of the terminal window.",
            parameters: schemaGetTerminalSize
        )
        conversation.define(
            function: declGetTerminalSize,
            arguments: RemoteCommand.GetTerminalSize.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getTerminalSize(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetShellType = JSONSchema(for: RemoteCommand.GetShellType(), descriptions: [:])
        let declGetShellType = ChatGPTFunctionDeclaration(
            name: "get_shell_type",
            description: "Detects the shell in use (e.g., bash, zsh, fish).",
            parameters: schemaGetShellType
        )
        conversation.define(
            function: declGetShellType,
            arguments: RemoteCommand.GetShellType.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getShellType(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaDetectSSHSession = JSONSchema(for: RemoteCommand.DetectSSHSession(), descriptions: [:])
        let declDetectSSHSession = ChatGPTFunctionDeclaration(
            name: "detect_ssh_session",
            description: "Returns true if the user is SSH’ed into a remote host.",
            parameters: schemaDetectSSHSession
        )
        conversation.define(
            function: declDetectSSHSession,
            arguments: RemoteCommand.DetectSSHSession.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .detectSSHSession(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetRemoteHostname = JSONSchema(for: RemoteCommand.GetRemoteHostname(), descriptions: [:])
        let declGetRemoteHostname = ChatGPTFunctionDeclaration(
            name: "get_remote_hostname",
            description: "Retrieves the remote hostname if in an SSH session.",
            parameters: schemaGetRemoteHostname
        )
        conversation.define(
            function: declGetRemoteHostname,
            arguments: RemoteCommand.GetRemoteHostname.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getRemoteHostname(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetUserIdentity = JSONSchema(for: RemoteCommand.GetUserIdentity(), descriptions: [:])
        let declGetUserIdentity = ChatGPTFunctionDeclaration(
            name: "get_user_identity",
            description: "Returns the logged-in user’s username.",
            parameters: schemaGetUserIdentity
        )
        conversation.define(
            function: declGetUserIdentity,
            arguments: RemoteCommand.GetUserIdentity.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getUserIdentity(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetCurrentDirectory = JSONSchema(for: RemoteCommand.GetCurrentDirectory(), descriptions: [:])
        let declGetCurrentDirectory = ChatGPTFunctionDeclaration(
            name: "get_current_directory",
            description: "Returns the current directory.",
            parameters: schemaGetCurrentDirectory
        )
        conversation.define(
            function: declGetCurrentDirectory,
            arguments: RemoteCommand.GetCurrentDirectory.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getCurrentDirectory(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaSetClipboard = JSONSchema(for: RemoteCommand.SetClipboard(), descriptions: ["text": "The text to copy to the clipboard."])
        let declSetClipboard = ChatGPTFunctionDeclaration(
            name: "set_clipboard",
            description: "Copies text to the clipboard.",
            parameters: schemaSetClipboard
        )
        conversation.define(
            function: declSetClipboard,
            arguments: RemoteCommand.SetClipboard.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .setClipboard(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaInsertTextAtCursor = JSONSchema(for: RemoteCommand.InsertTextAtCursor(), descriptions: ["text": "The text to insert at the cursor position."])
        let declInsertTextAtCursor = ChatGPTFunctionDeclaration(
            name: "insert_text_at_cursor",
            description: "Inserts text into the terminal input at the cursor position.",
            parameters: schemaInsertTextAtCursor
        )
        conversation.define(
            function: declInsertTextAtCursor,
            arguments: RemoteCommand.InsertTextAtCursor.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .insertTextAtCursor(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaDeleteCurrentLine = JSONSchema(for: RemoteCommand.DeleteCurrentLine(), descriptions: [:])
        let declDeleteCurrentLine = ChatGPTFunctionDeclaration(
            name: "delete_current_line",
            description: "Clears the current command line input (only at the prompt).",
            parameters: schemaDeleteCurrentLine
        )
        conversation.define(
            function: declDeleteCurrentLine,
            arguments: RemoteCommand.DeleteCurrentLine.self,
            implementation: { [weak self] llmMessage, command, completion in
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .deleteCurrentLine(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )

        let schemaGetManPage = JSONSchema(for: RemoteCommand.GetManPage(), descriptions: ["cmd": "The command whose man page content is requested."])
        let declGetManPage = ChatGPTFunctionDeclaration(
            name: "get_man_page",
            description: "Returns the content of a command's man page.",
            parameters: schemaGetManPage
        )
        conversation.define(
            function: declGetManPage,
            arguments: RemoteCommand.GetManPage.self,
            implementation: { [weak self] llmMessage, command, completion in
                NSLog("Completion block running for \(command)")
                self?.willExecuteCommand()
                let remoteCommand = RemoteCommand(llmMessage: llmMessage, content: .getManPage(command))
                self?.runRemoteCommand(remoteCommand) { result in
                    self?.didExecuteCommand()
                    completion(result)
                }
            }
        )
    }
    // MARK: - Function Calling Ingra

    private func willExecuteCommand() {
    }

    private func didExecuteCommand() {
    }

    private func runRemoteCommand(_ remoteCommand: RemoteCommand, completion: @escaping (Result<String, Error>) -> ()) {
        let requestID = UUID()
        pendingRemoteCommands[requestID] = completion
        #warning("TODO: It would be nice if AIConversation serialized half-completed function calls so it could be continued after a restart")
        broker.publish(message: .init(chatID: chatID,
                                      author: .agent,
                                      content: .remoteCommandRequest(remoteCommand),
                                      sentDate: Date(),
                                      uniqueID: requestID),
                       toChatID: chatID)
    }
}

extension Result where Failure == Error {
    // Upcast Result<Success,SpecificFailure> to Result<Success,Error>.
    init<SpecificFailure: Error>(_ result: Result<Success, SpecificFailure>) {
        self = result.mapError { $0 }
    }
}
