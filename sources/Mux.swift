//
//  Mux.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/26/21.
//

import Foundation

@objc(iTermMux)
class Mux: NSObject {
    private let group = DispatchGroup()
    private var count = 0

    @objc
    func add() -> (() -> Void) {
        group.enter()
        var completed = false
        count += 1
        let completion = {
            precondition(!completed)
            completed = true
            self.count -= 1
            self.group.leave()
        }
        return completion
    }

    @objc
    func join(_ block: @escaping () -> Void) {
        if count == 0 {
            // A little optimization - avoid a spin of the runloop if everything completed synchronously.
            block()
            return
        }
        group.notify(queue: .main) {
            block()
        }
    }
}

// MARK:- Convenience methods for interpolated strings.

extension Mux {
    @objc(evaluateInterpolatedString:scope:timeout:success:error:)
    func evaluate(_ interpolatedString: String,
                  scope: iTermVariableScope,
                  timeout: TimeInterval,
                  success successHandler: @escaping (AnyObject?) -> Void,
                  error errorHandler: @escaping (Error) -> Void) {
        let completion = add()
        let evaluator = iTermExpressionEvaluator(interpolatedString: interpolatedString,
                                                 scope: scope)
        evaluator.evaluate(withTimeout: timeout) { evaluator in
            defer {
                completion()
            }
            if let error = evaluator.error {
                errorHandler(error)
            } else {
                successHandler(evaluator.value as AnyObject?)
            }
        }
    }

    @objc(evaluateInterpolatedStrings:scope:timeout:success:error:)
    func evaluate(_ interpolatedStrings: [String],
                  scope: iTermVariableScope,
                  timeout: TimeInterval,
                  success successHandler: @escaping ([AnyObject]) -> Void,
                  error errorHandler: @escaping (Error) -> Void) {
        DLog("Mux \(self) evaluating interpolated strings \(interpolatedStrings) with timeout \(timeout) and scope \(scope)")
        enum Result {
            case pending
            case value(AnyObject?)
            case error(Error)

            var valueObject: AnyObject? {
                switch self {
                case .pending, .error:
                    preconditionFailure()
                case let .value(value):
                    return value
                }
            }
        }
        var lastError: Error?
        var results: [Result] = []
        for (i, string) in interpolatedStrings.enumerated() {
            results.append(.pending)
            evaluate(string, scope: scope, timeout: timeout) { obj in
                DLog("Mux \(self) evaluated \(string) with result \(obj?.debugDescription ?? "(nil)")")
                results[i] = .value(obj)
            } error: { error in
                DLog("Mux \(self) evaluated \(string) with error \(error)")
                lastError = error
                results[i] = .error(error)
            }
        }
        join {
            if let error = lastError {
                errorHandler(error)
            } else {
                successHandler(results.map { $0.valueObject ?? NSNull() })
            }
        }
    }
}
