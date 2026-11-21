//
//  TextViewEventsNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of the text view's event methods and of
//  session views that the nullability sanitizer found false (unit N10 of
//  docs/swift-migration/nullability-triage.md). The app passes a nil event on
//  purpose (-[PTYTextView updateCursor:nil] from PTYSession, and
//  [NSApp currentEvent], which is nil outside event handling), and every body
//  tolerates it. PTYMouseHandler, iTermImageView, iTermFakeWindowTitleLabel
//  and -[PTYTextView updateCursor:action:] (whose URLAction type Swift cannot
//  see) are not visible to Swift; the image view and the title label are
//  pinned in ImageViewNullabilityTests.m and
//  FakeWindowTitleLabelNullabilityTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class TextViewEventsNullabilityTests: XCTestCase {
    // These methods need a live text view in a window to call, and with nil
    // their bodies only read zero values from the event or ignore it, so they
    // are pinned at compile time: a method taking a non-optional does not
    // convert to one taking an optional, and guard let needs an optional.
    func testOptionalEventParametersCompile() {
        let clickPoint: (PTYTextView) -> (NSEvent?, Bool) -> NSPoint = PTYTextView.clickPoint(_:allowRightMarginOverflow:)
        let coordForEvent: (PTYTextView) -> (NSEvent?) -> VT100GridCoord = PTYTextView.coord(for:)
        let updateCursorAndUnderlinedRange: (PTYTextView) -> (NSEvent?) -> Void = PTYTextView.updateCursorAndUnderlinedRange(_:)
        let mouseIsOverImage: (PTYTextView) -> (NSEvent?) -> Bool = PTYTextView.mouseIsOverImage(in:)
        let haveOffscreenCommandLine: (any iTermContextMenuHelperDelegate, iTermTextViewContextMenuHelper) -> Bool = { delegate, helper in
            guard let commandLine = delegate.contextMenu(helper, offscreenCommandLineForClickAt: .zero) else {
                return false
            }
            return commandLine.absoluteLineNumber >= 0
        }
        let addBelowFindView: (SessionView) -> (NSView?) -> Void = SessionView.addSubview(belowFind:)
        XCTAssertNotNil(clickPoint as Any)
        XCTAssertNotNil(coordForEvent as Any)
        XCTAssertNotNil(updateCursorAndUnderlinedRange as Any)
        XCTAssertNotNil(mouseIsOverImage as Any)
        XCTAssertNotNil(haveOffscreenCommandLine as Any)
        XCTAssertNotNil(addBelowFindView as Any)
    }
}
