//
//  CockpitComposerAttachmentCharacterTests.swift
//  ModernTests
//
//  QA finding F-376: copying Cockpit composer text that held an @-mention
//  chip and pasting it back left an invisible U+FFFC (the attachment
//  character) where the chip was, and Shift-Return then sent it to the
//  shell as part of the command. Copy and paste now drop the character,
//  and a send never includes one.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CockpitComposerAttachmentCharacterTests: XCTestCase {
    private let attachmentCharacter = "\u{FFFC}"
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("CockpitComposerAttachmentCharacterTests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func findComposer(in view: NSView) -> ComposerTextView? {
        if let composer = view as? ComposerTextView {
            return composer
        }
        for subview in view.subviews {
            if let composer = findComposer(in: subview) {
                return composer
            }
        }
        return nil
    }

    private func makeCockpitComposer() throws -> (iTermMinimalComposerViewController, ComposerTextView) {
        let composer = iTermMinimalComposerViewController()
        _ = composer.view
        composer.setComposerRichTextEnabled(true)
        let textView = try XCTUnwrap(findComposer(in: composer.view))
        return (composer, textView)
    }

    func testWholeFieldSendDropsStrayAttachmentCharacter() {
        // What pasting copied chip text used to leave: the character with
        // no attachment behind it.
        let attributed = NSAttributedString(string: attachmentCharacter + "   echo CHIP1")
        let (chips, command) = CockpitWindowController.chipTokensAndCommand(in: attributed, selectedText: nil)
        XCTAssertEqual(chips, [])
        XCTAssertEqual(command, "echo CHIP1")
    }

    func testWholeFieldSendWithChipAndStrayAttachmentCharacter() {
        let font = NSFont.systemFont(ofSize: 12)
        let attributed = NSMutableAttributedString(
            attributedString: ChatSessionMentionAttachment.attributedString(guid: "ptys_A",
                                                                            displayName: "A",
                                                                            font: font,
                                                                            color: .linkColor))
        attributed.append(NSAttributedString(string: " echo " + attachmentCharacter + "X"))
        let (chips, command) = CockpitWindowController.chipTokensAndCommand(in: attributed, selectedText: nil)
        XCTAssertEqual(chips, ["@ptys_A"])
        XCTAssertEqual(command, "echo X")
    }

    func testPasteDropsAttachmentCharacter() throws {
        let (composer, textView) = try makeCockpitComposer()
        pasteboard.clearContents()
        pasteboard.setString(attachmentCharacter + "  echo CHIP1", forType: .string)
        XCTAssertTrue(textView.pasteStrippingAttachmentCharacters(from: pasteboard))
        XCTAssertFalse(composer.attributedStringValue.string.contains(attachmentCharacter))
        XCTAssertEqual(composer.attributedStringValue.string, "  echo CHIP1")
    }

    func testPasteOfOnlyChipsLeavesTheSelectionAlone() throws {
        let (composer, textView) = try makeCockpitComposer()
        composer.replace(NSRange(location: 0, length: 0), with: NSAttributedString(string: "keep"))
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        pasteboard.clearContents()
        pasteboard.setString(attachmentCharacter, forType: .string)
        XCTAssertTrue(textView.pasteStrippingAttachmentCharacters(from: pasteboard))
        XCTAssertEqual(composer.attributedStringValue.string, "keep")
    }

    func testPasteWithoutAttachmentCharacterIsLeftToTheCaller() throws {
        let (_, textView) = try makeCockpitComposer()
        pasteboard.clearContents()
        pasteboard.setString("echo hi", forType: .string)
        XCTAssertFalse(textView.pasteStrippingAttachmentCharacters(from: pasteboard))
    }

    func testCopyDropsAttachmentCharacter() throws {
        let (composer, textView) = try makeCockpitComposer()
        let font = NSFont.systemFont(ofSize: 12)
        let contents = NSMutableAttributedString(
            attributedString: ChatSessionMentionAttachment.attributedString(guid: "ptys_A",
                                                                            displayName: "A",
                                                                            font: font,
                                                                            color: .linkColor))
        contents.append(NSAttributedString(string: " echo CHIP1", attributes: [.font: font]))
        composer.replace(NSRange(location: 0, length: composer.attributedStringValue.length), with: contents)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        pasteboard.clearContents()
        XCTAssertTrue(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertFalse(copied.contains(attachmentCharacter))
        XCTAssertEqual(copied, " echo CHIP1")
    }
}
