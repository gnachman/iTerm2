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

    // The visible text with the inline terminal glyph (U+FFFC object
    // replacement char) and its trailing thin space (U+2009) removed, so an
    // exact-string assert covers ordering and accidental duplication despite
    // the icon runs each mention adds.
    private func visibleText(_ attributed: NSAttributedString) -> String {
        return attributed.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "")
    }

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

    func test_unresolvedMention_renderedAsGrayedNonClickableMention() {
        let input = attr("See @\(guid) now.")
        let out = OrchestrationMentionRenderer.link(input, linkColor: .blue, resolve: resolveNone)

        // The raw id is gone, replaced with the "[defunct session]" label
        // (same bracketed wording the phone renderers use). Assert the whole
        // visible text so ordering and any accidental duplication are covered,
        // not just presence.
        XCTAssertFalse(out.string.contains(guid))
        XCTAssertEqual(visibleText(out), "See [defunct session] now.")

        // The label is grayed and carries no link styling or click target.
        let range = (out.string as NSString).range(of: "defunct")
        let attrs = out.attributes(at: range.location, effectiveRange: nil)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, .secondaryLabelColor)
        XCTAssertNil(attrs[clickable])
        XCTAssertNil(attrs[.underlineStyle])

        // Like a live mention it gets a leading terminal glyph (the char
        // right after "See "), but that glyph is not a click target either.
        let iconAttrs = out.attributes(at: 4, effectiveRange: nil)
        XCTAssertNotNil(iconAttrs[.attachment] as? NSTextAttachment)
        XCTAssertNil(iconAttrs[clickable])
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
        // Resolved mention becomes a name (with icon); defunct one becomes the
        // grayed "[defunct session]" mention; surrounding text is preserved in
        // order. Strip the glyphs/thin spaces and assert the whole visible
        // text so ordering and duplication stay covered.
        XCTAssertEqual(visibleText(out), "x Alpha y [defunct session] z")
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

    // MARK: - Markdown

    // Two stableIDs in one paragraph put an underscore before each body, which
    // markdown pairs up as emphasis delimiters. Without protection the
    // underscores are consumed and the ids render as dead "ptysXXXX" text.
    func test_linkMarkdown_stableIDUnderscoresSurviveMarkdown() {
        let first = StableSessionID.generate()
        let second = StableSessionID.generate()
        let markdown = "Done, @\(first) finished, so I told @\(second) to re-run its tests."
        let rendered = OrchestrationMentionRenderer.restore(MentionParser.protect(markdown)) {
            AttributedStringForGPTMarkdown($0, linkColor: .blue, textColor: .black) {}
        }
        XCTAssertEqual(rendered.string, markdown)
        XCTAssertEqual(MentionParser.mentions(in: rendered.string).map(\.token), [first, second])
    }

    func test_linkMarkdown_markdownOutsideMentionsStillRendered() {
        let id = StableSessionID.generate()
        let rendered = OrchestrationMentionRenderer.restore(MentionParser.protect("**bold** @\(id)")) {
            AttributedStringForGPTMarkdown($0, linkColor: .blue, textColor: .black) {}
        }
        XCTAssertEqual(rendered.string, "bold @\(id)")
    }

    func test_protect_noMentions_isIdentity() {
        let protected = MentionParser.protect("plain _text_ here")
        XCTAssertEqual(protected.text, "plain _text_ here")
        XCTAssertTrue(protected.substitutions.isEmpty)
    }

    // A code block's copy button captures the renderer's pre-restore string, so
    // a placeholder inside a code block would end up on the pasteboard. Code
    // isn't subject to emphasis parsing, so mentions there are left alone.
    func test_protect_skipsFencedCodeBlock() {
        let id = StableSessionID.generate()
        let markdown = "Run this:\n```\nit2 session send --session @\(id) make\n```\nThen @\(id)"
        let protected = MentionParser.protect(markdown)
        XCTAssertEqual(protected.substitutions.map(\.original), ["@\(id)"])
        let fence = (protected.text as NSString).range(of: "```\nit2 session send --session @\(id) make\n```")
        XCTAssertNotEqual(fence.location, NSNotFound)

        let rendered = OrchestrationMentionRenderer.restore(protected) {
            AttributedStringForGPTMarkdown($0, linkColor: .blue, textColor: .black) {}
        }
        XCTAssertFalse(rendered.string.contains("iTermMention"))
        XCTAssertTrue(rendered.string.contains("--session @\(id) make"))
    }

    // SwiftyMarkdown also makes a line indented by four spaces or a tab a code
    // block with a copy button, nested list items included.
    func test_protect_skipsIndentedCodeLines() {
        let id = StableSessionID.generate()
        for line in ["    it2 session send --session @\(id) make",
                     "\tit2 session send --session @\(id) make",
                     "    - ask @\(id) to rerun"] {
            let markdown = "Steps:\n\(line)\nThen @\(id)"
            let protected = MentionParser.protect(markdown, indentedCodeBlocks: true)
            XCTAssertEqual(protected.substitutions.map(\.original), ["@\(id)"], line)
            XCTAssertTrue(protected.text.contains("\n\(line)\n"), line)

            let rendered = OrchestrationMentionRenderer.restore(protected) {
                AttributedStringForGPTMarkdown($0, linkColor: .blue, textColor: .black) {}
            }
            XCTAssertFalse(rendered.string.contains("iTermMention"), line)
        }
    }

    // SwiftyMarkdown matches its tab-indented list tokens before the tab code
    // rule, so those lines are prose and still get protected.
    func test_protect_tabIndentedListItemsStillProtected() {
        let id = StableSessionID.generate()
        for line in ["\t- ask @\(id)", "\t* ask @\(id)", "\t1. ask @\(id)", "\t\t- ask @\(id)"] {
            let protected = MentionParser.protect(line, indentedCodeBlocks: true)
            XCTAssertEqual(protected.substitutions.map(\.original), ["@\(id)"], line)
        }
    }

    // The phone's inline-only markdown has no indented code blocks, so by
    // default an indented line is protected like any other.
    func test_protect_indentedLinesProtectedByDefault() {
        let id = StableSessionID.generate()
        let protected = MentionParser.protect("    - ask @\(id) to rerun")
        XCTAssertEqual(protected.substitutions.map(\.original), ["@\(id)"])
    }

    func test_protect_skipsInlineCode() {
        let id = StableSessionID.generate()
        let protected = MentionParser.protect("use `@\(id)` here")
        XCTAssertTrue(protected.substitutions.isEmpty)
    }

    // A placeholder in a link destination lands only in the .link attribute,
    // where restore can't see it, so link targets are left alone.
    func test_protect_skipsLinkDestinationsAndURLs() {
        let id = StableSessionID.generate()
        for markdown in ["[the build session](iterm2:reveal/@\(id))",
                         "<iterm2:reveal/\(id)>",
                         "see https://example.com/\(id) now"] {
            let protected = MentionParser.protect(markdown)
            XCTAssertTrue(protected.substitutions.isEmpty, markdown)
            XCTAssertEqual(protected.text, markdown)
        }
    }

    func test_protect_linkTextIsStillProtected() {
        let id = StableSessionID.generate()
        let other = StableSessionID.generate()
        let protected = MentionParser.protect("[@\(id)](https://example.com) and @\(other)")
        XCTAssertEqual(Set(protected.substitutions.map(\.original)), ["@\(id)", "@\(other)"])
    }
}
