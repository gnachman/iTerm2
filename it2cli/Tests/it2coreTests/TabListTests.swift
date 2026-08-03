import XCTest
import ProtobufRuntime
@testable import it2core

final class TabListTests: XCTestCase {
    func testTabListTabularOutput() throws {
        let channel = FakeChannel()

        // Focus response (id 1): no selected-tab notifications -> nothing active.
        let focusReply = ITMServerOriginatedMessage()
        focusReply.id_p = 1
        focusReply.focusResponse = ITMFocusResponse()

        // List response (id 2): one window, one tab containing one session.
        let summary = ITMSessionSummary()
        summary.uniqueIdentifier = "sess-1"
        let link = ITMSplitTreeNode_SplitTreeLink()
        link.session = summary
        let root = ITMSplitTreeNode()
        root.linksArray.add(link)
        let tab = ITMListSessionsResponse_Tab()
        tab.tabId = "tab-1"
        tab.root = root
        let window = ITMListSessionsResponse_Window()
        window.windowId = "win-1"
        window.tabsArray.add(tab)
        let listResp = ITMListSessionsResponse()
        listResp.windowsArray.add(window)
        let listReply = ITMServerOriginatedMessage()
        listReply.id_p = 2
        listReply.listSessionsResponse = listResp

        channel.responses = [focusReply, listReply]

        let capture = OutputCapture()
        var command = try Tab.List.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["tab-1\twindow=win-1\tindex=0\tsessions=1"])
    }
}
