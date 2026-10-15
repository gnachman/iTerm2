//
//  XibCatalogGapLocalizationTests.swift
//  ModernTests
//
//  The browser menu’s Show Toolbar item and the Bell sound: label in Settings had no
//  entries in their XIB catalogs, so they were English in every language. pt-BR also
//  labeled the profile Tags field “Etiquetas:” next to a “Tags >” button.
//

import XCTest

final class XibCatalogGapLocalizationTests: XCTestCase {
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
        let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        guard unit?["state"] as? String == "translated" || language == "en" else {
            return nil
        }
        return unit?["value"] as? String
    }

    private func untranslatedLanguages(_ key: String, in strings: [String: Any]) -> [String] {
        return languages.filter { (value(key, $0, in: strings) ?? "").isEmpty }
    }

    func testShowToolbarMenuItemIsTranslated() throws {
        let mainMenu = try strings("sources/MainMenu/mul.lproj/MainMenu.xcstrings")
        XCTAssertEqual(value("Tgl-bT-sh7.title", "en", in: mainMenu), "Show Toolbar")
        XCTAssertEqual(untranslatedLanguages("Tgl-bT-sh7.title", in: mainMenu), [])
    }

    func testBellSoundLabelIsTranslated() throws {
        let preferences = try strings("sources/Settings/mul.lproj/PreferencePanel.xcstrings")
        XCTAssertEqual(value("bS4-Tc-6yH.title", "en", in: preferences), "Bell sound:")
        XCTAssertEqual(untranslatedLanguages("bS4-Tc-6yH.title", in: preferences), [])
    }

    func testPtBRProfileTagsLabelMatchesTagsButton() throws {
        let preferences = try strings("sources/Settings/mul.lproj/PreferencePanel.xcstrings")
        let label = value("3244.title", "pt-BR", in: preferences)
        let button = value("u6m-pp-fub.title", "pt-BR", in: preferences)
        XCTAssertEqual(button, "Tags >")
        XCTAssertEqual(label, "Tags:")
        // The profile list's tag heading and the tag column use the same word.
        let catalog = try strings("xcstrings/Localizable.xcstrings")
        XCTAssertEqual(value("ProfileListView.TagsMenuItem", "pt-BR", in: catalog), "Tags")
        XCTAssertEqual(value("ProfileTagsView.TagNameColumn", "pt-BR", in: catalog), "Nome da tag")
    }
}
