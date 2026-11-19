//
//  PSMTabRichContentRenderer.swift
//  iTerm2SharedARC
//
//  Lays out and draws rich tab content lines (PSMTabRichLine) inside a tab
//  cell. Shared by the Yosemite and Tahoe tab styles. Assumes a flipped view,
//  as the tab bar is.
//
//  The block of lines is centered as if every line were present, so text
//  doesn't move when a line becomes empty. When the cell is too short for
//  every line, the lines that fit are centered instead. An empty line that collapses gives
//  its space to the lines below it; the row's height never changes. A line
//  whose text can wrap (maximumLines > 1) always takes the height of all its
//  lines. A line can ask for extra space before the next one, as a title does.
//

import AppKit

@objc(PSMTabRichContentRenderer)
final class PSMTabRichContentRenderer: NSObject {
    static func font(for line: PSMTabRichLine, baseFont: NSFont) -> NSFont {
        let size = max(1, round(baseFont.pointSize * line.scale * 2) / 2)
        var font = NSFont.systemFont(ofSize: size, weight: line.bold ? .semibold : .regular)
        if line.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static func height(for line: PSMTabRichLine, baseFont: NSFont) -> CGFloat {
        return singleLineHeight(for: line, baseFont: baseFont) * CGFloat(line.maximumLines)
    }

    private static func singleLineHeight(for line: PSMTabRichLine, baseFont: NSFont) -> CGFloat {
        let font = font(for: line, baseFont: baseFont)
        return ceil(font.ascender - font.descender + font.leading)
    }

    // Height of the whole block, counting every line whether or not it has
    // text. This is what the tab height is based on.
    @objc(contentHeightForLines:baseFont:)
    static func contentHeight(lines: [PSMTabRichLine], baseFont: NSFont) -> CGFloat {
        return lines.indices.reduce(0) {
            $0 + height(for: lines[$1], baseFont: baseFont) + spacing(after: $1, in: lines)
        }
    }

    // The space between a line and the next. None after the last line.
    private static func spacing(after index: Int, in lines: [PSMTabRichLine]) -> CGFloat {
        return index + 1 < lines.count ? lines[index].spacingAfter : 0
    }

    // Height of the band holding a collapsed tab group's name above its
    // lines: the preferred height when there's room, else less, so the lines
    // fit, but never less than minimum (the name's own height).
    @objc(nameBandHeightWithPreferred:minimum:available:lines:baseFont:bottomPadding:)
    static func nameBandHeight(preferred: CGFloat,
                               minimum: CGFloat,
                               available: CGFloat,
                               lines: [PSMTabRichLine],
                               baseFont: NSFont,
                               bottomPadding: CGFloat) -> CGFloat {
        let spare = available - contentHeight(lines: lines, baseFont: baseFont) - bottomPadding
        return max(minimum, min(preferred, spare))
    }

    // Width of the widest line's text, for styles that size the label to its
    // content. Text that can wrap counts at its unwrapped width (its widest
    // paragraph), so it wraps only when the tab can't be that wide.
    @objc(preferredWidthForLines:baseFont:)
    static func preferredWidth(lines: [PSMTabRichLine], baseFont: NSFont) -> CGFloat {
        return lines.reduce(0) { widest, line in
            let width = line.attributedText(attributes: [.font: font(for: line, baseFont: baseFont)]).size().width
            return max(widest, ceil(width))
        }
    }

    // One rect per line, in order. NSZeroRect for a line with nothing to draw
    // (an empty line, collapsed or not) or one that doesn't fit in rect.
    @objc(layoutLines:inRect:baseFont:)
    static func layout(lines: [PSMTabRichLine], in rect: NSRect, baseFont: NSFont) -> [NSRect] {
        var y = top(lines: lines, in: rect, baseFont: baseFont)
        var result = [NSRect]()
        for (index, line) in lines.enumerated() {
            let lineHeight = height(for: line, baseFont: baseFont) + spacing(after: index, in: lines)
            if line.isBlank {
                result.append(.zero)
                if !line.collapsesWhenEmpty {
                    y += lineHeight
                }
                continue
            }
            // Drop a line that doesn't fit rather than drawing it into the
            // neighboring cell (which wouldn't be redrawn when it changes).
            // Text that wraps keeps as many of its lines as fit.
            let single = singleLineHeight(for: line, baseFont: baseFont)
            let linesThatFit = min(line.maximumLines, Int(floor((rect.maxY - y) / single)))
            if linesThatFit < 1 {
                result.append(.zero)
                y += lineHeight
                continue
            }
            result.append(NSRect(x: rect.minX, y: y, width: rect.width, height: single * CGFloat(linesThatFit)))
            y += lineHeight
        }
        return result
    }

    // The block of lines is centered vertically in rect. When it doesn't all
    // fit, as when tabs are limited to fewer lines than the layout has, the
    // lines that fit are centered, so the tab keeps its padding.
    private static func top(lines: [PSMTabRichLine], in rect: NSRect, baseFont: NSFont) -> CGFloat {
        let height = heightOfLinesThatFit(lines: lines, in: rect.height, baseFont: baseFont)
        return rect.minY + max(0, floor((rect.height - height) / 2))
    }

    // The height of the lines, counting each line a line can wrap to, that
    // fit in available, taken in order. Like contentHeight, it counts every
    // line, empty or not.
    private static func heightOfLinesThatFit(lines: [PSMTabRichLine],
                                             in available: CGFloat,
                                             baseFont: NSFont) -> CGFloat {
        var used: CGFloat = 0
        for (index, line) in lines.enumerated() {
            let single = singleLineHeight(for: line, baseFont: baseFont)
            // The spacing before this line counts only if a row of it fits.
            let before = index > 0 ? spacing(after: index - 1, in: lines) : 0
            for row in 0..<line.maximumLines {
                let gap = row == 0 ? before : 0
                guard used + gap + single <= available else {
                    return used
                }
                used += gap + single
            }
        }
        return used
    }

    // The vertical center of the first line's first row, where a tab lines
    // up its icons and activity indicator. It depends only on the layout, not
    // on what the lines say, so an indicator positioned by it can't go stale
    // as text changes. When an empty first line collapses, the next one moves
    // up to the same top, so this is still close to that line's middle (off
    // by half the difference in their heights). The middle of rect when there
    // are no lines.
    @objc(firstLineMidYForLines:inRect:baseFont:)
    static func firstLineMidY(lines: [PSMTabRichLine], in rect: NSRect, baseFont: NSFont) -> CGFloat {
        guard let first = lines.first else {
            return rect.midY
        }
        return top(lines: lines, in: rect, baseFont: baseFont) + singleLineHeight(for: first, baseFont: baseFont) / 2
    }

    // colorAppearance picks between a line's light and dark colors. Pass the
    // style's accessoryAppearance, which is set when the bar is dark or light
    // regardless of the window's appearance. nil means the current drawing
    // appearance.
    @objc(drawLines:inRect:baseFont:textColor:secondaryColor:alignment:colorAppearance:)
    static func draw(lines: [PSMTabRichLine],
                     in rect: NSRect,
                     baseFont: NSFont,
                     textColor: NSColor,
                     secondaryColor: NSColor,
                     alignment: NSTextAlignment,
                     colorAppearance: NSAppearance? = nil) {
        draw(lines: lines,
             in: rect,
             baseFont: baseFont,
             textColor: textColor,
             secondaryColor: secondaryColor,
             alignment: alignment,
             colorAppearance: colorAppearance,
             highlight: nil)
    }

    // highlight is a tab bar search's query, whose matches are highlighted
    // (see PSMTabSearchHighlight).
    @objc(drawLines:inRect:baseFont:textColor:secondaryColor:alignment:colorAppearance:highlight:)
    static func draw(lines: [PSMTabRichLine],
                     in rect: NSRect,
                     baseFont: NSFont,
                     textColor: NSColor,
                     secondaryColor: NSColor,
                     alignment: NSTextAlignment,
                     colorAppearance: NSAppearance?,
                     highlight: String?) {
        let rects = layout(lines: lines, in: rect, baseFont: baseFont)
        for (line, lineRect) in zip(lines, rects) where lineRect != .zero {
            let text = attributedText(for: line,
                                      baseFont: baseFont,
                                      textColor: textColor,
                                      secondaryColor: secondaryColor,
                                      alignment: alignment,
                                      colorAppearance: colorAppearance,
                                      highlight: highlight)
            if line.maximumLines > 1 {
                text.draw(with: lineRect,
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                          context: nil)
            } else {
                text.draw(in: lineRect)
            }
        }
    }

    // A line as drawn.
    static func attributedText(for line: PSMTabRichLine,
                               baseFont: NSFont,
                               textColor: NSColor,
                               secondaryColor: NSColor,
                               alignment: NSTextAlignment,
                               colorAppearance: NSAppearance?,
                               highlight: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        // Text that wraps can only be cut off at its end.
        let wraps = line.maximumLines > 1
        paragraph.lineBreakMode = wraps ? .byWordWrapping : line.lineBreakMode
        paragraph.alignment = alignment
        let color = line.color(for: colorAppearance) ?? (line.secondary ? secondaryColor : textColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: line, baseFont: baseFont),
            .foregroundColor: color,
            .paragraphStyle: paragraph]
        return PSMTabSearchHighlight.highlighting(line.attributedText(attributes: attributes), query: highlight)
    }
}
