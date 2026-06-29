//
//  ChatTitleStyling.swift
//  iTerm2SharedARC
//
//  Shared decoration for chat titles in lists and menus: an orchestrator
//  badge (wand.and.rays) before the name, plus session-linkage helpers used
//  to pick weight/color. Keeping this in one place stops the inline panel's
//  switch-chat menu and the chat window's chat list from drifting apart.
//

import AppKit

extension Chat {
    // True when this chat is bound to the given terminal/browser session.
    func isLinked(toSessionGuid guid: String) -> Bool {
        return terminalSessionGuid == guid || browserSessionGuid == guid
    }
}

enum ChatTitleStyling {
    // Reusing the symbol lookup + configuration is the costly part on the
    // selection/scroll hot path, so cache the template by point size and the
    // tinted copy by (point size, resolved color). Tinted entries are keyed by
    // the color resolved to concrete sRGB components, so light/dark variants
    // of a dynamic color (resolved by the caller's effective appearance) get
    // distinct entries rather than colliding.
    private static let templateCache = NSCache<NSNumber, NSImage>()
    private static let tintedCache = NSCache<NSString, NSImage>()

    // Template wand.and.rays glyph for orchestrator chats. As a template
    // image it follows whatever tinting its host applies (NSMenu tints it for
    // light/dark and highlighted rows automatically); for plain text labels,
    // which don't tint template attachments, callers bake a color via
    // `orchestratorImage(pointSize:tint:)` and re-bake when the appearance or
    // selection changes.
    static func orchestratorTemplateImage(pointSize: CGFloat) -> NSImage? {
        let key = NSNumber(value: Double(pointSize))
        if let cached = templateCache.object(forKey: key) {
            return cached
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: SFSymbol.wandAndRays.rawValue,
                                  accessibilityDescription: "Orchestrator chat")?
            .withSymbolConfiguration(config) else {
            return nil
        }
        image.isTemplate = true
        templateCache.setObject(image, forKey: key)
        return image
    }

    // The orchestrator glyph baked to a concrete color, for text contexts
    // that won't tint a template attachment (NSTextField labels). Resolve
    // dynamic colors by calling inside the host's effective appearance.
    static func orchestratorImage(pointSize: CGFloat, tint: NSColor) -> NSImage? {
        let cacheKey: NSString? = (tint.usingColorSpace(.sRGB)).map { c in
            "\(pointSize)|\(c.redComponent)|\(c.greenComponent)|\(c.blueComponent)|\(c.alphaComponent)" as NSString
        }
        if let cacheKey, let cached = tintedCache.object(forKey: cacheKey) {
            return cached
        }
        guard let tinted = orchestratorTemplateImage(pointSize: pointSize)?.it_image(withTintColor: tint) else {
            return nil
        }
        if let cacheKey {
            tintedCache.setObject(tinted, forKey: cacheKey)
        }
        return tinted
    }

    // Title for a chat row or menu item: an optional leading orchestrator
    // glyph followed by the name, in the given font. Callers pick the weight
    // (e.g. bold for the current session). Pass color = nil to leave the text
    // color to the host: NSMenu inverts the title on a highlighted row only
    // when no foreground color is baked in, so menu items pass nil. Pass
    // includeGlyph: false when the host shows the glyph itself (e.g. a menu
    // item's template image) so it can tint it for selection/dark mode.
    static func attributedTitle(_ title: String,
                                orchestrator: Bool,
                                font: NSFont,
                                color: NSColor?,
                                includeGlyph: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // The embedded glyph can't be tinted by the host, so bake it to the
        // text color (or the label color when the host owns the text color).
        let glyphTint = color ?? .labelColor
        if includeGlyph, orchestrator, let image = orchestratorImage(pointSize: font.pointSize, tint: glyphTint) {
            let attachment = NSTextAttachment()
            attachment.image = image
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let color {
            attributes[.foregroundColor] = color
        }
        result.append(NSAttributedString(string: title, attributes: attributes))
        // An attributed string's default paragraph style wraps; force
        // single-line tail truncation so chat titles never spill onto a
        // second line (the host label/cell's lineBreakMode is ignored once
        // an attributed value is set).
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        result.addAttribute(.paragraphStyle,
                            value: paragraph,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
}
