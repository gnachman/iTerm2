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
        let code = IT2Embedded.run(arguments: ["definitely-not-a-command"], io: io, channel: FakeChannel())
        XCTAssertEqual(code, 64) // ArgumentParser validation failure
        XCTAssertFalse(err().isEmpty, "usage/error should go to stderr")
    }

    func testVersionReturnsZeroAndWritesToStdout() {
        let (io, out, _) = capturing()
        let code = IT2Embedded.run(arguments: ["--version"], io: io, channel: FakeChannel())
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
        let code = IT2Embedded.run(arguments: ["alias", "nope"], io: io, channel: FakeChannel())
        XCTAssertEqual(code, 3)
        XCTAssertEqual(err(), ["No aliases defined in config file"])
    }
}
