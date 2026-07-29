//
//  WorkgroupIntrospectionMarkupTests.swift
//  iTerm2
//
//  Verifies the markup tokens get_screen_contents weaves into extracted
//  screen text: ⟨dim⟩…⟨/dim⟩ around faint text, ⟨cursor⟩ at the cursor
//  position, and ⟨image⟩ for inline images. The dim/cursor cases drive a
//  real VT100Screen through the terminal parser so they exercise the
//  whole pipeline (faint-bit detection, coord alignment, cursor
//  placement). The image cases drive renderAttributed directly because
//  synthesizing a real image cell in a headless test is impractical.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class WorkgroupIntrospectionMarkupTests: XCTestCase {

    private let dimOpen = "\u{27E8}dim\u{27E9}"
    private let dimClose = "\u{27E8}/dim\u{27E9}"
    private let cursor = "\u{27E8}cursor\u{27E9}"
    private let image = "\u{27E8}image\u{27E9}"

    // Keep a strong reference to the session: VT100Screen holds its
    // delegate weakly, so a local would be deallocated mid-test.
    private var session = FakeSession()

    private func makeScreen(width: Int = 40, height: Int = 5) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            mutableState.terminal?.encoding = String.Encoding.utf8.rawValue
            screen.destructivelySetScreenWidth(Int32(width),
                                                height: Int32(height),
                                                mutableState: mutableState)
        })
        return screen
    }

    // Feed raw bytes through the real parser, then flush the token
    // executor (via an empty joined block) so the effects are visible
    // synchronously. Token execution is scheduled asynchronously, so
    // reading the screen without this flush is racy.
    private func inject(_ screen: VT100Screen, _ string: String) {
        screen.inject(string.data(using: .utf8)!)
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private func extracted(_ screen: VT100Screen) -> String {
        return WorkgroupIntrospection.extractScreenText(ofScreen: screen,
                                                        fromLine: 0,
                                                        toLine: screen.numberOfLines())
    }

    // MARK: - Dim (faint) markup, end to end

    func testFaintTextIsWrappedInDimMarkup() {
        let screen = makeScreen()
        // "normal " then faint "faint" (SGR 2) then reset and " tail".
        inject(screen, "normal \u{1b}[2mfaint\u{1b}[0m tail")
        // Cursor ends just past "tail", so it lands at end of the line.
        XCTAssertEqual(extracted(screen),
                       "normal \(dimOpen)faint\(dimClose) tail\(cursor)")
    }

    // MARK: - Cursor markup, end to end

    func testCursorSitsBeforeFaintSuggestion() {
        let screen = makeScreen()
        // The headline case: typed "ls " followed by a faint suggestion
        // "-la", with the cursor parked just before the suggestion.
        inject(screen, "ls \u{1b}[2m-la\u{1b}[0m")
        inject(screen, "\u{1b}[4G")  // CHA to column 4 (0-based x=3), before "-la"
        XCTAssertEqual(extracted(screen),
                       "ls \(dimOpen)\(cursor)-la\(dimClose)")
    }

    func testCursorAtEndOfTypedInputDoesNotJumpToNextLine() {
        let screen = makeScreen()
        inject(screen, "first\r\nsecond")
        // Park the cursor at the end of "first" (row 1, col 6 -> y=0, x=5)
        // while a later line still has text. The marker must stay on the
        // cursor's own line rather than jumping to the start of "second".
        inject(screen, "\u{1b}[1;6H")
        XCTAssertEqual(extracted(screen),
                       "first\(cursor)\nsecond")
    }

    // MARK: - Image markup, via renderAttributed

    func testImageMarkupCollapsesConsecutiveCellsOfSameImage() {
        let img1 = NSImage(size: NSSize(width: 1, height: 1))
        let img2 = NSImage(size: NSSize(width: 1, height: 1))
        let input = NSMutableAttributedString(string: "a")
        // Two separate attachments pointing at the SAME image instance,
        // as the extractor produces for adjacent cells of one image.
        input.append(attachmentString(image: img1))
        input.append(attachmentString(image: img1))
        input.append(NSAttributedString(string: "b"))
        input.append(attachmentString(image: img2))
        input.append(NSAttributedString(string: "c"))

        let result = WorkgroupIntrospection.renderAttributed(input, cursorIndex: nil)
        XCTAssertEqual(result, "a\(image)b\(image)c")
    }

    // MARK: - All three markups composed

    func testDimImageAndCursorComposed() {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        let input = NSMutableAttributedString(string: "ab")
        input.append(NSAttributedString(
            string: "cd",
            attributes: [WorkgroupIntrospection.faintAttributeKey: true]))
        input.append(attachmentString(image: img))
        input.append(NSAttributedString(string: "e"))
        // Cursor at index 2: the boundary between "ab" and the faint "cd".
        let result = WorkgroupIntrospection.renderAttributed(input, cursorIndex: 2)
        XCTAssertEqual(result, "ab\(dimOpen)\(cursor)cd\(dimClose)\(image)e")
    }

    private func attachmentString(image: NSImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }
}
