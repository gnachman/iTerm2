import Foundation
import ProtobufRuntime
@testable import it2core

/// In-memory APIChannel for testing APIClient / commands without a running iTerm2.
/// Responses are returned in order; the enclosing APIClient.send() matches by id.
final class FakeChannel: APIChannel {
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

/// Captures stdout/stderr lines and vends an IT2Context whose client speaks to a
/// FakeChannel. Reference type so captured lines survive the command's run().
final class OutputCapture {
    private(set) var out: [String] = []
    private(set) var err: [String] = []

    func context(channel: FakeChannel,
                 confirm: @escaping (String) -> Bool = { _ in false },
                 isRemote: Bool = false) -> IT2Context {
        return IT2Context(
            out: { [weak self] in self?.out.append($0) },
            err: { [weak self] in self?.err.append($0) },
            confirm: confirm,
            makeClient: { APIClient(channel: channel) },
            installsSignalHandlers: false,  // embedded-like: no process to own
            isRemote: isRemote
        )
    }
}
