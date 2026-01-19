//
//  Subexpression.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/13/26.
//

import Foundation

@objc(iTermSubexpression)
class Subexpression: NSObject {
    private enum Expression: CustomDebugStringConvertible {
        case literal(NSNumber)
        case stringLiteral(String)
        case indirect(IndirectValue)
        case functionCall(iTermScriptFunctionCall)
        case unaryOperation(operand: Subexpression,
                            operation: UnaryOperation)
        case binaryOperation(lhs: Subexpression,
                             operation: BinaryOperation,
                             rhs: Subexpression)
        case ternaryOperation(lhs: Subexpression,
                              operation: TernaryOperation,
                              mid: Subexpression,
                              rhs: Subexpression)
        case error(String)

        var requiresAsyncEvaluation: Bool {
            switch self {
            case .literal, .stringLiteral, .indirect, .error:
                false
            case .functionCall:
                true
            case .unaryOperation(operand: let operand, operation: _):
                operand.requiresAsyncEvaluation
            case let .binaryOperation(lhs: lhs, operation: _, rhs: rhs):
                lhs.requiresAsyncEvaluation || rhs.requiresAsyncEvaluation
            case let .ternaryOperation(lhs: lhs, operation: _, mid: mid, rhs: rhs):
                // This could be more efficient - when lhs can be evaluated synchronously then we
                // only need to consider either mid or rhs for ?: operator.
                lhs.requiresAsyncEvaluation || mid.requiresAsyncEvaluation || rhs.requiresAsyncEvaluation
            }
        }

        var containsAnyFunctionCall: Bool {
            switch self {
            case .literal, .stringLiteral, .indirect, .error:
                false
            case .functionCall:
                true
            case .unaryOperation(operand: let operand, operation: _):
                operand.containsAnyFunctionCall
            case let .binaryOperation(lhs: lhs, operation: _, rhs: rhs):
                lhs.containsAnyFunctionCall || rhs.containsAnyFunctionCall
            case let .ternaryOperation(lhs: lhs, operation: _, mid: mid, rhs: rhs):
                // This could be more efficient - when lhs can be evaluated synchronously then we
                // only need to consider either mid or rhs for ?: operator.
                lhs.containsAnyFunctionCall || mid.containsAnyFunctionCall || rhs.containsAnyFunctionCall
            }
        }

        var debugDescription: String {
            switch self {
            case .literal(let number):
                return number.stringValue
            case .stringLiteral(let string):
                return "\"\(string)\""
            case .indirect(let iv):
                return iv.description
            case .functionCall(let functionCall):
                return "\(functionCall)"
            case .unaryOperation(operand: let operand, operation: let operation):
                return "(\(operation) \(operand))"
            case .binaryOperation(lhs: let lhs, operation: let operation, rhs: let rhs):
                return "(\(lhs) \(operation) \(rhs))"
            case .ternaryOperation(lhs: let lhs, operation: let operation, mid: let mid, rhs: let rhs):
                return "(\(lhs) \(operation) \(mid) ? \(rhs) : \(lhs))"
            case .error(let message):
                return "<Error: \(message)>"
            }
        }
    }

    private enum UnaryOperation {
        case negate
        case logicalNot

        func execute(_ value: Double) -> NSNumber {
            switch self {
            case .negate:
                return NSNumber(value: -value)
            case .logicalNot:
                return NSNumber(value: value == 0 ? 1 : 0)
            }
        }

        func executeTyped(_ value: Any) throws -> NSNumber {
            switch self {
            case .negate:
                guard let num = value as? NSNumber else {
                    throw iTermError("Cannot negate non-numeric value")
                }
                return execute(num.doubleValue)

            case .logicalNot:
                // Only numbers allowed for logical not
                guard let num = value as? NSNumber else {
                    throw iTermError("Logical not requires numeric operand, got \(type(of: value))")
                }
                return execute(num.doubleValue)
            }
        }
    }

    private enum BinaryOperation {
        case plus
        case minus
        case times
        case dividedBy
        case equalTo
        case notEqualTo
        case lessThan
        case greaterThan
        case lessThanOrEqual
        case greaterThanOrEqual
        case logicalAnd
        case logicalOr

        func execute(lhs: Double, rhs: Double) -> NSNumber {
            switch self {
            case .plus:
                return NSNumber(value: lhs + rhs)
            case .minus:
                return NSNumber(value: lhs - rhs)
            case .times:
                return NSNumber(value: lhs * rhs)
            case .dividedBy:
                return NSNumber(value: lhs / rhs)
            case .equalTo:
                // NaN special case: NaN != NaN per IEEE 754
                if lhs.isNaN || rhs.isNaN {
                    return NSNumber(value: false)
                }
                return NSNumber(value: lhs == rhs)
            case .notEqualTo:
                // NaN special case: NaN != NaN per IEEE 754
                if lhs.isNaN || rhs.isNaN {
                    return NSNumber(value: true)
                }
                return NSNumber(value: lhs != rhs)
            case .lessThan:
                // NaN special case: NaN < x is always false
                if lhs.isNaN || rhs.isNaN {
                    return NSNumber(value: false)
                }
                return NSNumber(value: lhs < rhs)
            case .greaterThan:
                // NaN special case: NaN > x is always false
                if lhs.isNaN || rhs.isNaN {
                    return NSNumber(value: false)
                }
                return NSNumber(value: lhs > rhs)
            case .lessThanOrEqual:
                // NaN special case: NaN <= x is always false
                if lhs.isNaN || rhs.isNaN {
                    return NSNumber(value: false)
                }
                return NSNumber(value: lhs <= rhs)
            case .greaterThanOrEqual:
                // NaN special case: NaN >= x is always false
                if lhs.isNaN || rhs.isNaN {
                    return NSNumber(value: false)
                }
                return NSNumber(value: lhs >= rhs)
            case .logicalAnd:
                // Logical AND: 0 is false, non-zero is true
                let lhsTruthy = (lhs != 0)
                let rhsTruthy = (rhs != 0)
                return NSNumber(value: (lhsTruthy && rhsTruthy) ? 1 : 0)
            case .logicalOr:
                // Logical OR: 0 is false, non-zero is true
                let lhsTruthy = (lhs != 0)
                let rhsTruthy = (rhs != 0)
                return NSNumber(value: (lhsTruthy || rhsTruthy) ? 1 : 0)
            }
        }

        // Try to convert all objects to NSNumber. If any cannot be converted, then convert none of them.
        private func numberize(objects: [Any]) -> [Any] {
            let numberize: (Any) -> NSNumber? = {
                if let number = $0 as? NSNumber { return number }
                if let string = $0 as? String {
                    if let i = Int(string) { return NSNumber(value: i) }
                    if let d = Double(string) { return NSNumber(value: d) }
                }
                return nil
            }
            let numbers = objects.compactMap { numberize($0) }
            if numbers.count == objects.count {
                return numbers
            }
            return objects
        }

        private func numberize(_ tuple: (Any, Any)) -> (Any, Any) {
            let values = numberize(objects: [tuple.0, tuple.1])
            return (values[0], values[1])
        }

        // Type-aware execution for comparison operators
        func executeTyped(lhs: Any, rhs: Any) throws -> NSNumber {
            switch self {
            case .plus, .minus, .times, .dividedBy:
                // Arithmetic requires numbers
                let (ln, rn) = numberize((lhs, rhs))
                guard let lhsNum = ln as? NSNumber, let rhsNum = rn as? NSNumber else {
                    throw iTermError("Arithmetic operations require numeric operands")
                }
                return execute(lhs: lhsNum.doubleValue, rhs: rhsNum.doubleValue)

            case .equalTo, .notEqualTo:
                // Equality comparison supports all types
                let (ln, rn) = numberize((lhs, rhs))
                return try executeEquality(lhs: ln, rhs: rn, negate: self == .notEqualTo)

            case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
                // Relational comparison - type must match
                let (ln, rn) = numberize((lhs, rhs))
                return try executeRelational(lhs: ln, rhs: rn, operation: self)

            case .logicalAnd, .logicalOr:
                // Logical operators require numbers
                let (ln, rn) = numberize((lhs, rhs))
                guard let lhsNum = ln as? NSNumber, let rhsNum = rn as? NSNumber else {
                    throw iTermError("Logical operations require numeric operands")
                }
                return execute(lhs: lhsNum.doubleValue, rhs: rhsNum.doubleValue)
            }
        }

        private func executeRelational(lhs: Any, rhs: Any, operation: BinaryOperation) throws -> NSNumber {
            // Handle same type: NSNumber
            if let lhsNum = lhs as? NSNumber, let rhsNum = rhs as? NSNumber {
                return execute(lhs: lhsNum.doubleValue, rhs: rhsNum.doubleValue)
            }

            // Handle same type: NSString
            if let lhsStr = lhs as? NSString, let rhsStr = rhs as? NSString {
                let comparison = lhsStr.compare(rhsStr as String)
                switch operation {
                case .lessThan:
                    return NSNumber(value: comparison == .orderedAscending)
                case .greaterThan:
                    return NSNumber(value: comparison == .orderedDescending)
                case .lessThanOrEqual:
                    return NSNumber(value: comparison != .orderedDescending)
                case .greaterThanOrEqual:
                    return NSNumber(value: comparison != .orderedAscending)
                default:
                    throw iTermError("Invalid relational operation")
                }
            }

            // Handle same type: NSArray (lexicographic comparison)
            if let lhsArr = lhs as? NSArray, let rhsArr = rhs as? NSArray {
                let comparison = lexicographicCompare(lhs: lhsArr, rhs: rhsArr)
                switch operation {
                case .lessThan:
                    return NSNumber(value: comparison < 0)
                case .greaterThan:
                    return NSNumber(value: comparison > 0)
                case .lessThanOrEqual:
                    return NSNumber(value: comparison <= 0)
                case .greaterThanOrEqual:
                    return NSNumber(value: comparison >= 0)
                default:
                    throw iTermError("Invalid relational operation")
                }
            }

            // Handle NSNull specially
            // If either operand is NSNull:
            // - null < anything → false
            // - null > anything → false
            // - null <= null → true, null <= non-null → false
            // - null >= null → true, null >= non-null → false
            if lhs is NSNull || rhs is NSNull {
                let bothNull = (lhs is NSNull && rhs is NSNull)
                switch operation {
                case .lessThan, .greaterThan:
                    return NSNumber(value: false)
                case .lessThanOrEqual, .greaterThanOrEqual:
                    return NSNumber(value: bothNull)
                default:
                    throw iTermError("Invalid relational operation")
                }
            }

            // Different types: relational operators return error
            throw iTermError("Cannot compare incompatible types with relational operators. Left-hand side is \(type(of: lhs)), right-hand side is \(type(of: rhs))")
        }

        private func lexicographicCompare(lhs: NSArray, rhs: NSArray) -> Int {
            let minCount = min(lhs.count, rhs.count)
            for i in 0..<minCount {
                let lhsElem = lhs[i]
                let rhsElem = rhs[i]

                // Compare elements
                if let lhsNum = lhsElem as? NSNumber, let rhsNum = rhsElem as? NSNumber {
                    let lhsVal = lhsNum.doubleValue
                    let rhsVal = rhsNum.doubleValue
                    if lhsVal < rhsVal {
                        return -1
                    } else if lhsVal > rhsVal {
                        return 1
                    }
                } else if let lhsStr = lhsElem as? NSString, let rhsStr = rhsElem as? NSString {
                    let comp = lhsStr.compare(rhsStr as String)
                    if comp != .orderedSame {
                        return comp == .orderedAscending ? -1 : 1
                    }
                } else if let lhsArr = lhsElem as? NSArray, let rhsArr = rhsElem as? NSArray {
                    let comp = lexicographicCompare(lhs: lhsArr, rhs: rhsArr)
                    if comp != 0 {
                        return comp
                    }
                }
                // If elements are equal or incomparable, continue to next
            }
            // All compared elements are equal, compare by length
            if lhs.count < rhs.count {
                return -1
            } else if lhs.count > rhs.count {
                return 1
            } else {
                return 0
            }
        }

        private func executeEquality(lhs: Any, rhs: Any, negate: Bool) throws -> NSNumber {
            var equal: Bool

            // Handle same type: NSNumber
            if let lhsNum = lhs as? NSNumber, let rhsNum = rhs as? NSNumber {
                let lhsDouble = lhsNum.doubleValue
                let rhsDouble = rhsNum.doubleValue
                // NaN special case: NaN != NaN per IEEE 754
                if lhsDouble.isNaN || rhsDouble.isNaN {
                    equal = false
                } else {
                    equal = (lhsDouble == rhsDouble)
                }
            }
            // Handle same type: NSString
            else if let lhsStr = lhs as? NSString, let rhsStr = rhs as? NSString {
                equal = lhsStr.isEqual(to: rhsStr as String)
            }
            // Handle same type: NSArray
            else if let lhsArr = lhs as? NSArray, let rhsArr = rhs as? NSArray {
                equal = lhsArr.isEqual(to: rhsArr)
            }
            // Handle same type: NSNull
            else if lhs is NSNull && rhs is NSNull {
                equal = true
            }
            // Different types: == returns false, != returns true
            else {
                equal = false
            }

            // Apply negation if this is !=
            return NSNumber(value: negate ? !equal : equal)
        }
    }

    private enum TernaryOperation {
        case conditional
    }

    private let value: Expression

    override var description: String {
        "<Subexpression \(value.debugDescription)>"
    }

    // MARK: - Swift Initializers (non-optional, type-safe)

    @objc(initWithNumber:)
    init(number: NSNumber) {
        value = .literal(number)
    }

    @objc(initWithStringLiteral:)
    init(stringLiteral: String) {
        value = .stringLiteral(stringLiteral)
    }

    @objc(initWithFunctionCall:)
    init(functionCall: iTermScriptFunctionCall) {
        value = .functionCall(functionCall)
    }

    init(negated expression: Subexpression) {
        value = .unaryOperation(operand: expression, operation: .negate)
    }

    init(logicalNot expression: Subexpression) {
        value = .unaryOperation(operand: expression, operation: .logicalNot)
    }

    init(lhs: Subexpression, plus rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .plus, rhs: rhs)
    }

    init(lhs: Subexpression, minus rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .minus, rhs: rhs)
    }

    init(lhs: Subexpression, times rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .times, rhs: rhs)
    }

    init(lhs: Subexpression, dividedBy rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .dividedBy, rhs: rhs)
    }

    init(lhs: Subexpression, equalTo rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .equalTo, rhs: rhs)
    }

    init(lhs: Subexpression, notEqualTo rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .notEqualTo, rhs: rhs)
    }

    init(lhs: Subexpression, lessThan rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .lessThan, rhs: rhs)
    }

    init(lhs: Subexpression, greaterThan rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .greaterThan, rhs: rhs)
    }

    init(lhs: Subexpression, lessThanOrEqual rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .lessThanOrEqual, rhs: rhs)
    }

    init(lhs: Subexpression, greaterThanOrEqual rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .greaterThanOrEqual, rhs: rhs)
    }

    init(lhs: Subexpression, logicalAnd rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .logicalAnd, rhs: rhs)
    }

    init(lhs: Subexpression, logicalOr rhs: Subexpression) {
        value = .binaryOperation(lhs: lhs, operation: .logicalOr, rhs: rhs)
    }

    init(condition: Subexpression, whenTrue: Subexpression, whenFalse: Subexpression) {
        value = .ternaryOperation(lhs: condition,
                                  operation: .conditional,
                                  mid: whenTrue,
                                  rhs: whenFalse)
    }

    @objc(initWithIndirectValue:)
    init(indirectValue: IndirectValue) {
        value = .indirect(indirectValue)
    }

    // MARK: - Objective-C Compatible Initializers (nullable, for Obj-C bridge)

    @objc(initNegated:)
    convenience init(negated expression: Subexpression?) {
        guard let expression = expression else {
            self.init(error: "Nil operand in unary operation")
            return
        }
        self.init(negated: expression)
    }

    @objc(initLogicalNot:)
    convenience init(logicalNot expression: Subexpression?) {
        guard let expression = expression else {
            self.init(error: "Nil operand in logical not operation")
            return
        }
        self.init(logicalNot: expression)
    }

    @objc(init:plus:)
    convenience init(lhs: Subexpression?, plus rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (+)")
            return
        }
        self.init(lhs: lhs, plus: rhs)
    }

    @objc(init:minus:)
    convenience init(lhs: Subexpression?, minus rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (-)")
            return
        }
        self.init(lhs: lhs, minus: rhs)
    }

    @objc(init:times:)
    convenience init(lhs: Subexpression?, times rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (*)")
            return
        }
        self.init(lhs: lhs, times: rhs)
    }

    @objc(init:dividedBy:)
    convenience init(lhs: Subexpression?, dividedBy rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (/)")
            return
        }
        self.init(lhs: lhs, dividedBy: rhs)
    }

    @objc(init:equalTo:)
    convenience init(lhs: Subexpression?, equalTo rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (==)")
            return
        }
        self.init(lhs: lhs, equalTo: rhs)
    }

    @objc(init:notEqualTo:)
    convenience init(lhs: Subexpression?, notEqualTo rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (!=)")
            return
        }
        self.init(lhs: lhs, notEqualTo: rhs)
    }

    @objc(init:lessThan:)
    convenience init(lhs: Subexpression?, lessThan rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (<)")
            return
        }
        self.init(lhs: lhs, lessThan: rhs)
    }

    @objc(init:greaterThan:)
    convenience init(lhs: Subexpression?, greaterThan rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (>)")
            return
        }
        self.init(lhs: lhs, greaterThan: rhs)
    }

    @objc(init:lessThanOrEqual:)
    convenience init(lhs: Subexpression?, lessThanOrEqual rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (<=)")
            return
        }
        self.init(lhs: lhs, lessThanOrEqual: rhs)
    }

    @objc(init:greaterThanOrEqual:)
    convenience init(lhs: Subexpression?, greaterThanOrEqual rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (>=)")
            return
        }
        self.init(lhs: lhs, greaterThanOrEqual: rhs)
    }

    @objc(init:logicalAnd:)
    convenience init(lhs: Subexpression?, logicalAnd rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (&&)")
            return
        }
        self.init(lhs: lhs, logicalAnd: rhs)
    }

    @objc(init:logicalOr:)
    convenience init(lhs: Subexpression?, logicalOr rhs: Subexpression?) {
        guard let lhs = lhs, let rhs = rhs else {
            self.init(error: "Nil operand in binary operation (||)")
            return
        }
        self.init(lhs: lhs, logicalOr: rhs)
    }

    @objc(initCondition:whenTrue:otherwise:)
    convenience init(condition: Subexpression?, whenTrue: Subexpression?, whenFalse: Subexpression?) {
        guard let condition = condition, let whenTrue = whenTrue, let whenFalse = whenFalse else {
            self.init(error: "Nil operand in ternary operation")
            return
        }
        self.init(condition: condition, whenTrue: whenTrue, whenFalse: whenFalse)
    }

    // MARK: - Error Initializer

    private init(error: String) {
        value = .error(error)
    }

    private struct Context {
        var invocation: String
        var receiver: String?
        var timeout: TimeInterval
        var sideEffectsAllowed: Bool
        var scope: iTermVariableScope
    }

    @objc
    func evaluate(invocation: String,
                  receiver: String?,
                  timeout: TimeInterval,
                  sideEffectsAllowed: Bool,
                  scope: iTermVariableScope,
                  completion: @escaping (iTermOr<NSObject, NSError>) -> ()) {
        let context = Context(invocation: invocation,
                              receiver: receiver,
                              timeout: timeout,
                              sideEffectsAllowed: sideEffectsAllowed,
                              scope: scope)
        execute(context: context, completion: completion)
    }

    @objc var requiresAsyncEvaluation: Bool {
        return value.requiresAsyncEvaluation
    }

    @objc var containsAnyFunctionCall: Bool {
        return value.containsAnyFunctionCall
    }

    @objc var isError: Bool {
        if case .error = value {
            return true
        }
        return false
    }

    @objc func synchronousValue(sideEffectsAllowed: Bool,
                                scope: iTermVariableScope) throws -> NSNumber {
        it_assert(!requiresAsyncEvaluation)
        switch value {
        case let .literal(number):
            return number
        case .stringLiteral:
            throw iTermError("Cannot convert string literal to number")
        case .indirect(let iv):
            guard let value = iv.synchronousValue(scope: scope) else {
                throw iTermError("IndirectValue.synchronousValue returned nil")
            }
            guard let number = value as? NSNumber else {
                throw iTermError("IndirectValue.synchronousValue returned non-NSNumber type \(type(of: value))")
            }
            return number
        case .functionCall:
            throw iTermError("Cannot evaluate function call synchronously")
        case .unaryOperation(operand: let operand, operation: let operation):
            return try operation.execute(operand.synchronousValue(sideEffectsAllowed: sideEffectsAllowed,
                                                              scope: scope).doubleValue)
        case .binaryOperation(lhs: let lhs, operation: let operation, rhs: let rhs):
            // For equality, relational, and logical operators, use type-aware execution
            if operation == .equalTo || operation == .notEqualTo ||
               operation == .lessThan || operation == .greaterThan ||
               operation == .lessThanOrEqual || operation == .greaterThanOrEqual ||
               operation == .logicalAnd || operation == .logicalOr {
                let lhsVal = try lhs.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
                let rhsVal = try rhs.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
                return try operation.executeTyped(lhs: lhsVal, rhs: rhsVal)
            }
            // For arithmetic operators, convert to doubles
            return try operation.execute(
                lhs: lhs.synchronousValue(
                    sideEffectsAllowed: sideEffectsAllowed,
                    scope: scope).doubleValue,
                rhs: rhs.synchronousValue(
                    sideEffectsAllowed: sideEffectsAllowed,
                    scope: scope).doubleValue)
        case .ternaryOperation(lhs: let lhs, operation: _, mid: let mid, rhs: let rhs):
            let cond = try lhs.synchronousValue(sideEffectsAllowed: sideEffectsAllowed, scope: scope).boolValue
            if cond {
                return try mid.synchronousValue(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            } else {
                return try rhs.synchronousValue(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            }
        case .error(let message):
            throw iTermError("Subexpression error: \(message)")
        }
    }

    // Helper method to get Any value (for type-aware comparisons)
    private func synchronousValueAny(sideEffectsAllowed: Bool,
                                     scope: iTermVariableScope) throws -> Any {
        it_assert(!requiresAsyncEvaluation)
        switch value {
        case let .literal(number):
            return number
        case let .stringLiteral(string):
            return string as NSString
        case .indirect(let iv):
            // IndirectValue returns nil for NSNull values, treat nil as NSNull
            if let value = iv.synchronousValue(scope: scope) {
                return value
            } else {
                return NSNull()
            }
        case .functionCall:
            throw iTermError("Cannot evaluate function call synchronously")
        case .unaryOperation(operand: let operand, operation: let operation):
            let val = try operand.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            return try operation.executeTyped(val)
        case .binaryOperation(lhs: let lhs, operation: let operation, rhs: let rhs):
            let lhsVal = try lhs.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            let rhsVal = try rhs.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            return try operation.executeTyped(lhs: lhsVal, rhs: rhsVal)
        case .ternaryOperation(lhs: let lhs, operation: _, mid: let mid, rhs: let rhs):
            // Ternary needs number for condition
            let cond = try lhs.synchronousValue(sideEffectsAllowed: sideEffectsAllowed, scope: scope).boolValue
            if cond {
                return try mid.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            } else {
                return try rhs.synchronousValueAny(sideEffectsAllowed: sideEffectsAllowed, scope: scope)
            }
        case .error(let message):
            throw iTermError("Subexpression error: \(message)")
        }
    }

    private func execute(context: Context, completion: @escaping (iTermOr<NSObject, NSError>) -> ()) {
        switch value {
        case let .literal(number):
            completion(.first(number))
        case let .stringLiteral(string):
            completion(.first(string as NSString))
        case .indirect(let iv):
            iv.evaluate(invocation: context.invocation,
                        receiver: context.receiver,
                        timeout: context.timeout,
                        sideEffectsAllowed: context.sideEffectsAllowed,
                        scope: context.scope) { result in
                result.whenFirst { obj in
                    completion(.first(obj))
                } second: { error in
                    completion(.second(error))
                }
            }
        case let .functionCall(call):
            let evaluator = iTermExpressionEvaluator(
                parsedExpression: iTermParsedExpression(functionCall: call),
                invocation: context.invocation,
                scope: context.scope)
            evaluator.evaluate(withTimeout: context.timeout,
                               sideEffectsAllowed: context.sideEffectsAllowed) { evaluator in
                if let error = evaluator.error {
                    completion(.second(error as NSError))
                } else {
                    // evaluator.value may be nil or NSNull
                    if let value = evaluator.value as? NSObject {
                        // NSNull is a valid value (represents undefined/optional)
                        completion(.first(value))
                    } else {
                        // Function returned nil - treat as NSNull
                        completion(.first(NSNull()))
                    }
                }
            }
        case .unaryOperation(operand: let operand, operation: let operation):
            operand.execute(context: context) { result in
                result.whenFirst { value in
                    do {
                        let result = try operation.executeTyped(value)
                        completion(.first(result))
                    } catch {
                        completion(.second(error as NSError))
                    }
                } second: { error in
                    completion(.second(error))
                }
            }
        case .binaryOperation(lhs: let lhs, operation: let operation, rhs: let rhs):
            executeBinaryOperation(context: context,
                                   lhs: lhs,
                                   operation: operation,
                                   rhs: rhs,
                                   completion: completion)
        case .ternaryOperation(lhs: let lhs, operation: let operation, mid: let mid, rhs: let rhs):
            executeTernaryOperation(context: context,
                                    lhs: lhs,
                                    operation: operation,
                                    mid: mid,
                                    rhs: rhs,
                                    completion: completion)
        case .error(let message):
            let error = iTermError("Subexpression error: \(message)")
            completion(.second(error as NSError))
        }
    }

    private func executeBinaryOperation(context: Context,
                                        lhs: Subexpression,
                                        operation: BinaryOperation,
                                        rhs: Subexpression,
                                        completion: @escaping (iTermOr<NSObject, NSError>) -> ()) {
        let group = DispatchGroup()
        group.enter()
        var lhsValue: NSObject?
        var rhsValue: NSObject?
        var error: NSError?
        lhs.execute(context: context) { result in
            result.whenFirst { value in
                lhsValue = value
            } second: { err in
                error = err
            }
            group.leave()
        }
        group.enter()
        rhs.execute(context: context) { result in
            result.whenFirst { value in
                rhsValue = value
            } second: { err in
                error = err
            }
            group.leave()
        }
        if let error {
            completion(.second(error as NSError))
        } else if let lhsValue, let rhsValue {
            do {
                let result = try operation.executeTyped(lhs: lhsValue, rhs: rhsValue)
                completion(.first(result))
            } catch {
                completion(.second(iTermError(error, adding: "In \(context.invocation)") as NSError))
            }
        } else {
            group.notify(queue: .main) {
                if let error {
                    completion(.second(error as NSError))
                } else if let lhsValue, let rhsValue {
                    do {
                        let result = try operation.executeTyped(lhs: lhsValue, rhs: rhsValue)
                        completion(.first(result))
                    } catch {
                        completion(.second(error as NSError))
                    }
                } else {
                    completion(.second(iTermError("Bug: Missing value without error in binary operation. lhs=\(d(lhs)) rhs=\(d(rhs)) int \(context.invocation)") as NSError))
                }
            }
        }
    }

    private func executeTernaryOperation(context: Context,
                                         lhs: Subexpression,
                                         operation: TernaryOperation,
                                         mid: Subexpression,
                                         rhs: Subexpression,
                                         completion: @escaping (iTermOr<NSObject, NSError>) -> ()) {
        switch operation {
        case .conditional:
            executeConditional(context: context,
                               lhs: lhs,
                               operation: operation,
                               mid: mid,
                               rhs: rhs,
                               completion: completion)
        }
    }

    private func executeConditional(context: Context,
                                    lhs: Subexpression,
                                    operation: TernaryOperation,
                                    mid: Subexpression,
                                    rhs: Subexpression,
                                    completion: @escaping (iTermOr<NSObject, NSError>) -> ()) {
        let group = DispatchGroup()
        group.enter()
        var value: NSObject?
        var error: NSError?
        lhs.execute(context: context) { result in
            result.whenFirst { condValue in
                guard let number = condValue as? NSNumber else {
                    error = iTermError("Type mismatch: expected number but got \(type(of: condValue))") as NSError
                    return
                }
                if number.boolValue {
                    group.enter()
                    mid.execute(context: context) { result in
                        result.whenFirst { finalResult in
                            value = finalResult
                        } second: { err in
                            error = err
                        }
                        group.leave()
                    }
                } else {
                    group.enter()
                    rhs.execute(context: context) { result in
                        result.whenFirst { finalResult in
                            value = finalResult
                        } second: { err in
                            error = err
                        }
                        group.leave()
                    }
                }
            } second: { err in
                error = err
            }
            group.leave()
        }
        if let error {
            completion(.second(error as NSError))
        } else if let value {
            completion(.first(value))
        } else {
            group.notify(queue: .main) {
                if let error {
                    completion(.second(error as NSError))
                } else if let value {
                    completion(.first(value))
                } else {
                    completion(.second(iTermError("Bug: Missing value without error in condition of ternary operator. \(context.invocation)") as NSError))
                }
            }
        }
    }
}

func d(_ any: Any?) -> String {
    guard let any else {
        return "(nil)"
    }
    if let nsobject = any as? NSObject {
        return nsobject.description
    }
    if let debugDescribable = any as? CustomDebugStringConvertible {
        return debugDescribable.debugDescription
    }
    return String(describing: any)
}
