//
//  AutomaticProfileSwitchingSession.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/13/26.
//

import Foundation

@objc(iTermAutomaticProfileSwitchingSessionDelegate)
protocol AutomaticProfileSwitchingSessionDelegate: AnyObject {
    func automaticProfileSwitchingSessionExpressionNeedEvaluation(_ session: AutomaticProfileSwitchingSession)
}

@objc(iTermAutomaticProfileSwitchingExpressionValueProvider)
protocol AutomaticProfileSwitchingExpressionScoreProvider: AnyObject {
    @objc(scoreForExpression:)
    func score(forExpression expression: String) -> Double
}

@objc(iTermAutomaticProfileSwitchingSession)
class AutomaticProfileSwitchingSession: NSObject, AutomaticProfileSwitchingExpressionScoreProvider {
    private let scope: iTermVariableScope
    private var evaluators = [String: iTermExpressionObserver]()
    @objc weak var delegate: AutomaticProfileSwitchingSessionDelegate?
    private let reloadJoiner = IdempotentOperationJoiner.asyncJoiner(.main)
    private let evaluateJoiner = IdempotentOperationJoiner.asyncJoiner(.main)

    @objc(initWithScope:)
    init(scope: iTermVariableScope) {
        self.scope = scope
        super.init()
        reload()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadAllProfiles(_:)),
                                               name: NSNotification.Name(kReloadAllProfiles),
                                               object: nil)
    }

    @objc private func reloadAllProfiles(_ notification: Notification) {
        reloadJoiner.setNeedsUpdate { [weak self] in
            self?.reload()
        }
    }

    private func reload() {
        for evaluator in evaluators.values {
            evaluator.invalidate()
        }
        evaluators.removeAll()
        let rules = ProfileModel.sharedInstance().bookmarks().flatMap { ($0[KEY_BOUND_HOSTS] as? [String]) ?? [] }
        for string in rules {
            if let rule = iTermRule(string: string),
               let expression = rule.expression {
                evaluators[expression] = iTermExpressionObserver(
                    string: expression,
                    scope: scope,
                    sideEffectsAllowed: true,
                    observer: { [weak self] maybeValue, maybeError in
                        DLog("Expression \(expression) has value \(d(maybeValue)), error \(d(maybeError)) so will reevaluate aps")
                        // The delegate has to be called asynchronously so we have a chance to
                        // compute the values of all our expressions when something changes.
                        // Unfortunately, async calls could cause rapid switching since results
                        // could come in staggered.
                        self?.evaluateJoiner.setNeedsUpdate {
                            if let self {
                                self.delegate?.automaticProfileSwitchingSessionExpressionNeedEvaluation(self)
                            }
                        }
                        return maybeValue
                    })
            }
        }
    }

    func score(forExpression expression: String) -> Double {
        return evaluators[expression]?.evaluationResult as? Double ?? -Double.infinity
    }
}

@objc
extension iTermAutomaticProfileSwitcher {
    @objc(ruleToProfileMap:)
    func ruleToProfileMap(profiles: [NSDictionary]) -> [String: NSDictionary] {
        let tuples: [(String, NSDictionary)] = profiles.lazy.flatMap { profile in
            let rules = (profile[KEY_BOUND_HOSTS] as? [String]) ?? []
            return rules.lazy.map {
                ($0, profile)
            }
        }
        return tuples.reduce(into: [String: NSDictionary]()) { partialResult, tuple in
            partialResult[tuple.0] = tuple.1
        }
    }
}
