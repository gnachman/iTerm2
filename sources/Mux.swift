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
    private struct Task {
        let description: String
    }
    private var tasks = [Task?]()
    @objc var pendingDescriptions: [String] {
        return tasks.compactMap { $0?.description }
    }

    func add(_ description: String) -> (() -> Void) {
        let i = tasks.count
        tasks.append(Task(description: description))
        group.enter()
        var completed = false
        count += 1
        let completion = {
            precondition(!completed)
            completed = true
            self.count -= 1
            self.tasks[i] = nil
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
    @objc(evaluateInterpolatedString:scope:timeout:retryTime:success:error:)
    func evaluate(_ interpolatedString: String,
                  scope: iTermVariableScope,
                  timeout: TimeInterval,
                  retryTime: TimeInterval,
                  success successHandler: @escaping (AnyObject?) -> Void,
                  error errorHandler: @escaping (Error) -> Void) {
        let completion = add(interpolatedString)
        let evaluator = iTermExpressionEvaluator(interpolatedString: interpolatedString,
                                                 scope: scope)
        if retryTime > 0 {
            evaluator.retryUntil = Date().addingTimeInterval(retryTime)
        }
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

    @objc(evaluateInterpolatedStrings:scope:timeout:retryTime:success:error:)
    func evaluate(_ interpolatedStrings: [String],
                  scope: iTermVariableScope,
                  timeout: TimeInterval,
                  retryTime: TimeInterval,
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
                    it_preconditionFailure()
                case let .value(value):
                    return value
                }
            }
        }
        var lastError: Error?
        var results: [Result] = []
        for (i, string) in interpolatedStrings.enumerated() {
            results.append(.pending)
            evaluate(string, scope: scope, timeout: timeout, retryTime: retryTime) { obj in
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
