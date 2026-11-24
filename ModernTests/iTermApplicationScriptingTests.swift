//
//  iTermApplicationScriptingTests.swift
//  ModernTests
//
//  Characterization tests for the category iTermApplication (Scripting):
//  -valueForUndefinedKey:, which answers every key nothing else answers on
//  the application object with an empty array, and -currentScriptingWindow,
//  the AppleScript property “current window” of iTerm2.sdef. Written against
//  the Objective-C runtime interface so they run unchanged against a Swift
//  extension with the same selectors. The test host is the app, so NSApp is
//  the real iTermApplication and the app's sdef is registered.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermApplicationScriptingTests: XCTestCase {
    private var savedCurrentTerminal: PseudoTerminal?
    private var fixtures = [TerminalWindowTestFixture]()

    private var app: iTermApplication {
        guard let app = NSApp as? iTermApplication else {
            it_fatalError("NSApp is not an iTermApplication")
        }
        return app
    }

    private var controller: iTermController {
        guard let controller = iTermController.sharedInstance() else {
            it_fatalError("No iTermController")
        }
        return controller
    }

    override func setUp() {
        super.setUp()
        savedCurrentTerminal = controller.currentTerminal
    }

    override func tearDown() {
        for fixture in fixtures {
            fixture.close()
        }
        fixtures = []
        controller.currentTerminal = savedCurrentTerminal
        savedCurrentTerminal = nil
        super.tearDown()
    }

    // The helper behind -setCurrentTerminal: defers only for a restoring,
    // miniaturized window when the Dock minimizes to the application icon, so
    // for nil and for a fresh window it takes effect at once. Check that it did.
    private func makeCurrent(_ terminal: PseudoTerminal?, file: StaticString = #filePath, line: UInt = #line) {
        controller.currentTerminal = terminal
        XCTAssertTrue(controller.currentTerminal === terminal,
                      "precondition: the current terminal was not set synchronously",
                      file: file, line: line)
    }

    // Opens two terminal windows, so that a lookup that answers with the
    // first or last terminal, or the first or last window, instead of the
    // current terminal is told apart from the real one.
    private func openTwoTerminals(file: StaticString = #filePath, line: UInt = #line) -> (TerminalWindowTestFixture, TerminalWindowTestFixture) {
        let a = TerminalWindowTestFixture()
        let b = TerminalWindowTestFixture()
        fixtures += [a, b]
        let terminals = controller.terminals() ?? []
        XCTAssertTrue(terminals.contains { $0 === a.terminal } && terminals.contains { $0 === b.terminal },
                      "precondition: both terminals are registered with the controller",
                      file: file, line: line)
        XCTAssertFalse(a.window === b.window, "precondition: two windows", file: file, line: line)
        return (a, b)
    }

    // Makes each of the two terminals current in turn and checks that `lookup`
    // gives a wrapper of that terminal's window and not of the other's. One of
    // the two is not the controller's first terminal and one is not its last.
    private func checkBothOrders(_ lookup: () throws -> Any?, file: StaticString = #filePath, line: UInt = #line) throws {
        let (a, b) = openTwoTerminals(file: file, line: line)
        for (current, other) in [(a, b), (b, a)] {
            makeCurrent(current.terminal, file: file, line: line)
            let result = try XCTUnwrap(try lookup() as? iTermScriptingWindow, file: file, line: line)
            XCTAssertTrue(result.underlyingWindow === current.window, "wraps the current terminal's window", file: file, line: line)
            XCTAssertFalse(result.underlyingWindow === other.window, "not the other terminal's window", file: file, line: line)
        }
    }

    private func emptyArrayCheck(_ value: Any?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let array = value as? NSArray else {
            XCTFail("\(what): expected an NSArray, got \(String(describing: value))", file: file, line: line)
            return
        }
        XCTAssertEqual(array.count, 0, what, file: file, line: line)
    }

    // MARK: - valueForUndefinedKey:

    func testUndefinedKeyGivesEmptyArray() {
        emptyArrayCheck(app.value(forKey: "iTermNoSuchKeyForScriptingTests"), "valueForKey:")
    }

    func testUndefinedKeyPathGivesEmptyArray() {
        emptyArrayCheck(app.value(forKeyPath: "iTermNoSuchKeyForScriptingTests.other"), "valueForKeyPath:")
    }

    func testDirectValueForUndefinedKeyGivesEmptyArray() {
        emptyArrayCheck(app.value(forUndefinedKey: "currentScriptingWindow"), "direct send")
    }

    // A nil key, sent without the SDK's nonnull annotation so that the test
    // itself is not a nullability violation. The Objective-C ignores the key.
    func testNilKeyGivesEmptyArray() {
        typealias Send = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
        let selector = NSSelectorFromString("valueForUndefinedKey:")
        guard let method = class_getInstanceMethod(iTermApplication.self, selector) else {
            XCTFail("iTermApplication has no -valueForUndefinedKey:")
            return
        }
        let send = unsafeBitCast(method_getImplementation(method), to: Send.self)
        emptyArrayCheck(send(app, selector, nil), "nil key")
    }

    // Keys the application answers never reach the override.
    func testAnsweredKeysDoNotReachTheOverride() {
        XCTAssertTrue(app.value(forKey: "isActive") is NSNumber)
        XCTAssertTrue(app.value(forKey: "name") is NSString, "NSApplication answers the sdef's name")
        XCTAssertTrue(app.value(forKey: "version") is NSString, "NSApplication answers the sdef's version")
    }

    // MARK: - currentScriptingWindow

    // Terminal windows are open, so that a lookup that answers with some
    // window or terminal instead of the current one fails here whatever ran
    // before.
    func testCurrentScriptingWindowIsNilWithNoCurrentTerminal() {
        _ = openTwoTerminals()
        makeCurrent(nil)
        XCTAssertNil(app.value(forKey: "currentScriptingWindow"))
    }

    func testCurrentScriptingWindowWrapsTheCurrentTerminalsWindow() throws {
        try checkBothOrders { app.value(forKey: "currentScriptingWindow") }
    }

    func testEachLookupMakesANewWrapper() throws {
        let (a, _) = openTwoTerminals()
        makeCurrent(a.terminal)
        let first = try XCTUnwrap(app.value(forKey: "currentScriptingWindow") as? iTermScriptingWindow)
        let second = try XCTUnwrap(app.value(forKey: "currentScriptingWindow") as? iTermScriptingWindow)
        XCTAssertTrue(first.underlyingWindow === a.window)
        XCTAssertTrue(second.underlyingWindow === a.window)
        XCTAssertFalse(first === second, "each lookup makes a new wrapper")
    }

    // The answer does not depend on which window is key. The current
    // terminal's window is ordered out, so it cannot be key, while the other
    // terminal's window stays on screen. When the app is active (an earlier
    // test can leave the test host active), making a terminal current makes
    // its window key, and ordering out the key window would make the other
    // terminal's window key and so current. So a window that belongs to no
    // terminal takes the key first: only a terminal window becoming key
    // changes the current terminal. This holds whether or not the app is
    // active.
    func testCurrentScriptingWindowIsTheCurrentTerminalsEvenWhenNotKey() throws {
        let (a, b) = openTwoTerminals()
        makeCurrent(b.terminal)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.titled],
                             backing: .buffered,
                             defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        b.window.orderOut(nil)
        XCTAssertTrue(controller.currentTerminal === b.terminal, "precondition: still current")
        XCTAssertFalse(b.window.isKeyWindow, "precondition: not key")
        XCTAssertFalse(NSApp.keyWindow === b.window, "precondition: not the key window")
        let result = try XCTUnwrap(app.value(forKey: "currentScriptingWindow") as? iTermScriptingWindow)
        XCTAssertTrue(result.underlyingWindow === b.window)
        XCTAssertFalse(result.underlyingWindow === a.window)
    }

    // MARK: - Cocoa Scripting

    private func applicationClassDescription() throws -> NSScriptClassDescription {
        return try XCTUnwrap(NSScriptClassDescription(for: iTermApplication.self),
                             "the sdef's application class is not registered for iTermApplication")
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        return string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    func testSdefMapsCurrentWindowToTheKey() throws {
        let description = try applicationClassDescription()
        XCTAssertEqual(description.key(withAppleEventCode: fourCharCode("Crwn")), "currentScriptingWindow")
    }

    private func evaluateCurrentWindowSpecifier() throws -> Any? {
        let description = try applicationClassDescription()
        let specifier = NSPropertySpecifier(containerClassDescription: description,
                                            containerSpecifier: nil,
                                            key: "currentScriptingWindow")
        return specifier.objectsByEvaluatingSpecifier
    }

    func testSpecifierEvaluatesToNilWithNoCurrentTerminal() throws {
        _ = openTwoTerminals()
        makeCurrent(nil)
        XCTAssertNil(try evaluateCurrentWindowSpecifier())
    }

    func testSpecifierEvaluatesToTheCurrentTerminalsWindow() throws {
        try checkBothOrders { try evaluateCurrentWindowSpecifier() }
    }

    // MARK: - Runtime surface

    func testRuntimeSelectorsAndEncodings() throws {
        let expected = ["valueForUndefinedKey:": "@24@0:8@16",
                        "currentScriptingWindow": "@16@0:8"]
        for (name, encoding) in expected {
            let method = try XCTUnwrap(class_getInstanceMethod(iTermApplication.self, NSSelectorFromString(name)), name)
            XCTAssertEqual(method_getTypeEncoding(method).map { String(cString: $0) }, encoding, name)
            XCTAssertTrue(iTermApplication.instancesRespond(to: NSSelectorFromString(name)), name)
        }
        // The override is iTermApplication's own, not NSObject's.
        let own = class_getInstanceMethod(iTermApplication.self, NSSelectorFromString("valueForUndefinedKey:"))
        let inherited = class_getInstanceMethod(NSObject.self, NSSelectorFromString("valueForUndefinedKey:"))
        XCTAssertNotEqual(own.map(method_getImplementation), inherited.map(method_getImplementation))
    }
}
