//
//  iTermSSHHelpersIncludeTests.swift
//  ModernTests
//
//  SCP transfers build an NMSSHSession from iTermSSHHelpers' configs, and the SSH integration
//  resolves hostnames with iTermHostnameFinder. Both must see hosts defined in included files.
//  Nothing here connects to a server, and nothing reads the real ~/.ssh or /etc/ssh.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSSHHelpersIncludeTests: XCTestCase {
    private var root: URL!
    private var home: String!
    private var sys: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iTermSSHHelpersIncludeTests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home").path
        sys = root.appendingPathComponent("etc-ssh").path
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: sys, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ lines: [String]) {
        let dir = (path as NSString).deletingLastPathComponent
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try! (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private var appSupportConfig: String { root.appendingPathComponent("AppSupport/ssh_config").path }
    private var userConfig: String { home + "/.ssh/config" }

    private func configs() -> [NMSSHConfig] {
        let expander = iTermSSHConfigIncludeExpander(homeDirectory: home,
                                                     userName: "tu",
                                                     uid: 501,
                                                     localHostname: { "lh.example.com" },
                                                     environment: [:],
                                                     systemConfigDirectory: sys)
        return iTermSSHHelpers.configs(withUserPaths: [appSupportConfig, userConfig],
                                       systemPaths: [sys + "/ssh_config", sys + "/missing"],
                                       expander: expander)
    }

    private func writeLima() {
        write(userConfig, ["Include ~/.lima/*/ssh.config"])
        write(home + "/.lima/dev/ssh.config", ["Host lima-dev",
                                               "  Hostname 127.0.0.1",
                                               "  Port 56266",
                                               "  User u"])
    }

    func testSessionUsesIncludedHost() {
        writeLima()
        let session = NMSSHSession(host: "lima-dev",
                                   configs: configs(),
                                   withDefaultPort: 22,
                                   defaultUsername: "nobody")
        XCTAssertEqual(session.host, "127.0.0.1")
        XCTAssertEqual(session.port.intValue, 56266)
        XCTAssertEqual(session.username, "u")
        XCTAssertFalse(session.isConnected)
    }

    func testConfigPrecedenceAcrossFiles() {
        write(appSupportConfig, ["Host x", "Port 1"])
        write(userConfig, ["Include inc"])
        write(home + "/.ssh/inc", ["Host x", "Port 2", "User ux"])
        let session = NMSSHSession(host: "x",
                                   configs: configs(),
                                   withDefaultPort: 22,
                                   defaultUsername: "nobody")
        XCTAssertEqual(session.port.intValue, 1)
        XCTAssertEqual(session.username, "ux")
    }

    func testSystemConfigIncludesAreAnchoredAtSystemDirectory() {
        write(sys + "/ssh_config", ["Include conf.d/*"])
        write(sys + "/conf.d/s", ["Host s", "Port 3"])
        let session = NMSSHSession(host: "s",
                                   configs: configs(),
                                   withDefaultPort: 22,
                                   defaultUsername: "nobody")
        XCTAssertEqual(session.port.intValue, 3)
    }

    func testHostnameFinderUsesIncludedHost() {
        writeLima()
        let finder = iTermHostnameFinder(configs: { self.configs() })
        XCTAssertEqual(finder.sshHostname(forHost: "lima-dev"), "127.0.0.1")
        XCTAssertEqual(finder.sshHostname(forHost: "unknown-host"), "unknown-host")
    }
}
