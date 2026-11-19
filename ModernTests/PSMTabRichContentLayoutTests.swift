//
//  PSMTabRichContentLayoutTests.swift
//  ModernTests
//
//  How rich tab content lines are placed inside a tab cell. The block of
//  lines is centered as if every line were present, so a cell's text doesn't
//  jump when a line becomes empty and collapses. Collapsed lines give their
//  space to the lines below them.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabRichContentLayoutTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 12)

    private func line(_ text: String,
                      scale: CGFloat = 1,
                      collapses: Bool = true,
                      spacingAfter: CGFloat = 0) -> PSMTabRichLine {
        return PSMTabRichLine(text: text,
                              scale: scale,
                              bold: false,
                              italic: false,
                              color: nil,
                              secondary: false,
                              lineBreakMode: .byTruncatingTail,
                              collapsesWhenEmpty: collapses,
                              spacingAfter: spacingAfter)
    }

    // A title gets a little room between it and the lines under it.
    func testSpacingAfterALineSeparatesItFromTheNext() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let rects = layout([line("title", spacingAfter: 3), line("b")], in: rect)
        XCTAssertEqual(rects[1]!.minY - rects[0]!.maxY, 3, accuracy: 0.001)
        let plain = PSMTabRichContentRenderer.contentHeight(lines: [line("title"), line("b")], baseFont: font)
        let spaced = PSMTabRichContentRenderer.contentHeight(lines: [line("title", spacingAfter: 3), line("b")], baseFont: font)
        XCTAssertEqual(spaced, plain + 3, "the tab is tall enough for it")
    }

    // Nothing follows the last line, so it needs no spacing.
    func testNoSpacingAfterTheLastLine() {
        XCTAssertEqual(PSMTabRichContentRenderer.contentHeight(lines: [line("title", spacingAfter: 3)], baseFont: font),
                       PSMTabRichContentRenderer.contentHeight(lines: [line("title")], baseFont: font))
    }

    // An empty line that collapses gives up its spacing too, and the lines
    // below take its place.
    func testCollapsedLineGivesUpItsSpacing() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let collapsed = layout([line("", spacingAfter: 3), line("b"), line("c")], in: rect)
        let full = layout([line("a", spacingAfter: 3), line("b"), line("c")], in: rect)
        XCTAssertEqual(collapsed[1]!.minY, full[0]!.minY, accuracy: 0.001)
    }

    // When not every line fits, the spacing counts toward what fits and the
    // lines that fit are centered with it.
    func testSpacingCountsWhenCenteringTheLinesThatFit() {
        let single = PSMTabRichContentRenderer.height(for: line("a"), baseFont: font)
        let rect = NSRect(x: 0, y: 0, width: 100, height: single * 2 + 3)
        let rects = layout([line("a", spacingAfter: 3), line("b"), line("c")], in: rect)
        XCTAssertEqual(rects[0]!.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rects[1]!.minY, single + 3, accuracy: 0.001)
        XCTAssertNil(rects[2])
    }

    private func layout(_ lines: [PSMTabRichLine], in rect: NSRect) -> [NSRect?] {
        return PSMTabRichContentRenderer.layout(lines: lines, in: rect, baseFont: font)
            .map { $0 == .zero ? nil : $0 }
    }

    func testLinesStackTopToBottomInAFlippedView() {
        let rects = layout([line("a"), line("b")], in: NSRect(x: 10, y: 0, width: 100, height: 100))
        let first = rects[0]!
        let second = rects[1]!
        XCTAssertEqual(first.minX, 10)
        XCTAssertEqual(first.width, 100)
        XCTAssertEqual(second.minY, first.maxY, accuracy: 0.001)
    }

    func testBlockIsVerticallyCentered() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let rects = layout([line("a"), line("b")], in: rect)
        let top = rects[0]!.minY
        let bottom = rects[1]!.maxY
        XCTAssertEqual(top - rect.minY, rect.maxY - bottom, accuracy: 0.5)
    }

    func testEmptyCollapsingLineGivesItsSpaceToTheLinesBelow() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let full = layout([line("a"), line("b"), line("c")], in: rect)
        let collapsed = layout([line("a"), line("  "), line("c")], in: rect)
        XCTAssertNil(collapsed[1])
        XCTAssertEqual(collapsed[0], full[0], "lines above don't move")
        XCTAssertEqual(collapsed[2]!.minY, full[1]!.minY, accuracy: 0.001)
    }

    func testEmptyNonCollapsingLineKeepsItsSpace() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let full = layout([line("a"), line("b"), line("c")], in: rect)
        let kept = layout([line("a"), line("", collapses: false), line("c")], in: rect)
        XCTAssertNil(kept[1], "nothing to draw")
        XCTAssertEqual(kept[2], full[2])
    }

    // The total height counts every line, empty or not, which is what keeps
    // the tab height fixed.
    func testContentHeightCountsEveryLine() {
        let all = PSMTabRichContentRenderer.contentHeight(lines: [line("a"), line("b", scale: 0.85)], baseFont: font)
        let withEmpty = PSMTabRichContentRenderer.contentHeight(lines: [line("a"), line("", scale: 0.85)], baseFont: font)
        XCTAssertEqual(all, withEmpty)
        XCTAssertGreaterThan(all, PSMTabRichContentRenderer.contentHeight(lines: [line("a")], baseFont: font))
    }

    func testSmallerScaleMakesShorterLine() {
        let rects = layout([line("big", scale: 1.15), line("small", scale: 0.85)],
                           in: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertGreaterThan(rects[0]!.height, rects[1]!.height)
    }

    // A cell shorter than the content (a tab bar that hasn't been made tall
    // enough) centers the lines that fit rather than centering the whole
    // block off the top, so the tab keeps its padding.
    func testContentTallerThanCellCentersTheLinesThatFit() {
        let one = PSMTabRichContentRenderer.contentHeight(lines: [line("a")], baseFont: font)
        let rect = NSRect(x: 0, y: 5, width: 100, height: one * 2 + 8)
        let rects = layout([line("a"), line("b"), line("c")], in: rect)
        XCTAssertEqual(rects[0]!.minY, rect.minY + 4, accuracy: 0.001)
        XCTAssertNil(rects[2])
    }

    // Lines that don't fit are dropped rather than drawn into the next cell.
    func testLinesThatDoNotFitAreDropped() {
        let one = PSMTabRichContentRenderer.contentHeight(lines: [line("a")], baseFont: font)
        let rect = NSRect(x: 0, y: 0, width: 100, height: one * 2 + 1)
        let rects = layout([line("a"), line("b"), line("c")], in: rect)
        XCTAssertNotNil(rects[0])
        XCTAssertNotNil(rects[1])
        XCTAssertNil(rects[2])
        for r in rects.compactMap({ $0 }) {
            XCTAssertLessThanOrEqual(r.maxY, rect.maxY)
        }
    }

    // MARK: - Lightweight HTML

    private func html(_ text: String) -> PSMTabRichLine {
        return PSMTabRichLine(text: text, scale: 1, bold: false, italic: false, color: nil, secondary: false,
                              lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: true, maximumLines: 1, html: true)
    }

    // Markup with no text in it, as when a job line's values are all empty,
    // is blank and collapses.
    func testHTMLWithOnlyMarkupIsBlank() {
        XCTAssertTrue(html(" <font color=\"\"></font>").isBlank)
        XCTAssertFalse(html("<b>x</b>").isBlank)
        XCTAssertFalse(line("<b></b>").isBlank, "a plain text line shows its tags")
        XCTAssertEqual(html("a &lt; <b>b</b>").visibleText, "a < b")
        XCTAssertEqual(line("a &lt; <b>b</b>").visibleText, "a &lt; <b>b</b>")
    }

    func testHTMLWidthIsTheWidthOfItsText() {
        let markup = PSMTabRichContentRenderer.preferredWidth(lines: [html("<font color=\"#ff0000\">abc</font>")], baseFont: font)
        let plain = PSMTabRichContentRenderer.preferredWidth(lines: [line("abc")], baseFont: font)
        XCTAssertEqual(markup, plain)
    }

    // An HTML line draws its runs in their colors; a plain one draws its tags
    // as text in the line's color.
    func testHTMLDrawsInItsColors() {
        func redPixels(_ richLine: PSMTabRichLine) -> Int {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 20, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            PSMTabRichContentRenderer.draw(lines: [richLine], in: NSRect(x: 0, y: 0, width: 100, height: 20),
                                           baseFont: font, textColor: .black, secondaryColor: .gray, alignment: .left)
            NSGraphicsContext.restoreGraphicsState()
            var count = 0
            for y in 0..<20 {
                for x in 0..<100 {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                       c.alphaComponent > 0.5, c.redComponent > 0.8, c.greenComponent < 0.3, c.blueComponent < 0.3 {
                        count += 1
                    }
                }
            }
            return count
        }
        XCTAssertGreaterThan(redPixels(html("<font color=\"#ff0000\">MMM</font>")), 10)
        XCTAssertEqual(redPixels(line("<font color=\"#ff0000\">MMM</font>")), 0)
        // A chip drawn on its group's color uses lines without their colors,
        // markup colors included.
        XCTAssertEqual(redPixels(html("<font color=\"#ff0000\">MMM</font>").lineWithoutColor), 0)
    }

    // A line with a dark color draws in it under a dark appearance, and in
    // its other color under a light one.
    func testDarkColorDrawsUnderADarkAppearance() {
        func pixels(_ appearance: NSAppearance.Name,
                    colorAppearance: NSAppearance? = nil,
                    matching match: (NSColor) -> Bool) -> Int {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 20, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            let richLine = PSMTabRichLine(text: "MMM", scale: 1, bold: true, italic: false,
                                          color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                          darkColor: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
                                          secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: false)
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                PSMTabRichContentRenderer.draw(lines: [richLine], in: NSRect(x: 0, y: 0, width: 100, height: 20),
                                               baseFont: font, textColor: .black, secondaryColor: .gray, alignment: .left,
                                               colorAppearance: colorAppearance)
                NSGraphicsContext.restoreGraphicsState()
            }
            var count = 0
            for y in 0..<20 {
                for x in 0..<100 {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5, match(c) {
                        count += 1
                    }
                }
            }
            return count
        }
        let red = { (c: NSColor) in c.redComponent > 0.8 && c.blueComponent < 0.3 }
        let blue = { (c: NSColor) in c.blueComponent > 0.8 && c.redComponent < 0.3 }
        XCTAssertGreaterThan(pixels(.aqua, matching: red), 10)
        XCTAssertEqual(pixels(.aqua, matching: blue), 0)
        XCTAssertGreaterThan(pixels(.darkAqua, matching: blue), 10)
        XCTAssertEqual(pixels(.darkAqua, matching: red), 0)
        // A style whose bar is dark or light regardless of the window's
        // appearance, like Minimal following the terminal background, says
        // which color to use.
        XCTAssertGreaterThan(pixels(.aqua, colorAppearance: NSAppearance(named: .darkAqua), matching: blue), 10)
        XCTAssertEqual(pixels(.aqua, colorAppearance: NSAppearance(named: .darkAqua), matching: red), 0)
        XCTAssertGreaterThan(pixels(.darkAqua, colorAppearance: NSAppearance(named: .aqua), matching: red), 10)
    }

    func testEqualityIncludesTheDarkColor() {
        func line(dark: NSColor?) -> PSMTabRichLine {
            return PSMTabRichLine(text: "a", scale: 1, bold: false, italic: false, color: .red, darkColor: dark,
                                  secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: false)
        }
        XCTAssertEqual(line(dark: .blue), line(dark: .blue))
        XCTAssertNotEqual(line(dark: .blue), line(dark: nil))
        XCTAssertNil(line(dark: .blue).lineWithoutColor.darkColor)
    }

    // MARK: - Lines that wrap

    private func wrapping(_ text: String, lines: Int, collapses: Bool = true) -> PSMTabRichLine {
        return PSMTabRichLine(text: text,
                              scale: 1,
                              bold: false,
                              italic: false,
                              color: nil,
                              secondary: false,
                              lineBreakMode: .byTruncatingTail,
                              collapsesWhenEmpty: collapses,
                              maximumLines: lines)
    }

    func testWrappingLineReservesAllItsLines() {
        let single = PSMTabRichContentRenderer.height(for: line("x"), baseFont: font)
        XCTAssertEqual(PSMTabRichContentRenderer.height(for: wrapping("x", lines: 3), baseFont: font), single * 3)
        let rects = layout([wrapping("short", lines: 3), line("below")],
                           in: NSRect(x: 0, y: 0, width: 100, height: single * 4))
        XCTAssertEqual(rects[0]?.height, single * 3)
        XCTAssertEqual(rects[1]?.minY, single * 3, "the line below doesn't move up when the text is short")
    }

    func testEmptyWrappingLineGivesUpAllItsLines() {
        let single = PSMTabRichContentRenderer.height(for: line("x"), baseFont: font)
        let rects = layout([wrapping("", lines: 3), line("below")],
                           in: NSRect(x: 0, y: 0, width: 100, height: single * 4))
        XCTAssertNil(rects[0])
        XCTAssertEqual(rects[1]?.minY, 0, "the block fills the cell, so the line below moves to the top")
    }

    // When the cell is too short for every line, a wrapping line keeps as
    // many of its lines as fit rather than disappearing.
    func testWrappingLineShowsTheLinesThatFit() {
        let single = PSMTabRichContentRenderer.height(for: line("x"), baseFont: font)
        let rects = layout([wrapping("long text", lines: 3)],
                           in: NSRect(x: 0, y: 0, width: 100, height: single * 2))
        XCTAssertEqual(rects[0]?.height, single * 2)
    }

    // A tab sized to its content gets room for text that can wrap to show
    // without wrapping, up to the tab's maximum width. It wraps only when
    // there isn't room. Asking for less would cut text off in a tab that
    // could have shown it.
    func testPreferredWidthOfAWrappingLineIsItsUnwrappedWidth() {
        let text = "a fairly long status detail"
        let oneLine = PSMTabRichContentRenderer.preferredWidth(lines: [line(text)], baseFont: font)
        XCTAssertEqual(PSMTabRichContentRenderer.preferredWidth(lines: [wrapping(text, lines: 3)], baseFont: font),
                       oneLine)
    }

    // Wrapped text is drawn on more than one line, in the line's rect.
    func testWrappingLineDrawsOnSeveralLines() {
        let single = PSMTabRichContentRenderer.height(for: line("x"), baseFont: font)
        let size = NSSize(width: 60, height: single * 3)
        let image = NSImage(size: size, flipped: true) { rect in
            PSMTabRichContentRenderer.draw(lines: [self.wrapping("word word word word word word", lines: 3)],
                                           in: rect,
                                           baseFont: self.font,
                                           textColor: .black,
                                           secondaryColor: .black,
                                           alignment: .left)
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        func inked(row: Int) -> Bool {
            let y = Int((CGFloat(row) + 0.5) * single * CGFloat(rep.pixelsHigh) / size.height)
            return (0..<rep.pixelsWide).contains { (rep.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.3 }
        }
        XCTAssertTrue(inked(row: 0))
        XCTAssertTrue(inked(row: 1))
    }
}
