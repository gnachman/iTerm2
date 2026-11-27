//
//  iTermMoveTabToWindowBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/19.
//

import Foundation

// iterm2.move_tab_to_window() moves the calling scope's tab out of its
// window into a new window, and gives the new window's GUID.
@objc(iTermMoveTabToWindowBuiltInFunction)
class iTermMoveTabToWindowBuiltInFunction: NSObject, iTermBuiltInFunctionProtocol {
    @objc(registerBuiltInFunction)
    class func register() {
        let function = iTermBuiltInFunction(
            name: "move_tab_to_window",
            arguments: [:],
            optionalArguments: [],
            defaultValues: ["tab_id": iTermVariableKeyTabID],
            context: .tab,
            sideEffectsPlaceholder: "[move_tab_to_window]") { parameters, completion in
                // The scope's tab ID variable always holds a string.
                self.moveTab(withID: parameters["tab_id"] as? String, completion: completion)
            }
        iTermBuiltInFunctions.sharedInstance().register(function, namespace: "iterm2")
    }

    @objc(moveTabWithID:completion:)
    class func moveTab(withID tabID: String?,
                       completion: @escaping iTermBuiltInFunctionCompletionBlock) {
        let controller = iTermController.sharedInstance()
        let tab = controller?.tab(withID: tabID)
        guard tabID != nil else {
            completion(nil, error(code: 1,
                                  description: String(localized: "MoveTabToWindow.NoSuchTab",
                                                      defaultValue: "No such tab",
                                                      comment: "Error when no tab matches the given tab_id")))
            return
        }

        guard let term = controller?.terminal(with: tab) else {
            completion(nil, error(code: 2,
                                  description: String(localized: "MoveTabToWindow.TabHasNoWindow",
                                                      defaultValue: "Tab has no window",
                                                      comment: "Error when the tab is not in any window")))
            return
        }

        guard let tabs = term.tabs(), tabs.count >= 2 else {
            completion(nil, error(code: 3,
                                  description: String(localized: "MoveTabToWindow.WindowHasOnlyOneTab",
                                                      defaultValue: "Window has only one tab",
                                                      comment: "Error when the window has only one tab so it cannot be moved out")))
            return
        }
        guard let newWindowController = term.it_moveTab(toNewWindow: tab) else {
            completion(nil, error(code: 4,
                                  description: String(localized: "MoveTabToWindow.FailedToCreateWindow",
                                                      defaultValue: "Failed to create new window",
                                                      comment: "Error when creating a new window for the tab fails")))
            return
        }

        completion(newWindowController.terminalGuid, nil)
    }

    private class func error(code: Int, description: String) -> NSError {
        return NSError(domain: "com.iterm2.move-tab-to-window",
                       code: code,
                       userInfo: [NSLocalizedDescriptionKey: description])
    }
}
