import ArgumentParser
import Foundation
import ProtobufRuntime

private func installSigintHandler() {
    signal(SIGINT) { _ in
        Foundation.exit(0)
    }
}

struct Monitor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monitor",
        abstract: "Monitor iTerm2 events.",
        subcommands: [
            Output.self,
            Keystroke.self,
            Variable.self,
            Prompt.self,
            Activity.self,
        ]
    )
}

// MARK: - monitor output

extension Monitor {
    struct Output: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "output",
            abstract: "Monitor session output."
        )

        @Flag(name: .shortAndLong, help: "Follow output continuously.")
        var follow = false

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        @Option(name: .shortAndLong, help: "Filter output by regex pattern.")
        var pattern: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)
            let regex: NSRegularExpression?
            if let pattern = pattern {
                do {
                    regex = try NSRegularExpression(pattern: pattern)
                } catch {
                    throw IT2Error.invalidArgument("Invalid regex pattern: \(error.localizedDescription)")
                }
            } else {
                regex = nil
            }

            if follow {
                // Subscribe to screen updates.
                let notifReq = ITMNotificationRequest()
                notifReq.session = sessionId
                notifReq.subscribe = true
                notifReq.notificationType = .notifyOnScreenUpdate

                let subMsg = ITMClientOriginatedMessage()
                subMsg.id_p = client.nextId()
                subMsg.notificationRequest = notifReq

                let subResp = try client.send(subMsg)
                guard subResp.submessageOneOfCase == .notificationResponse,
                      let notifResp = subResp.notificationResponse,
                      notifResp.status == ITMNotificationResponse_Status.ok else {
                    throw IT2Error.apiError("Failed to subscribe to screen updates")
                }

                FileHandle.standardError.write(Data("Monitoring output from session \(sessionId)...\nPress Ctrl+C to stop\n".utf8))
                installSigintHandler()

                // Loop receiving notifications.
                while true {
                    let data = try client.receiveRaw()
                    let response = try ITMServerOriginatedMessage.parse(from: data)

                    if response.submessageOneOfCase == .notification,
                       let notif = response.notification,
                       notif.hasScreenUpdateNotification {
                        // Fetch current screen contents.
                        let bufReq = ITMGetBufferRequest()
                        bufReq.session = sessionId
                        let lineRange = ITMLineRange()
                        lineRange.screenContentsOnly = true
                        bufReq.lineRange = lineRange

                        let bufMsg = ITMClientOriginatedMessage()
                        bufMsg.id_p = client.nextId()
                        bufMsg.getBufferRequest = bufReq

                        let bufResp = try client.send(bufMsg)
                        if bufResp.submessageOneOfCase == .getBufferResponse,
                           let buf = bufResp.getBufferResponse,
                           buf.status == ITMGetBufferResponse_Status.ok,
                           let contents = buf.contentsArray as? [ITMLineContents] {
                            let lines = contents.map { $0.text ?? "" }
                            if let regex = regex {
                                for line in lines {
                                    let range = NSRange(line.startIndex..., in: line)
                                    if regex.firstMatch(in: line, range: range) != nil {
                                        print(line)
                                    }
                                }
                            } else {
                                let text = lines.joined(separator: "\n")
                                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    print(text)
                                }
                            }
                        }
                    }
                }
            } else {
                // Just get current screen contents.
                let bufReq = ITMGetBufferRequest()
                bufReq.session = sessionId
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
                    if bufResp.status == ITMGetBufferResponse_Status.sessionNotFound {
                        throw IT2Error.targetNotFound("Session not found")
                    }
                    throw IT2Error.apiError("Get buffer failed with status \(bufResp.status.rawValue)")
                }
                guard let contents = bufResp.contentsArray as? [ITMLineContents] else {
                    return
                }

                let lines = contents.map { $0.text ?? "" }
                if let regex = regex {
                    for line in lines {
                        let range = NSRange(line.startIndex..., in: line)
                        if regex.firstMatch(in: line, range: range) != nil {
                            print(line)
                        }
                    }
                } else {
                    print(lines.joined(separator: "\n"))
                }
            }
        }
    }
}

// MARK: - monitor keystroke

extension Monitor {
    struct Keystroke: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "keystroke",
            abstract: "Monitor keystrokes."
        )

        @Option(name: .shortAndLong, help: "Filter keystrokes by regex pattern.")
        var pattern: String?

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)
            let regex: NSRegularExpression?
            if let pattern = pattern {
                do {
                    regex = try NSRegularExpression(pattern: pattern)
                } catch {
                    throw IT2Error.invalidArgument("Invalid regex pattern: \(error.localizedDescription)")
                }
            } else {
                regex = nil
            }

            let notifReq = ITMNotificationRequest()
            notifReq.session = sessionId
            notifReq.subscribe = true
            notifReq.notificationType = .notifyOnKeystroke
            notifReq.keystrokeMonitorRequest = ITMKeystrokeMonitorRequest()

            let subMsg = ITMClientOriginatedMessage()
            subMsg.id_p = client.nextId()
            subMsg.notificationRequest = notifReq

            let subResp = try client.send(subMsg)
            guard subResp.submessageOneOfCase == .notificationResponse,
                  let notifResp = subResp.notificationResponse,
                  notifResp.status == ITMNotificationResponse_Status.ok else {
                throw IT2Error.apiError("Failed to subscribe to keystrokes")
            }

            FileHandle.standardError.write(Data("Monitoring keystrokes in session \(sessionId)...\nPress Ctrl+C to stop\n".utf8))
            installSigintHandler()

            while true {
                let data = try client.receiveRaw()
                let response = try ITMServerOriginatedMessage.parse(from: data)

                if response.submessageOneOfCase == .notification,
                   let notif = response.notification,
                   notif.hasKeystrokeNotification,
                   let keystroke = notif.keystrokeNotification {
                    let chars = keystroke.characters ?? ""
                    if let regex = regex {
                        let range = NSRange(chars.startIndex..., in: chars)
                        if regex.firstMatch(in: chars, range: range) != nil {
                            print("Keystroke: \(chars)")
                        }
                    } else {
                        print("Keystroke: \(chars)")
                    }
                }
            }
        }
    }
}

// MARK: - monitor variable

extension Monitor {
    struct Variable: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "variable",
            abstract: "Monitor variable changes."
        )

        @Argument(help: "Variable name to monitor.")
        var variableName: String

        @Option(name: .shortAndLong, help: "Target session ID.")
        var session: String?

        @Flag(name: .long, help: "Monitor app-level variable.")
        var appLevel = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let notifReq = ITMNotificationRequest()
            notifReq.subscribe = true
            notifReq.notificationType = .notifyOnVariableChange

            let varMon = ITMVariableMonitorRequest()
            varMon.name = variableName
            if appLevel {
                varMon.scope = .app
            } else {
                varMon.scope = .session
                varMon.identifier = try client.resolveSessionId(session)
            }
            notifReq.variableMonitorRequest = varMon

            let subMsg = ITMClientOriginatedMessage()
            subMsg.id_p = client.nextId()
            subMsg.notificationRequest = notifReq

            let subResp = try client.send(subMsg)
            guard subResp.submessageOneOfCase == .notificationResponse,
                  let notifResp = subResp.notificationResponse,
                  notifResp.status == ITMNotificationResponse_Status.ok else {
                throw IT2Error.apiError("Failed to subscribe to variable changes")
            }

            let scopeLabel = appLevel ? "app" : "session"
            FileHandle.standardError.write(Data("Monitoring \(scopeLabel) variable '\(variableName)'...\n".utf8))

            // Display initial value.
            let varReq = ITMVariableRequest()
            if appLevel {
                varReq.app = true
            } else {
                varReq.sessionId = varMon.identifier
            }
            varReq.getArray.add(variableName)
            let initMsg = ITMClientOriginatedMessage()
            initMsg.variableRequest = varReq
            let initResp = try client.send(initMsg)
            if initResp.submessageOneOfCase == .variableResponse,
               let vr = initResp.variableResponse,
               vr.valuesArray_Count > 0,
               let val = vr.valuesArray.object(at: 0) as? String {
                print("Current value: \(val)")
            }

            FileHandle.standardError.write(Data("Press Ctrl+C to stop\n".utf8))
            installSigintHandler()

            while true {
                let data = try client.receiveRaw()
                let response = try ITMServerOriginatedMessage.parse(from: data)

                if response.submessageOneOfCase == .notification,
                   let notif = response.notification,
                   notif.hasVariableChangedNotification,
                   let varNotif = notif.variableChangedNotification {
                    print("Changed to: \(varNotif.jsonNewValue ?? "null")")
                }
            }
        }
    }
}

// MARK: - monitor prompt

extension Monitor {
    struct Prompt: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prompt",
            abstract: "Monitor shell prompts (requires shell integration)."
        )

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let sessionId = try client.resolveSessionId(session)

            // Check if shell integration is installed (before subscribing).
            let varReq = ITMVariableRequest()
            varReq.sessionId = sessionId
            varReq.getArray.add("user.shell_integration_installed")
            let varMsg = ITMClientOriginatedMessage()
            varMsg.variableRequest = varReq
            let varResp = try client.send(varMsg)
            var shellIntegrationInstalled = false
            if varResp.submessageOneOfCase == .variableResponse,
               let vr = varResp.variableResponse,
               vr.valuesArray_Count > 0,
               let val = vr.valuesArray.object(at: 0) as? String {
                shellIntegrationInstalled = (val != "null" && val != "false" && val != "0" && !val.isEmpty)
            }
            if !shellIntegrationInstalled {
                FileHandle.standardError.write(Data("Warning: Shell integration may not be installed.\nInstall it from: iTerm2 > Install Shell Integration\n".utf8))
            }

            let notifReq = ITMNotificationRequest()
            notifReq.session = sessionId
            notifReq.subscribe = true
            notifReq.notificationType = .notifyOnPrompt

            let promptMon = ITMPromptMonitorRequest()
            promptMon.modesArray.addValue(ITMPromptMonitorMode.prompt.rawValue)
            promptMon.modesArray.addValue(ITMPromptMonitorMode.commandStart.rawValue)
            promptMon.modesArray.addValue(ITMPromptMonitorMode.commandEnd.rawValue)
            notifReq.promptMonitorRequest = promptMon

            let subMsg = ITMClientOriginatedMessage()
            subMsg.notificationRequest = notifReq

            let subResp = try client.send(subMsg)
            guard subResp.submessageOneOfCase == .notificationResponse,
                  let notifResp = subResp.notificationResponse,
                  notifResp.status == ITMNotificationResponse_Status.ok else {
                throw IT2Error.apiError("Failed to subscribe to prompt notifications")
            }

            FileHandle.standardError.write(Data("Monitoring prompts in session \(sessionId)...\nPress Ctrl+C to stop\n".utf8))
            installSigintHandler()

            while true {
                let data = try client.receiveRaw()
                let response = try ITMServerOriginatedMessage.parse(from: data)

                if response.submessageOneOfCase == .notification,
                   let notif = response.notification,
                   notif.hasPromptNotification,
                   let promptNotif = notif.promptNotification {
                    switch promptNotif.eventOneOfCase {
                    case .prompt:
                        print("New prompt detected")
                    case .commandStart:
                        if let cmd = promptNotif.commandStart {
                            print("Command started: \(cmd.command ?? "")")
                        }
                    case .commandEnd:
                        if let end = promptNotif.commandEnd {
                            print("Command finished (exit status: \(end.status))")
                        }
                    default:
                        break
                    }
                }
            }
        }
    }
}

// MARK: - monitor activity

extension Monitor {
    struct Activity: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "activity",
            abstract: "Monitor session activity."
        )

        @Flag(name: .shortAndLong, help: "Monitor all sessions.")
        var all = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            if all {
                FileHandle.standardError.write(Data("Monitoring activity in all sessions...\n".utf8))
            } else {
                FileHandle.standardError.write(Data("Monitoring activity in current session...\n".utf8))
            }
            FileHandle.standardError.write(Data("Press Ctrl+C to stop\n".utf8))
            installSigintHandler()

            let currentSessionId: String? = all ? nil : (try? client.resolveSessionId(nil))
            var sessionActivity: [String: Bool] = [:]

            // Poll session.isActive every 0.5s, matching Python behavior.
            while true {
                let windows = try fetchWindows(client: client)

                var allSessionIds: [String] = []
                for win in windows {
                    if let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                        for tab in tabs {
                            allSessionIds.append(contentsOf: collectSessionIds(from: tab.root))
                        }
                    }
                }

                for sid in allSessionIds {
                    if !all && sid != currentSessionId { continue }

                    let varReq = ITMVariableRequest()
                    varReq.sessionId = sid
                    varReq.getArray.add("session.isActive")
                    let varMsg = ITMClientOriginatedMessage()
                    varMsg.variableRequest = varReq

                    let varResp = try client.send(varMsg)
                    guard varResp.submessageOneOfCase == .variableResponse,
                          let vr = varResp.variableResponse,
                          vr.status == ITMVariableResponse_Status.ok,
                          vr.valuesArray_Count > 0,
                          let valueStr = vr.valuesArray.object(at: 0) as? String else {
                        continue
                    }

                    let isActive = valueStr == "true" || valueStr == "1"
                    let prevActive = sessionActivity[sid]

                    if prevActive == nil {
                        sessionActivity[sid] = isActive
                    } else if prevActive != isActive {
                        sessionActivity[sid] = isActive

                        let nameReq = ITMVariableRequest()
                        nameReq.sessionId = sid
                        nameReq.getArray.add("session.name")
                        let nameMsg = ITMClientOriginatedMessage()
                        nameMsg.variableRequest = nameReq

                        var displayName = sid
                        if let nameResp = try? client.send(nameMsg),
                           nameResp.submessageOneOfCase == .variableResponse,
                           let nr = nameResp.variableResponse,
                           nr.valuesArray_Count > 0,
                           let name = nr.valuesArray.object(at: 0) as? String,
                           name != "null" {
                            displayName = trimJSONQuotes(name)
                        }

                        if isActive {
                            print("Session active: \(displayName)")
                        } else {
                            print("Session idle: \(displayName)")
                        }
                    }
                }

                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}
