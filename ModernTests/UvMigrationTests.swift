//
//  UvMigrationTests.swift
//  ModernTests
//
//  Phase 3 of the uv Python-runtime migration. When existing legacy full-env
//  scripts are migrated to uv, most keep their pinned Python minor, but a few
//  (3.7, which python-build-standalone cannot provide) are bumped to 3.9. Those
//  forced bumps are surfaced to the user in one consolidated, suppressible warning.
//  See docs/uv-python-runtime-migration.md (Phase 3).
//

import XCTest
@testable import iTerm2SharedARC

final class UvMigrationTests: XCTestCase {
    func testForcedRemapsOnlyIncludesBumpedScripts() {
        let requested = ["Old": "3.7", "Keeps": "3.10", "AlsoOld": "3.7"]
        let available = ["3.9", "3.10", "3.11"]
        let remaps = iTermUvMigration.forcedRemaps(requestedVersionsByScript: requested, available: available)
        // Only the two 3.7 scripts are bumped; the 3.10 one is preserved silently.
        XCTAssertEqual(remaps.map { $0.scriptName }, ["AlsoOld", "Old"])  // sorted by name
        XCTAssertTrue(remaps.allSatisfy { $0.fromVersion == "3.7" && $0.toVersion == "3.9" })
    }

    func testNoRemapsWhenAllVersionsAvailable() {
        let requested = ["A": "3.9", "B": "3.11.2"]
        let remaps = iTermUvMigration.forcedRemaps(requestedVersionsByScript: requested,
                                                   available: ["3.9", "3.10", "3.11"])
        XCTAssertTrue(remaps.isEmpty)
    }

    func testConsolidatedWarningTextListsEachScriptAndCaveat() {
        let remaps = [iTermUvPythonRemap(scriptName: "Alpha", fromVersion: "3.7", toVersion: "3.9"),
                      iTermUvPythonRemap(scriptName: "Beta", fromVersion: "3.7", toVersion: "3.9")]
        let text = iTermUvMigration.consolidatedWarningText(remaps: remaps)
        XCTAssertTrue(text.contains("Alpha"))
        XCTAssertTrue(text.contains("Beta"))
        XCTAssertTrue(text.contains("3.7"))
        XCTAssertTrue(text.contains("3.9"))
        // The compatibility caveat must be present so the user knows scripts may break.
        XCTAssertTrue(text.lowercased().contains("compat"))
        // House style: no straight double quotes, no em dashes.
        XCTAssertFalse(text.contains("\""))
        XCTAssertFalse(text.contains("\u{2014}"))
    }

    func testWarningTextForSingleScriptReadsNaturally() {
        let text = iTermUvMigration.consolidatedWarningText(
            remaps: [iTermUvPythonRemap(scriptName: "Solo", fromVersion: "3.7", toVersion: "3.9")])
        XCTAssertTrue(text.contains("Solo"))
        XCTAssertTrue(text.contains("3.9"))
    }

    func testPendingWarningNonNilForUnavailablePin() {
        let text = iTermUvMigration.pendingVersionBumpWarning(requestedVersionsByScript: ["Old": "3.7"])
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("Old") ?? false)
    }

    func testPendingWarningNilWhenNothingBumped() {
        XCTAssertNil(iTermUvMigration.pendingVersionBumpWarning(
            requestedVersionsByScript: ["A": "3.10", "B": "3.12"]))
    }

    // MARK: - Selecting the scripts an "Upgrade Now" button should migrate

    func testScriptsNeedingBumpReturnsOnlyUnavailablePinsSortedByName() {
        let scripts = [
            iTermUvLegacyScript(relativeName: "Keeps", containerPath: "/s/Keeps",
                                requestedVersion: "3.10", dependencies: ["iterm2"]),
            iTermUvLegacyScript(relativeName: "Old", containerPath: "/s/Old",
                                requestedVersion: "3.7", dependencies: ["iterm2"]),
            iTermUvLegacyScript(relativeName: "AlsoOld", containerPath: "/s/AlsoOld",
                                requestedVersion: "3.7", dependencies: []),
        ]
        let bumped = iTermUvMigration.scriptsNeedingBump(scripts, available: ["3.9", "3.10", "3.11"])
        // Only the two 3.7 scripts are bumped, sorted by name; the 3.10 one is preserved.
        XCTAssertEqual(bumped.map { $0.relativeName }, ["AlsoOld", "Old"])
        // The full descriptor is carried through so the caller can migrate it directly.
        XCTAssertEqual(bumped.first?.containerPath, "/s/AlsoOld")
    }

    func testScriptsNeedingBumpEmptyWhenAllAvailable() {
        let scripts = [
            iTermUvLegacyScript(relativeName: "A", containerPath: "/s/A",
                                requestedVersion: "3.10", dependencies: ["iterm2"]),
            iTermUvLegacyScript(relativeName: "B", containerPath: "/s/B",
                                requestedVersion: "3.11.2", dependencies: nil),
        ]
        XCTAssertTrue(iTermUvMigration.scriptsNeedingBump(scripts, available: ["3.9", "3.10", "3.11"]).isEmpty)
    }

    // MARK: - Rebuild-with-rollback file operations

    private func makeContainer() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("uvmig-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ path: String, _ contents: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testBackupMovesLegacyEnvironmentAside() throws {
        let c = try makeContainer()
        try write((c as NSString).appendingPathComponent("iterm2env/versions/3.7.0/bin/python3"), "legacy")
        try iTermUvMigration.backUpLegacyEnvironment(container: c)
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent("iterm2env")))
        XCTAssertEqual(
            try String(contentsOfFile: (c as NSString).appendingPathComponent("saved-iterm2env/versions/3.7.0/bin/python3")),
            "legacy")
    }

    func testBackupTreatsSavedAsTheGoodCopyWhenBothExist() throws {
        // A leftover saved-iterm2env alongside an iterm2env means a legacy runtime
        // upgrade was interrupted: saved-iterm2env is the GOOD copy and iterm2env is a
        // broken partial. Backing up must preserve the good copy and discard the
        // partial, not the reverse (which would lose the user's working environment if
        // the uv migration then failed).
        let c = try makeContainer()
        try write((c as NSString).appendingPathComponent("saved-iterm2env/good"), "good")
        try write((c as NSString).appendingPathComponent("iterm2env/partial"), "partial")
        try iTermUvMigration.backUpLegacyEnvironment(container: c)
        let fm = FileManager.default
        // The good env is moved aside as the backup for the migration.
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent("iterm2env")))
        XCTAssertEqual(
            try String(contentsOfFile: (c as NSString).appendingPathComponent("saved-iterm2env/good")), "good")
        // The broken partial is gone, not preserved as the backup.
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent("saved-iterm2env/partial")))
    }

    func testRestoreUndoesAFailedMigration() throws {
        let c = try makeContainer()
        // State after backup + a partial uv provision that then failed.
        try write((c as NSString).appendingPathComponent("saved-iterm2env/versions/3.7.0/bin/python3"), "legacy")
        try write((c as NSString).appendingPathComponent(".venv/bin/python"), "partial")
        try write((c as NSString).appendingPathComponent("python-runtime.json"), "{}")

        try iTermUvMigration.restoreLegacyEnvironment(container: c)

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent(".venv")))
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent("python-runtime.json")))
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent("saved-iterm2env")))
        XCTAssertEqual(
            try String(contentsOfFile: (c as NSString).appendingPathComponent("iterm2env/versions/3.7.0/bin/python3")),
            "legacy")
    }

    func testBackupRecoversOrphanedBackupInsteadOfDeletingIt() throws {
        // An interrupted prior migration left the user's ONLY environment at
        // saved-iterm2env (no iterm2env), plus a partial .venv. Backing up again must
        // not delete that backup.
        let c = try makeContainer()
        try write((c as NSString).appendingPathComponent("saved-iterm2env/versions/3.7.0/bin/python3"),
                  "the-only-copy")
        try write((c as NSString).appendingPathComponent(".venv/bin/python"), "partial")

        try iTermUvMigration.backUpLegacyEnvironment(container: c)

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: (c as NSString).appendingPathComponent(".venv")),
                       "the partial venv should be cleared")
        let savedPy = (c as NSString).appendingPathComponent("saved-iterm2env/versions/3.7.0/bin/python3")
        let legacyPy = (c as NSString).appendingPathComponent("iterm2env/versions/3.7.0/bin/python3")
        let survived = (try? String(contentsOfFile: savedPy)) ?? (try? String(contentsOfFile: legacyPy))
        XCTAssertEqual(survived, "the-only-copy", "the user's environment must not be lost")
    }

    func testBackupThenRestoreRoundTripsPreservesLegacy() throws {
        let c = try makeContainer()
        let legacyFile = (c as NSString).appendingPathComponent("iterm2env/versions/3.7.0/bin/python3")
        try write(legacyFile, "original")
        try iTermUvMigration.backUpLegacyEnvironment(container: c)
        try iTermUvMigration.restoreLegacyEnvironment(container: c)
        XCTAssertEqual(try String(contentsOfFile: legacyFile), "original")
    }

    func testBackupIsNoOpWhenNoLegacyEnvironment() throws {
        let c = try makeContainer()
        XCTAssertNoThrow(try iTermUvMigration.backUpLegacyEnvironment(container: c))
        XCTAssertFalse(FileManager.default.fileExists(atPath: (c as NSString).appendingPathComponent("saved-iterm2env")))
    }

    func testDiscardBackupRemovesSaved() throws {
        let c = try makeContainer()
        try write((c as NSString).appendingPathComponent("saved-iterm2env/x"), "y")
        // The removal happens on a background queue, so wait for the completion rather
        // than asserting synchronously (which would race).
        let removed = expectation(description: "backup removed")
        iTermUvMigration.discardLegacyBackup(container: c) {
            removed.fulfill()
        }
        wait(for: [removed], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: (c as NSString).appendingPathComponent("saved-iterm2env")))
    }
}
