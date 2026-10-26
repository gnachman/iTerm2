import XCTest
import ProtobufRuntime
@testable import it2core

// The focus response lists the active session of every tab in every window, so
// `app get-focus` must pick the active session of the key window's selected
// tab rather than whichever session happens to be listed last.
final class GetFocusTests: XCTestCase {
    private func focusNote(window: String, status: ITMFocusChangedNotification_Window_WindowStatus) -> ITMFocusChangedNotification {
        let note = ITMFocusChangedNotification()
        let w = ITMFocusChangedNotification_Window()
        w.windowId = window
        w.windowStatus = status
        note.window = w
        return note
    }

    private func selectedTabNote(_ tab: String) -> ITMFocusChangedNotification {
        let note = ITMFocusChangedNotification()
        note.selectedTab = tab
        return note
    }

    private func sessionNote(_ session: String) -> ITMFocusChangedNotification {
        let note = ITMFocusChangedNotification()
        note.session = session
        return note
    }

    private func makeTab(_ tabId: String, sessions: [String], activeSessionId: String?) -> ITMListSessionsResponse_Tab {
        let root = ITMSplitTreeNode()
        for id in sessions {
            let summary = ITMSessionSummary()
            summary.uniqueIdentifier = id
            let link = ITMSplitTreeNode_SplitTreeLink()
            link.session = summary
            root.linksArray.add(link)
        }
        let tab = ITMListSessionsResponse_Tab()
        tab.tabId = tabId
        tab.root = root
        if let activeSessionId {
            tab.activeSessionId = activeSessionId
        }
        return tab
    }

    private func makeWindow(_ windowId: String, tabs: [ITMListSessionsResponse_Tab], selectedTabId: String?) -> ITMListSessionsResponse_Window {
        let window = ITMListSessionsResponse_Window()
        window.windowId = windowId
        for tab in tabs {
            window.tabsArray.add(tab)
        }
        if let selectedTabId {
            window.selectedTabId = selectedTabId
        }
        return window
    }

    private func reply(id: Int64, focus notes: [ITMFocusChangedNotification]) -> ITMServerOriginatedMessage {
        let focusResp = ITMFocusResponse()
        for note in notes {
            focusResp.notificationsArray.add(note)
        }
        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.focusResponse = focusResp
        return message
    }

    private func reply(id: Int64, windows: [ITMListSessionsResponse_Window]) -> ITMServerOriginatedMessage {
        let listResp = ITMListSessionsResponse()
        for window in windows {
            listResp.windowsArray.add(window)
        }
        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.listSessionsResponse = listResp
        return message
    }

    private func reply(id: Int64, name: String) -> ITMServerOriginatedMessage {
        let vr = ITMVariableResponse()
        vr.status = .ok
        vr.valuesArray.add(name)
        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.variableResponse = vr
        return message
    }

    private func run(_ responses: [ITMServerOriginatedMessage]) throws -> (OutputCapture, FakeChannel) {
        let channel = FakeChannel()
        channel.responses = responses
        let capture = OutputCapture()
        var command = try App.GetFocus.parse([])
        try command.run(capture.context(channel: channel))
        return (capture, channel)
    }

    // Two tabs in one window with the first selected: the focus response lists
    // both tabs' active sessions, the second tab's last.
    func testReportsSelectedTabsSessionNotLastTabs() throws {
        let notes = [focusNote(window: "win-1", status: .terminalWindowBecameKey),
                     selectedTabNote("tab-1"),
                     sessionNote("sess-1"),
                     sessionNote("sess-2")]
        let window = makeWindow("win-1",
                                tabs: [makeTab("tab-1", sessions: ["sess-1"], activeSessionId: "sess-1"),
                                       makeTab("tab-2", sessions: ["sess-2"], activeSessionId: "sess-2")],
                                selectedTabId: "tab-1")
        let (capture, channel) = try run([reply(id: 1, focus: notes),
                                          reply(id: 2, windows: [window]),
                                          reply(id: 3, name: #""first""#)])
        XCTAssertEqual(capture.out, ["Current window: win-1",
                                     "Current tab: tab-1",
                                     "Current session: sess-1",
                                     "Session name: first"])
        XCTAssertEqual(channel.sent.last?.variableRequest?.sessionId, "sess-1")
    }

    // An older iTerm2 that predates selected_tab_id and active_session_id in
    // ListSessionsResponse: fall back to the focus response, matching its
    // entries against the key window's tabs.
    func testFallsBackToFocusNotificationsForOlderServers() throws {
        let notes = [focusNote(window: "win-2", status: .terminalWindowBecameKey),
                     selectedTabNote("tab-1"),
                     sessionNote("sess-1"),
                     selectedTabNote("tab-2"),
                     sessionNote("sess-2"),
                     sessionNote("sess-3")]
        let windows = [makeWindow("win-1",
                                  tabs: [makeTab("tab-1", sessions: ["sess-1"], activeSessionId: nil)],
                                  selectedTabId: nil),
                       makeWindow("win-2",
                                  tabs: [makeTab("tab-2", sessions: ["sess-2", "sess-2b"], activeSessionId: nil),
                                         makeTab("tab-3", sessions: ["sess-3"], activeSessionId: nil)],
                                  selectedTabId: nil)]
        let (capture, _) = try run([reply(id: 1, focus: notes),
                                    reply(id: 2, windows: windows),
                                    reply(id: 3, name: #""second""#)])
        XCTAssertEqual(capture.out, ["Current window: win-2",
                                     "Current tab: tab-2",
                                     "Current session: sess-2",
                                     "Session name: second"])
    }

    // Commands that default to the current session resolve it the same way:
    // the key window's selected tab, not the last window's.
    func testResolveSessionIdUsesKeyWindowsSelectedTab() throws {
        let notes = [focusNote(window: "win-1", status: .terminalWindowBecameKey),
                     selectedTabNote("tab-1b"),
                     sessionNote("sess-1a"),
                     sessionNote("sess-1b"),
                     selectedTabNote("tab-2"),
                     sessionNote("sess-2")]
        let windows = [makeWindow("win-1",
                                  tabs: [makeTab("tab-1a", sessions: ["sess-1a"], activeSessionId: "sess-1a"),
                                         makeTab("tab-1b", sessions: ["sess-1b"], activeSessionId: "sess-1b")],
                                  selectedTabId: "tab-1b"),
                       makeWindow("win-2",
                                  tabs: [makeTab("tab-2", sessions: ["sess-2"], activeSessionId: "sess-2")],
                                  selectedTabId: "tab-2")]
        let channel = FakeChannel()
        channel.responses = [reply(id: 1, focus: notes), reply(id: 2, windows: windows)]
        let client = APIClient(channel: channel)
        XCTAssertEqual(try client.resolveSessionId(nil), "sess-1b")
    }

    func testNoWindows() throws {
        let notes = [focusNote(window: "", status: .terminalWindowResignedKey)]
        let (capture, _) = try run([reply(id: 1, focus: notes),
                                    reply(id: 2, windows: [])])
        XCTAssertEqual(capture.out, ["No current window",
                                     "No current tab",
                                     "No current session"])
    }
}
