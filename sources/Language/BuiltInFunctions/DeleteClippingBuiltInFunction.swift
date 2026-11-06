//
//  DeleteClippingBuiltInFunction.swift
//  iTerm2SharedARC
//

import Foundation

@objc(iTermDeleteClippingBuiltInFunction)
class DeleteClippingBuiltInFunction: NSObject {
    private static let argSession = "session"
    private static let argID = "id"
}

extension DeleteClippingBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let errorDomain = "com.iterm2.delete-clipping"

    private static func error(message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "delete_clipping",
            arguments: [argID: NSString.self],
            optionalArguments: Set(),
            defaultValues: [argSession: iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[delete_clipping]") { parameters, completion in
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 key: argSession,
                                                                 errorDomain: errorDomain,
                                                                 completion: completion) else {
                    return
                }
                guard let identifier = parameters[argID] as? String else {
                    completion(nil, error(message: String(localized: "DeleteClipping.MissingArgument", defaultValue: "Missing required argument", comment: "Error shown when delete_clipping is called without a required argument")))
                    return
                }
                // Mirror add_clipping's routing: a code-review workgroup peer
                // deletes from the leader's clippings, since that's where its
                // own add_clipping calls land.
                let target: PTYSession
                if session.workgroupSessionMode == .codeReview,
                   let leader = session.workgroupInstance?.mainSession {
                    target = leader
                } else {
                    target = session
                }
                guard target.deleteClipping(identifier: identifier) else {
                    completion(nil, error(message: String(localized: "DeleteClipping.NotFound", defaultValue: "No clipping with ID \(identifier)", comment: "Error shown when delete_clipping is given an ID that matches no clipping. The placeholder is the ID.")))
                    return
                }
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
