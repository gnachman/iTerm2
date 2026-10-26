//
//  ChineseTypeVerbTranslationTests.swift
//  ModernTests
//
//  The Cockpit’s “Type @ to …” hints were translated into Simplified Chinese
//  with “Type” as the noun 类型 (“kind”) instead of the verb 输入, giving
//  “输入类型：@ 选择要写入的会话” (“Input type: @ choose …”) (QA F-512).
//

import XCTest

final class ChineseTypeVerbTranslationTests: XCTestCase {
    func testCockpitTypeAtHintsUseTheVerb() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Cockpit.DefaultTip", "Cockpit.PickSessionStatus"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = entry["localizations"] as? [String: Any]
            let unit = (localizations?["zh-Hans"] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = try XCTUnwrap(unit?["value"] as? String, key)
            XCTAssertFalse(value.contains("类型"), "\(key): \(value)")
            XCTAssertTrue(value.hasPrefix("输入 @"), "\(key): \(value)")
        }
    }
}
