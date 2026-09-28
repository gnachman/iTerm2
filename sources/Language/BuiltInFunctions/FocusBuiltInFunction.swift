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
    private static let errorDomain = "com.iterm2.focus"

    private static func error(message: String) -> NSError {
        return NSError(domain: errorDomain,
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
            // Localization unneeded
            sideEffectsPlaceholder: "[focus]") {
                parameters, completion in
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 errorDomain: errorDomain,
                                                                 completion: completion) else {
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
