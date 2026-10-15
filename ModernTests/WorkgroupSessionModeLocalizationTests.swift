//
//  WorkgroupSessionModeLocalizationTests.swift
//  ModernTests
//
//  The workgroup session Mode popup titles used Swift NSLocalizedString, which
//  string extraction does not pick up, so “Regular”, “Code Review” and “Diff”
//  never reached the catalog and were English in every language (QA F-311).
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupSessionModeLocalizationTests: XCTestCase {
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

    func testModeTitlesAreTranslated() throws {
        let catalog = try strings("xcstrings/Localizable.xcstrings")
        for key in ["WorkgroupSessionMode.Regular",
                    "WorkgroupSessionMode.CodeReview",
                    "WorkgroupSessionMode.Diff"] {
            XCTAssertEqual(untranslatedLanguages(key, in: catalog), [], key)
        }
    }

    func testEnglishTitlesAreUnchanged() {
        XCTAssertEqual(iTermWorkgroupSessionMode.regular.localizedTitle, "Regular")
        XCTAssertEqual(iTermWorkgroupSessionMode.codeReview.localizedTitle, "Code Review")
        XCTAssertEqual(iTermWorkgroupSessionMode.diff.localizedTitle, "Diff")
    }

    // Guards against a regression to NSLocalizedString(_:comment:), which the
    // extraction step silently skips in Swift.
    func testNoSwiftNSLocalizedStringInWorkgroupSessionMode() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("sources/Workgroups/iTermWorkgroupSessionMode.swift"),
                                encoding: .utf8)
        XCTAssertFalse(source.contains("NSLocalizedString("))
    }
}
