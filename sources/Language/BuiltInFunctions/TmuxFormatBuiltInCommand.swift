//
//  TmuxFormatBuiltInCommand.swift
//  iTerm2
//
//  Created by George Nachman on 1/31/25.
//

@objc(iTermTmuxFormatBuiltInFunction)
class TmuxFormatBuiltInFunction: NSObject {}

extension TmuxFormatBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let errorDomain = "com.iterm2.tmux-format"

    private static func error(message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: 1,
                       userInfo: [ NSLocalizedDescriptionKey: message])
    }

    static func register() {
        /// Bind a tmux format string (e.g., `#{T:set-titles-string}` to a user-defined variable (e.g., `user.tmuxTitle`).
        let formatKey = "format"
        let sessionIDKey = "session_id"
        let backingVariableKey = "backing_var"
        let builtInFunction = iTermBuiltInFunction(
            name: "tmux_format",
            arguments: [formatKey: NSString.self,
                     sessionIDKey: NSString.self,
               backingVariableKey: iTermVariableReference<AnyObject>.self],
            optionalArguments: [sessionIDKey],
            defaultValues: [sessionIDKey: iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: nil) {
                parameters, completion in
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 errorDomain: errorDomain,
                                                                 lookup: .inWindow,
                                                                 completion: completion) else {
                    return
                }
                guard let ref = parameters[backingVariableKey] as? iTermVariableReference<AnyObject> else {
                    completion(nil, error(message: String(localized: "TmuxFormat.TypeMismatchBackingVariable", defaultValue: "Type mismatch for \(backingVariableKey). Must be a path reference.", comment: "Error when the backing_var argument is not a path reference")))
                    return
                }
                execute(session: session,
                        format: parameters[formatKey] as? String,
                        ref: ref,
                        completion: completion)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    private static func execute(session: PTYSession,
                                format: String?,
                                ref: iTermVariableReference<AnyObject>,
                                completion: iTermBuiltInFunctionCompletionBlock) {
        guard let format else {
            completion(nil, Self.error(message: String(localized: "TmuxFormat.InvalidFormat", defaultValue: "Invalid format", comment: "Error when the format argument is invalid")))
            return
        }
        do {
            let value = try session.tmuxFormat(format,
                                               reference: ref)
            completion(value, nil)
        } catch {
            completion(nil, error)
        }
    }
}
