import XCTest
import ProtobufRuntime
@testable import it2core

// Profile properties, variable values and function results arrive
// JSON-encoded, and iTerm2 escapes "/" as "\/". Commands must decode them, not
// just strip the quotes, or the escapes leak into the output.
final class JSONStringValueTests: XCTestCase {
    func testDecodesEscapes() {
        XCTAssertEqual(jsonStringValue(#""Q\/P \"x\"""#), #"Q/P "x""#)
        XCTAssertEqual(jsonStringValue(#""a \\ b""#), #"a \ b"#)
    }

    func testNullAndMissingAreEmpty() {
        XCTAssertEqual(jsonStringValue("null"), "")
        XCTAssertEqual(jsonStringValue(nil), "")
    }

    func testNonStringValuesAreKept() {
        XCTAssertEqual(jsonStringValue("12"), "12")
        XCTAssertEqual(jsonStringValue("true"), "true")
    }

    func testProfileListDecodesNameAndGuid() throws {
        let guidProp = ITMProfileProperty()
        guidProp.key = "Guid"
        guidProp.jsonValue = #""G\/1""#
        let nameProp = ITMProfileProperty()
        nameProp.key = "Name"
        nameProp.jsonValue = #""Q\/P \"x\"""#
        let profile = ITMListProfilesResponse_Profile()
        profile.propertiesArray.add(guidProp)
        profile.propertiesArray.add(nameProp)
        let listResp = ITMListProfilesResponse()
        listResp.profilesArray.add(profile)
        let reply = ITMServerOriginatedMessage()
        reply.id_p = 1
        reply.listProfilesResponse = listResp

        let channel = FakeChannel()
        channel.responses = [reply]
        let capture = OutputCapture()
        var command = try Profile.List.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["G/1\t" + #"Q/P "x""#])
    }

    func testGetFocusDecodesSessionName() throws {
        let sessionNote = ITMFocusChangedNotification()
        sessionNote.session = "sess-1"
        let focusResp = ITMFocusResponse()
        focusResp.notificationsArray.add(sessionNote)
        let focusReply = ITMServerOriginatedMessage()
        focusReply.id_p = 1
        focusReply.focusResponse = focusResp

        let vr = ITMVariableResponse()
        vr.status = .ok
        vr.valuesArray.add(#""say \"hi\" \\ x\/y""#)
        let varReply = ITMServerOriginatedMessage()
        varReply.id_p = 2
        varReply.variableResponse = vr

        let channel = FakeChannel()
        channel.responses = [focusReply, varReply]
        let capture = OutputCapture()
        var command = try App.GetFocus.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out.last, #"Session name: say "hi" \ x/y"#)
    }
}
