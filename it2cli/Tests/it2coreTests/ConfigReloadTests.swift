import XCTest
@testable import it2core

final class ConfigReloadTests: XCTestCase {
    func testConfigReloadListsProfilesAndAliases() throws {
        let path = NSTemporaryDirectory() + "it2rc-\(UUID().uuidString).yaml"
        let yaml = """
        profiles:
          dev:
            - command: "echo hi"
        aliases:
          greet: session run "echo hello"
        """
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("IT2_CONFIG_PATH", path, 1)
        defer { unsetenv("IT2_CONFIG_PATH") }

        let capture = OutputCapture()
        var command = try ConfigReload.parse([])
        command.run(capture.context(channel: FakeChannel())) // does not touch the API

        XCTAssertEqual(capture.out, [
            "Configuration reloaded",
            "Loaded 1 profiles: dev",
            "Loaded 1 aliases: greet",
        ])
    }

    func testMissingAliasExitsWithCodeThree() throws {
        let path = NSTemporaryDirectory() + "it2rc-\(UUID().uuidString).yaml"
        try "{}\n".write(toFile: path, atomically: true, encoding: .utf8) // no aliases defined
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("IT2_CONFIG_PATH", path, 1)
        defer { unsetenv("IT2_CONFIG_PATH") }

        let capture = OutputCapture()
        var command = try AliasCommand.parse(["nope"])
        XCTAssertThrowsError(try command.run(capture.context(channel: FakeChannel()))) { error in
            guard let exit = error as? IT2Exit else {
                return XCTFail("expected IT2Exit, got \(error)")
            }
            XCTAssertEqual(exit.code, 3)
        }
        XCTAssertEqual(capture.err, ["No aliases defined in config file"])
    }

    func testMalformedConfigWarningGoesToErrSink() throws {
        // Valid YAML but not a top-level mapping: the parse warning must reach the
        // injected err sink (so a remote it2-over-ssh user sees it down the ssh channel)
        // rather than the process's real stderr, which is the GUI app's when embedded.
        let path = NSTemporaryDirectory() + "it2rc-\(UUID().uuidString).yaml"
        try "- not\n- a mapping\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        setenv("IT2_CONFIG_PATH", path, 1)
        defer { unsetenv("IT2_CONFIG_PATH") }

        let capture = OutputCapture()
        var command = try ConfigReload.parse([])
        command.run(capture.context(channel: FakeChannel()))

        XCTAssertTrue(capture.err.contains { $0.contains("Could not parse config file") },
                      "warning must reach the err sink, got err=\(capture.err)")
    }
}
