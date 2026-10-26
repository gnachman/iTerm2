import XCTest
@testable import it2core

/// Tests the in-process entry point IT2Embedded.run and the shared
/// runToExitCode outcome->exit-code mapping.
final class IT2EmbeddedTests: XCTestCase {
    private func capturing() -> (IT2IO, () -> [String], () -> [String]) {
        var out: [String] = []
        var err: [String] = []
        let io = IT2IO(stdout: { out.append($0) }, stderr: { err.append($0) })
        return (io, { out }, { err })
    }

    func testUnknownCommandReturns64AndWritesUsage() {
        let (io, _, err) = capturing()
        let code = IT2Embedded.run(arguments: ["definitely-not-a-command"], io: io, channel: FakeChannel(), originIdentifier: nil)
        XCTAssertEqual(code, 64) // ArgumentParser validation failure
        XCTAssertFalse(err().isEmpty, "usage/error should go to stderr")
    }

    func testVersionReturnsZeroAndWritesToStdout() {
        let (io, out, _) = capturing()
        let code = IT2Embedded.run(arguments: ["--version"], io: io, channel: FakeChannel(), originIdentifier: nil)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out().contains("1.0.0"), "got \(out())")
    }

    func testIT2ExitCodePropagates() throws {
        // The alias-not-found path calls ctx.exit(3); verify IT2Embedded maps it.
        let path = NSTemporaryDirectory() + "it2rc-\(UUID().uuidString).yaml"
        try "{}\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("IT2_CONFIG_PATH", path, 1)
        defer { unsetenv("IT2_CONFIG_PATH") }

        let (io, _, err) = capturing()
        let code = IT2Embedded.run(arguments: ["alias", "nope"], io: io, channel: FakeChannel(), originIdentifier: nil)
        XCTAssertEqual(code, 3)
        XCTAssertEqual(err(), ["No aliases defined in config file"])
    }
}
// MARK: - stdin and environment reach a command (3b)

/// The wire carries a remote command's stdin and an allowlisted slice of its environment. These
/// pin that IT2Embedded actually hands both to the IT2Context a command reads, rather than
/// stopping at the boundary. The equivalent gap one layer up is what made the PATH regression
/// possible: every unit test passed while the integration was wrong.
final class IT2EmbeddedStdinEnvTests: XCTestCase {
    private func contextSeenBy(arguments: [String],
                               stdin: Data,
                               environment: [String: String]) -> IT2Context? {
        var captured: IT2Context?
        IT2Context.captureForTesting = { captured = $0 }
        defer { IT2Context.captureForTesting = nil }
        _ = IT2Embedded.run(arguments: arguments,
                            io: IT2IO(stdout: { _ in }, stderr: { _ in }),
                            channel: FakeChannel(),
                            originIdentifier: "conductor-A",
                            stdin: stdin,
                            environment: environment)
        return captured
    }

    func testStdinReachesTheContext() throws {
        let payload = Data(#"{"hook_event_name":"Stop"}"#.utf8)
        let context = try XCTUnwrap(contextSeenBy(arguments: ["--version"],
                                                  stdin: payload,
                                                  environment: [:]))
        XCTAssertEqual(context.stdin(), payload)
    }

    func testEnvironmentReachesTheContext() throws {
        let context = try XCTUnwrap(contextSeenBy(arguments: ["--version"],
                                                  stdin: Data(),
                                                  environment: ["TMUX_PANE": "%3"]))
        XCTAssertEqual(context.environment["TMUX_PANE"], "%3")
    }

    // A remote context must not fall back to the Mac's own environment: that would make a
    // remote command address a local session.
    func testTheMacsEnvironmentIsNotVisibleToARemoteCommand() throws {
        let context = try XCTUnwrap(contextSeenBy(arguments: ["--version"],
                                                  stdin: Data(),
                                                  environment: ["TMUX_PANE": "%3"]))
        XCTAssertEqual(context.environment, ["TMUX_PANE": "%3"],
                       "only what came over the wire: \(context.environment)")
    }
}
