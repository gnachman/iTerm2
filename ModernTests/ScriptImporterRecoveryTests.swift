//
//  ScriptImporterRecoveryTests.swift
//  ModernTests
//
//  Regression tests for the replace-import crash-recovery sweep, whose delete branch
//  once destroyed the user's only backup. The sweep must:
//    - RESTORE the original when the target is a symlink (a full-environment install
//      leaves Scripts/<name> as a symlink into a temp dir until it completes, and that
//      symlink can outlive a crash), because fileExistsAtPath would follow it and
//      wrongly conclude the replacement finished.
//    - DELETE the backup only when the target is a real, completed item.
//    - leave a coincidentally-named ".replacing-…" file (no valid UUID tail) untouched.
//    - remove orphaned ".installing-*" atomic-install staging dirs.
//

import XCTest
@testable import iTerm2SharedARC

final class ScriptImporterRecoveryTests: XCTestCase {
    private func makeDir() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("importrec-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func writeDir(_ path: String, tag: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try tag.write(toFile: (path as NSString).appendingPathComponent("tag"), atomically: true, encoding: .utf8)
    }

    private func backupName(_ scriptName: String) -> String {
        return ".replacing-\(scriptName)-\(UUID().uuidString)"
    }

    func testRestoresWhenTargetIsSymlink() throws {
        // The crash window: target is a symlink into a (surviving) temp dir. The install did
        // not complete, so the backup must be restored, not deleted.
        let scripts = try makeDir()
        let name = "my-script"
        let backup = (scripts as NSString).appendingPathComponent(backupName(name))
        try writeDir(backup, tag: "ORIGINAL")
        let temp = try makeDir()
        try writeDir((temp as NSString).appendingPathComponent("payload"), tag: "PARTIAL")
        try FileManager.default.createSymbolicLink(atPath: (scripts as NSString).appendingPathComponent(name),
                                                   withDestinationPath: (temp as NSString).appendingPathComponent("payload"))

        iTermScriptImporter.recoverStaleReplaceBackups(inDirectory: scripts)

        let restoredTag = (scripts as NSString).appendingPathComponent("\(name)/tag")
        XCTAssertEqual(try String(contentsOfFile: restoredTag, encoding: .utf8), "ORIGINAL")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup), "backup should be consumed by the restore")
        // The restore removes the leftover symlink before moving the backup into place.
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: (scripts as NSString).appendingPathComponent(name),
                                                     isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testDeletesBackupWhenTargetIsRealCompletedItem() throws {
        // The replacement completed (target is a real dir); the backup leaked (crash before
        // cleanup) and must be removed, not restored over the new install.
        let scripts = try makeDir()
        let name = "my-script"
        let backup = (scripts as NSString).appendingPathComponent(backupName(name))
        try writeDir(backup, tag: "ORIGINAL")
        try writeDir((scripts as NSString).appendingPathComponent(name), tag: "NEW")

        iTermScriptImporter.recoverStaleReplaceBackups(inDirectory: scripts)

        XCTAssertFalse(FileManager.default.fileExists(atPath: backup))
        let tag = (scripts as NSString).appendingPathComponent("\(name)/tag")
        XCTAssertEqual(try String(contentsOfFile: tag, encoding: .utf8), "NEW", "the completed install must be kept")
    }

    func testLeavesCoincidentallyNamedFileUntouched() throws {
        // A user file named ".replacing-…" without a valid UUID tail must not be treated as
        // our backup and renamed to a truncated garbage name.
        let scripts = try makeDir()
        let stray = (scripts as NSString).appendingPathComponent(".replacing-notes-and-more")
        try "keep me".write(toFile: stray, atomically: true, encoding: .utf8)

        iTermScriptImporter.recoverStaleReplaceBackups(inDirectory: scripts)

        XCTAssertTrue(FileManager.default.fileExists(atPath: stray))
        XCTAssertEqual(try String(contentsOfFile: stray, encoding: .utf8), "keep me")
    }

    func testRemovesOrphanedInstallStagingDir() throws {
        let scripts = try makeDir()
        let staging = (scripts as NSString).appendingPathComponent(".installing-my-script-\(UUID().uuidString)")
        try writeDir(staging, tag: "junk")

        iTermScriptImporter.recoverStaleReplaceBackups(inDirectory: scripts)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging))
    }
}
