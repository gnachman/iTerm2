//
//  PasteBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/23.
//

import Cocoa

@objc(iTermPasteBuiltInFunction)
class PasteBuiltInFunction: NSObject {

}

extension PasteBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.paste",
                       code: 1,
                       userInfo: [ NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "paste",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[paste]") { parameters, completion in
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.MissingSessionID", defaultValue: "Missing session_id. This shouldn’t happen so please report a bug.", comment: "Error shown when the session_id argument is unexpectedly missing (should not happen)")))
                    return
                }
                guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist")))
                    return
                }
                session.textview?.paste(nil)
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
