//
//  VariablesScopeTests.swift
//  iTerm2
//
//  Ported from the legacy iTermVariablesTest.m. Covers iTermVariableScope reads and
//  writes, iTermVariableReference observation, late binding of references, and
//  frame shadowing between a scope and its copy.
//

import XCTest
@testable import iTerm2SharedARC

final class VariablesScopeTests: XCTestCase, iTermObject {
    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Helpers

    private func makeScope(context: iTermVariablesSuggestionContext = .session) -> (scope: iTermVariableScope,
                                                                                    variables: iTermVariables) {
        let variables = iTermVariables(context: context, owner: self)
        let scope = iTermVariableScope()
        scope.add(variables, toScopeNamed: nil)
        return (scope, variables)
    }

    private func number(_ value: AnyObject?) -> NSNumber? {
        return value as? NSNumber
    }

    // MARK: - Tests

    func testWriteThenRead() {
        let (scope, _) = makeScope()
        scope.setValue(123, forVariableNamed: "v")
        XCTAssertEqual(number(scope.value(forVariableName: "v") as AnyObject?), 123)
    }

    func testReferenceProducesValueOnChange() {
        let (scope, _) = makeScope()
        scope.setValue(123, forVariableNamed: "v")

        var actual: NSNumber?
        let ref = iTermVariableReference<AnyObject>(path: "v", vendor: scope)
        ref.onChangeBlock = {
            actual = ref.value as? NSNumber
        }

        scope.setValue(987, forVariableNamed: "v")
        XCTAssertEqual(actual, 987)
    }

    func testReferenceCanSetValue() {
        let (scope, _) = makeScope()
        scope.setValue(123, forVariableNamed: "v")

        let ref = iTermVariableReference<AnyObject>(path: "v", vendor: scope)
        ref.value = 987 as NSNumber
        XCTAssertEqual(number(scope.value(forVariableName: "v") as AnyObject?), 987)
    }

    func testLateResolutionOfReferenceToUnsetVariable() {
        let (scope, _) = makeScope()

        let ref = iTermVariableReference<AnyObject>(path: "v", vendor: scope)
        var actual: NSNumber?
        ref.onChangeBlock = {
            actual = ref.value as? NSNumber
        }

        scope.setValue(987, forVariableNamed: "v")
        XCTAssertEqual(actual, 987)
    }

    func testReferenceFollowsChangeOfIntermediateObject() {
        let (tabScope, _) = makeScope(context: .tab)
        let (session1Scope, session1) = makeScope()
        let (session2Scope, session2) = makeScope()

        tabScope.setValue(session1, forVariableNamed: "currentSession")
        session1Scope.setValue(1, forVariableNamed: "n")
        session2Scope.setValue(2, forVariableNamed: "n")

        let ref = iTermVariableReference<AnyObject>(path: "currentSession.n", vendor: tabScope)
        var actual: NSNumber?
        ref.onChangeBlock = {
            actual = ref.value as? NSNumber
        }
        XCTAssertEqual(ref.value as? NSNumber, 1)

        tabScope.setValue(session2, forVariableNamed: "currentSession")
        XCTAssertEqual(ref.value as? NSNumber, 2)
        XCTAssertEqual(actual, 2)
    }

    func testLateResolutionOfIntermediateObject() {
        let (tabScope, _) = makeScope(context: .tab)
        let (session1Scope, session1) = makeScope()
        session1Scope.setValue(123, forVariableNamed: "n")

        let ref = iTermVariableReference<AnyObject>(path: "currentSession.n", vendor: tabScope)
        var actual: NSNumber?
        ref.onChangeBlock = {
            actual = ref.value as? NSNumber
        }
        tabScope.setValue(session1, forVariableNamed: "currentSession")
        XCTAssertEqual(actual, 123)
    }

    func testFrameAddedToCopiedScopeShadowsOriginalWithoutModifyingIt() throws {
        let (scope1, vars1) = makeScope()
        scope1.setValue(123, forVariableNamed: "v")

        let scope2 = try XCTUnwrap(scope1.copy() as? iTermVariableScope)
        let vars2 = iTermVariables(context: .session, owner: self)
        scope2.add(vars2, toScopeNamed: nil)
        scope2.setValue(234, forVariableNamed: "v")

        XCTAssertEqual(number(scope1.value(forVariableName: "v") as AnyObject?), 123)
        XCTAssertEqual(number(vars1.discouragedValue(forVariableName: "v") as AnyObject?), 123)

        XCTAssertEqual(number(scope2.value(forVariableName: "v") as AnyObject?), 234)
        XCTAssertEqual(number(vars2.discouragedValue(forVariableName: "v") as AnyObject?), 234)
    }
}
