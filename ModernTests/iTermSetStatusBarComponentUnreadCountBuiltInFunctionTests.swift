//
//  iTermSetStatusBarComponentUnreadCountBuiltInFunctionTests.swift
//  ModernTests
//
//  Characterization tests for iTermSetStatusBarComponentUnreadCountBuiltInFunction,
//  which registers iterm2.set_status_bar_component_unread_count(identifier:count:)
//  with the shared built-in function registry. Calling it sets the unread
//  count that iTermStatusBarUnreadCountController keeps for a status bar
//  component's identifier, for every session, and completes with no result
//  and no error. The class is found by its runtime name and its methods are
//  sent by selector, the way the registry reaches them. Each test replaces
//  the shared registry's
//  functions and restores them afterwards.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// Selectors the tests send by name through AnyObject: one of
// iTermStatusBarUnreadCountController's shared instance, and the class
// method of the function's class.
@objc private protocol UnreadCountSelectors {
    @objc(unreadCountForComponentWithIdentifier:sessionID:)
    func unreadCount(identifier: String, sessionID: String) -> Int

    @objc(setCount:forIdentifier:completion:)
    func setCount(_ count: Int, forIdentifier identifier: String, completion: @escaping (Any?, Error?) -> Void)
}

final class iTermSetStatusBarComponentUnreadCountBuiltInFunctionTests: XCTestCase {
    private let unitClassName = "iTermSetStatusBarComponentUnreadCountBuiltInFunction"
    private let functionName = "set_status_bar_component_unread_count"
    private var savedRegistry: Any?

    override func setUp() {
        super.setUp()
        savedRegistry = iTermBuiltInFunctions.sharedInstance().savedState()
        iTermBuiltInFunctions.sharedInstance().restoreState(NSMutableDictionary())
    }

    override func tearDown() {
        if let savedRegistry {
            iTermBuiltInFunctions.sharedInstance().restoreState(savedRegistry)
        }
        super.tearDown()
    }

    private var functionClass: AnyClass? {
        return NSClassFromString(unitClassName)
    }

    private func classMethods(_ cls: AnyClass) -> [String: String] {
        guard let metaclass = object_getClass(cls) else {
            return [:]
        }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(metaclass, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    private func register() {
        guard let cls = functionClass as? NSObject.Type else {
            XCTFail("no class")
            return
        }
        _ = (cls as AnyObject).perform(NSSelectorFromString("registerBuiltInFunction"))
    }

    private func unreadCount(_ identifier: String) -> Int {
        guard let controllerClass = NSClassFromString("iTermStatusBarUnreadCountController") as? NSObject.Type,
              let controller = (controllerClass as AnyObject).perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() else {
            XCTFail("no controller")
            return -1
        }
        return (controller as AnyObject).unreadCount?(identifier: identifier, sessionID: "no-such-session") ?? -1
    }

    private struct Outcome {
        var called = 0
        var result: Any?
        var error: Error?
    }

    private func call(_ parameters: [String: Any], sideEffectsAllowed: Bool = true) -> Outcome {
        var outcome = Outcome()
        iTermBuiltInFunctions.sharedInstance().callFunction(withName: functionName,
                                                            namespace: "iterm2",
                                                            parameters: parameters,
                                                            scope: iTermVariableScope(),
                                                            sideEffectsAllowed: sideEffectsAllowed) { result, error in
            outcome.called += 1
            outcome.result = result
            outcome.error = error
        }
        return outcome
    }

    private func uniqueIdentifier() -> String {
        return "com.iterm2.test.unread.\(UUID().uuidString)"
    }

    func testClassExistsWithItsSuperclassAndProtocol() {
        guard let cls = functionClass else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSObject.self)
        guard let proto = NSProtocolFromString("iTermBuiltInFunction") else {
            XCTFail("no protocol")
            return
        }
        XCTAssertTrue(class_conformsToProtocol(cls, proto))
    }

    func testSelectorsAndEncodings() {
        guard let cls = functionClass else {
            XCTFail("no class")
            return
        }
        let methods = classMethods(cls)
        XCTAssertEqual(methods["registerBuiltInFunction"], "v16@0:8")
        XCTAssertEqual(methods["setCount:forIdentifier:completion:"], "v40@0:8q16@24@?32")
    }

    func testRegistersUnderItsNameWithItsArguments() {
        let registry = iTermBuiltInFunctions.sharedInstance()
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: ["identifier", "count"]))
        register()
        XCTAssertTrue(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: ["identifier", "count"]))
        XCTAssertTrue(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: ["count", "identifier"]))
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: ["identifier"]))
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: ["count"]))
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: nil, arguments: ["identifier", "count"]))
        XCTAssertEqual(registry.registeredFunctionSignatureDictionary().keys.sorted(), ["iterm2.\(functionName)"])
    }

    func testCallSetsTheCountAndCompletesWithNothing() {
        register()
        let identifier = uniqueIdentifier()
        let posted = expectation(forNotification: NSNotification.Name("iTermStatusBarUnreadCountDidChange"),
                                 object: identifier)
        let outcome = call(["identifier": identifier, "count": 7])
        wait(for: [posted], timeout: 0)
        XCTAssertEqual(outcome.called, 1)
        XCTAssertNil(outcome.result)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(unreadCount(identifier), 7)

        XCTAssertEqual(call(["identifier": identifier, "count": 0]).called, 1)
        XCTAssertEqual(unreadCount(identifier), 0)
    }

    func testCountIsTruncatedToAnInteger() {
        register()
        let identifier = uniqueIdentifier()
        XCTAssertNil(call(["identifier": identifier, "count": 2.9]).error)
        XCTAssertEqual(unreadCount(identifier), 2)
        XCTAssertNil(call(["identifier": identifier, "count": -3]).error)
        XCTAssertEqual(unreadCount(identifier), -3)
    }

    func testWithoutSideEffectsGivesThePlaceholderAndSetsNothing() {
        register()
        let identifier = uniqueIdentifier()
        let outcome = call(["identifier": identifier, "count": 5], sideEffectsAllowed: false)
        XCTAssertEqual(outcome.called, 1)
        XCTAssertEqual(outcome.result as? String, "[set_status_bar_component_unread_count]")
        XCTAssertNil(outcome.error)
        XCTAssertEqual(unreadCount(identifier), 0)
    }

    func testWrongTypeIsRejectedBeforeTheBodyRuns() {
        register()
        let identifier = uniqueIdentifier()
        let outcome = call(["identifier": identifier, "count": "4"])
        XCTAssertEqual(outcome.called, 1)
        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(unreadCount(identifier), 0)
    }

    // +setCount:forIdentifier:completion: called directly, through the runtime.
    func testSetCountSetsTheCountAndCompletes() {
        guard let cls = functionClass else {
            XCTFail("no class")
            return
        }
        let identifier = uniqueIdentifier()
        var calls = [(Any?, Error?)]()
        let sent: Void? = (cls as AnyObject).setCount?(11, forIdentifier: identifier) { result, error in
            calls.append((result, error))
        }
        XCTAssertNotNil(sent)
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls.first?.0)
        XCTAssertNil(calls.first?.1)
        XCTAssertEqual(unreadCount(identifier), 11)
    }
}
