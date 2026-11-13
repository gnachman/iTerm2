//
//  AnnouncementMnemonicTitleTests.swift
//  ModernTests
//
//  An announcement action names its Option-key shortcut with an underscore (“_Always”). The
//  Chinese and Japanese translations write the shortcut the way those languages do, as a
//  parenthesized letter after the text (“常に(_A)”, “一律（_A）”). The button already appends
//  “(⌥A)”, so the parenthesized letter has to go or the shortcut shows twice.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class AnnouncementMnemonicTitleTests: XCTestCase {
    private func buttonTitles(_ actions: [String]) -> [String] {
        let view: iTermAnnouncementView = iTermAnnouncementView(title: "Title",
                                         style: .kiTermAnnouncementViewStyleQuestion,
                                         actions: actions,
                                         block: { _ in })
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        return all(view).compactMap { $0 as? NSButton }
            .filter { $0.action == NSSelectorFromString("buttonPressed:") }
            .map { $0.title }
            .sorted()
    }

    private func expected(_ text: String, _ key: String) -> String {
        let format = NSLocalizedString("Announcement.ActionWithShortcut", value: "%1$@ (⌥%2$@)", comment: "")
        return String(format: format, text, key)
    }

    func testInlineUnderscoreMarksTheShortcut() {
        XCTAssertEqual(buttonTitles(["_Always", "Never _Ask"]),
                       [expected("Always", "A"), expected("Never Ask", "A")].sorted())
    }

    func testParenthesizedShortcutIsNotShownTwice() {
        XCTAssertEqual(buttonTitles(["常に許可(_A)", "一律允許（_A）"]),
                       [expected("常に許可", "A"), expected("一律允許", "A")].sorted())
        XCTAssertEqual(buttonTitles(["暂时 (_T)", "_Never"]),
                       [expected("暂时", "T"), expected("Never", "N")].sorted())
    }
}
