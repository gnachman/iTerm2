import XCTest
import ProtobufRuntime
@testable import it2core

final class MonitorOutputTests: XCTestCase {
    func testMonitorOutputOncePrintsScreenContents() throws {
        let channel = FakeChannel()

        let line1 = ITMLineContents()
        line1.text = "hello"
        let line2 = ITMLineContents()
        line2.text = "world"
        let buf = ITMGetBufferResponse()
        buf.status = .ok
        buf.contentsArray.add(line1)
        buf.contentsArray.add(line2)

        let reply = ITMServerOriginatedMessage()
        reply.id_p = 1
        reply.getBufferResponse = buf
        channel.responses = [reply]

        let capture = OutputCapture()
        // No --follow: a single GetBuffer, print the screen, return (no streaming).
        var command = try Monitor.Output.parse(["-s", "sess-1"])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["hello\nworld"])
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .getBufferRequest)
    }
}
