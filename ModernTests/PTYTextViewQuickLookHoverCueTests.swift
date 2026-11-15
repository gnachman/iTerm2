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
