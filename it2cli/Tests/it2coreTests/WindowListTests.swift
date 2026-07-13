import XCTest
import ProtobufRuntime
@testable import it2core

final class WindowListTests: XCTestCase {
    func testWindowListTabularOutput() throws {
        let channel = FakeChannel()

        let window = ITMListSessionsResponse_Window()
        window.windowId = "win-1"
        window.tabsArray.add(ITMListSessionsResponse_Tab())
        window.tabsArray.add(ITMListSessionsResponse_Tab())

        let listResp = ITMListSessionsResponse()
        listResp.windowsArray.add(window)

        let reply = ITMServerOriginatedMessage()
        reply.id_p = 1
        reply.listSessionsResponse = listResp
        // Only the list response is queued; the per-window fullscreen probe is
        // wrapped in try? and degrades to "not fullscreen".
        channel.responses = [reply]

        let capture = OutputCapture()
        var command = try Window.List.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["win-1\t2 tabs"])
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .listSessionsRequest)
    }
}
