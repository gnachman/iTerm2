//
//  TriggerInterpolatedParameterTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/21/26.
//

import XCTest
@testable import iTerm2SharedARC

final class TriggerInterpolatedParameterTests: XCTestCase, iTermObject {
    private let matches = ["T12345678", "T", "12345678"]

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Classification

    func testPlainStringIsLiteral() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter("https://example.com/").kind, .literal)
    }

    func testBackreferenceSyntaxIsLiteral() {
        // \1 is the non-interpolated backreference syntax, not an interpolated expression.
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"https://example.com/\1"#).kind, .literal)
    }

    func testMatchReferenceIsTriggerLocal() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"https://example.com/lookup?q=\(matches[0])"#).kind,
                       .triggerLocal)
    }

    func testLineReferenceIsTriggerLocal() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"line \(line)"#).kind, .triggerLocal)
    }

    func testSessionVariableRequiresScope() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"\(path)/\(matches[0])"#).kind, .requiresScope)
    }

    func testFunctionCallRequiresScope() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"\(f(x: matches[0]))"#).kind, .requiresScope)
    }

    func testOperatorRequiresScope() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"\(matches[0] + "x")"#).kind, .requiresScope)
    }

    func testComputedIndexRequiresScope() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"\(matches[1 + 1])"#).kind, .requiresScope)
    }

    func testOptionalRequiresScope() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"\(matches[0]?)"#).kind, .requiresScope)
    }

    func testWholeArrayRequiresScope() {
        XCTAssertEqual(TriggerInterpolatedParameter.parameter(#"\(matches)"#).kind, .requiresScope)
    }

    func testResultIsCached() {
        let string = #"https://example.com/\(matches[2])"#
        XCTAssertTrue(TriggerInterpolatedParameter.parameter(string) ===
                      TriggerInterpolatedParameter.parameter(string))
    }

    // MARK: - Evaluation

    func testValue() {
        let parameter = TriggerInterpolatedParameter.parameter(#"https://example.com/lookup?q=\(matches[0])"#)
        XCTAssertEqual(parameter.value(matches: matches, absLine: 7), "https://example.com/lookup?q=T12345678")
    }

    func testValueWithWhitespaceAndLine() {
        let parameter = TriggerInterpolatedParameter.parameter(#"\( matches [ 2 ] ) on \(line)"#)
        XCTAssertEqual(parameter.value(matches: matches, absLine: 42), "12345678 on 42")
    }

    func testIndexOutOfRangeReturnsNil() {
        let parameter = TriggerInterpolatedParameter.parameter(#"\(matches[3])"#)
        XCTAssertNil(parameter.value(matches: matches, absLine: 0))
    }

    func testMissingLineReturnsNil() {
        let parameter = TriggerInterpolatedParameter.parameter(#"\(line)"#)
        XCTAssertNil(parameter.value(matches: matches, absLine: -1))
    }

    // MARK: - Parity with the general evaluator

    // The template must produce exactly what the general evaluator would, including escape
    // expansion in the literal parts.
    func testParityWithGeneralEvaluator() throws {
        let strings = [
            #"https://example.com/lookup?q=\(matches[0])"#,
            #"\(matches[1])-\(matches[2])"#,
            #"tab\there\(matches[0])\n"#,
            #"quote \"\(matches[0])\" backslash \\"#,
            #"é\(matches[0])"#,
            #"line \(line):\(matches[2])"#,
            #"\(matches[0])"#,
        ]
        let scope = iTermVariableScope()
        scope.add(iTermVariables(context: [], owner: self), toScopeNamed: nil)
        for string in strings {
            let parameter = TriggerInterpolatedParameter.parameter(string)
            XCTAssertEqual(parameter.kind, .triggerLocal, string)
            let evaluator = SwiftyStringWithBackreferencesEvaluator(string)
            let expected = try evaluator.evaluate(additionalContext: ["matches": matches as NSArray,
                                                                      "line": NSNumber(value: 99)],
                                                  scope: scope,
                                                  owner: self,
                                                  sideEffectsAllowed: false)
            XCTAssertEqual(parameter.value(matches: matches, absLine: 99), expected, string)
        }
    }
}
