//
//  SSHConfigTestFixture.swift
//  ModernTests
//
//  Resolves hosts against an ssh config written to a temporary directory, with a fake home
//  directory and user, so tests never read the real ~/.ssh or /etc/ssh.
//

import XCTest
@_spi(Testing) import NMSSH

final class SSHConfigTestFixture {
    let root: URL
    let home: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHConfigTestFixture-\(UUID().uuidString)")
        home = root.appendingPathComponent("home").path
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Resolves `host` against a user config containing `contents`.
    func resolve(_ host: String, in contents: String) throws -> NMSSHHostConfig {
        let path = home + "/.ssh/config"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        let local = SSHConfigResolver.LocalSystem(homeDirectory: home,
                                                  userName: "localuser",
                                                  uid: getuid(),
                                                  hostname: "mac.example.com",
                                                  environment: [:],
                                                  systemConfigDirectory: root.appendingPathComponent("etc-ssh").path)
        return SSHConfigResolver(files: [SSHConfigFile(path: path, isUserConfig: true)], localSystem: local)
            .resolve(host: host, user: nil, port: nil, remoteCommand: nil)
    }
}

extension NMSSHHostConfig {
    /// Whether no setting applied.
    var isEmpty: Bool {
        return hostname == nil && user == nil && port == nil && ((identityFiles as? [String]) ?? []).isEmpty
    }

    var identityFilePaths: [String] {
        return (identityFiles as? [String]) ?? []
    }
}
