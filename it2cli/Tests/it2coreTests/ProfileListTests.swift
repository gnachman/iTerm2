import XCTest
import ProtobufRuntime
@testable import it2core

final class ProfileListTests: XCTestCase {
    func testProfileListTabularOutput() throws {
        let channel = FakeChannel()

        let guidProp = ITMProfileProperty()
        guidProp.key = "Guid"
        guidProp.jsonValue = "\"GUID-1\"" // JSON-quoted; the command trims quotes
        let nameProp = ITMProfileProperty()
        nameProp.key = "Name"
        nameProp.jsonValue = "\"Default\""

        let profile = ITMListProfilesResponse_Profile()
        profile.propertiesArray.add(guidProp)
        profile.propertiesArray.add(nameProp)

        let listResp = ITMListProfilesResponse()
        listResp.profilesArray.add(profile)

        let reply = ITMServerOriginatedMessage()
        reply.id_p = 1
        reply.listProfilesResponse = listResp
        channel.responses = [reply]

        let capture = OutputCapture()
        var command = try Profile.List.parse([])
        try command.run(capture.context(channel: channel))

        XCTAssertEqual(capture.out, ["GUID-1\tDefault"])
        XCTAssertEqual(channel.sent.first?.submessageOneOfCase, .listProfilesRequest)
    }
}
