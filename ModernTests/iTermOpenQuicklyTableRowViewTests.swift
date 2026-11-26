//
//  iTermOpenQuicklyTableRowViewTests.swift
//  ModernTests
//
//  Characterization tests for the two row views of the Open Quickly window,
//  iTermOpenQuicklyTableRowView and iTermOpenQuicklyTableRowView_BigSur:
//  NSTableRowView subclasses that are always emphasized, so a table that is
//  not key still draws a blue selection. The first also overrides
//  -drawSelectionInRect: only to call super. Written against the
//  Objective-C runtime so they run unchanged against Swift classes with the
//  same runtime names. Nothing is put on screen; drawing goes to an
//  offscreen bitmap.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermOpenQuicklyTableRowViewTests: XCTestCase {
    private let classNames = ["iTermOpenQuicklyTableRowView", "iTermOpenQuicklyTableRowView_BigSur"]

    private func rowViewClass(_ name: String) -> NSTableRowView.Type? {
        return NSClassFromString(name) as? NSTableRowView.Type
    }

    private func ownMethods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    private func render(_ size: NSSize, _ body: () -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width),
                                         pixelsHigh: Int(size.height),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep),
              let bytes = rep.bitmapData else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        body()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    func testClassesExistUnderTheirObjectiveCNamesWithTheirSuperclass() {
        for name in classNames {
            guard let cls = rowViewClass(name) else {
                XCTFail("no class \(name)")
                continue
            }
            XCTAssertTrue(class_getSuperclass(cls) === NSTableRowView.self, name)
        }
    }

    func testSelectorsAndEncodings() {
        guard let cls = rowViewClass(classNames[0]),
              let bigSur = rowViewClass(classNames[1]) else {
            XCTFail("no class")
            return
        }
        XCTAssertEqual(ownMethods(cls)["isEmphasized"], "B16@0:8")
        XCTAssertEqual(ownMethods(cls)["drawSelectionInRect:"], "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16")
        XCTAssertEqual(ownMethods(bigSur)["isEmphasized"], "B16@0:8")
        XCTAssertNil(ownMethods(bigSur)["drawSelectionInRect:"])
    }

    func testIsEmphasizedEvenWhenSetToNo() {
        guard let cls = rowViewClass(classNames[0]) else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: NSRect(x: 0, y: 0, width: 20, height: 10))
        XCTAssertTrue(view.isEmphasized)
        view.isEmphasized = false
        XCTAssertTrue(view.isEmphasized)
    }

    func testBigSurIsEmphasizedEvenWhenSetToNo() {
        guard let cls = rowViewClass(classNames[1]) else {
            XCTFail("no class")
            return
        }
        // The window controller makes it with -init.
        let view = cls.init()
        XCTAssertTrue(view.isEmphasized)
        view.isEmphasized = false
        XCTAssertTrue(view.isEmphasized)
    }

    // The override only calls super, so it draws what NSTableRowView draws
    // for an emphasized, selected row.
    func testDrawSelectionDrawsWhatSuperDraws() {
        guard let cls = rowViewClass(classNames[0]) else {
            XCTFail("no class")
            return
        }
        let frame = NSRect(x: 0, y: 0, width: 20, height: 10)
        let view = cls.init(frame: frame)
        view.isSelected = true
        let plain = NSTableRowView(frame: frame)
        plain.isSelected = true
        plain.isEmphasized = true
        let drawn = render(frame.size) { view.drawSelection(in: frame) }
        let expected = render(frame.size) { plain.drawSelection(in: frame) }
        XCTAssertNotNil(drawn)
        XCTAssertEqual(drawn, expected)
        // Something was drawn, so the comparison means something.
        XCTAssertTrue(expected?.contains { $0 != 0 } ?? false)
    }
}
