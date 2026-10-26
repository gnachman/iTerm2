//
//  ChineseCustomHeaderTerminologyTests.swift
//  ModernTests
//
//  The Chinese AI model editor labels its custom headers section 自定义头信息,
//  but the “no API key” hint told users to use 自定义标头, a different term for
//  the same section (QA F-367).
//

import XCTest

final class ChineseCustomHeaderTerminologyTests: XCTestCase {
    func testCustomHeaderTermIsConsistent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        var offenders: [String] = []
        for (key, entryAny) in strings {
            let localizations = (entryAny as? [String: Any])?["localizations"] as? [String: Any]
            let unit = (localizations?["zh-Hans"] as? [String: Any])?["stringUnit"] as? [String: Any]
            if let value = unit?["value"] as? String, value.contains("自定义标头") {
                offenders.append(key)
            }
        }
        XCTAssertEqual(offenders.sorted(), [], "Use 自定义头信息 to match the Custom headers label")
    }
}
