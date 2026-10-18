//
//  ChatInputMentionFontTests.swift
//  iTerm2 ModernTests
//
//  An @-mention chip in the AI chat input is a rasterized image baked for one
//  font. Changing the font of the input's text (Format > Font, or the Font
//  panel) must re-render the chip at the new size instead of leaving it at the
//  old one (QA finding F-371).
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatInputMentionFontTests: XCTestCase {
    private func makeMention(in storage: NSTextStorage, font: NSFont) throws -> ChatSessionMentionAttachment {
        storage.setAttributedString(
            ChatSessionMentionAttachment.attributedString(guid: "guid",
                                                          displayName: "host.local",
                                                          font: font,
                                                          color: .linkColor))
        return try XCTUnwrap(storage.attribute(.attachment, at: 0, effectiveRange: nil)
                             as? ChatSessionMentionAttachment)
    }

    func testChangingTheFontOfAMentionResizesItsChip() throws {
        let inputView = ChatInputView()
        let storage = try XCTUnwrap(inputView.textViewForTesting.textStorage)
        let mention = try makeMention(in: storage, font: NSFont.systemFont(ofSize: 13))
        let smallBounds = mention.bounds

        let big = NSFont.systemFont(ofSize: 28)
        storage.addAttribute(.font, value: big, range: NSRange(location: 0, length: storage.length))

        XCTAssertGreaterThan(mention.bounds.height, smallBounds.height * 1.5,
                             "the chip should grow with its font")
        XCTAssertGreaterThan(mention.bounds.width, smallBounds.width * 1.5)
        XCTAssertEqual(mention.renderedFont, big)
    }

    // An attribute edit over the chip that leaves its font alone (e.g. a
    // color change, or reapplying the same font) doesn't re-render it.
    func testAttributeEditWithTheSameFontDoesNotReRenderTheChip() throws {
        let inputView = ChatInputView()
        let storage = try XCTUnwrap(inputView.textViewForTesting.textStorage)
        let font = NSFont.systemFont(ofSize: 13)
        let mention = try makeMention(in: storage, font: font)
        storage.append(NSAttributedString(string: " hello", attributes: [.font: font]))
        let image = mention.image

        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))

        XCTAssertTrue(mention.image === image)
    }
}
