import XCTest
import ProtobufRuntime
@testable import it2core

/// An in-memory APIChannel for testing APIClient without a running iTerm2.
private final class FakeChannel: APIChannel {
    private(set) var sent: [ITMClientOriginatedMessage] = []
    var responses: [ITMServerOriginatedMessage] = []
    private(set) var disconnected = false

    func send(_ request: ITMClientOriginatedMessage) throws {
        sent.append(request)
    }

    func receiveMessage() throws -> ITMServerOriginatedMessage {
        guard !responses.isEmpty else {
            throw IT2Error.apiError("FakeChannel ran out of responses")
        }
        return responses.removeFirst()
    }

    func disconnect() {
        disconnected = true
    }
}

private func listSessionsRequest() -> ITMClientOriginatedMessage {
    let request = ITMClientOriginatedMessage()
    request.listSessionsRequest = ITMListSessionsRequest()
    return request
}

private func response(id: Int64) -> ITMServerOriginatedMessage {
    let message = ITMServerOriginatedMessage()
    message.id_p = id
    return message
}

final class APIClientTests: XCTestCase {
    func testSendAssignsIdAndReturnsMatchingResponse() throws {
        let channel = FakeChannel()
        let reply = response(id: 1)
        channel.responses = [reply]

        let client = APIClient(channel: channel)
        let got = try client.send(listSessionsRequest())

        XCTAssertEqual(channel.sent.count, 1)
        XCTAssertEqual(channel.sent.first?.id_p, 1, "send() should assign the next id")
        XCTAssertTrue(got === reply)
    }

    func testSendPreservesCallerAssignedId() throws {
        let channel = FakeChannel()
        channel.responses = [response(id: 42)]

        let client = APIClient(channel: channel)
        let request = listSessionsRequest()
        request.id_p = 42 // caller-assigned; send() must not overwrite it

        let got = try client.send(request)
        XCTAssertEqual(channel.sent.first?.id_p, 42)
        XCTAssertEqual(got.id_p, 42)
    }

    func testSendSkipsResponsesWithNonMatchingId() throws {
        // A stray message (e.g. a late notification) with a different id should
        // be skipped until the matching response arrives.
        let channel = FakeChannel()
        let stray = response(id: 999)
        let match = response(id: 1)
        channel.responses = [stray, match]

        let client = APIClient(channel: channel)
        let got = try client.send(listSessionsRequest())
        XCTAssertTrue(got === match)
    }

    func testSendThrowsOnServerError() {
        let channel = FakeChannel()
        let errorReply = response(id: 1)
        errorReply.error = "boom"
        channel.responses = [errorReply]

        let client = APIClient(channel: channel)
        XCTAssertThrowsError(try client.send(listSessionsRequest())) { error in
            guard let it2 = error as? IT2Error, case .apiError = it2 else {
                return XCTFail("expected IT2Error.apiError, got \(error)")
            }
        }
    }

    func testReceiveMessageStreamsInOrder() throws {
        let channel = FakeChannel()
        let first = response(id: 10)
        let second = response(id: 11)
        channel.responses = [first, second]

        let client = APIClient(channel: channel)
        XCTAssertTrue(try client.receiveMessage() === first)
        XCTAssertTrue(try client.receiveMessage() === second)
    }

    func testDisconnectForwardsToChannel() {
        let channel = FakeChannel()
        let client = APIClient(channel: channel)
        client.disconnect()
        XCTAssertTrue(channel.disconnected)
    }
}
