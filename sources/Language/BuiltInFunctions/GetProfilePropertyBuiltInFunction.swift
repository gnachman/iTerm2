//
//  GetProfilePropertyBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/4/23.
//

import Foundation

@objc(iTermGetProfilePropertyBuiltInFunction)
class GetProfilePropertyBuiltInFunction: NSObject {

}

extension GetProfilePropertyBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.get-profile-property",
                       code: 1,
                       userInfo: [ NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let keyArgName = "key"
        let sessionIDArgName = "session_id"

        let builtInFunction = iTermBuiltInFunction(
            name: "get_profile_property",
            arguments: [keyArgName: NSString.self],
            optionalArguments: Set(),
            defaultValues: [sessionIDArgName: iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let sessionID = parameters[sessionIDArgName] as? String else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.MissingSessionID", defaultValue: "Missing session_id. This shouldn’t happen so please report a bug.", comment: "Error shown when the session_id argument is unexpectedly missing (should not happen)")))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist")))
                    return
                }
                let key = parameters[keyArgName] as! String
                let value = iTermProfilePreferences.object(forKey: key, inProfile: session.justProfile)
                completion(value, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
