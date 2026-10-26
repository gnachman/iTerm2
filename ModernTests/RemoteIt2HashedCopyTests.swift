//
//  RemoteIt2HashedCopyTests.swift
//  iTerm2 ModernTests
//
//  The remote it2 keeps the established ~/.iterm2/it2.<hash>.py name, the same
//  path the shell-integration scripts materialize their embedded copy to, so
//  the uploaded copy and the materialized one agree instead of competing.
//
//  The bundle cannot hold that name: it changes whenever it2.py changes, and
//  each change would need a fresh Xcode file reference. TarJob derives a remote
//  entry's name from the source's path relative to its local base, so a
//  hash-named copy made on the way out produces the right remote name while the
//  bundle keeps one stable it2.py.
//

import XCTest
@testable import iTerm2SharedARC

final class RemoteIt2HashedCopyTests: XCTestCase {
    private var dir: URL!
    private var source: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("it2copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        source = dir.appendingPathComponent("it2.py")
        try "print('hi')\n".write(to: source, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func cacheDir() -> URL {
        return dir.appendingPathComponent("cache")
    }

    func testCopyIsNamedByTheHashAndHasTheSameContents() throws {
        let url = try XCTUnwrap(iTermRemoteIt2.hashedCopyURL(source: source,
                                                             hash: "abc123",
                                                             cacheDirectory: cacheDir()))
        XCTAssertEqual(url.lastPathComponent, "it2.abc123.py",
                       "the remote name comes from this basename")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "print('hi')\n")
    }

    // The upload happens per connection, so this runs often. A copy already in place must be
    // reused rather than rewritten, and reusing it must not depend on the bundle still being
    // readable.
    func testAnExistingCopyIsReused() throws {
        let first = try XCTUnwrap(iTermRemoteIt2.hashedCopyURL(source: source,
                                                               hash: "abc123",
                                                               cacheDirectory: cacheDir()))
        let marker = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: first.path)

        let second = try XCTUnwrap(iTermRemoteIt2.hashedCopyURL(source: source,
                                                                hash: "abc123",
                                                                cacheDirectory: cacheDir()))
        XCTAssertEqual(first, second)
        let mtime = try FileManager.default.attributesOfItem(atPath: second.path)[.modificationDate] as? Date
        XCTAssertEqual(mtime, marker, "an existing copy must be reused, not rewritten")
    }

    // A new build changes the hash, so both copies coexist. Nothing may delete the other: two
    // iTerm2 builds can be uploading to the same host, and each needs its own.
    func testADifferentHashMakesASecondCopy() throws {
        let old = try XCTUnwrap(iTermRemoteIt2.hashedCopyURL(source: source,
                                                             hash: "oldhash",
                                                             cacheDirectory: cacheDir()))
        let new = try XCTUnwrap(iTermRemoteIt2.hashedCopyURL(source: source,
                                                             hash: "newhash",
                                                             cacheDirectory: cacheDir()))
        XCTAssertNotEqual(old, new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path),
                      "the previous build's copy must survive")
    }

    // Staging goes in this instance's dot dir, never /tmp: that is shared by every user on the
    // machine, so a copy there both leaks what is being uploaded and may not be writable.
    func testStagingLivesInTheDotDirNotTmp() throws {
        let staging = try XCTUnwrap(iTermRemoteIt2.stagingDirectory())
        let dotDir = try XCTUnwrap(FileManager.default.homeDirectoryDotDir())
        XCTAssertTrue(staging.path.hasPrefix(dotDir), "got \(staging.path), dot dir \(dotDir)")
        XCTAssertFalse(staging.path.hasPrefix("/tmp"))
        XCTAssertFalse(staging.path.hasPrefix("/private/tmp"))
    }

    // The temporary the copy is written through must be a sibling, so it inherits the same
    // directory's permissions and the move into place is a rename rather than a cross-device
    // copy.
    func testTemporaryIsASiblingOfTheFinalCopy() throws {
        let url = try XCTUnwrap(iTermRemoteIt2.hashedCopyURL(source: source,
                                                             hash: "sibling",
                                                             cacheDirectory: cacheDir()))
        XCTAssertEqual(url.deletingLastPathComponent().path, cacheDir().path)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: cacheDir().path)) ?? []
        XCTAssertEqual(leftovers, ["it2.sibling.py"], "no temporary left behind: \(leftovers)")
    }

    // MARK: - Where the uploads land

    // Got this wrong once: destinationBase is <home>/.iterm2/shell-integration, not <home>, so
    // deriving the dot dir with one deletingLastPathComponent too few produced
    // <home>/.iterm2/.iterm2. The remote paths are the contract with the shell scripts (which
    // materialize to ~/.iterm2/it2.<hash>.py) and with the injected PATH (~/.iterm2/bin), so
    // pin them.
    func testIt2FilesLandInTheDotDirAndItsBin() throws {
        let dotIterm2 = URL(fileURLWithPath: "/$HOME/.iterm2")
        let files = ShellIntegrationInjector.instance.it2Files(dotIterm2: dotIterm2)
        let destinations = Set(files.values.map { $0.path })
        XCTAssertTrue(destinations.contains("/$HOME/.iterm2"),
                      "the interpreter goes beside what the scripts materialize: \(destinations)")
        XCTAssertTrue(destinations.contains("/$HOME/.iterm2/bin"),
                      "the wrapper goes where PATH points: \(destinations)")
        XCTAssertFalse(destinations.contains { $0.contains(".iterm2/.iterm2") },
                       "doubled dot dir: \(destinations)")
    }

    // TarJob names the remote entry by the LOCAL basename, so the staged names ARE the remote
    // names. The wrapper must arrive as "it2", not "it2-remote".
    func testStagedNamesAreTheRemoteNames() throws {
        let files = ShellIntegrationInjector.instance.it2Files(
            dotIterm2: URL(fileURLWithPath: "/$HOME/.iterm2"))
        let byDestination = Dictionary(uniqueKeysWithValues: files.map { ($1.path, $0.lastPathComponent) })
        XCTAssertEqual(byDestination["/$HOME/.iterm2/bin"], "it2")
        XCTAssertEqual(byDestination["/$HOME/.iterm2"], "it2.\(iTermRemoteIt2.bundledPyHash).py")
    }

    func testTheWrapperIsStagedExecutable() throws {
        let wrapper = try XCTUnwrap(Bundle(for: PTYSession.self).path(forResource: "it2-remote",
                                                                     ofType: nil))
        let staged = try XCTUnwrap(iTermRemoteIt2.stagedWrapper(source: URL(fileURLWithPath: wrapper)))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: staged.path),
                      "tar preserves the mode, so it has to be right before we tar it")
    }

    func testMissingSourceYieldsNil() {
        XCTAssertNil(iTermRemoteIt2.hashedCopyURL(source: dir.appendingPathComponent("absent.py"),
                                                  hash: "abc123",
                                                  cacheDirectory: cacheDir()))
    }
}
