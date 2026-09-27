//
//  AddClippingBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/26.
//

import Foundation

@objc(iTermAddClippingBuiltInFunction)
class AddClippingBuiltInFunction: NSObject {
    private static let argSession = "session"
    private static let argType = "type"
    private static let argTitle = "title"
    private static let argDetail = "detail"
}

extension AddClippingBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let errorDomain = "com.iterm2.add-clipping"

    private static func error(message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "add_clipping",
            arguments: [argType: NSString.self,
                        argTitle: NSString.self,
                        argDetail: NSString.self],
            optionalArguments: Set(),
            defaultValues: [argSession: iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[add_clipping]") { parameters, completion in
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 key: argSession,
                                                                 errorDomain: errorDomain,
                                                                 completion: completion) else {
                    return
                }
                guard let type = parameters[argType] as? String,
                      let title = parameters[argTitle] as? String,
                      let detail = parameters[argDetail] as? String else {
                    completion(nil, error(message: String(localized: "AddClipping.MissingArgument", defaultValue: "Missing required argument", comment: "Error shown when add_clipping is called without a required argument")))
                    return
                }
                // Code-review-mode workgroup peers send their clippings
                // to the workgroup leader instead of accumulating them
                // on the (often short-lived) review session itself —
                // the leader is where the user is actually working, so
                // their it2 add-clipping call from inside `claude`
                // surfaces alongside their normal terminal history.
                let target: PTYSession
                if session.workgroupSessionMode == .codeReview,
                   let leader = session.workgroupInstance?.mainSession {
                    target = leader
                } else {
                    target = session
                }
                target.addClipping(type: type, title: title, detail: detail)
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
