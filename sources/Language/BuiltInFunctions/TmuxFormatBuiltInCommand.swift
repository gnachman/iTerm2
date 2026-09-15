//
//  TmuxFormatBuiltInCommand.swift
//  iTerm2
//
//  Created by George Nachman on 1/31/25.
//

@objc(iTermTmuxFormatBuiltInFunction)
class TmuxFormatBuiltInFunction: NSObject {}

extension TmuxFormatBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.tmux-format",
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
                guard let sessionID = parameters[sessionIDKey] as? String else {
                    completion(nil, error(message: String(localized: "TmuxFormat.MissingSessionID", defaultValue: "Missing \(sessionIDKey). This shouldn't happen so please report a bug.", comment: "Error when the session_id argument is missing")))
                    return
                }
                guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist")))
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
