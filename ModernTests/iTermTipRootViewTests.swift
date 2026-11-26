//
//  iTermTipRootViewTests.swift
//  ModernTests
//
//  Characterization tests for iTermTipRootView, the content view of the tip
//  of the day window, which iTermTipWindowController.xib names as a
//  customClass. It is flipped, becomes an accessibility element when it
//  awakes from the nib, and draws by clearing its bounds. Written against
//  the Objective-C runtime so they run unchanged against a Swift class with
//  the same runtime name. Nothing is put on screen; drawing goes to an
//  offscreen bitmap.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermTipRootViewTests: XCTestCase {
    private let unitClassName = "iTermTipRootView"

    private func viewClass() -> NSView.Type? {
        return NSClassFromString(unitClassName) as? NSView.Type
    }

    func testClassExistsUnderItsObjectiveCNameWithItsSuperclass() {
        guard let cls = viewClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSView.self)
    }

    func testSelectorsAndEncodings() {
        guard let cls = viewClass() else {
            XCTFail("no class")
            return
        }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            XCTFail("no method list")
            return
        }
        defer { free(methods) }
        let own = Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
        XCTAssertEqual(own["awakeFromNib"], "v16@0:8")
        XCTAssertEqual(own["drawRect:"], "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16")
        XCTAssertEqual(own["isFlipped"], "B16@0:8")
    }

    func testIsFlipped() {
        guard let cls = viewClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(cls.init(frame: NSRect(x: 0, y: 0, width: 10, height: 10)).isFlipped)
    }

    func testAwakeFromNibMakesItAnAccessibilityElement() {
        guard let cls = viewClass() else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertFalse(view.isAccessibilityElement())
        view.awakeFromNib()
        XCTAssertTrue(view.isAccessibilityElement())
    }

    // NSRectFill copies, so clear color replaces what was there instead of
    // compositing over it: an opaque red background becomes transparent.
    func testDrawRectClearsItsBounds() {
        guard let cls = viewClass() else {
            XCTFail("no class")
            return
        }
        let frame = NSRect(x: 0, y: 0, width: 8, height: 8)
        let view = cls.init(frame: frame)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: 8,
                                         pixelsHigh: 8,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            XCTFail("no bitmap")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.red.set()
        frame.fill(using: .copy)
        XCTAssertEqual(rep.colorAt(x: 4, y: 4)?.alphaComponent, 1)
        view.draw(frame)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        for (x, y) in [(0, 0), (4, 4), (7, 7)] {
            XCTAssertEqual(rep.colorAt(x: x, y: y)?.alphaComponent, 0, "\(x),\(y)")
        }
    }

    // The window is not visible at launch, so instantiating the nib orders
    // nothing in. No owner: only the File's Owner outlets go unconnected.
    func testXibMakesTheContentViewOfThisClassAndAwakesIt() {
        guard let nib = NSNib(nibNamed: "iTermTipWindowController",
                              bundle: Bundle(for: iTermShellIntegrationWindowController.self)) else {
            XCTFail("no nib")
            return
        }
        var topLevelObjects: NSArray?
        XCTAssertTrue(nib.instantiate(withOwner: nil, topLevelObjects: &topLevelObjects))
        let windows = (topLevelObjects as? [Any] ?? []).compactMap { $0 as? NSWindow }
        XCTAssertEqual(windows.count, 1)
        guard let window = windows.first, let contentView = window.contentView else {
            XCTFail("no window")
            return
        }
        window.isReleasedWhenClosed = false
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(NSStringFromClass(type(of: contentView)), unitClassName)
        XCTAssertTrue(contentView.isFlipped)
        XCTAssertTrue(contentView.isAccessibilityElement())
    }
}
