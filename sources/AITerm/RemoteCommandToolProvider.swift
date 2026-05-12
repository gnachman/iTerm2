//
//  RemoteCommandToolProvider.swift
//  iTerm2SharedARC
//

import Foundation

// Tool provider for AITerm's single-session-bound chat surface.
// Wraps the RemoteCommand.Content enum's 28 tool cases as
// ChatGPTFunctionDeclarations, filtered by the chat's current
// permission set, and routes each invocation back through a
// dispatcher closure the agent supplies. Pulled out of ChatAgent so
// the agent's tool wiring is one delegation rather than a 60-line
// switch-on-enum inside the agent class.
final class RemoteCommandToolProvider: ToolProvider {
    typealias Dispatcher = (RemoteCommand, String?, @escaping (Result<String, Error>) throws -> ()) throws -> ()

    // Closure that produces the chat's currently-allowed permission
    // categories. Resolved each time registerTools runs so a
    // permission change picks up the new set on the next register.
    private let allowedCategories: () -> Set<RemoteCommand.Content.PermissionCategory>

    // Per-call dispatcher. The provider passes the LLM-decoded
    // RemoteCommand plus the response ID and a completion the LLM
    // framework parks on; the agent does the broker round-trip and
    // resumes the completion when the user side responds.
    private let dispatcher: Dispatcher

    init(allowedCategories: @escaping () -> Set<RemoteCommand.Content.PermissionCategory>,
         dispatcher: @escaping Dispatcher) {
        self.allowedCategories = allowedCategories
        self.dispatcher = dispatcher
    }

    func registerTools(on conversation: inout AIConversation) {
        let permissions = allowedCategories()
        for content in RemoteCommand.Content.allCases {
            guard permissions.contains(content.permissionCategory) else {
                continue
            }
            switch content {
            case .isAtPrompt(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .executeCommand(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getLastExitStatus(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCommandHistory(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getLastCommand(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCommandBeforeCursor(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .searchCommandHistory(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCommandOutput(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getTerminalSize(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getShellType(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .detectSSHSession(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getRemoteHostname(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getUserIdentity(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getCurrentDirectory(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .setClipboard(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .insertTextAtCursor(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .deleteCurrentLine(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getManPage(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .createFile(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .searchBrowser(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .loadURL(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .webSearch(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .getURL(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            case .readWebPage(let prototype):
                define(in: &conversation, content: content, prototype: prototype)
            }
        }
    }

    private func define<T: Codable>(in conversation: inout AIConversation,
                                    content: RemoteCommand.Content,
                                    prototype: T) {
        let f = ChatGPTFunctionDeclaration(
            name: content.functionName,
            description: content.functionDescription,
            parameters: JSONSchema(for: prototype,
                                   descriptions: content.argDescriptions))
        let argsType = type(of: prototype)
        let dispatcher = self.dispatcher
        conversation.define(
            function: f,
            arguments: argsType) { llmMessage, command, completion in
                let remoteCommand = RemoteCommand(llmMessage: llmMessage,
                                                  content: content.withValue(command))
                try dispatcher(remoteCommand, llmMessage.responseID, completion)
            }
    }
}
