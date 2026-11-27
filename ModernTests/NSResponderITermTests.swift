//
//  NSResponderITermTests.swift
//  ModernTests
//
//  Characterization tests for the category NSResponder (iTerm), which gives
//  every responder four methods with default answers that subclasses
//  override: -it_wantsScrollWheelMomentumEvents (NO),
//  -it_scrollWheelMomentum: (does nothing), -it_isTerminalResponder (NO) and
//  -it_preferredFirstResponder, which is NO except for a text view whose
//  delegate responds to the same selector, in which case the delegate
//  answers.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// A delegate that is not a responder but answers -it_preferredFirstResponder.
private final class PreferringDelegate: NSObject, NSTextViewDelegate {
    var answer = true

    @objc func it_preferredFirstResponder() -> Bool {
        return answer
    }
}

// A text field delegate that answers -it_preferredFirstResponder.
private final class PreferringFieldDelegate: NSObject, NSTextFieldDelegate {
    @objc func it_preferredFirstResponder() -> Bool {
        return true
    }
}

// A delegate that does not answer -it_preferredFirstResponder at all.
private final class SilentDelegate: NSObject, NSTextViewDelegate {
}

// A delegate that is a responder and so gets the category's default answer.
private final class ResponderDelegate: NSResponder, NSTextViewDelegate {
}

// A responder that overrides -it_preferredFirstResponder to say YES.
private final class PreferringResponderDelegate: NSResponder, NSTextViewDelegate {
    override func it_preferredFirstResponder() -> Bool {
        return true
    }
}

private final class TextViewSubclass: NSTextView {
}

// Records every scroll event and momentum message it receives.
private final class RecordingResponder: NSResponder {
    var received = [String]()

    override func scrollWheel(with event: NSEvent) {
        received.append("scrollWheel")
    }

    override func it_scrollWheelMomentum(_ event: NSEvent?) {
        received.append("momentum")
    }
}

final class NSResponderITermTests: XCTestCase {
    private func ownMethods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary((0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        }, uniquingKeysWith: { first, _ in first })
    }

    private func scrollEvent() -> NSEvent? {
        guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil,
                                    units: .pixel,
                                    wheelCount: 1,
                                    wheel1: 3,
                                    wheel2: 0,
                                    wheel3: 0) else {
            return nil
        }
        return NSEvent(cgEvent: cgEvent)
    }

    func testSelectorsAndEncodingsAreOnNSResponder() {
        let methods = ownMethods(NSResponder.self)
        XCTAssertEqual(methods["it_wantsScrollWheelMomentumEvents"], "B16@0:8")
        XCTAssertEqual(methods["it_scrollWheelMomentum:"], "v24@0:8@16")
        XCTAssertEqual(methods["it_preferredFirstResponder"], "B16@0:8")
        XCTAssertEqual(methods["it_isTerminalResponder"], "B16@0:8")
    }

    func testDoesNotWantScrollWheelMomentumEvents() {
        XCTAssertFalse(NSResponder().it_wantsScrollWheelMomentumEvents())
        XCTAssertFalse(NSView().it_wantsScrollWheelMomentumEvents())
        XCTAssertFalse(NSTextView().it_wantsScrollWheelMomentumEvents())
    }

    func testIsNotATerminalResponder() {
        XCTAssertFalse(NSResponder().it_isTerminalResponder())
        XCTAssertFalse(NSView().it_isTerminalResponder())
        XCTAssertFalse(NSTextView().it_isTerminalResponder())
    }

    // The default does nothing: it neither forwards the event up the
    // responder chain nor handles it as a scroll.
    func testScrollWheelMomentumDoesNothing() {
        let next = RecordingResponder()
        let responder = NSView()
        responder.nextResponder = next
        guard let event = scrollEvent() else {
            XCTFail("no event")
            return
        }
        responder.it_scrollWheelMomentum(event)
        responder.it_scrollWheelMomentum(nil)
        XCTAssertEqual(next.received, [])
        XCTAssertTrue(responder.nextResponder === next)
    }

    func testPreferredFirstResponderIsNoForAnythingButATextView() {
        XCTAssertFalse(NSResponder().it_preferredFirstResponder())
        XCTAssertFalse(NSView().it_preferredFirstResponder())
        // A text field's delegate is not asked.
        let delegate = PreferringFieldDelegate()
        let field = NSTextField()
        field.delegate = delegate
        XCTAssertFalse(field.it_preferredFirstResponder())
    }

    func testTextViewWithoutDelegateIsNotPreferred() {
        XCTAssertFalse(NSTextView().it_preferredFirstResponder())
    }

    func testTextViewWhoseDelegateDoesNotRespondIsNotPreferred() {
        let delegate = SilentDelegate()
        let textView = NSTextView()
        textView.delegate = delegate
        XCTAssertFalse(textView.it_preferredFirstResponder())
    }

    // A delegate that is not a responder is still asked when it responds.
    func testTextViewAsksADelegateThatResponds() {
        let delegate = PreferringDelegate()
        let textView = NSTextView()
        textView.delegate = delegate
        XCTAssertTrue(textView.it_preferredFirstResponder())
        delegate.answer = false
        XCTAssertFalse(textView.it_preferredFirstResponder())
    }

    func testTextViewAsksAResponderDelegate() {
        let plain = ResponderDelegate()
        let preferring = PreferringResponderDelegate()
        let textView = NSTextView()
        textView.delegate = plain
        XCTAssertFalse(textView.it_preferredFirstResponder())
        textView.delegate = preferring
        XCTAssertTrue(textView.it_preferredFirstResponder())
    }

    func testTextViewSubclassAsksItsDelegate() {
        let delegate = PreferringDelegate()
        let textView = TextViewSubclass()
        textView.delegate = delegate
        XCTAssertTrue(textView.it_preferredFirstResponder())
    }
}
