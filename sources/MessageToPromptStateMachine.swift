//
//  MessageToPromptStateMachine.swift
//  iTerm2
//
//  Created by George Nachman on 8/18/25.
//

struct MessageToPromptStateMachine {
    private enum Mode {
        case regular
        case initialExplanation
    }
    private var mode = Mode.regular

    mutating func body(message: Message) -> LLM.Message.Body {
        switch message.author {
        case .agent:
            body(agentMessage: message)
        case .user:
            body(userMessage: message)
        }
    }

    private mutating func body(agentMessage: Message) -> LLM.Message.Body {
        switch agentMessage.content {
        case .plainText(let value, context: _), .markdown(let value):
            return .text(value)
        case .explanationResponse(let annotations, _, _):
            return .text(annotations.rawResponse)
        case .remoteCommandRequest(let request):
            if let call = request.llmMessage.function_call {
                return .functionCall(call,
                                     id: request.llmMessage.functionCallID)
            } else {
                return .uninitialized
            }
        case .remoteCommandResponse, .selectSessionRequest, .clientLocal, .renameChat, .append,
                .commit, .setPermissions, .vectorStoreCreated, .terminalCommand, .appendAttachment,
                .explanationRequest, .userCommand:
            it_fatalError()
        case .multipart(let subparts, _):
            return .multipart(subparts.compactMap { subpart -> LLM.Message.Body? in
                switch subpart {
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let code):
                        return .text(code)
                    case .statusUpdate:
                        return nil
                    case .file, .fileID:
                        return .attachment(attachment)
                    }
                case .markdown(let string), .plainText(let string):
                    return .text(string)
                case .context:
                    it_fatalError()
                }
            })
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

    private mutating func body(userMessage: Message) -> LLM.Message.Body {
        switch userMessage.content {
        case .plainText(let value, context: let context):
            defer {
                mode = .regular
            }
            switch mode {
            case .regular:
                return .text(value + (context.map { "\n" + $0 } ?? ""))
            case .initialExplanation:
                return .text(AIExplanationRequest.conversationalPrompt(userPrompt: value))
            }
        case .explanationRequest(let request):
            mode = .initialExplanation
            return .text(request.prompt())
        case .multipart(let subparts, _):
            var parts = subparts.compactMap { subpart -> LLM.Message.Body? in
                switch subpart {
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let code):
                        return .text(code)
                    case .statusUpdate:
                        return nil
                    case .file, .fileID:
                        return .attachment(attachment)
                    }
                case .markdown(let string), .plainText(let string), .context(let string):
                    return .text(string)
                }
            }
            if parts.contains(where: { $0.isAttachment}),
               let i = parts.firstIndex(where: { $0.isText }) {
                parts[i].prepend("I have attached files for you to use.\n")
            }
            return .multipart(parts)
        case .remoteCommandResponse(let result, _, let functionName, let functionCallID):
            let output = result.map { value in
                value
            } failure: { error in
                "I was unable to complete the function call: " + error.localizedDescription
            }
            return .functionOutput(name: functionName,
                                   output: output,
                                   id: functionCallID)
        case .terminalCommand(let cmd):
            return .text(prompt(terminalCommand: cmd))
        case .explanationResponse, .append, .appendAttachment, .remoteCommandRequest,
                .selectSessionRequest, .clientLocal, .renameChat, .commit, .setPermissions,
                .vectorStoreCreated, .userCommand, .markdown:
            it_fatalError()
        }
    }
}

extension Message.Subpart {
    var isFileAttachment: Bool {
        switch self {
        case .attachment(let attachment):
            switch attachment.type {
            case .file, .fileID:
                true
            case .code, .statusUpdate:
                false
            }
        case .plainText, .markdown, .context:
            false
        }
    }
}

extension LLM.Message.Body {
    var isAttachment: Bool {
        switch self {
        case .attachment: true
        case .uninitialized, .text, .functionCall, .functionOutput, .multipart: false
        }
    }
    var isText: Bool {
        switch self {
        case .text: true
        case .attachment, .uninitialized, .functionCall, .functionOutput, .multipart: false
        }
    }
    mutating func prepend(_ string: String)  {
        it_assert(isText)
        if case .text(let text) = self {
            self = .text(string + text)
        }
    }
}
