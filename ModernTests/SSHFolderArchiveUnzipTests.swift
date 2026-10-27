//
//  SSHFolderArchiveUnzipTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

// F-921: downloading a folder `sub` through Download Files… gave `<destination>/sub/sub/in.txt`.
// The remote archive holds `sub/…`, and it was unzipped into the folder itself.
@MainActor
final class SSHFolderArchiveUnzipTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // Makes an archive laid out like the framer's: every entry is under `folderName/`.
    private func makeArchive(folderName: String) throws -> URL {
        let source = directory.appendingPathComponent("source")
        let folder = source.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"),
                                                withIntermediateDirectories: true)
        try Data("inner".utf8).write(to: folder.appendingPathComponent("in.txt"))
        try Data("deep".utf8).write(to: folder.appendingPathComponent("nested/deep.txt"))
        let zip = directory.appendingPathComponent("archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-q", "-r", zip.path, folderName]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }

    func testFolderContentsGoDirectlyInDestination() async throws {
        let zip = try makeArchive(folderName: "sub")
        let destination = directory.appendingPathComponent("out/sub")

        try await Conductor.unzipFolderArchive(zip, folderName: "sub", to: destination)

        let fileManager = FileManager.default
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("in.txt"), encoding: .utf8), "inner")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("nested/deep.txt"), encoding: .utf8), "deep")
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("sub").path))
        // Nothing is left beside it.
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path), ["sub"])
    }

    func testExistingFilesInDestinationAreReplacedOrKept() async throws {
        let zip = try makeArchive(folderName: "sub")
        let destination = directory.appendingPathComponent("out/sub")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("in.txt"))
        try Data("other".utf8).write(to: destination.appendingPathComponent("other.txt"))

        try await Conductor.unzipFolderArchive(zip, folderName: "sub", to: destination)

        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("in.txt"), encoding: .utf8), "inner")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("other.txt"), encoding: .utf8), "other")
    }

    // An empty folder's archive has no entries, and unzip fails on that.
    func testEmptyArchiveMakesEmptyFolder() async throws {
        let zip = directory.appendingPathComponent("empty.zip")
        // End of central directory record with no entries, as Python's zipfile writes it.
        var bytes: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        bytes += [UInt8](repeating: 0, count: 18)
        try Data(bytes).write(to: zip)
        let destination = directory.appendingPathComponent("out/sub")

        try await Conductor.unzipFolderArchive(zip, folderName: "sub", to: destination)

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
    }

    func testBadArchiveThrows() async throws {
        let zip = directory.appendingPathComponent("bad.zip")
        try Data("not a zip".utf8).write(to: zip)
        let destination = directory.appendingPathComponent("out/sub")
        do {
            try await Conductor.unzipFolderArchive(zip, folderName: "sub", to: destination)
            XCTFail("Expected an error")
        } catch {
        }
        // The staging folder isn't left behind.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path), [])
    }
}
