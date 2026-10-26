//
//  JapaneseUserTerminologyTests.swift
//  ModernTests
//
//  Japanese translations write “user” as ユーザー everywhere except a few
//  strings that used the short form ユーザ, and the SSH Integration file
//  transfer description inserted an unlocalized “(unknown)” when the user name
//  was missing (QA F-368).
//

import XCTest

final class JapaneseUserTerminologyTests: XCTestCase {
    private func strings(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["strings"] as! [String: Any]
    }

    private func japaneseValue(_ entryAny: Any) -> String? {
        let localizations = (entryAny as? [String: Any])?["localizations"] as? [String: Any]
        let unit = (localizations?["ja"] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    func testJapaneseUsesLongFormOfUser() throws {
        let shortForm = try NSRegularExpression(pattern: "ユーザ(?!ー)")
        var offenders: [String] = []
        for path in ["xcstrings/Localizable.xcstrings",
                     "sources/Settings/mul.lproj/PreferencePanel.xcstrings"] {
            for (key, entryAny) in try strings(path) {
                guard let value = japaneseValue(entryAny) else {
                    continue
                }
                let range = NSRange(value.startIndex..., in: value)
                if shortForm.firstMatch(in: value, range: range) != nil {
                    offenders.append("\(path): \(key)")
                }
            }
        }
        XCTAssertEqual(offenders.sorted(), [])
    }

    func testUnknownUserNameIsTranslated() throws {
        let catalog = try strings("xcstrings/Localizable.xcstrings")
        let localizations = (catalog["ConductorFileTransfer.UnknownUserName"] as? [String: Any])?["localizations"] as? [String: Any]
        for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
            let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            XCTAssertEqual(unit?["state"] as? String, "translated", language)
        }
    }
}
