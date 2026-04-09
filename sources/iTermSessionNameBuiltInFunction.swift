//
//  iTermSessionNameBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

// This is an easy way to get a session name since there isn't an always non-null variable
// equivalent to PTYSession.name
@objc(iTermSessionNameBuiltInFunction)
class SessionNameBuiltInFunction: NSObject, iTermBuiltInFunctionProtocol {
    private static let argSession = "session"
    private static let argName = "name"
    private static let argProfileName = "profileName"

    @objc(registerBuiltInFunction)
    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "session_name",
            arguments: [argSession: NSString.self],
            optionalArguments: Set([argName, argProfileName]),
            defaultValues: [argName: iTermVariableKeySessionName,
                            argProfileName: iTermVariableKeySessionProfileName],
            context: .session,
            sideEffectsPlaceholder: nil) { parameters, completion in
                let name = parameters[argName] as? String
                let profileName = parameters[argProfileName] as? String
                completion(name ?? profileName ?? "Untitled", nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction,
                                                        namespace: "iterm2.private")
    }
}
