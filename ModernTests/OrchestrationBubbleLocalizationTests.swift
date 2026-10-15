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
