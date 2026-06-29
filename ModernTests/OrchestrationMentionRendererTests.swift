//
//  OrchestrationMentionRendererTests.swift
//  iTerm2 ModernTests
//
//  Exercises the string/attribute transformation in
//  OrchestrationMentionRenderer with an injected resolver, so we cover
//  matching, replacement, link styling, and the defunct-placeholder
//  path without standing up real sessions or workgroups.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class OrchestrationMentionRendererTests: XCTestCase {
    // Must match the literal OrchestrationMentionRenderer attaches; the
    // key itself is private, so we reconstruct it here.
    private let clickable = NSAttributedString.Key("ClickableAttribute")
    private let guid = "01234567-89ab-cdef-0123-456789abcdef"

    private func attr(_ string: String,
                      _ extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.black]
        attributes.merge(extra) { _, new in new }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private func resolveTo(_ name: String) -> OrchestrationMentionRenderer.Resolver {
        return { _, uuid in OrchestrationMentionRenderer.Resolved(displayName: name, revealGuid: uuid) }
    }

    private let resolveNone: OrchestrationMentionRenderer.Resolver = { _, _ in nil }

    // MARK: - Matching

    func test_noMentions_returnsInputUnchanged() {
        let input = attr("hello @world, this @abc is not a uuid")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveNone)
        XCTAssertEqual(out.string, input.string)
    }

    func test_emailAddress_notMatched() {
        let input = attr("ping me at foo@example.com")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue) { _, _ in
            XCTFail("resolver must not be called for a non-UUID token")
            return nil
        }
        XCTAssertEqual(out.string, input.string)
    }

    func test_trailingHexDigit_preventsPartialMatch() {
        // A 13th hex digit on the final group means it isn't a clean
        // UUID; the lookahead must reject it rather than matching the
        // first 12.
        let input = attr("id @\(guid)0 end")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue) { _, _ in
            XCTFail("resolver must not be called for an over-long id")
            return nil
        }
        XCTAssertEqual(out.string, input.string)
    }

    func test_uppercaseUuid_matched() {
        let upper = guid.uppercased()
        var captured: String?
        let out = OrchestrationMentionRenderer.link(attr("@\(upper)"), linkColor: .blue) { _, uuid in
            captured = uuid
            return OrchestrationMentionRenderer.Resolved(displayName: "U", revealGuid: uuid)
        }
        XCTAssertEqual(captured, upper)
        XCTAssertTrue(out.string.contains("U"))
        XCTAssertFalse(out.string.contains(upper))
    }

    // MARK: - Prefix parsing

    func test_prefixForms_parsedAndPassedToResolver() {
        var seen: [(prefix: String?, uuid: String)] = []
        let resolver: OrchestrationMentionRenderer.Resolver = { prefix, uuid in
            seen.append((prefix, uuid))
            return OrchestrationMentionRenderer.Resolved(displayName: "X", revealGuid: uuid)
        }
        let input = attr("a @\(guid) b @session:\(guid) c @wg-\(guid) d")
        _ = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolver)

        XCTAssertEqual(seen.count, 3)
        XCTAssertNil(seen[0].prefix)
        XCTAssertEqual(seen[0].uuid, guid)
        XCTAssertEqual(seen[1].prefix, "session:")
        XCTAssertEqual(seen[1].uuid, guid)
        XCTAssertEqual(seen[2].prefix, "wg-")
        XCTAssertEqual(seen[2].uuid, guid)
    }

    // MARK: - Replacement

    func test_resolvedMention_replacedWithLinkedName() {
        let input = attr("See @\(guid) now.")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveTo("Build"))
        // The name is present (with a leading icon glyph) and the raw
        // id is gone.
        XCTAssertTrue(out.string.contains("See "))
        XCTAssertTrue(out.string.contains("Build now."))
        XCTAssertFalse(out.string.contains(guid))

        let range = (out.string as NSString).range(of: "Build")
        let attrs = out.attributes(at: range.location, effectiveRange: nil)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, .blue)
        XCTAssertEqual(attrs[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNotNil(attrs[clickable] as? ((NSPoint) -> ()))
    }

    func test_resolvedMention_hasLeadingSessionIcon() {
        let input = attr("@\(guid)")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveTo("Build"))
        // The first character is an image attachment carrying the same
        // click action as the name.
        let attrs = out.attributes(at: 0, effectiveRange: nil)
        XCTAssertNotNil(attrs[.attachment] as? NSTextAttachment)
        XCTAssertNotNil(attrs[clickable] as? ((NSPoint) -> ()))
    }

    func test_unresolvedMention_replacedWithDefunctPlaceholder() {
        let input = attr("See @\(guid) now.")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveNone)
        XCTAssertEqual(out.string, "See [defunct session] now.")

        let range = (out.string as NSString).range(of: "defunct")
        let attrs = out.attributes(at: range.location, effectiveRange: nil)
        // The placeholder is plain text: no link styling, no click target.
        XCTAssertNil(attrs[clickable])
        XCTAssertNil(attrs[.underlineStyle])
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, .black)
    }

    func test_mentionAsEntireString() {
        let out = OrchestrationMentionRenderer.link(attr("@\(guid)"),
                                                    linkColor: .blue,
                                                    resolve: resolveTo("Solo"))
        XCTAssertTrue(out.string.contains("Solo"))
        XCTAssertFalse(out.string.contains(guid))
    }

    func test_multipleMentions_mixedResolution() {
        let other = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        let resolver: OrchestrationMentionRenderer.Resolver = { _, uuid in
            uuid == self.guid
                ? OrchestrationMentionRenderer.Resolved(displayName: "Alpha", revealGuid: uuid)
                : nil
        }
        let input = attr("x @\(guid) y @\(other) z")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolver)
        // Resolved mention becomes a name (with icon); defunct one is the
        // plain placeholder; surrounding text is preserved in order.
        XCTAssertTrue(out.string.contains("x "))
        XCTAssertTrue(out.string.contains("Alpha y [defunct session] z"))
        XCTAssertFalse(out.string.contains(guid))
        XCTAssertFalse(out.string.contains(other))
    }

    // MARK: - Attribute inheritance

    func test_baseFontAttribute_preservedOnLink() {
        let font = NSFont.systemFont(ofSize: 9)
        let input = attr("@\(guid)", [.font: font])
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveTo("Name"))
        let range = (out.string as NSString).range(of: "Name")
        let attrs = out.attributes(at: range.location, effectiveRange: nil)
        XCTAssertEqual(attrs[.font] as? NSFont, font)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, .blue)
    }

    func test_surroundingText_attributesPreserved() {
        let font = NSFont.systemFont(ofSize: 9)
        let input = attr("before @\(guid) after", [.font: font])
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveTo("Mid"))
        XCTAssertTrue(out.string.contains("before "))
        XCTAssertTrue(out.string.contains("Mid"))
        XCTAssertTrue(out.string.contains(" after"))

        let beforeAttrs = out.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(beforeAttrs[.font] as? NSFont, font)
        XCTAssertNil(beforeAttrs[clickable])

        let afterRange = (out.string as NSString).range(of: "after")
        let afterAttrs = out.attributes(at: afterRange.location, effectiveRange: nil)
        XCTAssertEqual(afterAttrs[.font] as? NSFont, font)
        XCTAssertNil(afterAttrs[clickable])
    }
}
