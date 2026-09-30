import XCTest
import ProtobufRuntime
@testable import it2core

// `it2 handle-agent-hook` through the embedded entry point, the way a remote hook reaches it:
// the payload arrives as the context's stdin and the addressing variables as the context's
// environment, never from the process, and the resulting built-in invocation goes out over the
// channel. This is the integration test for the command tree; the decision logic itself is
// covered scenario by scenario in AgentHookScenarioTests.
final class AgentHookEmbeddedTests: XCTestCase {
    private func statusReply(id: Int64) -> ITMServerOriginatedMessage {
        let message = ITMServerOriginatedMessage()
        message.id_p = id
        let invoke = ITMInvokeFunctionResponse()
        let success = ITMInvokeFunctionResponse_Success()
        success.jsonResult = "{\"status\":\"working\",\"detail\":null,\"background_tasks\":0,\"turn_open\":null}"
        invoke.success = success
        message.invokeFunctionResponse = invoke
        return message
    }

    private func capturing() -> (IT2IO, () -> [String], () -> [String]) {
        var out: [String] = []
        var err: [String] = []
        let io = IT2IO(stdout: { out.append($0) }, stderr: { err.append($0) })
        return (io, { out }, { err })
    }

    func testPayloadOnStdinBecomesASetSessionStatusInvocation() throws {
        let channel = FakeChannel()
        channel.responses = [statusReply(id: 1)]
        let (io, out, err) = capturing()
        let payload = Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"s"}"#.utf8)

        let code = IT2Embedded.run(arguments: ["handle-agent-hook"],
                                   io: io,
                                   channel: channel,
                                   originIdentifier: nil,
                                   stdin: payload,
                                   environment: ["TERM_SESSION_ID": "w0t0p0:ABC", "IT2_SOCK": "/tmp/x.sock"])

        XCTAssertEqual(code, 0)
        XCTAssertEqual(out(), [], "a hook must print nothing: Codex rejects non-JSON stdout")
        XCTAssertEqual(err(), [])
        let invocation = try XCTUnwrap(channel.sent.first?.invokeFunctionRequest?.invocation)
        XCTAssertTrue(invocation.hasPrefix("iterm2.set_session_status(session_id: \"ABC\""), invocation)
        XCTAssertTrue(invocation.contains("status: \"working\""), invocation)
        XCTAssertTrue(invocation.contains("expires_on: \"progress-end\""), invocation)
        XCTAssertEqual(channel.sent.count, 1)
    }

    // The process's own environment must never be consulted: in-process inside iTerm2 that would
    // be iTerm2's environment, not the hook's.
    func testProcessEnvironmentIsNotConsulted() throws {
        setenv("TERM_SESSION_ID", "w0t0p0:FROM-PROCESS", 1)
        defer { unsetenv("TERM_SESSION_ID") }
        let channel = FakeChannel()
        let (io, out, err) = capturing()
        let payload = Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8)

        let code = IT2Embedded.run(arguments: ["handle-agent-hook"],
                                   io: io,
                                   channel: channel,
                                   originIdentifier: nil,
                                   stdin: payload,
                                   environment: ["IT2_SOCK": "/tmp/x.sock"])

        XCTAssertEqual(code, 0)
        XCTAssertEqual(channel.sent.count, 0, "nothing to address, so nothing is sent")
        XCTAssertEqual(out(), [])
        XCTAssertEqual(err(), [])
    }

    func testCodexHookAsksForTheProgressRing() throws {
        let channel = FakeChannel()
        channel.responses = [statusReply(id: 1)]
        let (io, _, _) = capturing()
        let payload = Data(#"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8)

        let code = IT2Embedded.run(arguments: ["handle-agent-hook", "--agent", "codex"],
                                   io: io,
                                   channel: channel,
                                   originIdentifier: nil,
                                   stdin: payload,
                                   environment: ["TERM_SESSION_ID": "w0t0p0:ABC", "IT2_SOCK": "/tmp/x.sock"])

        XCTAssertEqual(code, 0)
        let invocation = try XCTUnwrap(channel.sent.first?.invokeFunctionRequest?.invocation)
        XCTAssertTrue(invocation.contains("progress: \"running\""), invocation)
        XCTAssertFalse(invocation.contains("expires_on"), "Codex statuses never expire on progress end: \(invocation)")
    }
}
