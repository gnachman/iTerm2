import ArgumentParser
import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

struct Session: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage iTerm2 sessions.",
        subcommands: sortedSubcommands([
            List.self,
            Split.self,
            Run.self,
            Send.self,
            Close.self,
            Restart.self,
            Focus.self,
            Read.self,
            Clear.self,
            Capture.self,
            Copy.self,
            SetName.self,
            SetColor.self,
            SetStatus.self,
            GetStatus.self,
            GetBackgroundTasks.self,
            SetAgentConversation.self,
            GetVar.self,
            SetVar.self,
            AddClipping.self,
            ArchiveClippings.self,
            DeleteClipping.self,
        ])
    )
}

// MARK: - session list

extension Session {
    struct List: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all sessions."
        )

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        @Option(name: .long, help: ArgumentHelp(
            "Print an interpolated string for each session instead of the usual columns.",
            discussion: """
                Evaluated in each session’s context, as in a badge. For example: \
                --format '\\(session.id)\\t\\(session.path)\\t\\(session.jobName)'. \
                An undefined variable becomes an empty string. With --json, the result \
                is added to each session as “formatted”.
                """,
            valueName: "string"))
        var format: String?

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let formatInvocation = format.map { "iterm2.interpolate(string: \(swiftyStringLiteral($0)))" }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.listSessionsRequest = ITMListSessionsRequest()

            let response = try client.send(request)
            guard response.submessageOneOfCase == .listSessionsResponse,
                  let listResp = response.listSessionsResponse else {
                throw IT2Error.apiError("No list sessions response")
            }

            guard let windows = listResp.windowsArray as? [ITMListSessionsResponse_Window] else { return }

            var sessions: [(window: ITMListSessionsResponse_Window,
                            tab: ITMListSessionsResponse_Tab,
                            summary: ITMSessionSummary)] = []
            for window in windows {
                guard let tabs = window.tabsArray as? [ITMListSessionsResponse_Tab] else { continue }
                for tab in tabs {
                    walkSessions(in: tab) { s in
                        sessions.append((window, tab, s))
                    }
                }
            }

            let formattedValues = try formatInvocation.map {
                try formatAll(client: client,
                              invocation: $0,
                              sessionIds: sessions.map { $0.summary.uniqueIdentifier ?? "" },
                              ctx: ctx)
            }

            // A formatted line replaces the columns, so text output doesn't need the
            // variables behind them.
            if let formattedValues, !json {
                for value in formattedValues {
                    ctx.out(value)
                }
                return
            }

            var sessionsData: [[String: Any]] = []
            for (i, (window, tab, s)) in sessions.enumerated() {
                let isTmux = tab.tmuxWindowId != nil && tab.tmuxWindowId != "-1"
                let cols = s.hasGridSize ? Int(s.gridSize.width) : 0
                let rows = s.hasGridSize ? Int(s.gridSize.height) : 0
                let id = s.uniqueIdentifier ?? ""
                let vars = (try? fetchSessionVars(client: client, sessionId: id))
                    ?? (name: "", tty: "")
                var entry: [String: Any] = [
                    "id": id,
                    "name": vars.name,
                    "title": s.title ?? "",
                    "tty": vars.tty,
                    "cols": cols,
                    "rows": rows,
                    "window_id": window.windowId ?? "",
                    "tab_id": tab.tabId ?? "",
                    "is_tmux": isTmux,
                ]
                if let formattedValues {
                    entry["formatted"] = formattedValues[i]
                }
                sessionsData.append(entry)
            }

            if json {
                ctx.printJSON(sessionsData)
            } else {
                for s in sessionsData {
                    let id = s["id"] as? String ?? ""
                    let name = s["name"] as? String ?? ""
                    let title = s["title"] as? String ?? ""
                    let size = "\(s["cols"] ?? 0)x\(s["rows"] ?? 0)"
                    let tty = s["tty"] as? String ?? ""
                    ctx.out("\(id)\t\(name)\t\(title)\t\(size)\t\(tty)")
                }
            }
        }


        /// Evaluate the --format invocation in each session's context, in order.
        ///
        /// An iTerm2 that predates iterm2.interpolate fails the up-front probe, so
        /// nothing is evaluated. Past that, a session that fails (it closed during
        /// the listing, or the format calls a function that fails there) gets an
        /// empty string, as an undefined variable does, and each distinct reason is
        /// reported once on stderr. When every session fails the format itself is at
        /// fault (a syntax error, say), so that throws. Only a failure the function
        /// reports counts as a session's; a transport error such as iTerm2 quitting
        /// mid-listing throws, rather than blanking the remaining sessions.
        private func formatAll(client: APIClient,
                               invocation: String,
                               sessionIds: [String],
                               ctx: IT2Context) throws -> [String] {
            _ = try client.invoke("iterm2.interpolate(string: \"\")",
                                  failure: "This version of iTerm2 doesn’t support --format")

            var values: [String] = []
            var failures: [(sessionId: String, error: Error)] = []
            for sessionId in sessionIds {
                do {
                    let result = try client.invoke(invocation,
                                                   sessionID: sessionId,
                                                   failure: "Could not evaluate --format")
                    values.append(decodeJSONString(result) ?? "")
                } catch let error as IT2Error {
                    guard case .functionFailed = error else {
                        throw error
                    }
                    failures.append((sessionId, error))
                    values.append("")
                }
            }
            if let first = failures.first, failures.count == sessionIds.count {
                throw first.error
            }
            var reported = Set<String>()
            for failure in failures where reported.insert("\(failure.error)").inserted {
                ctx.err("\(failure.error) (session \(failure.sessionId))")
            }
            return values
        }

        /// Fetch session.name and session.tty via VariableRequest.
        private func fetchSessionVars(client: APIClient, sessionId: String) throws -> (name: String, tty: String) {
            let varReq = ITMVariableRequest()
            varReq.sessionId = sessionId
            varReq.getArray.add("session.name")
            varReq.getArray.add("session.tty")

            let msg = ITMClientOriginatedMessage()
            msg.id_p = client.nextId()
            msg.variableRequest = varReq

            let resp = try client.send(msg)
            var name = ""
            var tty = ""
            if resp.submessageOneOfCase == .variableResponse,
               let vr = resp.variableResponse,
               vr.status == ITMVariableResponse_Status.ok {
                if vr.valuesArray_Count > 0, let n = vr.valuesArray.object(at: 0) as? String {
                    name = decodeJSONString(n) ?? ""
                }
                if vr.valuesArray_Count > 1, let t = vr.valuesArray.object(at: 1) as? String {
                    tty = decodeJSONString(t) ?? ""
                }
            }
            return (name, tty)
        }
    }
}

// MARK: - session split

extension Session {
    struct Split: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "split",
            abstract: "Split current session."
        )

        @Flag(name: .shortAndLong, help: "Split vertically.")
        var vertical = false

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Option(name: .shortAndLong, help: "Profile to use for new pane.")
        var profile: String?

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let split = ITMSplitPaneRequest()
            split.session = APIClient.normalizeSessionId(session ?? "active")
            split.splitDirection = vertical ? .vertical : .horizontal
            if let profile = profile {
                split.profileName = profile
            }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.splitPaneRequest = split

            let response = try client.send(request)
            guard response.submessageOneOfCase == .splitPaneResponse,
                  let splitResp = response.splitPaneResponse else {
                throw IT2Error.apiError("No split pane response")
            }

            guard splitResp.status == ITMSplitPaneResponse_Status.ok else {
                if splitResp.status == ITMSplitPaneResponse_Status.sessionNotFound {
                    throw IT2Error.targetNotFound("Session not found")
                } else if splitResp.status == ITMSplitPaneResponse_Status.cannotSplit {
                    throw IT2Error.apiError("Cannot split this pane. A floating pane can’t be split, and a pane may be too small.")
                } else {
                    throw IT2Error.apiError("Split failed with status \(splitResp.status.rawValue)")
                }
            }

            guard splitResp.sessionIdArray_Count > 0,
                  let newSessionId = splitResp.sessionIdArray.object(at: 0) as? String else {
                throw IT2Error.apiError("Split succeeded but no session ID returned")
            }

            ctx.out("Created new pane: \(newSessionId)")
        }
    }
}

// MARK: - session run

extension Session {
    struct Run: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Execute command in session with newline."
        )

        @Argument(help: "Command to run.")
        var command: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Flag(name: .shortAndLong, help: "Run in all sessions.")
        var all = false

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let sendText = ITMSendTextRequest()
            sendText.session = all ? "all" : (APIClient.normalizeSessionId(session ?? "active"))
            sendText.text = command + "\r"

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.sendTextRequest = sendText

            let response = try client.send(request)
            guard response.submessageOneOfCase == .sendTextResponse,
                  let sendResp = response.sendTextResponse else {
                throw IT2Error.apiError("No send text response")
            }
            guard sendResp.status == ITMSendTextResponse_Status.ok else {
                throw IT2Error.targetNotFound("Session not found")
            }

            if all {
                let windows = try fetchWindows(client: client)
                var count = 0
                for win in windows {
                    if let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                        for tab in tabs { count += collectSessionIds(in: tab).count }
                    }
                }
                if count > 1 {
                    ctx.out("Executed command in \(count) sessions")
                }
            }
        }
    }
}

// MARK: - session send

extension Session {
    struct Send: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "send",
            abstract: "Send text to session without newline."
        )

        @Argument(help: "Text to send.")
        var text: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Flag(name: .shortAndLong, help: "Send to all sessions.")
        var all = false

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let sendText = ITMSendTextRequest()
            sendText.session = all ? "all" : (APIClient.normalizeSessionId(session ?? "active"))
            sendText.text = text

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.sendTextRequest = sendText

            let response = try client.send(request)
            guard response.submessageOneOfCase == .sendTextResponse,
                  let sendResp = response.sendTextResponse else {
                throw IT2Error.apiError("No send text response")
            }
            guard sendResp.status == ITMSendTextResponse_Status.ok else {
                throw IT2Error.targetNotFound("Session not found")
            }

            if all {
                let windows = try fetchWindows(client: client)
                var count = 0
                for win in windows {
                    if let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                        for tab in tabs { count += collectSessionIds(in: tab).count }
                    }
                }
                if count > 1 {
                    ctx.out("Sent text to \(count) sessions")
                }
            }
        }
    }
}

// MARK: - session close

extension Session {
    struct Close: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "close",
            abstract: "Close session."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Flag(name: .shortAndLong, help: "Force close without confirmation.")
        var force = false

        func run(_ ctx: IT2Context) throws {
            let sessionId = APIClient.normalizeSessionId(session ?? "active")

            try ctx.confirmOrThrow("Close session \(sessionId)?", force: force)

            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let closeReq = ITMCloseRequest()
            let closeSessions = ITMCloseRequest_CloseSessions()
            closeSessions.sessionIdsArray.add(sessionId)
            closeReq.sessions = closeSessions

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.closeRequest = closeReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .closeResponse,
                  let closeResp = response.closeResponse else {
                throw IT2Error.apiError("No close response")
            }

            if closeResp.statusesArray_Count > 0 {
                let status = closeResp.statusesArray.value(at: 0)
                if status == ITMCloseResponse_Status.notFound.rawValue {
                    throw IT2Error.targetNotFound("Session not found")
                } else if status == ITMCloseResponse_Status.userDeclined.rawValue {
                    throw IT2Error.apiError("User declined to close session")
                }
            }

            ctx.out("Session closed")
        }
    }
}

// MARK: - session set-name

extension Session {
    struct SetName: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "set-name",
            abstract: "Set session name."
        )

        @Argument(help: "Name to set.")
        var name: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)

            let invoke = ITMInvokeFunctionRequest()
            let method = ITMInvokeFunctionRequest_Method()
            method.receiver = sessionId
            invoke.method = method
            invoke.invocation = "iterm2.set_name(name: \(jsonString(name)))"

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.invokeFunctionRequest = invoke

            let response = try client.send(request)
            guard response.submessageOneOfCase == .invokeFunctionResponse,
                  let invokeResp = response.invokeFunctionResponse else {
                throw IT2Error.apiError("No invoke function response")
            }

            if invokeResp.dispositionOneOfCase == .error {
                let reason = invokeResp.error?.errorReason ?? "unknown"
                throw IT2Error.apiError("Set name failed: \(reason)")
            }

            ctx.out("Session name set to: \(name)")
        }
    }
}

// MARK: - session set-color

extension Session {
    struct SetColor: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "set-color",
            abstract: "Set session tab color."
        )

        @Argument(help: "Color as hex string (e.g. #FF0000).")
        var color: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run(_ ctx: IT2Context) throws {
            let colorJSON = try colorToJSON(color)

            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)

            let setProp = ITMSetProfilePropertyRequest()
            setProp.session = sessionId

            let enableColor = ITMSetProfilePropertyRequest_Assignment()
            enableColor.key = "Use Tab Color"
            enableColor.jsonValue = "true"

            let setColor = ITMSetProfilePropertyRequest_Assignment()
            setColor.key = "Tab Color"
            setColor.jsonValue = colorJSON

            setProp.assignmentsArray = NSMutableArray(array: [enableColor, setColor])

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.setProfilePropertyRequest = setProp

            let response = try client.send(request)
            guard response.submessageOneOfCase == .setProfilePropertyResponse,
                  let propResp = response.setProfilePropertyResponse else {
                throw IT2Error.apiError("No set profile property response")
            }
            guard propResp.status == ITMSetProfilePropertyResponse_Status.ok else {
                throw IT2Error.apiError("Set color failed with status \(propResp.status.rawValue)")
            }

            ctx.out("Tab color set to \(color)")
        }

    }
}

// MARK: - session restart

extension Session {
    struct Restart: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "restart",
            abstract: "Restart session."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let restartReq = ITMRestartSessionRequest()
            restartReq.sessionId = try client.resolveSessionId(session)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.restartSessionRequest = restartReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .restartSessionResponse,
                  let restartResp = response.restartSessionResponse else {
                throw IT2Error.apiError("No restart session response")
            }
            guard restartResp.status == ITMRestartSessionResponse_Status.ok else {
                throw IT2Error.apiError("Restart failed with status \(restartResp.status.rawValue)")
            }
            ctx.out("Session restarted")
        }
    }
}

// MARK: - session focus

extension Session {
    struct Focus: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "focus",
            abstract: "Focus a specific session."
        )

        @Argument(help: "Session ID to focus.")
        var sessionId: String

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let activate = ITMActivateRequest()
            activate.sessionId = sessionId
            activate.selectSession = true
            activate.selectTab = true
            activate.orderWindowFront = true

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.activateRequest = activate

            let response = try client.send(request)
            guard response.submessageOneOfCase == .activateResponse,
                  let activateResp = response.activateResponse else {
                throw IT2Error.apiError("No activate response")
            }
            guard activateResp.status == ITMActivateResponse_Status.ok else {
                throw IT2Error.targetNotFound("Session '\(sessionId)' not found")
            }
            ctx.out("Focused session: \(sessionId)")
        }
    }
}

// MARK: - session read

extension Session {
    struct Read: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Display screen contents."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Option(name: [.customShort("n"), .long], help: "Number of lines to read.")
        var lines: Int?

        func run(_ ctx: IT2Context) throws {
            // Reject a negative count up front: Collection.suffix(_:) traps on a negative
            // length (the `--lines=-5` form parses a negative straight into the Int?
            // option), and embedded over SSH that trap would take down the whole iTerm2
            // process -- a remote user must never be able to reach it.
            if let n = lines, n < 0 {
                throw IT2Error.invalidArgument("--lines must be non-negative")
            }

            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let bufReq = ITMGetBufferRequest()
            bufReq.session = try client.resolveSessionId(session)
            let lineRange = ITMLineRange()
            lineRange.screenContentsOnly = true
            bufReq.lineRange = lineRange

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.getBufferRequest = bufReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .getBufferResponse,
                  let bufResp = response.getBufferResponse else {
                throw IT2Error.apiError("No get buffer response")
            }
            guard bufResp.status == ITMGetBufferResponse_Status.ok else {
                throw IT2Error.targetNotFound("Session not found")
            }

            guard let contents = bufResp.contentsArray as? [ITMLineContents] else { return }
            let outputLines: [ITMLineContents]
            if let n = lines, n < contents.count {  // n >= 0 (validated above), so suffix is safe
                outputLines = Array(contents.suffix(n))
            } else {
                outputLines = contents
            }
            for line in outputLines {
                ctx.out(line.text ?? "")
            }
        }
    }
}

// MARK: - session clear

extension Session {
    struct Clear: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear screen."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let sendText = ITMSendTextRequest()
            sendText.session = APIClient.normalizeSessionId(session ?? "active")
            sendText.text = "\u{0C}" // Ctrl+L

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.sendTextRequest = sendText

            let _ = try client.send(request)
        }
    }
}

// MARK: - session capture

extension Session {
    struct Capture: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "capture",
            abstract: "Capture screen to file."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Option(name: .shortAndLong, help: "Output file path.")
        var output: String

        @Flag(name: .long, help: "Include scrollback history.")
        var history = false

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let bufReq = ITMGetBufferRequest()
            bufReq.session = try client.resolveSessionId(session)
            let lineRange = ITMLineRange()
            if history {
                lineRange.trailingLines = Int32.max
            } else {
                lineRange.screenContentsOnly = true
            }
            bufReq.lineRange = lineRange

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.getBufferRequest = bufReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .getBufferResponse,
                  let bufResp = response.getBufferResponse else {
                throw IT2Error.apiError("No get buffer response")
            }
            guard bufResp.status == ITMGetBufferResponse_Status.ok else {
                throw IT2Error.targetNotFound("Session not found")
            }

            guard let contents = bufResp.contentsArray as? [ITMLineContents] else { return }
            let text = contents.map { $0.text ?? "" }.joined(separator: "\n")
            try text.write(toFile: output, atomically: true, encoding: .utf8)
            ctx.out("Screen captured to: \(output)")
        }
    }
}

// MARK: - session copy

extension Session {
    struct Copy: ParsableCommand, IT2Runnable {
        static let configuration = CommandConfiguration(
            commandName: "copy",
            abstract: "Copy selection to clipboard."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)

            // Get selection.
            let selReq = ITMSelectionRequest()
            let getSelReq = ITMSelectionRequest_GetSelectionRequest()
            getSelReq.sessionId = sessionId
            selReq.getSelectionRequest = getSelReq

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.selectionRequest = selReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .selectionResponse,
                  let selResp = response.selectionResponse,
                  selResp.status == ITMSelectionResponse_Status.ok,
                  selResp.responseOneOfCase == .getSelectionResponse,
                  let getResp = selResp.getSelectionResponse,
                  let selection = getResp.selection,
                  selection.subSelectionsArray_Count > 0,
                  let subSelections = selection.subSelectionsArray as? [ITMSubSelection] else {
                ctx.out("No selection")
                return
            }

            // Extract text for each sub-selection using its coordinate range.
            var selectedTexts: [String] = []
            for subSel in subSelections {
                guard let coordRange = subSel.windowedCoordRange else { continue }

                let bufReq = ITMGetBufferRequest()
                bufReq.session = sessionId
                let lineRange = ITMLineRange()
                lineRange.windowedCoordRange = coordRange
                bufReq.lineRange = lineRange

                let bufMsg = ITMClientOriginatedMessage()
                bufMsg.id_p = client.nextId()
                bufMsg.getBufferRequest = bufReq

                let bufResp = try client.send(bufMsg)
                if bufResp.submessageOneOfCase == .getBufferResponse,
                   let buf = bufResp.getBufferResponse,
                   buf.status == ITMGetBufferResponse_Status.ok,
                   let contents = buf.contentsArray as? [ITMLineContents] {
                    let text = contents.map { $0.text ?? "" }.joined(separator: "\n")
                    selectedTexts.append(text)
                }
            }

            guard !selectedTexts.isEmpty else {
                ctx.out("No text selected")
                return
            }

            let text = selectedTexts.joined(separator: "\n")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(Data(text.utf8))
            pipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            ctx.out("Selection copied to clipboard")
        }
    }
}

// MARK: - session get-var

extension Session {
    struct GetVar: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-var",
            abstract: "Get session variable value.",
            discussion: "See also: it2 session set-var"
        )

        @Argument(help: "Variable name.")
        var variable: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }
            let varReq = ITMVariableRequest()
            varReq.sessionId = sessionId
            varReq.getArray.add(variable)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.variableRequest = varReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .variableResponse,
                  let varResp = response.variableResponse else {
                throw IT2Error.apiError("No variable response")
            }
            guard varResp.status == ITMVariableResponse_Status.ok else {
                throw IT2Error.apiError("Get variable failed with status \(varResp.status.rawValue)")
            }

            if varResp.valuesArray_Count > 0,
               let value = varResp.valuesArray.object(at: 0) as? String,
               value != "null" {
                ctx.out(value)
            } else {
                ctx.out("Variable '\(variable)' not set")
            }
        }
    }
}

// MARK: - session add-clipping

extension Session {
    struct AddClipping: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add-clipping",
            abstract: "Add a clipping to a session (e.g., a code review comment).",
            discussion: "Prints the new clipping’s unique ID. See also: it2 session delete-clipping"
        )

        @Argument(help: "Clipping type (e.g., “Code Review Comment”).")
        var type: String

        @Argument(help: "Clipping title.")
        var title: String

        @Argument(help: "Clipping detail.")
        var detail: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }
            let result = try client.invoke(
                "iterm2.add_clipping(type: \(jsonString(type)), title: \(jsonString(title)), detail: \(jsonString(detail)))",
                sessionID: sessionId,
                failure: "Add clipping failed")
            // Older versions of iTerm2 return nothing.
            if let identifier = decodeJSONString(result) {
                ctx.out(identifier)
            }
        }
    }
}

// MARK: - session archive-clippings

extension Session {
    struct ArchiveClippings: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "archive-clippings",
            abstract: "Archive a session's clippings, clearing the live list and adding a history entry."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }
            _ = try client.invoke("iterm2.archive_clippings()",
                                  sessionID: sessionId,
                                  failure: "Archive clippings failed")
        }
    }
}

// MARK: - session delete-clipping

extension Session {
    struct DeleteClipping: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete-clipping",
            abstract: "Delete a session’s clipping by the ID add-clipping printed.",
            discussion: "Only live clippings can be deleted, not archived ones. See also: it2 session add-clipping"
        )

        @Argument(help: "Clipping ID, as printed by add-clipping.")
        var id: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }
            _ = try client.invoke("iterm2.delete_clipping(id: \(jsonString(id)))",
                                  sessionID: sessionId,
                                  failure: "Delete clipping failed")
        }
    }
}

// MARK: - session set-var

extension Session {
    struct SetVar: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-var",
            abstract: "Set session variable value.",
            discussion: """
                With --peer-name, the variable is set on every member of the calling \
                session\u{2019}s workgroup that has that name (ignoring case), so an \
                agent can reach a peer without knowing its session ID. A member that \
                hasn\u{2019}t started yet gets the value when it does. For example, \
                a browser peer whose URL is \\(user.reviewURL) navigates when an \
                agent in its workgroup runs: \
                it2 session set-var --peer-name Browser user.reviewURL https://example.com/

                See also: it2 session get-var
                """
        )

        @Argument(help: "Variable name.")
        var variable: String

        @Argument(help: "Value to set: JSON, or else a plain string.")
        var value: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux). With --peer-name, the session whose workgroup to search.")
        var session: String?

        // An array so that giving it twice can be refused rather than the last one winning.
        @Option(name: .customLong("peer-name"), help: "Set the variable on the members of the caller\u{2019}s workgroup with this name.")
        var peerNames: [String] = []

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            // A permission rule that allows this command for one peer is a prefix match, so
            // anything appended to it is allowed too, and a second --peer-name would otherwise
            // replace the first and reach another member.
            guard peerNames.count <= 1 else {
                throw IT2Error.invalidArgument("--peer-name can be given only once.")
            }
            let peerName = peerNames.first
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            let explicit = !(session ?? "").isEmpty || tmuxOptions.usesTmuxAddressing
            // With no target, the caller's own session is the one searched. A caller that seems
            // to be in a session it can't identify would otherwise fall back to the focused
            // session, which may be another workgroup whose browser has the user's sign-ins.
            if peerName != nil, !explicit, client.callerSessionID() == nil, client.callerSeemsToBeInASession {
                throw IT2Error.invalidArgument(
                    "it2 couldn\u{2019}t tell which session it is running in, so it can\u{2019}t find the workgroup member named by --peer-name.")
            }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           allowAll: peerName == nil,
                                                           ctx: ctx) else {
                return
            }
            guard let peerName else {
                try Self.set(variable: variable, value: value, sessionID: sessionId, client: client)
                ctx.out("Set \(variable) = \(value)")
                return
            }
            // Likewise --session or --tmux would pick another workgroup to search, and its
            // browser has the user's sign-ins. So a caller running in a session may only name that
            // session, and one that seems to be in a session it can't identify may name none; only
            // one plainly outside iTerm2 may name any.
            if explicit {
                // "active" is resolved by iTerm2 when the function runs, to whichever session has
                // focus then, so checking it here would race a focus change. Leaving out
                // --session already means the caller's own session.
                if sessionId == "active" {
                    throw IT2Error.invalidArgument(
                        "With --peer-name, leave out --session to use the session it2 is running in. \u{201C}active\u{201D} is whichever session has focus, which may be in another workgroup.")
                }
                let caller = client.callerSessionID()
                if !Self.sessionID(sessionId, isCaller: caller, callerSeemsToBeInASession: client.callerSeemsToBeInASession) {
                    throw IT2Error.invalidArgument(
                        "With --peer-name, --session and --tmux can only name the session it2 is running in, since the peer is looked up in that session\u{2019}s workgroup.")
                }
            }
            // iTerm2 sets it on each member with the name, and on one that hasn't started (a
            // peer still spawning, or in tmux one not created until shown), when it starts.
            let invocation = "iterm2.set_workgroup_member_variable(session_id: \(jsonString(sessionId)), " +
                "name: \(jsonString(peerName)), variable: \(jsonString(variable)), " +
                "json_value: \(jsonString(Self.jsonValue(value))))"
            let result = try client.invoke(invocation, failure: "Couldn\u{2019}t set \(variable) on workgroup member \(peerName)")
            let counts = Self.memberVariableCounts(result)
            if counts.set > 0 {
                ctx.out("Set \(variable) = \(value) on \(counts.set) workgroup member\(counts.set == 1 ? "" : "s") named \(peerName)")
            }
            if counts.pending > 0 {
                ctx.out("The workgroup member named \(peerName) hasn\u{2019}t started yet. It gets \(variable) = \(value) when it does.")
            }
            if counts.failed > 0 {
                throw IT2Error.apiError("Couldn\u{2019}t set \(variable) on \(counts.failed) workgroup member\(counts.failed == 1 ? "" : "s") named \(peerName)")
            }
        }

        /// The counts in set_workgroup_member_variable's result.
        static func memberVariableCounts(_ result: String) -> (set: Int, failed: Int, pending: Int) {
            guard let data = result.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return (0, 0, 0)
            }
            func count(_ key: String) -> Int {
                return (dict[key] as? NSNumber)?.intValue ?? 0
            }
            return (count("set"), count("failed"), count("pending"))
        }

        private static func set(variable: String,
                                value: String,
                                sessionID: String,
                                client: APIClient) throws {
            let varReq = ITMVariableRequest()
            varReq.sessionId = sessionID

            let setEntry = ITMVariableRequest_Set()
            setEntry.name = variable
            setEntry.value = jsonValue(value)
            varReq.setArray.add(setEntry)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.variableRequest = varReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .variableResponse,
                  let varResp = response.variableResponse else {
                throw IT2Error.apiError("No variable response")
            }
            guard varResp.status == ITMVariableResponse_Status.ok else {
                throw IT2Error.apiError("Set variable failed with status \(varResp.status.rawValue)")
            }
        }

        /// Whether a --session or --tmux target may be searched for a peer: it is the caller's
        /// own session (GUIDs compared without regard to case), or the caller plainly runs outside
        /// iTerm2 and so may name any.
        static func sessionID(_ sessionID: String, isCaller caller: String?, callerSeemsToBeInASession: Bool) -> Bool {
            guard let caller else {
                return !callerSeemsToBeInASession
            }
            return caller.caseInsensitiveCompare(sessionID) == .orderedSame
        }

        /// The API takes the value as JSON and ignores one that doesn't parse, so a
        /// value that is already JSON (a quoted string, number, object, ...) goes as
        /// is and anything else is sent as a JSON string.
        static func jsonValue(_ value: String) -> String {
            if let data = value.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil {
                return value
            }
            return jsonString(value)
        }
    }
}

// MARK: - session get-status

extension Session {
    /// The read-back get-status and set-status --json share.
    static func getStatusInvocation(sessionID: String) -> String {
        return "iterm2.get_session_status(session_id: \(jsonString(sessionID)))"
    }

    struct GetStatus: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-status",
            abstract: "Print a session’s status indicator as JSON: status, text_color, dot_color, detail, background_tasks and turn_open.",
            discussion: """
                turn_open is null until set-status --turn-open has been called \
                for the session. set-status --json prints the same thing \
                after applying an update. See also: it2 session set-status
                """
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }

            let result = try client.invoke(Session.getStatusInvocation(sessionID: sessionId),
                                           failure: "Get status failed")
            // Keys match set-status's options, and an unset field is null rather than absent, so
            // a read and a write are obviously symmetric.
            ctx.out(result.isEmpty ? "{}" : result)
        }
    }
}

// MARK: - session set-status

/// The two states of the tab's progress ring a status update can ask for. Spelled the same way
/// in the set_session_status built-in.
enum ProgressOption: String, ExpressibleByArgument {
    case running
    case stopped
}

// The options for setting a session status, shared by `it2 session set-status`
// and the top-level `it2 set-status` shortcut so the two cannot drift.
struct SetStatusOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
    var session: String?

    @OptionGroup var tmuxOptions: TmuxPaneOptions

    @Option(name: .long, help: "Status text (waiting, done, error, working, or idle).")
    var status: String?

    @Option(name: .long, help: "Dot indicator color as #rrggbb.")
    var dotColor: String?

    @Option(name: .long, help: "Text color as #rrggbb.")
    var textColor: String?

    @Option(name: .long, help: "Optional detail text shown alongside the status.")
    var detail: String?

    @Option(name: .long, help: "Number of background tasks still running (stored in memory for later get-background-tasks queries).")
    var backgroundTasks: Int?

    @Option(name: .long, parsing: .unconditional, help: """
        Add to the background task count rather than assigning it, \
        clamped at zero. The read and the write happen together, so two \
        callers counting at the same time cannot lose an update the way a \
        separate get-background-tasks and set-status could. Cannot be \
        combined with --background-tasks. Pass --json to see the result.
        """)
    var backgroundTasksDelta: Int?

    @Option(name: .long, help: """
        Record whether the status-reporting program is mid-turn (true or \
        false). Stored in memory for later get-status queries.
        """)
    var turnOpen: Bool?

    @Option(name: .long, help: """
        Apply the update only if the turn flag currently holds this value \
        (true or false). A flag never set matches neither. Together with \
        --if-background-tasks this lets a caller act on a status it read \
        a moment ago without a newer update being overwritten in between; \
        with --json, the printed status shows whether the update landed.
        """)
    var ifTurnOpen: Bool?

    @Option(name: .long, help: """
        Apply the update only if the background task count currently \
        equals this value. See --if-turn-open.
        """)
    var ifBackgroundTasks: Int?

    @Flag(name: .long, help: """
        Print the status as it stood once this update was applied, in the \
        form get-status prints, instead of the usual message. Lets a \
        caller that changed the count or closed the turn learn in the \
        same round trip what the session looked like at that instant.
        """)
    var json = false

    @Option(name: .long, help: """
        Draw or stop the tab’s progress ring: running or stopped. For a \
        program that reports through hooks but does not emit the progress \
        protocol (OSC 9;4) itself. Applied the way the terminal applies the \
        protocol, so an expiring status sees the ring stop.
        """)
    var progress: ProgressOption?

    @Option(name: .long, help: "Expire this status by itself when an event happens. The only value is “progress-end”: the session reported through the progress protocol (OSC 9;4) that the operation running when the status was set has ended.")
    var expiresOn: String?

    @Option(name: .long, help: "Status text to leave behind when the status expires. Empty clears it.")
    var thenStatus: String?

    @Option(name: .long, help: "Dot indicator color to leave behind when the status expires, as #rrggbb. Empty clears it.")
    var thenDotColor: String?

    @Option(name: .long, help: "Text color to leave behind when the status expires, as #rrggbb. Empty clears it.")
    var thenTextColor: String?

    @Option(name: .long, help: "Detail text to leave behind when the status expires. Empty clears it.")
    var thenDetail: String?

    @Option(name: .long, help: ArgumentHelp("Which agent's hook is writing this status (claude or codex). Set by handle-agent-hook.", visibility: .hidden))
    var agent: String?

    /// The keyword arguments for iterm2.set_session_status, minus session_id.
    var invocationArguments: [String] {
        var args: [String] = []
        if let agent {
            args.append("agent: \(jsonString(agent))")
        }
        if let status {
            args.append("status: \(jsonString(status))")
        }
        if let textColor {
            args.append("text_color: \(jsonString(textColor))")
        }
        if let dotColor {
            args.append("dot_color: \(jsonString(dotColor))")
        }
        if let detail {
            args.append("detail: \(jsonString(detail))")
        }
        if let progress {
            args.append("progress: \(jsonString(progress.rawValue))")
        }
        if let backgroundTasks {
            args.append("background_tasks: \(backgroundTasks)")
        }
        if let backgroundTasksDelta {
            args.append("background_tasks_delta: \(backgroundTasksDelta)")
        }
        if let turnOpen {
            args.append("turn_open: \(turnOpen)")
        }
        if let ifTurnOpen {
            args.append("if_turn_open: \(ifTurnOpen)")
        }
        if let ifBackgroundTasks {
            args.append("if_background_tasks: \(ifBackgroundTasks)")
        }
        if let expiresOn {
            args.append("expires_on: \(jsonString(expiresOn))")
        }
        if let thenStatus {
            args.append("then_status: \(jsonString(thenStatus))")
        }
        if let thenDotColor {
            args.append("then_dot_color: \(jsonString(thenDotColor))")
        }
        if let thenTextColor {
            args.append("then_text_color: \(jsonString(thenTextColor))")
        }
        if let thenDetail {
            args.append("then_detail: \(jsonString(thenDetail))")
        }
        return args
    }
}

extension Session {
    struct SetStatus: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-status",
            abstract: "Set session status indicator.",
            discussion: "See also: it2 session get-status, it2 session get-background-tasks"
        )

        @OptionGroup var options: SetStatusOptions

        var tmuxOptions: TmuxPaneOptions { return options.tmuxOptions }

        /// The JSON --json prints. An older iTerm2 answers set_session_status
        /// with nothing at all, and the update has landed by the time the
        /// answer is looked at, so an answer that is not the status is not a
        /// failure: the status is read back with `readBack` instead. Only when
        /// that gives nothing either is the caller told that the update went
        /// through but its result is unknown.
        static func statusJSON(fromResult result: String, readBack: () throws -> String) throws -> String {
            if result.hasPrefix("{") {
                return result
            }
            let status = try readBack()
            guard status.hasPrefix("{") else {
                throw IT2Error.apiError("Status updated but the resulting status was not returned")
            }
            return status
        }

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(options.session,
                                                           tmuxOptions: options.tmuxOptions,
                                                           ctx: ctx) else {
                return
            }

            let args = ["session_id: \(jsonString(sessionId))"] + options.invocationArguments
            let result = try client.invoke("iterm2.set_session_status(\(args.joined(separator: ", ")))",
                                           failure: "Set status failed")

            // The status comes back with every call, but printing it only on
            // request keeps this parseable: a caller that asked for it gets
            // the JSON and nothing else.
            if options.json {
                ctx.out(try Self.statusJSON(fromResult: result) {
                    try client.invoke(Session.getStatusInvocation(sessionID: sessionId),
                                      failure: "Status updated but it could not be read back")
                })
                return
            }
            ctx.out("Session status updated.")
        }
    }
}

// MARK: - session get-background-tasks

extension Session {
    struct GetBackgroundTasks: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-background-tasks",
            abstract: "Print the background-task count last stored via set-status --background-tasks.",
            discussion: "See also: it2 session set-status"
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }

            let result = try client.invoke("iterm2.get_background_task_count()",
                                           sessionID: sessionId,
                                           failure: "Get background tasks failed")
            ctx.out(result.isEmpty ? "0" : result)
        }
    }
}

// MARK: - session set-agent-conversation

extension Session {
    /// The invocation set-agent-conversation makes. Internal so tests can pin it. The agent,
    /// directory, and transcript describe a conversation that started, so iTerm2 can offer to
    /// resume it after a restart; `userQuit` with `ended` says there is nothing to resume.
    static func setAgentConversationInvocation(sessionID: String,
                                               conversationID: String,
                                               ended: Bool = false,
                                               userQuit: Bool = false,
                                               agent: AgentKind? = nil,
                                               directory: String? = nil,
                                               transcript: String? = nil) -> String {
        var args = ["session_id: \(jsonString(sessionID))",
                    "conversation_id: \(jsonString(conversationID))"]
        if ended {
            args.append("ended: true")
            if userQuit {
                args.append("quit: true")
            }
        }
        if let agent {
            args.append("agent: \(jsonString(agent.rawValue))")
        }
        if let directory {
            args.append("directory: \(jsonString(directory))")
        }
        if let transcript {
            args.append("transcript: \(jsonString(transcript))")
        }
        return "iterm2.set_agent_conversation(\(args.joined(separator: ", ")))"
    }

    struct SetAgentConversation: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-agent-conversation",
            abstract: "Say which agent conversation a session is running.",
            discussion: """
                Agent hooks run this when a conversation starts or resumes, and with \
                --ended when it ends. iTerm2 remembers what a workgroup\u{2019}s browser \
                showed for each conversation and shows it again when the same \
                conversation resumes. Given the agent, iTerm2 also offers to resume the \
                conversation if a restart of iTerm2 or the Mac ends it.
                """,
            // Only agent hooks run this, through handle-agent-hook.
            shouldDisplay: false
        )

        @Argument(help: "The agent\u{2019}s conversation ID, such as Claude Code\u{2019}s session_id.")
        var conversationID: String

        @Flag(name: .long, help: "The conversation ended. Forgotten only if it is still the session\u{2019}s.")
        var ended = false

        @Flag(name: .long, help: "With --ended: the user quit the agent on purpose, so there is nothing to offer to resume.")
        var quit = false

        @Option(name: .long, help: "Which agent runs the conversation: claude or codex. Needed for the offer to resume.")
        var agent: AgentKind?

        @Option(name: .long, help: "The directory the agent is running in.")
        var directory: String?

        @Option(name: .long, help: "The file the agent keeps the conversation in. If given, iTerm2 offers to resume only once it exists.")
        var transcript: String?

        @Option(name: .shortAndLong, help: "Target session ID (default: active, or the pane named by --tmux).")
        var session: String?

        @OptionGroup var tmuxOptions: TmuxPaneOptions

        func run(_ ctx: IT2Context) throws {
            let client = try ctx.makeClient()
            defer { client.disconnect() }

            guard let sessionId = try client.resolveTarget(session,
                                                           tmuxOptions: tmuxOptions,
                                                           ctx: ctx) else {
                return
            }
            let full = Session.setAgentConversationInvocation(sessionID: sessionId,
                                                              conversationID: conversationID,
                                                              ended: ended,
                                                              userQuit: quit,
                                                              agent: agent,
                                                              directory: directory,
                                                              transcript: transcript)
            let basic = Session.setAgentConversationInvocation(sessionID: sessionId,
                                                               conversationID: conversationID,
                                                               ended: ended)
            do {
                _ = try client.invoke(full, failure: "Set agent conversation failed")
            } catch where full != basic {
                // An iTerm2 that knows only the conversation ID refuses the rest. What it does
                // know (the workgroup browser's memory) still works.
                _ = try client.invoke(basic, failure: "Set agent conversation failed")
            }
        }
    }
}
