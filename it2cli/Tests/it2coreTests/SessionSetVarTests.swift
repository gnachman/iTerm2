import XCTest
import ProtobufRuntime
@testable import it2core

/// session set-var sends the value as JSON, which is what the API expects. A
/// value that isn't valid JSON is a plain string and must be encoded as one;
/// otherwise iTerm2 silently drops it.
final class SessionSetVarTests: XCTestCase {
    private func okResponse(id: Int64) -> ITMServerOriginatedMessage {
        let vr = ITMVariableResponse()
        vr.status = .ok
        let message = ITMServerOriginatedMessage()
        message.id_p = id
        message.variableResponse = vr
        return message
    }

    private func sentValue(forArguments arguments: [String]) throws -> (value: String?, out: [String]) {
        let channel = FakeChannel()
        channel.responses = [okResponse(id: 1)]
        let capture = OutputCapture()

        let command = try Session.SetVar.parse(["-s", "sess-1"] + arguments)
        try command.run(capture.context(channel: channel))

        let request = try XCTUnwrap(channel.sent.last?.variableRequest)
        XCTAssertEqual(request.sessionId, "sess-1")
        let set = try XCTUnwrap(request.setArray.firstObject as? ITMVariableRequest_Set)
        XCTAssertEqual(set.name, "user.x")
        return (set.value, capture.out)
    }

    func testPlainValueIsSentAsJSONString() throws {
        let result = try sentValue(forArguments: ["user.x", "hello"])
        XCTAssertEqual(result.value, "\"hello\"")
        XCTAssertEqual(result.out, ["Set user.x = hello"])
    }

    func testPlainValueWithQuotesAndSlashesIsEncoded() throws {
        let plain = #"a "b" \ /c"#
        let result = try sentValue(forArguments: ["user.x", plain])
        XCTAssertEqual(decodeJSONString(try XCTUnwrap(result.value)), plain)
    }

    func testQuotedJSONStringIsSentUnchanged() throws {
        let result = try sentValue(forArguments: ["user.x", "\"hello\""])
        XCTAssertEqual(result.value, "\"hello\"")
    }

    func testJSONNumberIsSentUnchanged() throws {
        let result = try sentValue(forArguments: ["user.x", "42"])
        XCTAssertEqual(result.value, "42")
    }

    func testJSONObjectIsSentUnchanged() throws {
        let result = try sentValue(forArguments: ["user.x", #"{"a": 1}"#])
        XCTAssertEqual(result.value, #"{"a": 1}"#)
    }

    func testEmptyValueIsSentAsEmptyString() throws {
        let result = try sentValue(forArguments: ["user.x", ""])
        XCTAssertEqual(result.value, "\"\"")
    }
}
