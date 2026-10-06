//
//  FloatingPaneBuiltInFunctions.swift
//  iTerm2SharedARC
//
//  Built-in functions that create and arrange floating panes, for the Python API and it2:
//  create_floating_pane, dock_floating_pane, set_floating_pane_frame and raise_floating_pane.
//  Frames are in points in the tab, with the origin at its top left and y increasing downward,
//  as ListSessions reports them.
//

import Foundation

@objc(iTermFloatingPaneBuiltInFunctions)
class FloatingPaneBuiltInFunctions: NSObject {
    private static let errorDomain = "com.iterm2.floating-pane"

    private static func error(_ message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static var notAFloatError: NSError {
        error(String(localized: "FloatingPane.NotAFloatingPane",
                     defaultValue: "The session is not in a floating pane",
                     comment: "Error from a floating pane function called with a session that is not in a floating pane"))
    }

    @objc static func registerBuiltInFunctions() {
        registerCreate()
        registerDock()
        registerSetFrame()
        registerRaise()
    }

    /// The session's tab and float, or nil after reporting the failure through `completion`.
    private static func floatingPane(for parameters: [AnyHashable: Any],
                                     completion: (Any?, Error?) -> Void) -> (PTYSession, PTYTab, iTermFloatingPaneView)? {
        guard let session = iTermBuiltInFunction.session(for: parameters,
                                                         key: "session",
                                                         errorDomain: errorDomain,
                                                         lookup: .inWindow,
                                                         completion: completion) else {
            return nil
        }
        guard let tab = session.delegate as? PTYTab, let pane = tab.floatingPane(for: session) else {
            completion(nil, notAFloatError)
            return nil
        }
        return (session, tab, pane)
    }

    private static func registerCreate() {
        let f = iTermBuiltInFunction(
            name: "create_floating_pane",
            arguments: ["tab_id": NSString.self,
                        "profile": NSString.self],
            optionalArguments: Set(["profile"]),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[create_floating_pane]") { parameters, completion in
                guard let tabID = parameters["tab_id"] as? String,
                      let tab = iTermController.sharedInstance().tab(withID: tabID),
                      let terminal = tab.realParentWindow() as? PseudoTerminal else {
                    completion(nil, error(String(localized: "FloatingPane.NoSuchTab",
                                                 defaultValue: "No such tab",
                                                 comment: "Error from create_floating_pane when the tab ID does not identify a tab")))
                    return
                }
                if tab.isTmuxTab || terminal.layoutLocked || terminal.inInstantReplay() {
                    completion(nil, error(String(localized: "FloatingPane.CannotCreate",
                                                 defaultValue: "Can’t add a floating pane to this tab now",
                                                 comment: "Error from create_floating_pane when the tab is a tmux tab, its window’s layout is locked, or it is in instant replay")))
                    return
                }
                let profile: [AnyHashable: Any]?
                if let name = parameters["profile"] as? String {
                    profile = ProfileModel.sharedInstance().bookmark(withName: name)
                } else {
                    profile = ProfileModel.sharedInstance().defaultProfile()
                }
                guard let profile else {
                    completion(nil, error(String(localized: "FloatingPane.NoSuchProfile",
                                                 defaultValue: "No such profile",
                                                 comment: "Error from create_floating_pane when the profile name does not identify a profile")))
                    return
                }
                let parent = tab.activeSession
                let create = { (oldCWD: String?) in
                    let session = terminal.addFloatingPane(to: tab,
                                                           profile: profile,
                                                           parentSession: parent,
                                                           oldCWD: oldCWD,
                                                           completion: nil)
                    if let guid = session?.guid {
                        completion(guid, nil)
                    } else {
                        completion(nil, error(String(localized: "FloatingPane.CreateFailed",
                                                     defaultValue: "Failed to create the floating pane",
                                                     comment: "Error from create_floating_pane when the session could not be created")))
                    }
                }
                guard let parent else {
                    create(nil)
                    return
                }
                parent.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(with: (profile as NSDictionary).sshIdentity) { oldCWD in
                    create(oldCWD)
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func registerDock() {
        let f = iTermBuiltInFunction(
            name: "dock_floating_pane",
            arguments: ["session": NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[dock_floating_pane]") { parameters, completion in
                guard let (session, tab, _) = floatingPane(for: parameters, completion: completion) else {
                    return
                }
                guard let terminal = tab.realParentWindow(), terminal.canDockFloating(session) else {
                    completion(nil, error(String(localized: "FloatingPane.CannotDock",
                                                 defaultValue: "Can’t dock this floating pane now",
                                                 comment: "Error from dock_floating_pane when the layout is locked, the tab is a tmux tab, or instant replay is running")))
                    return
                }
                terminal.dockFloating(session)
                completion(NSNull(), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func registerSetFrame() {
        let f = iTermBuiltInFunction(
            name: "set_floating_pane_frame",
            arguments: ["session": NSString.self,
                        "x": NSNumber.self,
                        "y": NSNumber.self,
                        "width": NSNumber.self,
                        "height": NSNumber.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[set_floating_pane_frame]") { parameters, completion in
                guard let (session, tab, pane) = floatingPane(for: parameters, completion: completion) else {
                    return
                }
                guard let x = parameters["x"] as? NSNumber,
                      let y = parameters["y"] as? NSNumber,
                      let width = parameters["width"] as? NSNumber,
                      let height = parameters["height"] as? NSNumber else {
                    completion(nil, error(String(localized: "FloatingPane.InvalidFrame",
                                                 defaultValue: "Invalid frame",
                                                 comment: "Error from set_floating_pane_frame when an argument is missing or not a number")))
                    return
                }
                guard tab.floatingPaneCanResize(pane) else {
                    completion(nil, error(String(localized: "FloatingPane.CannotResize",
                                                 defaultValue: "Can’t move or resize this floating pane now",
                                                 comment: "Error from set_floating_pane_frame when the layout is locked or the float shows instant replay")))
                    return
                }
                // The size is rounded to whole cells, and the frame is kept inside the tab.
                FloatingPaneLayout.fit(pane,
                                       session: session,
                                       toVisualOutlineFrame: NSRect(x: x.doubleValue,
                                                                    y: y.doubleValue,
                                                                    width: width.doubleValue,
                                                                    height: height.doubleValue))
                tab.floatingPanesDidChange()
                completion(NSNull(), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func registerRaise() {
        let f = iTermBuiltInFunction(
            name: "raise_floating_pane",
            arguments: ["session": NSString.self,
                        "to_front": NSNumber.self],
            optionalArguments: Set(["to_front"]),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[raise_floating_pane]") { parameters, completion in
                guard let (_, tab, pane) = floatingPane(for: parameters, completion: completion) else {
                    return
                }
                if (parameters["to_front"] as? NSNumber)?.boolValue ?? true {
                    tab.bringFloatingPane(toFront: pane)
                } else {
                    tab.sendFloatingPane(toBack: pane)
                }
                completion(NSNull(), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }
}
