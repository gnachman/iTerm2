//
//  ExpressionSystemIntegrationTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/18/26.
//

import XCTest
@testable import iTerm2SharedARC

// Integration tests for the entire expression system
final class ExpressionSystemIntegrationTests: XCTestCase, iTermObject {
    private var savedBIFs: Any?
    private var scope: iTermVariableScope!

    override func setUp() {
        super.setUp()
        savedBIFs = iTermBuiltInFunctions.sharedInstance().savedState()

        registerTestFunctions()

        scope = iTermVariableScope()
        let variables = iTermVariables(context: [], owner: self)
        scope.add(variables, toScopeNamed: nil)
    }

    override func tearDown() {
        if let saved = savedBIFs {
            iTermBuiltInFunctions.sharedInstance().restoreState(saved)
        }
        super.tearDown()
    }

    private func registerTestFunctions() {
        let add = iTermBuiltInFunction(
            name: "add",
            arguments: ["x": NSNumber.self, "y": NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { parameters, completion in
            let x = (parameters["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (parameters["y"] as? NSNumber)?.doubleValue ?? 0
            completion(NSNumber(value: x + y), nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(add, namespace: nil)
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - End-to-End Expression Evaluation

    func testCompleteArithmeticExpression() {
        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "(5 + 3) * 2 - 1", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 15)
    }

    func testExpressionWithVariablesAndArithmetic() {
        scope.setValue(NSNumber(value: 10), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 5), forVariableNamed: "y")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "x * 2 + y", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 25)
    }

    func testExpressionWithFunctionAndArithmetic() {
        let expectation = XCTestExpectation(description: "function and arithmetic")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 5, y: 3) * 2", scope: scope)
        evaluator.evaluate(withTimeout: 1, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(output as? NSNumber, 16)
    }

    func testArrayIndexingWithArithmetic() {
        let array = [10, 20, 30, 40, 50] as NSArray
        scope.setValue(array, forVariableNamed: "arr")
        scope.setValue(NSNumber(value: 2), forVariableNamed: "base")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "arr[base + 1]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 40)
    }

    func testNestedTernaryWithArithmetic() {
        scope.setValue(NSNumber(value: 1), forVariableNamed: "flag")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "flag ? (5 + 5) : (10 * 2)", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 10)
    }

    func testComplexNestedExpression() {
        scope.setValue(NSNumber(value: 3), forVariableNamed: "x")
        scope.setValue(NSNumber(value: 4), forVariableNamed: "y")
        scope.setValue([10, 20, 30, 40] as NSArray, forVariableNamed: "arr")

        var output: Any?
        // arr[(x + y) / 2] - 5 = arr[3] - 5 = 40 - 5 = 35
        let evaluator = iTermExpressionEvaluator(expressionString: "arr[(x + y) / 2] - 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }
        XCTAssertEqual(output as? NSNumber, 35)
    }

    // MARK: - Expression Rule Integration

    func testExpressionRuleParsing() {
        // Changed to use simple expression since comparison operators not implemented
        let rule = iTermRule(string: "{columns * rows}")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.expression, "columns * rows")
    }

    func testExpressionRuleScoring() {
        class TestProvider: NSObject, AutomaticProfileSwitchingExpressionScoreProvider {
            func score(forExpression expression: String) -> Double {
                // Note: expression received WITHOUT braces (braces are stripped by rule parsing)
                // Changed to use simple expression since comparison operators not implemented
                if expression == "columns * rows" {
                    return 42.0
                }
                return -Double.infinity
            }
        }

        let provider = TestProvider()
        let rule = iTermRule(string: "{columns * rows}")

        let score = rule?.score(forHostname: "anyhost",
                               username: "anyuser",
                               path: "/anypath",
                               job: "anyjob",
                               commandLine: "",
                               expressionValueProvider: provider)
        XCTAssertEqual(score, 42.0)
    }

    // MARK: - Concurrent Evaluation

    func testConcurrentBinaryEvaluation() {
        let expectation = XCTestExpectation(description: "concurrent evaluation")

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "add(x: 1, y: 2) + add(x: 3, y: 4)", scope: scope)
        evaluator.evaluate(withTimeout: 2, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)
        XCTAssertEqual(output as? NSNumber, 10)
    }

    // MARK: - Error Handling

    func testErrorPropagationThroughComplexExpression() {
        // x is undefined
        var output: Any?
        var error: Error?
        let evaluator = iTermExpressionEvaluator(expressionString: "(x + 5) * 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            error = eval.error
        }

        XCTAssertNil(output)
        XCTAssertNotNil(error)
    }

    func testTypeMismatchInComplexExpression() {
        scope.setValue("string" as NSString, forVariableNamed: "x")

        var error: Error?
        let evaluator = iTermExpressionEvaluator(expressionString: "x + 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            error = eval.error
        }

        XCTAssertNotNil(error)
    }

    // MARK: - Performance

    func testLargeArithmeticExpression() {
        // Test that deeply nested expressions don't cause stack overflow or excessive delay
        var exprString = "1"
        for i in 2...50 {
            exprString += " + \(i)"
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: exprString, scope: scope)
        evaluator.evaluate(withTimeout: 1, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }

        // Sum of 1 to 50 = 1275
        XCTAssertEqual(output as? NSNumber, 1275)
    }

    func testManyVariablesInExpression() {
        for i in 1...20 {
            scope.setValue(NSNumber(value: i), forVariableNamed: "v\(i)")
        }

        var output: Any?
        let evaluator = iTermExpressionEvaluator(expressionString: "v1 + v2 + v3 + v4 + v5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            output = eval.value
            XCTAssertNil(eval.error)
        }

        XCTAssertEqual(output as? NSNumber, 15)
    }

    // MARK: - Mixed Rule Types

    func testMixedRuleTypeScoring() {
        class MixedProvider: NSObject, AutomaticProfileSwitchingExpressionScoreProvider {
            func score(forExpression expression: String) -> Double {
                // Note: expression received WITHOUT braces (braces are stripped by rule parsing)
                if expression == "myvar" {
                    return 100.0
                }
                return -Double.infinity
            }
        }

        let provider = MixedProvider()

        // Expression rule
        let exprRule = iTermRule(string: "{myvar}")
        let exprScore = exprRule?.score(forHostname: "host",
                                        username: "user",
                                        path: "/path",
                                        job: "job",
                                        commandLine: "",
                                        expressionValueProvider: provider) ?? 0

        // Traditional rule
        let tradRule = iTermRule(string: "host")
        let tradScore = tradRule?.score(forHostname: "host",
                                        username: "user",
                                        path: "/path",
                                        job: "job",
                                        commandLine: "",
                                        expressionValueProvider: provider) ?? 0

        // Expression should win with score 100
        XCTAssertEqual(exprScore, 100.0)
        XCTAssertGreaterThan(tradScore, 0)
        XCTAssertGreaterThan(exprScore, tradScore)
    }
}
