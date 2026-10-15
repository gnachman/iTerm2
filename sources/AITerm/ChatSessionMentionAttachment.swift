//
//  ChatSessionMentionAttachment.swift
//  iTerm2
//
//  An @-mention of a terminal session inside the AI chat compose field. The
//  user picks a session from the mention picker and we insert one of these as a
//  single NSTextAttachment. NSTextView treats an attachment (one U+FFFC
//  character) as an atomic unit for caret movement, selection, and deletion, so
//  the mention behaves as a single entity the user cannot edit a part of.
//
//  The attachment carries the session guid and renders as a terminal glyph plus
//  the session's name in the link color, matching how OrchestrationMentionRenderer
//  draws AI-generated mentions. When the message is sent,
//  NSAttributedString.chatMentionSerialized() turns each attachment back into
//  "@<guid>", which is exactly the form the orchestrator expects (and which
//  OrchestrationMentionRenderer parses on the way back).
//

import AppKit

class ChatSessionMentionAttachment: NSTextAttachment {
    let guid: String
    let displayName: String
    // SF Symbol drawn to the left of the name. Defaults to the terminal
    // glyph (a session); callers that mention a whole tab or window pass
    // a different symbol so the three kinds are visually distinct.
    let symbolName: String

    init(guid: String, displayName: String, symbolName: String = SFSymbol.terminal.rawValue) {
        self.guid = guid
        self.displayName = displayName
        self.symbolName = symbolName
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // Builds an atomic mention: a single attachment whose image is the glyph
    // + name, baseline-aligned to `font`. `color` should already be
    // resolved for the appearance the text view is currently showing.
    static func attributedString(guid: String,
                                 displayName: String,
                                 font: NSFont,
                                 color: NSColor,
                                 symbolName: String = SFSymbol.terminal.rawValue) -> NSAttributedString {
        let attachment = ChatSessionMentionAttachment(guid: guid, displayName: displayName, symbolName: symbolName)
        attachment.renderImage(font: font, color: color)
        // Carry the default font/label color on the attachment character itself.
        // When the caret sits next to the token (e.g. before a token that's the
        // first thing in the field) NSTextView seeds typingAttributes from this
        // character, so without these the next typed run would use a default
        // (black) color instead of the theme's text color.
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes([.font: font, .foregroundColor: NSColor.labelColor],
                             range: NSRange(location: 0, length: result.length))
        return result
    }

    // (Re)render this token's image for the given font and (already
    // appearance-resolved) color, and set its baseline-aligned bounds. The
    // token is a rasterized image, so callers must invoke this again when the
    // effective appearance changes or the baked link color goes stale.
    func renderImage(font: NSFont, color: NSColor) {
        let metrics = VerticalMetrics(font: font, displayName: displayName)
        let image = Self.tokenImage(displayName: displayName,
                                    font: font,
                                    color: color,
                                    symbolName: symbolName,
                                    metrics: metrics)
        self.image = image
        // The image's baseline sits `metrics.ascent` below its top, so an
        // origin of `metrics.descent` (negative) puts it on the surrounding
        // text's baseline. For a name that fits the font's line box, the
        // image stays within the ascent and descent that plain text in
        // `font` already gives the line, so the chip changes neither the
        // line's height nor where its baseline falls.
        self.bounds = NSRect(x: 0,
                             y: metrics.descent,
                             width: image.size.width,
                             height: image.size.height)
    }

    // The vertical box the token image occupies, relative to the baseline.
    // TextKit 1 lays a line of plain text out with its baseline at the
    // layout manager's rounded baseline offset, not at the font's exact
    // ascender (e.g. Menlo 12 has an 11.14pt ascender but an 11pt baseline
    // offset). An attachment taller than that pushes the baseline down and
    // makes the line taller, so the image never reaches past the line box
    // the name would get if it were typed as plain text. That box is the
    // font's own for most names and taller for one with a fallback-font
    // glyph such as an emoji, so a chip affects the line exactly as its
    // name typed out would. Within that box the image covers the name's
    // ink, so the image (which clips what it draws) cuts nothing off that
    // plain text would show inside its line.
    struct VerticalMetrics {
        // Distance from the baseline up to the top of the image.
        let ascent: CGFloat
        // Distance from the baseline down to the bottom of the image
        // (negative, like NSFont.descender).
        let descent: CGFloat

        init(font: NSFont, displayName: String) {
            // Without font leading this is the smallest box plain text
            // gets, so it holds whether or not the text view uses leading.
            let fontOnly = Self.lineBox(NSAttributedString(string: " ", attributes: [.font: font]))
            iconAscent = min(font.ascender, fontOnly.baseline)
            iconDescent = max(font.descender, fontOnly.baseline - fontOnly.height)

            let name = NSAttributedString(string: displayName, attributes: [.font: font])
            let plain = displayName.isEmpty ? fontOnly : Self.lineBox(name)
            // Without .usesLineFragmentOrigin the rect is relative to the
            // baseline origin with y increasing upward.
            let ink = name.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude),
                                        options: [.usesDeviceMetrics])
            let inkTop = ink.isEmpty ? 0 : ink.maxY
            let inkBottom = ink.isEmpty ? 0 : ink.minY
            let exactAscent = max(iconAscent, min(inkTop, plain.baseline))
            let exactDescent = min(iconDescent, max(inkBottom, plain.baseline - plain.height))
            // Put the image's edges whole points from the baseline. Plain
            // text's baseline lands on the pixel grid, so edges a fraction
            // of a point away got rounded to the grid when the chip was
            // drawn, moving the name off the adjacent text's baseline (a
            // device pixel low on a 2x display). Grow outward to the next
            // whole point when the line box has room; otherwise keep the
            // exact edge rather than clip the name.
            let lineTop = max(fontOnly.baseline, plain.baseline)
            let lineBottom = min(fontOnly.baseline - fontOnly.height, plain.baseline - plain.height)
            let roundedUp = ceil(exactAscent)
            ascent = roundedUp <= lineTop + 0.001 ? roundedUp : exactAscent
            let roundedDown = floor(exactDescent)
            descent = roundedDown >= lineBottom - 0.001 ? roundedDown : exactDescent
        }

        // The height of a single laid-out line of `string` and its
        // baseline's distance below the line's top, as TextKit 1 lays it
        // out without font leading.
        private static func lineBox(_ string: NSAttributedString) -> (height: CGFloat, baseline: CGFloat) {
            let storage = NSTextStorage(attributedString: string)
            let layoutManager = NSLayoutManager()
            layoutManager.usesFontLeading = false
            let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                         height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            layoutManager.ensureLayout(for: container)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            return (lineRect.height, layoutManager.location(forGlyphAt: 0).y)
        }

        // The icon fills the font's line box, whatever the name needs.
        let iconAscent: CGFloat
        let iconDescent: CGFloat

        var height: CGFloat { ascent - descent }
    }

    // Renders the glyph + underlined name to a resolution-independent image.
    private static func tokenImage(displayName: String,
                                   font: NSFont,
                                   color: NSColor,
                                   symbolName: String,
                                   metrics: VerticalMetrics) -> NSImage {
        let inner = innerAttributedString(displayName: displayName,
                                          font: font,
                                          color: color,
                                          symbolName: symbolName,
                                          metrics: metrics)
        let bounding = inner.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin])
        let size = NSSize(width: ceil(bounding.width), height: metrics.height)
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return NSImage(size: size, flipped: true) { rect in
            // Without .usesLineFragmentOrigin the rect's origin is the
            // baseline origin, so the name's baseline sits exactly
            // `metrics.ascent` below the top of the image.
            inner.draw(with: NSRect(x: rect.minX,
                                    y: rect.minY + metrics.ascent,
                                    width: rect.width,
                                    height: rect.height),
                       options: [])
            return true
        }
    }

    // The terminal glyph + thin space + underlined name, in `color`.
    private static func innerAttributedString(displayName: String,
                                              font: NSFont,
                                              color: NSColor,
                                              symbolName: String,
                                              metrics: VerticalMetrics) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let icon = iconString(color: color, symbolName: symbolName, metrics: metrics) {
            result.append(icon)
            result.append(NSAttributedString(string: "\u{2009}",
                                             attributes: [.font: font, .foregroundColor: color]))
        }
        result.append(NSAttributedString(string: displayName,
                                         attributes: [.font: font,
                                                      .foregroundColor: color,
                                                      .underlineStyle: NSUnderlineStyle.single.rawValue,
                                                      .underlineColor: color]))
        return result
    }

    // A glyph in `color`, sized to the run's font and embedded in an
    // attachment so it lays out inline with the name. It fills the font's
    // line box, which the token image always contains.
    private static func iconString(color: NSColor,
                                   symbolName: String,
                                   metrics: VerticalMetrics) -> NSAttributedString? {
        guard let symbol = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: String(localized: "ChatSessionMentionAttachment.SessionAccessibility", defaultValue: "iTerm2 session", comment: "Accessibility description for the session icon in a mention")) else {
            return nil
        }
        let height = metrics.iconAscent - metrics.iconDescent
        let aspectRatio = symbol.size.height > 0 ? symbol.size.width / symbol.size.height : 1
        // Render every layer in `color` at full opacity (monochrome).
        // it_image(withTintColor:) preserves a symbol's built-in
        // two-tone opacity, which makes macwindow's faint window body
        // read as washed out; a single-color palette flattens that.
        let tinted = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
            ?? symbol.it_image(withTintColor: color)
        let attachment = NSTextAttachment()
        attachment.image = tinted
        attachment.bounds = NSRect(x: 0, y: metrics.iconDescent, width: height * aspectRatio, height: height)
        return NSAttributedString(attachment: attachment)
    }
}

// Single source of truth for how a terminal session is named in chat mentions:
// the @-mention picker, the inserted token, and the rendered message bubbles all
// go through this so they stay consistent. A session inside a workgroup is
// prefixed with its component/role (e.g. "Diff", "Code Review", "Chat") so peers
// that haven't started yet, and therefore have no title, remain identifiable.
enum ChatMentionDisplay {
    // The (workgroup name, role/component name) a session belongs to, or nil for
    // a standalone session. Resolved the same way OrchestrationMentionRenderer
    // resolves workgroups, so it avoids the @MainActor-isolated
    // WorkgroupIntrospection.context(for:).
    static func context(for session: PTYSession) -> (workgroup: String, role: String)? {
        for instance in iTermWorkgroupController.instance.allInstances {
            for member in instance.resolvedMembers() where member.session === session {
                return (instance.workgroup.name, member.displayName)
            }
        }
        return nil
    }

    // The user-facing name for a session mention: "Role: title", or just "Role"
    // when the session has no title yet (colon omitted), or the bare title for a
    // standalone session.
    static func displayName(for session: PTYSession) -> String {
        let title = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let role = context(for: session)?.role.trimmingCharacters(in: .whitespacesAndNewlines),
           !role.isEmpty {
            return title.isEmpty ? role : "\(role): \(title)"
        }
        return title.isEmpty ? String(localized: "ChatSessionMentionAttachment.UntitledSession", defaultValue: "Untitled session", comment: "Fallback name for a terminal session with no title") : title
    }
}

extension NSAttributedString {
    // The plain-text form to send: every session mention becomes "@<guid>",
    // every other run contributes its literal characters. This is the inverse
    // of inserting ChatSessionMentionAttachments and the form the orchestrator
    // (and OrchestrationMentionRenderer) understands.
    func chatMentionSerialized() -> String {
        var result = ""
        let full = NSRange(location: 0, length: length)
        let ns = string as NSString
        enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            if let mention = value as? ChatSessionMentionAttachment {
                result += "@" + mention.guid
            } else if value == nil {
                result += ns.substring(with: range)
            }
            // Any other attachment type (none expected in this field) contributes
            // nothing rather than a stray object-replacement character.
        }
        return result
    }
}
