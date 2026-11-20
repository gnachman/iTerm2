//
//  PlistNULCodecTests.swift
//  ModernTests
//
//  Issue 13224: a profile whose hotkey was recorded as Ctrl+Space stores a NUL
//  as its hotkey characters. XML property lists can't hold a NUL, so saving
//  settings to a custom folder and exporting all settings both failed.
//

import XCTest
@testable import iTerm2SharedARC

final class PlistNULCodecTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlistNULCodecTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private let nul = "\u{0}"

    // Shaped like the settings attached to the issue.
    private var prefsWithNUL: NSDictionary {
        return [
            "New Bookmarks": [
                ["Name": "default",
                 "HotKey Characters": nul,
                 "HotKey Characters Ignoring Modifiers": " ",
                 "HotKey Key Code": 49,
                 "HotKey Modifier Flags": 262144,
                 "Has Hotkey": false],
                ["Name": "tmux",
                 "Session Hotkey": ["characters": "a\(nul)b\(nul)\(nul)c\(nul)",
                                    "charactersIgnoringModifiers": "2",
                                    "keyCode": 19,
                                    "modifiers": 262144]]
            ],
            "Some Strings": ["first": "\(nul)leading", "last": "trailing\(nul)", "none": "none", "empty": ""],
            "A List": ["none", ""],
            "A Number": 3.5,
            "A Bool": true,
            "Some Data": Data([0, 1, 2]),
        ] as NSDictionary
    }

    private func xmlSerializes(_ object: Any) -> Bool {
        return (try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)) != nil
    }

    func testRawPrefsWithNULDoNotSerializeAsXML() {
        // Guards the premise: if Foundation ever learns to write NUL, this codec is unnecessary.
        XCTAssertFalse(xmlSerializes(prefsWithNUL))
    }

    func testEncodedPrefsSerializeAsXML() {
        XCTAssertTrue(xmlSerializes(PlistNULCodec.encoded(prefsWithNUL)))
    }

    func testRoundTripThroughXML() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: PlistNULCodec.encoded(prefsWithNUL),
                                                      format: .xml,
                                                      options: 0)
        let readBack = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary)
        XCTAssertEqual(PlistNULCodec.decoded(readBack), prefsWithNUL)
    }

    func testEncodedForm() {
        let encoded = PlistNULCodec.encoded(["k": "a\(nul)\(nul)b", "other": "x"] as NSDictionary)
        XCTAssertEqual(encoded, ["k": "ab",
                                 "other": "x",
                                 PlistNULCodec.sidecarKey: ["k": ["a", "", "b"]]] as NSDictionary)

        let justNUL = PlistNULCodec.encoded(["k": nul] as NSDictionary)
        XCTAssertEqual(justNUL, ["k": "", PlistNULCodec.sidecarKey: ["k": ["", ""]]] as NSDictionary)
    }

    func testValuesWithoutNULAreReturnedUnchanged() {
        let prefs = ["Name": "x", "List": ["a", "b"], "Nested": ["k": 1]] as NSDictionary
        XCTAssertTrue(PlistNULCodec.encoded(prefs) === prefs)
        XCTAssertTrue(PlistNULCodec.decoded(prefs) === prefs)
    }

    // An older version that edits the value keeps the sidecar but not the original; its edit wins.
    func testStaleSidecarIsIgnored() {
        let edited = ["k": "edited", PlistNULCodec.sidecarKey: ["k": ["", ""]]] as NSDictionary
        XCTAssertEqual(PlistNULCodec.decoded(edited), ["k": "edited"] as NSDictionary)
    }

    func testStaleSidecarIsNotCarriedForward() {
        let local = ["k": "edited", PlistNULCodec.sidecarKey: ["k": ["", ""]]] as NSDictionary
        XCTAssertEqual(PlistNULCodec.encoded(local), ["k": "edited"] as NSDictionary)

        let localWithNUL = ["k": "edited",
                            "j": "\(nul)",
                            PlistNULCodec.sidecarKey: ["k": ["", ""]]] as NSDictionary
        XCTAssertEqual(PlistNULCodec.encoded(localWithNUL),
                       ["k": "edited", "j": "", PlistNULCodec.sidecarKey: ["j": ["", ""]]] as NSDictionary)
    }

    func testMalformedSidecarsAreRemoved() {
        let malformed: [NSDictionary] = [
            ["k": "x", PlistNULCodec.sidecarKey: "not a dictionary"],
            ["k": "x", PlistNULCodec.sidecarKey: ["k": ["x"]]],
            ["k": "x", PlistNULCodec.sidecarKey: ["k": "x"]],
            ["k": "x", PlistNULCodec.sidecarKey: ["k": ["x", 1]]],
            ["k": "x", PlistNULCodec.sidecarKey: ["missing": ["x", ""]]],
            ["k": 1, PlistNULCodec.sidecarKey: ["k": ["1", ""]]],
        ]
        for dictionary in malformed {
            XCTAssertEqual(PlistNULCodec.decoded(dictionary), ["k": dictionary["k"]!] as NSDictionary)
        }
    }

    func testStringsWithNULInArraysLoseTheirNULs() {
        let prefs = ["List": ["a\(nul)b", "c"]] as NSDictionary
        let encoded = PlistNULCodec.encoded(prefs)
        XCTAssertTrue(xmlSerializes(encoded))
        XCTAssertEqual(PlistNULCodec.decoded(encoded), ["List": ["ab", "c"]] as NSDictionary)
    }

    // Saving to the custom folder then reading it back must give exactly what was saved. Otherwise
    // the next save would think the folder changed since launch and ask to overwrite it.
    func testRemotePreferencesSaveAndLoad() throws {
        let path = tempDirectory.appendingPathComponent("com.googlecode.iterm2.plist").path
        let saved = try XCTUnwrap(iTermRemotePreferences.savePrefs(prefsWithNUL as! [AnyHashable: Any],
                                                                   toFile: path))
        let loaded = try XCTUnwrap(iTermRemotePreferences.prefs(fromFile: path))
        XCTAssertEqual(loaded as NSDictionary, saved as NSDictionary)
        XCTAssertEqual(loaded as NSDictionary, prefsWithNUL)

        // The file on disk is XML.
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("<?xml"))
        XCTAssertTrue(contents.contains(PlistNULCodec.sidecarKey))
    }

    // A version of iTerm2 without the codec reads a plain string with the NULs removed and ignores
    // the sidecar.
    func testOlderReadersSeeAString() throws {
        let path = tempDirectory.appendingPathComponent("old-reader.plist").path
        XCTAssertNotNil(iTermRemotePreferences.savePrefs(prefsWithNUL as! [AnyHashable: Any], toFile: path))
        let raw = try XCTUnwrap(NSDictionary(contentsOfFile: path))
        let profiles = try XCTUnwrap(raw["New Bookmarks"] as? [NSDictionary])
        XCTAssertEqual(profiles[0]["HotKey Characters"] as? String, "")
        let sessionHotkey = try XCTUnwrap(profiles[1]["Session Hotkey"] as? NSDictionary)
        XCTAssertEqual(sessionHotkey["characters"] as? String, "abc")
        let shortcut = try XCTUnwrap(iTermShortcut(dictionary: sessionHotkey as! [AnyHashable: Any]))
        XCTAssertTrue(shortcut.isAssigned)
    }
}
