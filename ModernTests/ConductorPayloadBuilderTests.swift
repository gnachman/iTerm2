//
//  ConductorPayloadBuilderTests.swift
//  iTerm2 ModernTests
//
//  Payloads uploaded to a remote host at getshell. Phase 3a adds it2 to this
//  set, keyed by a content hash, which makes two existing behaviours dangerous.
//
//  A TarJob tars all of its sources together, so one missing local file makes
//  tarballData() throw and the WHOLE job is dropped. Payload paths are also
//  persisted in restorable state, so after an upgrade a session can still be
//  carrying the previous build's it2.<hash>.py path. That stale entry would
//  otherwise suppress the entire shell-integration upload for that session, and
//  the symptom would be "shell integration silently stopped working after an
//  update" with nothing pointing at the cause.
//
//  So a missing source is skipped individually, and two entries that would land
//  on the same remote path are deduped rather than tarred twice.
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorPayloadBuilderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("payloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func destinations(_ builder: ConductorPayloadBuilder) -> [String] {
        var result = [String]()
        builder.enumeratePayloads { _, destination in
            result.append(destination)
        }
        return result
    }

    // The upgrade case: a stale hashed path persisted in restorable state no longer exists.
    // It must not take the live files down with it.
    func testAMissingSourceDoesNotSuppressItsSiblings() throws {
        let present = try makeFile("iterm2_shell_integration.zsh")
        let missing = dir.appendingPathComponent("it2.deadbeefdeadbeef.py")
        let remote = URL(fileURLWithPath: "/$HOME/.iterm2/shell-integration")

        let builder = ConductorPayloadBuilder()
        builder.add(localPath: present, destination: remote)
        builder.add(localPath: missing, destination: remote)

        XCTAssertEqual(destinations(builder), [remote.path],
                       "the job with the live file must still be uploaded")
    }

    func testAJobWithOnlyMissingSourcesProducesNothing() {
        let builder = ConductorPayloadBuilder()
        builder.add(localPath: dir.appendingPathComponent("gone.py"),
                    destination: URL(fileURLWithPath: "/$HOME/.iterm2/bin"))
        XCTAssertEqual(destinations(builder), [], "nothing to send, so no payload")
    }

    // Adding the same file twice (two callers both asking for it2, say) must not tar it twice.
    func testDuplicateSourceAndDestinationIsAddedOnce() throws {
        let file = try makeFile("it2-remote")
        let remote = URL(fileURLWithPath: "/$HOME/.iterm2/bin")

        let builder = ConductorPayloadBuilder()
        builder.add(localPath: file, destination: remote)
        builder.add(localPath: file, destination: remote)

        XCTAssertEqual(destinations(builder), [remote.path])
        XCTAssertEqual(builder.sourceCount(forDestination: remote.path), 1,
                       "the same file must not be tarred twice")
    }

    // Two different local files landing on the same remote path: the first wins, because the
    // remote name is the local basename and the second would overwrite it inside one tarball.
    func testTwoSourcesWithTheSameRemoteNameAreDeduped() throws {
        let a = dir.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        let b = dir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let first = a.appendingPathComponent("it2")
        let second = b.appendingPathComponent("it2")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let remote = URL(fileURLWithPath: "/$HOME/.iterm2/bin")

        let builder = ConductorPayloadBuilder()
        builder.add(localPath: first, destination: remote)
        builder.add(localPath: second, destination: remote)

        XCTAssertEqual(builder.sourceCount(forDestination: remote.path), 1,
                       "same remote name, so only one may be sent")
    }

    func testDistinctDestinationsAreKept() throws {
        let script = try makeFile("iterm2_shell_integration.zsh")
        let wrapper = try makeFile("it2-remote")
        let builder = ConductorPayloadBuilder()
        builder.add(localPath: script, destination: URL(fileURLWithPath: "/$HOME/.iterm2/shell-integration"))
        builder.add(localPath: wrapper, destination: URL(fileURLWithPath: "/$HOME/.iterm2/bin"))
        XCTAssertEqual(Set(destinations(builder)),
                       ["/$HOME/.iterm2/shell-integration", "/$HOME/.iterm2/bin"])
    }
}
