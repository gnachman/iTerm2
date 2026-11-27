//
//  iTermMoveTabToWindowBuiltInFunctionTests.swift
//  ModernTests
//
//  Characterization tests for iTermMoveTabToWindowBuiltInFunction, which
//  registers iterm2.move_tab_to_window() with the shared built-in function
//  registry. The function takes no arguments; its tab_id parameter defaults
//  to the calling scope's tab ID. It moves that tab out of its window into a
//  new one and completes with the new window's GUID, or completes with an
//  error in the domain com.iterm2.move-tab-to-window: code 1 when there is
//  no tab ID, 2 when no window holds the tab, 3 when the window has only one
//  tab, and 4 when the new window could not be made. The class is found by
//  its runtime name and its methods are sent by selector, the way the
//  registry reaches them. Each test replaces the shared registry's
//  functions and restores them afterwards. Codes 3 and 4 and the success
//  path need a real window with tabs and are not reached here.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// The class method of the function's class, sent by name through AnyObject.
@objc private protocol MoveTabToWindowSelectors {
    @objc(moveTabWithID:completion:)
    func moveTab(withID tabID: String?, completion: @escaping (Any?, Error?) -> Void)
}

final class iTermMoveTabToWindowBuiltInFunctionTests: XCTestCase, iTermObject {
    private let unitClassName = "iTermMoveTabToWindowBuiltInFunction"
    private let functionName = "move_tab_to_window"
    private let domain = "com.iterm2.move-tab-to-window"
    // A tab ID made only of digits, as real ones are, that no tab has.
    private let unusedTabID = "987654321"
    private var savedRegistry: Any?
    private var variables = [iTermVariables]()

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

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

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

    private struct Outcome {
        var called = 0
        var result: Any?
        var error: NSError?
    }

    // A scope whose tab ID is `tabID`, or which has no tab ID when it is nil.
    private func scope(tabID: String?) -> iTermVariableScope {
        let scope = iTermVariableScope()
        let tabVariables = iTermVariables(context: .tab, owner: self)
        variables.append(tabVariables)
        scope.add(tabVariables, toScopeNamed: nil)
        if let tabID {
            scope.setValue(tabID, forVariableNamed: "id")
        }
        return scope
    }

    private func call(_ parameters: [String: Any] = [:],
                      tabID: String?,
                      sideEffectsAllowed: Bool = true) -> Outcome {
        var outcome = Outcome()
        iTermBuiltInFunctions.sharedInstance().callFunction(withName: functionName,
                                                            namespace: "iterm2",
                                                            parameters: parameters,
                                                            scope: scope(tabID: tabID),
                                                            sideEffectsAllowed: sideEffectsAllowed) { result, error in
            outcome.called += 1
            outcome.result = result
            outcome.error = error as NSError?
        }
        return outcome
    }

    private func moveTabDirectly(_ tabID: String?) -> [Outcome] {
        guard let cls = functionClass else {
            XCTFail("no class")
            return []
        }
        var outcomes = [Outcome]()
        let sent: Void? = (cls as AnyObject).moveTab?(withID: tabID) { result, error in
            outcomes.append(Outcome(called: 1, result: result, error: error as NSError?))
        }
        XCTAssertNotNil(sent)
        return outcomes
    }

    private func assertError(_ error: NSError?,
                             code: Int,
                             key: String,
                             english: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertEqual(error?.domain, domain, file: file, line: line)
        XCTAssertEqual(error?.code, code, file: file, line: line)
        XCTAssertEqual(error?.userInfo.keys.sorted(), [NSLocalizedDescriptionKey], file: file, line: line)
        let localized = Bundle.main.localizedString(forKey: key, value: english, table: nil)
        XCTAssertEqual(error?.userInfo[NSLocalizedDescriptionKey] as? String, localized, file: file, line: line)
        XCTAssertEqual(error?.localizedDescription, localized, file: file, line: line)
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
        XCTAssertEqual(methods["moveTabWithID:completion:"], "v32@0:8@16@?24")
    }

    func testRegistersUnderItsNameWithNoArguments() {
        let registry = iTermBuiltInFunctions.sharedInstance()
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: []))
        register()
        XCTAssertTrue(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: []))
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: "iterm2", arguments: ["tab_id"]))
        XCTAssertFalse(registry.haveFunction(withName: functionName, namespace: nil, arguments: []))
        XCTAssertEqual(registry.registeredFunctionSignatureDictionary() as NSDictionary,
                       ["iterm2.\(functionName)": [String]()] as NSDictionary)
    }

    // The tab ID comes from the scope's "id" variable; passing tab_id
    // explicitly is a call to an undeclared function.
    func testExplicitTabIDIsNotAccepted() {
        register()
        let outcome = call(["tab_id": unusedTabID], tabID: nil)
        XCTAssertEqual(outcome.called, 1)
        XCTAssertNil(outcome.result)
        XCTAssertNotNil(outcome.error)
        XCTAssertNotEqual(outcome.error?.domain, domain)
    }

    func testWithoutSideEffectsGivesThePlaceholder() {
        register()
        let outcome = call(tabID: nil, sideEffectsAllowed: false)
        XCTAssertEqual(outcome.called, 1)
        XCTAssertEqual(outcome.result as? String, "[move_tab_to_window]")
        XCTAssertNil(outcome.error)
    }

    func testNoTabIDInTheScopeIsNoSuchTab() {
        register()
        let outcome = call(tabID: nil)
        XCTAssertEqual(outcome.called, 1)
        XCTAssertNil(outcome.result)
        assertError(outcome.error, code: 1, key: "MoveTabToWindow.NoSuchTab", english: "No such tab")
    }

    // A tab ID that matches no tab is reported as a tab with no window, not
    // as no such tab: only a missing ID gives code 1.
    func testUnknownTabIDInTheScopeIsTabHasNoWindow() {
        register()
        let outcome = call(tabID: unusedTabID)
        XCTAssertEqual(outcome.called, 1)
        XCTAssertNil(outcome.result)
        assertError(outcome.error, code: 2, key: "MoveTabToWindow.TabHasNoWindow", english: "Tab has no window")

        let nonNumeric = call(tabID: "not a tab")
        assertError(nonNumeric.error, code: 2, key: "MoveTabToWindow.TabHasNoWindow", english: "Tab has no window")
    }

    // +moveTabWithID:completion: called directly, through the runtime.
    func testMoveTabWithNilIDIsNoSuchTab() {
        let outcomes = moveTabDirectly(nil)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertNil(outcomes.first?.result)
        assertError(outcomes.first?.error, code: 1, key: "MoveTabToWindow.NoSuchTab", english: "No such tab")
    }

    func testMoveTabWithUnknownIDIsTabHasNoWindow() {
        for tabID in [unusedTabID, "", "x"] {
            let outcomes = moveTabDirectly(tabID)
            XCTAssertEqual(outcomes.count, 1, tabID)
            XCTAssertNil(outcomes.first?.result, tabID)
            assertError(outcomes.first?.error, code: 2, key: "MoveTabToWindow.TabHasNoWindow", english: "Tab has no window")
        }
    }

    func testEnglishMessages() throws {
        try XCTSkipUnless(Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? false,
                          "the messages are compared with their English text")
        XCTAssertEqual(moveTabDirectly(nil).first?.error?.localizedDescription, "No such tab")
        XCTAssertEqual(moveTabDirectly(unusedTabID).first?.error?.localizedDescription, "Tab has no window")
    }
}
