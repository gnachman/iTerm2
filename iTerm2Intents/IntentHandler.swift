//
//  IntentHandler.swift
//  iTerm2Intents
//
//  Created by George Nachman on 11/16/21.
//

import Intents

class IntentHandler: INExtension, RunShellScriptIntentHandling {
    func handle(intent: RunShellScriptIntent) async -> RunShellScriptIntentResponse {
        return RunShellScriptIntentResponse()
    }
}
