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
    private static let expiresOnArg = "expires_on"
    private static let thenStatusArg = "then_status"
    private static let thenTextColorArg = "then_text_color"
    private static let thenDotColorArg = "then_dot_color"
    private static let thenDetailArg = "then_detail"

    // The only expiration reason there is so far. Spelled the same way in the
    // OSC 21337 payload and in it2's --expires-on.
    private static let progressEndReason = "progress-end"

    /// Which color argument could not be parsed. Returned rather than a
    /// message so the caller can name the argument it passed in a complete
    /// localized sentence of its own.
    enum InvalidColorArgument {
        case textColor
        case dotColor
    }

    /// Fills the visible fields of `update` from one set of arguments. The
    /// primary status and the fallback an expiring status hands off to take
    /// exactly the same fields, so they are parsed the same way: an empty
    /// string clears a field and a missing one leaves it alone.
    private static func populate(_ update: VT100TabStatusUpdate,
                                 status: String?,
                                 textColor: String?,
                                 dotColor: String?,
                                 detail: String?) -> InvalidColorArgument? {
        if let status {
            if status.isEmpty {
                update.statusPresence = .cleared
            } else {
                update.statusPresence = .set
                update.status = status
            }
        }

        if let textColor {
            if textColor.isEmpty {
                update.statusColorPresence = .cleared
            } else {
                guard let color = parseColor(textColor) else {
                    return .textColor
                }
                update.statusColorPresence = .set
                update.statusColor = color
            }
        }

        if let dotColor {
            if dotColor.isEmpty {
                update.indicatorPresence = .cleared
            } else {
                guard let color = parseColor(dotColor) else {
                    return .dotColor
                }
                update.indicatorPresence = .set
                update.indicator = color
            }
        }

        if let detail {
            if detail.isEmpty {
                update.detailPresence = .cleared
            } else {
                update.detailPresence = .set
                update.detail = detail
            }
        }

        return nil
    }

    private static func parseColor(_ hex: String) -> iTermSRGBColor? {
        var color = iTermSRGBColor(r: 0, g: 0, b: 0)
        guard iTermSRGBColorFromHexString(hex, &color) else {
            return nil
        }
        return color
    }

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
                backgroundTasksArg: NSNumber.self,
                      expiresOnArg: NSString.self,
                     thenStatusArg: NSString.self,
                  thenTextColorArg: NSString.self,
                   thenDotColorArg: NSString.self,
                     thenDetailArg: NSString.self],
            optionalArguments: Set([statusArg, textColorArg, dotColorArg, detailArg,
                                    backgroundTasksArg, expiresOnArg, thenStatusArg,
                                    thenTextColorArg, thenDotColorArg, thenDetailArg]),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[set_status]") { parameters, completion in
                DLog("set_status \(parameters)")
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.MissingSessionID", defaultValue: "Missing session_id. This shouldn’t happen so please report a bug.", comment: "Error shown when the session_id argument is unexpectedly missing (should not happen)")))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist")))
                    return
                }

                let update = VT100TabStatusUpdate()
                if let invalid = populate(update,
                                          status: parameters[statusArg] as? String,
                                          textColor: parameters[textColorArg] as? String,
                                          dotColor: parameters[dotColorArg] as? String,
                                          detail: parameters[detailArg] as? String) {
                    switch invalid {
                    case .textColor:
                        completion(nil, error(message: String(localized: "SetStatus.InvalidTextColor", defaultValue: "Invalid text_color (expected #rrggbb)", comment: "Error when the text_color argument isn't a valid hex color")))
                    case .dotColor:
                        completion(nil, error(message: String(localized: "SetStatus.InvalidDotColor", defaultValue: "Invalid dot_color (expected #rrggbb)", comment: "Error when the dot_color argument isn't a valid hex color")))
                    }
                    return
                }

                if let backgroundTasks = parameters[backgroundTasksArg] as? NSNumber {
                    update.backgroundTasksPresence = .set
                    update.backgroundTasks = max(0, backgroundTasks.intValue)
                }

                let thenStatus = parameters[thenStatusArg] as? String
                let thenTextColor = parameters[thenTextColorArg] as? String
                let thenDotColor = parameters[thenDotColorArg] as? String
                let thenDetail = parameters[thenDetailArg] as? String
                let hasFallbackArgs = thenStatus != nil || thenTextColor != nil ||
                                      thenDotColor != nil || thenDetail != nil

                if let expiresOn = parameters[expiresOnArg] as? String, !expiresOn.isEmpty {
                    guard expiresOn == progressEndReason else {
                        completion(nil, error(message: String(localized: "SetStatus.UnknownExpiresOn", defaultValue: "Unknown expires_on “\(expiresOn)”. The only supported value is progress-end.", comment: "Error when the expires_on argument names an event iTerm2 does not know. The placeholder is the value the caller passed.")))
                        return
                    }
                    // With no then_ arguments the status simply goes away when
                    // it expires, which is what a caller who only wants to
                    // scope a status to its operation means.
                    let fallback = hasFallbackArgs ? VT100TabStatusUpdate() : VT100TabStatusUpdate.clear
                    if let invalid = populate(fallback,
                                              status: thenStatus,
                                              textColor: thenTextColor,
                                              dotColor: thenDotColor,
                                              detail: thenDetail) {
                        switch invalid {
                        case .textColor:
                            completion(nil, error(message: String(localized: "SetStatus.InvalidThenTextColor", defaultValue: "Invalid then_text_color (expected #rrggbb)", comment: "Error when the then_text_color argument isn't a valid hex color")))
                        case .dotColor:
                            completion(nil, error(message: String(localized: "SetStatus.InvalidThenDotColor", defaultValue: "Invalid then_dot_color (expected #rrggbb)", comment: "Error when the then_dot_color argument isn't a valid hex color")))
                        }
                        return
                    }
                    update.expiresOn = .progressEnd
                    update.expirationFallback = fallback
                } else if hasFallbackArgs {
                    completion(nil, error(message: String(localized: "SetStatus.ThenWithoutExpiresOn", defaultValue: "The then_ arguments only mean something with expires_on, which was not given.", comment: "Error when a caller asks for a replacement status without saying when it should be applied")))
                    return
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
                    completion(nil, error(message: String(localized: "BuiltInFunction.MissingSessionID", defaultValue: "Missing session_id. This shouldn’t happen so please report a bug.", comment: "Error shown when the session_id argument is unexpectedly missing (should not happen)")))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist")))
                    return
                }
                completion(NSNumber(value: session.tabStatus?.backgroundTasks ?? 0), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(getBackgroundTasks, namespace: "iterm2")
    }
}
