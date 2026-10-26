//
//  SessionStatusHelpLocalizationTests.swift
//  ModernTests
//
//  The English Session Status help gained a Program Status Protocol (OSC 7501)
//  paragraph, but no translation was updated, so every other language lacked
//  it and all of them were left needs_review (QA F-369).
//

import XCTest

final class SessionStatusHelpLocalizationTests: XCTestCase {
    func testEveryTranslationDescribesOSC7501() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        let localizations = (strings["ToolStatus.HelpMarkdown"] as? [String: Any])?["localizations"] as? [String: Any]
        for language in ["en", "de", "ja", "pt-BR", "ru", "zh-Hans"] {
            let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String ?? ""
            XCTAssertTrue(value.contains("OSC 7501"), language)
            if language != "en" {
                XCTAssertEqual(unit?["state"] as? String, "translated", language)
            }
        }
    }
}
