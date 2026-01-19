//
//  IndirectValueTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/18/26.
//

import XCTest
@testable import iTerm2SharedARC

final class IndirectValueTests: XCTestCase, iTermObject {
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
            let x = (parameters["x"] as? NSNumber)?.intValue ?? 0
            let y = (parameters["y"] as? NSNumber)?.intValue ?? 0
            completion(NSNumber(value: x + y), nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(add, namespace: nil)
    }

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Array Dereference with Literal Index

    func testArrayDereferenceWithLiteralIndex() {
        let expectation = XCTestExpectation(description: "array dereference")

        let array = [10, 20, 30, 40] as NSArray
        let indexExpr = Subexpression(number: 2)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSNumber, 30)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayDereferenceWithVariableIndex() {
        let expectation = XCTestExpectation(description: "array dereference with variable")

        scope.setValue(NSNumber(value: 1), forVariableNamed: "idx")

        let array = [10, 20, 30, 40] as NSArray
        let idxPath = IndirectValue(path: "idx")
        let indexExpr = Subexpression(indirectValue: idxPath)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSNumber, 20)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayDereferenceWithExpression() {
        let expectation = XCTestExpectation(description: "array dereference with expression")

        scope.setValue(NSNumber(value: 2), forVariableNamed: "x")

        let array = [10, 20, 30, 40, 50] as NSArray
        let xPath = IndirectValue(path: "x")
        let xExpr = Subexpression(indirectValue: xPath)
        let oneExpr = Subexpression(number: 1)
        let indexExpr = Subexpression(lhs: xExpr, plus: oneExpr) // x + 1 = 2 + 1 = 3
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSNumber, 40)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayDereferenceWithFunctionCall() {
        let expectation = XCTestExpectation(description: "array dereference with function")

        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let array = [10, 20, 30, 40, 50] as NSArray
        let funcExpr = Subexpression(functionCall: parsedExpr.functionCall)
        let indirectValue = IndirectValue(array: array, indexExpression: funcExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 1, sideEffectsAllowed: true, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSNumber, 40) // index 3
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testArrayDereferenceNegativeIndex() {
        let expectation = XCTestExpectation(description: "array dereference negative")

        let array = [10, 20, 30] as NSArray
        let indexExpr = Subexpression(number: -1)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error for negative index")
            } second: { error in
                // Expected - negative index causes out of bounds
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayDereferenceFloatIndex() {
        let expectation = XCTestExpectation(description: "array dereference float")

        let array = [10, 20, 30, 40] as NSArray
        let indexExpr = Subexpression(number: NSNumber(value: 2.7))
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                // Should truncate to 2
                XCTAssertEqual(value as? NSNumber, 30)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayDereferenceNaNIndex() {
        let expectation = XCTestExpectation(description: "array dereference NaN")

        let array = [10, 20, 30] as NSArray
        let indexExpr = Subexpression(number: NSNumber(value: Double.nan))
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                // NaN converts to 0, so this might succeed or fail depending on implementation
                // Just document the behavior
            } second: { error in
                // Error is also acceptable
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Async Detection

    func testRequiresAsyncWhenIndexHasFunction() {
        let parser = iTermExpressionParser.callParser()!
        guard let parsedExpr = parser.parse("add(x:1, y:2)", scope: scope) else {
            XCTFail("Failed to parse")
            return
        }

        let array = [10, 20, 30] as NSArray
        let funcExpr = Subexpression(functionCall: parsedExpr.functionCall)
        let indirectValue = IndirectValue(array: array, indexExpression: funcExpr)

        XCTAssertTrue(indirectValue.requiresAsyncEvaluation)
        XCTAssertTrue(indirectValue.containsAnyFunctionCall)
    }

    func testSynchronousWhenIndexIsLiteral() {
        let array = [10, 20, 30] as NSArray
        let indexExpr = Subexpression(number: 1)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        XCTAssertFalse(indirectValue.requiresAsyncEvaluation)
        XCTAssertFalse(indirectValue.containsAnyFunctionCall)
    }

    func testSynchronousValueWithSyncIndex() {
        let array = [100, 200, 300] as NSArray
        let indexExpr = Subexpression(number: 1)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        let value = indirectValue.synchronousValue(scope: scope)
        XCTAssertEqual(value as? NSNumber, 200)
    }

    // MARK: - Error Conditions

    func testErrorStoredInConstructor() {
        let expectation = XCTestExpectation(description: "error stored")

        let indirectValue = IndirectValue(error: "Test error message", path: "somePath")

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertTrue(error.localizedDescription.contains("Test error message"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testValueStoredInConstructor() {
        let expectation = XCTestExpectation(description: "value stored")

        let storedValue = NSNumber(value: 42)
        let indirectValue = IndirectValue(value: storedValue, path: nil)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSNumber, 42)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testMissingValueError() {
        let expectation = XCTestExpectation(description: "missing value")

        let indirectValue = IndirectValue(value: nil, path: nil)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertTrue(error.localizedDescription.contains("Missing value"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testValueStoredReturnsValueDirectly() {
        let expectation = XCTestExpectation(description: "value stored returns directly")

        let storedString = "This is a string" as NSString
        let indirectValue = IndirectValue(value: storedString, path: nil)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                // When value is stored directly, it's returned as-is
                XCTAssertEqual(value as? NSString, storedString)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testPathNotFound() {
        let expectation = XCTestExpectation(description: "path not found")

        let indirectValue = IndirectValue(path: "nonexistentVariable")

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten error")
            } second: { error in
                XCTAssertTrue(error.localizedDescription.contains("nonexistentVariable"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Optional Path

    func testOptionalPath() {
        let indirectValue = IndirectValue(path: "null")
        XCTAssertTrue(indirectValue.isOptional)
    }

    func testNonOptionalPath() {
        let indirectValue = IndirectValue(path: "somePath")
        XCTAssertFalse(indirectValue.isOptional)
    }

    // MARK: - Complex Index Expressions

    func testComplexIndexExpression() {
        let expectation = XCTestExpectation(description: "complex index")

        scope.setValue(NSNumber(value: 2), forVariableNamed: "base")
        scope.setValue(NSNumber(value: 3), forVariableNamed: "multiplier")

        let array = [0, 10, 20, 30, 40, 50, 60] as NSArray
        let basePath = IndirectValue(path: "base")
        let baseExpr = Subexpression(indirectValue: basePath)
        let multPath = IndirectValue(path: "multiplier")
        let multExpr = Subexpression(indirectValue: multPath)
        let indexExpr = Subexpression(lhs: baseExpr, times: multExpr) // 2 * 3 = 6
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSNumber, 60)
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayOfNonNumbers() {
        let expectation = XCTestExpectation(description: "array of strings")

        let array = ["first", "second", "third"] as NSArray
        let indexExpr = Subexpression(number: 1)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTAssertEqual(value as? NSString, "second")
            } second: { error in
                XCTFail("Got error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayOutOfBounds() {
        let expectation = XCTestExpectation(description: "array out of bounds")

        let array = [10, 20, 30] as NSArray
        let indexExpr = Subexpression(number: 10)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { _ in
                XCTFail("Should have gotten out of bounds error")
            } second: { error in
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Nil Safety Guards via Expression Evaluator

    func testArrayIndexWithNullValueInArithmetic() {
        scope.setValue([10, 20, 30] as NSArray, forVariableNamed: "arr")
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        // nullVar + 1 should trigger the safety guard when synchronousValue
        // tries to cast nil to NSNumber
        let evaluator = iTermExpressionEvaluator(expressionString: "arr[nullVar + 1]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: false) { eval in
            // Should trigger safety guard or produce error
            if let _ = eval.value {
                XCTFail("Should have gotten error or crash")
            } else if let error = eval.error {
                // Expected - error from safety guard or earlier
                XCTAssertNotNil(error)
            } else {
                XCTFail("Should have either value or error")
            }
        }
    }

    // MARK: - Array Bounds Checking (Async Path)

    func testArrayIndexOutOfBoundsPositiveAsync() {
        let expectation = XCTestExpectation(description: "async out of bounds positive")

        scope.setValue(NSNumber(value: 100), forVariableNamed: "idx")

        let array = [10, 20, 30] as NSArray
        let idxPath = IndirectValue(path: "idx")
        let indexExpr = Subexpression(indirectValue: idxPath)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTFail("Should have gotten out of bounds error, got value: \(value)")
            } second: { error in
                XCTAssertNotNil(error)
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("out of bounds") || desc.contains("index"),
                    "Error should mention out of bounds: \(error.localizedDescription)"
                )
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayIndexOutOfBoundsNegativeAsync() {
        let expectation = XCTestExpectation(description: "async out of bounds negative")

        scope.setValue(NSNumber(value: -1), forVariableNamed: "idx")

        let array = [10, 20, 30] as NSArray
        let idxPath = IndirectValue(path: "idx")
        let indexExpr = Subexpression(indirectValue: idxPath)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTFail("Should have gotten out of bounds error for negative index, got value: \(value)")
            } second: { error in
                XCTAssertNotNil(error)
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("out of bounds") || desc.contains("index"),
                    "Error should mention out of bounds: \(error.localizedDescription)"
                )
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayIndexExactlyAtBoundAsync() {
        let expectation = XCTestExpectation(description: "async index at bound")

        scope.setValue(NSNumber(value: 3), forVariableNamed: "idx")

        let array = [10, 20, 30] as NSArray // Valid indices: 0, 1, 2
        let idxPath = IndirectValue(path: "idx")
        let indexExpr = Subexpression(indirectValue: idxPath)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTFail("Index 3 should be out of bounds for array of size 3, got value: \(value)")
            } second: { error in
                XCTAssertNotNil(error)
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("out of bounds") || desc.contains("index"),
                    "Error should mention out of bounds: \(error.localizedDescription)"
                )
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayIndexWithComputedOutOfBoundsAsync() {
        let expectation = XCTestExpectation(description: "async computed out of bounds")

        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")

        let array = [10, 20, 30] as NSArray
        // x + 10 = 5 + 10 = 15, which is out of bounds
        let xPath = IndirectValue(path: "x")
        let xExpr = Subexpression(indirectValue: xPath)
        let ten = Subexpression(number: 10)
        let indexExpr = Subexpression(lhs: xExpr, plus: ten)
        let indirectValue = IndirectValue(array: array, indexExpression: indexExpr)

        indirectValue.evaluate(invocation: "test", receiver: nil, timeout: 0, sideEffectsAllowed: false, scope: scope) { result in
            result.whenFirst { value in
                XCTFail("Computed index out of bounds should error, got value: \(value)")
            } second: { error in
                XCTAssertNotNil(error)
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("out of bounds") || desc.contains("index"),
                    "Error should mention out of bounds: \(error.localizedDescription)"
                )
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testArrayIndexBoundsWithFunctionCallAsync() {
        let expectation = XCTestExpectation(description: "async function call out of bounds")

        scope.setValue(NSNumber(value: 5), forVariableNamed: "x")
        let array = [10, 20, 30] as NSArray
        scope.setValue(array, forVariableNamed: "arr")

        // add(x:5, y:100) = 105, which is out of bounds
        let evaluator = iTermExpressionEvaluator(expressionString: "arr[add(x:x, y:100)]", scope: scope)

        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            // The main point of this test is to not crash - the exact error doesn't matter
            XCTAssertNil(eval.value, "Function call returning out of bounds index should fail")
            XCTAssertNotNil(eval.error, "Should produce an error")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}
