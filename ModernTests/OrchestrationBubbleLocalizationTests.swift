//
//  OrchestrationBubbleLocalizationTests.swift
//  ModernTests
//
//  The AI chat watch screen-read consent body and the register_timer bubble
//  were English literals, so they stayed English in a translated UI (QA F-280).
//

import XCTest
@testable import iTerm2SharedARC

final class OrchestrationBubbleLocalizationTests: XCTestCase {
    func testStringsAreTranslated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        let keys = ["OrchestratorDispatcher.WatchScreenReadConsent",
                    "OrchestratorDispatcher.WatchScreenReadConsentInWorkgroup",
                    "OrchestrationTool.TimerAfter",
                    "OrchestrationTool.TimerAfterWithNote",
                    "OrchestrationTool.TimerAt",
                    "OrchestrationTool.TimerAtWithNote",
                    "OrchestrationTool.TimerLater",
                    "OrchestrationTool.TimerLaterWithNote"]
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
            }
        }
    }

    // Every tool-call bubble and the key binding editor's setting picker placeholder were English
    // literals too.
    func testToolBubblesAndSettingPickerAreTranslated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        let keys = strings.keys.filter { $0.hasPrefix("OrchestrationTool.") } + ["SettingPopup.SelectSetting"]
        XCTAssertGreaterThan(keys.count, 25)
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
            }
        }
    }

    @MainActor
    func testToolBubbleEnglish() {
        func describe(_ name: String, _ args: [String: Any]) -> String {
            return OrchestrationToolProvider.humanDescription(forToolName: name, args: AnyCodable(args))
        }
        XCTAssertEqual(describe("list_workgroups", [:]), "Looking up workgroups")
        XCTAssertEqual(describe("get_state", ["session_guid": "g1"]), "Checking state of @g1")
        XCTAssertEqual(describe("get_screen_contents", [:]), "Reading screen of _(unknown session)_")
        XCTAssertEqual(describe("scroll_wheel", ["session_guid": "g1"]), "Scrolling @g1 to show older content")
        XCTAssertEqual(describe("scroll_wheel", ["session_guid": "g1", "direction": "down"]),
                       "Scrolling @g1 to show newer content")
        XCTAssertEqual(describe("list_workgroup_clippings", [:]), "Listing clippings in _unknown workgroup_")
        XCTAssertEqual(describe("send_text", ["session_guid": "g1", "text": "ls\n"]),
                       "Typing into @g1: \u{201C}ls \u{201D}")
        XCTAssertEqual(describe("add_workgroup_clipping", ["workgroup_id": "wg-1", "title": "T"]),
                       "Posting clipping \u{201C}T\u{201D} to @wg-1")
        XCTAssertEqual(describe("add_workgroup_clipping", ["workgroup_id": "wg-1"]),
                       "Posting an untitled clipping to @wg-1")
        XCTAssertEqual(describe("start_session", ["command": "top"]), "Starting new session: `top`")
        XCTAssertEqual(describe("start_code_review", ["session_guid": "g1", "prompt_name": "Deep"]),
                       "Kicking off Code Review on @g1 with saved prompt \u{201C}Deep\u{201D}")
        XCTAssertEqual(describe("start_code_review", ["session_guid": "g1"]),
                       "Kicking off Code Review on @g1 with the default prompt")
        XCTAssertEqual(describe("register_watch", ["target_state": "idle"]),
                       "Will notify when the linked session becomes **idle**")
        XCTAssertEqual(describe("register_watch", ["session_guid": "g1", "condition": "done"]),
                       "Will notify when @g1 satisfies: \u{201C}done\u{201D}")
        XCTAssertEqual(describe("unregister_watch", [:]), "Cancelling a watch")
        XCTAssertEqual(describe("session_execute_command", ["command": "make"]), "Executing `make`")
        XCTAssertEqual(describe("session_get_selection", ["session_guid": "g1"]), "Get selection in @g1")
        XCTAssertEqual(describe("some_tool", [:]), "Some tool")
    }

    func testTimerBubbleEnglish() {
        XCTAssertEqual(OrchestrationToolProvider.timerDescription(when: .after("5min"), quotedNote: nil),
                       "Setting a timer to fire in 5min")
        XCTAssertEqual(OrchestrationToolProvider.timerDescription(when: .after("5min"), quotedNote: "\u{201C}de1\u{201D}"),
                       "Setting a timer to fire in 5min: \u{201C}de1\u{201D}")
        XCTAssertEqual(OrchestrationToolProvider.timerDescription(when: .at("2026-01-01T00:00:00Z"), quotedNote: nil),
                       "Setting a timer to fire at 2026-01-01T00:00:00Z")
        XCTAssertEqual(OrchestrationToolProvider.timerDescription(when: .later, quotedNote: "\u{201C}x\u{201D}"),
                       "Setting a timer to fire later: \u{201C}x\u{201D}")
    }

    func testConsentBodyNamesWorkgroupOnlyForRealWorkgroups() {
        let synthetic = WorkgroupIntrospection.syntheticWorkgroupIDPrefix + "abc"
        let standalone = OrchestratorDispatcher.watchScreenReadConsentText(role: "-zsh",
                                                                           workgroup: "ignored",
                                                                           workgroupID: synthetic)
        XCTAssertTrue(standalone.hasPrefix("This watch reads -zsh\u{2019}s screen repeatedly"), standalone)
        XCTAssertFalse(standalone.contains("ignored"))

        let inWorkgroup = OrchestratorDispatcher.watchScreenReadConsentText(role: "Reviewer",
                                                                            workgroup: "Project",
                                                                            workgroupID: "real-id")
        XCTAssertTrue(inWorkgroup.hasPrefix("This watch reads the screen of Reviewer in Project repeatedly"), inWorkgroup)
    }
}
