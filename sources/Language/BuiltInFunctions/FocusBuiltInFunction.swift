//
//  FocusBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/23.
//

import Foundation

@objc(iTermFocusBuiltInFunction)
class FocusBuiltInFunction: NSObject {

}

extension FocusBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.focus",
                       code: 1,
                       userInfo: [ NSLocalizedDescriptionKey: message])
    }
    
    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "focus",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: "[focus]") {
                parameters, completion in
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: "Missing session_id. This shouldn't happen so please report a bug."))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }
                execute(session: session, completion: completion)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    private static func execute(session: PTYSession, completion: iTermBuiltInFunctionCompletionBlock) {
        // reveal() handles disinterring buried sessions and swapping
        // non-visible workgroup peers into their pane; takeFocus alone
        // would silently no-op for either case (its first responder
        // target isn't in any window). Calling reveal first means
        // "focus" actually focuses the session the caller named,
        // regardless of visibility, which matches the API's promise.
        session.reveal()
        session.takeFocus()
        completion(nil, nil)
    }
}
