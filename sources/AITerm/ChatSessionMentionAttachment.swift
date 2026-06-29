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

    init(guid: String, displayName: String) {
        self.guid = guid
        self.displayName = displayName
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // Builds an atomic mention: a single attachment whose image is the terminal
    // glyph + name, baseline-aligned to `font`. `color` should already be
    // resolved for the appearance the text view is currently showing.
    static func attributedString(guid: String,
                                 displayName: String,
                                 font: NSFont,
                                 color: NSColor) -> NSAttributedString {
        let attachment = ChatSessionMentionAttachment(guid: guid, displayName: displayName)
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
        let image = Self.tokenImage(displayName: displayName, font: font, color: color)
        self.image = image
        // The image is rendered with its single text line laid out from the top
        // (flipped drawing handler), so the baseline sits `ascender` below the
        // image top. Offsetting bounds by ascender - height puts that baseline
        // on the surrounding text's baseline. (Mirrors the descender-based
        // offset OrchestrationMentionRenderer.iconString uses for its glyph.)
        self.bounds = NSRect(x: 0,
                             y: font.ascender - image.size.height,
                             width: image.size.width,
                             height: image.size.height)
    }

    // Renders the glyph + underlined name to a resolution-independent image.
    private static func tokenImage(displayName: String,
                                   font: NSFont,
                                   color: NSColor) -> NSImage {
        let inner = innerAttributedString(displayName: displayName, font: font, color: color)
        let bounding = inner.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin])
        let size = NSSize(width: ceil(bounding.width), height: ceil(bounding.height))
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return NSImage(size: size, flipped: true) { rect in
            inner.draw(with: rect, options: [.usesLineFragmentOrigin])
            return true
        }
    }

    // The terminal glyph + thin space + underlined name, in `color`.
    private static func innerAttributedString(displayName: String,
                                              font: NSFont,
                                              color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let icon = iconString(font: font, color: color) {
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

    // A terminal glyph tinted to `color`, sized to the run's font and embedded
    // in an attachment so it lays out inline with the name.
    private static func iconString(font: NSFont, color: NSColor) -> NSAttributedString? {
        guard let symbol = NSImage(systemSymbolName: SFSymbol.terminal.rawValue,
                                   accessibilityDescription: "iTerm2 session") else {
            return nil
        }
        let height = font.ascender - font.descender
        let aspectRatio = symbol.size.height > 0 ? symbol.size.width / symbol.size.height : 1
        let tinted = symbol.it_image(withTintColor: color)
        let attachment = NSTextAttachment()
        attachment.image = tinted
        attachment.bounds = NSRect(x: 0, y: font.descender, width: height * aspectRatio, height: height)
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
        return title.isEmpty ? "Untitled session" : title
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
