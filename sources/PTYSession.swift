//
//  PTYSession.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import WebKit

// MARK: - AI Chat
extension PTYSession {
    func add(aiAnnotations annotations: [AITermAnnotation],
             baseOffset: Int64,
             locatedString: iTermLocatedString) -> [URL?] {
        let width = screen.width()
        let offset = baseOffset - screen.totalScrollbackOverflow()
        var urls = [URL?]()
        for aiAnnotation in annotations {
            let y = Int64(aiAnnotation.run.origin.y) + offset
            guard y >= 0 else {
                urls.append(nil)
                continue
            }
            let note = PTYAnnotation()
            note.stringValue = aiAnnotation.note
            var end = aiAnnotation.run.origin
            end.x += aiAnnotation.run.length - 1
            if end.x >= width {
                end.y += end.x / width
                end.x %= width
            }
            end.x += 1
            let range = VT100GridCoordRangeMake(aiAnnotation.run.origin.x,
                                                aiAnnotation.run.origin.y,
                                                end.x,
                                                end.y)
            // Don't make them visible because it becomes total chaos if there are a lot of them.
            screen.addNote(note, in: range, focus: false, visible: false)
            urls.append(url(annotation: note.uniqueID))
        }
        return urls
    }

    @objc func revealAnnotation(_ id: String) {
        screen.enumerateObservableMarks { type, line, obj in
            guard type == .annotation, let note = obj as? PTYAnnotationReading, note.uniqueID == id else {
                return
            }
            textview.scrollLineNumberRange(
                intoView: VT100GridRangeMake(Int32(Int64(line) - screen.totalScrollbackOverflow()), 1))
            highlightMarkOrNote(obj)
        }
    }

    private func url(annotation: String) -> URL? {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "annotation"
        components.queryItems = [URLQueryItem(name: "ann", value: annotation),
                                 URLQueryItem(name: "s", value: guid)]
        return components.url
    }

    @objc(urlForPromptMark:)
    func promptMarkURL(mark: VT100ScreenMarkReading) -> URL {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "reveal-mark"
        var items = [URLQueryItem]()
        items.append(URLQueryItem(name: "s", value: guid))
        items.append(URLQueryItem(name: "m", value: mark.guid))
        components.queryItems = items
        return components.url!
    }

    private func url(_ selection: iTermSelection, in snapshot: TerminalContentSnapshot) -> URL? {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "/compound-location"
        var items = [URLQueryItem]()
        items.append(URLQueryItem(name: "session", value: guid))
        let overflow = screen.totalScrollbackOverflow()
        for sub in selection.allSubSelections {
            let coordRange = VT100GridCoordRangeFromAbsCoordRange(sub.absRange.coordRange, overflow)
            if coordRange.start.y < 0 {
                continue
            }
            guard let start = snapshot.lineBuffer.position(forCoordinate: coordRange.start,
                                                           width: screen.width(),
                                                           offset: 0) else {
                continue
            }
            guard let end = snapshot.lineBuffer.position(forCoordinate: coordRange.end,
                                                         width: screen.width(),
                                                         offset: 0) else {
                continue
            }
            let location = sub.absRange.columnWindow.location
            let length = sub.absRange.columnWindow.length
            let info = SubSelectionSerializationInfo(
                mode: sub.selectionMode.rawValue,
                start: start,
                end: end,
                windowedRange: location..<(location + length))
            items.append(URLQueryItem(name: "sub", value: info.queryValue))
        }
        components.queryItems = items
        return components.url
    }

    @objc(explainSelectionWithAI:truncated:snapshot:command:subjectMatter:title:error:)
    func explainWithAI(selection: iTermSelection,
                       truncated: Bool,
                       snapshot: TerminalContentSnapshot,
                       command: String?,
                       subjectMatter: String,
                       title: String) throws {
        let request = AIExplanationRequest(command: command,
                                           snapshot: snapshot,
                                           selection: selection,
                                           truncated: truncated,
                                           question: "",
                                           subjectMatter: subjectMatter,
                                           url: url(selection, in: snapshot),
                                           context: AIExplanationRequest.Context(
                                            sessionID: guid,
                                            baseOffset: screen.totalScrollbackOverflow()))
        guard let client = ChatClient.instance else {
            iTermWarning.show(withTitle: "AI Chat could not be opened. Verify you only have one instance of iTerm2 running.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Error",
                              window: self.genericView.window)
            return
        }
        try client.explain(request,
                           title: title,
                           scope: genericScope)
    }

    struct NotABrowserError: LocalizedError {
        var errorDescription: String? { "The associated session is a terminal emulator, not a web browser" }
    }
    struct NotATerminalError: LocalizedError {
        var errorDescription: String? { "The associated session is a web browser, not a terminal emulator" }
    }

    func ensureIsTerminal() throws {
        if isBrowserSession() {
            throw NotATerminalError()
        }
    }

    func ensureIsBrowser() throws {
        if !isBrowserSession() {
            throw NotABrowserError()
        }
    }

    func execute(_ command: RemoteCommand, completion: @escaping (String, String) throws -> ()) throws {
        DLog("\(command)")
        cancelRemoteCommand()
        switch command.content {
        case .isAtPrompt(let isAtPrompt):
            try ensureIsTerminal()
            try isAtPromptRemoteCommand(isAtPrompt: isAtPrompt,
                                        completion: completion)
        case .executeCommand(let executeCommand):
            try ensureIsTerminal()
            try executeCommandRemoteCommand(executeCommand: executeCommand,
                                            completion: completion)
        case .getLastExitStatus(let getLastExitStatus):
            try ensureIsTerminal()
            try getLastExitStatusRemoteCommand(getLastExitStatus: getLastExitStatus,
                                               completion: completion)
        case .getCommandHistory(let getCommandHistory):
            try ensureIsTerminal()
            try getCommandHistoryRemoteCommand(getCommandHistory: getCommandHistory,
                                               completion: completion)
        case .getLastCommand(let getLastCommand):
            try ensureIsTerminal()
            try getLastCommandRemoteCommand(getLastCommand: getLastCommand,
                                            completion: completion)
        case .getCommandBeforeCursor(let getCommandBeforeCursor):
            try ensureIsTerminal()
            try getCommandBeforeCursorRemoteCommand(getCommandBeforeCursor: getCommandBeforeCursor,
                                                    completion: completion)
        case .searchCommandHistory(let searchCommandHistory):
            try ensureIsTerminal()
            try searchCommandHistoryRemoteCommand(searchCommandHistory: searchCommandHistory,
                                                  completion: completion)
        case .getCommandOutput(let getCommandOutput):
            try ensureIsTerminal()
            try getCommandOutputRemoteCommand(getCommandOutput: getCommandOutput,
                                              completion: completion)
        case .getTerminalSize(let getTerminalSize):
            try ensureIsTerminal()
            try getTerminalSizeRemoteCommand(getTerminalSize: getTerminalSize,
                                             completion: completion)
        case .getShellType(let getShellType):
            try ensureIsTerminal()
            try getShellTypeRemoteCommand(getShellType: getShellType,
                                          completion: completion)
        case .detectSSHSession(let detectSSHSession):
            try ensureIsTerminal()
            try detectSSHSessionRemoteCommand(detectSSHSession: detectSSHSession,
                                              completion: completion)
        case .getRemoteHostname(let getRemoteHostname):
            try ensureIsTerminal()
            try getRemoteHostnameRemoteCommand(getRemoteHostname: getRemoteHostname,
                                               completion: completion)
        case .getUserIdentity(let getUserIdentity):
            try ensureIsTerminal()
            try getUserIdentityRemoteCommand(getUserIdentity: getUserIdentity,
                                             completion: completion)
        case .getCurrentDirectory(let getCurrentDirectory):
            try ensureIsTerminal()
            try getCurrentDirectoryRemoteCommand(getCurrentDirectory: getCurrentDirectory,
                                                 completion: completion)
        case .setClipboard(let setClipboard):
            try ensureIsTerminal()
            try setClipboardRemoteCommand(setClipboard: setClipboard,
                                          completion: completion)
        case .insertTextAtCursor(let insertTextAtCursor):
            try ensureIsTerminal()
            try insertTextAtCursorRemoteCommand(insertTextAtCursor: insertTextAtCursor,
                                                completion: completion)
        case .deleteCurrentLine(let deleteCurrentLine):
            try ensureIsTerminal()
            try deleteCurrentLineRemoteCommand(deleteCurrentLine: deleteCurrentLine,
                                               completion: completion)
        case .getManPage(let getManPage):
            try ensureIsTerminal()
            try getManPageRemoteCommand(getManPage: getManPage,
                                        completion: completion)
        case .createFile(let createFile):
            try ensureIsTerminal()
            try createFileCommand(createFile: createFile,
                                  completion: completion)
        case .searchBrowser(let args):
            try ensureIsBrowser()
            try searchBrowser(args: args, completion: completion)
        case .loadURL(let args):
            try ensureIsBrowser()
            try loadURL(args: args, completion: completion)
        case .webSearch(let args):
            try ensureIsBrowser()
            try webSearch(args: args, completion: completion)
        case .getURL(let args):
            try ensureIsBrowser()
            try getURL(args: args, completion: completion)
        case .readWebPage(let args):
            try ensureIsBrowser()
            try readWebPage(args: args, completion: completion)
        }
    }
}

// MARK: - Remote commands

class OneTimeStringClosure {
    private var closure: ((String) -> ())?

    init(_ closure: @escaping (String) -> ()) {
        self.closure = closure
    }

    func call(_ string: String) {
        if let closure {
            self.closure = nil
            closure(string)
        }
    }
}

@objc(iTermRunningRemoteCommand)
class RunningRemoteCommand: NSObject {
    enum State {
        case expectation(iTermExpectation, (String) -> ())
        case futureString(OneTimeStringClosure)
        case waitingForMark(UUID, OneTimeStringClosure)
        case none
    }
    var state = State.none
}

extension PTYSession {
    func cancelRemoteCommand() {
        let previousState = runningRemoteCommand.state
        runningRemoteCommand.state = .none
        switch previousState {
        case .expectation(let expectation, let completion):
            expect.cancelExpectation(expectation)
            completion("The function call was canceled by user request.")
        case .futureString(let otsc):
            otsc.call("The function call was canceled by user request.")
        case .waitingForMark(_, let otsc):
            screen.pause(atNextPrompt: nil)
            otsc.call("The function call was canceled by user request.")
        case .none:
            break
        }
    }

    var isExecutingRemoteCommand: Bool {
        switch runningRemoteCommand.state {
        case .none:
            false
        default:
            true
        }
    }

    func isAtPromptRemoteCommand(isAtPrompt: RemoteCommand.IsAtPrompt,
                                 completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.", "Failed to check if you’re at the prompt because Shell Integration is not installed.")
            return
        }
        try completion(currentCommand != nil ? "true" : "false", "Notified AI that you are \(currentCommand != nil ? "at" : "not at") the a prompt.")
    }

    func executeCommandRemoteCommand(executeCommand: RemoteCommand.ExecuteCommand,
                                     completion: @escaping (String, String) throws -> ()) rethrows {
        if !iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() || currentCommand == nil {
            try jankyExecuteCommand(executeCommand, completion: completion)
        } else {
            try goodExecuteCommand(executeCommand, completion: completion)
        }
    }

    private func goodExecuteCommand(_ executeCommand: RemoteCommand.ExecuteCommand,
                                    completion: @escaping (String, String) throws -> ()) rethrows {
        let start = Int64(screen.numberOfScrollbackLines() + screen.cursorY() - 1) + screen.totalScrollbackOverflow()
        let uuid = UUID()
        let otsc = OneTimeStringClosure { message in
            try? completion(message, "Ran \(executeCommand.command)")
        }
        runningRemoteCommand.state = .waitingForMark(uuid, otsc)
        writeTaskNoBroadcast(executeCommand.command + "\r")
        screen.pause { [weak self] in
            if let self,
               case .waitingForMark(let current, _) = self.runningRemoteCommand.state,
               current == uuid {
                self.runningRemoteCommand.state = .none
                if let content = contentAfter(start) {
                    otsc.call(content)
                }
            }
        }
    }

    private func jankyExecuteCommand(_ executeCommand: RemoteCommand.ExecuteCommand,
                                     completion: @escaping (String, String) throws -> ()) rethrows {
        let uuid = UUID().uuidString
        let start = Int64(screen.numberOfScrollbackLines() + screen.cursorY() - 1) + screen.totalScrollbackOverflow()
        writeTaskNoBroadcast(executeCommand.command + ";echo '-- FINISHED' \(uuid)\r")
        let expectation = addExpectation("^-- FINISHED \(uuid)", after: nil, deadline: nil, willExpect: nil) { [weak self] _ in
            self?.runningRemoteCommand.state = .none
            if var content = self?.contentAfter(start) {
                let ranges = content.ranges(of: uuid)
                if ranges.count == 2 {
                    // Normal case
                    content = String(content[ranges[0].upperBound..<ranges[1].lowerBound])
                    content.removeSuffix("-- FINISHED ")
                    try? completion(content, "Ran \(executeCommand.command)")
                } else {
                    // Something weird happened, probably the start fell off the end of scrollback history.
                    try? completion(
                        content
                            .replacingOccurrences(of: "-- FINISHED \(uuid)",
                                                  with: "")
                            .replacingOccurrences(of: uuid,
                                                  with: ""),
                        "Ran \(executeCommand.command) but its output could not be located. Did you run out of scrollback history lines?")
                }
            } else {
                try? completion("The executeCommand function call failed because the output of the command is not available. The buffer may have been cleared or some other technical issue occurred.",
                                "Ran \(executeCommand.command) but its output was unavailable. Did you run out of scrollback history lines?")
            }
        }
        runningRemoteCommand.state = .expectation(expectation, { output in
            try? completion(output, "Ran \(executeCommand.command)")}
        )
    }

    private func contentAfter(_ absLine: Int64) -> String? {
        let extractor = iTermTextExtractor(dataSource: screen)
        let end = Int64(screen.numberOfScrollbackLines() + screen.cursorY() - 1) + screen.totalScrollbackOverflow()
        let range = VT100GridCoordRangeFromAbsCoordRange(VT100GridAbsCoordRangeMake(0, absLine, screen.width(), end),
                                                         screen.totalScrollbackOverflow())
        let content = extractor.content(in: VT100GridWindowedRangeMake(range, 0, 0),
                          attributeProvider: nil,
                          nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                          pad: false,
                          includeLastNewline: false,
                          trimTrailingWhitespace: true,
                          cappedAtSize: -1,
                          truncateTail: false,
                          continuationChars: nil,
                          coords: nil)
        return content as? String
    }

    func getLastExitStatusRemoteCommand(getLastExitStatus: RemoteCommand.GetLastExitStatus,
                                        completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
                       "Failed to get the last command’s exit status because shell integration is not installed.")
            return
        }
        guard let promise = screen.lastCommandMark()?.returnCodePromise, let value = promise.maybeValue  else {
            try completion("The last command is still running and has not exited yet.",
                       "The last command seems to still be running so its exit status cannot be retrieved.")
            return
        }
        try completion(value.stringValue, "The exit status of the last command provided to AI.")
    }

    func getCommandHistoryRemoteCommand(getCommandHistory: RemoteCommand.GetCommandHistory,
                                        completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
                       "Command history isn’t available because Shell Integration isn’t installed.")
            return
        }
        var commands = [String]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark?.command {
                commands.append(command)
            }
        }
        try completion(commands.joined(separator: "\n"), "Command history provided to AI.")
    }

    func getLastCommandRemoteCommand(getLastCommand: RemoteCommand.GetLastCommand,
                                     completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
                       "The last command execute can’t be provided because Shell Integration isn’t installed.")
            return
        }
        guard let command = screen.lastCommandMark()?.command else {
            try completion("There are no previous command in history", "No previous command is available in this session}s history.")
            return
        }
        try completion(command, "Last command provided to AI.")
    }

    func getCommandBeforeCursorRemoteCommand(getCommandBeforeCursor: RemoteCommand.GetCommandBeforeCursor,
                                             completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
            "The contents of the shell prompt could not be determined because Shell Integration isn’t installed.")
            return
        }
        guard let currentCommandUpToCursor else {
            try completion("The user is not at the prompt.",
            "The contents of the shell prompt could not be provided because it appears the session is not currently at a prompt.")
            return
        }
        #warning("TODO: Test this")
        try completion(currentCommandUpToCursor, "Current command provided to AI.")

    }

    func searchCommandHistoryRemoteCommand(searchCommandHistory: RemoteCommand.SearchCommandHistory,
                                           completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
                       "Command history is not available because Shell Integration isn’t installed.")
            return
        }
        var commands = [String]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark?.command, command.contains(searchCommandHistory.query) {
                commands.append(command)
            }
        }
        try completion(commands.joined(separator: "\n"), "Command history provided to AI.")
    }

    func getCommandOutputRemoteCommand(getCommandOutput: RemoteCommand.GetCommandOutput,
                                       completion: @escaping (String, String) throws -> ()) rethrows {
        let absRange = textViewRangeOfLastCommandOutput()
        let range = VT100GridCoordRangeFromAbsCoordRange(absRange, screen.totalScrollbackOverflow())
        if range.start.x < 0 {
            try completion("The output is no longer available.", "The output of the last command wasn’t provided because it is no longer available.")
            return
        }
        let extractor = iTermTextExtractor(dataSource: screen)
        let content = extractor.content(in: VT100GridWindowedRangeMake(range, 0, 0),
                          attributeProvider: nil,
                          nullPolicy: .kiTermTextExtractorNullPolicyFromLastToEnd,
                          pad: false,
                          includeLastNewline: false,
                          trimTrailingWhitespace: true,
                          cappedAtSize: 16384,
                          truncateTail: false,
                          continuationChars: nil,
                          coords: nil)
        if let string = content as? String {
            try completion(string, "Last command’s output provided to AI.")
        } else {
            try completion("The content could not be retrieved because of an unexpected error",
            "The output of the last command wasn’t provided because of an unexpected error.")
        }
    }

    func getTerminalSizeRemoteCommand(getTerminalSize: RemoteCommand.GetTerminalSize,
                                      completion: @escaping (String, String) throws -> ()) rethrows {
        try completion("\(screen.width()) columns wide by \(screen.height()) rows tall",
                   "Session size provided to AI.")
    }

    func getShellTypeRemoteCommand(getShellType: RemoteCommand.GetShellType,
                                   completion: @escaping (String, String) throws -> ()) rethrows {
        try completion(genericScope.stringValue(forVariableName: iTermVariableKeyShell),
                   "Shell type provided to AI")
    }

    func detectSSHSessionRemoteCommand(detectSSHSession: RemoteCommand.DetectSSHSession,
                                       completion: @escaping (String, String) throws -> ()) rethrows {
        let value = screen.lastRemoteHost()?.isLocalhost ?? false
        try completion("\(value)", "SSH status provided to AI.")
    }

    func getRemoteHostnameRemoteCommand(getRemoteHostname: RemoteCommand.GetRemoteHostname,
                                        completion: @escaping (String, String) throws -> ()) rethrows {
        try completion(screen.lastRemoteHost()?.hostname ?? "Unknown",
                   "Hostname provided to AI")
    }

    func getUserIdentityRemoteCommand(getUserIdentity: RemoteCommand.GetUserIdentity,
                                      completion: @escaping (String, String) throws -> ()) rethrows {
        try completion(screen.lastRemoteHost()?.username ?? NSUserName(),
                   "User name provided to AI.")
    }

    func getCurrentDirectoryRemoteCommand(getCurrentDirectory: RemoteCommand.GetCurrentDirectory,
                                          completion: @escaping (String, String) throws -> ()) rethrows {
        try completion(genericScope.stringValue(forVariableName: iTermVariableKeySessionPath),
                   "Current directory provided to AI.")
    }

    func setClipboardRemoteCommand(setClipboard: RemoteCommand.SetClipboard,
                                   completion: @escaping (String, String) throws -> ()) rethrows {
        NSPasteboard.general.declareTypes([.string], owner: NSApp)
        NSPasteboard.general.setString(setClipboard.text, forType: .string)
        try completion("Copied", "Clipboard contents changed by AI.")
    }

    func insertTextAtCursorRemoteCommand(insertTextAtCursor: RemoteCommand.InsertTextAtCursor,
                                         completion: @escaping (String, String) throws -> ()) rethrows {
        writeTaskNoBroadcast(insertTextAtCursor.text)
        try completion("Inserted", "Text inserted by AI.")
    }

    func deleteCurrentLineRemoteCommand(deleteCurrentLine: RemoteCommand.DeleteCurrentLine,
                                        completion: @escaping (String, String) throws -> ()) rethrows {
        writeTaskNoBroadcast("\u{15}")
        try completion("Done", "Current line deleted by AI.")
    }

    func getManPageRemoteCommand(getManPage: RemoteCommand.GetManPage,
                                 completion: @escaping (String, String) throws -> ()) rethrows {
        let otsc = OneTimeStringClosure { message in
            try? completion(message, "manpage provided to AI.")
        }
        runningRemoteCommand.state = .futureString(otsc)
        if let conductor, conductor.framing {
            fetchRemoteManpage(from: conductor, command: getManPage.cmd) { otsc.call($0) }
            return
        }
        fetchLocalManpage(command: getManPage.cmd) { otsc.call($0) }
    }

    func createFileCommand(createFile: RemoteCommand.CreateFile,
                           completion: @escaping (String, String) throws -> ()) rethrows {
        DLog("\(createFile)")
        if #available(macOS 11, *) {
            if let conductor, conductor.framing {
                try createRemoteFile(createFile, conductor: conductor, completion: completion)
                return
            }
        }
        try createLocalFile(createFile, completion: completion)
    }

    @available(macOS 11.0, *)
    private func createRemoteFile(_ createFile: RemoteCommand.CreateFile,
                                  conductor: Conductor,
                                  completion: @escaping (String, String) throws -> ()) rethrows {
        DLog("Send to composer")
        conductor.create(file: createFile.filename, content: createFile.content.lossyData) { error in
            if let error {
                try? completion("Error creating \(createFile.filename): " + error.localizedDescription,
                           "Failed to create \(createFile) on remote host: \(error.localizedDescription)")
            } else {
                try? completion("Done", "AI created \(createFile.filename) on remote host.")
            }
        }
    }
    

    private func createLocalFile(_ createFile: RemoteCommand.CreateFile,
                                 completion: @escaping (String, String) throws -> ()) rethrows {
        do {
            let abs = if createFile.filename.hasPrefix("/") {
                createFile.filename
            } else {
                (currentLocalWorkingDirectory ?? "/").appending(pathComponent: createFile.filename)
            }
            let fileURL = URL(fileURLWithPath: abs)
            try createFile.content.write(to: fileURL,
                                         atomically: false,
                                         encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            try completion("Ok", "Created \(createFile.filename) and revealed in Finder.")
        } catch {
            try completion("Error: \(error.localizedDescription)", "Failed to create \(createFile.filename): \(error.localizedDescription)")
        }
    }

    private func fetchLocalManpage(command: String, completion: @escaping (String) -> ()) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/man")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var outputData = Data()
        // Drain the pipe concurrently.

        let inputPipe = Pipe()
        process.standardInput = inputPipe
        try? inputPipe.fileHandleForWriting.close()

        process.environment = ["MANPAGER": "cat", "TERM": "dumb"]

        do {
            try process.run()
            DLog("Session \(self) running \(command)")
            pipe.fileHandleForReading.readabilityHandler = { [weak pipe] handle in
                let data = handle.availableData
                if data.count == 0 {
                    try? pipe?.fileHandleForReading.close()
                    pipe?.fileHandleForReading.readabilityHandler = nil
                }
                DispatchQueue.main.async {
                    DLog("Session \(self) read \(data.count)bytes")
                    if data.count > 0 {
                        outputData.append(data)
                    } else {
                        DLog("Session \(self) will call completion block")
                        let output = outputData.stringOrHex
                        completion(output)
                    }
                }
            }
        } catch {
            completion("Error running man command: \(error)")
        }
    }

    private func fetchRemoteManpage(from conductor: Conductor,
                                    command: String,
                                    completion: @escaping (String) -> ()) {
        conductor.runRemoteCommand("man \((command as NSString).withEscapedShellCharacters(includingNewlines: true)!) | cat") { data, status in
            if status != 0 {
                completion("There was a problem running man on the remote host. It exited with status \(status)")
            } else {
                completion(data.stringOrHex)
            }
        }
    }
    private func searchBrowser(args: RemoteCommand.SearchBrowser, completion: @escaping (String, String) throws -> ()) rethrows {
        view.browserViewController.findOnPage(query: args.query, maxResults: 20, contextLength: 100) { result in
            switch result {
            case .success(let results):
                let json = try! JSONEncoder().encode(results).lossyString
                try? completion(json, "Find on page complete")
            case .failure(let error as LocalizedError):
                try? completion(error.errorDescription ?? "An unknown error occurred", "Find on page failed")
            case .failure:
                try? completion("An unknown error occurred", "Find on page failed")
            }
        }
    }

    private func loadURL(args: RemoteCommand.LoadURL, completion: @escaping (String, String) throws -> ()) rethrows {
        guard let url = URL(string: args.url) else {
            try completion("The URL \(args.url) is not well formed", "Navigation failed")
            return
        }
        view.browserViewController.loadURL(url) { error in
            if let error {
                try? completion("The web page could not be loaded: " + error.localizedDescription, "Navigation failed")
            } else {
                try? completion("The web page was loaded successfully.", "Navigation complete")
            }
        }
    }

    private func webSearch(args: RemoteCommand.WebSearch, completion: @escaping (String, String) throws -> ()) rethrows {
        view.browserViewController.doWebSearch(for: args.query) { [weak self] error in
            if let error {
                DLog("\(error)")
                try? completion("Web search is not currently available", "Web search failed")
                return
            }
            self?.view.browserViewController.convertToMarkdown(skipChrome: true) { (result: Result<String, Error>) in
                if let markdown = result.successValue {
                    try? completion(markdown, "Web search complete")
                } else {
                    try? completion("Web search is not currently availble", "Web search failed")
                }
            }
        }
    }

    private func getURL(args: RemoteCommand.GetURL, completion: @escaping (String, String) throws -> ()) rethrows {
        if let url = view.browserViewController.webView.url {
            try completion(url.absoluteString, "URL provided")
        } else {
            try completion("about:blank", "URL provided")
        }
    }

    private func readWebPage(args: RemoteCommand.ReadWebPage, completion: @escaping (String, String) throws -> ()) rethrows {
        view.browserViewController.convertToMarkdown(skipChrome: false) { (result: Result<String, Error>) in
            switch result {
            case .success(let text):
                let lines = text.components(separatedBy: "\n")
                guard args.startingLineNumber < lines.count else {
                    try? completion("The page contains \(lines.count) lines. Your request was out of bounds.",
                                   "AI attempted to read past the end of the page")
                    return
                }
                let sub = lines[args.startingLineNumber..<min(lines.count, args.startingLineNumber + args.numberOfLines)]
                let combined = sub.joined(separator: "\n")
                try? completion(combined, "Contents provided")
            case .failure(let error):
                try? completion("The page could not be converted to markdown for reading: " + error.localizedDescription,
                               "Page content could not be read")
            }
        }
    }
}

struct SubSelectionSerializationInfo {
    var mode: Int
    var start: LineBufferPosition
    var end: LineBufferPosition
    var windowedRange: Range<Int32>?

    // Format: "mode;startCompact;endCompact;range"
    // where range is "lower:upper" if non-nil, or "nil" otherwise.
    var queryValue: String {
        let rangeString = windowedRange.map { "\($0.lowerBound):\($0.upperBound)" } ?? "nil"
        return "\(mode);\(start.compactStringValue);\(end.compactStringValue);\(rangeString)"
    }

    static func from(queryValue: String) -> SubSelectionSerializationInfo? {
        let components = queryValue.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        precondition(components.count == 4, "Invalid queryValue format")

        guard let mode = Int(components[0]) else {
            DLog("Invalid mode in queryValue \(queryValue)")
            return nil
        }

        // Assumes LineBufferPosition can be re-created from its compact string.
        let start = LineBufferPosition.fromCompactStringValue(components[1])
        let end = LineBufferPosition.fromCompactStringValue(components[2])

        let windowedRange: Range<Int32>? = {
            if components[3] == "nil" { return nil }
            let parts = components[3].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            precondition(parts.count == 2, "Invalid range format")
            guard let lower = Int32(parts[0]), let upper = Int32(parts[1]) else {
                DLog("Invalid range bounds in queryValue \(queryValue)")
                return nil
            }
            return lower..<upper
        }()

        return SubSelectionSerializationInfo(mode: mode, start: start, end: end, windowedRange: windowedRange)
    }

    func absRange(_ screen: VT100Screen) -> VT100GridAbsWindowedRange? {
        guard let snapshot = screen.snapshotForcingPrimaryGrid(false) else {
            return nil
        }
        var ok = ObjCBool(false)
        let startCoord = snapshot.lineBuffer.coordinate(for: start,
                                                        width: screen.width(),
                                                        extendsRight: true,
                                                        ok: &ok)
        guard ok.boolValue else {
            return nil
        }
        let endCoord = snapshot.lineBuffer.coordinate(for: end,
                                                      width: screen.width(),
                                                      extendsRight: true,
                                                      ok: &ok)
        guard ok.boolValue else {
            return nil
        }
        let overflow = screen.totalScrollbackOverflow()
        let coordRange = VT100GridAbsCoordRange(start: VT100GridAbsCoordFromCoord(startCoord, overflow),
                                                end: VT100GridAbsCoordFromCoord(endCoord, overflow))
        return VT100GridAbsWindowedRange(coordRange: coordRange,
                                         columnWindow: VT100GridRange(location: windowedRange?.lowerBound ?? 0,
                                                                      length: Int32(windowedRange?.count ?? 0)))
    }
}

@objc
extension iTermSubSelection {
    @objc(initWithCompactString:screen:)
    convenience init?(compactString: String, screen: VT100Screen) {
        guard let info = SubSelectionSerializationInfo.from(queryValue: compactString) else {
            return nil
        }
        guard let absRange = info.absRange(screen) else {
            return nil
        }
        guard let mode = iTermSelectionMode(rawValue: info.mode) else {
            return nil
        }
        self.init(absRange: absRange,
                  mode: mode,
                  width: screen.width())
    }
}

// MARK: - AI Suggestions
extension PTYSession {
    private func previouslyRunCommands(_ n: Int) -> ArraySlice<AICompletion.PreviouslyRunCommand> {
        guard let remoteHost = screen.lastRemoteHost() else {
            return ArraySlice([])
        }
        return iTermShellHistoryController
            .sharedInstance()
            .commandUses(forHost: remoteHost)
            .compactMap { use -> AICompletion.PreviouslyRunCommand? in
                guard let command = use.command,
                      let time = use.time else {
                    return nil
                }
                return AICompletion.PreviouslyRunCommand(
                    command: command,
                    workingDirectory: use.directory,
                    date: Date(timeIntervalSinceReferenceDate: time.doubleValue))
            }.sorted(by: { lhs, rhs in
                lhs.date < rhs.date
            })
            .suffix(10)
    }

    @objc(suggestWithAI:fileCompletions:firstResult:)
    func suggestWithAI(request: SuggestionRequest, files: [CompletionItem], firstResult: CompletionItem?) {
        let history = previouslyRunCommands(20)
        AICompletion.suggestionCompletions(
            request,
            history: history,
            files: files) { cs in
                let modified: [CompletionItem] =
                if cs.isEmpty {
                    []
                } else if let firstResult {
                    [firstResult] + cs.filter { $0.value != firstResult.value }
                } else {
                    cs
                }
                request.completion(false, modified)
            }
    }
}

extension PTYSession {
    // Returns an error if one occurs.
    @objc(performCopyModeCommands:)
    func performCopyModeCommands(_ commands: String) -> String? {
        let parser = VimKeyParser(commands)
        let events: [NSEvent]
        do {
            events = try parser.events()
        } catch {
            return error.localizedDescription
        }
        let wasInCopyMode = copyMode
        defer {
            copyMode = wasInCopyMode
        }
        copyMode = true
        for event in events {
            modeHandler.handle(event)
            if !copyMode {
                copyMode = true
            }
        }
        return nil
    }
}

@available(macOS 11.0, *)
extension PTYSession: PathCompletionHelperDelegate {
    @objc(showCompletionUIForPathMark:)
    func showCompletionUI(pathMark: PathMarkReading) -> PathCompletionHelper? {
        guard screen.isAtCommandPrompt else {
            return nil
        }
        let pathCompletionHelper = PathCompletionHelper(remoteHost: screen.lastRemoteHost(),
                                                        conductor: conductor,
                                                        pathMark: pathMark)
        pathCompletionHelper.delegate = self
        pathCompletionHelper.begin()
        return pathCompletionHelper
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              rangeForInterval interval: Interval) -> VT100GridCoordRange {
        return screen.coordRange(for: interval)
    }

    func pathCompletionHelperWidth(_ helper: PathCompletionHelper) -> Int32 {
        return screen.width()
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              screenRectForCoordRange coordRange: VT100GridCoordRange) -> NSRect {
        let startRect = textview.rect(for: coordRange.start)
        let endRect = textview.rect(for: coordRange.end)
        let textViewRect = startRect.union(endRect)
        let windowRect = textview.convert(textViewRect, to: nil)
        let screenRect = textview.window?.convertToScreen(windowRect) ?? .zero
        return screenRect
    }

    func pathCompletionHelperWindow(_ helper: PathCompletionHelper) -> NSWindow? {
        return textview.window
    }

    func pathCompletionHelperFont(_ helper: PathCompletionHelper) -> NSFont {
        return textview.fontTable.asciiFont.font
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper, didSelect suggestion: String) {
        let escaped = (suggestion as NSString).withBackslashEscapedShellCharacters(includingNewlines: true)!
        if screen.isAtCommandPrompt && (currentCommand ?? "").isEmpty {
            writeTask("cd \(escaped)\r")
        } else {
            setOrAppendComposerString((currentCommand ?? "") + escaped)
        }
        helper.invalidate()
        pathCompletionHelper = nil
    }
}

extension PTYSession {
    // NOTE: The channels branch of iTerm2-Shell-Integration has the `it2run` server process you need to test this.
    @objc(addChannelClient:command:)
    func add(channelClient: ChannelClient, command: String) {
        it_assert(!isTmuxClient)

        channelClients.add(channelClient)
        let session = newSession(forChannelID: channelClient.uid, command: command)!
        let iobuffer = IOBuffer(fileDescriptor: channelClient.fd,
                                operationQueue: FileDescriptorMonitor.queue) { [weak session] in
            // receive returns nil if only part of a segmented message is received.
            if var data = channelClient.mux.receive() {
                data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
                    session?.threadedReadTask(ptr.baseAddress!, length: Int32(ptr.count))
                }
            }
        } writeClosure: { data in
            channelClient.mux.send(message: data)
        }
        session.shell.ioBuffer = iobuffer
        session.channelParentGuid = guid
        // Should only be nil for tmux
        let restorableSession = self.restorableSession!
        restorableSession.arrangement = [:]
        restorableSession.sessions = [session]
        restorableSession.group = .kiTermRestorableSessionGroupChannel
        iTermBuriedSessions.sharedInstance().add(restorableSession, for: session)
    }

    @objc(removeChannelClientWithID:)
    func removeChannelClient(id: String) {
        let indexes = channelClients.indexesOfObjects { obj, _, _ in
            (obj as! ChannelClient).uid == id
        }
        channelClients.removeObjects(at: indexes)
    }

    @objc(removeChannelClientsForConductor:)
    func removeChannelClients(for conductor: Conductor) {
        let indexes = channelClients.indexesOfObjects { obj, _, _ in
            (obj as! ChannelClient).conductor === conductor
        }
        channelClients.removeObjects(at: indexes)
    }

    @objc(swapWithChannelSessionWithUID:)
    func swapWithChannelSession(uid: String) {
        let session = iTermBuriedSessions.sharedInstance().buriedSessions().first { candidate in
            candidate.channelUID == uid
        }
        guard let session else {
            DLog("No buried session with channel uid \(uid)")
            return
        }
        delegate?.swapSession(self, withBuriedSession: session)
    }

}

@objc
extension PTYSession {
    func smartSelectAllVisible() {
        DLog("begin");
        textview?.removeContentNavigationShortcutsAndSearchResults(false)
        let visibleLines = textview.rangeOfVisibleLines
        let overflow = screen.totalScrollbackOverflow()
        let y = VT100GridRangeNoninclusiveMaxLL(visibleLines) + overflow
        textview.findOnPageHelper.setStartPoint(VT100GridAbsCoordMake(0, y))
        let findDriver = view.findDriverCreatingIfNeeded

        let regex = regularExpressonForNonLowPrecisionSmartSelectionRulesCombined
        DLog("findDriver=\(findDriver.d) regex=\(regex.d)")
        var done = false
        let visibleAbsLines = NSMakeRange(Int(visibleLines.location) + Int(overflow),
                                          Int(visibleLines.length))
        var indexes = IndexSet(integersIn: Range(visibleAbsLines)!)
        findDriver?.closeViewAndDoTemporarySearch(for: regex,
                                                  mode: .caseSensitiveRegex) { [weak self] linesSearched in
            guard let textview = self?.textview, !done else {
                return
            }
            indexes.remove(integersIn: Range(linesSearched)!)
            if indexes.isEmpty {
                textview.convertVisibleSearchResultsToContentNavigationShortcuts(with: .copy,
                                                                                 clearOnEnd: true)
                done = true
            }
        }
    }
}

extension PTYSession {
    @objc
    var minimalThemeTextColor: NSColor {
        if let color = textview.colorForMargins {
            if color.isDark {
                return NSColor(displayP3Red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            } else {
                return NSColor(displayP3Red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
            }
        }
        return textview.colorMap.color(forKey: kColorMapForeground)
    }
}

@available(macOS 11, *)
extension PTYSession {
    @objc(openURL:)
    func open(url: URL) {
        guard view.isBrowser else {
            DLog("Can't open \(url), not a browser")
            return
        }
        view.browserViewController?.loadURL(url.absoluteString)
    }

    @objc
    var webSiteTitle: String? {
        if #available(macOS 11, *) {
            return view.browserViewController?.title
        }
        return nil
    }

    @objc
    func loadDeferredURLIfNeeded() {
        view.browserViewController?.loadDeferredURLIfNeeded()
    }
}


@available(macOS 11, *)
extension PTYSession {
    @objc
    func becomeBrowser(configuration: WKWebViewConfiguration,
                       restorableState: NSDictionary?) {
        let nullValue = NSNull()
        let terminalOnlyKeys = [
            KEY_INITIAL_TEXT: nullValue,
            KEY_CUSTOM_DIRECTORY: nullValue,
            KEY_WORKING_DIRECTORY: nullValue,
            KEY_SSH_CONFIG: nullValue,
            KEY_AWDS_WIN_OPTION: nullValue,
            KEY_AWDS_WIN_DIRECTORY: nullValue,
            KEY_AWDS_TAB_OPTION: nullValue,
            KEY_AWDS_TAB_DIRECTORY: nullValue,
            KEY_AWDS_PANE_OPTION: nullValue,
            KEY_AWDS_PANE_DIRECTORY: nullValue,
            KEY_BLINKING_CURSOR: nullValue,
            KEY_CURSOR_SHADOW: nullValue,
            KEY_CURSOR_HIDDEN_WITHOUT_FOCUS: nullValue,
            KEY_CURSOR_TYPE: nullValue,
            KEY_DISABLE_BOLD: nullValue,
            KEY_USE_BOLD_FONT: nullValue,
            KEY_THIN_STROKES: nullValue,
            KEY_USE_ITALIC_FONT: nullValue,
            KEY_ANTI_ALIASING: nullValue,
            KEY_ASCII_ANTI_ALIASED: nullValue,
            KEY_DISABLE_WINDOW_RESIZING: nullValue,
            KEY_DISABLE_UNFOCUSED_WINDOW_RESIZING: nullValue,
            KEY_TREAT_NON_ASCII_AS_DOUBLE_WIDTH: nullValue,
            KEY_AMBIGUOUS_DOUBLE_WIDTH: nullValue,
            KEY_USE_HFS_PLUS_MAPPING: nullValue,
            KEY_UNICODE_NORMALIZATION: nullValue,
            KEY_SILENCE_BELL: nullValue,
            KEY_VISUAL_BELL: nullValue,
            KEY_FLASHING_BELL: nullValue,
            KEY_XTERM_MOUSE_REPORTING: nullValue,
            KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL: nullValue,
            KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS: nullValue,
            KEY_UNICODE_VERSION: nullValue,
            KEY_DISABLE_SMCUP_RMCUP: nullValue,
            KEY_ALLOW_TITLE_REPORTING: nullValue,
            KEY_ALLOW_ALTERNATE_MOUSE_SCROLL: nullValue,
            KEY_RESTRICT_MOUSE_REPORTING_TO_ALTERNATE_SCREEN_MODE: nullValue,
            KEY_ALLOW_PASTE_BRACKETING: nullValue,
            KEY_ALLOW_TITLE_SETTING: nullValue,
            KEY_DISABLE_PRINTING: nullValue,
            KEY_SCROLLBACK_WITH_STATUS_BAR: nullValue,
            KEY_SCROLLBACK_IN_ALTERNATE_SCREEN: nullValue,
            KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED: nullValue,
            KEY_SEND_BELL_ALERT: nullValue,
            KEY_SEND_IDLE_ALERT: nullValue,
            KEY_SEND_NEW_OUTPUT_ALERT: nullValue,
            KEY_SEND_TERMINAL_GENERATED_ALERT: nullValue,
            KEY_ALLOW_CHANGE_CURSOR_BLINK: nullValue,
            KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY: nullValue,
            KEY_AUTOMATICALLY_ENABLE_ALTERNATE_MOUSE_SCROLL: nullValue,
            KEY_RESTRICT_ALTERNATE_MOUSE_SCROLL_TO_VERTICAL: nullValue,
            KEY_SET_LOCALE_VARS: nullValue,
            KEY_CUSTOM_LOCALE: nullValue,
            KEY_SCROLLBACK_LINES: nullValue,
            KEY_UNLIMITED_SCROLLBACK: nullValue,
            KEY_TERMINAL_TYPE: nullValue,
            KEY_ANSWERBACK_STRING: nullValue,
            KEY_USE_CANONICAL_PARSER: nullValue,
            KEY_PLACE_PROMPT_AT_FIRST_COLUMN: nullValue,
            KEY_SHOW_MARK_INDICATORS: nullValue,
            KEY_SHOW_OFFSCREEN_COMMANDLINE: nullValue,
            KEY_TMUX_NEWLINE: nullValue,
            KEY_PROMPT_PATH_CLICK_OPENS_NAVIGATOR: nullValue,
            KEY_AUTOLOG: nullValue,
            KEY_LOGDIR: nullValue,
            KEY_LOG_FILENAME_FORMAT: nullValue,
            KEY_SEND_CODE_WHEN_IDLE: nullValue,
            KEY_IDLE_CODE: nullValue,
            KEY_IDLE_PERIOD: nullValue,
            KEY_JOBS: nullValue,
            KEY_REDUCE_FLICKER: nullValue,
            KEY_LOGGING_STYLE: nullValue,
            KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY: nullValue,
            KEY_SHOW_TIMESTAMPS: nullValue,
            KEY_TIMESTAMPS_STYLE: nullValue,
            KEY_TIMESTAMPS_VISIBLE: nullValue,
            KEY_OPTION_KEY_SENDS: nullValue,
            KEY_RIGHT_OPTION_KEY_SENDS: nullValue,
            KEY_LEFT_OPTION_KEY_CHANGEABLE: nullValue,
            KEY_RIGHT_OPTION_KEY_CHANGEABLE: nullValue,
            KEY_APPLICATION_KEYPAD_ALLOWED: nullValue,
            KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS: nullValue,
            KEY_TREAT_OPTION_AS_ALT: nullValue,
            KEY_ALLOW_MODIFY_OTHER_KEYS: nullValue,
            KEY_USE_LIBTICKIT_PROTOCOL: nullValue,
            KEY_LEFT_CONTROL: nullValue,
            KEY_RIGHT_CONTROL: nullValue,
            KEY_LEFT_COMMAND: nullValue,
            KEY_RIGHT_COMMAND: nullValue,
            KEY_FUNCTION: nullValue,
            KEY_TMUX_PANE_TITLE: nullValue,
            KEY_FOREGROUND_COLOR: nullValue,
            KEY_FOREGROUND_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_FOREGROUND_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_BACKGROUND_COLOR: nullValue,
            KEY_BACKGROUND_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_BACKGROUND_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_BOLD_COLOR: nullValue,
            KEY_BOLD_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_BOLD_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_USE_BOLD_COLOR: nullValue,
            KEY_USE_BOLD_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_USE_BOLD_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_BRIGHTEN_BOLD_TEXT: nullValue,
            KEY_BRIGHTEN_BOLD_TEXT + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_BRIGHTEN_BOLD_TEXT + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_CURSOR_COLOR: nullValue,
            KEY_CURSOR_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_CURSOR_TEXT_COLOR: nullValue,
            KEY_CURSOR_TEXT_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_CURSOR_TEXT_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_0_COLOR: nullValue,
            KEY_ANSI_0_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_0_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_1_COLOR: nullValue,
            KEY_ANSI_1_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_1_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_2_COLOR: nullValue,
            KEY_ANSI_2_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_2_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_3_COLOR: nullValue,
            KEY_ANSI_3_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_3_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_4_COLOR: nullValue,
            KEY_ANSI_4_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_4_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_5_COLOR: nullValue,
            KEY_ANSI_5_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_5_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_6_COLOR: nullValue,
            KEY_ANSI_6_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_6_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_7_COLOR: nullValue,
            KEY_ANSI_7_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_7_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_8_COLOR: nullValue,
            KEY_ANSI_8_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_8_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_9_COLOR: nullValue,
            KEY_ANSI_9_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_9_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_10_COLOR: nullValue,
            KEY_ANSI_10_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_10_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_11_COLOR: nullValue,
            KEY_ANSI_11_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_11_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_12_COLOR: nullValue,
            KEY_ANSI_12_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_12_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_13_COLOR: nullValue,
            KEY_ANSI_13_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_13_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_14_COLOR: nullValue,
            KEY_ANSI_14_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_14_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_ANSI_15_COLOR: nullValue,
            KEY_ANSI_15_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_ANSI_15_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEYTEMPLATE_ANSI_X_COLOR: nullValue,
            KEYTEMPLATE_ANSI_X_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEYTEMPLATE_ANSI_X_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_SMART_CURSOR_COLOR: nullValue,
            KEY_SMART_CURSOR_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_SMART_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_MINIMUM_CONTRAST: nullValue,
            KEY_MINIMUM_CONTRAST + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_MINIMUM_CONTRAST + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_FAINT_TEXT_ALPHA: nullValue,
            KEY_FAINT_TEXT_ALPHA + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_FAINT_TEXT_ALPHA + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_USE_SELECTED_TEXT_COLOR: nullValue,
            KEY_USE_SELECTED_TEXT_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_USE_SELECTED_TEXT_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_UNDERLINE_COLOR: nullValue,
            KEY_UNDERLINE_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_UNDERLINE_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_USE_UNDERLINE_COLOR: nullValue,
            KEY_USE_UNDERLINE_COLOR + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_USE_UNDERLINE_COLOR + COLORS_DARK_MODE_SUFFIX: nullValue,
            KEY_CURSOR_BOOST: nullValue,
            KEY_CURSOR_BOOST + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_CURSOR_BOOST + COLORS_DARK_MODE_SUFFIX: nullValue,
        ]
        setSessionSpecificProfileValues(terminalOnlyKeys, reload: false)
        DispatchQueue.main.async {
            self.reloadProfile()
        }

        if iTermProfilePreferences.bool(forKey: KEY_BROWSER_DEV_NULL, inProfile: self.profile) {
            setSessionSpecificProfileValues([KEY_UNDO_TIMEOUT: 0])
        }
        let model: ProfileModel
        let guid: String
        let myGuid = profile[KEY_GUID]! as! String
        if isDivorced {
            if let originalGuid = profile[KEY_ORIGINAL_GUID] as? String,
               ProfileModel.sharedInstance()!.bookmark(withGuid: originalGuid) != nil {
                model = ProfileModel.sharedInstance()!
                guid = originalGuid
            } else {
                model = ProfileModel.sessionsInstance()!
                guid = myGuid
            }
        } else {
            model = ProfileModel.sharedInstance()!
            guid = myGuid
        }
        let vc = iTermBrowserViewController(
            configuration: configuration,
            sessionGuid: guid,
            profileObserver: iTermProfilePreferenceObserver(
                guid: profile[KEY_GUID]! as! String,
                model: isDivorced ? ProfileModel.sessionsInstance() : ProfileModel.sharedInstance()),
            profileMutator: iTermProfilePreferenceMutator(
                model: model,
                guid: guid),
            indicatorsHelper: textview.indicatorsHelper)
        vc.delegate = self
        view.setBrowserViewController(
            vc, initialURL: iTermProfilePreferences.string(forKey: KEY_INITIAL_URL,
                                                           inProfile: profile),
            restorableState: restorableState as? [AnyHashable: Any])
    }
}

@objc
extension PTYSession {
    var defaultAccountNameForPasswordManager: String? {
        if isBrowserSession() {
            return view.browserViewController.currentURL?.host
        }
        return nil
    }
}
