//
//  SetStatusBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/12/26.
//

import Foundation

@objc(iTermSetStatusBuiltInFunction)
class SetStatusBuiltInFunction: NSObject {
}

extension SetStatusBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let statusArg = "status"
    private static let textColorArg = "text_color"
    private static let dotColorArg = "dot_color"
    private static let detailArg = "detail"
    private static let backgroundTasksArg = "background_tasks"

    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.set-status",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "set_status",
            arguments: [statusArg: NSString.self,
                      textColorArg: NSString.self,
                       dotColorArg: NSString.self,
                         detailArg: NSString.self,
                backgroundTasksArg: NSNumber.self],
            optionalArguments: Set([statusArg, textColorArg, dotColorArg, detailArg,
                                    backgroundTasksArg]),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: "[set_status]") { parameters, completion in
                DLog("set_status \(parameters)")
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: "Missing session_id"))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }

                let update = VT100TabStatusUpdate()

                if let status = parameters[statusArg] as? String {
                    if status.isEmpty {
                        update.statusPresence = .cleared
                    } else {
                        update.statusPresence = .set
                        update.status = status
                    }
                }

                if let textColorHex = parameters[textColorArg] as? String {
                    if textColorHex.isEmpty {
                        update.statusColorPresence = .cleared
                    } else {
                        var textColor = iTermSRGBColor(r: 0, g: 0, b: 0)
                        guard iTermSRGBColorFromHexString(textColorHex, &textColor) else {
                            completion(nil, error(message: "Invalid text_color (expected #rrggbb)"))
                            return
                        }
                        update.statusColorPresence = .set
                        update.statusColor = textColor
                    }
                }

                if let dotColorHex = parameters[dotColorArg] as? String {
                    if dotColorHex.isEmpty {
                        update.indicatorPresence = .cleared
                    } else {
                        var dotColor = iTermSRGBColor(r: 0, g: 0, b: 0)
                        guard iTermSRGBColorFromHexString(dotColorHex, &dotColor) else {
                            completion(nil, error(message: "Invalid dot_color (expected #rrggbb)"))
                            return
                        }
                        update.indicatorPresence = .set
                        update.indicator = dotColor
                    }
                }

                if let detail = parameters[detailArg] as? String {
                    if detail.isEmpty {
                        update.detailPresence = .cleared
                    } else {
                        update.detailPresence = .set
                        update.detail = detail
                    }
                }

                if let backgroundTasks = parameters[backgroundTasksArg] as? NSNumber {
                    update.backgroundTasksPresence = .set
                    update.backgroundTasks = max(0, backgroundTasks.intValue)
                }

                session.screenSetTabStatus(update)
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")

        // Read-back for the background-task count. cc-status runs once
        // per hook event with no state of its own, and idle_prompt
        // payloads carry no task info; this lets it ask iTerm2 for the
        // count the earlier Stop/SubagentStop events parked here (RAM
        // only), instead of keeping marker files on disk.
        let getBackgroundTasks = iTermBuiltInFunction(
            name: "get_background_task_count",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: "Missing session_id"))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }
                completion(NSNumber(value: session.tabStatus?.backgroundTasks ?? 0), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(getBackgroundTasks, namespace: "iterm2")
    }
}
