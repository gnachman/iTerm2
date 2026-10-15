//
//  AITitleComponentLocalizationTests.swift
//  ModernTests
//
//  The “AI-generated name” item in Settings > Profiles > General > Title and the
//  “AI” sample in the title preview were hard-coded English (QA F-340).
//

import XCTest

final class AITitleComponentLocalizationTests: XCTestCase {
    private let languages = ["de", "ja", "pt-BR", "ru", "zh-Hans"]

    private func strings(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["strings"] as! [String: Any]
    }

    private func value(_ key: String, _ language: String, in strings: [String: Any]) -> String? {
        let entry = strings[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        guard unit?["state"] as? String == "translated" else {
            return nil
        }
        return unit?["value"] as? String
    }

    func testTitleComponentStringsAreTranslated() throws {
        let catalog = try strings("xcstrings/Localizable.xcstrings")
        for key in ["ProfilesGeneral.TitleComponentAIGeneratedName", "ProfilesGeneral.TitlePreviewAI"] {
            for language in languages {
                XCTAssertNotNil(value(key, language, in: catalog), "\(key) \(language)")
            }
        }
    }

    // The aiGeneratedTabTitles advanced setting tells the user to add the
    // “AI-generated name” title component, so each translation of the menu item
    // must be the name that setting’s help text quotes.
    func testMenuItemMatchesNameQuotedByAdvancedSetting() throws {
        let catalog = try strings("xcstrings/Localizable.xcstrings")
        for language in languages {
            guard let name = value("ProfilesGeneral.TitleComponentAIGeneratedName", language, in: catalog),
                  let help = value("AdvancedSetting.aiGeneratedTabTitles", language, in: catalog) else {
                XCTFail("missing \(language)")
                continue
            }
            XCTAssertTrue(help.contains(name), "\(language): \(name) not in \(help)")
        }
    }
}
