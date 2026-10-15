//
//  MenuBarIconSettingsLocalizationTests.swift
//  ModernTests
//
//  The menu bar icon row in Settings > Appearance > General (“Menu bar icon:”,
//  “Show menu bar icon” and the text field placeholder) had no entries in
//  PreferencePanel.xcstrings, so it was English in every language (QA F-262,
//  F-304).
//

import XCTest

final class MenuBarIconSettingsLocalizationTests: XCTestCase {
    private let languages = ["de", "ja", "pt-BR", "ru", "zh-Hans"]

    private func strings(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["strings"] as! [String: Any]
    }

    private func untranslatedLanguages(_ key: String, in strings: [String: Any]) -> [String] {
        guard let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any] else {
            return languages
        }
        return languages.filter { language in
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String ?? ""
            return unit?["state"] as? String != "translated" || value.isEmpty
        }
    }

    func testMenuBarIconRowIsTranslated() throws {
        let catalog = try strings("sources/Settings/mul.lproj/PreferencePanel.xcstrings")
        for key in ["uzZ-ah-yKW.title", "7MO-8Z-Pic.title", "MtC-QF-N2i.placeholderString"] {
            XCTAssertEqual(untranslatedLanguages(key, in: catalog), [], key)
        }
    }
}
