//
//  PTYSession.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

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

    @objc(explainSelectionWithAI:truncated:snapshot:command:subjectMatter:title:)
    func explainWithAI(selection: iTermSelection,
                       truncated: Bool,
                       snapshot: TerminalContentSnapshot,
                       command: String?,
                       subjectMatter: String,
                       title: String) {
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
        client.explain(request,
                       title: title,
                       scope: genericScope)
    }

    func execute(_ command: RemoteCommand, completion: @escaping (String, String) -> ()) {
        DLog("\(command)")
        cancelRemoteCommand()
        switch command.content {
        case .isAtPrompt(let isAtPrompt):
            isAtPromptRemoteCommand(isAtPrompt: isAtPrompt,
                                    completion: completion)
        case .executeCommand(let executeCommand):
            executeCommandRemoteCommand(executeCommand: executeCommand,
                                        completion: completion)
        case .getLastExitStatus(let getLastExitStatus):
            getLastExitStatusRemoteCommand(getLastExitStatus: getLastExitStatus,
                                           completion: completion)
        case .getCommandHistory(let getCommandHistory):
            getCommandHistoryRemoteCommand(getCommandHistory: getCommandHistory,
                                           completion: completion)
        case .getLastCommand(let getLastCommand):
            getLastCommandRemoteCommand(getLastCommand: getLastCommand,
                                        completion: completion)
        case .getCommandBeforeCursor(let getCommandBeforeCursor):
            getCommandBeforeCursorRemoteCommand(getCommandBeforeCursor: getCommandBeforeCursor,
                                                completion: completion)
        case .searchCommandHistory(let searchCommandHistory):
            searchCommandHistoryRemoteCommand(searchCommandHistory: searchCommandHistory,
                                              completion: completion)
        case .getCommandOutput(let getCommandOutput):
            getCommandOutputRemoteCommand(getCommandOutput: getCommandOutput,
                                          completion: completion)
        case .getTerminalSize(let getTerminalSize):
            getTerminalSizeRemoteCommand(getTerminalSize: getTerminalSize,
                                         completion: completion)
        case .getShellType(let getShellType):
            getShellTypeRemoteCommand(getShellType: getShellType,
                                      completion: completion)
        case .detectSSHSession(let detectSSHSession):
            detectSSHSessionRemoteCommand(detectSSHSession: detectSSHSession,
                                          completion: completion)
        case .getRemoteHostname(let getRemoteHostname):
            getRemoteHostnameRemoteCommand(getRemoteHostname: getRemoteHostname,
                                           completion: completion)
        case .getUserIdentity(let getUserIdentity):
            getUserIdentityRemoteCommand(getUserIdentity: getUserIdentity,
                                         completion: completion)
        case .getCurrentDirectory(let getCurrentDirectory):
            getCurrentDirectoryRemoteCommand(getCurrentDirectory: getCurrentDirectory,
                                             completion: completion)
        case .setClipboard(let setClipboard):
            setClipboardRemoteCommand(setClipboard: setClipboard,
                                      completion: completion)
        case .insertTextAtCursor(let insertTextAtCursor):
            insertTextAtCursorRemoteCommand(insertTextAtCursor: insertTextAtCursor,
                                            completion: completion)
        case .deleteCurrentLine(let deleteCurrentLine):
            deleteCurrentLineRemoteCommand(deleteCurrentLine: deleteCurrentLine,
                                           completion: completion)
        case .getManPage(let getManPage):
            getManPageRemoteCommand(getManPage: getManPage,
                                    completion: completion)
        case .createFile(let createFile):
            createFileCommand(createFile: createFile,
                              completion: completion)
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
                                 completion: @escaping (String, String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.", "Failed to check if you’re at the prompt because Shell Integration is not installed.")
            return
        }
        completion(currentCommand != nil ? "true" : "false", "Notified AI that you are \(currentCommand != nil ? "at" : "not at") the a prompt.")
    }

    func executeCommandRemoteCommand(executeCommand: RemoteCommand.ExecuteCommand,
                                     completion: @escaping (String, String) -> ()) {
        if !iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() || currentCommand == nil {
            jankyExecuteCommand(executeCommand, completion: completion)
        } else {
            goodExecuteCommand(executeCommand, completion: completion)
        }
    }

    private func goodExecuteCommand(_ executeCommand: RemoteCommand.ExecuteCommand,
                                    completion: @escaping (String, String) -> ()) {
        let start = Int64(screen.numberOfScrollbackLines() + screen.cursorY() - 1) + screen.totalScrollbackOverflow()
        let uuid = UUID()
        let otsc = OneTimeStringClosure { message in
            completion(message, "Ran \(executeCommand.command)")
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
                                     completion: @escaping (String, String) -> ()) {
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
                    completion(content, "Ran \(executeCommand.command)")
                } else {
                    // Something weird happened, probably the start fell off the end of scrollback history.
                    completion(
                        content
                            .replacingOccurrences(of: "-- FINISHED \(uuid)",
                                                  with: "")
                            .replacingOccurrences(of: uuid,
                                                  with: ""),
                        "Ran \(executeCommand.command) but its output could not be located. Did you run out of scrollback history lines?")
                }
            } else {
                completion("The executeCommand function call failed because the output of the command is not available. The buffer may have been cleared or some other technical issue occurred.",
                           "Ran \(executeCommand.command) but its output was unavailable. Did you run out of scrollback history lines?")
            }
        }
        runningRemoteCommand.state = .expectation(expectation, { output in completion(output, "Ran \(executeCommand.command)")})
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
                                        completion: @escaping (String, String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.",
                       "Failed to get the last command’s exit status because shell integration is not installed.")
            return
        }
        guard let promise = screen.lastCommandMark()?.returnCodePromise, let value = promise.maybeValue  else {
            completion("The last command is still running and has not exited yet.",
                       "The last command seems to still be running so its exit status cannot be retrieved.")
            return
        }
        completion(value.stringValue, "The exit status of the last command provided to AI.")
    }

    func getCommandHistoryRemoteCommand(getCommandHistory: RemoteCommand.GetCommandHistory,
                                        completion: @escaping (String, String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.",
                       "Command history isn’t available because Shell Integration isn’t installed.")
            return
        }
        var commands = [String]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark?.command {
                commands.append(command)
            }
        }
        completion(commands.joined(separator: "\n"), "Command history provided to AI.")
    }

    func getLastCommandRemoteCommand(getLastCommand: RemoteCommand.GetLastCommand,
                                     completion: @escaping (String, String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.",
                       "The last command execute can’t be provided because Shell Integration isn’t installed.")
            return
        }
        guard let command = screen.lastCommandMark()?.command else {
            completion("There are no previous command in history", "No previous command is available in this session}s history.")
            return
        }
        completion(command, "Last command provided to AI.")
    }

    func getCommandBeforeCursorRemoteCommand(getCommandBeforeCursor: RemoteCommand.GetCommandBeforeCursor,
                                             completion: @escaping (String, String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.",
            "The contents of the shell prompt could not be determined because Shell Integration isn’t installed.")
            return
        }
        guard let currentCommandUpToCursor else {
            completion("The user is not at the prompt.",
            "The contents of the shell prompt could not be provided because it appears the session is not currently at a prompt.")
            return
        }
        #warning("TODO: Test this")
        completion(currentCommandUpToCursor, "Current command provided to AI.")

    }

    func searchCommandHistoryRemoteCommand(searchCommandHistory: RemoteCommand.SearchCommandHistory,
                                           completion: @escaping (String, String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.",
                       "Command history is not available because Shell Integration isn’t installed.")
            return
        }
        var commands = [String]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark?.command, command.contains(searchCommandHistory.query) {
                commands.append(command)
            }
        }
        completion(commands.joined(separator: "\n"), "Command history provided to AI.")
    }

    func getCommandOutputRemoteCommand(getCommandOutput: RemoteCommand.GetCommandOutput,
                                       completion: @escaping (String, String) -> ()) {
        let absRange = textViewRangeOfLastCommandOutput()
        let range = VT100GridCoordRangeFromAbsCoordRange(absRange, screen.totalScrollbackOverflow())
        if range.start.x < 0 {
            completion("The output is no longer available.", "The output of the last command wasn’t provided because it is no longer available.")
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
            completion(string, "Last command’s output provided to AI.")
        } else {
            completion("The content could not be retrieved because of an unexpected error",
            "The output of the last command wasn’t provided because of an unexpected error.")
        }
    }

    func getTerminalSizeRemoteCommand(getTerminalSize: RemoteCommand.GetTerminalSize,
                                      completion: @escaping (String, String) -> ()) {
        completion("\(screen.width()) columns wide by \(screen.height()) rows tall",
                   "Session size provided to AI.")
    }

    func getShellTypeRemoteCommand(getShellType: RemoteCommand.GetShellType,
                                   completion: @escaping (String, String) -> ()) {
        completion(genericScope.stringValue(forVariableName: iTermVariableKeyShell),
                   "Shell type provided to AI")
    }

    func detectSSHSessionRemoteCommand(detectSSHSession: RemoteCommand.DetectSSHSession,
                                       completion: @escaping (String, String) -> ()) {
        let value = screen.lastRemoteHost()?.isLocalhost ?? false
        completion("\(value)", "SSH status provided to AI.")
    }

    func getRemoteHostnameRemoteCommand(getRemoteHostname: RemoteCommand.GetRemoteHostname,
                                        completion: @escaping (String, String) -> ()) {
        completion(screen.lastRemoteHost()?.hostname ?? "Unknown",
                   "Hostname provided to AI")
    }

    func getUserIdentityRemoteCommand(getUserIdentity: RemoteCommand.GetUserIdentity,
                                      completion: @escaping (String, String) -> ()) {
        completion(screen.lastRemoteHost()?.username ?? NSUserName(),
                   "User name provided to AI.")
    }

    func getCurrentDirectoryRemoteCommand(getCurrentDirectory: RemoteCommand.GetCurrentDirectory,
                                          completion: @escaping (String, String) -> ()) {
        completion(genericScope.stringValue(forVariableName: iTermVariableKeySessionPath),
                   "Current directory provided to AI.")
    }

    func setClipboardRemoteCommand(setClipboard: RemoteCommand.SetClipboard,
                                   completion: @escaping (String, String) -> ()) {
        NSPasteboard.general.declareTypes([.string], owner: NSApp)
        NSPasteboard.general.setString(setClipboard.text, forType: .string)
        completion("Copied", "Clipboard contents changed by AI.")
    }

    func insertTextAtCursorRemoteCommand(insertTextAtCursor: RemoteCommand.InsertTextAtCursor,
                                         completion: @escaping (String, String) -> ()) {
        writeTaskNoBroadcast(insertTextAtCursor.text)
        completion("Inserted", "Text inserted by AI.")
    }

    func deleteCurrentLineRemoteCommand(deleteCurrentLine: RemoteCommand.DeleteCurrentLine,
                                        completion: @escaping (String, String) -> ()) {
        writeTaskNoBroadcast("\u{15}")
        completion("Done", "Current line deleted by AI.")
    }

    func getManPageRemoteCommand(getManPage: RemoteCommand.GetManPage,
                                 completion: @escaping (String, String) -> ()) {
        let otsc = OneTimeStringClosure { message in
            completion(message, "manpage provided to AI.")
        }
        runningRemoteCommand.state = .futureString(otsc)
        if let conductor, conductor.framing {
            fetchRemoteManpage(from: conductor, command: getManPage.cmd) { otsc.call($0) }
            return
        }
        fetchLocalManpage(command: getManPage.cmd) { otsc.call($0) }
    }

    func createFileCommand(createFile: RemoteCommand.CreateFile,
                           completion: @escaping (String, String) -> ()) {
        DLog("\(createFile)")
        if #available(macOS 11, *) {
            if let conductor, conductor.framing {
                createRemoteFile(createFile, conductor: conductor, completion: completion)
                return
            }
        }
        createLocalFile(createFile, completion: completion)
    }

    @available(macOS 11.0, *)
    private func createRemoteFile(_ createFile: RemoteCommand.CreateFile,
                                  conductor: Conductor,
                                  completion: @escaping (String, String) -> ()) {
        DLog("Send to composer")
        conductor.create(file: createFile.filename, content: createFile.content.lossyData) { error in
            if let error {
                completion("Error creating \(createFile.filename): " + error.localizedDescription,
                           "Failed to create \(createFile) on remote host: \(error.localizedDescription)")
            } else {
                completion("Done", "AI created \(createFile.filename) on remote host.")
            }
        }
    }
    

    private func createLocalFile(_ createFile: RemoteCommand.CreateFile,
                                 completion: @escaping (String, String) -> ()) {
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
            completion("Ok", "Created \(createFile.filename) created and revealed in Finder.")
        } catch {
            completion("Error: \(error.localizedDescription)", "Failed to create \(createFile.filename): \(error.localizedDescription)")
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
