//
//  MoveSessionBuiltInFunctions.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/11/26.
//

import Foundation

class MoveSessionToNewTabBuiltInFunction: iTermBuiltInFunction {
    @objc static func registerBuiltInFunction() {
        let f = iTermBuiltInFunction(
            name: "move_session_to_new_tab",
            arguments: ["session": NSString.self,
                        "window_id": NSString.self,
                        "tab_index": NSNumber.self],
            optionalArguments: Set(["window_id", "tab_index"]),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[move_session_to_new_tab]") { parameters, completion in
                guard let sessionID = parameters["session"] as? String else {
                    completion(nil, Self.error(String(localized: "MoveSession.MissingSessionArgument", defaultValue: "Missing session argument", comment: "Error when the session argument is missing")))
                    return
                }
                let windowID = parameters["window_id"] as? String
                let tabIndex = (parameters["tab_index"] as? NSNumber)?.int32Value ?? -1

                let controller = iTermController.sharedInstance()!
                guard let session = controller.session(withGUID: sessionID) else {
                    completion(nil, Self.error(String(localized: "MoveSession.InvalidSessionID", defaultValue: "Invalid session ID", comment: "Error when a session ID does not identify a session")))
                    return
                }

                let destWindow: PseudoTerminal
                if let windowID = windowID {
                    guard let term = controller.terminal(withGuid: windowID) else {
                        completion(nil, Self.error(String(localized: "MoveSession.InvalidWindowID", defaultValue: "Invalid window ID", comment: "Error when a window ID does not identify a window")))
                        return
                    }
                    destWindow = term
                } else {
                    guard let term = controller.windowForSession(withGUID: sessionID) else {
                        completion(nil, Self.error(String(localized: "MoveSession.NoWindow", defaultValue: "Session has no window", comment: "Error when a session is not in a window")))
                        return
                    }
                    destWindow = term
                }

                if session.isTmuxClient {
                    // tmux pane moves are asynchronous. Kick it off and
                    // return JSON null so the Python side gets None.
                    _ = MovePaneController.sharedInstance().moveSession(
                        session,
                        toNewTabIn: destWindow,
                        atIndex: tabIndex)
                    completion(NSNull(), nil)
                } else {
                    let tabID = MovePaneController.sharedInstance().moveSession(
                        session,
                        toNewTabIn: destWindow,
                        atIndex: tabIndex)
                    if tabID < 0 {
                        completion(nil, Self.error(String(localized: "MoveSession.MoveFailed", defaultValue: "Failed to move session", comment: "Error when moving a session into a new tab fails")))
                        return
                    }
                    completion(String(tabID), nil)
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func error(_ message: String) -> NSError {
        return NSError(domain: "com.iterm2.move-session-to-new-tab",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}

class MoveSessionToNewWindowBuiltInFunction: iTermBuiltInFunction {
    @objc static func registerBuiltInFunction() {
        let f = iTermBuiltInFunction(
            name: "move_session_to_new_window",
            arguments: ["session": NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[move_session_to_new_window]") { parameters, completion in
                guard let sessionID = parameters["session"] as? String else {
                    completion(nil, Self.error(String(localized: "MoveSession.MissingSessionArgument", defaultValue: "Missing session argument", comment: "Error when the session argument is missing")))
                    return
                }

                let controller = iTermController.sharedInstance()!
                guard let session = controller.session(withGUID: sessionID) else {
                    completion(nil, Self.error(String(localized: "MoveSession.InvalidSessionID", defaultValue: "Invalid session ID", comment: "Error when a session ID does not identify a session")))
                    return
                }

                if session.isTmuxClient {
                    // tmux pane moves are asynchronous. Kick it off and
                    // return JSON null so the Python side gets None.
                    _ = MovePaneController.sharedInstance().moveSession(toNewWindow: session)
                    completion(NSNull(), nil)
                } else {
                    let windowGuid = MovePaneController.sharedInstance().moveSession(toNewWindow: session)
                    if let windowGuid = windowGuid {
                        completion(windowGuid, nil)
                    } else {
                        completion(nil, Self.error(String(localized: "MoveSession.MoveToNewWindowFailed", defaultValue: "Failed to move session to new window", comment: "Error when moving a session into a new window fails")))
                    }
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func error(_ message: String) -> NSError {
        return NSError(domain: "com.iterm2.move-session-to-new-window",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}
