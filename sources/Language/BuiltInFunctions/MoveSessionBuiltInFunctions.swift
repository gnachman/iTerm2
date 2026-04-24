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
                    completion(nil, Self.error("Missing session argument"))
                    return
                }
                let windowID = parameters["window_id"] as? String
                let tabIndex = (parameters["tab_index"] as? NSNumber)?.int32Value ?? -1

                let controller = iTermController.sharedInstance()!
                guard let session = controller.session(withGUID: sessionID) else {
                    completion(nil, Self.error("Invalid session ID"))
                    return
                }

                let destWindow: PseudoTerminal
                if let windowID = windowID {
                    guard let term = controller.terminal(withGuid: windowID) else {
                        completion(nil, Self.error("Invalid window ID"))
                        return
                    }
                    destWindow = term
                } else {
                    guard let term = controller.windowForSession(withGUID: sessionID) else {
                        completion(nil, Self.error("Session has no window"))
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
                        completion(nil, Self.error("Failed to move session"))
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
                    completion(nil, Self.error("Missing session argument"))
                    return
                }

                let controller = iTermController.sharedInstance()!
                guard let session = controller.session(withGUID: sessionID) else {
                    completion(nil, Self.error("Invalid session ID"))
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
                        completion(nil, Self.error("Failed to move session to new window"))
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
