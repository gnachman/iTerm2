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
    private static let sessionIDArg = "session_id"

    private static let socketPathArg = "socket_path"
    private static let serverPIDArg = "server_pid"
    private static let paneArg = "pane"
    private static let originArg = "origin"

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

    private static func missingSessionIDError() -> NSError {
        return error(message: String(localized: "BuiltInFunction.MissingSessionID", defaultValue: "Missing session_id. This shouldn’t happen so please report a bug.", comment: "Error shown when the session_id argument is unexpectedly missing (should not happen)"))
    }

    private static func noSuchSessionError() -> NSError {
        return error(message: String(localized: "BuiltInFunction.NoSuchSession", defaultValue: "No such session", comment: "Error shown when a function is called with a session ID that does not exist"))
    }

    // Turn the status arguments into an update, or explain why they're invalid. Shared by the
    // session-context and app-context setters so the two can't drift: both take exactly the same
    // fields, including the background-task count and the expiration with its fallback.
    private static func makeUpdate(_ parameters: [AnyHashable: Any]) -> Result<VT100TabStatusUpdate, NSError> {
        let update = VT100TabStatusUpdate()
        if let invalid = populate(update,
                                  status: parameters[statusArg] as? String,
                                  textColor: parameters[textColorArg] as? String,
                                  dotColor: parameters[dotColorArg] as? String,
                                  detail: parameters[detailArg] as? String) {
            switch invalid {
            case .textColor:
                return .failure(error(message: String(localized: "SetStatus.InvalidTextColor", defaultValue: "Invalid text_color (expected #rrggbb)", comment: "Error when the text_color argument isn't a valid hex color")))
            case .dotColor:
                return .failure(error(message: String(localized: "SetStatus.InvalidDotColor", defaultValue: "Invalid dot_color (expected #rrggbb)", comment: "Error when the dot_color argument isn't a valid hex color")))
            }
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
                return .failure(error(message: String(localized: "SetStatus.UnknownExpiresOn", defaultValue: "Unknown expires_on “\(expiresOn)”. The only supported value is progress-end.", comment: "Error when the expires_on argument names an event iTerm2 does not know. The placeholder is the value the caller passed.")))
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
                    return .failure(error(message: String(localized: "SetStatus.InvalidThenTextColor", defaultValue: "Invalid then_text_color (expected #rrggbb)", comment: "Error when the then_text_color argument isn't a valid hex color")))
                case .dotColor:
                    return .failure(error(message: String(localized: "SetStatus.InvalidThenDotColor", defaultValue: "Invalid then_dot_color (expected #rrggbb)", comment: "Error when the then_dot_color argument isn't a valid hex color")))
                }
            }
            update.expiresOn = .progressEnd
            update.expirationFallback = fallback
        } else if hasFallbackArgs {
            return .failure(error(message: String(localized: "SetStatus.ThenWithoutExpiresOn", defaultValue: "The then_ arguments only mean something with expires_on, which was not given.", comment: "Error when a caller asks for a replacement status without saying when it should be applied")))
        }

        return .success(update)
    }

    // Resolve a target the way the rest of the API does: "active" is a spelling every other it2
    // command accepts, and anySession(withGUID:) has no case for it, so a plain GUID lookup would
    // fail with "No such session".
    //
    // These are the same two branches as -[iTermAPIHelper sessionForAPIIdentifier:
    // includeBuriedSessions:], inlined rather than delegated. Delegating meant going through
    // +sharedInstanceIfEnabled, which returns nil when the Python API preference is off -- and
    // these functions are reachable without it, from an Invoke Script Function trigger, a status
    // bar component, or any expression evaluation. The alias would then quietly stop working
    // depending on an unrelated setting.
    private static func session(forIdentifier identifier: String) -> PTYSession? {
        guard let controller = iTermController.sharedInstance() else {
            return nil
        }
        if identifier == "active" {
            guard let terminal: PseudoTerminal = controller.currentTerminal else {
                return nil
            }
            return terminal.currentSession()
        }
        return controller.anySession(withGUID: identifier)
    }

    // A tmux gateway is rarely a sensible status target: iTerm2 buries it as soon as tmux opens its
    // windows, so the update usually lands where no window can show it.
    //
    // Reaching here means an explicit request to target that session -- `it2 set-status -s <gateway
    // guid>`, or a trigger or script calling set_status from the gateway session itself. The
    // cc-status hook cannot: inside a pane it addresses the pane, and if $TMUX will not parse it
    // reports nothing rather than falling back to TERM_SESSION_ID, precisely because that names a
    // gateway under control mode.
    //
    // Logged rather than refused: a gateway can be un-buried from Sessions > Buried Sessions, in
    // which case its status really is visible, and an explicit target should not be second-guessed.
    // Budgeted because a trigger can fire this per matching line.
    private static func warnIfTmuxGateway(_ session: PTYSession, functionName: String) {
        guard session.isTmuxGateway else {
            return
        }
        RLogOncePerKey("gateway-status:\(functionName):\(session.guid)",
                       "\(functionName) targeted tmux gateway session \(session.guid); unless it has been un-buried the update will not be visible anywhere. A caller inside a tmux pane should address the pane instead.")
    }

    // JSON has no "absent", so an unset field round-trips as null.
    private static func orNull(_ value: String?) -> Any {
        guard let value else {
            return NSNull()
        }
        return value
    }

    // Clamp and round. iTermSRGBColor components are not guaranteed to sit in 0...1: converting an
    // out-of-gamut Display P3 selection to sRGB can overshoot either end, and xtermParseColorArgument
    // (which feeds the OSC 21337 path) does not bound them either. Truncating -0.05 would print
    // "fffffff4" and 1.05 would print four digits for one channel, yielding a string no hex parser
    // accepts. Rounding also matters for in-range values: a 16-bit OSC color of 0.5 must come back
    // as #80, not #7f, so that a get/set round trip preserves the color.
    // Internal rather than private so ModernTests can pin the clamping and rounding.
    static func hexString(_ color: iTermSRGBColor) -> String {
        func component(_ value: CGFloat) -> Int {
            // Non-finite first: min/max propagate NaN (both comparisons are false), so clamping
            // leaves it NaN and Int() then TRAPS. A component really can be NaN -- OSC 21337 goes
            // through xtermParseColorArgument, whose `(1 << (4 * length)) - 1` overflows to 0 for
            // an 8-digit component, making the division 0/0. Reading a status set that way would
            // otherwise take the app down. NaN is not > 0, so it lands on 0.
            guard value.isFinite else {
                return value > 0 ? 255 : 0
            }
            return Int((min(max(value, 0.0), 1.0) * 255.0).rounded())
        }
        return String(format: "#%02x%02x%02x",
                      component(color.r),
                      component(color.g),
                      component(color.b))
    }

    // The optional status arguments, shared by both setters.
    private static var statusArguments: [String: AnyClass] {
        return [statusArg: NSString.self,
                textColorArg: NSString.self,
                dotColorArg: NSString.self,
                detailArg: NSString.self,
                backgroundTasksArg: NSNumber.self,
                expiresOnArg: NSString.self,
                thenStatusArg: NSString.self,
                thenTextColorArg: NSString.self,
                thenDotColorArg: NSString.self,
                thenDetailArg: NSString.self]
    }

    private static var optionalStatusArguments: Set<String> {
        return Set(statusArguments.keys)
    }

    static func register() {
        registerSetStatus()
        registerGetBackgroundTaskCount()
        registerSetSessionStatus()
        registerGetSessionStatus()
        registerSessionIDForTmuxPane()
    }

    // MARK: - Session context

    // The original, which infers its target from the invoking session. Triggers and existing
    // scripts call this. Programmatic callers should prefer set_session_status, which says what it
    // is aiming at.
    private static func registerSetStatus() {
        let builtInFunction = iTermBuiltInFunction(
            name: "set_status",
            arguments: statusArguments,
            optionalArguments: optionalStatusArguments,
            defaultValues: [sessionIDArg: iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[set_status]") { parameters, completion in
                DLog("set_status \(parameters)")
                guard let sessionID = parameters[sessionIDArg] as? String else {
                    completion(nil, missingSessionIDError())
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, noSuchSessionError())
                    return
                }
                warnIfTmuxGateway(session, functionName: "set_status")
                switch makeUpdate(parameters) {
                case .failure(let err):
                    completion(nil, err)
                case .success(let update):
                    session.screenSetTabStatus(update)
                    completion(nil, nil)
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    // Read-back for the background-task count. cc-status runs once
    // per hook event with no state of its own, and idle_prompt
    // payloads carry no task info; this lets it ask iTerm2 for the
    // count the earlier Stop/SubagentStop events parked here (RAM
    // only), instead of keeping marker files on disk.
    private static func registerGetBackgroundTaskCount() {
        let getBackgroundTasks = iTermBuiltInFunction(
            name: "get_background_task_count",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: [sessionIDArg: iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let sessionID = parameters[sessionIDArg] as? String else {
                    completion(nil, missingSessionIDError())
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, noSuchSessionError())
                    return
                }
                completion(NSNumber(value: session.tabStatus?.backgroundTasks ?? 0), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(getBackgroundTasks, namespace: "iterm2")
    }

    // MARK: - App context
    //
    // These name their target explicitly. A process running in a tmux pane has no way to learn its
    // iTerm2 session ID (see TmuxPaneLocator), so it resolves one with session_id_for_tmux_pane and
    // passes it here; there is no session to route a session-context invocation through.

    private static func registerSetSessionStatus() {
        var arguments = statusArguments
        arguments[sessionIDArg] = NSString.self
        let builtInFunction = iTermBuiltInFunction(
            name: "set_session_status",
            arguments: arguments,
            optionalArguments: optionalStatusArguments,
            defaultValues: [:],
            context: .app,
            // Localization unneeded
            sideEffectsPlaceholder: "[set_session_status]") { parameters, completion in
                DLog("set_session_status \(parameters)")
                guard let sessionID = parameters[sessionIDArg] as? String else {
                    completion(nil, missingSessionIDError())
                    return
                }
                guard let session = session(forIdentifier: sessionID) else {
                    completion(nil, noSuchSessionError())
                    return
                }
                warnIfTmuxGateway(session, functionName: "set_session_status")
                switch makeUpdate(parameters) {
                case .failure(let err):
                    completion(nil, err)
                case .success(let update):
                    session.screenSetTabStatus(update)
                    completion(nil, nil)
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    // Returns the accumulated status as a dictionary keyed the same way set_session_status takes
    // its arguments, so a read and a write are obviously symmetric. Unset fields are null rather
    // than absent, so a caller can tell "explicitly empty" from "key I don't know about". The
    // background-task count is included so a caller addressing a tmux pane can read it back
    // without a second function.
    private static func registerGetSessionStatus() {
        let builtInFunction = iTermBuiltInFunction(
            name: "get_session_status",
            arguments: [sessionIDArg: NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let sessionID = parameters[sessionIDArg] as? String else {
                    completion(nil, missingSessionIDError())
                    return
                }
                guard let session = session(forIdentifier: sessionID) else {
                    completion(nil, noSuchSessionError())
                    return
                }
                let status = session.tabStatus
                completion([statusArg: orNull(status?.statusText),
                            textColorArg: orNull((status?.hasStatusTextColor ?? false) ? hexString(status!.statusTextColor) : nil),
                            dotColorArg: orNull((status?.hasIndicator ?? false) ? hexString(status!.indicatorColor) : nil),
                            detailArg: orNull(status?.detailText),
                            backgroundTasksArg: NSNumber(value: status?.backgroundTasks ?? 0)], nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    // Maps a tmux pane to the session showing it. Arguments are the socket path and pid from $TMUX
    // plus the number from $TMUX_PANE, which is everything a process inside a pane knows about
    // itself, and an origin naming the machine those were collected on.
    //
    // `origin` is empty for this Mac, or the clientUniqueID of the SSH-integration conductor a
    // remote caller arrived over. It exists because the rest of the address is only meaningful
    // within one machine (see TmuxPaneLocator). The it2 command tree fills it in from its own
    // execution context, never from its arguments, so a remote caller cannot name a connection
    // other than its own. A local API client can pass anything, which grants nothing: a client
    // that can call this can already drive every session directly.
    //
    // Returns the empty string when no connected tmux server answers to that address, rather than
    // guessing at a session.
    private static func registerSessionIDForTmuxPane() {
        let builtInFunction = iTermBuiltInFunction(
            name: "session_id_for_tmux_pane",
            arguments: [socketPathArg: NSString.self,
                        serverPIDArg: NSNumber.self,
                        paneArg: NSNumber.self,
                        originArg: NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let socketPath = parameters[socketPathArg] as? String,
                      let serverPID = parameters[serverPIDArg] as? NSNumber,
                      let pane = parameters[paneArg] as? NSNumber,
                      let origin = parameters[originArg] as? String else {
                    completion(nil, error(message: String(localized: "SessionIDForTmuxPane.MissingArgument", defaultValue: "Missing required argument", comment: "Error when a required argument to session_id_for_tmux_pane is absent")))
                    return
                }
                let session = TmuxPaneLocator.session(socketPath: socketPath,
                                                      serverPID: serverPID.int32Value,
                                                      pane: pane.int32Value,
                                                      // Empty means local. Carried as a string
                                                      // rather than an absent argument so the
                                                      // function keeps one signature.
                                                      origin: origin.isEmpty ? nil : origin)
                completion(session?.guid ?? "", nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
