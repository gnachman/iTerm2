import XCTest
import ProtobufRuntime
@testable import it2core

/// Integration-style test: drives the real `session list` command logic with a
/// fake channel and a capturing context, asserting both the requests it builds
/// and the text it formats.
final class SessionListTests: XCTestCase {
    private func listResponse(id: Int64, sessionId: String, title: String) -> ITMServerOriginatedMessage {
        let summary = ITMSessionSummary()
        summary.uniqueIdentifier = sessionId
        summary.title = title
        // No gridSize -> hasGridSize is false -> reported as 0x0.

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

        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.listSessionsResponse = listResp
        return message
    }

    private func variableResponse(id: Int64, name: String, tty: String) -> ITMServerOriginatedMessage {
        let vr = ITMVariableResponse()
        vr.status = .ok
        vr.valuesArray.add("\"\(name)\"") // values arrive JSON-quoted; the command trims quotes
        vr.valuesArray.add("\"\(tty)\"")

        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.variableResponse = vr
        return message
    }

    func testSessionListTabularOutput() throws {
        let channel = FakeChannel()
        channel.responses = [
            listResponse(id: 1, sessionId: "sess-1", title: "My Title"),
            variableResponse(id: 2, name: "myname", tty: "/dev/ttys001"),
        ]
        let capture = OutputCapture()

        var command = try Session.List.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["sess-1\tmyname\tMy Title\t0x0\t/dev/ttys001"])

        // The command should issue exactly a ListSessions request then a Variable request.
        XCTAssertEqual(channel.sent.count, 2)
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .listSessionsRequest)
        XCTAssertEqual(channel.sent.last?.submessageOneOfCase, .variableRequest)
        XCTAssertTrue(channel.disconnected, "run() should disconnect the client")
    }
}
