//
//  AboutBackersColumnsView.swift
//  iTerm2
//
//  Created by George Nachman on 11/6/26.
//

import AppKit

// Lays out the About window's backers in columns, like names on a memorial
// wall: each name in its own cell, filling down each column before moving to
// the next. Higher-tier backers form their own block above everyone else, on
// the same column grid so the two blocks line up.
@objc(iTermAboutBackersColumnsView)
class AboutBackersColumnsView: NSView {
    private static let fontSize: CGFloat = 11
    private static let rowHeight: CGFloat = 16
    private static let columnGutter: CGFloat = 16
    // A name wider than this is truncated rather than letting one long name
    // cost every column its width.
    private static let maxColumnWidth: CGFloat = 150
    private static let tierSpacing: CGFloat = 12
    private static let starSize: CGFloat = 9
    private static let starToNameGap: CGFloat = 3
    private static let inset = NSSize(width: 20, height: 16)

    private var higherTier = [String]()
    private var everyoneElse = [String]()
    private var message: String?

    override var isFlipped: Bool { true }

    // Replaces the names with a single centered line, for the loading and
    // error states.
    @objc func show(message: String) {
        self.message = message
        higherTier = []
        everyoneElse = []
        namesDidChange()
    }

    @objc func show(higherTier: [String], everyoneElse: [String]) {
        message = nil
        self.higherTier = higherTier.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        self.everyoneElse = everyoneElse.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        namesDidChange()
    }

    @objc(heightForWidth:)
    func height(forWidth width: CGFloat) -> CGFloat {
        var height = Self.inset.height * 2
        if message != nil {
            return height + Self.rowHeight
        }
        let grid = Grid(width: width, higherTier: higherTier, everyoneElse: everyoneElse)
        height += CGFloat(grid.higherTierRows + grid.everyoneElseRows) * Self.rowHeight
        if grid.higherTierRows > 0 && grid.everyoneElseRows > 0 {
            height += Self.tierSpacing
        }
        return height
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let message {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let string = NSAttributedString(string: message,
                                            attributes: [.font: Self.regularFont,
                                                         .foregroundColor: NSColor.secondaryLabelColor,
                                                         .paragraphStyle: paragraphStyle])
            draw(string, in: NSRect(x: Self.inset.width,
                                    y: Self.inset.height,
                                    width: bounds.width - Self.inset.width * 2,
                                    height: Self.rowHeight))
            return
        }
        let grid = Grid(width: bounds.width, higherTier: higherTier, everyoneElse: everyoneElse)
        var y = Self.inset.height
        if grid.higherTierRows > 0 {
            drawTier(higherTier, rows: grid.higherTierRows, grid: grid, top: y, starred: true)
            y += CGFloat(grid.higherTierRows) * Self.rowHeight + Self.tierSpacing
        }
        if grid.everyoneElseRows > 0 {
            drawTier(everyoneElse, rows: grid.everyoneElseRows, grid: grid, top: y, starred: false)
        }
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? {
        if let message {
            return message
        }
        // Localization unneeded
        return (higherTier + everyoneElse).joined(separator: ", ")
    }
}

private extension AboutBackersColumnsView {
    static var regularFont: NSFont { NSFont.systemFont(ofSize: fontSize) }
    static var higherTierFont: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .medium) }

    // One column grid shared by both tiers, sized to the widest name and
    // centered in the available width.
    struct Grid {
        var columns: Int
        var columnWidth: CGFloat
        var originX: CGFloat
        var higherTierRows: Int
        var everyoneElseRows: Int

        init(width: CGFloat, higherTier: [String], everyoneElse: [String]) {
            let available = max(0, width - AboutBackersColumnsView.inset.width * 2)
            let starWidth = AboutBackersColumnsView.starSize + AboutBackersColumnsView.starToNameGap
            let widest = max(higherTier.map { AboutBackersColumnsView.width(of: $0, font: AboutBackersColumnsView.higherTierFont) + starWidth }.max() ?? 0,
                             everyoneElse.map { AboutBackersColumnsView.width(of: $0, font: AboutBackersColumnsView.regularFont) }.max() ?? 0)
            let gutter = AboutBackersColumnsView.columnGutter
            columnWidth = min(max(1, ceil(widest)), AboutBackersColumnsView.maxColumnWidth, max(1, available))
            columns = max(1, Int((available + gutter) / (columnWidth + gutter)))
            let gridWidth = CGFloat(columns) * columnWidth + CGFloat(columns - 1) * gutter
            originX = AboutBackersColumnsView.inset.width + max(0, round((available - gridWidth) / 2))
            higherTierRows = (higherTier.count + columns - 1) / columns
            everyoneElseRows = (everyoneElse.count + columns - 1) / columns
        }

        func cellOrigin(index: Int, rows: Int, top: CGFloat) -> NSPoint {
            let column = index / rows
            let row = index % rows
            return NSPoint(x: originX + CGFloat(column) * (columnWidth + AboutBackersColumnsView.columnGutter),
                           y: top + CGFloat(row) * AboutBackersColumnsView.rowHeight)
        }
    }

    static func width(of name: String, font: NSFont) -> CGFloat {
        return (name as NSString).size(withAttributes: [.font: font]).width
    }

    func namesDidChange() {
        needsDisplay = true
    }

    // Names run down each column and then on to the next.
    func drawTier(_ names: [String], rows: Int, grid: Grid, top: CGFloat, starred: Bool) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: starred ? Self.higherTierFont : Self.regularFont,
            .foregroundColor: starred ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        let star = starred ? Self.starImage() : nil
        for (index, name) in names.enumerated() {
            let origin = grid.cellOrigin(index: index, rows: rows, top: top)
            var textRect = NSRect(x: origin.x, y: origin.y, width: grid.columnWidth, height: Self.rowHeight)
            if let star {
                let starRect = NSRect(x: origin.x,
                                      y: origin.y + round((Self.rowHeight - Self.starSize) / 2),
                                      width: Self.starSize,
                                      height: Self.starSize)
                star.draw(in: starRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                let offset = Self.starSize + Self.starToNameGap
                textRect.origin.x += offset
                textRect.size.width -= offset
            }
            draw(NSAttributedString(string: name, attributes: attributes), in: textRect)
        }
    }

    // Draws one line vertically centered in its row.
    func draw(_ string: NSAttributedString, in rect: NSRect) {
        let font = (string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) ?? Self.regularFont
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        var textRect = rect
        textRect.origin.y += round((rect.height - lineHeight) / 2)
        textRect.size.height = lineHeight
        string.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // Drawn as a symbol rather than the feed's emoji so it takes the type's
    // size and colour.
    static func starImage() -> NSImage? {
        let description = NSLocalizedString("AboutWindow.HigherTierBackerMarker",
                                            value: "Higher-tier backer",
                                            comment: "Accessibility description for the star shown before higher-tier backers in the about window")
        let config = NSImage.SymbolConfiguration(pointSize: starSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemYellow]))
        return NSImage(systemSymbolName: SFSymbol.starFill.rawValue, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
    }
}
