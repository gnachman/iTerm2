//
//  PTYSession.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

extension PTYSession {
    private func promptUserForAIExplanationQuestion(regarding subjectMatter: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Enter a question about \(subjectMatter), or leave it empty to annotate it with explanations. Press ⇧⏎ to send."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = ShiftEnterTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        input.isRichText = false
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = .width
        input.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        input.textContainer?.widthTracksTextView = true
        input.textContainerInset = NSSize(width: 4, height: 4)

        weak var weakAlert = alert
        input.shiftEnterPressed = {
            weakAlert?.buttons.first?.performClick(nil)
        }

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = input
        scrollView.borderType = .lineBorder

        alert.accessoryView = scrollView
        alert.window.initialFirstResponder = input
        DispatchQueue.main.async {
            input.window?.makeFirstResponder(input)
        }

        let button = alert.runModal()
        return button == .alertFirstButtonReturn ? input.string : nil
    }

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

    @objc(explainSelectionWithAI:snapshot:command:subjectMatter:title:)
    func explainWithAI(selection: iTermSelection,
                       snapshot: TerminalContentSnapshot,
                       command: String?,
                       subjectMatter: String,
                       title: String) {
        let request = AIExplanationRequest(command: command,
                                           snapshot: snapshot,
                                           selection: selection,
                                           question: "",
                                           subjectMatter: subjectMatter,
                                           url: url(selection, in: snapshot))
        guard let client = ChatClient.instance else {
            #warning("TODO: Error handling")
            return
        }
        client.explain(request,
                       title: title,
                       guid: guid,
                       baseOffset: screen.totalScrollbackOverflow(),
                       scope: genericScope)
    }

    func execute(_ command: RemoteCommand, completion: @escaping (String) -> ()) {
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
                                 completion: @escaping (String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.")
            return
        }
        completion(currentCommand != nil ? "true" : "false")
    }

    func executeCommandRemoteCommand(executeCommand: RemoteCommand.ExecuteCommand,
                                     completion: @escaping (String) -> ()) {
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
                    completion(content)
                } else {
                    // Something weird happened, probably the start fell off the end of scrollback history.
                    completion(
                        content
                            .replacingOccurrences(of: "-- FINISHED \(uuid)",
                                                  with: "")
                            .replacingOccurrences(of: uuid,
                                                  with: ""))
                }
            } else {
                completion("The executeCommand function call failed because the output of the command is not available. The buffer may have been cleared or some other technical issue occurred.")
            }
        }
        runningRemoteCommand.state = .expectation(expectation, completion)
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
                                        completion: @escaping (String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.")
            return
        }
        guard let promise = screen.lastCommandMark()?.returnCodePromise, let value = promise.maybeValue  else {
            completion("The last command is still running and has not exited yet.")
            return
        }
        completion(value.stringValue)
    }

    func getCommandHistoryRemoteCommand(getCommandHistory: RemoteCommand.GetCommandHistory,
                                        completion: @escaping (String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.")
            return
        }
        var commands = [String]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark?.command {
                commands.append(command)
            }
        }
        completion(commands.joined(separator: "\n"))
    }

    func getLastCommandRemoteCommand(getLastCommand: RemoteCommand.GetLastCommand,
                                     completion: @escaping (String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.")
            return
        }
        guard let command = screen.lastCommandMark()?.command else {
            completion("The last command is still running and has not exited yet.")
            return
        }
        completion(command)
    }

    func getCommandBeforeCursorRemoteCommand(getCommandBeforeCursor: RemoteCommand.GetCommandBeforeCursor,
                                             completion: @escaping (String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.")
            return
        }
        guard let currentCommand else {
            completion("The user is not at the prompt.")
            return
        }
        #warning("TODO: Cut off the part after the cursor")
        completion(currentCommand)

    }

    func searchCommandHistoryRemoteCommand(searchCommandHistory: RemoteCommand.SearchCommandHistory,
                                           completion: @escaping (String) -> ()) {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            completion("Tell the user they need to install Shell Integration to access this information.")
            return
        }
        var commands = [String]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark?.command, command.contains(searchCommandHistory.query) {
                commands.append(command)
            }
        }
        completion(commands.joined(separator: "\n"))
    }

    func getCommandOutputRemoteCommand(getCommandOutput: RemoteCommand.GetCommandOutput,
                                       completion: @escaping (String) -> ()) {
        let absRange = textViewRangeOfLastCommandOutput()
        let range = VT100GridCoordRangeFromAbsCoordRange(absRange, screen.totalScrollbackOverflow())
        if range.start.x < 0 {
            completion("The output is no longer available.")
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
            completion(string)
        } else {
            completion("The content could not be retrieved because of an unexpected error")
        }
    }

    func getTerminalSizeRemoteCommand(getTerminalSize: RemoteCommand.GetTerminalSize,
                                      completion: @escaping (String) -> ()) {
        completion("\(screen.width()) columns wide by \(screen.height()) rows tall")
    }

    func getShellTypeRemoteCommand(getShellType: RemoteCommand.GetShellType,
                                   completion: @escaping (String) -> ()) {
        completion(genericScope.stringValue(forVariableName: iTermVariableKeyShell))
    }

    func detectSSHSessionRemoteCommand(detectSSHSession: RemoteCommand.DetectSSHSession,
                                       completion: @escaping (String) -> ()) {
        let value = screen.lastRemoteHost()?.isLocalhost ?? false
        completion("\(value)")
    }

    func getRemoteHostnameRemoteCommand(getRemoteHostname: RemoteCommand.GetRemoteHostname,
                                        completion: @escaping (String) -> ()) {
        completion(screen.lastRemoteHost()?.hostname ?? "Unknown")
    }

    func getUserIdentityRemoteCommand(getUserIdentity: RemoteCommand.GetUserIdentity,
                                      completion: @escaping (String) -> ()) {
        completion(screen.lastRemoteHost()?.username ?? NSUserName())
    }

    func getCurrentDirectoryRemoteCommand(getCurrentDirectory: RemoteCommand.GetCurrentDirectory,
                                          completion: @escaping (String) -> ()) {
        completion(genericScope.stringValue(forVariableName: iTermVariableKeySessionPath))
    }

    func setClipboardRemoteCommand(setClipboard: RemoteCommand.SetClipboard,
                                   completion: @escaping (String) -> ()) {
        NSPasteboard.general.declareTypes([.string], owner: NSApp)
        NSPasteboard.general.setString(setClipboard.text, forType: .string)
        completion("Copied")
    }

    func insertTextAtCursorRemoteCommand(insertTextAtCursor: RemoteCommand.InsertTextAtCursor,
                                         completion: @escaping (String) -> ()) {
        writeTaskNoBroadcast(insertTextAtCursor.text)
        completion("Inserted")
    }

    func deleteCurrentLineRemoteCommand(deleteCurrentLine: RemoteCommand.DeleteCurrentLine,
                                        completion: @escaping (String) -> ()) {
        writeTaskNoBroadcast("\u{15}")
    }

    func getManPageRemoteCommand(getManPage: RemoteCommand.GetManPage,
                                 completion: @escaping (String) -> ()) {
        let otsc = OneTimeStringClosure(completion)
        runningRemoteCommand.state = .futureString(otsc)
        if let conductor, conductor.framing {
            fetchRemoteManpage(from: conductor, command: getManPage.cmd) { otsc.call($0) }
            return
        }
        fetchLocalManpage(command: getManPage.cmd) { otsc.call($0) }
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
