import ArgumentParser
import Foundation
import ProtobufRuntime

struct Tab: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tab",
        abstract: "Manage iTerm2 tabs.",
        subcommands: [
            New.self,
            List.self,
            Close.self,
            Select.self,
            Move.self,
            Next.self,
            Prev.self,
            Goto.self,
        ]
    )
}

// MARK: - tab new

extension Tab {
    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "new",
            abstract: "Create new tab."
        )

        @Option(name: .shortAndLong, help: "Profile to use.")
        var profile: String?

        @Option(name: .shortAndLong, help: "Window ID (default: current).")
        var window: String?

        @Option(name: .shortAndLong, help: "Command to run.")
        var command: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let createTab = ITMCreateTabRequest()
            if let profile = profile {
                createTab.profileName = profile
            }
            if let window = window {
                createTab.windowId = window
            } else {
                createTab.windowId = try resolveCurrentWindowId(client: client)
            }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.createTabRequest = createTab

            let response = try client.send(request)
            guard response.submessageOneOfCase == .createTabResponse,
                  let tabResp = response.createTabResponse else {
                throw IT2Error.apiError("No create tab response")
            }
            guard tabResp.status == ITMCreateTabResponse_Status.ok else {
                throw IT2Error.apiError("Failed to create tab: status \(tabResp.status.rawValue)")
            }

            print("Created new tab: \(tabResp.tabId)")

            if let command = command, let sessionId = tabResp.sessionId {
                let sendText = ITMSendTextRequest()
                sendText.session = sessionId
                sendText.text = command + "\r"

                let cmdReq = ITMClientOriginatedMessage()
                cmdReq.sendTextRequest = sendText
                let _ = try client.send(cmdReq)
            }
        }
    }
}

// MARK: - tab list

extension Tab {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all tabs."
        )

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        @Option(name: .shortAndLong, help: "Window ID to list tabs from.")
        var window: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            // Get the selected tab per window from focus info.
            let focusMsg = ITMClientOriginatedMessage()
            focusMsg.id_p = client.nextId()
            focusMsg.focusRequest = ITMFocusRequest()
            let focusResp = try client.send(focusMsg)
            var selectedTabs = Set<String>()
            if focusResp.submessageOneOfCase == .focusResponse,
               let focus = focusResp.focusResponse,
               let notifications = focus.notificationsArray as? [ITMFocusChangedNotification] {
                for n in notifications {
                    if n.eventOneOfCase == .selectedTab {
                        selectedTabs.insert(n.selectedTab ?? "")
                    }
                }
            }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.listSessionsRequest = ITMListSessionsRequest()

            let response = try client.send(request)
            guard response.submessageOneOfCase == .listSessionsResponse,
                  let listResp = response.listSessionsResponse else {
                throw IT2Error.apiError("No list sessions response")
            }

            var tabsData: [[String: Any]] = []
            guard let windows = listResp.windowsArray as? [ITMListSessionsResponse_Window] else { return }
            for win in windows {
                if let filterWindow = window, win.windowId != filterWindow { continue }
                guard let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] else { continue }
                for (idx, tab) in tabs.enumerated() {
                    let sessionCount = countSessions(in: tab.root)
                    let isActive = selectedTabs.contains(tab.tabId ?? "")
                    let entry: [String: Any] = [
                        "id": tab.tabId ?? "",
                        "window_id": win.windowId ?? "",
                        "index": idx,
                        "sessions": sessionCount,
                        "is_active": isActive,
                    ]
                    tabsData.append(entry)
                }
            }

            if json {
                if let data = try? JSONSerialization.data(withJSONObject: tabsData, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                for t in tabsData {
                    let active = (t["is_active"] as? Bool == true) ? "\t✓" : ""
                    print("\(t["id"] ?? "")\twindow=\(t["window_id"] ?? "")\tindex=\(t["index"] ?? "")\tsessions=\(t["sessions"] ?? "")\(active)")
                }
            }
        }

        private func countSessions(in node: ITMSplitTreeNode?) -> Int {
            return collectSessionIds(from: node).count
        }
    }
}

// MARK: - tab close

extension Tab {
    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close",
            abstract: "Close tab."
        )

        @Argument(help: "Tab ID.")
        var tabId: String?

        @Flag(name: .shortAndLong, help: "Force close without confirmation.")
        var force = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let id = try tabId ?? resolveCurrentTabId(client: client)

            if !force {
                confirmAction("Close tab \(id)?")
            }

            let closeReq = ITMCloseRequest()
            let closeTabs = ITMCloseRequest_CloseTabs()
            closeTabs.tabIdsArray.add(id)
            closeReq.tabs = closeTabs

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.closeRequest = closeReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .closeResponse else {
                throw IT2Error.apiError("No close response")
            }
            print("Tab closed")
        }
    }
}

// MARK: - tab select

extension Tab {
    struct Select: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "select",
            abstract: "Select tab by ID or index."
        )

        @Argument(help: "Tab ID or numeric index.")
        var tabIdOrIndex: String

        @Option(name: .shortAndLong, help: "Window ID (for index-based selection).")
        var window: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let resolvedTabId: String
            let isIndex: Bool
            if let index = Int(tabIdOrIndex) {
                // Index-based selection.
                isIndex = true
                let windowId = try window ?? resolveCurrentWindowId(client: client)
                let tabs = try getTabsForWindow(client: client, windowId: windowId)
                guard index >= 0 && index < tabs.count else {
                    throw IT2Error.invalidArgument("Tab index \(index) out of range")
                }
                resolvedTabId = tabs[index].tabId ?? ""
            } else {
                isIndex = false
                resolvedTabId = tabIdOrIndex
            }

            let activate = ITMActivateRequest()
            activate.tabId = resolvedTabId
            activate.selectTab = true

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.activateRequest = activate

            let response = try client.send(request)
            guard response.submessageOneOfCase == .activateResponse,
                  let activateResp = response.activateResponse else {
                throw IT2Error.apiError("No activate response")
            }
            guard activateResp.status == ITMActivateResponse_Status.ok else {
                throw IT2Error.targetNotFound("Tab '\(tabIdOrIndex)' not found")
            }
            if isIndex {
                print("Selected tab at index \(tabIdOrIndex)")
            } else {
                print("Selected tab: \(tabIdOrIndex)")
            }
        }
    }
}

// MARK: - tab move

extension Tab {
    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move tab to its own new window."
        )

        @Argument(help: "Tab ID (default: current).")
        var tabId: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let id = try tabId ?? resolveCurrentTabId(client: client)

            let invoke = ITMInvokeFunctionRequest()
            let tab = ITMInvokeFunctionRequest_Tab()
            tab.tabId = id
            invoke.tab = tab
            invoke.invocation = "iterm2.move_tab_to_window()"

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
                throw IT2Error.apiError("Move tab failed: \(reason)")
            }

            print("Moved tab to new window")
        }
    }
}

// MARK: - tab next

extension Tab {
    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "next",
            abstract: "Switch to next tab."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let (tabs, currentIdx, _) = try getTabsAndCurrentIndex(client: client)
            let nextIdx = (currentIdx + 1) % tabs.count
            let nextTab = tabs[nextIdx]

            let activate = ITMActivateRequest()
            activate.tabId = nextTab.tabId
            activate.selectTab = true

            let request = ITMClientOriginatedMessage()
            request.activateRequest = activate

            let response = try client.send(request)
            guard response.submessageOneOfCase == .activateResponse,
                  let activateResp = response.activateResponse,
                  activateResp.status == ITMActivateResponse_Status.ok else {
                throw IT2Error.apiError("Failed to switch tab")
            }
            print("Switched to tab \(nextIdx)")
        }
    }
}

// MARK: - tab prev

extension Tab {
    struct Prev: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prev",
            abstract: "Switch to previous tab."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let (tabs, currentIdx, _) = try getTabsAndCurrentIndex(client: client)
            let prevIdx = (currentIdx - 1 + tabs.count) % tabs.count
            let prevTab = tabs[prevIdx]

            let activate = ITMActivateRequest()
            activate.tabId = prevTab.tabId
            activate.selectTab = true

            let request = ITMClientOriginatedMessage()
            request.activateRequest = activate

            let response = try client.send(request)
            guard response.submessageOneOfCase == .activateResponse,
                  let activateResp = response.activateResponse,
                  activateResp.status == ITMActivateResponse_Status.ok else {
                throw IT2Error.apiError("Failed to switch tab")
            }
            print("Switched to tab \(prevIdx)")
        }
    }
}

// MARK: - tab goto

extension Tab {
    struct Goto: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "goto",
            abstract: "Go to tab by index."
        )

        @Argument(help: "Tab index (0-based).")
        var index: Int

        @Option(name: .shortAndLong, help: "Window ID (default: current).")
        var window: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let windowId = try window ?? resolveCurrentWindowId(client: client)
            let tabs = try getTabsForWindow(client: client, windowId: windowId)

            guard index >= 0 && index < tabs.count else {
                throw IT2Error.invalidArgument("Tab index \(index) out of range (0-\(tabs.count - 1))")
            }

            let tab = tabs[index]
            let activate = ITMActivateRequest()
            activate.tabId = tab.tabId
            activate.selectTab = true

            let request = ITMClientOriginatedMessage()
            request.activateRequest = activate

            let response = try client.send(request)
            guard response.submessageOneOfCase == .activateResponse,
                  let activateResp = response.activateResponse,
                  activateResp.status == ITMActivateResponse_Status.ok else {
                throw IT2Error.apiError("Failed to switch tab")
            }
            print("Switched to tab \(index)")
        }
    }
}

// MARK: - Helpers

func getTabsForWindow(client: APIClient, windowId: String) throws -> [ITMListSessionsResponse_Tab] {
    let windows = try fetchWindows(client: client)

    for win in windows {
        if win.windowId == windowId {
            return (win.tabsArray as? [ITMListSessionsResponse_Tab]) ?? []
        }
    }
    throw IT2Error.targetNotFound("Window '\(windowId)' not found")
}

func getTabsAndCurrentIndex(client: APIClient) throws -> ([ITMListSessionsResponse_Tab], Int, String) {
    let windowId = try resolveCurrentWindowId(client: client)
    let currentTabId = try resolveCurrentTabId(client: client)
    let tabs = try getTabsForWindow(client: client, windowId: windowId)

    guard let idx = tabs.firstIndex(where: { $0.tabId == currentTabId }) else {
        throw IT2Error.apiError("Current tab not found in window")
    }
    return (tabs, idx, windowId)
}

func resolveCurrentTabId(client: APIClient) throws -> String {
    let focus = try fetchFocusState(client: client)
    // The last selectedTabId corresponds to the key window.
    if let tabId = focus.selectedTabIds.last {
        return tabId
    }
    throw IT2Error.targetNotFound("No current tab")
}
