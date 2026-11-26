//
//  iTermGlobalSearchOutlineViewTests.swift
//  ModernTests
//
//  Characterization tests for iTermGlobalSearchOutlineView, the outline view
//  of the Find Globally window: an NSOutlineView subclass that
//  iTermGlobalSearch.xib names as a customClass and whose one override,
//  -acceptsFirstMouse:, returns YES. Written against the Objective-C runtime
//  so they run unchanged against a Swift class with the same runtime name.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermGlobalSearchOutlineViewTests: XCTestCase {
    private let unitClassName = "iTermGlobalSearchOutlineView"
    private let selector = NSSelectorFromString("acceptsFirstMouse:")

    private func outlineViewClass() -> NSOutlineView.Type? {
        return NSClassFromString(unitClassName) as? NSOutlineView.Type
    }

    func testClassExistsUnderItsObjectiveCNameWithItsSuperclass() {
        guard let cls = outlineViewClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSOutlineView.self)
    }

    func testAcceptsFirstMouseSelectorAndEncoding() {
        guard let cls = outlineViewClass() else {
            XCTFail("no class")
            return
        }
        guard let method = class_getInstanceMethod(cls, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "B24@0:8@16")
        // Implemented by the class itself, not inherited.
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            XCTFail("no method list")
            return
        }
        defer { free(methods) }
        let own = (0..<Int(count)).map { method_getName(methods[$0]) }
        XCTAssertTrue(own.contains(selector))
    }

    func testAcceptsFirstMouseWithNilEvent() {
        guard let cls = outlineViewClass() else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testAcceptsFirstMouseWithAMouseDown() {
        guard let cls = outlineViewClass() else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                       location: NSPoint(x: 5, y: 5),
                                       modifierFlags: [],
                                       timestamp: 0,
                                       windowNumber: 0,
                                       context: nil,
                                       eventNumber: 0,
                                       clickCount: 1,
                                       pressure: 1)
        XCTAssertNotNil(event)
        XCTAssertTrue(view.acceptsFirstMouse(for: event))
    }

    // The xib names the class as the outline view's customClass, with no
    // customModule, so nib loading finds it by its bare Objective-C name. The
    // nib's window is visible at launch, so instantiating the nib would order
    // it in (and its compiled form is a NIBArchive, which NSKeyedUnarchiver
    // cannot read); instead this reads the xib from the source tree and
    // resolves its customClass the way nib loading does, by name.
    func testXibNamesTheClassByItsBareObjectiveCName() throws {
        let xibURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sources/GlobalSearch/Base.lproj/iTermGlobalSearch.xib")
        let document = try XMLDocument(contentsOf: xibURL, options: [])
        let nodes = try document.nodes(forXPath: "//outlineView[@customClass]")
        XCTAssertEqual(nodes.count, 1)
        guard let element = nodes.first as? XMLElement,
              let customClass = element.attribute(forName: "customClass")?.stringValue else {
            XCTFail("no outline view with a custom class")
            return
        }
        XCTAssertEqual(customClass, unitClassName)
        XCTAssertNil(element.attribute(forName: "customModule"))
        guard let cls = NSClassFromString(customClass) as? NSOutlineView.Type else {
            XCTFail("the custom class does not resolve to an outline view class")
            return
        }
        let view = cls.init(frame: .zero)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }
}
