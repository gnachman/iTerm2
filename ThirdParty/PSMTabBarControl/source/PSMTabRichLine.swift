//
//  PSMTabRichLine.swift
//  iTerm2SharedARC
//
//  One line of rich tab content, already evaluated, as the tab bar needs it
//  to draw. The owner of a tab supplies these through
//  -[PSMTabBarControlRepresentedObjectIdentifierProtocol psmTabRichLines];
//  the tab bar never sees the configuration they came from.
//

import AppKit

@objc(PSMTabRichLine)
final class PSMTabRichLine: NSObject {
    @objc let text: String
    // Font size relative to the tab bar's normal title font.
    @objc let scale: CGFloat
    @objc let bold: Bool
    @objc let italic: Bool
    // nil means the tab's normal text color (or its secondary color when
    // secondary is set).
    @objc let color: NSColor?
    // Used instead of color under a dark appearance. nil means color is used
    // in both.
    @objc let darkColor: NSColor?
    @objc let secondary: Bool
    @objc let lineBreakMode: NSLineBreakMode
    // When the text is empty (or only whitespace), lines below move up into
    // this line's space. The row's height does not change.
    @objc let collapsesWhenEmpty: Bool
    // The text wraps onto at most this many lines, the last truncated. The
    // line always takes the height of all of them.
    @objc let maximumLines: Int
    // text is lightweight HTML (see +[NSAttributedString
    // fromLightweightHTML:attributes:]) rather than plain text.
    @objc let html: Bool
    // Extra space between this line and the next, as under a title. None
    // when nothing follows, or when the line is empty and collapses.
    @objc let spacingAfter: CGFloat
    // Whether an HTML line's <font color> applies. lineWithoutColor turns it
    // off.
    private let usesMarkupColors: Bool

    @objc convenience init(text: String,
                           scale: CGFloat,
                           bold: Bool,
                           italic: Bool,
                           color: NSColor?,
                           darkColor: NSColor? = nil,
                           secondary: Bool,
                           lineBreakMode: NSLineBreakMode,
                           collapsesWhenEmpty: Bool,
                           maximumLines: Int = 1,
                           html: Bool = false,
                           spacingAfter: CGFloat = 0) {
        self.init(text: text,
                  scale: scale,
                  bold: bold,
                  italic: italic,
                  color: color,
                  darkColor: darkColor,
                  secondary: secondary,
                  lineBreakMode: lineBreakMode,
                  collapsesWhenEmpty: collapsesWhenEmpty,
                  maximumLines: maximumLines,
                  html: html,
                  spacingAfter: spacingAfter,
                  usesMarkupColors: true)
    }

    // text with attributes applied to all of it, and HTML markup applied.
    func attributedText(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard html else {
            return NSAttributedString(string: text, attributes: attributes)
        }
        let parsed = NSAttributedString.fromLightweightHTML(text, attributes: attributes)
        guard !usesMarkupColors, parsed.length > 0 else {
            return parsed
        }
        let uncolored = NSMutableAttributedString(attributedString: parsed)
        let range = NSRange(location: 0, length: uncolored.length)
        if let color = attributes[.foregroundColor] {
            uncolored.addAttribute(.foregroundColor, value: color, range: range)
        } else {
            uncolored.removeAttribute(.foregroundColor, range: range)
        }
        return uncolored
    }

    // The text a reader sees: without markup, for an HTML line.
    @objc private(set) lazy var visibleText: String = {
        return html ? attributedText(attributes: [:]).string : text
    }()

    // The same line in the normal (or secondary) text color, ignoring any
    // colors in its markup.
    @objc var lineWithoutColor: PSMTabRichLine {
        return PSMTabRichLine(text: text,
                              scale: scale,
                              bold: bold,
                              italic: italic,
                              color: nil,
                              darkColor: nil,
                              secondary: secondary,
                              lineBreakMode: lineBreakMode,
                              collapsesWhenEmpty: collapsesWhenEmpty,
                              maximumLines: maximumLines,
                              html: html,
                              spacingAfter: spacingAfter,
                              usesMarkupColors: false)
    }

    private init(text: String,
                 scale: CGFloat,
                 bold: Bool,
                 italic: Bool,
                 color: NSColor?,
                 darkColor: NSColor?,
                 secondary: Bool,
                 lineBreakMode: NSLineBreakMode,
                 collapsesWhenEmpty: Bool,
                 maximumLines: Int,
                 html: Bool,
                 spacingAfter: CGFloat,
                 usesMarkupColors: Bool) {
        self.text = text
        self.scale = scale
        self.bold = bold
        self.italic = italic
        self.color = color
        self.darkColor = darkColor
        self.secondary = secondary
        self.lineBreakMode = lineBreakMode
        self.collapsesWhenEmpty = collapsesWhenEmpty
        self.maximumLines = max(1, maximumLines)
        self.html = html
        self.spacingAfter = max(0, spacingAfter)
        self.usesMarkupColors = usesMarkupColors
    }

    // The color to draw in on a bar with this appearance (the current drawing
    // appearance when nil), or nil for the tab's normal (or secondary) text
    // color.
    func color(for appearance: NSAppearance?) -> NSColor? {
        guard let darkColor else {
            return color
        }
        let names: [NSAppearance.Name] = [.darkAqua, .vibrantDark, .aqua, .vibrantLight]
        switch (appearance ?? NSAppearance.currentDrawing()).bestMatch(from: names) {
        case .darkAqua, .vibrantDark:
            return darkColor
        default:
            return color
        }
    }

    @objc var isBlank: Bool {
        return visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PSMTabRichLine else {
            return false
        }
        return text == other.text &&
            scale == other.scale &&
            bold == other.bold &&
            italic == other.italic &&
            color == other.color &&
            darkColor == other.darkColor &&
            secondary == other.secondary &&
            lineBreakMode == other.lineBreakMode &&
            collapsesWhenEmpty == other.collapsesWhenEmpty &&
            maximumLines == other.maximumLines &&
            html == other.html &&
            spacingAfter == other.spacingAfter &&
            usesMarkupColors == other.usesMarkupColors
    }

    override var hash: Int {
        return text.hashValue
    }

    override var description: String {
        return "<PSMTabRichLine \(text.debugDescription) scale=\(scale) bold=\(bold) collapses=\(collapsesWhenEmpty) lines=\(maximumLines) html=\(html) spacingAfter=\(spacingAfter)>"
    }
}
