//
//  SwiftyStringWithBackreferencesEvaluator.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/16/21.
//

import Foundation

// Evaluates a swifty string when matches (which can be used as backreferences) are present. Adds
// them as \(matches[0]) and such.
@objc(iTermSwiftyStringWithBackreferencesEvaluator)
class SwiftyStringWithBackreferencesEvaluator: NSObject {
    private var cachedSwiftyString: iTermSwiftyString? = nil
    @objc var expression: String

    @objc(initWithExpression:) init(_ expression: String) {
        self.expression = expression
    }

    @objc func evaluate(additionalContext: [String: AnyObject],
                        scope: iTermVariableScope,
                        owner: iTermObject,
                        completion: @escaping (String?, NSError?) -> ()) {
        let myScope = amendedScope(scope,
                                   owner: owner,
                                   values: additionalContext)
        if cachedSwiftyString?.swiftyString != expression {
            cachedSwiftyString = iTermSwiftyString(string: expression,
                                                   scope: myScope,
                                                   observer: nil)
        }
        cachedSwiftyString!.evaluateSynchronously(false,
                                                  with: myScope) { value, error, missing in
            if let error = error {
                completion(nil, error as NSError)
                return
            }
            completion(value, nil)
        }
    }

    private func amendedScope(_ scope: iTermVariableScope,
                              owner: iTermObject,
                              values: [String: AnyObject]) -> iTermVariableScope {
        let matchesFrame = iTermVariables(context: [], owner: owner)
        let myScope: iTermVariableScope = scope.copy() as! iTermVariableScope
        myScope.add(matchesFrame, toScopeNamed: nil)
        for (key, value) in values {
            myScope.setValue(value, forVariableNamed: key)
        }
        return myScope
    }
}
