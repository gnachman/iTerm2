//
//  ChatSessionMentionAttachmentLayoutTests.swift
//  iTerm2 ModernTests
//
//  A session @-mention chip (ChatSessionMentionAttachment) sits inline in the
//  Cockpit composer and the AI chat input. It must not change the line's
//  height or move the baseline of the text around it, the name drawn inside
//  the chip must sit on the same baseline as the surrounding text, and the
//  name must not be clipped. These lay the text out offscreen with TextKit
//  and compare a chip against the same text without one.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class ChatSessionMentionAttachmentLayoutTests: XCTestCase {
    private var fonts: [NSFont] {
        var result: [NSFont] = [NSFont.systemFont(ofSize: 13),
                                NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)]
        for (name, size) in [("Monaco", 12.0), ("Menlo-Regular", 12.0), ("Menlo-Regular", 13.0), ("Courier", 14.0)] {
            if let font = NSFont(name: name, size: size) {
                result.append(font)
            }
        }
        return result
    }

    private struct Layout {
        let storage: NSTextStorage
        let layoutManager: NSLayoutManager
        let container: NSTextContainer
    }

    private func layOut(_ attributed: NSAttributedString, usesFontLeading: Bool = true) -> Layout {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = usesFontLeading
        let container = NSTextContainer(size: NSSize(width: 10_000, height: 10_000))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return Layout(storage: storage, layoutManager: layoutManager, container: container)
    }

    private func plain(_ string: String, _ font: NSFont) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    private func chip(_ name: String, _ font: NSFont) -> NSAttributedString {
        return ChatSessionMentionAttachment.attributedString(guid: "guid",
                                                             displayName: name,
                                                             font: font,
                                                             color: NSColor.black)
    }

    // Line fragment rect and the baseline (from the top of the line
    // fragment) of the glyph for character `index`.
    private func metrics(_ layout: Layout, characterIndex index: Int) -> (lineRect: NSRect, baseline: CGFloat) {
        let glyph = layout.layoutManager.glyphIndexForCharacter(at: index)
        let lineRect = layout.layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = layout.layoutManager.location(forGlyphAt: glyph)
        return (lineRect, location.y)
    }

    func testChipDoesNotChangeLineHeightOrTextBaseline() {
        // "\u{00C9}lan" has an accented capital that overshoots Menlo's
        // rounded baseline offset by a fraction of a point.
        for name in ["-zsh", "\u{00C9}lan"] {
            for font in fonts {
                for usesFontLeading in [true, false] {
                    let withChip = NSMutableAttributedString(attributedString: chip(name, font))
                    withChip.append(plain(" echo hi", font))
                    let withoutChip = plain("X echo hi", font)

                    let a = metrics(layOut(withChip, usesFontLeading: usesFontLeading), characterIndex: 2)
                    let b = metrics(layOut(withoutChip, usesFontLeading: usesFontLeading), characterIndex: 2)
                    XCTAssertEqual(a.lineRect.height, b.lineRect.height, accuracy: 0.001,
                                   "Line height changed by chip \(name) for \(font) usesFontLeading=\(usesFontLeading)")
                    XCTAssertEqual(a.baseline, b.baseline, accuracy: 0.001,
                                   "Text baseline moved by chip \(name) for \(font) usesFontLeading=\(usesFontLeading)")
                }
            }
        }
    }

    // A name with a fallback-font glyph (an emoji) may make the line taller,
    // but only as much as typing the name out as plain text would.
    func testChipWithEmojiAffectsLineLikePlainText() {
        let name = "\u{2733}\u{FE0F} Claude \u{1F600}"
        for font in fonts {
            let withChip = NSMutableAttributedString(attributedString: chip(name, font))
            withChip.append(plain(" echo hi", font))
            let typedOut = plain(name + " echo hi", font)

            let a = metrics(layOut(withChip), characterIndex: 2)
            let b = metrics(layOut(typedOut), characterIndex: (name as NSString).length + 1)
            XCTAssertLessThanOrEqual(a.lineRect.height, b.lineRect.height + 0.001,
                                     "Chip line taller than typed-out name for \(font)")
            XCTAssertLessThanOrEqual(a.baseline, b.baseline + 0.001,
                                     "Chip pushed the baseline lower than the typed-out name for \(font)")
        }
    }

    // Renders the laid-out text into a bitmap and returns, for each
    // column range, the topmost and bottommost rows containing ink (any
    // pixel that is not near white, so color emoji count).
    private func inkRows(_ layout: Layout, columns: [Range<Int>], scale: CGFloat) -> [(top: Int, bottom: Int)?] {
        let used = layout.layoutManager.usedRect(for: layout.container)
        let width = Int(ceil(used.width * scale)) + 4
        let height = Int(ceil(used.height * scale)) + 4
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width,
                                         pixelsHigh: height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            XCTFail("No bitmap")
            return []
        }
        rep.size = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        NSGraphicsContext.current = flipped
        flipped.cgContext.translateBy(x: 0, y: CGFloat(height) / scale)
        flipped.cgContext.scaleBy(x: 1, y: -1)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale).fill()
        let glyphs = layout.layoutManager.glyphRange(for: layout.container)
        layout.layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layout.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        NSGraphicsContext.restoreGraphicsState()

        func hasInk(_ x: Int, _ y: Int) -> Bool {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                return false
            }
            return min(color.redComponent, color.greenComponent, color.blueComponent) < 0.5
        }
        return columns.map { range in
            let clamped = range.clamped(to: 0..<width)
            let rows = (0..<height).filter { y in clamped.contains { x in hasInk(x, y) } }
            guard let top = rows.first, let bottom = rows.last else {
                return nil
            }
            return (top, bottom)
        }
    }

    // Device-pixel column ranges of the right third of the chip at
    // character 0 (where its name is drawn; the icon is on the left) and of
    // the plain text at `textRange`.
    private func columns(_ layout: Layout,
                         textRange: NSRange,
                         scale: CGFloat) -> (chip: Range<Int>, text: Range<Int>) {
        let chipGlyph = layout.layoutManager.glyphIndexForCharacter(at: 0)
        let chipRect = layout.layoutManager.boundingRect(forGlyphRange: NSRange(location: chipGlyph, length: 1),
                                                         in: layout.container)
        let textGlyphs = layout.layoutManager.glyphRange(forCharacterRange: textRange,
                                                         actualCharacterRange: nil)
        let textRect = layout.layoutManager.boundingRect(forGlyphRange: textGlyphs, in: layout.container)
        let chipColumns = Int((chipRect.maxX - chipRect.width / 3) * scale)..<Int((chipRect.maxX - 1) * scale)
        let textColumns = Int((textRect.minX + 1) * scale)..<Int((textRect.maxX - 1) * scale)
        return (chipColumns, textColumns)
    }

    func testChipNameSharesBaselineWithSurroundingText() {
        let scale: CGFloat = 4
        for font in fonts {
            // Only capital H so every glyph's top is the cap height above
            // the baseline: equal top rows means equal baselines.
            let attributed = NSMutableAttributedString(attributedString: chip("HHHH", font))
            attributed.append(plain(" HHHH", font))
            let layout = layOut(attributed)
            let (chipColumns, textColumns) = columns(layout, textRange: NSRange(location: 2, length: 4), scale: scale)
            let rows = inkRows(layout, columns: [chipColumns, textColumns], scale: scale)
            guard rows.count == 2, let chipInk = rows[0], let textInk = rows[1] else {
                XCTFail("No ink found for \(font)")
                continue
            }
            // Allow one device pixel for antialiasing at 4x.
            XCTAssertLessThanOrEqual(abs(chipInk.top - textInk.top), 1,
                                     "Chip name top row \(chipInk.top) vs text top row \(textInk.top) for \(font)")
        }
    }

    // QA finding F-330: on a 2x display the name inside the chip was drawn
    // one device pixel (0.5pt) below the adjacent text, because the chip's
    // edges sat a fraction of a point from the baseline and got rounded to
    // the pixel grid when drawn. The chip's box is whole points from the
    // baseline, so at 1x and 2x the name lands on the same rows as the text.
    func testChipNameSharesBaselineWithSurroundingTextOnPixelGrid() {
        for scale: CGFloat in [1, 2] {
            for font in fonts {
                let attributed = NSMutableAttributedString(attributedString: chip("HHHH", font))
                attributed.append(plain(" HHHH", font))
                let layout = layOut(attributed)
                let (chipColumns, textColumns) = columns(layout, textRange: NSRange(location: 2, length: 4), scale: scale)
                let rows = inkRows(layout, columns: [chipColumns, textColumns], scale: scale)
                guard rows.count == 2, let chipInk = rows[0], let textInk = rows[1] else {
                    XCTFail("No ink found for \(font) at \(scale)x")
                    continue
                }
                XCTAssertEqual(chipInk.top, textInk.top,
                               "Chip name top row vs text top row for \(font) at \(scale)x")
            }
        }
    }

    func testChipBoundsAreWholePointsFromBaseline() {
        for name in ["-zsh", "HHHH", "\u{00C9}lan", "\u{00C5}g\u{1F600}"] {
            for font in fonts {
                let attachment = ChatSessionMentionAttachment(guid: "guid", displayName: name)
                attachment.renderImage(font: font, color: .black)
                XCTAssertEqual(attachment.bounds.minY, attachment.bounds.minY.rounded(),
                               "Chip bottom off the point grid for \(name) in \(font)")
                XCTAssertEqual(attachment.bounds.maxY, attachment.bounds.maxY.rounded(),
                               "Chip top off the point grid for \(name) in \(font)")
            }
        }
    }

    // A name whose glyphs reach past the font's line box (an emoji, an
    // accented capital, a descender) must not be cut off by the chip's
    // image.
    func testChipNameIsNotClipped() {
        assertChipNameIsNotClipped(fonts: fonts)
    }

    // Fractional sizes give line boxes that aren't whole points, where the
    // chip can't round its edges outward (F-330) and must not clip instead.
    func testChipNameIsNotClippedWithFractionalLineBox() {
        var fractional: [NSFont] = [NSFont.systemFont(ofSize: 13.5),
                                    NSFont.monospacedSystemFont(ofSize: 12.3, weight: .regular)]
        for (name, size) in [("Menlo-Regular", 12.5), ("Courier", 14.7)] {
            if let font = NSFont(name: name, size: size) {
                fractional.append(font)
            }
        }
        assertChipNameIsNotClipped(fonts: fractional)
    }

    private func assertChipNameIsNotClipped(fonts: [NSFont]) {
        let scale: CGFloat = 4
        let name = "\u{00C5}g\u{1F600}\u{2733}\u{FE0F}"
        for font in fonts {
            let attributed = NSMutableAttributedString(attributedString: chip(name, font))
            attributed.append(plain(" " + name, font))
            let layout = layOut(attributed)
            let (chipColumns, textColumns) = columns(layout,
                                                     textRange: NSRange(location: 2, length: (name as NSString).length),
                                                     scale: scale)
            let rows = inkRows(layout, columns: [chipColumns, textColumns], scale: scale)
            guard rows.count == 2, let chipInk = rows[0], let textInk = rows[1] else {
                XCTFail("No ink found for \(font)")
                continue
            }
            // Plain text may overdraw its line fragment; the chip only has
            // to show what falls inside the line, as a chip may not make
            // the line taller than the same text typed out would.
            let lineRect = layout.layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let expectedTop = max(textInk.top, Int(floor(lineRect.minY * scale)))
            let expectedBottom = min(textInk.bottom, Int(ceil(lineRect.maxY * scale)) - 1)
            // The chip may reach lower than plain text (its underline) but
            // must reach at least as high and as low, within a pixel.
            XCTAssertLessThanOrEqual(chipInk.top, expectedTop + 1,
                                     "Chip name clipped at top (\(chipInk.top) vs \(expectedTop)) for \(font)")
            XCTAssertGreaterThanOrEqual(chipInk.bottom, expectedBottom - 1,
                                        "Chip name clipped at bottom (\(chipInk.bottom) vs \(expectedBottom)) for \(font)")
        }
    }
}
