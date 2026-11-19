//
//  PSMTabSearchHighlightTests.swift
//  ModernTests
//
//  During a tab bar search, matches in tab text are highlighted: black text
//  on yellow, wherever the text comes from.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabSearchHighlightTests: XCTestCase {
    private func highlightedRanges(_ string: NSAttributedString) -> [NSRange] {
        var ranges = [NSRange]()
        string.enumerateAttribute(.backgroundColor,
                                  in: NSRange(location: 0, length: string.length)) { value, range, _ in
            if value != nil {
                ranges.append(range)
            }
        }
        return ranges
    }

    func testEveryMatchIgnoringCaseAndAccents() {
        let font = NSFont.systemFont(ofSize: 12)
        let original = NSAttributedString(string: "Café cafe CAFE", attributes: [.font: font,
                                                                                .foregroundColor: NSColor.white])
        let result = PSMTabSearchHighlight.highlighting(original, query: "cafe")
        XCTAssertEqual(highlightedRanges(result), [NSRange(location: 0, length: 4),
                                                   NSRange(location: 5, length: 4),
                                                   NSRange(location: 10, length: 4)])
        XCTAssertEqual(result.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       PSMTabSearchHighlight.backgroundColor)
        XCTAssertEqual(result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       PSMTabSearchHighlight.textColor)
        // Text between matches keeps its color, and every character its font.
        XCTAssertEqual(result.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .white)
        XCTAssertEqual(result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, font)
        XCTAssertEqual(result.string, original.string)
    }

    func testNoQueryOrNoMatchChangesNothing() {
        let original = NSAttributedString(string: "title")
        XCTAssertTrue(PSMTabSearchHighlight.highlighting(original, query: nil) === original)
        XCTAssertTrue(PSMTabSearchHighlight.highlighting(original, query: "  ") === original)
        XCTAssertTrue(PSMTabSearchHighlight.highlighting(original, query: "zzz") === original)
    }

    // Spaces around the query don't count, as in the search itself.
    func testQueryIsTrimmed() {
        let result = PSMTabSearchHighlight.highlighting(NSAttributedString(string: "a job"), query: " job ")
        XCTAssertEqual(highlightedRanges(result), [NSRange(location: 2, length: 3)])
    }

    // Rich content lines, including HTML ones, are highlighted as drawn.
    func testRichLines() {
        let line = PSMTabRichLine(text: "<b>api</b> server", scale: 1, bold: false, italic: false, color: nil,
                                  secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: true,
                                  html: true)
        let text = PSMTabRichContentRenderer.attributedText(for: line,
                                                            baseFont: NSFont.systemFont(ofSize: 12),
                                                            textColor: .white,
                                                            secondaryColor: .gray,
                                                            alignment: .left,
                                                            colorAppearance: nil,
                                                            highlight: "SERVER")
        XCTAssertEqual(text.string, "api server")
        XCTAssertEqual(highlightedRanges(text), [NSRange(location: 4, length: 6)])
    }

    // A search can hide the selected tab when it doesn't match. The Minimal
    // style then draws no selected tab, as when it's in the overflow menu,
    // rather than outlining a cell that isn't there.
    func testMinimalStyleIgnoresAHiddenSelectedTab() {
        let control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 150, height: 400))
        let shown = PSMTabBarCell(controlView: control)!
        let selected = PSMTabBarCell(controlView: control)!
        selected.state = .on
        selected.isCollapsedHidden = true
        control.cells().setArray([shown, selected])
        let style = PSMMinimalTabStyle()
        XCTAssertNil(style.selectedCell(in: control))
        selected.isCollapsedHidden = false
        XCTAssertTrue(style.selectedCell(in: control) === selected)
    }

    // A hidden cell that was selected before can keep its selected state
    // while hidden; the shown selected tab is still found after it.
    func testMinimalStyleFindsTheShownSelectedTabPastAStaleHiddenOne() {
        let control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 150, height: 400))
        let stale = PSMTabBarCell(controlView: control)!
        stale.state = .on
        stale.isCollapsedHidden = true
        let selected = PSMTabBarCell(controlView: control)!
        selected.state = .on
        control.cells().setArray([stale, selected])
        XCTAssertTrue(PSMMinimalTabStyle().selectedCell(in: control) === selected)
    }
}
