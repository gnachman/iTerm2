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
            context: .session) {
                parameters, completion in
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: "Missing session_id. This shouldn't happen so please report a bug."))
                    return
                }
                guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }
                execute(session: session, completion: completion)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    private static func execute(session: PTYSession, completion: iTermBuiltInFunctionCompletionBlock) {
        session.takeFocus()
        completion(nil, nil)
    }
}
