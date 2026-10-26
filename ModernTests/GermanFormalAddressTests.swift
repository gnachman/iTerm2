//
//  GermanFormalAddressTests.swift
//  ModernTests
//
//  The German UI addresses the user formally (Sie). The website permissions
//  panel strings used the informal du forms (dich, Gib) (QA F-362).
//

import XCTest

final class GermanFormalAddressTests: XCTestCase {
    func testGermanDoesNotUseInformalAddress() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        // Case-sensitive so code tokens such as DIR are not mistaken for German.
        let informal = try NSRegularExpression(pattern: "\\b([Dd]u|[Dd]ich|[Dd]ir|[Dd]ein(e|en|em|er|es)?|Gib)\\b")
        var offenders: [String] = []
        for (key, entryAny) in strings {
            let localizations = (entryAny as? [String: Any])?["localizations"] as? [String: Any]
            let unit = (localizations?["de"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard let value = unit?["value"] as? String else {
                continue
            }
            if informal.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
                offenders.append(key)
            }
        }
        XCTAssertEqual(offenders.sorted(), [])
    }
}
