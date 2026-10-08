//
//  InterpolateBuiltInFunction.swift
//  iTerm2SharedARC
//
//  iterm2.interpolate(string:) returns its argument. Because a string literal in a
//  function call is an interpolated string, this evaluates an interpolated string
//  in the caller's scope, which the API otherwise can't do. For example, invoked in
//  a session's context:
//
//    iterm2.interpolate(string: "\(session.path) \(session.jobName)")
//
//  it2 session list --format uses it.
//

import Foundation

@objc(iTermInterpolateBuiltInFunction)
class InterpolateBuiltInFunction: NSObject {
}

extension InterpolateBuiltInFunction: iTermBuiltInFunctionProtocol {
    static func register() {
        let stringArg = "string"
        let function = iTermBuiltInFunction(
            name: "interpolate",
            arguments: [stringArg: NSString.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let string = parameters[stringArg] as? String else {
                    completion(nil, NSError(domain: "com.iterm2.interpolate",
                                            code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: String(localized: "Interpolate.MissingArgument", defaultValue: "interpolate requires a string", comment: "Error when the interpolate function's string argument is missing")]))
                    return
                }
                completion(string, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(function, namespace: "iterm2")
    }
}
