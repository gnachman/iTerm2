//
//  iTermSetStatusBarComponentUnreadCountBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/6/19.
//

import Foundation

// iterm2.set_status_bar_component_unread_count(identifier:count:) sets the
// unread count of the status bar components with an identifier, in every
// session.
@objc(iTermSetStatusBarComponentUnreadCountBuiltInFunction)
class iTermSetStatusBarComponentUnreadCountBuiltInFunction: NSObject, iTermBuiltInFunctionProtocol {
    @objc(registerBuiltInFunction)
    class func register() {
        let identifier = "identifier"
        let count = "count"

        let function = iTermBuiltInFunction(
            name: "set_status_bar_component_unread_count",
            arguments: [identifier: NSString.self,
                        count: NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: "[set_status_bar_component_unread_count]") { parameters, completion in
                // The registry calls this block only after checking that both
                // arguments are present and have the classes given in
                // `arguments`, so the fallback values are never used.
                self.setCount((parameters[count] as? NSNumber)?.intValue ?? 0,
                              forIdentifier: parameters[identifier] as? String ?? "",
                              completion: completion)
            }
        iTermBuiltInFunctions.sharedInstance().register(function, namespace: "iterm2")
    }

    @objc(setCount:forIdentifier:completion:)
    class func setCount(_ count: Int,
                        forIdentifier identifier: String,
                        completion: @escaping iTermBuiltInFunctionCompletionBlock) {
        iTermStatusBarUnreadCountController.sharedInstance().setUnreadCountForComponentWithIdentifier(identifier,
                                                                                                      count: count)
        completion(nil, nil)
    }
}
