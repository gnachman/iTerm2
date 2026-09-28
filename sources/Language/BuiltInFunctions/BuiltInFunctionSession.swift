//
//  BuiltInFunctionSession.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/25/26.
//

import Foundation

/// Where a session-context built-in function looks for the session it was
/// invoked in.
enum BuiltInFunctionSessionLookup {
    /// Sessions in a window, buried sessions and workgroup peer ports.
    case any
    /// Only sessions in a window.
    case inWindow
}

extension iTermBuiltInFunction {
    /// The session a session-context function operates on, or nil after
    /// reporting the failure through `completion`. Every such function
    /// starts with the same two checks, so they live here and cannot drift
    /// in how they answer a missing or unknown session.
    static func session(for parameters: [AnyHashable: Any],
                        key: String = "session_id",
                        errorDomain: String,
                        lookup: BuiltInFunctionSessionLookup = .any,
                        completion: (Any?, Error?) -> Void) -> PTYSession? {
        func error(_ message: String) -> NSError {
            return NSError(domain: errorDomain,
                           code: 1,
                           userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard let sessionID = parameters[key] as? String else {
            completion(nil, error(String(localized: "BuiltInFunction.MissingSessionID", defaultValue: "Missing session_id. This shouldn’t happen so please report a bug.", comment: "Error shown when the session_id argument is unexpectedly missing (should not happen)")))
            return nil
        }
        let session: PTYSession?
        switch lookup {
        case .any:
            session = iTermController.sharedInstance().anySession(withGUID: sessionID)
        case .inWindow:
            session = iTermController.sharedInstance().session(withGUID: sessionID)
        }
        guard let session else {
            completion(nil, error(String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist")))
            return nil
        }
        return session
    }
}
