//
//  SessionUndoTimeoutLabelLocalizationTests.swift
//  ModernTests
//
//  The German label above the Undo seconds field in Settings > Profiles >
//  Session was wider than the label’s frame, so its last characters were
//  clipped (QA F-511).
//

import AppKit
import XCTest

final class SessionUndoTimeoutLabelLocalizationTests: XCTestCase {
    private let languages = ["en", "de", "ja", "pt-BR", "ru", "zh-Hans"]

    // The label (JdL-vz-9Vf in PreferencePanel.xib) is 551pt wide and clips. Its cell insets
    // leave about 547pt for text in the system font. Keep a little slack below that.
    func testUndoTimeoutLabelFitsItsFrame() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("sources/Settings/mul.lproj/PreferencePanel.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["JdL-vz-9Vf.title"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for language in languages {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = try XCTUnwrap(unit?["value"] as? String, language)
            let width = (value as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, 543, "\(language): \(value)")
        }
    }
}
