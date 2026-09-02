//
//  PTYSession.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import WebKit

@objc
class PTYSessionClipping: NSObject {
    @objc let type: String
    @objc let title: String
    @objc let detail: String

    @objc(initWithType:title:detail:)
    init(type: String, title: String, detail: String) {
        self.type = type
        self.title = title
        self.detail = detail
    }

    @objc var dictionaryValue: [String: String] {
        return ["type": type, "title": title, "detail": detail]
    }

    @objc(initWithDictionary:)
    convenience init?(dictionary: [String: String]) {
        guard let type = dictionary["type"],
              let title = dictionary["title"],
              let detail = dictionary["detail"] else {
            return nil
        }
        self.init(type: type, title: title, detail: detail)
    }
}

@objc
class PTYSessionSwiftState: NSObject {
    // The iTermWorkgroupInstance owns the peer port (held
    // strongly by it and by the workgroup controller's dict).
    weak var peerPort: PTYSessionPeerPort?

    // The controller's dict keeps the instance alive
    // for the workgroup's lifetime; sessions never outlive their
    // workgroup (the sessionWillTerminate observer tears the
    // workgroup down if any tracked session goes away).
    weak var workgroupInstance: iTermWorkgroupInstance?

    // Mode this session inherited from its workgroup config when it was
    // spawned. .regular for everything that didn't come from a workgroup
    // (or that came from a regular-mode workgroup config). .codeReview
    // gates the deferred prompt-overlay launch path.
    var workgroupSessionMode: iTermWorkgroupSessionMode = .regular

    // When true, this session's `endAction` always reports .default no
    // matter what the profile's "Close Sessions On End" (KEY_SESSION_END_ACTION)
    // is. Set on workgroup-spawned member sessions (peers, splits, tabs)
    // so a profile sync — which reconciles non-overridden keys back to
    // the shared profile — can't quietly flip a member to Close and make
    // it auto-close when its program exits (e.g. a Diff pane whose
    // difftool finishes), which would tear the whole workgroup down. The
    // leader/main session is deliberately not marked, so it still honors
    // its profile.
    var forceDefaultEndAction = false

    // For .codeReview sessions, the raw (unwrapped, swifty-templated)
    // command — e.g. "claude \(codeReviewPrompt)". Cached so any future
    // relaunch (toolbar reload, broken-pipe restart announcement) can
    // re-present the prompt overlay against the original template.
    var codeReviewRawCommand: String?

    // For .codeReview sessions, the prompt text the user last submitted
    // from the overlay (which may be a preset or a hand-edited value).
    // nil until the first submission. When the overlay is re-presented
    // (toolbar reload, broken-pipe restart) this is used as the default
    // instead of the store's last-selected preset, so the user's prior
    // edits are preserved across reloads.
    var codeReviewLastUsedPrompt: String?

    // For .diff sessions whose spawn was deferred (the workgroup's git
    // poller hadn't reported any pending change yet at spawn time), the
    // captured closure that fires the launch request. Cleared by
    // firePendingDiffLaunch after it runs so a subsequent poll doesn't
    // re-launch the same session.
    var pendingDiffLaunch: (() -> Void)?

    // For .codeReview sessions, whether the "auto-send clippings when idle"
    // toolbar toggle is on. When on, the workgroup peer port sends this
    // session's clippings to the workgroup's main session each time the
    // review session transitions from working to idle. Runtime-only and
    // defaults off: re-entering a workgroup starts with the toggle off.
    var autoSendClippingsWhenIdle = false

    // For the main (root) session, whether the "auto-request review when
    // idle" toolbar toggle is on. When on, the workgroup peer port asks
    // the sole code-review session to run a review each time the main
    // session transitions from working to idle. Runtime-only and defaults
    // off, same as autoSendClippingsWhenIdle.
    var autoRequestReviewWhenIdle = false

    var delegateObservers = [(PTYSessionDelegate) -> ()]()

    // Canonical storage for this session's clippings. Sessions in a peer group
    // all delegate through PTYSessionPeerPort to the leader session's storage,
    // so this is only the active backing store on the leader (or on a solo
    // session). Non-leader sessions keep this empty.
    var clippings = [PTYSessionClipping]()

    // Past snapshots produced by "archive clippings". Oldest first. Each entry
    // is the full clippings list at the moment the user (or claude-code)
    // pressed Archive. Combined with `clippings` they form a timeline whose
    // tail is the live list.
    var clippingsArchive = [[PTYSessionClipping]]()

    // Which entry in the [archive..., live] timeline the view is showing.
    // -1 means the live list (`clippings`); 0..<clippingsArchive.count means
    // that archive entry. Anything else is treated as live. Persisted to
    // arrangements so re-opening a window restores the view position.
    var clippingsViewIndex = -1

    // Whether the user wants the clippings panel shown. Defaults to false so
    // a fresh launch shows nothing; add_clipping flips it to true. Lives on
    // the leader (parallel to `clippings`) and is exposed via the peer port
    // so all peers share it.
    var clippingsVisibilityFlag = false

    // Holds the modal panel used by the "+" button so it isn't deallocated
    // before the sheet finishes.
    var activeAddClippingPanel: AddClippingPanel?

    // ID of the chat hosted in this session's right-gutter panel, or nil if
    // none. A session owns at most one inline chat at a time.
    var inlineChatID: String?

    // Whether the inline chat panel is currently shown. The panel only
    // contributes to the right-extra width budget when this is true and
    // inlineChatID is non-nil.
    var inlineChatVisibilityFlag = true
}

// MARK: - AI Chat
extension PTYSession {
    var aiState: String {
        var items = [String]()
        if iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() {
            if let currentCommand, !currentCommand.isEmpty {
                items.append("This command is currently executing: \(currentCommand)")
            } else {
                items.append("The terminal is currently at the command prompt")
            }

            if let mark = screen.lastCommandMark(),
               let command = mark.fullCommand,
               mark.hasCode {
                items.append("The last command exited with status \(mark.code). That command was: \(command)")
            }
            items.append("The terminal size is \(screen.width()) columns wide by \(screen.height()) rows tall")
        }
        let shell = genericScope.stringValue(forVariableName: iTermVariableKeyShell)
        if !shell.isEmpty {
            items.append("The current shell is \(shell). Ensure commands you execute will work in this shell.")
        }
        if let remoteHost = screen.lastRemoteHost() {
            let username: String?
            if !remoteHost.isLocalhost, let host = remoteHost.hostname {
                items.append("The user is SSHed to \(host)")
                username = remoteHost.username
            } else {
                username = NSUserName()
            }
            if let username {
                items.append("The username is \(username)")
            }
        } else {
            items.append("The username is \(NSUserName())")
        }
        let pwd = genericScope.stringValue(forVariableName: iTermVariableKeySessionPath)
        if !pwd.isEmpty {
            items.append("The current working directory is \(pwd)")
        }
        return items.map { "<info>" + $0.escapedForHTML + "</info>" }.joined(separator: "\n")
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
            textview?.scrollLineNumberRange(
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
        // logicalSubSelections (not allSubSelections) so serializing during an
        // in-progress bidi character drag encodes LOGICAL buffer positions, not the
        // raw visual live range. Same coordinate contract as the get_selection API.
        for sub in selection.logicalSubSelections {
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
                              window: self.genericView?.window)
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
        // Keep the payload (a shell command string or arbitrary file contents) out of
        // the ring; the opt-in debug log still gets the whole command.
        RLog("execute remote command \(redacted: command, or: command.content.functionName)")
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
        case .getScreenContents(let getScreenContents):
            try ensureIsTerminal()
            try getScreenContentsRemoteCommand(getScreenContents: getScreenContents,
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
        case .restartSession(let restartSession):
            try ensureIsTerminal()
            try restartSessionRemoteCommand(restartSession: restartSession,
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
        let string = executeCommand.command + ";echo '-- FINISHED' \(uuid)\r"
        let willExpect = { [weak self] in
            _ = self?.writeTaskNoBroadcast(string)
        }
        let expectation = addExpectation("^-- FINISHED \(uuid)", after: nil, deadline: nil, willExpect: willExpect) { [weak self] _ in
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
                          coords: nil,
                          deduplicateDECDHL: true)
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
        var entries = [[String: String]]()
        let limit = getCommandHistory.limit
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if entries.count >= limit {
                return
            }
            if let command = mark.fullCommand {
                var entry: [String: String] = ["command": command]
                let guid = mark.guid
                if !guid.isEmpty {
                    entry["id"] = guid
                }
                entries.append(entry)
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries),
           let json = String(data: data, encoding: .utf8) {
            try completion(json, "Command history provided to AI.")
        } else {
            try completion("[]", "Command history provided to AI.")
        }
    }

    func getLastCommandRemoteCommand(getLastCommand: RemoteCommand.GetLastCommand,
                                     completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
                       "The last command execute can’t be provided because Shell Integration isn’t installed.")
            return
        }
        guard let command = screen.lastCommandMark()?.fullCommand else {
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
        try completion(currentCommandUpToCursor, "Current command provided to AI.")

    }

    func searchCommandHistoryRemoteCommand(searchCommandHistory: RemoteCommand.SearchCommandHistory,
                                           completion: @escaping (String, String) throws -> ()) rethrows {
        guard iTermShellHistoryController.sharedInstance().commandHistoryHasEverBeenUsed() else {
            try completion("Tell the user they need to install Shell Integration to access this information.",
                       "Command history is not available because Shell Integration isn’t installed.")
            return
        }
        var entries = [[String: String]]()
        screen.enumeratePrompts(from: nil, to: nil) { mark in
            if let command = mark.fullCommand, command.contains(searchCommandHistory.query) {
                var entry: [String: String] = ["command": command]
                let guid = mark.guid
                if !guid.isEmpty {
                    entry["id"] = guid
                }
                entries.append(entry)
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries),
           let json = String(data: data, encoding: .utf8) {
            try completion(json, "Command history provided to AI.")
        } else {
            try completion("[]", "Command history provided to AI.")
        }
    }

    func getCommandOutputRemoteCommand(getCommandOutput: RemoteCommand.GetCommandOutput,
                                       completion: @escaping (String, String) throws -> ()) rethrows {
        let range: VT100GridCoordRange
        let id = getCommandOutput.id
        if !id.isEmpty, let mark = screen.promptMark(withGUID: id) {
            range = screen.rangeOfOutput(forCommandMark: mark)
        } else {
            let absRange = textViewRangeOfLastCommandOutput()
            range = VT100GridCoordRangeFromAbsCoordRange(absRange, screen.totalScrollbackOverflow())
        }
        if range.start.x < 0 {
            try completion("The output is no longer available.",
                           "The command output wasn’t provided because it is no longer available.")
            return
        }
        let extractor = iTermTextExtractor(dataSource: screen)
        let content = extractor.content(in: VT100GridWindowedRangeMake(range, 0, 0),
                          attributeProvider: nil,
                          nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                          pad: false,
                          includeLastNewline: false,
                          trimTrailingWhitespace: true,
                          cappedAtSize: 16384,
                          truncateTail: false,
                          continuationChars: nil,
                          coords: nil,
                          deduplicateDECDHL: true)
        if let string = content as? String {
            try completion(string, "Command output provided to AI.")
        } else {
            try completion("The content could not be retrieved because of an unexpected error",
                           "The command output wasn’t provided because of an unexpected error.")
        }
    }

    func getTerminalSizeRemoteCommand(getTerminalSize: RemoteCommand.GetTerminalSize,
                                      completion: @escaping (String, String) throws -> ()) rethrows {
        try completion("\(screen.width()) columns wide by \(screen.height()) rows tall",
                   "Session size provided to AI.")
    }

    // Session-bound counterpart of the orchestrator's get_screen_contents.
    // Reuses the same WorkgroupIntrospection core and returns the identical
    // structured result the orchestrator emits, so the two tools behave the
    // same. On the alternate screen the result is only the current grid with
    // is_snapshot=true: there is no scrollback to reveal (this chat has no
    // scroll_wheel tool), so we present it as having no history.
    func getScreenContentsRemoteCommand(getScreenContents: RemoteCommand.GetScreenContents,
                                        completion: @escaping (String, String) throws -> ()) throws {
        let requestedLines = getScreenContents.lines > 0 ? getScreenContents.lines : nil
        let contents = WorkgroupIntrospection.screenContents(forSession: self,
                                                             requestedLines: requestedLines)
        let data = try JSONEncoder().encode(OrchestratorResult.screenContents(contents))
        let json = String(data: data, encoding: .utf8) ?? "{}"
        try completion(json, "Screen contents provided to AI.")
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
        let decoded: String
        do {
            decoded = try decodeAIBackslashEscapes(insertTextAtCursor.text)
        } catch {
            try completion("Error: \(error). Try again with a corrected text argument.",
                       "AI tried to insert text but the escape sequence was malformed.")
            return
        }
        // A terminal Return key sends CR (0x0D), not LF (0x0A). Many
        // raw-mode programs (shell line editors, REPLs, TUIs like Claude
        // Code) treat a bare LF as "insert a literal newline" rather than
        // "submit the line", so an AI-supplied \n often fails to act as
        // Return. Translate LF to CR here. Collapse CRLF to a single CR
        // first so we don't emit a double Return.
        let normalized = decoded
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
        writeTaskNoBroadcast(normalized)
        // A bare "Inserted" reads as ambiguous to the model (did anything
        // actually get typed?), which invites a duplicate insertion "to
        // be sure." Report the concrete character count so the result is
        // unmistakably a success.
        let count = normalized.count
        let noun = count == 1 ? "character" : "characters"
        try completion("Inserted \(count) \(noun).", "Text inserted by AI.")
    }

    func deleteCurrentLineRemoteCommand(deleteCurrentLine: RemoteCommand.DeleteCurrentLine,
                                        completion: @escaping (String, String) throws -> ()) rethrows {
        writeTaskNoBroadcast("\u{15}")
        try completion("Done", "Current line deleted by AI.")
    }

    func restartSessionRemoteCommand(restartSession: RemoteCommand.RestartSession,
                                     completion: @escaping (String, String) throws -> ()) rethrows {
        // isRestartable() guards -restartSession, which asserts on entry. A
        // session with no restartable program (e.g. a live tmux or SSH session)
        // has nothing to relaunch, so report that back rather than aborting.
        guard isRestartable() else {
            try completion("This session cannot be restarted.",
                           "AI tried to restart the session but it is not restartable.")
            return
        }
        // restart() is the Swift-refined name for ObjC -restartSession. This
        // kills any running jobs and relaunches the session's command, exactly
        // like the Session > Restart Session menu (but without its confirmation
        // warning, since the AI permission prompt already gated this).
        restart()
        try completion("The session is being restarted.",
                       "Session restarted by AI.")
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
        if let conductor, conductor.framing {
            try createRemoteFile(createFile, conductor: conductor, completion: completion)
            return
        }
        try createLocalFile(createFile, completion: completion)
    }

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
            RLog("Session \(self) running \(redacted: command, or: "len=\(command.count)")")
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
        conductor.runRemoteCommand("man \((command as NSString).withEscapedShellCharacters(includingNewlines: true)) | cat") { data, status in
            if status != 0 {
                completion("There was a problem running man on the remote host. It exited with status \(status)")
            } else {
                completion(data.stringOrHex)
            }
        }
    }
    private func searchBrowser(args: RemoteCommand.SearchBrowser, completion: @escaping (String, String) throws -> ()) rethrows {
        view?.browserViewController?.findOnPage(query: args.query, maxResults: 20, contextLength: 100) { result in
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
        view?.browserViewController?.loadURL(url) { error in
            if let error {
                try? completion("The web page could not be loaded: " + error.localizedDescription, "Navigation failed")
            } else {
                try? completion("The web page was loaded successfully.", "Navigation complete")
            }
        }
    }

    private func webSearch(args: RemoteCommand.WebSearch, completion: @escaping (String, String) throws -> ()) rethrows {
        view?.browserViewController?.doWebSearch(for: args.query) { [weak self] error in
            if let error {
                RLog("\(error)")
                try? completion("Web search is not currently available", "Web search failed")
                return
            }
            self?.view?.browserViewController?.convertToMarkdown(skipChrome: true) { (result: Result<String, Error>) in
                if let markdown = result.successValue {
                    try? completion(markdown, "Web search complete")
                } else {
                    try? completion("Web search is not currently availble", "Web search failed")
                }
            }
        }
    }

    private func getURL(args: RemoteCommand.GetURL, completion: @escaping (String, String) throws -> ()) rethrows {
        if let url = view?.browserViewController?.webView.url {
            try completion(url.absoluteString, "URL provided")
        } else {
            try completion("about:blank", "URL provided")
        }
    }

    private func readWebPage(args: RemoteCommand.ReadWebPage, completion: @escaping (String, String) throws -> ()) rethrows {
        view?.browserViewController?.convertToMarkdown(skipChrome: false) { (result: Result<String, Error>) in
            switch result {
            case .success(let text):
                let lines = text.components(separatedBy: "\n")
                guard args.startingLineNumber < lines.count else {
                    try? completion("The page contains \(lines.count) lines. Your request was out of bounds.",
                                   "AI attempted to read past the end of the page")
                    return
                }
                let sub = lines[args.startingLineNumber..<min(lines.count, args.startingLineNumber + args.numberOfLines)]
                let combined = sub.joined(separator: "\n") + "\n\n[There are a total of \(lines.count) lines of text in this web page.]"
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
            RLog("Invalid mode in queryValue \(queryValue)")
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
                RLog("Invalid range bounds in queryValue \(queryValue)")
                return nil
            }
            return lower..<upper
        }()

        return SubSelectionSerializationInfo(mode: mode, start: start, end: end, windowedRange: windowedRange)
    }

    func absRange(_ screen: VT100Screen) -> VT100GridAbsWindowedRange? {
        let snapshot = screen.snapshotForcingPrimaryGrid(false)
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
        guard let textview else { return .zero }
        let startRect = textview.rect(for: coordRange.start)
        let endRect = textview.rect(for: coordRange.end)
        let textViewRect = startRect.union(endRect)
        let windowRect = textview.convert(textViewRect, to: nil)
        let screenRect = textview.window?.convertToScreen(windowRect) ?? .zero
        return screenRect
    }

    func pathCompletionHelperWindow(_ helper: PathCompletionHelper) -> NSWindow? {
        return textview?.window
    }

    func pathCompletionHelperFont(_ helper: PathCompletionHelper) -> NSFont {
        return textview?.fontTable.asciiFont.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper, didSelect suggestion: String) {
        let escaped = (suggestion as NSString).withBackslashEscapedShellCharacters(includingNewlines: true)
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
        let restorableSession = self.restorableSession
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
            RLog("No buried session with channel uid \(uid)")
            return
        }
        delegate?.swapSession(self, withBuriedSession: session)
    }

}

@objc
extension PTYSession {
    func smartSelectAllVisible() {
        DLog("begin");
        guard let textview, let view else { return }
        textview.removeContentNavigationShortcutsAndSearchResults(false)
        let visibleLines = textview.rangeOfVisibleLines
        let overflow = screen.totalScrollbackOverflow()
        let y = VT100GridRangeNoninclusiveMaxLL(visibleLines) + overflow
        textview.findOnPageHelper.setStartPoint(VT100GridAbsCoordMake(0, y))
        let findDriver = view.findDriverCreatingIfNeeded

        let regex = regularExpressonForNonLowPrecisionSmartSelectionRulesCombined
        DLog("findDriver=\(findDriver.d) regex=\(regex)")
        var done = false
        let visibleAbsLines = NSMakeRange(Int(visibleLines.location) + Int(overflow),
                                          Int(visibleLines.length))
        var indexes = IndexSet(integersIn: Range(visibleAbsLines)!)
        findDriver?.closeViewAndDoTemporarySearch(for: regex,
                                                  mode: .caseSensitiveRegex,
                                                  extendResultsAcrossSoftBoundaries: false) { [weak self] linesSearched in
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
        let light = NSColor(displayP3Red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        let dark = NSColor(displayP3Red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        // A browser session has no colorForMargins, so the fallback below would use the
        // profile's foreground color, which does not track the page background. Pick the
        // text color from the page background's darkness instead. minimalBrowserTintColor
        // is the shared accessor (also gated on the minimal tab style), so this stays in
        // sync with effectiveUnprocessedBackgroundColor and colorMapShouldBeInDarkMode.
        if let bg = minimalBrowserTintColor {
            return bg.isDark ? light : dark
        }
        if let color = textview?.colorForMargins {
            return color.isDark ? light : dark
        }
        return textview?.colorMap.color(forKey: kColorMapForeground) ?? NSColor.textColor
    }
}

extension PTYSession {
    @objc(openURL:)
    func open(url: URL) {
        guard view?.isBrowser == true else {
            RLog("Can't open \(url), not a browser")
            return
        }
        view?.browserViewController?.loadURL(url.absoluteString)
    }

    @objc
    var webSiteTitle: String? {
        return view?.browserViewController?.title
    }

    @objc
    func loadDeferredURLIfNeeded() {
        view?.browserViewController?.loadDeferredURLIfNeeded()
    }
}


extension PTYSession {
    @discardableResult
    @objc
    func becomeBrowser(configuration: WKWebViewConfiguration,
                       restorableState: NSDictionary?) -> Bool {
        if !iTermBrowserGateway.browserAllowed(checkIfNo: true) {
            return false
        }
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
            KEY_ENABLE_PROGRESS_BARS: nullValue,
            KEY_PROGRESS_BAR_HEIGHT: nullValue,
            KEY_PROGRESS_BAR_COLOR_SCHEME: nullValue,
            KEY_ALLOW_TITLE_SETTING: nullValue,
            KEY_DISABLE_PRINTING: nullValue,
            KEY_SCROLLBACK_WITH_STATUS_BAR: nullValue,
            KEY_SCROLLBACK_IN_ALTERNATE_SCREEN: nullValue,
            KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED: nullValue,
            KEY_SEND_BELL_ALERT: nullValue,
            KEY_SEND_IDLE_ALERT: nullValue,
            KEY_SEND_NEW_OUTPUT_ALERT: nullValue,
            KEY_SEND_TERMINAL_GENERATED_ALERT: nullValue,
            KEY_SUPPRESS_ALERTS_IN_ACTIVE_SESSION: nullValue,
            KEY_ALLOW_CHANGE_CURSOR_BLINK: nullValue,
            KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY: nullValue,
            KEY_RUN_COMMAND_IN_LOGIN_SHELL: nullValue,
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
            KEY_SHOW_OFFSCREEN_COMMANDLINE_FOR_CURRENT_COMMAND: nullValue,
            KEY_TMUX_NEWLINE: nullValue,
            KEY_PROMPT_PATH_CLICK_OPENS_NAVIGATOR: nullValue,
            KEY_AUTOLOG: nullValue,
            KEY_ARCHIVE: nullValue,
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
            KEY_HARMONIZE_256_COLORS: nullValue,
            KEY_HARMONIZE_256_COLORS + COLORS_LIGHT_MODE_SUFFIX: nullValue,
            KEY_HARMONIZE_256_COLORS + COLORS_DARK_MODE_SUFFIX: nullValue,
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

        if iTermProfilePreferences.bool(forKey: KEY_BROWSER_DEV_NULL, inProfile: justProfile) {
            setSessionSpecificProfileValues([KEY_UNDO_TIMEOUT: 0])
        }
        let model: ProfileModel
        let guid: String
        let myGuid = justProfile[KEY_GUID]! as! String
        if isDivorced {
            if let originalGuid = justProfile[KEY_ORIGINAL_GUID] as? String,
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
        guard let textview, let view else { return false }
        let vc = iTermBrowserViewController(
            configuration: configuration,
            sessionGuid: guid,
            profileObserver: iTermProfilePreferenceObserver(
                guid: justProfile[KEY_GUID]! as! String,
                model: isDivorced ? ProfileModel.sessionsInstance() : ProfileModel.sharedInstance()),
            profileMutator: iTermProfilePreferenceMutator(
                model: model,
                guid: guid),
            indicatorsHelper: textview.indicatorsHelper)
        vc.delegate = self
        view.setBrowserViewController(
            vc, initialURL: iTermProfilePreferences.string(forKey: KEY_INITIAL_URL,
                                                           inProfile: justProfile),
            restorableState: restorableState as? [AnyHashable: Any])
        // Seed the session name only when there isn't one already, so it is non-empty
        // before the first page-title callback for a fresh session, WITHOUT clobbering a
        // name restored from a saved arrangement (the last page title). The latter must
        // survive even if the page fails to reload (offline, or a now-missing file:// URL).
        // didUpdateTitle overwrites it once WebKit reports a title, and the session-name
        // component is guaranteed for browsers by iTermSessionTitleBuiltInFunction, so a
        // seeded or restored name shows regardless of the profile's title components.
        if !hasExistingSessionName {
            setUntrustedIconName(justProfile[KEY_NAME] as? String ?? iTermBrowserSessionTitle.defaultProfileName)
        }
        return true
    }

    @objc
    func terminateBrowser(){
        view?.browserViewController?.terminate()
    }
}

@objc
extension PTYSession {
    var defaultAccountNameForPasswordManager: String? {
        if isBrowserSession() {
            return view?.browserViewController?.currentURL?.host
        }
        return nil
    }
}

@objc
extension PTYSession {
    func willOpenEditSessionSettings() {
        if var triggerDicts = self.justProfile[KEY_TRIGGERS] as? [NSDictionary] {
            var haveStats = false
            screen.performBlock(joinedThreads: { _, state, _ in
                let stats = state.triggerStats()
                if stats.count == triggerDicts.count {
                    for i in 0..<stats.count {
                        if var dict = triggerDicts[i] as? [String: Any] {
                            haveStats = true
                            dict[kTriggerPerformanceKey] = stats[i].dictionaryValue
                            triggerDicts[i] = dict as NSDictionary
                        }
                    }
                }
            })
            if haveStats {
                setSessionSpecificProfileValues([KEY_TRIGGERS: triggerDicts])
            }
        }
    }
}

@objc
extension PTYSession {
    func saveArchive() {
        guard let destination = iTermProfilePreferences.string(forKey: KEY_ARCHIVEDIR, inProfile: justProfile) else {
            RLog("No archive dir in profile")
            return
        }
        let term = delegate?.realParentWindow() as? PseudoTerminal
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        let dateTime = formatter.string(from: now)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ",", with: "")
        let filename = "\(dateTime) - \(name).itermarchive"
        let url = URL(fileURLWithPath: destination).appendingPathComponent(filename)
        saveArchive(to: iTermSavePanelItem(filename: url.path, host: .localhost), term: term)
    }

    @objc(saveArchiveTo:term:)
    func saveArchive(to location: iTermSavePanelItem, term: PseudoTerminal?) {

        let arrangement: [AnyHashable: Any]?
        if let term {
            arrangement = term.arrangement(with: self)
        } else {
            arrangement = PseudoTerminal.arrangement(with: self)
        }
        guard let data = (arrangement as? NSDictionary)?.propertyListData() else {
            DLog("Invalid plist at \(((arrangement as? NSDictionary)?.it_invalidPathInPlist()).d)")
            return
        }
        if location.host.isLocalhost {
            // This has to be synchronous for saving archives on app quit.
            do {
                try data.write(to: URL(fileURLWithPath: location.filename))
                ArchivesMenuBuilder.shared?.didAdd(path: location.filename)
            } catch {
                RLog("Saving to \(location.description) failed: \(error)")
                iTermNotificationController.sharedInstance().notify(
                    "Archiving to \(location.displayName) failed: \(error.localizedDescription)")
            }
            return
        }
        Task { @MainActor in
            do {
                try await location.upload(data: data)
                if location.host.isLocalhost {
                    ArchivesMenuBuilder.shared?.didAdd(path: location.filename)
                }
            } catch {
                RLog("Saving to \(location.description) failed: \(error)")
                iTermNotificationController.sharedInstance().notify(
                    "Archiving to \(location.displayName) failed: \(error.localizedDescription)")
            }
        }
    }
}

extension PTYSession: AutomaticProfileSwitchingSessionDelegate {
    func automaticProfileSwitchingSessionExpressionNeedEvaluation(_ session: AutomaticProfileSwitchingSession) {
        if iTermProfilePreferences.bool(forKey: KEY_PREVENT_APS, inProfile: justProfile) {
            return
        }
        // apsContext is initialized in -setPreferencesFromAddressBookEntry:.
        // This delegate callback only fires after that runs, so this is
        // belt-and-suspenders.
        guard let apsContext else { return }
        automaticProfileSwitcher.markDirty()
        automaticProfileSwitcher.setHostname(genericScope.value(forVariableName: iTermVariableKeySessionHostname) as? String,
                                             username: genericScope.value(forVariableName: iTermVariableKeySessionUsername) as? String,
                                             path: genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String,
                                             job: genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String,
                                             commandLine: genericScope.value(forVariableName: iTermVariableKeySessionCommandLine) as? String,
                                             expressionValueProvider: apsContext)
    }
}

// MARK: - Session Note

extension PTYSession {
    @objc func textViewEditSessionNote() {
        guard let view else { return }
        if view.isSessionNoteVisible {
            view.hideSessionNote()
        } else {
            if sessionNoteModel == nil {
                sessionNoteModel = SessionNoteModel()
            }
            view.showSessionNote(with: sessionNoteModel!)
        }
    }
}

extension PTYSession {
    var peerPort: PTYSessionPeerPort? {
        get {
            swiftState.peerPort
        }
        set {
            swiftState.peerPort = newValue
        }
    }

    // Read-only bridge for ObjC. We deliberately don't make the Swift
    // `peerPort` property `@objc` directly: doing so would also expose
    // the setter to ObjC, which lets callers bypass `set(peerPort:)`'s
    // "self.peerPort == nil" invariant. ObjC consumers that need to
    // *read* the peer port (e.g. the toolbelt's window-contains check)
    // go through this method.
    @objc(peerPort)
    func _objcPeerPort() -> PTYSessionPeerPort? {
        return peerPort
    }

    func set(peerPort: PTYSessionPeerPort) {
        it_assert(self.peerPort == nil)
        self.peerPort = peerPort
    }

    // Display label identifying this peer within its workgroup peer
    // group, or nil when the session isn't a member of a multi-peer
    // workgroup port. Used by the Session Status toolbelt tool to
    // disambiguate rows for sessions that share a tab/workgroup name.
    var peerDisplayLabel: String? {
        guard let port = peerPort as? iTermWorkgroupPeerPort,
              port.peerCount > 1,
              let id = port.identifier(for: self) else {
            return nil
        }
        return port.label(forPeerID: id)
    }

    // Workgroup runtime: when a workgroup is active on this session,
    // `workgroupInstance` points at the per-entry state owner.
    @objc var workgroupInstance: iTermWorkgroupInstance? {
        get { swiftState.workgroupInstance }
        set { swiftState.workgroupInstance = newValue }
    }

    // Workgroup-mode tag set by the spawn path. .codeReview triggers the
    // deferred-launch / prompt-overlay path; .regular runs the program
    // immediately as before.
    @objc var workgroupSessionMode: iTermWorkgroupSessionMode {
        get { swiftState.workgroupSessionMode }
        set { swiftState.workgroupSessionMode = newValue }
    }

    // See SwiftState.forceDefaultEndAction. Read by -[PTYSession endAction].
    @objc var forceDefaultEndAction: Bool {
        get { swiftState.forceDefaultEndAction }
        set { swiftState.forceDefaultEndAction = newValue }
    }

    // Raw (unwrapped, swifty-templated) command for .codeReview sessions.
    // Used by reload paths (toolbar reload, restart-after-exit) to
    // re-present the prompt overlay against the original template.
    @objc var codeReviewRawCommand: String? {
        get { swiftState.codeReviewRawCommand }
        set { swiftState.codeReviewRawCommand = newValue }
    }

    // Prompt text last submitted from the code-review overlay; used as the
    // default when re-presenting the overlay so prior (possibly hand-edited)
    // input is preserved across reloads. See PTYSession+CodeReviewPrompt.
    @objc var codeReviewLastUsedPrompt: String? {
        get { swiftState.codeReviewLastUsedPrompt }
        set { swiftState.codeReviewLastUsedPrompt = newValue }
    }

    // Closure that fires the deferred launch for a .diff-mode session
    // whose spawn was held back because the workgroup’s git poller had
    // not yet reported a pending change. iTermWorkgroupInstance calls
    // firePendingDiffLaunch from gitPollerDidUpdate once changes appear.
    var pendingDiffLaunch: (() -> Void)? {
        get { swiftState.pendingDiffLaunch }
        set { swiftState.pendingDiffLaunch = newValue }
    }

    @objc var hasPendingDiffLaunch: Bool {
        return swiftState.pendingDiffLaunch != nil
    }

    // Run the captured deferred-launch closure (if any) and clear it so
    // a later gitPollerDidUpdate doesn’t fire a second launch. Also
    // dismiss the waiting overlay (if presented); the actual launch
    // will paint terminal output onto a freshly-cleared session view.
    @objc
    func firePendingDiffLaunch() {
        let closure = swiftState.pendingDiffLaunch
        RLog("PTYSession[\(guid)]: firePendingDiffLaunch hasClosure=\(closure != nil)")
        swiftState.pendingDiffLaunch = nil
        // While the diff-waiting overlay is up, -mainResponder routes to
        // its Run Anyway button, so the peer swap that revealed this
        // session parked the window's first responder on that button.
        // Dismissing the overlay removes that button; without reassigning,
        // the window is left with a dead first responder and typing beeps
        // (the first-visit "command runs but the terminal isn't first
        // responder" bug). If the overlay owns focus right now, hand it
        // back to the terminal once the overlay is gone and the deferred
        // command has launched — mainResponder then resolves to the
        // freshly-running text view.
        let overlayOwnedFocus = diffWaitingOverlayOwnsFirstResponder
        view?.dismissDiffWaitingPromptOverlay()
        closure?()
        if overlayOwnedFocus {
            view?.window?.makeFirstResponder(mainResponder)
        }
    }

    // True when the diff-waiting overlay (or one of its subviews, e.g.
    // its Run Anyway button — see -mainResponder) currently holds the
    // window's first responder. firePendingDiffLaunch consults this
    // before tearing the overlay down so it only restores focus to the
    // terminal when the overlay actually owned it, and leaves first
    // responder alone when a poller-driven launch fires while the user's
    // focus is elsewhere.
    private var diffWaitingOverlayOwnsFirstResponder: Bool {
        guard let overlay = view?.diffWaitingPromptOverlay,
              let responder = overlay.window?.firstResponder as? NSView else {
            return false
        }
        return responder.isDescendant(of: overlay)
    }

    // Drop the initial-spawn waiting overlay onto the session view.
    // Called from the .diff spawn paths immediately after
    // pendingDiffLaunch is set, so the user sees an explanation rather
    // than a blank screen the moment they activate the buried peer
    // (or, for split/tab .diff sessions, the moment the spawn lands in
    // the window). The Run Anyway button routes back through
    // firePendingDiffLaunch so the manual override and the poller-
    // driven path go through the same dismiss + launch sequence.
    @objc
    func presentDiffWaitingPromptOverlay() {
        guard let sessionView: SessionView = view else {
            RLog("PTYSession[\(guid)]: presentDiffWaitingPromptOverlay aborted, session has no view")
            return
        }
        sessionView.presentDiffWaitingPromptOverlay { [weak self] in
            self?.firePendingDiffLaunch()
        }
    }

    // Drop the queued-reload waiting overlay onto the session view.
    // Distinct from the initial-spawn variant: the previous program
    // is still rendered on the terminal underneath, so the text says
    // "Reload queued" rather than "waiting to start" and there's a
    // Cancel button that clears pendingDiffLaunch without firing it
    // (otherwise an accidental Reload click on a clean tree would
    // queue a restart that the next poll tick fires, killing the
    // visible output).
    @objc
    func presentDiffWaitingPromptOverlayForQueuedReload() {
        guard let sessionView: SessionView = view else {
            RLog("PTYSession[\(guid)]: presentDiffWaitingPromptOverlayForQueuedReload aborted, session has no view")
            return
        }
        sessionView.presentDiffWaitingPromptOverlayForQueuedReload(
            onRunAnyway: { [weak self] in
                self?.firePendingDiffLaunch()
            },
            onCancel: { [weak self] in
                // Clear the closure without firing it: the user picked
                // Cancel because they don't want to restart after all.
                self?.pendingDiffLaunch = nil
            })
    }

    // Reload entry point for .diff-mode workgroup sessions. Handles
    // all three runtime states:
    //
    //   A) Initial spawn still waiting: pendingDiffLaunch is set, no
    //      program has run yet. If the poller now reports pending
    //      changes, fire the stashed closure (which is the original
    //      attachOrLaunch). Otherwise the overlay is already up; do
    //      nothing and let the next poll tick fire it.
    //
    //   B) Program is running or restartable: if there are pending
    //      changes, restart() immediately. Otherwise install a fresh
    //      restart() closure as pendingDiffLaunch and re-present the
    //      waiting overlay so a subsequent poll tick (or Run Anyway)
    //      re-runs the command. Re-checks isRestartable() inside the
    //      closure because the program may exit between the click and
    //      the fire, and -restart asserts isRestartable on entry.
    //
    //   C) Not restartable and no pending launch: nothing to do.
    //
    // Called from both the peer-port and instance-side reload
    // delegates so a reload button on either a peer or a non-peer
    // (split/tab) .diff session lands here. Both call sites bypass
    // the global isRestartable() guard for .diff because State A is a
    // legitimately reloadable state even though _program is nil.
    //
    // `resolveCommand` yields the login-shell-wrapped diff command
    // matching the file picker's selection AT THE MOMENT IT RUNS
    // (per-file when a file is picked, All Files otherwise). It is
    // evaluated as late as possible: immediately for the ready path,
    // or inside the deferred pendingDiffLaunch closure at fire time
    // (the next poll tick or Run Anyway), so a picker pick or gitBase
    // change between the reload click and the actual relaunch is
    // reflected. Reload must run this rather than the session's
    // last-launched _program, because the two can silently diverge:
    // when the file the popup was on stops being a diffable change, a
    // git poll resets the popup back to "All Files" in
    // CCDiffSelectorItem.set(fileStatuses:) without restarting the
    // session, leaving _program pointed at a now-clean per-file diff.
    // Replaying that _program runs `git difftool` on a file with no
    // changes, which prints nothing and exits 0, ending the session
    // instead of re-diffing. A nil resolver (or one that yields nil)
    // falls back to a plain restart() for callers (e.g. arrangement
    // restoration) that have no selector selection to resolve.
    func reloadDiffWithDeferralIfNeeded(resolveCommand: (() -> String?)? = nil) {
        let ready = workgroupInstance?.diffLaunchReady ?? false
        RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded ready=\(ready) hasPendingDiffLaunch=\(hasPendingDiffLaunch) restartable=\(isRestartable())")
        if hasPendingDiffLaunch {
            if ready {
                RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded firing pending diff launch (State A)")
                firePendingDiffLaunch()
            } else {
                RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded waiting, launch not ready (State A)")
            }
            return
        }
        guard isRestartable() else {
            RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded aborted, not restartable and no pending launch (State C)")
            return
        }
        // No inner isRestartable() re-check inside the closure: under
        // current invariants -isRestartable becomes true once _program
        // is assigned and never flips back (no code path clears
        // _program; browser-ness is fixed at session creation). The
        // outer guard is enough, so the closure only needs the weak
        // self check.
        let restartWithCurrentSelection: () -> Void = { [weak self] in
            if let command = resolveCommand?() {
                self?.restart(withCommand: command)
            } else {
                self?.restart()
            }
        }
        if ready {
            RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded restarting immediately (State B, ready)")
            restartWithCurrentSelection()
            return
        }
        RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded queuing restart and showing waiting overlay (State B, not ready)")
        pendingDiffLaunch = restartWithCurrentSelection
        // Queued-reload variant of the overlay: the previous diff
        // output is still on screen behind the panel. Cancel clears
        // pendingDiffLaunch without firing it, so an accidental
        // Reload click can be undone.
        presentDiffWaitingPromptOverlayForQueuedReload()
    }

    // Whether the user can currently see this session: it has a live
    // delegate (a buried peer has none) and its tab is the selected one.
    // Gates the deferred .diff launch so the diff runs against the tree
    // as it stands when the session is actually shown, not whenever the
    // poller first happened to see a change.
    var isVisibleForDeferredDiff: Bool {
        return delegate?.sessionBelongsToVisibleTab() ?? false
    }

    // Called when a .diff session may have become visible (a peer swapped
    // into its tab, or a tab selected). The initial diff launch is
    // deferred until the session is actually shown, so if it is now
    // visible and the poller already reports diffable changes, fire it
    // rather than making the user wait for the next poll tick. If there's
    // nothing diffable yet, the "waiting for changes" overlay stays up
    // and the next poll tick fires it (the session is visible now, so
    // fireDeferredDiffLaunches' gate passes).
    //
    // The isVisibleForDeferredDiff guard is load-bearing: a peer swap can
    // complete on a background tab (workgroup restoration across tabs, a
    // programmatic reveal), and firing there would run the diff against
    // the swap-in-time tree instead of what's on screen when the user
    // first sees it. A background swap is a no-op here; the tab-select
    // hook or the next poll tick picks the session up once it truly
    // reaches the foreground.
    //
    // This only ever fires the one deferred launch: firePendingDiffLaunch
    // clears the closure, so re-showing a diff that already ran does
    // nothing. Switching between peers never re-runs the diff.
    @objc
    func fireDeferredDiffLaunchIfVisibleNow() {
        guard workgroupSessionMode == .diff,
              hasPendingDiffLaunch,
              isVisibleForDeferredDiff,
              workgroupInstance?.diffLaunchReady == true else {
            return
        }
        firePendingDiffLaunch()
    }

    // Build a peer session for a workgroup's configured peer, driven
    // by an iTermWorkgroupSessionConfig config (profile override, command
    // override, buried until activated). `workgroupInstanceID` is
    // injected as ITERM_WORKGROUP_ID in the launch request so the
    // peer's shell sees the per-entry workgroup id.
    func makeWorkgroupPeer(config: iTermWorkgroupSessionConfig,
                           workgroupInstanceID: String) -> iTermPromise<PTYSession> {
        return iTermPromise<PTYSession> { seal in
            withDelegate { [weak self] delegate in
                guard let self else {
                    seal.reject(iTermError("Session terminated"))
                    return
                }
                asyncInitialDirectoryForNewSessionBased { [weak self] oldCWD in
                    guard let self else {
                        seal.reject(iTermError("Session terminated"))
                        return
                    }
                    let factory = iTermSessionFactory()
                    guard var profile = self.profile else {
                        seal.reject(iTermError("Session has no profile"))
                        return
                    }
                    guard let myView = self.view else {
                        seal.reject(iTermError("Session has no view"))
                        return
                    }
                    if let guid = config.profileGUID,
                       let override = ProfileModel.sharedInstance()?
                        .bookmark(withGuid: guid) {
                        profile = override
                    }
                    // Workgroup-spawned sessions must not auto-close when
                    // their command exits (a git-diff peer would vanish the
                    // moment diff finishes), and closing one should prompt
                    // on Cmd-W since it tears the whole workgroup down.
                    // Matches WorkgroupSessionSpawner's split/tab behavior:
                    // always prompt on close, never auto-close on exit.
                    profile[KEY_PROMPT_CLOSE] = PROMPT_ALWAYS
                    profile[KEY_SESSION_END_ACTION] =
                        iTermSessionEndAction.default.rawValue
                    // Browser profile + configured URL: seed
                    // KEY_INITIAL_URL so the browser session's
                    // deferred-URL load picks it up.
                    if !config.urlString.isEmpty,
                       let customCommand = profile[KEY_CUSTOM_COMMAND as String] as? String,
                       customCommand == kProfilePreferenceCommandTypeBrowserValue {
                        profile[KEY_INITIAL_URL as String] = config.urlString
                    }

                    let newSession = factory.newSession(withProfile: profile,
                                                        parent: self)
                    // Durably pin the default end action: the profile
                    // override above sets the initial value, but a later
                    // profile sync can revert a non-overridden key to the
                    // shared profile's Close. This flag can't be reverted,
                    // so the peer never auto-closes on program exit.
                    newSession.forceDefaultEndAction = true
                    newSession.setScreenSize(myView.bounds.size,
                                             parent: delegate.realParentWindow())
                    newSession.setSize(screen.size)
                    if let newSessionView = newSession.view {
                        newSessionView.scrollview.hasVerticalScroller = myView.scrollview.hasVerticalScroller
                        newSessionView.scrollview.lineScroll = myView.scrollview.lineScroll
                        newSessionView.scrollview.pageScroll = myView.scrollview.pageScroll
                    }
                    if let imagePath = backgroundImagePath {
                        newSession.backgroundImagePath = imagePath
                    }
                    newSession.setPreferencesFromAddressBookEntry(profile)
                    newSession.loadInitialColorTableAndResetCursorGuide()
                    newSession.screen.resetTimestamps()

                    if ProfileModel.sessionsInstance().bookmark(withGuid: (newSession.justProfile[KEY_GUID] as! String)) != nil && isDivorced {
                        newSession.inheritDivorce(
                            from: self,
                            decree: "Workgroup peer of session with guid \(d(profile[KEY_GUID]))")
                    }
                    // Workgroup commands run via /usr/bin/login +
                    // ShellLauncher so dotfiles are sourced and the
                    // user's interactive PATH/aliases are visible.
                    // KEY_RUN_COMMAND_IN_LOGIN_SHELL doesn't apply
                    // here — the launch request below feeds `command`
                    // into the launcher directly, bypassing the
                    // bookmarkCommandSwiftyString: wrapping path.
                    newSession.workgroupSessionMode = config.mode
                    let urlString = config.urlString.isEmpty ? nil : config.urlString

                    // .codeReview mode defers the entire spawn: bury and
                    // fulfill the promise immediately so the workgroup
                    // can activate this peer (showing its overlay), then
                    // present the prompt overlay in the session's view.
                    // The Start handler builds and fires the launch
                    // request when the user is ready.
                    //
                    // The bury() is peer-specific: peers live in the
                    // same tab as the leader and need to be in the
                    // buried-sessions registry so the workgroup's
                    // mode-switch path can swap them in via
                    // sessionActivateSession:amongPeers:moveToolbar:.
                    // The parallel deferred-launch path in
                    // DefaultWorkgroupSessionSpawner.launch (for
                    // .codeReview splits/tabs) does NOT bury — split
                    // and tab sessions are visible in the window the
                    // moment they're inserted, so there's nothing to
                    // unbury from later.
                    if config.mode == .codeReview {
                        newSession.bury()
                        newSession.presentCodeReviewPromptOverlay(
                            rawCommand: config.command,
                            urlString: urlString,
                            objectType: .paneObject,
                            factory: factory,
                            windowController: nil,
                            oldCWD: oldCWD,
                            workgroupInstanceID: workgroupInstanceID)
                        seal.fulfill(newSession)
                        return
                    }

                    if config.mode == .diff {
                        // Bury immediately and defer the actual launch
                        // until the workgroup’s git poller reports a
                        // pending change (see firePendingDiffLaunch).
                        // The seal is fulfilled now so the peer port
                        // wires up the session and the workgroup is
                        // not blocked waiting on this peer.
                        //
                        // `factory` is a local with no other strong
                        // reference once this closure unwinds, so it
                        // has to be captured strongly here. Otherwise
                        // it deallocs before the poller's first update
                        // and the deferred launch silently no-ops. The
                        // closure itself dies after firePendingDiffLaunch
                        // clears it, so there's no long-lived retain.
                        //
                        // The captured `oldCWD` is the leader's PWD at
                        // spawn time; the deferred launch uses it
                        // as-is rather than re-resolving when the
                        // closure fires. A workgroup peer is supposed
                        // to mirror the entry point, so if the leader
                        // cd's elsewhere later the diff peer keeps
                        // diffing the repo the workgroup was opened
                        // on.
                        //
                        // gitBase is intentionally re-resolved at fire
                        // time using the workgroup instance's current
                        // value. The caller (iTermWorkgroupInstance.enter
                        // and friends) hands us an unsubstituted config
                        // for .diff, so a gitBase change while the
                        // deferred launch is pending automatically
                        // propagates without the gitBase delegate path
                        // having to rebuild this closure.
                        newSession.bury()
                        newSession.presentDiffWaitingPromptOverlay()
                        let cfg = config
                        newSession.pendingDiffLaunch = { [weak newSession] in
                            guard let newSession else { return }
                            let base = newSession.workgroupInstance?.currentGitBase
                                ?? CCGitBaseSelectorItem.defaultBase
                            let resolved = cfg.resolvedCommand(gitBase: base)
                            let cmd = resolved.isEmpty
                                ? nil
                                : ITAddressBookMgr.commandByWrapping(inLoginShell: resolved)
                            let request = iTermSessionAttachOrLaunchRequest(
                                session: newSession,
                                canPrompt: false,
                                objectType: .paneObject,
                                hasServerConnection: false,
                                serverConnection: iTermGeneralServerConnection(),
                                urlString: urlString,
                                allowURLSubs: false,
                                environment: ["ITERM_WORKGROUP_ID": workgroupInstanceID],
                                customShell: nil,
                                oldCWD: oldCWD,
                                forceUseOldCWD: true,
                                command: cmd,
                                isUTF8: nil,
                                substitutions: nil,
                                windowController: nil,
                                ready: nil) { _, _ in }
                            factory.attachOrLaunch(with: request)
                        }
                        seal.fulfill(newSession)
                        return
                    }
                    let command = config.command.isEmpty
                        ? nil
                        : ITAddressBookMgr.commandByWrapping(inLoginShell: config.command)
                    let launchRequest = iTermSessionAttachOrLaunchRequest(
                        session: newSession,
                        canPrompt: false,
                        objectType: .paneObject,
                        hasServerConnection: false,
                        serverConnection: iTermGeneralServerConnection(),
                        urlString: urlString,
                        allowURLSubs: false,
                        environment: ["ITERM_WORKGROUP_ID": workgroupInstanceID],
                        customShell: nil,
                        oldCWD: oldCWD,
                        forceUseOldCWD: true,
                        command: command,
                        isUTF8: nil,
                        substitutions: nil,
                        windowController: nil,
                        ready: nil) { session, ok in
                            if ok, let session {
                                session.bury()
                                seal.fulfill(session)
                            } else {
                                seal.reject(iTermError("Failed to create session"))
                            }
                        }
                    factory.attachOrLaunch(with: launchRequest)
                }
            }
        }
    }
    
    @objc
    func didAssignDelegate() {
        let observers = swiftState.delegateObservers
        swiftState.delegateObservers = []
        for closure in observers {
            if let delegate {
                closure(delegate)
            } else {
                swiftState.delegateObservers.append(closure)
            }
        }
    }
    
    private func withDelegate(_ closure: @escaping (PTYSessionDelegate) -> ()) {
        if let delegate {
            closure(delegate)
            return
        }
        swiftState.delegateObservers.append(closure)
    }
    
    @objc(sessionBelongsToPeers:)
    func belongs(toPeers peers: PTYSessionPeerPort) -> Bool {
        return peers.contains(session: self)
    }

    // Public accessor — delegates to the peer-group's leader if this session
    // is in a peer group, otherwise reads/writes its own swiftState storage.
    @objc var clippings: [PTYSessionClipping] {
        get {
            if let peerPort {
                return peerPort.clippings
            }
            return swiftState.clippings
        }
        set {
            if let peerPort {
                peerPort.clippings = newValue
            } else {
                swiftState.clippings = newValue
            }
        }
    }

    // Runtime toggle backing the code-review "auto-send clippings when idle"
    // toolbar item. Stored directly on the session (not peer-delegated) since
    // it controls this one review session's behavior, not shared group state.
    @objc var autoSendClippingsWhenIdle: Bool {
        get { swiftState.autoSendClippingsWhenIdle }
        set { swiftState.autoSendClippingsWhenIdle = newValue }
    }

    // Runtime toggle backing the main session's "auto-request review when
    // idle" toolbar item. Stored on the main session; controls its own
    // idle-driven behavior, not shared group state.
    @objc var autoRequestReviewWhenIdle: Bool {
        get { swiftState.autoRequestReviewWhenIdle }
        set { swiftState.autoRequestReviewWhenIdle = newValue }
    }

    // Bypasses peer-port delegation. Used by PTYSessionPeerPort to talk to its
    // leader's storage without recursing, and by save/restore so the leader's
    // data is persisted at the session level.
    @objc var localClippings: [PTYSessionClipping] {
        get { swiftState.clippings }
        set { swiftState.clippings = newValue }
    }

    @objc var localClippingsAsDictionaries: [[String: String]] {
        return swiftState.clippings.map { $0.dictionaryValue }
    }

    @objc(setLocalClippingsFromDictionaries:)
    func setLocalClippingsFromDictionaries(_ dictionaries: [[String: String]]) {
        swiftState.clippings = dictionaries.compactMap {
            PTYSessionClipping(dictionary: $0)
        }
    }

    // Public accessor for the archive — delegates to the peer-group leader
    // when in a peer group so all peers see the same history.
    @objc var clippingsArchive: [[PTYSessionClipping]] {
        get {
            if let peerPort {
                return peerPort.clippingsArchive
            }
            return swiftState.clippingsArchive
        }
        set {
            if let peerPort {
                peerPort.clippingsArchive = newValue
            } else {
                swiftState.clippingsArchive = newValue
            }
        }
    }

    // Bypasses peer-port delegation for save/restore and PTYSessionPeerPort.
    @objc var localClippingsArchive: [[PTYSessionClipping]] {
        get { swiftState.clippingsArchive }
        set { swiftState.clippingsArchive = newValue }
    }

    @objc var localClippingsArchiveAsDictionaries: [[[String: String]]] {
        return swiftState.clippingsArchive.map { snapshot in
            snapshot.map { $0.dictionaryValue }
        }
    }

    @objc(setLocalClippingsArchiveFromDictionaries:)
    func setLocalClippingsArchiveFromDictionaries(_ dictionaries: [[[String: String]]]) {
        swiftState.clippingsArchive = dictionaries.map { snapshot in
            snapshot.compactMap { PTYSessionClipping(dictionary: $0) }
        }
    }

    // Currently displayed entry in the timeline. -1 = live; 0..<archive.count
    // = that archive snapshot.
    @objc var clippingsViewIndex: Int {
        get {
            if let peerPort {
                return peerPort.clippingsViewIndex
            }
            return swiftState.clippingsViewIndex
        }
        set {
            let clamped = Self.clampClippingsViewIndex(newValue, archiveCount: clippingsArchive.count)
            if let peerPort {
                peerPort.clippingsViewIndex = clamped
            } else {
                swiftState.clippingsViewIndex = clamped
            }
            clippingsDidChange()
        }
    }

    @objc var localClippingsViewIndex: Int {
        get { swiftState.clippingsViewIndex }
        set { swiftState.clippingsViewIndex = newValue }
    }

    private static func clampClippingsViewIndex(_ index: Int, archiveCount: Int) -> Int {
        if index < 0 || index >= archiveCount {
            return -1
        }
        return index
    }

    // The list shown in the panel: live or one of the archive entries.
    @objc var viewedClippings: [PTYSessionClipping] {
        let index = clippingsViewIndex
        let archive = clippingsArchive
        if index >= 0 && index < archive.count {
            return archive[index]
        }
        return clippings
    }

    // True when the view is on the live list (index -1). Mutating actions in
    // the panel (add/delete/reorder/drop) are gated by this.
    @objc var clippingsViewIsLive: Bool {
        let index = clippingsViewIndex
        return index < 0 || index >= clippingsArchive.count
    }

    @objc(addClippingWithType:title:detail:)
    func addClipping(type: String, title: String, detail: String) {
        var current = clippings
        current.append(PTYSessionClipping(type: type, title: title, detail: detail))
        clippings = current
        // Adding a clipping is always an action against the live list, so
        // hop the view back to live so the new item is visible. The
        // clippingsViewIndex setter posts the change notification, so the
        // already-visible branch needs no further work; the auto-show branch
        // re-posts once via the visibility setter, which is fine.
        clippingsViewIndex = -1
        if !clippingsVisible {
            clippingsVisible = true
        }
    }

    // Hard cap on archived snapshots to keep the arrangement size bounded.
    // The auto-archive integration (one snapshot per Claude Code review pass)
    // is the primary driver: a long-lived session that runs dozens of passes
    // would otherwise grow the arrangement unbounded.
    private static let maxClippingsArchiveEntries = 50

    // Snapshot the live list into the archive (if it's non-empty) and clear
    // the live list. Leaves the view on "live" so the user immediately sees
    // a fresh, empty list. Routing for code-review workgroup peers is handled
    // by callers (the built-in function and toolbar action) so this method
    // can run unconditionally on the resolved target session.
    @objc(archiveClippings)
    @discardableResult
    func archiveClippings() -> Bool {
        let live = clippings
        guard !live.isEmpty else {
            return false
        }
        var archive = clippingsArchive
        archive.append(live)
        if archive.count > Self.maxClippingsArchiveEntries {
            archive.removeFirst(archive.count - Self.maxClippingsArchiveEntries)
        }
        clippingsArchive = archive
        clippings = []
        // clippingsViewIndex setter broadcasts; no explicit follow-up needed.
        clippingsViewIndex = -1
        return true
    }

    // Public accessor — delegates to the peer-group's leader, or own storage if solo.
    @objc var clippingsVisible: Bool {
        get {
            if let peerPort {
                return peerPort.clippingsVisibilityFlag
            }
            return swiftState.clippingsVisibilityFlag
        }
        set {
            if let peerPort {
                peerPort.clippingsVisibilityFlag = newValue
            } else {
                swiftState.clippingsVisibilityFlag = newValue
            }
            clippingsDidChange()
        }
    }

    // Bypasses peer-port delegation — used by PTYSessionPeerPort to talk to
    // the leader's storage without recursing.
    @objc var localClippingsVisibilityFlag: Bool {
        get { swiftState.clippingsVisibilityFlag }
        set { swiftState.clippingsVisibilityFlag = newValue }
    }

    // Effective visibility is just the user-controlled flag — no auto-hide
    // when the list is empty.
    @objc var clippingsPanelEffectivelyVisible: Bool {
        return clippingsVisible
    }

    // Call after any mutation to the clippings list — broadcasts to gutter
    // panels so they reload and re-evaluate their visibility.
    @objc func clippingsDidChange() {
        NotificationCenter.default.post(name: PTYSession.clippingsDidChangeNotification,
                                        object: nil)
        // The gutter controller only instantiates the clippings panel when the
        // registry's width is > 0. On the 0→1 transition (e.g., first clipping
        // added via the Python API) no panel exists yet to consume the
        // notification above, so kick the parent window's layout cascade —
        // which ends up calling iTermRightGutterController.layoutPanels and
        // creates the panel. Same goes for the 1→0 transition tearing it down
        // when no panel is around to detect its own visibility flip.
        if view?.actualRightExtra != desiredRightExtra() {
            delegate?.realParentWindow()?.rightExtraDidChange()
        }
    }

    @objc static let clippingsDidChangeNotification =
        Notification.Name("iTermClippingsDidChange")

    // The chat ID currently bound to this session's inline-chat right-gutter
    // panel, or nil if none. Setting this value re-runs the layout cascade
    // because the right-extra budget depends on whether an inline chat is
    // installed.
    @objc var inlineChatID: String? {
        get { swiftState.inlineChatID }
        set {
            swiftState.inlineChatID = newValue
            inlineChatDidChange()
        }
    }

    // Whether the inline chat panel should be shown. Honored only when an
    // inlineChatID is set; with no chat to show, visibility has no effect.
    @objc var inlineChatVisible: Bool {
        get { swiftState.inlineChatVisibilityFlag }
        set {
            swiftState.inlineChatVisibilityFlag = newValue
            inlineChatDidChange()
        }
    }

    @objc func inlineChatDidChange() {
        NotificationCenter.default.post(name: PTYSession.inlineChatDidChangeNotification,
                                        object: self)
        if view?.actualRightExtra != desiredRightExtra() {
            delegate?.realParentWindow()?.rightExtraDidChange()
        }
    }

    @objc static let inlineChatDidChangeNotification =
        Notification.Name("iTermInlineChatDidChange")

    // Action for the View > Show Inline Chat menu item. If a chat is bound
    // already, just toggle its panel visibility. The binding (inlineChatID)
    // lives in memory and is saved/restored with the window arrangement, so
    // re-toggling reuses the same chat across both panel hides and restarts.
    //
    // With no chat bound, fall back to the most recent chat the user
    // EXPLICITLY linked to this session (via the offerLink "Link" button or
    // from the chat window): that's all mostRecentChat(forGuid:) can match.
    // Inline chats are created unlinked (see createInlineChat), so this
    // fallback intentionally does NOT rediscover a prior inline chat whose
    // inlineChatID was lost; the only thing that clears inlineChatID is
    // deleting the chat, which removes it entirely, so there's no reusable
    // unlinked chat left behind to rediscover. When nothing matches, create a
    // fresh inline chat. Intentionally does NOT route through
    // ChatWindowController so the chat window stays unaffected and is not
    // opened as a side effect.
    @objc(toggleInlineChat)
    func toggleInlineChat() {
        if inlineChatID != nil {
            inlineChatVisible = !inlineChatVisible
            return
        }
        guard iTermAITermGatekeeper.check() else {
            return
        }
        guard let listModel = ChatListModel.instance else {
            return
        }
        let sessionGuid = self.guid
        if let existing = listModel.mostRecentChat(forGuid: sessionGuid) {
            inlineChatID = existing.id
            inlineChatVisible = true
            return
        }
        if createInlineChat() != nil {
            inlineChatVisible = true
        }
    }

    // Re-bind an inline chat during arrangement restoration. Setting
    // inlineChatID drives the right-extra layout cascade that instantiates the
    // gutter panel and reserves the panel's width, the same as a live toggle.
    //
    // Deliberately NOT gated on iTermAITermGatekeeper, unlike the create/show
    // entry points. Restoring a panel that shows past chat history is benign:
    // it makes no AI calls until the user sends a message, which goes through
    // the gate. Gating here would pay the plugin-load cost on the launch
    // restore path and would drop the saved binding whenever AI is temporarily
    // disabled.
    //
    // Validate against the chat list only if the chat DB is ALREADY open
    // (instanceIfExists, which does not construct it). Reading
    // ChatListModel.instance would force ChatDatabase to open chatdb.sqlite
    // and run migrations synchronously here on the restore path. When the DB
    // is open and the chat is gone (deleted since the arrangement was saved),
    // skip binding so the panel doesn't reopen onto a missing chat; when it
    // isn't open we can't tell, so bind optimistically. The width provider
    // re-validates that the chat still exists once the DB is open and drops
    // the binding (yielding no panel) if it has since been deleted.
    //
    // Edge case: if the chat DB cannot be opened at all this launch (e.g. a
    // second iTerm2 instance holds the sqlite lock), the width provider yields
    // 0 and the window restores at full terminal width with no panel. We still
    // set the binding so it survives to a healthy launch. Reserving width for
    // a panel that can't be constructed would crash the force-unwrapping panel
    // factory, so we accept the wider window in that degraded state.
    @objc(restoreInlineChatID:visible:)
    func restoreInlineChat(id: String, visible: Bool) {
        if ChatDatabase.instanceIfExists != nil,
           let listModel = ChatListModel.instance,
           listModel.index(of: id) == nil {
            return
        }
        inlineChatID = id
        inlineChatVisible = visible
    }

    // Create a brand-new chat for this session's inline panel and bind it via
    // inlineChatID. The chat is created UNLINKED (no terminal/browser GUID) and
    // carries a single .offerLink client-local message, mirroring the chat
    // window's new-chat flow: the user picks "Link" (bind to this session) or
    // "Enable Orchestration" from buttons in the conversation rather than the
    // panel deciding for them. Returns the new chat ID, or nil on failure.
    //
    // The offer is published here (at creation) rather than in
    // ChatViewController.attach(to:) because attach runs on every (re)attach;
    // offering there would stack duplicate offer bubbles across detach/reattach
    // cycles. Published client-local messages persist and replay when the panel
    // loads the chat.
    @discardableResult
    func createInlineChat() -> String? {
        guard let client = ChatClient.instance else {
            return nil
        }
        do {
            let title = "Chat about \(self.name)"
            let isBrowser = self.isBrowserSession()
            let chatID = try client.create(
                chatWithTitle: title,
                terminalSessionGuid: nil,
                browserSessionGuid: nil,
                initialMessages: [],
                permissions: "")
            try? client.publishClientLocalMessage(
                chatID: chatID,
                action: .offerLink(terminal: !isBrowser, guid: self.guid, name: self.name))
            inlineChatID = chatID
            return chatID
        } catch {
            RLog("\(error)")
            return nil
        }
    }
}

// MARK: - AI-generated tab titles

extension PTYSession {
    // Ticked from -updateDisplayBecause:, i.e. on the display-update cadence,
    // which can fire many times a second. That is deliberate: there is no
    // separate timer to keep in sync with output, and a tick that does nothing
    // costs a handful of dictionary lookups in AITabTitleGenerator.shouldAttempt.
    // Reading the screen - the part that walks the grid - and gathering context
    // happen only once that returns true.
    // Whether this session's current profile will actually display an AI title (the
    // AI title component is selected, or a custom title function that might
    // interpolate session.aiTitle). A missing profile is treated as "does not
    // consume" rather than falling through. Re-evaluated at both attempt time and
    // write time so a mid-generation profile switch is honored.
    private func sessionConsumesAITitle() -> Bool {
        guard let profile = self.profile else {
            return false
        }
        let components = iTermProfilePreferences.unsignedInteger(forKey: KEY_TITLE_COMPONENTS,
                                                                inProfile: profile)
        // Whether an active TemporarySessionName (manual tab rename / Set-Title trigger) is
        // currently masking the AI title. Mirrors the precedence titleForSessionName
        // enforces: the TemporarySessionName bit set AND a non-empty EFFECTIVE session name.
        // The effective name for a TAB (isWindowTitle == NO) is the tmux pane title for a
        // tmux session, else the autoName - matching the renderer's effectiveSessionName
        // (its `if (tmuxPaneVariable)` uses the TRIMMED pane title, so an empty/whitespace
        // pane title falls through to the non-tmux `effectiveSessionName = sessionName` =
        // autoName branch). Trim both here too, exactly as the renderer's trim() does, so
        // a whitespace-only value can't make the gate skip a title the tab would show.
        let trimmed = { (name: String) in name.trimmingCharacters(in: .whitespaces) }
        let tmuxPaneTitle = trimmed((genericScope.value(forVariableName: iTermVariableKeySessionTmuxPaneTitle) as? String) ?? "")
        let autoName = trimmed((genericScope.value(forVariableName: iTermVariableKeySessionAutoName) as? String) ?? "")
        let effectiveName = tmuxPaneTitle.isEmpty ? autoName : tmuxPaneTitle
        let isMaskedByTemporaryName =
            (components & iTermTitleComponents.temporarySessionName.rawValue) != 0 && !effectiveName.isEmpty
        // KEY_TITLE_FUNC is stored as an iTermTuple plist (display name, unique id),
        // NOT a string: reading it via stringForKey force-bridges an NSArray to
        // String and traps. Decode the tuple and use its identifier (secondObject),
        // mirroring the reader in PTYSession.m.
        let titleFuncTuple = iTermTuple<NSString, NSString>.fromPlistValue(
            iTermProfilePreferences.object(forKey: KEY_TITLE_FUNC, inProfile: profile))
        let hasCustomTitleFunction = !((titleFuncTuple.secondObject as String?) ?? "").isEmpty
        return AITabTitleGenerator.sessionConsumesAITitle(titleComponents: components,
                                                          hasCustomTitleFunction: hasCustomTitleFunction,
                                                          isMaskedByTemporaryName: isMaskedByTemporaryName)
    }

    @objc
    @MainActor
    func maybeUpdateAITitle() {
        // Main-thread only: this drives AITabTitleGenerator (whose methods assert the
        // main queue) and reads genericScope. Called from -updateDisplayBecause: on
        // the main thread today; asserting here makes that requirement explicit and
        // traps clearly at the boundary if a future path drives the cadence off-main
        // rather than racing genericScope.
        dispatchPrecondition(condition: .onQueue(.main))
        // Browser sessions have a real-but-empty VT100Screen and report idle
        // continuously; the whole AI-title path (screen extraction, availability
        // probe) assumes a terminal. isWorthTitling would reject the empty grid so no
        // model call happens, but the per-tick work is pure waste - skip it.
        guard !isBrowserSession() else {
            return
        }
        // The global feature gate first, before any per-session profile reads.
        // This is called from -updateDisplayBecause: for every session on the
        // display cadence; for the off-by-default common case the disabled path
        // must not pay for a profile lookup and two profile-pref reads per session
        // per tick.
        guard iTermAdvancedSettingsModel.aiGeneratedTabTitles() else {
            // The feature is off. If we previously set an AI title it would otherwise
            // stay frozen on the tab for the life of the session: the profile keeps
            // the AI component bit (so it stays reachable to uncheck) and
            // titleForSessionName still consumes aiTitle, and nothing else clears it.
            // Clear it (and the generator's state) once, only when one is actually
            // showing. Ask the generator's own applied-title record (a single dictionary
            // lookup) instead of a variable-scope traversal, so the common disabled-
            // default tick - every session, every display tick, for a user who never
            // enabled the feature - is as cheap as possible. The generator's
            // lastAppliedTitle is a faithful proxy: aiTitle is only ever written by the
            // generation completion (which sets it) or forgetAITitleState (which clears
            // it), and is no longer restored from arrangements.
            if AITabTitleGenerator.instance.hasNonEmptyAppliedTitle(forSessionID: guid) {
                forgetAITitleState()
            }
            return
        }
        // A terminated session must not be titled: -terminate forgets this
        // session's generator state and then schedules an async display tick,
        // which lands here after exited is set. Without this guard that tick
        // re-populates the generator via shouldAttempt, undoing the forget and
        // leaking one entry per closed session for the life of the process (and
        // a late generation could write a stale title onto a revived session).
        guard !exited else {
            return
        }
        // Only name a screen that has stopped moving. Titling mid-output would
        // name a half-drawn frame; isIdle (one second since the last byte) is
        // the signal the cadence controller already uses to decide a session
        // has settled.
        guard isIdle else {
            return
        }
        // The cheap throttle BEFORE the per-session profile reads. shouldAttempt
        // is a dictionary lookup plus the 5s throttle and does not need the
        // profile; on the vast majority of idle ticks it returns false here, so
        // the profile lookup and two profile-pref reads below run only ~once per
        // interval instead of every tick.
        let sessionID = guid
        guard AITabTitleGenerator.instance.shouldAttempt(forSessionID: sessionID) else {
            return
        }
        // Only run sessions that will actually display the AI title. A session
        // whose profile did not select the AI component (and has no custom title
        // function that might interpolate session.aiTitle) would feed its screen
        // through the model for a title it never shows.
        guard sessionConsumesAITitle() else {
            return
        }
        // The visible grid only, never scrollback: name what the user is looking
        // at now. For a full-screen app (tmux, an editor, an agent CLI) the
        // scrollback holds discarded frames, not history.
        let scrollback = screen.numberOfScrollbackLines()
        // extractScreenText is the agent screen-reading path: it weaves in ⟨cursor⟩,
        // ⟨dim⟩…⟨/dim⟩, and ⟨image⟩ markup. Strip it for titling so the model isn't
        // told the screen literally contains those tokens, the digest doesn't churn
        // on cursor movement, and a faint shell autosuggestion (a command NOT run)
        // doesn't name the tab.
        let contents = WorkgroupIntrospection.plainTitleText(
            WorkgroupIntrospection.extractScreenText(
                ofScreen: screen,
                fromLine: scrollback,
                toLine: scrollback + screen.height()))
        // Whether we're in a full-screen app, and (only then) the background-color
        // fingerprint of the visible grid. The generator only consults the
        // histogram on the alternate-screen path (a TUI re-titles when the color
        // layout changes, not when content scrolls); a plain shell decides on the
        // content digest alone. Computing the histogram walks the whole grid, so
        // skip that work for shells and pass an empty one.
        let isAlternate = screen.terminalSoftAlternateScreenMode
        let backgroundHistogram = isAlternate
            ? iTermTabTitleFrameFingerprint.backgroundHistogram(for: screen)
            : [:]
        // The program's own OSC titles (OSC 0/1 icon name, OSC 0/2 window name)
        // are a strong "task changed" signal that the background fingerprint
        // misses - e.g. switching files in vim keeps the same status-bar color
        // but changes the OSC title. Cleaned of the volatile leading glyphs some
        // programs animate (Claude Code cycles a spinner in its title) so the
        // animation itself doesn't count as a change.
        let oscTitle = Self.cleanedOSCTitle(genericScope.value(forVariableName: iTermVariableKeySessionIconName) as? String)
            + "\u{1}"
            + Self.cleanedOSCTitle(genericScope.value(forVariableName: iTermVariableKeySessionWindowName) as? String)
        AITabTitleGenerator.instance.requestTitle(
            forSessionID: sessionID,
            screen: contents,
            backgroundHistogram: backgroundHistogram,
            isAlternate: isAlternate,
            oscTitle: oscTitle,
            // Built lazily: the mark walk + variable reads happen only if a
            // generation actually runs, not on the common unchanged-screen tick.
            // The provider is non-escaping and runs synchronously inside
            // requestTitle, so a strong self capture cannot outlive this call.
            context: { self.aiTitleContext() }) { [weak self] title in
                guard let self, let title else {
                    return
                }
                // Re-check exited at write time. A generation can be in flight
                // when the session dies via a path that doesn't call -terminate
                // (broken pipe, tmux disconnect set exited=YES without forgetting
                // the generator state), so the !exited guard at the top of
                // maybeUpdateAITitle doesn't cover this late write.
                //
                // Forget, don't just return, for the SAME reason as the sibling guards
                // below: finish() has already committed lastAppliedTitle and stamped this
                // screen's fingerprint. The exited-without-terminate path runs no
                // forget, and a same-guid revive early-returns in -setGuid: (guid
                // unchanged), so without reconciling here an unchanged/similar screen whose
                // digest matches the stamp returns .skip forever, leaving the revived tab
                // stuck on the plain name. (If the object is instead released, the dealloc
                // forget already ran, making this a harmless no-op.)
                guard !self.exited else {
                    self.forgetAITitleState()
                    return
                }
                // Re-check the feature flag at write time too: the user can disable
                // aiGeneratedTabTitles while this ~0.3s generation is in flight, and
                // the disable-path clear in maybeUpdateAITitle only runs on the next
                // display tick - which may not come for a quiescent session. Without
                // this the late completion would write a title the feature is no
                // longer meant to produce, and it would linger.
                //
                // Forget rather than just return: finish() has already stamped this
                // screen's fingerprint and lastAppliedTitle in the generator. If we
                // bailed without resetting, re-enabling the feature on the unchanged
                // (idle) screen would hit regenerationDecision's .skip path and never
                // regenerate, leaving the tab stuck on the plain session name - the
                // same stuck state the profile-switch guard below forgets to avoid.
                // forgetAITitleState clears aiTitle AND resets those fingerprints so a
                // re-enable re-generates.
                guard iTermAdvancedSettingsModel.aiGeneratedTabTitles() else {
                    self.forgetAITitleState()
                    return
                }
                // Re-check the profile still consumes the AI title: the user can
                // switch to a non-AI profile while this generation is in flight. Just
                // clearing aiTitle is not enough - finish() already stamped this
                // screen's fingerprint in the generator, so switching BACK to the AI
                // profile on the unchanged screen would return .skip and never
                // regenerate, leaving the tab stuck on the plain name. forgetAITitleState
                // clears aiTitle AND resets those fingerprints so a switch-back
                // re-generates.
                guard self.sessionConsumesAITitle() else {
                    self.forgetAITitleState()
                    return
                }
                // genericScope, not variablesScope: the latter's generic type
                // does not bridge to Swift (see PTYSession.h).
                self.genericScope.setValue(title,
                                           forVariableNamed: iTermVariableKeySessionAITitle)
            }
    }

    // Strips leading non-alphanumeric junk (spinner/activity glyphs some programs
    // animate in their title) and collapses whitespace, so a change signal
    // reflects a real title change, not an animation frame.
    static func cleanedOSCTitle(_ s: String?) -> String {
        guard var t = s?[...] else {
            return ""
        }
        while let first = t.first, !first.isLetter, !first.isNumber {
            t = t.dropFirst()
        }
        // Normalize each whitespace token that is a whole volatile numeric shape -
        // a clock (12:34:56), an ISO date (2026-08-30), a percentage (41%), or an
        // elapsed-time counter (12s, 5m30s) - by replacing its digit runs with
        // '#'. This stops an animated clock/timer/percentage from reading as a
        // task change every tick, WITHOUT erasing digits that identify real work
        // (file1 -> file2, Issue 1234, 1m.log). Requiring the whole token to match
        // a volatile shape is what distinguishes "12s" (a timer) from "1m.log" (a
        // file).
        //
        // Drop tokens with NO letter or number (a braille/ASCII spinner or bracketed
        // glyph animated anywhere in the title - leading, middle, or trailing), so
        // they don't churn the change signal every frame. A token with any alnum
        // (e.g. "41%") is kept so the volatile-numeric normalizer above still handles
        // it - the leading char-strip already covers a spinner glued to the first
        // word.
        let tokens = t.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        return tokens
            .filter { token in token.contains(where: { $0.isLetter || $0.isNumber }) }
            .map { Self.normalizeVolatileToken($0) }
            .joined(separator: " ")
    }

    // Replaces digit runs with '#' if the token (ignoring surrounding brackets) is
    // a volatile numeric shape; otherwise returns it unchanged.
    private static func normalizeVolatileToken(_ token: String) -> String {
        let openers = Set("([{")
        let closers = Set(")]}")
        var start = token.startIndex
        var end = token.endIndex
        while start < end, openers.contains(token[start]) {
            start = token.index(after: start)
        }
        while start < end, closers.contains(token[token.index(before: end)]) {
            end = token.index(before: end)
        }
        let core = String(token[start..<end])
        guard Self.isVolatileNumericCore(core) else {
            return token
        }
        var body = ""
        var inDigits = false
        for ch in core {
            if ch.isNumber {
                if !inDigits {
                    body.append("#")
                    inDigits = true
                }
            } else {
                body.append(ch)
                inDigits = false
            }
        }
        return String(token[token.startIndex..<start]) + body + String(token[end..<token.endIndex])
    }

    // YYYY-MM-DD: three all-digit groups of lengths 4, 2, 2.
    private static func isISODateParts(_ s: Substring) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isNumber } }
    }

    // A classic wall clock H:MM[:SS][.fff], optionally an ISO datetime (date T
    // time) and/or with a trailing Z or +/-HH:MM timezone offset. The strict shape
    // is what keeps ratios/scores/host:port from being mistaken for clocks.
    private static func isVolatileClock(_ s: Substring) -> Bool {
        var time = s
        var isoDatetime = false
        if let t = time.firstIndex(of: "T") {
            guard Self.isISODateParts(time[..<t]) else {
                return false
            }
            time = time[time.index(after: t)...]
            isoDatetime = true
        }
        if time.hasSuffix("Z") {
            time = time.dropLast()
        } else if let sign = time.lastIndex(where: { $0 == "+" || $0 == "-" }),
                  sign != time.startIndex {
            let base = time[..<sign]
            let offset = time[time.index(after: sign)...]
            // Only strip a trailing +/-HH:MM when it can actually be a timezone offset
            // and NOT the separator of a time RANGE like 09:00-10:30. A real offset
            // rides on an ISO datetime (a T preceded it) or on a seconds-precision time
            // (12:34:56+05:00); a schedule range is bare HH:MM-HH:MM. Without this guard
            // lastIndex finds the range's own '-', its trailing HH:MM passes the offset
            // shape test, and two different ranges (09:00-10:30, 11:00-12:00) collapse to
            // the same token, hiding a real OSC change. Range-validating the offset alone
            // is not enough: 10:30 is itself a plausible-looking offset. Requiring the
            // datetime/seconds context is what separates an offset from a range, and the
            // range check on the offset additionally rejects 12:34-45:67.
            let baseHasSeconds = base.split(separator: ":", omittingEmptySubsequences: false).count == 3
            if (isoDatetime || baseHasSeconds) && Self.isTimezoneOffset(offset) {
                time = base
            }
        }
        return Self.isClockTime(time)
    }

    // A +/-HH:MM timezone offset (the sign is already consumed): two 2-digit groups
    // with hour 00-14 (max real UTC offset is +14) and minute 00-59.
    private static func isTimezoneOffset(_ s: Substring) -> Bool {
        let groups = s.split(separator: ":", omittingEmptySubsequences: false)
        guard groups.count == 2, groups[0].count == 2, groups[1].count == 2,
              let hour = Int(groups[0]), let minute = Int(groups[1]),
              hour <= 14, minute <= 59 else {
            return false
        }
        return true
    }

    // H:MM or H:MM:SS with optional fractional seconds. First group 1-2 digits, the
    // minute/second groups exactly 2. Also validate the RANGES (hour 0-23, minute/
    // second 0-59): the digit-length check alone still matches a genuine 2+2 token
    // like a host:port pair (80:80, 90:90) or a two-part id, which would then collapse
    // to #:# and hide a real OSC title change. Requiring valid clock ranges rejects
    // those (80 > 23) while keeping real clocks (12:34). It still can't distinguish a
    // port pair whose values happen to be valid clock numbers (22:22), but that is far
    // rarer.
    private static func isClockTime(_ s: Substring) -> Bool {
        let groups = s.split(separator: ":", omittingEmptySubsequences: false)
        guard groups.count == 2 || groups.count == 3 else {
            return false
        }
        for (i, group) in groups.enumerated() {
            var digits = group
            // Only the final group may carry a fractional part (.fff seconds).
            if i == groups.count - 1, let dot = digits.firstIndex(of: ".") {
                let frac = digits[digits.index(after: dot)...]
                guard !frac.isEmpty, frac.allSatisfy({ $0.isNumber }) else {
                    return false
                }
                digits = digits[..<dot]
            }
            guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }), let value = Int(digits) else {
                return false
            }
            if i == 0 {
                // Hour: 1-2 digits, 0-23.
                guard digits.count <= 2, value <= 23 else {
                    return false
                }
            } else {
                // Minute / second: exactly 2 digits, 0-59.
                guard digits.count == 2, value <= 59 else {
                    return false
                }
            }
        }
        return true
    }

    private static func isVolatileNumericCore(_ core: String) -> Bool {
        guard core.contains(where: { $0.isNumber }) else {
            return false
        }
        // Clock, possibly as an ISO datetime (date T time) with a trailing timezone
        // (Z or +/-HH:MM) or a 12-hour am/pm suffix - so 12:34:56,
        // 2026-08-30T12:34:56Z, 12:34:56+05:00, and 3:45pm normalize. Tightened to
        // the classic H:MM[:SS] shape (first group 1-2 digits, minute/second groups
        // exactly 2) so plain N:N ratios (16:9), scores (2:1), and host:port
        // (8080:80) are NOT swallowed and can still register a real OSC change.
        var clockCore = Substring(core)
        for suffix in ["am", "pm"] where clockCore.count > suffix.count
            && clockCore.suffix(suffix.count).lowercased() == suffix {
            clockCore = clockCore.dropLast(suffix.count)
            break
        }
        if Self.isVolatileClock(clockCore) {
            return true
        }
        // ISO date YYYY-MM-DD: three all-digit groups of lengths 4, 2, 2. Merely
        // "two hyphens" would also match version strings (1-2-3), IP fragments
        // (10-0-0), and step counters, masking real title changes.
        if Self.isISODateParts(Substring(core)) {
            return true
        }
        // Percentage: ends with '%', the rest digits or '.'.
        if core.hasSuffix("%") && core.dropLast().allSatisfy({ $0.isNumber || $0 == "." }) {
            return true
        }
        // Metric-suffixed counter: digits (with optional '.') then a thousands/
        // millions suffix, e.g. 1.2k, 3.4M, 100k. (Claude Code animates a "1.2k
        // tokens" readout.) Deliberately NOT B/G/T: those far more often denote a
        // size that identifies the work (7B model, 40G) than a counter. And an
        // all-digit UPPERCASE <n>K/<n>M is a resolution/size identifier (4K, 8K,
        // 1M rows), not a counter, so require either a lowercase 'k' or a decimal
        // point - the shapes animated counters actually take - to collapse it;
        // otherwise a 4K -> 8K switch would be masked as unchanged.
        if let last = core.last, "kKM".contains(last),
           last == "k" || core.contains("."),
           core.dropLast().contains(where: { $0.isNumber }),
           core.dropLast().allSatisfy({ $0.isNumber || $0 == "." }) {
            return true
        }
        // N/M progress: digits '/' digits, e.g. 42/100.
        let slashParts = core.split(separator: "/", omittingEmptySubsequences: false)
        if slashParts.count == 2,
           slashParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }) {
            return true
        }
        // Elapsed time: one-or-more (digits + unit), unit in {h, m, s, ms}.
        return Self.isElapsedTime(core)
    }

    private static func isElapsedTime(_ core: String) -> Bool {
        let chars = Array(core)
        var i = 0
        var sawSegment = false
        while i < chars.count {
            guard chars[i].isNumber else {
                return false
            }
            while i < chars.count && chars[i].isNumber {
                i += 1
            }
            // Optional fractional part (1.5s), matching the percentage/metric
            // branches which already allow a decimal point.
            if i + 1 < chars.count && chars[i] == "." && chars[i + 1].isNumber {
                i += 1
                while i < chars.count && chars[i].isNumber {
                    i += 1
                }
            }
            if i + 1 < chars.count && chars[i] == "m" && chars[i + 1] == "s" {
                i += 2   // milliseconds
            } else if i < chars.count && (chars[i] == "s" || chars[i] == "m" || chars[i] == "h") {
                i += 1   // seconds / minutes / hours
            } else {
                return false   // digits not followed by a unit
            }
            sawSegment = true
        }
        return sawSegment
    }

    // Observes iTermAdvancedSettingsDidChange (posted whenever any advanced setting's
    // backing default changes). When the user turns aiGeneratedTabTitles OFF, clear an
    // already-applied AI title right away rather than waiting for maybeUpdateAITitle on
    // the display cadence: a fully idle/occluded session may not get a tick soon, so
    // the stale title would stay pinned on the tab, masking the real session name.
    // Turning the feature ON needs no action here - the next idle tick regenerates. The
    // notification fires for every advanced-setting change, so the common case is the
    // cheap early return below.
    @objc
    nonisolated func aiGeneratedTabTitlesSettingDidChange() {
        // iTermAdvancedSettingsDidChange is posted SYNCHRONOUSLY from a user-defaults KVO
        // block on whatever thread mutated the default - not guaranteed main (a settable
        // bool changed off-main, or an external `defaults write` from another process). So
        // hop to main before touching genericScope / the main-actor generator, rather than
        // asserting main and crashing in release (the sibling observers registered in the
        // same block do not assert either).
        Task { @MainActor [weak self] in
            self?.clearAppliedAITitleIfFeatureDisabled()
        }
    }

    // Internal (not private) so the lifecycle tests can drive the clearing logic
    // synchronously, without the async main-hop in the @objc entry point above.
    @MainActor
    func clearAppliedAITitleIfFeatureDisabled() {
        guard !iTermAdvancedSettingsModel.aiGeneratedTabTitles() else {
            return
        }
        if let current = genericScope.value(forVariableName: iTermVariableKeySessionAITitle) as? String,
           !current.isEmpty {
            forgetAITitleState()
        }
    }

    // Drops the generator's per-session state so a long-lived iTerm2 process
    // does not retain an entry for every session ever opened.
    @objc
    @MainActor
    func forgetAITitleState() {
        // Main-thread only: forget() asserts the main queue and we mutate genericScope.
        // Called from -terminate and -setGuid: on the main thread; -dealloc uses the
        // guid-keyed static variant dispatched to main instead.
        dispatchPrecondition(condition: .onQueue(.main))
        // Read the displayed title before dropping generator state (forget() doesn't
        // touch the variable, but read first for clarity).
        let current = genericScope.value(forVariableName: iTermVariableKeySessionAITitle) as? String
        AITabTitleGenerator.instance.forget(sessionID: guid)
        // Also clear the displayed AI title, but ONLY if one is actually showing.
        // forget() wipes the generator's lastAppliedTitle, which disables the normal
        // clear-on-idle path, so on a restart / guid change a stale title from the shell
        // that just died would otherwise linger on the revived session's tab. The
        // variable lives on this session object, which survives a restart, so it must be
        // reset here. But aiTitle is now a declared dependency of session_title, so
        // writing "" onto an already-empty variable invalidates the title and forces a
        // recompute - and -terminate calls this for EVERY session on close, including
        // feature-off sessions that never titled. Checking the variable first skips that
        // per-session write + recompute for them, and unlike the generator's
        // lastAppliedTitle it also correctly clears a variable left stale after the
        // generator state was already dropped.
        if let current, !current.isEmpty {
            genericScope.setValue("", forVariableNamed: iTermVariableKeySessionAITitle)
        }
    }

    // Guid-keyed variant for -dealloc, which must not touch `self` and may run off
    // the main thread. The caller captures the guid and dispatches to the main
    // queue. Covers a session released without -terminate and without a guid
    // change (a broken pipe / tmux disconnect that set exited=YES).
    @objc
    @MainActor
    static func forgetAITitleState(forGuid guid: String) {
        AITabTitleGenerator.instance.forget(sessionID: guid)
    }

    // How many recent shell commands to feed the title model. Enough to show the
    // arc of a task without letting old, unrelated work dominate the context.
    private static let maxRecentAICommands = 8

    // The most recent shell commands run in this session, oldest first. Walks the
    // session's prompt marks (shell integration) and keeps the tail; the mark at
    // the current prompt has no command yet, so a command still being typed is
    // naturally excluded. Empty without shell integration.
    private func recentShellCommands(limit: Int) -> [String] {
        // Walk prompt marks newest-first and stop once we have `limit` commands,
        // rather than enumerating the entire (possibly tens-of-thousands) mark
        // history forward every ~5s just to keep the last few.
        var newestFirst: [String] = []
        screen.enumeratePromptsBackward { mark, stop in
            if let command = mark.fullCommand, !command.isEmpty {
                newestFirst.append(command)
                if newestFirst.count >= limit {
                    stop.pointee = true
                }
            }
        }
        return newestFirst.reversed()
    }

    // The structured context that precedes the screen. Only present fields go
    // into `text`; the raw fields are kept for the corpus. When idle at a shell
    // prompt the foreground job is just the shell (noise) and the command that
    // produced the screen has already exited, so the recent command history is
    // the real signal - it tells the model that a screenful of filenames is the
    // result of `ls DIR`, not a thing to name after one filename, and lets it
    // read a sequence of commands as one task in progress.
    private func aiTitleContext() -> AITabTitleContext {
        func string(_ name: String) -> String? {
            guard let value = genericScope.value(forVariableName: name) as? String,
                  !value.isEmpty else {
                return nil
            }
            return value
        }
        let job = string(iTermVariableKeySessionJob)
        let commandLine = string(iTermVariableKeySessionCommandLine)
        let cwd = string(iTermVariableKeySessionPath)
        let user = string(iTermVariableKeySessionUsername)
        let host = string(iTermVariableKeySessionHostname)
        let windowName = string(iTermVariableKeySessionWindowName)
        let atPrompt = isAtShellPrompt
        let lastCommand = string(iTermVariableKeySessionLastCommand)
        let home = string(iTermVariableKeySessionHomeDirectory)
        // Outside the alternate screen the command arc is a strong task signal,
        // whether idle at a prompt or with a long-running command in the
        // foreground: a slow `git push` should still be read as the tail of the
        // commit-and-push it followed, not named in isolation. In the alternate
        // screen the visible grid is the content, so history is noise.
        let recentCommands = screen.terminalSoftAlternateScreenMode
            ? []
            : recentShellCommands(limit: Self.maxRecentAICommands)

        let text = AITabTitleContext.assembleText(job: job,
                                                  commandLine: commandLine,
                                                  atPrompt: atPrompt,
                                                  lastCommand: lastCommand,
                                                  recentCommands: recentCommands,
                                                  cwd: cwd,
                                                  user: user,
                                                  host: host,
                                                  home: home,
                                                  runningCommandInHistory: haveAutoComposer())
        return AITabTitleContext(job: job,
                                 commandLine: commandLine,
                                 atPrompt: atPrompt,
                                 lastCommand: lastCommand,
                                 recentCommands: recentCommands,
                                 cwd: cwd,
                                 user: user,
                                 host: host,
                                 windowName: windowName,
                                 text: text)
    }
}
