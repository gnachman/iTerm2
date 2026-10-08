//
//  InterpolateBuiltInFunctionTests.swift
//  ModernTests
//
//  iterm2.interpolate(string:) evaluates an interpolated string in the scope it is
//  invoked in. it2 session list --format relies on it through InvokeFunctionRequest,
//  which goes through iTermScriptFunctionCall, so these tests do too.
//

import XCTest
@testable import iTerm2SharedARC

final class InterpolateBuiltInFunctionTests: XCTestCase, iTermObject {
    private var scope: iTermVariableScope!
    private var variables: iTermVariables!

    override func setUp() {
        super.setUp()
        scope = iTermVariableScope()
        variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)
        scope.setValue("/tmp/a b", forVariableNamed: "path")
        scope.setValue("vim", forVariableNamed: "jobName")
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { scope }

    // MARK: - Helpers

    private func call(_ invocation: String) -> (Any?, Error?) {
        let expectation = XCTestExpectation(description: invocation)
        var output: Any?
        var outputError: Error?
        iTermScriptFunctionCall.callFunction(invocation,
                                             timeout: 1,
                                             sideEffectsAllowed: false,
                                             scope: scope,
                                             retainSelf: true) { value, error, _ in
            output = value
            outputError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        return (output, outputError)
    }

    // MARK: - Tests

    func testInterpolatesVariables() {
        let (value, error) = call("iterm2.interpolate(string: \"\\(path)\\t\\(jobName)\")")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "/tmp/a b\tvim")
    }

    func testPlainString() {
        let (value, error) = call("iterm2.interpolate(string: \"hello\")")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "hello")
    }

    // An undefined variable interpolates to an empty string rather than failing, so a
    // --format naming a variable some sessions lack still prints a line for them.
    func testUndefinedVariableIsEmpty() {
        let (value, error) = call("iterm2.interpolate(string: \"[\\(undefinedVariable)]\")")
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, "[]")
    }
}
