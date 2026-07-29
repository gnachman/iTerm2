import XCTest
import ProtobufRuntime
@testable import it2core

final class SessionCloseTests: XCTestCase {
    func testDeclinedCloseThrowsCancelledAndDoesNotCallAPI() throws {
        let channel = FakeChannel() // no responses queued; must not be used
        let capture = OutputCapture()
        let ctx = capture.context(channel: channel, confirm: { _ in false })

        var command = try Session.Close.parse(["-s", "sess-1"])
        XCTAssertThrowsError(try command.run(ctx)) { error in
            guard let it2 = error as? IT2Error, case .cancelled = it2 else {
                return XCTFail("expected IT2Error.cancelled, got \(error)")
            }
        }
        XCTAssertEqual(channel.sent.count, 0, "a declined close must not talk to the API")
    }

    func testForceCloseSendsCloseRequest() throws {
        let channel = FakeChannel()
        let reply = ITMServerOriginatedMessage()
        reply.id_p = 1
        reply.closeResponse = ITMCloseResponse() // no statuses -> success
        channel.responses = [reply]

        let capture = OutputCapture()
        var command = try Session.Close.parse(["-s", "sess-1", "--force"])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["Session closed"])
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .closeRequest)
    }
}
