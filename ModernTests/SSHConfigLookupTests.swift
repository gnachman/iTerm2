//
//  SSHConfigLookupTests.swift
//  ModernTests
//
//  How iTerm2 uses its ssh config files: iTermSSHHelpers lists them and makes a resolver that
//  reads them as one pass, SCP builds an NMSSHSession from what it resolves, and the SSH
//  integration resolves hostnames (and so SSHIdentity) with iTermHostnameFinder. Everything here reads fixture files from a temporary directory; nothing
//  reads the real ~/.ssh or /etc/ssh, and nothing connects to a server.
//

import XCTest
@testable import iTerm2SharedARC

final class SSHConfigLookupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHConfigLookupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `contents` to a fixture file and returns its path.
    private func write(_ name: String, _ contents: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func missingPath(_ name: String) -> String {
        return root.appendingPathComponent(name).path
    }

    private func files(_ paths: [String]) -> [SSHConfigFile] {
        return paths.map { SSHConfigFile(path: $0, isUserConfig: true) }
    }

    private func finder(_ paths: [String]) -> iTermHostnameFinder {
        return iTermHostnameFinder(configFiles: { self.files(paths) })
    }

    // MARK: - iTermSSHHelpers

    func testDefaultConfigFilesInPrecedenceOrder() {
        let files = iTermSSHHelpers.defaultConfigFiles()
        XCTAssertEqual(files.count, 4)
        XCTAssertTrue(files[0].path.hasSuffix("/ssh_config"), files[0].path)
        XCTAssertEqual(files[1].path, ("~/.ssh/config" as NSString).expandingTildeInPath)
        XCTAssertEqual(files[2].path, "/etc/ssh/ssh_config")
        XCTAssertEqual(files[3].path, "/etc/ssh_config")
        XCTAssertEqual(files.map(\.isUserConfig), [true, true, false, false])
    }

    /// Missing files, empty paths, and files that aren't UTF-8 don't stop the others from
    /// being read, and the first file to set a value wins.
    func testUnreadableFilesDoNotStopOthers() throws {
        let notUTF8 = root.appendingPathComponent("binary").path
        try Data([0x48, 0x6f, 0x73, 0x74, 0x20, 0xff, 0xfe, 0x0a]).write(to: URL(fileURLWithPath: notUTF8))
        let first = try write("first", "Host *\n    Hostname first.example.com\n")
        let second = try write("second", "Host *\n    Hostname second.example.com\n    Port 2222\n")

        let config = iTermSSHHelpers.resolver(forFiles: files([missingPath("missing"), "", notUTF8, first, second]))
            .hostConfig(forHost: "x", user: nil, port: nil)
        XCTAssertEqual(config.hostname, "first.example.com")
        XCTAssertEqual(config.port, 2222)
    }

    func testEmptyFileContributesNothing() throws {
        XCTAssertEqual(finder([try write("empty", "")]).sshHostname(forHost: "web"), "web")
    }

    // MARK: - iTermHostnameFinder

    func testHostnameFinderFallsBackToHostAsTyped() throws {
        let path = try write("config", "Host other\n    Hostname other.example.com\n")
        XCTAssertEqual(finder([path]).sshHostname(forHost: "web"), "web")
        XCTAssertEqual(finder([]).sshHostname(forHost: "web"), "web")
    }

    func testHostnameFinderUsesFirstMatchingBlockWithinFile() throws {
        let path = try write("config", """
            Host web
                Hostname web.example.com
            Host *
                Hostname fallback.example.com

            """)
        XCTAssertEqual(finder([path]).sshHostname(forHost: "web"), "web.example.com")
        XCTAssertEqual(finder([path]).sshHostname(forHost: "db"), "fallback.example.com")
    }

    /// The first file whose matching blocks set a HostName wins.
    func testHostnameFinderPrefersEarlierFile() throws {
        let user = try write("user", "Host web\n    Hostname user.example.com\n")
        let system = try write("system", "Host web\n    Hostname system.example.com\n")
        XCTAssertEqual(finder([user, system]).sshHostname(forHost: "web"), "user.example.com")
    }

    /// A file that matches but sets no HostName doesn't stop the search.
    func testHostnameFinderSkipsFileWithoutHostname() throws {
        let user = try write("user", "Host web\n    Port 2222\n")
        let system = try write("system", "Host web\n    Hostname system.example.com\n")
        XCTAssertEqual(finder([user, system]).sshHostname(forHost: "web"), "system.example.com")
    }

    /// The finder rereads the files on every lookup, so edits take effect immediately.
    func testHostnameFinderSeesEditsWithoutRestart() throws {
        let path = try write("config", "Host web\n    Hostname before.example.com\n")
        let finder = finder([path])
        XCTAssertEqual(finder.sshHostname(forHost: "web"), "before.example.com")
        _ = try write("config", "Host web\n    Hostname after.example.com\n")
        XCTAssertEqual(finder.sshHostname(forHost: "web"), "after.example.com")
    }

    // MARK: - SSHIdentity

    /// The SSH integration's identity uses the resolved hostname. Its stringIdentifier keys
    /// “Always Allow This Host” grants and the file panel's remembered folder, so a change in
    /// resolution changes those keys.
    func testIdentityUsesResolvedHostname() throws {
        let path = try write("config", "Host web\n    Hostname web.example.com\n")
        let parsed = ParsedSSHArguments("-p 2200 me@web", booleanArgs: "", hostnameFinder: finder([path]))
        XCTAssertEqual(parsed.host, "web")
        XCTAssertEqual(parsed.identity.hostname, "web.example.com")
        XCTAssertEqual(parsed.identity.stringIdentifier, "me@web.example.com port 2200")
    }

    func testIdentityForUnconfiguredHost() throws {
        let path = try write("config", "Host other\n    Hostname other.example.com\n")
        let parsed = ParsedSSHArguments("web", booleanArgs: "", hostnameFinder: finder([path]))
        XCTAssertEqual(parsed.identity.hostname, "web")
        XCTAssertEqual(parsed.identity.stringIdentifier, "web")
    }

    /// Only HostName comes from the config: the identity's port and user come from the command
    /// line or default to 22 and none. OpenSSH would connect with the config's Port and User.
    func testIdentityIgnoresConfigPortAndUser() throws {
        let path = try write("config", """
            Host web
                Hostname web.example.com
                Port 2222
                User alice

            """)
        let parsed = ParsedSSHArguments("web", booleanArgs: "", hostnameFinder: finder([path]))
        XCTAssertEqual(parsed.identity.port, 22)
        XCTAssertNil(parsed.identity.username)
        XCTAssertEqual(parsed.identity.stringIdentifier, "web.example.com")
    }

    // MARK: - NMSSHSession (SCP)

    /// Builds a session the way SCPFile does.
    private func session(host: String,
                         paths: [String],
                         defaultPort: Int = 22,
                         defaultUsername: String = "defaultuser") -> NMSSHSession {
        let hostConfig = iTermSSHHelpers.resolver(forFiles: files(paths)).hostConfig(forHost: host, user: nil, port: nil)
        return NMSSHSession(host: host,
                            hostConfig: hostConfig,
                            withDefaultPort: defaultPort,
                            defaultUsername: defaultUsername)
    }

    /// SCP reads every file as one pass, with the first value winning.
    func testSessionMergesAcrossFiles() throws {
        let user = try write("user", "Host web\n    Port 2222\n")
        let system = try write("system", """
            Host web
                Hostname web.example.com
                Port 1
                User alice

            """)
        let session = session(host: "web", paths: [user, system])
        XCTAssertEqual(session.host, "web.example.com")
        XCTAssertEqual(session.port, 2222)
        XCTAssertEqual(session.username, "alice")
    }

    func testSessionFallsBackToDefaults() throws {
        let path = try write("config", "Host other\n    Hostname other.example.com\n")
        let session = session(host: "web", paths: [path], defaultPort: 2200, defaultUsername: "bob")
        XCTAssertEqual(session.host, "web")
        XCTAssertEqual(session.port, 2200)
        XCTAssertEqual(session.username, "bob")
    }

    func testSessionCollectsIdentityFiles() throws {
        let user = try write("user", "Host web\n    IdentityFile /keys/a\n")
        let system = try write("system", "Host *\n    IdentityFile /keys/b\n")
        let session = session(host: "web", paths: [user, system])
        XCTAssertEqual(session.hostConfig?.identityFiles as? [String], ["/keys/a", "/keys/b"])
    }

    /// The config's User and Port beat the ones SCP passes in (from the transfer's path), as
    /// NMSSHSession.h documents. OpenSSH gives a user or port named on the command line
    /// precedence over the config.
    func testSessionConfigBeatsExplicitUserAndPort() throws {
        let path = try write("config", "Host web\n    Port 2222\n    User alice\n")
        let session = session(host: "web", paths: [path], defaultPort: 2200, defaultUsername: "bob")
        XCTAssertEqual(session.port, 2222)
        XCTAssertEqual(session.username, "alice")
    }
}
