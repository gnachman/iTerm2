//
//  FunctionCallSuggesterLegacyCasesTests.swift
//  iTerm2
//
//  Ported from the legacy iTermFunctionCallSuggesterTest.m. The cases here are the
//  ones not already covered by iTermFunctionCallSuggesterTests: an exact-order
//  function-name suggestion list and structural parses of function calls whose
//  arguments are string literals and (nested) interpolated strings.
//

import XCTest
@testable import iTerm2SharedARC

final class FunctionCallSuggesterLegacyCasesTests: XCTestCase, iTermObject {
    private var suggester: iTermFunctionCallSuggester!
    private var parser: iTermExpressionParser!
    private var scope: iTermVariableScope!

    override func setUp() {
        super.setUp()
        let signatures = [ "func1": [ "arg1", "arg2" ],
                           "func2": [] ]
        let paths = Set([ "path.first", "path.second", "third" ])
        suggester = iTermFunctionCallSuggester(functionSignatures: signatures,
                                               pathSource: { _ in paths })
        parser = iTermExpressionParser.expressionParser()

        scope = iTermVariableScope()
        scope.add(iTermVariables(context: [], owner: self), toScopeNamed: nil)
    }

    override func tearDown() {
        suggester = nil
        parser = nil
        scope = nil
        super.tearDown()
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Helpers

    // iTermScriptFunctionCall.name is readwrite only in a class extension, which Swift
    // imports as get-only, so an expected call cannot be built by hand. Instead the
    // parsed call is checked structurally: its type, name, signature, and the
    // description of its single parameter, which is built from real
    // iTermParsedExpression objects so that it tracks their description format.
    private func assertParsedCall(_ maybeActual: iTermParsedExpression?,
                                  named name: String,
                                  parameterName: String,
                                  parameterValue: iTermParsedExpression,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        guard let actual = maybeActual else {
            XCTFail("parse returned nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.expressionType, .functionCall, file: file, line: line)
        guard actual.expressionType == .functionCall else {
            return
        }
        let call = actual.functionCall
        XCTAssertEqual(call.name, name, file: file, line: line)
        XCTAssertEqual(call.signature, "\(name)(\(parameterName))", file: file, line: line)
        XCTAssertEqual(call.description,
                       "<Func \(name)(\(parameterName): \(parameterValue))>",
                       file: file,
                       line: line)
    }

    private func interpolated(_ parts: [iTermParsedExpression]) -> iTermParsedExpression {
        return iTermParsedExpression(interpolatedStringParts: parts)
    }

    private func literal(_ string: String) -> iTermParsedExpression {
        return iTermParsedExpression(string: string)
    }

    // MARK: - Suggestions

    func testSuggestFunctionNamesForPrefixListsExactlyTheMatchingSignatures() {
        // The suggester enumerates NSDictionary.allKeys, so the relative order of the
        // two functions is not stable. Compare sorted to keep this deterministic while
        // still requiring exactly these two suggestions and nothing else.
        let actual = suggester.suggestions(for: "f")
        XCTAssertEqual(actual.sorted(), [ "func1(arg1:", "func2()" ])
    }

    // MARK: - Parsing

    func testParseFunctionCallWithStringLiteral() {
        let actual = parser.parse("func(x: \"foo\")", scope: scope)
        assertParsedCall(actual, named: "func", parameterName: "x", parameterValue: literal("foo"))
    }

    func testParseFunctionCallWithSwiftyStringFoldsResolvedVariableIntoLiteral() {
        scope.setValue("value", forVariableNamed: "path")
        let actual = parser.parse("func(x: \"foo\\(path)bar\")", scope: scope)
        assertParsedCall(actual,
                         named: "func",
                         parameterName: "x",
                         parameterValue: interpolated([ literal("foovaluebar") ]))
    }

    func testParseFunctionCallWithNestedSwiftyString() throws {
        // func(                                                      )
        //      x: "foo\(                                        )bar"
        //               inner(                                 )
        //                     s: "Hello \(     ), how are you?"
        //                                 world
        scope.setValue("WORLD", forVariableNamed: "world")
        let actual = parser.parse("func(x: \"foo\\(inner(s: \"Hello \\(world), how are you?\"))bar\")",
                                  scope: scope)

        // The inner call's expected form is produced by parsing it on its own, since
        // its structure is asserted independently above the nesting.
        let innerCall = try XCTUnwrap(parser.parse("inner(s: \"Hello \\(world), how are you?\")", scope: scope))
        assertParsedCall(innerCall,
                         named: "inner",
                         parameterName: "s",
                         parameterValue: interpolated([ literal("Hello WORLD, how are you?") ]))

        let xValue = interpolated([ literal("foo"), innerCall, literal("bar") ])
        assertParsedCall(actual, named: "func", parameterName: "x", parameterValue: xValue)
    }
}
