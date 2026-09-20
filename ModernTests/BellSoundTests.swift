//
//  BellSoundTests.swift
//  iTerm2 ModernTests
//
//  Pins how a profile’s KEY_BELL_SOUND string is interpreted. The value is
//  overloaded on purpose — empty means the system alert sound, a bare word
//  names an installed sound, and anything starting with a slash or tilde is a
//  file — so the classification is the part most likely to break silently.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class BellSoundTests: XCTestCase {

    // MARK: - Classifying a stored value

    func test_emptyAndNil_meanTheSystemAlertSound() {
        XCTAssertEqual(iTermBellSound.source(of: nil), .systemAlert)
        XCTAssertEqual(iTermBellSound.source(of: ""), .systemAlert)
        XCTAssertEqual(iTermBellSound.source(of: iTermBellSound.systemAlertValue), .systemAlert)
    }

    func test_bareWord_namesAnInstalledSound() {
        XCTAssertEqual(iTermBellSound.source(of: "Glass"), .named("Glass"))
        // A name with spaces is still a name, not a relative path.
        XCTAssertEqual(iTermBellSound.source(of: "My Sound"), .named("My Sound"))
    }

    func test_leadingSlashOrTilde_namesAFile() {
        XCTAssertEqual(iTermBellSound.source(of: "/tmp/chime.m4a"),
                       .file(URL(fileURLWithPath: "/tmp/chime.m4a")))
        let expanded = ("~/Sounds/chime.m4a" as NSString).expandingTildeInPath
        XCTAssertEqual(iTermBellSound.source(of: "~/Sounds/chime.m4a"),
                       .file(URL(fileURLWithPath: expanded)))
    }

    // MARK: - Display names

    func test_displayName_stripsPathAndExtension() {
        XCTAssertEqual(iTermBellSound.displayName(forProfileValue: "/tmp/sounds/chime.m4a"), "chime")
        XCTAssertEqual(iTermBellSound.displayName(forProfileValue: "Glass"), "Glass")
    }

    func test_displayName_isEmptyForTheSystemAlertSound() {
        // The caller titles this one itself because the title is localized.
        XCTAssertEqual(iTermBellSound.displayName(forProfileValue: ""), "")
        XCTAssertEqual(iTermBellSound.displayName(forProfileValue: nil), "")
    }

    // MARK: - Playability

    func test_systemAlertSound_isAlwaysPlayable() {
        XCTAssertTrue(iTermBellSound.isPlayable(profileValue: ""))
        XCTAssertTrue(iTermBellSound.isPlayable(profileValue: nil))
    }

    func test_existingFile_isPlayable() throws {
        let url = try temporaryFile(named: "bell.aiff")
        XCTAssertTrue(iTermBellSound.isPlayable(profileValue: url.path))
    }

    func test_missingFileOrName_isNotPlayable() {
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: "/nonexistent/iTerm2BellSoundTest.aiff"))
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: "iTerm2BellSoundTestNoSuchSound"))
    }

    // MARK: - Turning a chosen file into a stored value

    func test_fileOutsideSoundsFolders_isStoredByPath() throws {
        let url = try temporaryFile(named: "bell.aiff")
        XCTAssertEqual(iTermBellSound.profileValue(for: url),
                       url.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func test_fileInASoundsFolder_isStoredByName() throws {
        // A name survives a move to a Mac whose home directory is elsewhere, so a
        // sound that NSSound can find by name should never be stored as a path.
        let glass = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: glass.path) &&
                          NSSound(named: "Glass") != nil,
                          "This Mac has no Glass system sound")
        XCTAssertEqual(iTermBellSound.profileValue(for: glass), "Glass")
    }

    // MARK: - The installed sounds

    func test_installedSoundNames_areUniqueSortedAndLoadable() {
        let names = iTermBellSound.installedSoundNames()
        XCTAssertEqual(names.count, Set(names).count, "a name should be listed once")
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        for name in names {
            XCTAssertNotNil(NSSound(named: name), "\(name) was listed but can’t be loaded")
        }
    }

    // MARK: - Helpers

    private func temporaryFile(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BellSoundTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }
}
