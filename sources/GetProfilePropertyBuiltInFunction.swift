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
            context: .session) { parameters, completion in
                guard let sessionID = parameters[sessionIDArgName] as? String else {
                    completion(nil, error(message: "Missing session_id. This shouldn't happen so please report a bug."))
                    return
                }
                guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }
                let key = parameters[keyArgName] as! String
                let value = iTermProfilePreferences.object(forKey: key, inProfile: session.profile)
                completion(value, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
