//
//  WindowMenuLocalizationTests.swift
//  ModernTests
//
//  Window > Lock Location had no entry in MainMenu.xcstrings, and the tab
//  context menu’s “Rename Tab…” and “Tab Color:” label had no translations, so
//  all three showed English in every non-English UI (QA F-022, F-042, F-152).
//

import XCTest

final class WindowMenuLocalizationTests: XCTestCase {
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

    func testLockLocationMenuItemIsTranslated() throws {
        let mainMenu = try strings("sources/MainMenu/mul.lproj/MainMenu.xcstrings")
        XCTAssertEqual(untranslatedLanguages("Lk3-Ly-Lt2.title", in: mainMenu), [])
    }

    func testTabContextMenuStringsAreTranslated() throws {
        let catalog = try strings("xcstrings/Localizable.xcstrings")
        for key in ["PseudoTerminal.RenameTab", "ColorsMenuItemView.TabColorLabel"] {
            XCTAssertEqual(untranslatedLanguages(key, in: catalog), [], key)
        }
    }
}
