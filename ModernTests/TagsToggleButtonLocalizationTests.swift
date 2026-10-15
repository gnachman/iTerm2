//
//  TagsToggleButtonLocalizationTests.swift
//  ModernTests
//
//  The “Tags >” / “< Tags” toggle under the profile lists is a fixed-width
//  square button (51 to 53 points). The pt-BR “Etiquetas >” was clipped to
//  “Etiquet” and the Russian code-set “Метки >” was clipped too (QA F-232).
//  Every translation must fit the button’s text area.
//

import AppKit
import XCTest

final class TagsToggleButtonLocalizationTests: XCTestCase {
    // About 43 points of “Etiquet” were visible in the clipped button, so 45
    // points is the most the title can use. English (“Tags >”) is about 40.
    private let maximumWidth: CGFloat = 45

    private func strings(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["strings"] as! [String: Any]
    }

    func testTagsButtonTitlesFit() throws {
        let sources: [(String, [String])] = [
            ("sources/Settings/mul.lproj/PreferencePanel.xcstrings", ["u6m-pp-fub.title"]),
            ("sources/Settings/mul.lproj/ProfilesWindow.xcstrings", ["QXh-S4-dCz.title"]),
            ("xcstrings/Localizable.xcstrings", ["ProfilePreferences.ShowTags",
                                                 "ProfilePreferences.HideTags",
                                                 "ProfilesWindow.ExpandTags",
                                                 "ProfilesWindow.CollapseTags"]),
        ]
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var tooWide: [String] = []
        for (path, keys) in sources {
            let catalog = try strings(path)
            for key in keys {
                guard let localizations = (catalog[key] as? [String: Any])?["localizations"] as? [String: Any] else {
                    XCTFail("\(path): no \(key)")
                    continue
                }
                for (language, localizationAny) in localizations {
                    let unit = (localizationAny as? [String: Any])?["stringUnit"] as? [String: Any]
                    guard let value = unit?["value"] as? String else {
                        continue
                    }
                    let width = NSAttributedString(string: value, attributes: [.font: font]).size().width
                    if width > maximumWidth {
                        tooWide.append("\(key) \(language): \(value) (\(Int(width.rounded())) pt)")
                    }
                }
            }
        }
        XCTAssertEqual(tooWide.sorted(), [])
    }
}
