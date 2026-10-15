//
//  BrowserBasicAuthLocalizationTests.swift
//  ModernTests
//
//  The browser HTTP authentication prompt’s heading and the save-failure toast
//  were hard-coded English while the rest of the prompt was translated (QA
//  F-271).
//

import XCTest

final class BrowserBasicAuthLocalizationTests: XCTestCase {
    func testBasicAuthStringsAreTranslated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        let keys = ["BrowserBasicAuth.Prompt",
                    "BrowserBasicAuth.PromptWithRealm",
                    "BrowserBasicAuth.SavePasswordFailed"]
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
            }
        }
    }
}
