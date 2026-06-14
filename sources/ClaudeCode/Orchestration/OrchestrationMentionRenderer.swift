//
//  OrchestrationMentionRenderer.swift
//  iTerm2SharedARC
//
//  Turns @-prefixed session/workgroup identifiers in an orchestrator's
//  message into clickable links showing the entity's current name. The
//  orchestration system prompt tells the model to write a session_guid
//  or workgroup_id prefixed with "@" whenever it wants to point the user
//  at a specific session or workgroup; this is the rendering half of
//  that contract. A raw UUID means nothing to the user, so each
//  reference is replaced with the live name (clickable, reveals the
//  session) or the literal "[defunct session]" when it no longer
//  resolves to anything live.
//

import AppKit
import Foundation

enum OrchestrationMentionRenderer {
    // Matches "@" followed by a session/workgroup identifier:
    //   @<uuid>           a session_guid
    //   @session:<uuid>   a synthetic single-session workgroup_id
    //   @wg-<uuid>        a real workgroup instance id
    // The trailing lookahead keeps us from matching only a prefix of a
    // longer hex/dash run that merely starts like a UUID.
    private static let uuidPattern =
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    // Both prefixes are owned elsewhere (the workgroup mint and the
    // introspection payload builder); referencing the constants keeps
    // mention parsing from silently breaking if either ever changes.
    private static let workgroupPrefix = iTermWorkgroupInstance.instanceIDPrefix
    private static let sessionPrefix = WorkgroupIntrospection.syntheticWorkgroupIDPrefix
    private static let regex = try! NSRegularExpression(
        pattern: "@(\(NSRegularExpression.escapedPattern(for: sessionPrefix))|\(NSRegularExpression.escapedPattern(for: workgroupPrefix)))?(\(uuidPattern))(?![0-9A-Fa-f-])")

    // The marker keystroke for the in-process click handler lives on
    // ClickableTextView (see ToolCodecierge.swift). Using the same key
    // means @-mention links participate in the existing hover/click
    // machinery without registering a custom URL scheme.
    private static let clickableAttribute = NSAttributedString.Key("ClickableAttribute")

    // Resolved identity of a mention plus the guid to reveal on click.
    struct Resolved {
        let displayName: String
        // The session guid to reveal when the link is clicked. For a
        // workgroup this is its leader session, so clicking surfaces the
        // workgroup's main session.
        let revealGuid: String
    }

    // Maps a parsed mention to a live entity, or nil when it no longer
    // resolves. `prefix` is "session:" / "wg-" / nil (a bare guid);
    // `uuid` is the captured UUID. Injected so tests can drive the
    // string/attribute transformation without standing up real sessions.
    typealias Resolver = (_ prefix: String?, _ uuid: String) -> Resolved?

    // Replaces every @-prefixed session/workgroup mention in `input`
    // with a link to the live entity's name, or "[defunct session]"
    // when the identifier no longer resolves. Returns `input` unchanged
    // when there are no mentions.
    static func link(_ input: NSAttributedString, linkColor: NSColor) -> NSAttributedString {
        return link(input, linkColor: linkColor, resolve: liveResolve)
    }

    // Testable core: pure aside from the injected `resolve`.
    static func link(_ input: NSAttributedString,
                     linkColor: NSColor,
                     resolve: Resolver) -> NSAttributedString {
        let ns = input.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: input.string, range: fullRange)
        guard !matches.isEmpty else {
            return input
        }

        let result = NSMutableAttributedString()
        var cursor = 0
        for match in matches {
            let whole = match.range
            if whole.location > cursor {
                result.append(input.attributedSubstring(
                    from: NSRange(location: cursor, length: whole.location - cursor)))
            }
            // Inherit font/paragraph attributes from the first character
            // of the mention so the replacement matches the surrounding
            // text.
            let baseAttributes = input.attributes(at: whole.location, effectiveRange: nil)
            let prefix = match.range(at: 1).location == NSNotFound
                ? nil
                : ns.substring(with: match.range(at: 1))
            let uuid = ns.substring(with: match.range(at: 2))

            if let resolved = resolve(prefix, uuid) {
                result.append(linkString(for: resolved,
                                         baseAttributes: baseAttributes,
                                         linkColor: linkColor))
            } else {
                result.append(NSAttributedString(string: "[defunct session]",
                                                 attributes: baseAttributes))
            }
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result.append(input.attributedSubstring(
                from: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return result
    }

    private static func linkString(for resolved: Resolved,
                                   baseAttributes: [NSAttributedString.Key: Any],
                                   linkColor: NSColor) -> NSAttributedString {
        var attributes = baseAttributes
        attributes[.foregroundColor] = linkColor
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attributes[.underlineColor] = linkColor
        attributes[.cursor] = NSCursor.pointingHand
        let guid = resolved.revealGuid
        let action: (NSPoint) -> () = { _ in
            iTermController.sharedInstance()?.anySession(withGUID: guid)?.reveal()
        }
        attributes[clickableAttribute] = action

        // Prefix a terminal glyph so the user can tell at a glance the
        // link points at an iTerm2 session rather than the web. The
        // icon and the thin space between it and the name share the
        // link's click action, so the whole thing is one target.
        let result = NSMutableAttributedString()
        if let icon = iconString(font: baseAttributes[.font] as? NSFont,
                                 linkColor: linkColor,
                                 action: action) {
            result.append(icon)
            result.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
        }
        result.append(NSAttributedString(string: resolved.displayName, attributes: attributes))
        return result
    }

    // Builds an inline, link-tinted terminal glyph sized to the run's
    // font. Uses the same DynamicImage / .dynamicAttachment machinery as
    // the chat's code-copy buttons so ClickableTextView re-tints it when
    // the appearance flips. Returns nil if the SF Symbol is unavailable.
    private static func iconString(font: NSFont?,
                                   linkColor: NSColor,
                                   action: @escaping (NSPoint) -> ()) -> NSAttributedString? {
        guard let symbol = NSImage(systemSymbolName: "terminal",
                                   accessibilityDescription: "iTerm2 session") else {
            return nil
        }
        let dynamicImage = DynamicImage(image: symbol,
                                        dark: resolvedColor(linkColor, darkMode: true),
                                        light: resolvedColor(linkColor, darkMode: false))
        let attachment = NSTextAttachment()
        attachment.image = dynamicImage.tinted(forDarkMode: NSApp.effectiveAppearance.it_isDark)

        let height: CGFloat
        let y: CGFloat
        if let font {
            height = font.leading + font.ascender - font.descender
            y = font.descender
        } else {
            height = NSFont.systemFontSize
            y = 0
        }
        let aspectRatio = dynamicImage.image.size.width / dynamicImage.image.size.height
        attachment.bounds = NSRect(x: 0, y: y, width: height * aspectRatio, height: height)

        let string = NSMutableAttributedString(attachment: attachment)
        let range = NSRange(location: 0, length: string.length)
        string.addAttribute(clickableAttribute, value: action, range: range)
        string.addAttribute(.dynamicAttachment, value: dynamicImage, range: range)
        string.addAttribute(.cursor, value: NSCursor.pointingHand, range: range)
        return string
    }

    // Resolves a (possibly dynamic) color to its concrete value in the
    // given appearance, so the baked icon tint matches light/dark.
    private static func resolvedColor(_ color: NSColor, darkMode: Bool) -> NSColor {
        var resolved = color
        let name: NSAppearance.Name = darkMode ? .darkAqua : .aqua
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    // MARK: - Resolution

    // Live resolver: looks the identifier up in the running app.
    private static func liveResolve(prefix: String?, uuid: String) -> Resolved? {
        switch prefix {
        case workgroupPrefix:
            return resolveWorkgroup(instanceID: workgroupPrefix + uuid)
        case sessionPrefix:
            return resolveSession(guid: uuid)
        default:
            // A bare UUID is almost always a session_guid; fall back to
            // treating it as a workgroup instance id whose prefix the
            // model dropped.
            return resolveSession(guid: uuid) ?? resolveWorkgroup(instanceID: workgroupPrefix + uuid)
        }
    }

    private static func resolveSession(guid: String) -> Resolved? {
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: guid) else {
            return nil
        }
        // Use the shared mention naming so message bubbles match the picker and
        // the inserted token (workgroup role prefix, colon omitted when the
        // session has no title yet).
        return Resolved(displayName: ChatMentionDisplay.displayName(for: session), revealGuid: guid)
    }

    private static func resolveWorkgroup(instanceID: String) -> Resolved? {
        guard let instance = iTermWorkgroupController.instance.allInstances
            .first(where: { $0.instanceUniqueIdentifier == instanceID }),
              let leader = instance.mainSession else {
            return nil
        }
        let raw = instance.workgroup.name
        let name = raw.isEmpty ? "Untitled workgroup" : raw
        return Resolved(displayName: name, revealGuid: leader.guid)
    }
}
