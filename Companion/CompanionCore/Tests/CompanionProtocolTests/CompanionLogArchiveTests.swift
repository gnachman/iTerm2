//
//  CompanionLogArchiveTests.swift
//  CompanionCore
//
//  The log-emailing archive: many text files must collapse into one valid,
//  CRC-clean .zip that round-trips byte-for-byte. Where the platform provides
//  /usr/bin/unzip (the macOS test host) we validate against a real ZIP reader,
//  which independently checks each entry's CRC; everywhere we assert the
//  archive is well-formed and that compression actually shrinks text.
//

import XCTest
@testable import CompanionProtocol

final class CompanionLogArchiveTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompanionLogArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ data: Data) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testArchiveRoundTripsEveryFile() throws {
        // A compressible text file, an empty file, and a varied-byte file, so
        // every kind of entry is checked to round-trip through the system zipper.
        let files = [
            try write("a.log", Data(String(repeating: "diagnostic line 42\n", count: 5000).utf8)),
            try write("empty.log", Data()),
            try write("c.log", Data((0..<40_000).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761) }))
        ]
        let originals = try files.reduce(into: [String: Data]()) {
            $0[$1.lastPathComponent] = try Data(contentsOf: $1)
        }

        let archive = dir.appendingPathComponent("out.zip")
        try CompanionLogArchive.write(files: files, to: archive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        try assertLocalHeaderSignature(archive)

        let extracted = try unzip(archive)
        XCTAssertEqual(Set(extracted.keys), Set(originals.keys), "every file survived")
        for (name, data) in originals {
            XCTAssertEqual(extracted[name], data, "\(name) round-tripped byte-for-byte")
        }
    }

    func testCompressibleTextShrinks() throws {
        let text = Data(String(repeating: "the quick brown fox\n", count: 10_000).utf8)
        let file = try write("big.log", text)
        let archive = dir.appendingPathComponent("small.zip")
        try CompanionLogArchive.write(files: [file], to: archive)

        let archiveSize = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(archiveSize, 0)
        XCTAssertLessThan(archiveSize, text.count / 2, "repetitive text should compress well past 2x")
    }

    func testDuplicateBasenamesAreBothArchived() throws {
        // Legacy unlabeled files can share a basename across the app and NSE
        // directories; neither must be silently dropped on the name collision.
        let dirA = dir.appendingPathComponent("app", isDirectory: true)
        let dirB = dir.appendingPathComponent("nse", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let a = dirA.appendingPathComponent("2026-07-01_12-00-00.log")
        let b = dirB.appendingPathComponent("2026-07-01_12-00-00.log")
        try Data("from the app directory\n".utf8).write(to: a)
        try Data("from the nse directory\n".utf8).write(to: b)

        let archive = dir.appendingPathComponent("dupes.zip")
        try CompanionLogArchive.write(files: [a, b], to: archive)

        let extracted = try unzip(archive)
        XCTAssertEqual(extracted.count, 2, "both files archived under distinct names, neither dropped")
        let contents = Set(extracted.values)
        XCTAssertTrue(contents.contains(Data("from the app directory\n".utf8)))
        XCTAssertTrue(contents.contains(Data("from the nse directory\n".utf8)))
    }

    func testStagedArchiveSurvivesSourceDeletion() throws {
        // The delete-logs-while-emailing race: once a file is staged (hard
        // linked), the zip must still contain it even if the original is deleted
        // immediately after staging.
        let a = try write("a.log", Data("alpha contents\n".utf8))
        let staged = try CompanionLogArchive.stage(files: [a], folderName: "logs")
        try FileManager.default.removeItem(at: a)   // original gone after staging

        let archive = dir.appendingPathComponent("survives.zip")
        try CompanionLogArchive.zip(stagedDirectory: staged, to: archive)

        let extracted = try unzip(archive)
        XCTAssertEqual(extracted["a.log"], Data("alpha contents\n".utf8),
                       "hard-linked staging preserved the file past the source deletion")
    }

    func testUnreadableFilesAreSkipped() throws {
        let good = try write("good.log", Data("kept\n".utf8))
        let missing = dir.appendingPathComponent("does-not-exist.log")
        let archive = dir.appendingPathComponent("skip.zip")
        try CompanionLogArchive.write(files: [missing, good], to: archive)

        let extracted = try unzip(archive)
        XCTAssertEqual(Set(extracted.keys), ["good.log"])
    }

    func testNothingToArchiveThrowsAndLeavesNoFile() throws {
        let archive = dir.appendingPathComponent("nothing.zip")
        let missing = dir.appendingPathComponent("nope.log")
        XCTAssertThrowsError(try CompanionLogArchive.write(files: [missing], to: archive)) { error in
            XCTAssertEqual(error as? CompanionLogArchive.ArchiveError, .nothingToArchive)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path),
                       "a failed write leaves no partial archive")
    }

    func testNothingToArchiveClearsAStalePriorArchive() throws {
        // The app reuses one fixed archive path, so a nothing-to-archive write
        // must clear a previous run's zip rather than leave it to be attached.
        let archive = dir.appendingPathComponent("reused.zip")
        try Data("stale archive from a previous run".utf8).write(to: archive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

        let missing = dir.appendingPathComponent("gone.log")
        XCTAssertThrowsError(try CompanionLogArchive.write(files: [missing], to: archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path),
                       "the stale archive was removed")
    }

    // MARK: - helpers

    private func assertLocalHeaderSignature(_ url: URL) throws {
        let head = try Data(contentsOf: url).prefix(4)
        XCTAssertEqual(Array(head), [0x50, 0x4b, 0x03, 0x04], "starts with the ZIP local-file-header magic")
    }

    /// Extract with the system unzip (which verifies each entry's CRC) and return
    /// name -> contents. Skipped where Process/unzip are unavailable.
    private func unzip(_ archive: URL) throws -> [String: Data] {
        #if os(macOS)
        let out = dir.appendingPathComponent("extracted-\(UUID().uuidString)", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", archive.path, "-d", out.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip validated the archive (CRC-clean)")

        // The system zip nests the files under a top-level folder, so walk the
        // tree and key by file name rather than reading a flat directory.
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: out, includingPropertiesForKeys: [.isRegularFileKey])
        while let item = enumerator?.nextObject() as? URL {
            if try item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[item.lastPathComponent] = try Data(contentsOf: item)
            }
        }
        return result
        #else
        throw XCTSkip("unzip is only available on the macOS test host")
        #endif
    }
}
