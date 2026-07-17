import XCTest
import ProtobufRuntime
@testable import it2core

final class AppQuitTests: XCTestCase {
    func testDeclinedQuitThrowsCancelledAndDoesNotCallAPI() throws {
        let channel = FakeChannel()
        let capture = OutputCapture()
        let ctx = capture.context(channel: channel, confirm: { _ in false })

        var command = try App.Quit.parse([])
        XCTAssertThrowsError(try command.run(ctx)) { error in
            guard let it2 = error as? IT2Error, case .cancelled = it2 else {
                return XCTFail("expected IT2Error.cancelled, got \(error)")
            }
        }
        XCTAssertEqual(channel.sent.count, 0)
    }

    func testForceQuitSendsMenuItemRequest() throws {
        let channel = FakeChannel()
        let reply = ITMServerOriginatedMessage()
        reply.id_p = 1
        reply.menuItemResponse = ITMMenuItemResponse()
        channel.responses = [reply]

        let capture = OutputCapture()
        var command = try App.Quit.parse(["--force"])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["iTerm2 quit command sent"])
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .menuItemRequest)
    }
}
