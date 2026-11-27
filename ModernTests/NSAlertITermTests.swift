//
//  NSAlertITermTests.swift
//  ModernTests
//
//  Characterization tests for the category NSAlert (iTerm):
//  -runSheetModalForWindow: activates the app, shows the alert as a sheet on
//  the window and runs a modal session for it, which ends when the sheet ends
//  or the window closes. Running the method would put a sheet on screen and
//  activate the test host, so these tests pin only what the runtime records:
//  the selector, where it is defined, its type encoding and the name Swift
//  calls it by. NSAlert_iTermTests runs it for real, behind the onscreen gate.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class NSAlertITermTests: XCTestCase {
    private let selector = NSSelectorFromString("runSheetModalForWindow:")

    func testSelectorIsDefinedOnNSAlertWithItsEncoding() {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(NSAlert.self, &count) else {
            XCTFail("no methods")
            return
        }
        defer { free(methods) }
        let matches = (0..<Int(count)).filter { method_getName(methods[$0]) == selector }
        XCTAssertEqual(matches.count, 1)
        guard let index = matches.first, let encoding = method_getTypeEncoding(methods[index]) else {
            XCTFail("no method")
            return
        }
        XCTAssertEqual(String(cString: encoding), "q24@0:8@16")
    }

    func testEveryAlertResponds() {
        XCTAssertTrue(NSAlert().responds(to: selector))
        XCTAssertTrue(NSAlert.instancesRespond(to: selector))
    }

    // Swift callers use this name; the reference does not run the method.
    func testSwiftName() {
        let method: (NSAlert) -> (NSWindow) -> NSApplication.ModalResponse = NSAlert.runSheetModal(for:)
        XCTAssertNotNil(method)
    }
}
