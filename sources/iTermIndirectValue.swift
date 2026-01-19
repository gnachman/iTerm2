//
//  iTermIndirectValue.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/13/26.
//

import Foundation

@objc(iTermIndirectValue)
class IndirectValue: NSObject {
    // A value from a path
    @objc var value: NSObject?

    // Failed to get value early in parsing
    @objc var error: String?
    @objc var path: String?
    @objc var array: NSArray?
    @objc var indexExpression: Subexpression?
    @objc var optional: Bool = false

    @objc(initWithPath:)
    init(path: String) {
        self.path = path
    }

    @objc(initWithValue:path:)
    init(value: NSObject?, path: String?) {
        self.value = value
        self.path = path
    }

    @objc(initWithError:path:)
    init(error: String?, path: String?) {
        self.error = error
        self.path = path
    }

    @objc(initWithArray:indexExpression:)
    init(array: NSArray, indexExpression: Subexpression) {
        self.array = array
        self.indexExpression = indexExpression
    }

    override var description: String {
        if let value {
            return value.description
        }
        if let error {
            return "Error: \(error)"
        }
        if let path {
            return "path=\(path)"
        }
        if let indexExpression {
            return "array dereference at \(indexExpression.description)"
        }
        return "<Missing value>"
    }

    @objc
    var isOptional: Bool {
        return path == "null"
    }

    @objc
    var containsAnyFunctionCall: Bool {
        return indexExpression?.containsAnyFunctionCall ?? false
    }

    @objc
    var requiresAsyncEvaluation: Bool {
        return indexExpression?.requiresAsyncEvaluation ?? false
    }

    func synchronousValue(scope: iTermVariableScope) -> Any? {
        var value: Any?
        evaluate(invocation: "",
                 receiver: nil,
                 timeout: 0,
                 sideEffectsAllowed: false,
                 scope: scope) { result in
            result.whenFirst { obj in
                value = obj
            }
        }
        return value
    }

    @objc
    func evaluate(invocation: String,
                  receiver: String?,
                  timeout: TimeInterval,
                  sideEffectsAllowed: Bool,
                  scope: iTermVariableScope,
                  completion: @escaping (iTermOr<NSObject, NSError>) -> ()) {
        if let value {
            completion(.first(value))
            return
        }
        if let error {
            completion(.second(iTermError(error) as NSError))
            return
        }
        if let path {
            if let result = scope.value(forVariableName: path) as? NSObject {
                // NSNull means undefined variable (per iTermVariableScope.h)
                if result is NSNull {
                    if optional {
                        // Optional expression: return NSNull to represent "no value"
                        completion(.first(NSNull()))
                    } else {
                        // Non-optional expression: error
                        completion(.second(iTermError("Invalid variable reference \(path)") as NSError))
                    }
                } else {
                    completion(.first(result))
                }
            } else {
                if optional {
                    completion(.first(NSNull()))
                } else {
                    completion(.second(iTermError("Invalid variable reference \(path)") as NSError))
                }
            }
            return
        }
        if let indexExpression {
            guard let array else {
                completion(.second(iTermError("Indexing a non-array \(d(value))") as NSError))
                return
            }
            indexExpression.evaluate(invocation: invocation,
                                     receiver: receiver,
                                     timeout: timeout,
                                     sideEffectsAllowed: sideEffectsAllowed,
                                     scope: scope) { result in
                result.whenFirst { value in
                    guard let number = value as? NSNumber else {
                        completion(.second(iTermError("Array index must be a number") as NSError))
                        return
                    }
                    let i = number.intValue
                    if i < 0 || i >= array.count {
                        let errorMsg = "Array index \(i) out of bounds for array of size \(array.count) in \"\(invocation)\"."
                        completion(.second(iTermError(errorMsg) as NSError))
                        return
                    }
                    if let obj = array[i] as? NSObject {
                        completion(.first(obj))
                    } else {
                        completion(.second(iTermError("Non-object found in array at index \(i): \(d(array[i]))") as NSError))
                    }
                } second: { error in
                    completion(.second(error))
                }
            }
            return
        }
        completion(.second(iTermError("Missing value") as NSError))
    }
}
