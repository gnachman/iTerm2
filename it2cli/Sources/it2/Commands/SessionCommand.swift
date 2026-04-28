import ArgumentParser
import Foundation
import ProtobufRuntime

struct Session: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage iTerm2 sessions.",
        subcommands: [
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
            GetVar.self,
            SetVar.self,
            AddClipping.self,
        ]
    )
}

// MARK: - session list

extension Session {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all sessions."
        )

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.listSessionsRequest = ITMListSessionsRequest()

            let response = try client.send(request)
            guard response.submessageOneOfCase == .listSessionsResponse,
                  let listResp = response.listSessionsResponse else {
                throw IT2Error.apiError("No list sessions response")
            }

            guard let windows = listResp.windowsArray as? [ITMListSessionsResponse_Window] else { return }

            var sessionsData: [[String: Any]] = []
            for window in windows {
                guard let tabs = window.tabsArray as? [ITMListSessionsResponse_Tab] else { continue }
                for tab in tabs {
                    let isTmux = tab.tmuxWindowId != nil && tab.tmuxWindowId != "-1"
                    walkSplitTree(tab.root) { s in
                        let cols = s.hasGridSize ? Int(s.gridSize.width) : 0
                        let rows = s.hasGridSize ? Int(s.gridSize.height) : 0
                        let id = s.uniqueIdentifier ?? ""
                        let vars = (try? fetchSessionVars(client: client, sessionId: id))
                            ?? (name: "", tty: "")
                        sessionsData.append([
                            "id": id,
                            "name": vars.name,
                            "title": s.title ?? "",
                            "tty": vars.tty,
                            "cols": cols,
                            "rows": rows,
                            "window_id": window.windowId ?? "",
                            "tab_id": tab.tabId ?? "",
                            "is_tmux": isTmux,
                        ])
                    }
                }
            }

            if json {
                if let data = try? JSONSerialization.data(withJSONObject: sessionsData, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                for s in sessionsData {
                    let id = s["id"] as? String ?? ""
                    let name = s["name"] as? String ?? ""
                    let title = s["title"] as? String ?? ""
                    let size = "\(s["cols"] ?? 0)x\(s["rows"] ?? 0)"
                    let tty = s["tty"] as? String ?? ""
                    print("\(id)\t\(name)\t\(title)\t\(size)\t\(tty)")
                }
            }
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
                if vr.valuesArray_Count > 0, let n = vr.valuesArray.object(at: 0) as? String, n != "null" {
                    name = n.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                if vr.valuesArray_Count > 1, let t = vr.valuesArray.object(at: 1) as? String, t != "null" {
                    tty = t.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            return (name, tty)
        }
    }
}

// MARK: - session split

extension Session {
    struct Split: ParsableCommand {
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

        func run() throws {
            let client = try APIClient.connect()
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
                    throw IT2Error.apiError("Cannot split: pane may be too small")
                } else {
                    throw IT2Error.apiError("Split failed with status \(splitResp.status.rawValue)")
                }
            }

            guard splitResp.sessionIdArray_Count > 0,
                  let newSessionId = splitResp.sessionIdArray.object(at: 0) as? String else {
                throw IT2Error.apiError("Split succeeded but no session ID returned")
            }

            print("Created new pane: \(newSessionId)")
        }
    }
}

// MARK: - session run

extension Session {
    struct Run: ParsableCommand {
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

        func run() throws {
            let client = try APIClient.connect()
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
                        for tab in tabs { count += collectSessionIds(from: tab.root).count }
                    }
                }
                if count > 1 {
                    print("Executed command in \(count) sessions")
                }
            }
        }
    }
}

// MARK: - session send

extension Session {
    struct Send: ParsableCommand {
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

        func run() throws {
            let client = try APIClient.connect()
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
                        for tab in tabs { count += collectSessionIds(from: tab.root).count }
                    }
                }
                if count > 1 {
                    print("Sent text to \(count) sessions")
                }
            }
        }
    }
}

// MARK: - session close

extension Session {
    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close",
            abstract: "Close session."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Flag(name: .shortAndLong, help: "Force close without confirmation.")
        var force = false

        func run() throws {
            let sessionId = APIClient.normalizeSessionId(session ?? "active")

            if !force {
                confirmAction("Close session \(sessionId)?")
            }

            let client = try APIClient.connect()
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

            print("Session closed")
        }
    }
}

// MARK: - session set-name

extension Session {
    struct SetName: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-name",
            abstract: "Set session name."
        )

        @Argument(help: "Name to set.")
        var name: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
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

            print("Session name set to: \(name)")
        }
    }
}

// MARK: - session set-color

extension Session {
    struct SetColor: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-color",
            abstract: "Set session tab color."
        )

        @Argument(help: "Color as hex string (e.g. #FF0000).")
        var color: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let colorJSON = try colorToJSON(color)

            let client = try APIClient.connect()
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

            print("Tab color set to \(color)")
        }

    }
}

// MARK: - session restart

extension Session {
    struct Restart: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "restart",
            abstract: "Restart session."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
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
            print("Session restarted")
        }
    }
}

// MARK: - session focus

extension Session {
    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "focus",
            abstract: "Focus a specific session."
        )

        @Argument(help: "Session ID to focus.")
        var sessionId: String

        func run() throws {
            let client = try APIClient.connect()
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
            print("Focused session: \(sessionId)")
        }
    }
}

// MARK: - session read

extension Session {
    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Display screen contents."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Option(name: [.customShort("n"), .long], help: "Number of lines to read.")
        var lines: Int?

        func run() throws {
            let client = try APIClient.connect()
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
            if let n = lines, n < contents.count {
                outputLines = Array(contents.suffix(n))
            } else {
                outputLines = contents
            }
            for line in outputLines {
                print(line.text ?? "")
            }
        }
    }
}

// MARK: - session clear

extension Session {
    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear screen."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
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
    struct Capture: ParsableCommand {
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

        func run() throws {
            let client = try APIClient.connect()
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
            print("Screen captured to: \(output)")
        }
    }
}

// MARK: - session copy

extension Session {
    struct Copy: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy",
            abstract: "Copy selection to clipboard."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
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
                print("No selection")
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
                print("No text selected")
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
            print("Selection copied to clipboard")
        }
    }
}

// MARK: - session get-var

extension Session {
    struct GetVar: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-var",
            abstract: "Get session variable value."
        )

        @Argument(help: "Variable name.")
        var variable: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let varReq = ITMVariableRequest()
            varReq.sessionId = try client.resolveSessionId(session)
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
                print(value)
            } else {
                print("Variable '\(variable)' not set")
            }
        }
    }
}

// MARK: - session add-clipping

extension Session {
    struct AddClipping: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add-clipping",
            abstract: "Add a clipping to a session (e.g., a code review comment)."
        )

        @Argument(help: "Clipping type (e.g., “Code Review Comment”).")
        var type: String

        @Argument(help: "Clipping title.")
        var title: String

        @Argument(help: "Clipping detail.")
        var detail: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)

            let invoke = ITMInvokeFunctionRequest()
            let sessionContext = ITMInvokeFunctionRequest_Session()
            sessionContext.sessionId = sessionId
            invoke.session = sessionContext
            invoke.invocation = try "iterm2.add_clipping(type: \(jsonString(type)), title: \(jsonString(title)), detail: \(jsonString(detail)))"

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
                throw IT2Error.apiError("Add clipping failed: \(reason)")
            }
        }

        private func jsonString(_ s: String) throws -> String {
            let data = try JSONEncoder().encode(s)
            guard let str = String(data: data, encoding: .utf8) else {
                throw IT2Error.apiError("Failed to JSON-encode string")
            }
            return str
        }
    }
}

// MARK: - session set-var

extension Session {
    struct SetVar: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-var",
            abstract: "Set session variable value."
        )

        @Argument(help: "Variable name.")
        var variable: String

        @Argument(help: "Value to set.")
        var value: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let varReq = ITMVariableRequest()
            varReq.sessionId = try client.resolveSessionId(session)

            let setEntry = ITMVariableRequest_Set()
            setEntry.name = variable
            setEntry.value = value
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
            print("Set \(variable) = \(value)")
        }
    }
}

// MARK: - session set-status

extension Session {
    struct SetStatus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-status",
            abstract: "Set session status indicator."
        )

        @Option(name: .shortAndLong, help: "Target session ID.")
        var session: String

        @Option(name: .long, help: "Status text (idle, working, or waiting).")
        var status: String?

        @Option(name: .long, help: "Dot indicator color as #rrggbb.")
        var dotColor: String?

        @Option(name: .long, help: "Text color as #rrggbb.")
        var textColor: String?

        @Option(name: .long, help: "Optional detail text shown alongside the status.")
        var detail: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let invoke = ITMInvokeFunctionRequest()
            let sessionContext = ITMInvokeFunctionRequest_Session()
            sessionContext.sessionId = session
            invoke.session = sessionContext

            var args: [String] = []
            if let status = status {
                args.append("status: \(jsonString(status))")
            }
            if let textColor = textColor {
                args.append("text_color: \(jsonString(textColor))")
            }
            if let dotColor = dotColor {
                args.append("dot_color: \(jsonString(dotColor))")
            }
            if let detail = detail {
                args.append("detail: \(jsonString(detail))")
            }

            invoke.invocation = "iterm2.set_status(\(args.joined(separator: ", ")))"

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
                throw IT2Error.apiError("Set status failed: \(reason)")
            }

            print("Session status updated.")
        }
    }
}
