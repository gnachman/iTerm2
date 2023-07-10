//
//  MoveSessionBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/9/23.
//

import Foundation

class MoveSessionBuiltInFunction: iTermBuiltInFunction {
    @objc static func registerBuiltInFunction() {
        let f = iTermBuiltInFunction(name: "move_session",
                                        arguments: ["session": NSString.self,
                                                    "destination": NSString.self,
                                                    "vertical": NSNumber.self,
                                                    "before": NSNumber.self],
                                        optionalArguments: Set(),
                                        defaultValues: [:],
                                        context: .session) { parameters, completion in
            do {
                guard let session = parameters["session"] as? String,
                      let destination = parameters["destination"] as? String,
                      let vertical = parameters["vertical"] as? Bool,
                      let before = parameters["before"] as? Bool else {
                    completion(nil, NSError(domain: "com.iterm2.move-session",
                                            code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "Invalid argument"]))
                    return
                }
                do {
                    try moveSession(session: session,
                                    destination: destination,
                                    vertical: vertical,
                                    before: before)
                    completion(nil, nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func moveSession(session sourceID: String, destination destinationID: String, vertical: Bool, before: Bool) throws {
        guard let source = iTermController.sharedInstance().session(withGUID: sourceID),
              let destination = iTermController.sharedInstance().session(withGUID: destinationID) else {
            throw NSError(domain: "com.iterm2.move-session",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid session ID"])
        }
        if source.isTmuxClient != destination.isTmuxClient {
            throw NSError(domain: "com.iterm2.move-session",
                          code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "You can't intermingle tmux and non-tmux sessions"])
        }
        if source.isTmuxClient {
            if source.tmuxController !== destination.tmuxController {
                throw NSError(domain: "com.iterm2.move-session",
                              code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "Sessions belong to different tmuxes"])
            }
        }
        guard let sourceTab = source.delegate as? PTYTab, let destinationTab = destination.delegate as? PTYTab else {
            throw NSError(domain: "com.iterm2.move-session",
                          code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Session has no tab"])
        }
        if sourceTab.lockedSession == source || destinationTab.lockedSession == destination {
            throw NSError(domain: "com.iterm2.move-session",
                          code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Can't move locked session"])
        }
        if destinationTab.hasMaximizedPane() {
            destinationTab.unmaximize()
        }
        if sourceTab.hasMaximizedPane() {
            sourceTab.unmaximize()
        }
        let half: SplitSessionHalf = {
            switch (vertical, before) {
            case (false, false):
                return .northHalf
            case (false, true):
                return .southHalf
            case (true, false):
                return .eastHalf
            case (true, true):
                return .westHalf
            }
        }()
        MovePaneController.sharedInstance().movePane(source)
        MovePaneController.sharedInstance().didSelectDestinationSession(destination, half: half)
    }
}
