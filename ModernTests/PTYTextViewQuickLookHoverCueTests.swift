//
//  PTYTextViewQuickLookHoverCueTests.swift
//  ModernTests
//
//  Opening a hover preview can take key from the terminal window, which resigns key and removes
//  underlines. The hover cue’s underline must survive those focus changes while its preview is
//  open, and must not linger when no preview is open.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTextViewQuickLookHoverCueTests: XCTestCase {
    private var textView: PTYTextView!
    private let cueRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(2, 1, 8, 1), 0, 0)
    private let otherRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, 3, 4, 3), 0, 0)

    override func setUp() {
        super.setUp()
        textView = PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }

    override func tearDown() {
        textView.webQuickLookPopover = nil
        textView = nil
        super.tearDown()
    }

    private func showCue(previewOpen: Bool) {
        textView.quickLookHoverCueURL = "https://example.com/"
        textView.quickLookHoverCueUnderlinedRange = cueRange
        textView.drawingHelper.underlinedRange = cueRange
        if previewOpen {
            textView.webQuickLookPopover = NSPopover()
            textView.webQuickLookPopoverOpenedByHover = true
        }
    }

    private func assertUnderline(_ expected: VT100GridAbsWindowedRange,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        let actual = textView.drawingHelper.underlinedRange
        XCTAssertTrue(VT100GridAbsWindowedRangeEquals(actual, expected),
                      "underline is \(VT100GridAbsWindowedRangeDescription(actual)), expected \(VT100GridAbsWindowedRangeDescription(expected))",
                      file: file,
                      line: line)
    }

    private func assertNoUnderline(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(textView.hasUnderline,
                       "underline is \(VT100GridAbsWindowedRangeDescription(textView.drawingHelper.underlinedRange))",
                       file: file,
                       line: line)
    }

    // PseudoTerminal calls this on every text view when its window resigns key.
    func testWindowResigningKeyKeepsCueWhilePreviewOpen() {
        showCue(previewOpen: true)

        _ = textView.removeUnderlineForFocusChange()

        assertUnderline(cueRange)
    }

    func testWindowResigningKeyRemovesCueWithoutOpenPreview() {
        showCue(previewOpen: false)

        _ = textView.removeUnderlineForFocusChange()

        assertNoUnderline()
    }

    func testWindowResigningKeyRemovesUnderlineWithoutCue() {
        textView.drawingHelper.underlinedRange = otherRange

        _ = textView.removeUnderlineForFocusChange()

        assertNoUnderline()
    }

    func testWindowResigningKeyReplacesOtherUnderlineWithCueWhilePreviewOpen() {
        showCue(previewOpen: true)
        textView.drawingHelper.underlinedRange = otherRange

        _ = textView.removeUnderlineForFocusChange()

        assertUnderline(cueRange)
    }

    func testResigningFirstResponderKeepsCueWhilePreviewOpen() {
        showCue(previewOpen: true)

        XCTAssertTrue(textView.resignFirstResponder())

        assertUnderline(cueRange)
    }

    func testResigningFirstResponderRemovesCueWithoutOpenPreview() {
        showCue(previewOpen: false)

        XCTAssertTrue(textView.resignFirstResponder())

        assertNoUnderline()
    }

    // Moving focus to another split pane leaves the window key, so only resigning first responder
    // tells this view. A pending cue must not survive to come back on the next underline update.
    func testResigningFirstResponderClearsPendingCue() {
        showCue(previewOpen: false)

        XCTAssertTrue(textView.resignFirstResponder())

        XCTAssertNil(textView.quickLookHoverCueURL, "underline updates put back the underline of a set cue")
        assertNoUnderline()
    }

    func testResigningFirstResponderKeepsCueOfOpenPreview() {
        showCue(previewOpen: true)

        XCTAssertTrue(textView.resignFirstResponder())

        XCTAssertEqual(textView.quickLookHoverCueURL, "https://example.com/")
    }

    func testBecomingFirstResponderRestoresCueWhilePreviewOpen() {
        showCue(previewOpen: true)
        textView.removeUnderline()

        XCTAssertTrue(textView.becomeFirstResponder())

        assertUnderline(cueRange)
    }

    func testBecomingFirstResponderDoesNotRestoreCueWithoutOpenPreview() {
        showCue(previewOpen: false)
        textView.removeUnderline()

        XCTAssertTrue(textView.becomeFirstResponder())

        assertNoUnderline()
    }

    // Called after the hover preview opens and when the terminal window becomes key again.
    func testRestoreAfterOpenPutsCueBack() {
        showCue(previewOpen: true)
        textView.removeUnderline()

        textView.quickLookHoverRestoreCueUnderline()

        assertUnderline(cueRange)
    }

    func testRestoreDoesNothingOnceCueIsCleared() {
        showCue(previewOpen: true)
        textView.quickLookHoverCueURL = nil
        textView.removeUnderline()

        textView.quickLookHoverRestoreCueUnderline()

        assertNoUnderline()
    }

    func testRestoreDoesNothingForDeliberatelyOpenedPreview() {
        showCue(previewOpen: true)
        textView.webQuickLookPopoverOpenedByHover = false
        textView.removeUnderline()

        textView.quickLookHoverRestoreCueUnderline()

        assertNoUnderline()
    }
}

// In Hover mode the cue shows on the pointer move that enters an OSC 8 hyperlink, from a cheap
// synchronous lookup. These drive a real PTYTextView over a real VT100Screen.
final class PTYTextViewQuickLookHoverImmediateCueTests: XCTestCase {
    private var session: FakeSession!
    private var screen: VT100Screen!
    private var textView: PTYTextView!

    override func setUp() {
        super.setUp()
        session = FakeSession()
        screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            mutableState.terminal?.encoding = String.Encoding.utf8.rawValue
            self.screen.destructivelySetScreenWidth(20, height: 5, mutableState: mutableState)
        })
        textView = PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.dataSource = screen
        // Real cell metrics, so points map to cells.
        let font = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.setFontTable(FontTable(ascii: PTYFontInfo(font: font), nonAscii: nil, browserZoom: 1.0),
                              horizontalSpacing: 1.0,
                              verticalSpacing: 1.0)
    }

    override func tearDown() {
        textView = nil
        screen = nil
        session = nil
        super.tearDown()
    }

    private func feed(_ string: String) {
        screen.inject(Data(string.utf8))
        screen.waitForQueuedTokensForTesting()
    }

    private func hyperlink(_ url: String, _ text: String) -> String {
        return "\u{1b}]8;;\(url)\u{1b}\\\(text)\u{1b}]8;;\u{1b}\\"
    }

    // A point inside the cell at (x, y).
    private func point(_ x: Int, _ y: Int) -> NSPoint {
        let margin: CGFloat = CGFloat(iTermPreferences.sideMargins())
        let column: CGFloat = CGFloat(x) + 0.25
        let row: CGFloat = CGFloat(y) + 0.5
        return NSPoint(x: margin + column * textView.charWidth, y: row * textView.lineHeight)
    }

    private func lookUp(_ x: Int, _ y: Int, plainText: Bool = false) -> iTermQuickLookHoverImmediateLink? {
        return textView.quickLookHoverImmediateLink(at: point(x, y), includesPlainTextURLs: plainText)
    }

    func testFindsTheWholeHyperlinkUnderThePointer() {
        // “link” covers cells 3 through 6 of the first line.
        feed("ab " + hyperlink("https://example.com/x", "link") + " cd")

        var urlId: NSString?
        var target: NSString?
        let cellURL = iTermTextExtractor(dataSource: screen).urlOfHypertextLink(at: VT100GridCoordMake(4, 0),
                                                                                urlId: &urlId,
                                                                                target: &target)
        XCTAssertEqual(cellURL, URL(string: "https://example.com/x"),
                       "precondition: the hyperlink is on the screen: \(screen.compactLineDump())")
        for x in 3...6 {
            let link = lookUp(x, 0)
            XCTAssertEqual(link?.url, URL(string: "https://example.com/x"), "cell \(x)")
            XCTAssertEqual(link?.rects.count, 1)
            XCTAssertTrue(link?.rects.first?.rectValue.contains(point(x, 0)) ?? false)
        }
        let rects = lookUp(4, 0)?.rects.map(\.rectValue) ?? []
        XCTAssertTrue(rects.first?.contains(point(3, 0)) ?? false, "covers the first cell")
        XCTAssertTrue(rects.first?.contains(point(6, 0)) ?? false, "covers the last cell")
        XCTAssertFalse(rects.first?.contains(point(2, 0)) ?? true)
        XCTAssertFalse(rects.first?.contains(point(7, 0)) ?? true)
    }

    func testShowingTheCueUnderlinesTheWholeLinkAtOnce() {
        feed("ab " + hyperlink("https://example.com/x", "link") + " cd")

        guard let url = lookUp(5, 0)?.url else {
            XCTFail("no link under the pointer")
            return
        }
        textView.quickLookHoverShowCue(for: url)

        XCTAssertEqual(textView.quickLookHoverCueURL, "https://example.com/x")
        let expected = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(3, 0, 7, 0), 0, 20)
        let actual = textView.drawingHelper.underlinedRange
        XCTAssertTrue(VT100GridAbsWindowedRangeEquals(actual, expected),
                      "underline is \(VT100GridAbsWindowedRangeDescription(actual))")
    }

    func testPlainTextIsNotALinkByDefault() {
        feed("see https://example.com/y here")

        let link = lookUp(8, 0)
        XCTAssertNotNil(link, "a definite answer, so nothing is resolved later")
        XCTAssertNil(link?.url)
    }

    func testPlainTextIsLeftToTheFullResolutionWhenIncluded() {
        feed("see https://example.com/y here")

        XCTAssertNil(lookUp(8, 0, plainText: true))
    }

    private func osc133(_ body: String) -> String {
        return "\u{1b}]133;\(body)\u{07}"
    }

    // ⌘-click on a prompt shows its command info instead of opening a hyperlink in it, so hover
    // must not cue or preview that hyperlink either.
    func testHyperlinkInsideAShellPromptIsNotALink() {
        // The prompt “x lnk ” has the hyperlink in cells 2 through 4; the command “ls” follows it.
        feed(osc133("A") + "x " + hyperlink("https://example.com/p", "lnk") + " " + osc133("B") +
             "ls\r\n" + osc133("C") + hyperlink("https://example.com/o", "out") + "\r\n")

        var range = VT100GridWindowedRange()
        XCTAssertNotNil(screen.commandMark(at: VT100GridCoordMake(3, 0), mustHaveCommand: true, range: &range),
                        "precondition: the prompt has a command mark: \(screen.compactLineDump())")
        let link = lookUp(3, 0)
        XCTAssertNotNil(link, "a definite answer, so nothing is resolved later")
        XCTAssertNil(link?.url)
        XCTAssertEqual(lookUp(1, 1)?.url, URL(string: "https://example.com/o"),
                       "a hyperlink in the command's output is still a link")
    }

    func testHyperlinksThatAreNotWebAddressesAreNotLinks() {
        feed(hyperlink("file:///tmp/z", "file") + " " + hyperlink("mailto:a@example.com", "mail"))

        XCTAssertNil(lookUp(1, 0)?.url)
        XCTAssertNil(lookUp(6, 0)?.url)
        let rects = lookUp(1, 0)?.rects.map(\.rectValue) ?? []
        XCTAssertEqual(rects.count, 1, "the extent, so moves inside the link can skip it")
        XCTAssertTrue(rects.first?.contains(point(0, 0)) ?? false)
        XCTAssertTrue(rects.first?.contains(point(3, 0)) ?? false)
        XCTAssertFalse(rects.first?.contains(point(5, 0)) ?? true)
        XCTAssertNotNil(lookUp(6, 0, plainText: true), "a definite answer even with plain text included")
    }
}
