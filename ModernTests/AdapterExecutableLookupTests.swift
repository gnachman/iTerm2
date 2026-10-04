//
//  AdapterExecutableLookupTests.swift
//  ModernTests
//
//  Password manager adapters find their CLI (such as bw) on the user’s shell PATH before
//  asking for it in an open panel. The lookup must take the first executable match in PATH
//  order and keep the path as found, symlink included, so a package manager upgrade that
//  repoints the symlink is followed.
//

import XCTest
@testable import iTerm2SharedARC

final class AdapterExecutableLookupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func directory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ url: URL, executable: Bool) throws {
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644],
                                              ofItemAtPath: url.path)
    }

    private func find(_ path: [URL]) -> String? {
        return AdapterPasswordDataSource.findExecutable(named: "bw",
                                                        searchPath: path.map(\.path).joined(separator: ":"))
    }

    func testFirstMatchInPathOrderWins() throws {
        let first = try directory("first")
        let second = try directory("second")
        try makeFile(first.appendingPathComponent("bw"), executable: true)
        try makeFile(second.appendingPathComponent("bw"), executable: true)
        XCTAssertEqual(find([first, second]), first.appendingPathComponent("bw").path)
        XCTAssertEqual(find([second, first]), second.appendingPathComponent("bw").path)
    }

    func testSkipsNonExecutableFilesAndDirectories() throws {
        let notExecutable = try directory("plain")
        try makeFile(notExecutable.appendingPathComponent("bw"), executable: false)
        let hasDirectory = try directory("dir")
        try FileManager.default.createDirectory(at: hasDirectory.appendingPathComponent("bw"),
                                                withIntermediateDirectories: true)
        let good = try directory("good")
        try makeFile(good.appendingPathComponent("bw"), executable: true)
        XCTAssertEqual(find([notExecutable, hasDirectory, good]), good.appendingPathComponent("bw").path)
    }

    func testKeepsSymlinkPathRatherThanTarget() throws {
        let cellar = try directory("Cellar/bitwarden-cli/2026.9.0/bin")
        try makeFile(cellar.appendingPathComponent("bw"), executable: true)
        let bin = try directory("bin")
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("bw"),
                                                   withDestinationURL: cellar.appendingPathComponent("bw"))
        XCTAssertEqual(find([bin]), bin.appendingPathComponent("bw").path)
    }

    func testMissingOrEmptyPathFindsNothing() throws {
        let empty = try directory("empty")
        XCTAssertNil(find([empty]))
        XCTAssertNil(AdapterPasswordDataSource.findExecutable(named: "bw", searchPath: ""))
        XCTAssertNil(AdapterPasswordDataSource.findExecutable(named: "bw", searchPath: "::"))
    }
}
