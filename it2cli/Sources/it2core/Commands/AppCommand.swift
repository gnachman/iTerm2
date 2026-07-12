import ArgumentParser
import Foundation
import ProtobufRuntime

struct App: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Control iTerm2 application.",
        subcommands: [
            Activate.self,
            Hide.self,
            Quit.self,
            Version.self,
            Theme.self,
            GetFocus.self,
            Broadcast.self,
        ]
    )
}

// MARK: - app activate

extension App {
    struct Activate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "activate",
            abstract: "Activate iTerm2 (bring to front)."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let activate = ITMActivateRequest()
            let app = ITMActivateRequest_App()
            activate.activateApp = app

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.activateRequest = activate

            let _ = try client.send(request)
            print("iTerm2 activated")
        }
    }
}

// MARK: - app hide

extension App {
    struct Hide: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hide",
            abstract: "Hide iTerm2."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let menuReq = ITMMenuItemRequest()
            menuReq.identifier = "Hide iTerm2"

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.menuItemRequest = menuReq

            let _ = try client.send(request)
            print("iTerm2 hidden")
        }
    }
}

// MARK: - app quit

extension App {
    struct Quit: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "quit",
            abstract: "Quit iTerm2."
        )

        @Flag(name: .shortAndLong, help: "Force quit without confirmation.")
        var force = false

        func run() throws {
            if !force {
                confirmAction("Quit iTerm2?")
            }

            let client = try APIClient.connect()
            defer { client.disconnect() }

            let menuReq = ITMMenuItemRequest()
            menuReq.identifier = "Quit iTerm2"

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.menuItemRequest = menuReq

            let _ = try client.send(request)
            print("iTerm2 quit command sent")
        }
    }
}

// MARK: - app version

extension App {
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Show iTerm2 version."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let prefReq = ITMPreferencesRequest()
            let getReq = ITMPreferencesRequest_Request()
            let getPref = ITMPreferencesRequest_Request_GetPreference()
            getPref.key = "iTerm Version"
            getReq.getPreferenceRequest = getPref
            prefReq.requestsArray.add(getReq)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.preferencesRequest = prefReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .preferencesResponse,
                  let prefResp = response.preferencesResponse,
                  let results = prefResp.resultsArray as? [ITMPreferencesResponse_Result],
                  let result = results.first else {
                throw IT2Error.apiError("No preferences response")
            }

            if result.resultOneOfCase == .getPreferenceResult,
               let getResult = result.getPreferenceResult {
                let version = getResult.jsonValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "unknown"
                print("iTerm2 version: \(version)")
            } else {
                print("iTerm2 version: unknown")
            }
        }
    }
}

// MARK: - app theme

extension App {
    struct Theme: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "theme",
            abstract: "Show or set iTerm2 theme."
        )

        @Argument(help: "Theme value (light, dark, light-hc, dark-hc, automatic, minimal). Omit to show current.")
        var value: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let themeNames = ["light", "dark", "light-hc", "dark-hc", "automatic", "minimal"]

            if let value = value {
                guard let themeInt = themeNames.firstIndex(of: value) else {
                    throw IT2Error.invalidArgument("Invalid theme: \(value). Options: \(themeNames.joined(separator: ", "))")
                }

                let prefReq = ITMPreferencesRequest()
                let setReq = ITMPreferencesRequest_Request()
                let setPref = ITMPreferencesRequest_Request_SetPreference()
                setPref.key = "TabStyleWithAutomaticOption"
                setPref.jsonValue = "\(themeInt)"
                setReq.setPreferenceRequest = setPref
                prefReq.requestsArray.add(setReq)

                let request = ITMClientOriginatedMessage()
                request.id_p = client.nextId()
                request.preferencesRequest = prefReq

                let _ = try client.send(request)
                print("Theme set to: \(value)")
            } else {
                // Query the current theme via focus/activate - theme isn't directly queryable
                // as a single preference easily, so just report the TabStyle value.
                // Use effectiveTheme app variable, matching Python's app.async_get_theme().
                let varReq = ITMVariableRequest()
                varReq.app = true
                varReq.getArray.add("effectiveTheme")

                let request = ITMClientOriginatedMessage()
                request.variableRequest = varReq

                let response = try client.send(request)
                guard response.submessageOneOfCase == .variableResponse,
                      let varResp = response.variableResponse,
                      varResp.status == ITMVariableResponse_Status.ok,
                      varResp.valuesArray_Count > 0,
                      let val = varResp.valuesArray.object(at: 0) as? String else {
                    throw IT2Error.apiError("Could not get theme")
                }

                let attributes = trimJSONQuotes(val)
                print("Current theme: \(attributes)")
            }
        }
    }
}

// MARK: - app get-focus

extension App {
    struct GetFocus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-focus",
            abstract: "Get information about the currently focused element."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let focusReq = ITMClientOriginatedMessage()
            focusReq.id_p = client.nextId()
            focusReq.focusRequest = ITMFocusRequest()

            let response = try client.send(focusReq)
            guard response.submessageOneOfCase == .focusResponse,
                  let focus = response.focusResponse,
                  let notifications = focus.notificationsArray as? [ITMFocusChangedNotification] else {
                throw IT2Error.apiError("No focus response")
            }

            // Find key window, its selected tab, and active session (matching Python output).
            var keyWindowId: String?
            var selectedTabs: [String] = []
            var sessions: [String] = []

            for notification in notifications {
                switch notification.eventOneOfCase {
                case .window:
                    if let w = notification.window,
                       w.windowStatus == .terminalWindowBecameKey {
                        keyWindowId = w.windowId
                    }
                case .selectedTab:
                    selectedTabs.append(notification.selectedTab ?? "")
                case .session:
                    sessions.append(notification.session ?? "")
                default:
                    break
                }
            }

            if let windowId = keyWindowId {
                print("Current window: \(windowId)")
            } else {
                print("No current window")
            }
            if let tabId = selectedTabs.last {
                print("Current tab: \(tabId)")
            } else {
                print("No current tab")
            }
            if let sessionId = sessions.last {
                print("Current session: \(sessionId)")

                // Fetch session name.
                let varReq = ITMVariableRequest()
                varReq.sessionId = sessionId
                varReq.getArray.add("session.name")
                let varMsg = ITMClientOriginatedMessage()
                varMsg.id_p = client.nextId()
                varMsg.variableRequest = varReq
                let varResp = try client.send(varMsg)
                if varResp.submessageOneOfCase == .variableResponse,
                   let vr = varResp.variableResponse,
                   vr.valuesArray_Count > 0,
                   let name = vr.valuesArray.object(at: 0) as? String,
                   name != "null" {
                    print("Session name: \(name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))")
                }
            } else {
                print("No current session")
            }
        }
    }
}

// MARK: - app broadcast

extension App {
    struct Broadcast: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "broadcast",
            abstract: "Control input broadcasting.",
            subcommands: [
                On.self,
                Off.self,
                Add.self,
            ]
        )
    }
}

extension App.Broadcast {
    struct On: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "on",
            abstract: "Enable broadcasting for current tab."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            // Find the current session, then find which tab it belongs to,
            // and collect all sessions in that tab.
            let currentSessionId = try client.resolveSessionId(nil)

            let listMsg = ITMClientOriginatedMessage()
            listMsg.id_p = client.nextId()
            listMsg.listSessionsRequest = ITMListSessionsRequest()

            let listResp = try client.send(listMsg)
            guard listResp.submessageOneOfCase == .listSessionsResponse,
                  let sessions = listResp.listSessionsResponse else {
                throw IT2Error.apiError("Could not list sessions")
            }

            var sessionIds: [String] = []
            if let windows = sessions.windowsArray as? [ITMListSessionsResponse_Window] {
                for win in windows {
                    if let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                        for tab in tabs {
                            let tabSessionIds = collectSessionIds(from: tab.root)
                            if tabSessionIds.contains(currentSessionId) {
                                sessionIds = tabSessionIds
                                break
                            }
                        }
                    }
                    if !sessionIds.isEmpty { break }
                }
            }

            let domain = ITMBroadcastDomain()
            for id in sessionIds {
                domain.sessionIdsArray.add(id)
            }

            let setReq = ITMSetBroadcastDomainsRequest()
            setReq.broadcastDomainsArray.add(domain)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.setBroadcastDomainsRequest = setReq

            let response = try client.send(request)
            try checkBroadcastResponse(response)
            print("Broadcasting enabled for current tab")
        }

    }

    struct Off: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "off",
            abstract: "Disable broadcasting."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let setReq = ITMSetBroadcastDomainsRequest()
            // Empty array = disable all broadcasting.

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.setBroadcastDomainsRequest = setReq

            let response = try client.send(request)
            try checkBroadcastResponse(response)
            print("Broadcasting disabled")
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Create broadcast group with specified sessions."
        )

        @Argument(parsing: .remaining, help: "Session IDs to broadcast to.")
        var sessionIds: [String]

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            // Pre-validate: check all sessions exist.
            let windows = try fetchWindows(client: client)
            var knownIds = Swift.Set<String>()
            for win in windows {
                if let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                    for tab in tabs {
                        for id in collectSessionIds(from: tab.root) {
                            knownIds.insert(id)
                        }
                    }
                }
            }
            for id in sessionIds {
                let normalized = APIClient.normalizeSessionId(id)
                if !knownIds.contains(normalized) {
                    throw IT2Error.targetNotFound("Session '\(id)' not found")
                }
            }

            let domain = ITMBroadcastDomain()
            for id in sessionIds {
                domain.sessionIdsArray.add(APIClient.normalizeSessionId(id))
            }

            let setReq = ITMSetBroadcastDomainsRequest()
            setReq.broadcastDomainsArray.add(domain)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.setBroadcastDomainsRequest = setReq

            let response = try client.send(request)
            try checkBroadcastResponse(response)
            print("Created broadcast group with \(sessionIds.count) sessions")
        }
    }
}

// MARK: - Broadcast Helpers

func checkBroadcastResponse(_ response: ITMServerOriginatedMessage) throws {
    guard response.submessageOneOfCase == .setBroadcastDomainsResponse,
          let broadcastResp = response.setBroadcastDomainsResponse else {
        throw IT2Error.apiError("No broadcast domains response")
    }
    switch broadcastResp.status {
    case ITMSetBroadcastDomainsResponse_Status.ok:
        return
    case ITMSetBroadcastDomainsResponse_Status.sessionNotFound:
        throw IT2Error.targetNotFound("Session not found")
    case ITMSetBroadcastDomainsResponse_Status.broadcastDomainsNotDisjoint:
        throw IT2Error.apiError("Broadcast domains are not disjoint")
    case ITMSetBroadcastDomainsResponse_Status.sessionsNotInSameWindow:
        throw IT2Error.apiError("Sessions are not in the same window")
    default:
        throw IT2Error.apiError("Broadcast failed with status \(broadcastResp.status.rawValue)")
    }
}

