//
//  RemoteCommand.swift
//  iTerm2
//
//  Created by George Nachman on 8/18/25.
//

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
                    .readWebPage(ReadWebPage())
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

            var autopopulationTitle: String? {
                switch self {
                case .checkTerminalState:
                    "Provide Terminal State Automatically"
                case .runCommands, .viewHistory, .writeToClipboard, .typeForYou, .viewManpages,
                        .writeToFilesystem, .actInWebBrowser:
                    nil
                }
            }

            var autopopulationWarningText: String? {
                switch self {
                case .checkTerminalState:
                    "By setting this permission to “Always Allow”, terminal state will be sent automatically on every message you send in this chat.\nThis includes:\n • The current or last command and its exit status\n •The window size\n • Your shell\n • The current working directory, username, and hostname."
                case .runCommands, .viewHistory, .writeToClipboard, .typeForYou, .viewManpages,
                        .writeToFilesystem, .actInWebBrowser:
                    nil
                }
            }

            var regularTitle: String {
                "AI can \(rawValue)"
            }

            var autopopulatedWhenAlways: Bool {
                switch self {
                case .checkTerminalState:
                    true
                case .runCommands, .viewHistory, .writeToClipboard, .typeForYou, .viewManpages,
                        .writeToFilesystem, .actInWebBrowser:
                    false
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
            case .searchBrowser, .loadURL, .webSearch, .getURL, .readWebPage:
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
            }
        }
    }


    var llmMessage: LLM.Message
    var content: Content

    var needsSafetyCheck: Bool {
        if #unavailable(macOS 26) {
            return false
        }
        switch content {
        case .isAtPrompt, .getLastExitStatus, .getCommandHistory, .getLastCommand,
                .getCommandBeforeCursor, .searchCommandHistory, .getCommandOutput,
                .getTerminalSize, .getShellType, .detectSSHSession, .getRemoteHostname,
                .getUserIdentity, .getCurrentDirectory, .setClipboard,
                .deleteCurrentLine, .getManPage, .createFile, .searchBrowser,
                .loadURL, .webSearch, .getURL, .readWebPage, .insertTextAtCursor:
            return false
        case .executeCommand:
            return true
        }
    }

    @MainActor
    func isSafe() async -> Bool {
        switch content {
        case .isAtPrompt, .getLastExitStatus, .getCommandHistory, .getLastCommand,
                .getCommandBeforeCursor, .searchCommandHistory, .getCommandOutput,
                .getTerminalSize, .getShellType, .detectSSHSession, .getRemoteHostname,
                .getUserIdentity, .getCurrentDirectory, .setClipboard,
                .deleteCurrentLine, .getManPage, .createFile, .searchBrowser,
                .loadURL, .webSearch, .getURL, .readWebPage, .insertTextAtCursor:
            return true
        case .executeCommand(let command):
            if #available(macOS 26, *) {
                if AIAvailabilityProbe.check() {
                    let nagKey = "NoSyncAISafetyCheckNagComplete"
                    if UserDefaults.standard.object(forKey: kPreferenceKeyAISafetyCheck) == nil &&
                        !UserDefaults.standard.bool(forKey: nagKey) {
                        let selection = iTermWarning.show(
                            withTitle: "iTerm2 can use Apple Intelligence to check the safety of commands suggested by your AI agent. Would you like to enable safety checking?\n\nWhen enabled, commands may be sent to Apple’s servers for safety checking.",
                            actions: ["OK", "Cancel"],
                            accessory: nil,
                            identifier: nil,
                            silenceable: .kiTermWarningTypePersistent,
                            heading: "Enable Command Safety Checking?",
                            window: nil)
                        iTermPreferences.setBool(true, forKey: nagKey)
                        if selection == .kiTermWarningSelection0 {
                            iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)
                        }
                    }
                    if iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck) {
                        return await CommandSafetyChecker.check(command.command)
                    }
                }
            }
            return true
        }
    }

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
            "The AI agent would like to write to view the current web page"
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
                .webSearch, .getURL, .readWebPage:
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
        case .searchBrowser:
            "find_on_page"
        case .loadURL:
            "load_url"
        case .webSearch:
            "web_search_in_browser"
        case .getURL:
            "get_current_url"
        case .readWebPage:
            "read_web_page_section"
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
        case .searchBrowser(_):
            ["query": "The text to search for on the current page. Ensure you know which web page is currently loaded before using this."]
        case .loadURL(_):
            ["url": "The URL to load. Must use https scheme."]
        case .webSearch(_):
            ["query": "The web search query"]
        case .getURL(_):
            [:]
        case .readWebPage(_):
            ["startingLineNumber": "The line number to start reading at.",
             "numberOfLines": "The number of lines to return."]
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
            "Detects the shell in use (e.g., bash, fish, xonsh, zsh)."
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
            "Creates a file containing a specified string on the user's computer and then reveals it in Finder."
        case .loadURL:
            "Loads the specified URL in the associated web browser"
        case .webSearch:
            "Performs a web search using the currently configured search engine in the associated web browser"
        case .getURL:
            "Returns the current URL of the associated web browser"
        case .readWebPage:
            "Returns some of the content (in markdown format) of the page visible in the associated web browser."
        case .searchBrowser(_):
            "Searches the current web page in the associated web browser (after converting to markdown format) for a substring."
        }
    }

    func withValue(_ value: Any) -> RemoteCommand.Content {
        switch self {
        case .isAtPrompt: .isAtPrompt(value as! RemoteCommand.IsAtPrompt)
        case .executeCommand: .executeCommand(value as! RemoteCommand.ExecuteCommand)
        case .getLastExitStatus: .getLastExitStatus(value as! RemoteCommand.GetLastExitStatus)
        case .getCommandHistory: .getCommandHistory(value as! RemoteCommand.GetCommandHistory)
        case .getLastCommand: .getLastCommand(value as! RemoteCommand.GetLastCommand)
        case .getCommandBeforeCursor: .getCommandBeforeCursor(value as! RemoteCommand.GetCommandBeforeCursor)
        case .searchCommandHistory: .searchCommandHistory(value as! RemoteCommand.SearchCommandHistory)
        case .getCommandOutput: .getCommandOutput(value as! RemoteCommand.GetCommandOutput)
        case .getTerminalSize: .getTerminalSize(value as! RemoteCommand.GetTerminalSize)
        case .getShellType: .getShellType(value as! RemoteCommand.GetShellType)
        case .detectSSHSession: .detectSSHSession(value as! RemoteCommand.DetectSSHSession)
        case .getRemoteHostname: .getRemoteHostname(value as! RemoteCommand.GetRemoteHostname)
        case .getUserIdentity: .getUserIdentity(value as! RemoteCommand.GetUserIdentity)
        case .getCurrentDirectory: .getCurrentDirectory(value as! RemoteCommand.GetCurrentDirectory)
        case .setClipboard: .setClipboard(value as! RemoteCommand.SetClipboard)
        case .insertTextAtCursor: .insertTextAtCursor(value as! RemoteCommand.InsertTextAtCursor)
        case .deleteCurrentLine: .deleteCurrentLine(value as! RemoteCommand.DeleteCurrentLine)
        case .getManPage: .getManPage(value as! RemoteCommand.GetManPage)
        case .createFile: .createFile(value as! RemoteCommand.CreateFile)
        case .searchBrowser: .searchBrowser(value as! RemoteCommand.SearchBrowser)
        case .loadURL: .loadURL(value as! RemoteCommand.LoadURL)
        case .webSearch: .webSearch(value as! RemoteCommand.WebSearch)
        case .getURL: .getURL(value as! RemoteCommand.GetURL)
        case .readWebPage: .readWebPage(value as! RemoteCommand.ReadWebPage)
        }
    }
}
