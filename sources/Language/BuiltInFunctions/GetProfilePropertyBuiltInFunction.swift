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
    private static let errorDomain = "com.iterm2.get-profile-property"

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
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 errorDomain: errorDomain,
                                                                 completion: completion) else {
                    return
                }
                let key = parameters[keyArgName] as! String
                let value = iTermProfilePreferences.object(forKey: key, inProfile: session.justProfile)
                // A missing key has always answered NSNull: while the method was claimed
                // nonnull, Swift bridged its nil back to Objective-C as NSNull.
                completion(value ?? NSNull(), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
