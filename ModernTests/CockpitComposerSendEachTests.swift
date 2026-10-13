//
//  CockpitComposerSendEachTests.swift
//  ModernTests
//
//  In the cockpit, the composer holds @-mention chips (attachments) naming
//  the target sessions plus the typed command. Opt-Shift-Return (send each)
//  and Opt-Return (enqueue each) used to extract the command as a plain
//  string and delete it, chip included, from the text view before telling
//  the delegate. The cockpit reads the composer's attributed contents to
//  find its targets, found nothing, and sent nothing: the input vanished.
//  With rich text (chips) enabled, these keys now act like Shift-Return.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
private final class NoopSyntaxHighlighter: NSObject, SyntaxHighlighting {
    func highlight(range: NSRange) {}
}

@MainActor
private final class FakeCockpitComposerDelegate: NSObject, @MainActor iTermMinimalComposerViewControllerDelegate {
    struct Send {
        var command: String
        // What the cockpit would read from the composer when handling the send.
        var contents: NSAttributedString
    }
    weak var composer: iTermMinimalComposerViewController?
    var sends: [Send] = []
    var enqueues: [String] = []

    func minimalComposer(_ composer: iTermMinimalComposerViewController, sendCommand command: String, addNewline: Bool, dismiss: Bool) {
        sends.append(Send(command: command, contents: composer.attributedStringValue))
    }
    func minimalComposer(_ composer: iTermMinimalComposerViewController, enqueueCommand command: String, dismiss: Bool) {
        enqueues.append(command)
    }
    func minimalComposer(_ composer: iTermMinimalComposerViewController, sendControl control: String) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, sendToAdvancedPaste content: String) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, frameForHeight desiredHeight: CGFloat) -> NSRect {
        return NSRect(x: 0, y: 0, width: 400, height: 200)
    }
    func minimalComposerMaximumHeight(_ composer: iTermMinimalComposerViewController) -> CGFloat { 200 }
    func minimalComposer(_ composer: iTermMinimalComposerViewController, frameDidChangeTo newFrame: NSRect) {}
    func minimalComposerLineHeight(_ composer: iTermMinimalComposerViewController) -> CGFloat { 14 }
    func minimalComposerOpenHistory(_ composer: iTermMinimalComposerViewController, prefix: String, forSearch: Bool) {}
    func minimalComposerShowCompletions(_ completions: [String]) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, wantsKeyEquivalent event: NSEvent) -> Bool { false }
    func minimalComposer(_ composer: iTermMinimalComposerViewController, performFindPanelAction sender: Any) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, desiredHeightDidChange desiredHeight: CGFloat) {}
    func minimalComposerAutoComposerTextDidChange(_ composer: iTermMinimalComposerViewController) {}
    func minimalComposerClear(_ composer: iTermMinimalComposerViewController) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         syntaxHighlighterFor attributedString: NSMutableAttributedString) -> SyntaxHighlighting {
        return NoopSyntaxHighlighter()
    }
    func minimalComposerDidBecomeFirstResponder(_ composer: iTermMinimalComposerViewController) {}
    func minimalComposerShouldFetchSuggestions(_ composer: iTermMinimalComposerViewController,
                                               forHost remoteHost: VT100RemoteHostReading,
                                               tmuxController: TmuxController) -> Bool { false }
    func minimalComposer(_ composer: iTermMinimalComposerViewController, fetchSuggestions request: SuggestionRequest, byUserRequest: Bool) {}
    func minimalComposerHandleKeyDown(_ event: NSEvent) -> Bool { false }
    func minimalComposerNextResponder() -> NSResponder? { nil }
    func minimalComposerShouldForwardCopy(_ composer: iTermMinimalComposerViewController) -> Bool { false }
    func minimalComposerForwardMenuItem(_ menuItem: NSMenuItem) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, valueOfEnvironmentVariable name: String) -> String? { nil }
    func minimalComposerPreferredOffset(fromTopDidChange composer: iTermMinimalComposerViewController) {}
}

@MainActor
final class CockpitComposerSendEachTests: XCTestCase {
    private var composer: iTermMinimalComposerViewController!
    private var fakeDelegate: FakeCockpitComposerDelegate!
    private var textView: ComposerTextView!
    private let guid = "FAKE-SESSION-GUID"

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

    override func setUpWithError() throws {
        try super.setUpWithError()
        composer = iTermMinimalComposerViewController()
        fakeDelegate = FakeCockpitComposerDelegate()
        fakeDelegate.composer = composer
        composer.delegate = fakeDelegate
        composer.isAutoComposer = false
        _ = composer.view
        textView = try XCTUnwrap(findComposer(in: composer.view))
    }

    override func tearDown() {
        composer = nil
        fakeDelegate = nil
        textView = nil
        super.tearDown()
    }

    // Configure as the cockpit does and fill in "<chip> echo X".
    private func fillLikeCockpit() {
        composer.setComposerRichTextEnabled(true)
        let font = NSFont.systemFont(ofSize: 12)
        let contents = NSMutableAttributedString(
            attributedString: ChatSessionMentionAttachment.attributedString(guid: guid,
                                                                            displayName: "Target",
                                                                            font: font,
                                                                            color: .linkColor))
        contents.append(NSAttributedString(string: " echo X", attributes: [.font: font]))
        composer.replace(NSRange(location: 0, length: composer.attributedStringValue.length),
                         with: contents)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    private func pressReturn(_ modifiers: NSEvent.ModifierFlags) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,
                                                   location: .zero,
                                                   modifierFlags: modifiers,
                                                   timestamp: 0,
                                                   windowNumber: 0,
                                                   context: nil,
                                                   characters: "\r",
                                                   charactersIgnoringModifiers: "\r",
                                                   isARepeat: false,
                                                   keyCode: 36))
        textView.keyDown(with: event)
    }

    private func chipGUIDs(in attributed: NSAttributedString) -> [String] {
        var result = [String]()
        attributed.enumerateAttribute(.attachment,
                                      in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let mention = value as? ChatSessionMentionAttachment {
                result.append(mention.guid)
            }
        }
        return result
    }

    private func assertSentWithTargetIntact(_ modifiers: NSEvent.ModifierFlags,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) throws {
        fillLikeCockpit()
        XCTAssertEqual(chipGUIDs(in: composer.attributedStringValue), [guid], "Precondition", file: file, line: line)

        try pressReturn(modifiers)

        XCTAssertEqual(fakeDelegate.enqueues, [], file: file, line: line)
        XCTAssertEqual(fakeDelegate.sends.count, 1, file: file, line: line)
        guard let send = fakeDelegate.sends.first else {
            return
        }
        XCTAssertTrue(send.command.contains("echo X"), send.command, file: file, line: line)
        // The cockpit resolves targets and the command from the composer's
        // contents during the callback, so the chip and text must still be there.
        XCTAssertEqual(chipGUIDs(in: send.contents), [guid], file: file, line: line)
        XCTAssertTrue(send.contents.string.contains("echo X"), send.contents.string, file: file, line: line)
    }

    func testOptionShiftReturnSendsWithChipIntact() throws {
        try assertSentWithTargetIntact([.option, .shift])
    }

    func testOptionReturnSendsWithChipIntact() throws {
        try assertSentWithTargetIntact([.option])
    }

    func testShiftReturnSendsWithChipIntact() throws {
        try assertSentWithTargetIntact([.shift])
    }

    // Outside the cockpit, send each keeps its usual behavior: it takes the
    // command out of the composer and sends it.
    func testOptionShiftReturnStillSendsEachInPlainComposer() throws {
        textView.string = "echo X"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        try pressReturn([.option, .shift])
        XCTAssertEqual(fakeDelegate.sends.map(\.command), ["echo X"])
        XCTAssertEqual(fakeDelegate.enqueues, [])
        XCTAssertEqual(textView.string, "")
    }

    // Outside the cockpit, enqueue each keeps its usual behavior.
    func testOptionReturnStillEnqueuesEachInPlainComposer() throws {
        textView.string = "echo X"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        try pressReturn([.option])
        XCTAssertEqual(fakeDelegate.enqueues, ["echo X"])
        XCTAssertEqual(fakeDelegate.sends.count, 0)
        XCTAssertEqual(textView.string, "")
    }
}
