//
//  iTermRecordingProfileSanitizerTests.swift
//  ModernTests
//
//  An Instant Replay (.itr) file embeds a profile that comes from whoever made
//  the file. Only settings that affect how the recording is drawn may survive;
//  anything that can run commands, touch files, or evaluate expressions must be
//  dropped before the replay session is created.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermRecordingProfileSanitizerTests: XCTestCase {
    private let red: [String: Any] = [
        "Red Component": 1.0,
        "Green Component": 0.0,
        "Blue Component": 0.0,
        "Alpha Component": 1.0,
        "Color Space": "sRGB",
    ]

    private func sanitize(_ profile: [String: Any]) -> [String: Any] {
        return iTermRecordingProfileSanitizer.sanitizedProfile(profile)
    }

    func testIdleScriptTriggerIsRemoved() {
        let trigger: [String: Any] = [
            "action": "ScriptTrigger",
            "parameter": "open -a Calculator",
            "regex": "",
            "matchType": 105,
        ]
        let result = sanitize([KEY_TRIGGERS: [trigger],
                               KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: true])
        XCTAssertNil(result[KEY_TRIGGERS])
        XCTAssertNil(result[KEY_TRIGGERS_USE_INTERPOLATED_STRINGS])
    }

    func testActionBearingKeysAreRemoved() {
        let untrusted: [String: Any] = [
            KEY_KEYBOARD_MAP: ["0x61-0x0": ["Action": 35, "Text": "open -a Calculator"]],
            KEY_TOUCHBAR_MAP: ["x": ["Action": 35, "Text": "open -a Calculator"]],
            KEY_BINDINGS: ["0x61-0x0": "iterm2.run_coprocess(command: \"x\")"],
            KEY_SMART_SELECTION_RULES: [["regex": ".*", "actions": [["action": 1, "parameter": "x"]]]],
            KEY_SEMANTIC_HISTORY: ["action": "command", "text": "open -a Calculator"],
            KEY_CUSTOM_COMMAND: "Yes",
            KEY_COMMAND_LINE: "open -a Calculator",
            KEY_INITIAL_TEXT: "open -a Calculator",
            KEY_SEND_CODE_WHEN_IDLE: true,
            KEY_IDLE_CODE: 13,
            KEY_ANSWERBACK_STRING: "x",
            KEY_BADGE_FORMAT: "\\(iterm2.run_coprocess(command: \"x\"))",
            KEY_TITLE_COMPONENTS: 0,
            KEY_STATUS_BAR_LAYOUT: ["components": []],
            KEY_SHOW_STATUS_BAR: true,
            KEY_AUTOLOG: true,
            KEY_LOGDIR: "/tmp",
            KEY_BACKGROUND_IMAGE_LOCATION: "/etc/passwd",
            KEY_BOUND_HOSTS: ["example.com"],
            KEY_SSH_CONFIG: ["x": "y"],
            KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY: true,
            KEY_JOBS: ["x"],
            KEY_SESSION_END_ACTION: 1,
            KEY_HAS_HOTKEY: true,
            KEY_DYNAMIC_PROFILE_PARENT_NAME: "x",
            "Some Future Key That Runs Commands": "x",
        ]
        let result = sanitize(untrusted)
        for key in untrusted.keys {
            XCTAssertNil(result[key], "\(key) should have been removed")
        }
    }

    func testRenderingKeysArePreserved() {
        let untrusted: [String: Any] = [
            KEY_FOREGROUND_COLOR: red,
            KEY_BACKGROUND_COLOR + COLORS_LIGHT_MODE_SUFFIX: red,
            KEY_ANSI_3_COLOR + COLORS_DARK_MODE_SUFFIX: red,
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: true,
            KEY_USE_BOLD_COLOR + COLORS_DARK_MODE_SUFFIX: true,
            KEY_MINIMUM_CONTRAST: 0.5,
            KEY_NORMAL_FONT: "Menlo-Regular 14",
            KEY_NON_ASCII_FONT: "Menlo-Regular 14",
            KEY_USE_NONASCII_FONT: true,
            KEY_HORIZONTAL_SPACING: 1.1,
            KEY_VERTICAL_SPACING: 1.2,
            KEY_CURSOR_TYPE: 1,
            KEY_TRANSPARENCY: 0.25,
            KEY_AMBIGUOUS_DOUBLE_WIDTH: true,
            KEY_UNICODE_VERSION: 9,
            KEY_USE_ACTIVE_PANE_BORDER + COLORS_LIGHT_MODE_SUFFIX: true,
            KEY_ANIMATE_MOVEMENT: true,
            KEY_TIMESTAMPS_VISIBLE: true,
            KEY_SHOW_OFFSCREEN_COMMANDLINE: false,
            KEY_UNLIMITED_SCROLLBACK: true,
            KEY_REDUCE_FLICKER: true,
        ]
        let result = sanitize(untrusted)
        for (key, value) in untrusted {
            XCTAssertEqual(result[key] as? NSObject, value as? NSObject, "\(key) should have been kept")
        }
    }

    func testAllowedKeyWithIllegalValueIsRemoved() {
        let result = sanitize([KEY_TRANSPARENCY: "not a number",
                               KEY_NORMAL_FONT: ["not": "a string"]])
        XCTAssertNil(result[KEY_TRANSPARENCY])
        XCTAssertNil(result[KEY_NORMAL_FONT])
    }

    // Old recordings may carry deprecated keys that still affect rendering.
    // They have no validators, so they are converted to their replacements.
    func testDeprecatedRenderingKeysAreMigrated() {
        let result = sanitize([KEY_USE_HFS_PLUS_MAPPING: true,
                               KEY_DISABLE_BOLD: true])
        XCTAssertEqual(result[KEY_UNICODE_NORMALIZATION] as? Int,
                       Int(iTermUnicodeNormalization.hfsPlus.rawValue))
        XCTAssertEqual(result[KEY_USE_BOLD_FONT] as? Bool, false)
        XCTAssertNil(result[KEY_USE_HFS_PLUS_MAPPING])
        XCTAssertNil(result[KEY_DISABLE_BOLD])
    }

    func testDeprecatedKeysDoNotOverrideModernOnes() {
        let result = sanitize([KEY_USE_HFS_PLUS_MAPPING: true,
                               KEY_UNICODE_NORMALIZATION: Int(iTermUnicodeNormalization.NFC.rawValue),
                               KEY_DISABLE_BOLD: true,
                               KEY_USE_BOLD_FONT: true])
        XCTAssertEqual(result[KEY_UNICODE_NORMALIZATION] as? Int,
                       Int(iTermUnicodeNormalization.NFC.rawValue))
        XCTAssertEqual(result[KEY_USE_BOLD_FONT] as? Bool, true)
    }

    // Fails when a profile key is added without deciding whether a recording may
    // set it. Add the new key to allowedBaseKeys or deniedBaseKeys in
    // iTermRecordingProfileSanitizer.swift.
    func testEveryProfileKeyIsClassified() {
        let allowed = iTermRecordingProfileSanitizer.allowedBaseKeys
        let denied = iTermRecordingProfileSanitizer.deniedBaseKeys
        for key in iTermProfilePreferences.allKeys() {
            if iTermProfilePreferences.keyIsColor(key) {
                continue
            }
            let base = iTermProfilePreferences.baseColorKey(forKey: key)
            XCTAssertTrue(allowed.contains(base) || denied.contains(base),
                          "New profile key “\(key)” must be added to allowedBaseKeys or deniedBaseKeys in iTermRecordingProfileSanitizer.swift")
        }
    }

    func testAllowedAndDeniedKeysAreDisjoint() {
        let overlap = iTermRecordingProfileSanitizer.allowedBaseKeys.intersection(iTermRecordingProfileSanitizer.deniedBaseKeys)
        XCTAssertTrue(overlap.isEmpty, "Keys both allowed and denied: \(overlap.sorted())")
    }

    func testDeniedKeysAreDropped() {
        for key in iTermRecordingProfileSanitizer.deniedBaseKeys {
            XCTAssertFalse(iTermRecordingProfileSanitizer.keyIsAllowed(key), "\(key) is denied but allowed")
        }
    }

    // An allowlisted key with no validator would always be dropped.
    func testEveryAllowedKeyHasAValidator() {
        for key in iTermRecordingProfileSanitizer.allowedBaseKeys {
            // Font keys have no default but are strings.
            let value = iTermProfilePreferences.defaultObject(forKey: key) ?? ""
            XCTAssertTrue(iTermProfilePreferences.valueIsLegal(value, forKey: key), "\(key) has no validator")
        }
    }

    func testGUIDIsNotTakenFromTheFile() {
        let guid = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let result = sanitize([KEY_GUID: guid])
        let newGUID = result[KEY_GUID] as? String
        XCTAssertNotNil(newGUID)
        XCTAssertNotEqual(newGUID, guid)
    }
}
