//
//  iTermNoColorAccessoryButtonTests.swift
//  ModernTests
//
//  Characterization tests for iTermNoColorAccessoryButton, an NSButton
//  meant as the color panel's accessory view that sends -noColorChosen: to
//  the first responder. Its one override, -init, sizes it to the NoColor
//  image plus 8 points above and below and configures it. Written against
//  the Objective-C runtime so they run unchanged against a Swift class with
//  the same runtime name. Nothing is put on screen.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermNoColorAccessoryButtonTests: XCTestCase {
    private let unitClassName = "iTermNoColorAccessoryButton"

    private func buttonClass() -> NSButton.Type? {
        return NSClassFromString(unitClassName) as? NSButton.Type
    }

    func testClassExistsUnderItsObjectiveCNameWithItsSuperclass() {
        guard let cls = buttonClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSButton.self)
    }

    func testInitIsItsOwnMethod() {
        guard let cls = buttonClass() else {
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
        XCTAssertEqual(own["init"], "@16@0:8")
    }

    func testInitConfiguresTheButton() {
        guard let cls = buttonClass() else {
            XCTFail("no class")
            return
        }
        let button = cls.init()
        guard let expected = Bundle(for: cls).image(forResource: "NoColor") else {
            XCTFail("no image")
            return
        }
        XCTAssertEqual(button.frame, NSRect(x: 0, y: 0, width: expected.size.width, height: expected.size.height + 16))
        XCTAssertEqual(button.image?.size, expected.size)
        XCTAssertNil(button.target)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.title, "")
        XCTAssertEqual((button.cell as? NSButtonCell)?.highlightsBy, .contentsCellMask)
        // What NSButtonTypeMomentaryPushIn sets on the cell.
        XCTAssertEqual((button.cell as? NSButtonCell)?.showsStateBy, [])
    }

    func testInitSetsTheAction() {
        guard let cls = buttonClass() else {
            XCTFail("no class")
            return
        }
        let button = cls.init()
        XCTAssertEqual(button.action.map { NSStringFromSelector($0) }, "noColorChosen:")
    }

    func testTriggerControllerSeesItsKind() {
        guard let cls = buttonClass() else {
            XCTFail("no class")
            return
        }
        let button: NSView = cls.init()
        XCTAssertTrue(button.isKind(of: cls))
    }
}
