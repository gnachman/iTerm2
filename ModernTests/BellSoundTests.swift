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

    func test_audioFile_isPlayable() throws {
        let url = try temporaryFile(named: "bell.wav", contents: Self.wav())
        XCTAssertTrue(iTermBellSound.isPlayable(profileValue: url.path))
    }

    func test_missingFileOrName_isNotPlayable() {
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: "/nonexistent/iTerm2BellSoundTest.aiff"))
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: "iTerm2BellSoundTestNoSuchSound"))
    }

    func test_readableFileThatIsNotAudio_isNotPlayable() throws {
        // The player would fall back to the system alert sound for this, so Settings must
        // flag it rather than go by the file merely being readable.
        let url = try temporaryFile(named: "bell.wav", contents: Data("not audio".utf8))
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: url.path))
    }

    func test_fileChangedAfterLoading_isReloaded() throws {
        let url = try temporaryFile(named: "bell.wav", contents: Self.wav())
        XCTAssertTrue(iTermBellSound.isPlayable(profileValue: url.path))

        try Data("not audio".utf8).write(to: url)
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: url.path),
                       "a replaced file must not keep playing the sound loaded before")

        try Self.wav().write(to: url)
        XCTAssertTrue(iTermBellSound.isPlayable(profileValue: url.path))

        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(iTermBellSound.isPlayable(profileValue: url.path),
                       "a deleted file must not keep playing the sound loaded before")
    }

    // MARK: - Turning a chosen file into a stored value

    func test_fileOutsideSoundsFolders_isStoredByPath() throws {
        let sounds = try temporaryDirectory()
        let url = try temporaryFile(named: "bell.aiff")
        let catalog = iTermBellSound.Catalog(directories: [sounds.path])
        XCTAssertEqual(catalog.profileValue(for: url),
                       url.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func test_fileInASoundsFolder_isStoredByName() throws {
        // A name survives a move to a Mac whose home directory is elsewhere, so a
        // sound that NSSound can find by name should never be stored as a path.
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        let url = try file(named: "Chime.aiff", in: second)
        let catalog = iTermBellSound.Catalog(directories: [first.path, second.path])
        XCTAssertEqual(catalog.profileValue(for: url), "Chime")
    }

    func test_fileShadowedByAnEarlierSoundsFolder_isStoredByPath() throws {
        // NSSound takes the first folder that has the name, so storing the name would
        // play the other file.
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        let shadowing = try file(named: "Chime.aiff", in: first)
        let shadowed = try file(named: "Chime.aiff", in: second)
        let catalog = iTermBellSound.Catalog(directories: [first.path, second.path])
        XCTAssertEqual(catalog.profileValue(for: shadowed),
                       shadowed.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(catalog.profileValue(for: shadowing), "Chime")
    }

    func test_fileShadowedByADifferentExtension_isStoredByPath() throws {
        // Two files in one folder differing only in extension share a name, and which one
        // NSSound picks is not something to depend on.
        let sounds = try temporaryDirectory()
        let aiff = try file(named: "Chime.aiff", in: sounds)
        _ = try file(named: "Chime.wav", in: sounds)
        let catalog = iTermBellSound.Catalog(directories: [sounds.path])
        XCTAssertEqual(catalog.profileValue(for: aiff),
                       aiff.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func test_systemSound_isStoredByNameUnlessShadowed() throws {
        let glass = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: glass.path),
                          "This Mac has no Glass system sound")
        let catalog = iTermBellSound.Catalog(directories: iTermBellSound.soundDirectories)
        let shadowed = iTermBellSound.soundDirectories.dropLast().contains { directory in
            ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).contains {
                ($0 as NSString).deletingPathExtension == "Glass"
            }
        }
        XCTAssertEqual(catalog.profileValue(for: glass), shadowed ? glass.path : "Glass")
    }

    // MARK: - The installed sounds

    func test_catalog_listsEachAudioNameOnceInOrder() throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        _ = try file(named: "b.aiff", in: first)
        _ = try file(named: "a10.mp3", in: second)
        _ = try file(named: "a9.aiff", in: second)
        _ = try file(named: "b.aiff", in: second)
        _ = try file(named: "notes.txt", in: second)
        _ = try file(named: ".hidden.aiff", in: second)
        let catalog = iTermBellSound.Catalog(directories: [first.path, second.path, "/nonexistent"])
        XCTAssertEqual(catalog.names, ["a9", "a10", "b"])
    }

    func test_installedSoundNames_areUniqueAndSorted() {
        let names = iTermBellSound.Catalog(directories: iTermBellSound.soundDirectories).names
        XCTAssertEqual(names.count, Set(names).count, "a name should be listed once")
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BellSoundTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func temporaryFile(named name: String, contents: Data = Data()) throws -> URL {
        return try file(named: name, in: temporaryDirectory(), contents: contents)
    }

    private func file(named name: String, in directory: URL, contents: Data = Data()) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    // A tenth of a second of silence as 8 kHz, 8-bit mono PCM.
    private static func wav() -> Data {
        let samples = Data(repeating: 0x80, count: 800)
        func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var data = Data("RIFF".utf8)
        data += le32(UInt32(36 + samples.count))
        data += Data("WAVEfmt ".utf8)
        data += le32(16)           // fmt chunk size
        data += le16(1)            // PCM
        data += le16(1)            // channels
        data += le32(8000)         // sample rate
        data += le32(8000)         // byte rate
        data += le16(1)            // block align
        data += le16(8)            // bits per sample
        data += Data("data".utf8)
        data += le32(UInt32(samples.count))
        data += samples
        return data
    }
}
