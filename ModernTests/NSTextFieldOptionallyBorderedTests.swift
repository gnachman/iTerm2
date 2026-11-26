//
//  NSTextFieldOptionallyBorderedTests.swift
//  ModernTests
//
//  Characterization tests for the protocol iTermOptionallyBordered and the
//  category NSTextField (OptionallyBordered) that conforms NSTextField to it:
//  -setOptionalBorderEnabled: turns on the border and the background whatever
//  its argument. Written against the Objective-C runtime so they run
//  unchanged against a Swift protocol and extension with the same names.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class NSTextFieldOptionallyBorderedTests: XCTestCase {
    private let protocolName = "iTermOptionallyBordered"
    private let selector = NSSelectorFromString("setOptionalBorderEnabled:")

    private func borderlessField() -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        field.isBordered = false
        field.drawsBackground = false
        return field
    }

    func testProtocolExistsUnderItsObjectiveCNameWithItsMethod() {
        guard let proto = NSProtocolFromString(protocolName) else {
            XCTFail("no protocol")
            return
        }
        let description = protocol_getMethodDescription(proto, selector, true, true)
        XCTAssertEqual(description.name, selector)
        guard let types = description.types else {
            XCTFail("no types")
            return
        }
        XCTAssertEqual(String(cString: types), "v20@0:8B16")
    }

    func testNSTextFieldConformsToTheProtocol() {
        guard let proto = NSProtocolFromString(protocolName) else {
            XCTFail("no protocol")
            return
        }
        XCTAssertTrue(class_conformsToProtocol(NSTextField.self, proto))
        XCTAssertTrue(NSTextField().conforms(to: proto))
    }

    // TriggerController.m's private iTermTwoStringView adopts the protocol in
    // Objective-C; it must name the same runtime protocol.
    func testTwoStringViewConformsToTheSameProtocol() {
        guard let proto = NSProtocolFromString(protocolName),
              let cls = NSClassFromString("iTermTwoStringView") else {
            XCTFail("no protocol or class")
            return
        }
        XCTAssertTrue(class_conformsToProtocol(cls, proto))
    }

    func testMethodSelectorAndEncoding() {
        guard let method = class_getInstanceMethod(NSTextField.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "v20@0:8B16")
    }

    func testEnablingTurnsOnBorderAndBackground() {
        let field = borderlessField()
        field.setOptionalBorderEnabled(true)
        XCTAssertTrue(field.isBordered)
        XCTAssertTrue(field.drawsBackground)
    }

    // The argument is ignored: NO also turns both on.
    func testDisablingAlsoTurnsOnBorderAndBackground() {
        let field = borderlessField()
        field.setOptionalBorderEnabled(false)
        XCTAssertTrue(field.isBordered)
        XCTAssertTrue(field.drawsBackground)
    }

    // Callers send it to an object typed id<iTermOptionallyBordered>.
    func testThroughTheProtocol() {
        let field = borderlessField()
        let object: AnyObject = field
        guard let bordered = object as? iTermOptionallyBordered else {
            XCTFail("does not conform")
            return
        }
        bordered.setOptionalBorderEnabled(true)
        XCTAssertTrue(field.isBordered)
        XCTAssertTrue(field.drawsBackground)
    }
}
