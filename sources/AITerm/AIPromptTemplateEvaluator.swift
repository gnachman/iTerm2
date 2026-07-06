//
//  AIPromptTemplateEvaluator.swift
//  iTerm2
//
//  Created by George Nachman on 6/10/25.
//
//  Shared plumbing for the AI prompt templates that are editable in
//  Settings > General > AI > Prompts. Each template is an interpolated
//  string whose feature-specific inputs are exposed as variables in the
//  "ai" scope, e.g. \(ai.prompt) in the Engage AI prompt or \(ai.subject)
//  in the chat icon prompt.
//

import Foundation

enum AIPromptTemplateEvaluator {
    // Frames need an iTermObject owner; prompt templates have no
    // object-scoped methods, so a stub suffices.
    private class ScopeOwner: NSObject, iTermObject {
        func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
        func objectScope() -> iTermVariableScope? { nil }
    }

    // Evaluates `template`, exposing each entry of `variables` as
    // \(ai.<key>). Additional variables (e.g. \(shell)) resolve against
    // `scope` when one is provided. Pass synchronous: false to support
    // templates that call registered functions; the completion then may
    // run after a runloop turn instead of before this returns. A nil
    // result reaches the completion when evaluation fails.
    //
    // Built on iTermExpressionEvaluator, the one-shot primitive, rather
    // than iTermSwiftyString: the latter is the observed live-updating
    // class whose init eagerly re-evaluates, so it would evaluate the
    // template (and run any side effects) more than once per call.
    static func evaluate(_ template: String,
                         variables: [String: String],
                         scope callerScope: iTermVariableScope = iTermVariableScope(),
                         sideEffectsAllowed: Bool = false,
                         synchronous: Bool,
                         completion: @escaping (String?) -> Void) {
        // Work on a copy: addVariables(_:toScopeNamed:) inserts a new
        // frame with no same-name check, so mutating the caller's scope
        // would stack a stale "ai" frame onto it per call. Copying here
        // means no call site (e.g. one passing a session's live scope)
        // can get that wrong.
        let scope = callerScope.copy() as! iTermVariableScope
        let owner = ScopeOwner()
        let frame = iTermVariables(context: [], owner: owner)
        scope.add(frame, toScopeNamed: "ai")
        for (name, value) in variables {
            scope.setValue(value, forVariableNamed: "ai.\(name)")
        }
        let evaluator = iTermExpressionEvaluator(interpolatedString: template,
                                                 scope: scope)
        // 0 = synchronous without RPCs; 30s matches iTermGenericEvaluator's
        // asynchronous evaluation timeout. The evaluator keeps itself alive
        // until the completion runs, but iTermVariables only holds its
        // owner weakly, so keep ours alive explicitly.
        evaluator.evaluate(withTimeout: synchronous ? 0 : 30,
                           sideEffectsAllowed: sideEffectsAllowed) { evaluator in
            if evaluator.value == nil {
                // These templates are user-editable in Settings; a syntax
                // error (e.g. an unclosed interpolation) must be
                // diagnosable, not silently turn the feature off.
                RLog("AI prompt template evaluation failed: \(String(describing: evaluator.error)); template: \(template)")
            }
            withExtendedLifetime(owner) {
                completion(evaluator.value as? String)
            }
        }
    }

    // Synchronous convenience for templates that don't call functions.
    static func evaluateSynchronously(_ template: String,
                                      variables: [String: String]) -> String {
        var resolved = ""
        evaluate(template, variables: variables, synchronous: true) { value in
            resolved = value ?? ""
        }
        return resolved
    }
}
