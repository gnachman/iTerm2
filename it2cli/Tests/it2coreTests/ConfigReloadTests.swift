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
}
