//
//  TypeSafetyEdgeCaseTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/19/26.
//  Tests for type safety in arithmetic operations - addresses user concerns:
//  - "3 * a" (number with string)
//  - "[1,2] + 3" (array with number)
//

import XCTest
@testable import iTerm2SharedARC

final class TypeSafetyEdgeCaseTests: XCTestCase, iTermObject {
    private var savedBIFs: Any?
    private var scope: iTermVariableScope!

    override func setUp() {
        super.setUp()
        savedBIFs = iTermBuiltInFunctions.sharedInstance().savedState()

        // Register function that returns string
        let stringFunc = iTermBuiltInFunction(
            name: "getString",
            arguments: [:],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { _, completion in
            completion("hello" as NSString, nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(stringFunc, namespace: nil)

        // Register function that returns array
        let arrayFunc = iTermBuiltInFunction(
            name: "getArray",
            arguments: [:],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil
        ) { _, completion in
            completion([1, 2, 3] as NSArray, nil)
        }
        iTermBuiltInFunctions.sharedInstance().register(arrayFunc, namespace: nil)

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

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    // MARK: - Arithmetic with Strings (User Concern: "3 * a")

    func testMultiplyNumberByString() {
        scope.setValue("hello" as NSString, forVariableNamed: "str")

        let evaluator = iTermExpressionEvaluator(expressionString: "3 * str", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "3 * string should fail")
            XCTAssertNotNil(eval.error, "Should produce error for number * string")
            if let error = eval.error {
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("arithmetic operations require numeric operands"),
                    "Error message should mention type issue: \(error.localizedDescription)"
                )
            }
        }
    }

    func testAddNumberToString() {
        scope.setValue("world" as NSString, forVariableNamed: "str")

        let evaluator = iTermExpressionEvaluator(expressionString: "5 + str", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "5 + string should fail")
            XCTAssertNotNil(eval.error, "Should produce error for number + string")
        }
    }

    func testSubtractStringFromNumber() {
        scope.setValue("5" as NSString, forVariableNamed: "str")

        let evaluator = iTermExpressionEvaluator(expressionString: "10 - str", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "10 - string should fail")
            XCTAssertNotNil(eval.error, "Should produce error for number - string")
        }
    }

    func testDivideNumberByString() {
        scope.setValue("4" as NSString, forVariableNamed: "str")

        let evaluator = iTermExpressionEvaluator(expressionString: "20 / str", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "20 / string should fail")
            XCTAssertNotNil(eval.error, "Should produce error for number / string")
        }
    }

    func testNegateString() {
        scope.setValue("hello" as NSString, forVariableNamed: "str")

        let evaluator = iTermExpressionEvaluator(expressionString: "-str", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "-string should fail")
            XCTAssertNotNil(eval.error, "Should produce error for negating string")
        }
    }

    // MARK: - Arithmetic with Arrays

    func testAddArrayToNumber() {
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr + 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "array + number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for array + number")
            if let error = eval.error {
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("number") || desc.contains("array") || desc.contains("type") || desc.contains("nil"),
                    "Error message should mention type issue: \(error.localizedDescription)"
                )
            }
        }
    }

    func testMultiplyArrayByNumber() {
        scope.setValue([1, 2] as NSArray, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr * 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "array * number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for array * number")
        }
    }

    func testSubtractNumberFromArray() {
        scope.setValue([10, 20] as NSArray, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr - 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "array - number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for array - number")
        }
    }

    func testDivideArrayByNumber() {
        scope.setValue([10, 20] as NSArray, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr / 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "array / number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for array / number")
        }
    }

    func testNegateArray() {
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "arr")

        let evaluator = iTermExpressionEvaluator(expressionString: "-arr", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "-array should fail")
            XCTAssertNotNil(eval.error, "Should produce error for negating array")
        }
    }

    // MARK: - Null Handling in Arithmetic

    func testNullInAddition() {
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        let evaluator = iTermExpressionEvaluator(expressionString: "nullVar + 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "null + number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for null in arithmetic")
        }
    }

    func testNullInSubtraction() {
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        let evaluator = iTermExpressionEvaluator(expressionString: "5 - nullVar", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "number - null should fail")
            XCTAssertNotNil(eval.error, "Should produce error for null in arithmetic")
        }
    }

    func testNullInMultiplication() {
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        let evaluator = iTermExpressionEvaluator(expressionString: "3 * nullVar", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "number * null should fail")
            XCTAssertNotNil(eval.error, "Should produce error for null in arithmetic")
        }
    }

    func testNullInDivision() {
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        let evaluator = iTermExpressionEvaluator(expressionString: "10 / nullVar", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "number / null should fail")
            XCTAssertNotNil(eval.error, "Should produce error for null in arithmetic")
        }
    }

    func testNullInNegation() {
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        let evaluator = iTermExpressionEvaluator(expressionString: "-nullVar", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "-null should fail")
            XCTAssertNotNil(eval.error, "Should produce error for negating null")
        }
    }

    func testOptionalNullVariable() {
        // x? where x is undefined should return null, no error
        let evaluator = iTermExpressionEvaluator(expressionString: "undefinedVar?", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.error, "Optional undefined variable should not error")
            // Result should be nil (not NSNull in scope, just nil/missing)
            XCTAssertNil(eval.value, "Optional undefined variable should return nil")
        }
    }

    func testNonOptionalUndefinedVariable() {
        // x where x is undefined should error
        let evaluator = iTermExpressionEvaluator(expressionString: "undefinedVar", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Non-optional undefined variable should fail")
            XCTAssertNotNil(eval.error, "Should produce error for undefined variable")
            if let error = eval.error {
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("undefined") || desc.contains("variable") || desc.contains("reference"),
                    "Error message should mention undefined variable: \(error.localizedDescription)"
                )
            }
        }
    }

    func testNullInArrayIndex() {
        scope.setValue([1, 2, 3] as NSArray, forVariableNamed: "arr")
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        let evaluator = iTermExpressionEvaluator(expressionString: "arr[nullVar]", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Array index with null should fail")
            XCTAssertNotNil(eval.error, "Should produce error for null array index")
            if let error = eval.error {
                let desc = error.localizedDescription.lowercased()
                XCTAssertTrue(
                    desc.contains("index") || desc.contains("number"),
                    "Error message should mention array index issue: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Function Return Type Mixing

    func testFunctionReturningStringInArithmetic() {
        let evaluator = iTermExpressionEvaluator(expressionString: "getString() + 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "string function result + number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for string + number")
        }
    }

    func testFunctionReturningArrayInArithmetic() {
        let evaluator = iTermExpressionEvaluator(expressionString: "getArray() * 3", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "array function result * number should fail")
            XCTAssertNotNil(eval.error, "Should produce error for array * number")
        }
    }

    func testMixedTypesInComplexExpression() {
        scope.setValue("hello" as NSString, forVariableNamed: "str")

        // (3 + str) * 5 - the inner addition should fail and propagate error
        let evaluator = iTermExpressionEvaluator(expressionString: "(3 + str) * 5", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            XCTAssertNil(eval.value, "Type error in subexpression should propagate")
            XCTAssertNotNil(eval.error, "Should produce error for type mismatch in subexpression")
        }
    }

    // MARK: - Ternary with Type Errors

    func testTernaryWithTypeMismatchInCondition() {
        scope.setValue("hello" as NSString, forVariableNamed: "str")

        // str ? 1 : 2 - condition is string, which should be treated as error or truthy
        let evaluator = iTermExpressionEvaluator(expressionString: "str ? 1 : 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            // Strings might be truthy or might error - either is acceptable
            // Just verify it doesn't crash
            if eval.error == nil {
                XCTAssertNotNil(eval.value, "If no error, should return a value")
            }
        }
    }

    func testTernaryWithNullInCondition() {
        scope.setValue(NSNull(), forVariableNamed: "nullVar")

        // nullVar ? 1 : 2 - null should be falsy, return 2
        let evaluator = iTermExpressionEvaluator(expressionString: "nullVar ? 1 : 2", scope: scope)
        evaluator.evaluate(withTimeout: 0, sideEffectsAllowed: true) { eval in
            // Null might be falsy (return 2) or might error - either is acceptable
            if eval.error == nil {
                XCTAssertNotNil(eval.value, "If no error, should return a value")
            }
        }
    }
}
