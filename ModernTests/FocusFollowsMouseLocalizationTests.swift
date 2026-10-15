//
//  FocusFollowsMouseLocalizationTests.swift
//  ModernTests
//
//  The Focus Follows Mouse sub-option “…even to views like Search or Composer”
//  in Settings > Pointer had no entry in PreferencePanel.xcstrings, so it was
//  English in every language (QA F-310).
//

import XCTest

final class FocusFollowsMouseLocalizationTests: XCTestCase {
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

    func testEvenToViewsOptionIsTranslated() throws {
        let catalog = try strings("sources/Settings/mul.lproj/PreferencePanel.xcstrings")
        XCTAssertEqual(untranslatedLanguages("tXe-jL-3Kg.title", in: catalog), [])
    }
}
