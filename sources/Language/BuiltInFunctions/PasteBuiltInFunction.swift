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
    private static let errorDomain = "com.iterm2.paste"

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "paste",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[paste]") { parameters, completion in
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 errorDomain: errorDomain,
                                                                 lookup: .inWindow,
                                                                 completion: completion) else {
                    return
                }
                session.textview?.paste(nil)
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
