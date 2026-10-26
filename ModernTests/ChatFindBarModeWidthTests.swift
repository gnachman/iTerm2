//
//  ChatFindBarModeWidthTests.swift
//  ModernTests
//
//  QA finding F-111: the AI chat find bar's mode popup had a fixed width of
//  150 points, so in Portuguese it read “Ignorar maiúscul…”. These check
//  that the popup is as wide as its longest title in each shipped language.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatFindBarModeWidthTests: XCTestCase {
    private let keys = ["ChatFindBarView.ModeSmartCase",
                        "ChatFindBarView.ModeIgnoreCase",
                        "ChatFindBarView.ModeMatchCase",
                        "ChatFindBarView.ModeRegularExpression"]

    private func titles(_ language: String) -> [String] {
        guard let path = Bundle.main.path(forResource: "Localizable",
                                          ofType: "strings",
                                          inDirectory: nil,
                                          forLocalization: language),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("No Localizable.strings for \(language)")
            return []
        }
        return keys.compactMap { table[$0] }
    }

    // The width a popup like the find bar's needs to show `title` in full.
    private func widthNeeded(_ title: String) -> CGFloat {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.bezelStyle = .roundRect
        popup.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        popup.addItem(withTitle: title)
        return ceil(popup.cell!.cellSize.width)
    }

    func testPortugueseIgnoreCaseNeedsMoreThanTheOldWidth() {
        XCTAssertGreaterThan(widthNeeded("Ignorar maiúsculas/minúsculas"), 150)
    }

    func testModeWidthFitsEveryLanguage() {
        for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
            let titles = titles(language)
            XCTAssertEqual(titles.count, keys.count, language)
            let width = ChatFindBarView.modeWidth(forTitles: titles)
            for title in titles {
                XCTAssertGreaterThanOrEqual(width, widthNeeded(title), "\(language): \(title)")
            }
        }
    }

    func testEnglishFits() {
        let titles = ["Smart Case", "Ignore Case", "Match Case", "Regular Expression"]
        let width = ChatFindBarView.modeWidth(forTitles: titles)
        for title in titles {
            XCTAssertGreaterThanOrEqual(width, widthNeeded(title), title)
        }
        XCTAssertGreaterThanOrEqual(width, 150, "Never narrower than before")
    }

    func testLayoutUsesTheModeWidth() {
        let bar = ChatFindBarView(frame: NSRect(x: 0, y: 0, width: 800, height: ChatFindBarView.barHeight))
        bar.layout()
        let popup = bar.subviews.compactMap { $0 as? NSPopUpButton }.first
        XCTAssertNotNil(popup)
        let titles = popup?.itemTitles ?? []
        XCTAssertEqual(popup?.frame.width, ChatFindBarView.modeWidth(forTitles: titles))
    }
}
