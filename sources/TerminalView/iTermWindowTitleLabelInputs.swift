//
//  iTermWindowTitleLabelInputs.swift
//  iTerm2SharedARC
//
//  An immutable snapshot of everything that affects how the window title label
//  (iTermFakeWindowTitleLabel) renders. iTermRootTerminalView keeps the snapshot
//  it last rendered and skips the expensive attributed-string build + alignment
//  layout when the new inputs are equal. The title is polled ~once per second
//  per visible session even while idle, so without this guard many open windows
//  burn CPU rebuilding an identical label (issue 12982).
//

import AppKit

@objc(iTermWindowTitleLabelInputs)
class iTermWindowTitleLabelInputs: NSObject {
    private let title: String?
    private let subtitle: String?
    private let icon: NSImage?
    private let textColor: NSColor?
    private let font: NSFont?
    // The alignment (left vs. center) is a function of the available width, so
    // these geometry inputs must be part of equality even when the content is
    // unchanged (e.g. a live resize).
    private let width: CGFloat
    private let toolbeltWidth: CGFloat
    private let insets: NSEdgeInsets
    private let tabBarControlOnLoan: Bool
    // Whether the title string is rendered as HTML (kPreferenceKeyHTMLTabTitles)
    // and whether macOS 26 minimal titlebars force left alignment. Both change
    // the rendered result for identical content, so they belong in the key.
    private let parseHTML: Bool
    private let leftAlignTitleBarMinimalTahoe: Bool
    // The window's effective appearance (e.g. dark vs. light). The render bakes
    // the resolved text color into the attributed string, and normally a light
    // <-> dark switch changes textColor above and forces a rebuild on its own.
    // This is cheap insurance for the case where the title color happens to be
    // equal across appearances but something appearance-sensitive in the render
    // still differs; it is stable while idle so it never causes an extra rebuild.
    private let effectiveAppearanceName: String?
    // Fonts the PUA font provider resolves for the Private Use Area code points
    // in the title and subtitle. The label renders PUA (Nerd Font / Powerline)
    // glyphs with these fonts (see PSMApplyPUAFonts), which come from the current
    // session's terminal font, unrelated to the titlebar font captured above. So
    // when the terminal font changes these resolved fonts change and the label
    // must be rebuilt even though nothing else changed. Empty for the common case
    // of a title with no PUA code points.
    //
    // Note: when parseHTML is set this decodes the title/subtitle via the same
    // path the renderer uses (see PSMResolvedPUAFonts). For titles containing
    // b/i/u markup that means an HTML decode runs on every idle poll before the
    // isEqual: short-circuit. The common no-tag case early-outs cheaply inside
    // +newAttributedStringWithHTML:, and this is no worse than the pre-cache code
    // (which decoded during every render), so the savings are simply left on the
    // table for that narrow subset rather than adding a cross-poll decode cache.
    private let puaFonts: [NSFont]

    @objc(initWithTitle:subtitle:icon:textColor:font:width:toolbeltWidth:insets:tabBarControlOnLoan:parseHTML:leftAlignTitleBarMinimalTahoe:effectiveAppearanceName:puaFontProvider:)
    init(title: String?,
         subtitle: String?,
         icon: NSImage?,
         textColor: NSColor?,
         font: NSFont?,
         width: CGFloat,
         toolbeltWidth: CGFloat,
         insets: NSEdgeInsets,
         tabBarControlOnLoan: Bool,
         parseHTML: Bool,
         leftAlignTitleBarMinimalTahoe: Bool,
         effectiveAppearanceName: String?,
         puaFontProvider: PSMPUAFontProvider?) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.textColor = textColor
        self.font = font
        self.width = width
        self.toolbeltWidth = toolbeltWidth
        self.insets = insets
        self.tabBarControlOnLoan = tabBarControlOnLoan
        self.parseHTML = parseHTML
        self.leftAlignTitleBarMinimalTahoe = leftAlignTitleBarMinimalTahoe
        self.effectiveAppearanceName = effectiveAppearanceName
        // Fingerprint the code points that actually render, which means decoding
        // HTML the same way the renderer does when parseHTML is set.
        self.puaFonts = PSMResolvedPUAFonts(title ?? "", parseHTML, puaFontProvider) +
                        PSMResolvedPUAFonts(subtitle ?? "", parseHTML, puaFontProvider)
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? iTermWindowTitleLabelInputs else {
            return false
        }
        // The icon is compared by identity on purpose: NSImage is mutable, so
        // value-comparing two images would mean rendering both to bitmaps, but
        // iTermGraphicSource assigns a brand-new NSImage whenever the icon
        // changes and returns the same instance otherwise, so identity is
        // exactly the "did the icon change" signal we want. Everything else is
        // compared by value.
        return icon === other.icon &&
            title == other.title &&
            subtitle == other.subtitle &&
            textColor == other.textColor &&
            font == other.font &&
            width == other.width &&
            toolbeltWidth == other.toolbeltWidth &&
            insets.left == other.insets.left &&
            insets.right == other.insets.right &&
            insets.top == other.insets.top &&
            insets.bottom == other.insets.bottom &&
            tabBarControlOnLoan == other.tabBarControlOnLoan &&
            parseHTML == other.parseHTML &&
            leftAlignTitleBarMinimalTahoe == other.leftAlignTitleBarMinimalTahoe &&
            effectiveAppearanceName == other.effectiveAppearanceName &&
            puaFonts == other.puaFonts
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(subtitle)
        hasher.combine(icon.map { ObjectIdentifier($0) })
        hasher.combine(textColor)
        hasher.combine(font)
        hasher.combine(width)
        hasher.combine(toolbeltWidth)
        hasher.combine(insets.left)
        hasher.combine(insets.right)
        hasher.combine(insets.top)
        hasher.combine(insets.bottom)
        hasher.combine(tabBarControlOnLoan)
        hasher.combine(parseHTML)
        hasher.combine(leftAlignTitleBarMinimalTahoe)
        hasher.combine(effectiveAppearanceName)
        hasher.combine(puaFonts)
        return hasher.finalize()
    }
}
