import ArgumentParser
import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

// MARK: - Tmux pane addressing
//
// A process running in a tmux pane cannot learn its iTerm2 session ID. iTerm2 injects
// TERM_SESSION_ID only when it forks the job itself, and under control mode the tmux server forks
// the pane, so a pane inherits whatever the server picked up when it started -- usually the
// control-mode gateway, which iTerm2 buries the moment tmux opens its windows.
//
// What a pane always has is $TMUX and $TMUX_PANE:
//
//     TMUX=/private/tmp/tmux-501/default,52533,0
//             socket path              pid   session id
//     TMUX_PANE=%0
//
// iTerm2 owns the pane-to-session mapping under control mode, so it can turn those into a session
// ID. All three $TMUX fields matter: the socket path separates servers, the pid catches a server
// that restarted on the same socket, and the session id separates sessions within one server.

/// A tmux pane, named the way a process inside it can name itself.
struct TmuxAddress: Equatable {
    var socketPath: String
    var serverPID: Int32
    var pane: Int32

    /// Parse the values of $TMUX and $TMUX_PANE. Returns nil if either is malformed, which callers
    /// should treat as "not usefully inside tmux" rather than as an error.
    init?(tmux: String, pane paneString: String) {
        guard let (path, pid) = Self.server(inTMUX: tmux) else {
            return nil
        }
        guard paneString.hasPrefix("%"),
              let paneNumber = Int32(paneString.dropFirst()), paneNumber >= 0 else {
            return nil
        }
        socketPath = path
        serverPID = pid
        pane = paneNumber
    }

    /// The server half of $TMUX: its socket path and pid. Nil when the value is not a well-formed
    /// $TMUX. Shared with TmuxOwnership, which needs the socket path without a pane.
    static func server(inTMUX tmux: String) -> (socketPath: String, pid: Int32)? {
        // A socket path is an arbitrary filename and may contain commas, so the path is everything
        // before the LAST two fields rather than everything before the first comma.
        let fields = tmux.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 3 else {
            return nil
        }
        let path = fields[0..<(fields.count - 2)].joined(separator: ",")
        // The session id is parsed but not kept. It is checked because a well-formed $TMUX always
        // has one -- tmux writes -1 for a server-side job with no session -- so it is a cheap
        // sanity check that this really is $TMUX. It is not part of the address: a pane id is
        // unique across the whole server (next_window_pane_id in tmux's window.c), so socket path
        // plus pid plus pane identifies the pane outright. Carrying the session id would only
        // import a field that goes stale, since $TMUX is baked into a pane's environment at
        // creation and move-window can move the pane to another session afterwards.
        guard !path.isEmpty,
              let pid = Int32(fields[fields.count - 2]), pid > 0,
              let sessionID = Int32(fields[fields.count - 1]), sessionID >= 0 else {
            return nil
        }
        _ = sessionID
        return (path, pid)
    }

}

/// The tmux addressing options, for commands that can target a tmux pane instead of a session ID.
/// Mix in with `@OptionGroup`.
struct TmuxPaneOptions: ParsableArguments {
    @Option(name: .long, help: "Value of $TMUX from inside a tmux pane. With --tmux-pane, targets the session showing that pane. An explicit --session takes precedence, but this must still be well formed whenever it is present.")
    var tmux: String?

    @Option(name: .long, help: "Value of $TMUX_PANE, e.g. %0. Requires --tmux.")
    var tmuxPane: String?

    @Flag(name: .long, help: "Exit 0 without a message if the tmux pane can’t be resolved. For callers that run on every event, where a per-event failure would be worse than doing nothing.")
    var quietIfUnresolved = false

    /// What the caller asked for. "Asked and got it wrong" must stay distinguishable from "didn't
    /// ask": the first has to fail rather than quietly retarget, because the active-session default
    /// would put the update on whatever the user happens to be looking at.
    enum Resolution {
        case notRequested
        case malformed
        case address(TmuxAddress)
    }

    /// Why a tmux address could not be turned into a session.
    ///
    /// The two differ in whether anything could be done about it, which is what the exit status
    /// should say. A pane that is not found may be transient (an attach still in flight) or a
    /// misconfiguration, and the caller genuinely failed to do what it was asked. Being on the far
    /// side of SSH integration is neither: no address collected there can ever be used here, so a
    /// per-event caller would fail forever, and reporting it once on stderr is the most that helps.
    enum Unresolved {
        case paneNotFound
        /// iTerm2 was asked and the call itself failed, rather than answering "no such pane".
        /// Most often version skew: an in-place app update swaps the bundle while the old process
        /// keeps running, and `it2` is resolved from the bundle on every hook event, so a new CLI
        /// talks to an app that does not have these functions yet. Also a busy main thread turning
        /// the invoke into a timeout. Both are "cannot resolve right now" from a caller's point of
        /// view, which is what --quiet-if-unresolved is about.
        case lookupFailed(String)

        /// Localization unneeded: it2 is a command-line tool with no bundle or string catalog, and
        /// its whole vocabulary (options, JSON keys, this text) is English.
        var message: String {
            switch self {
            case .paneNotFound:
                return "No session is showing that tmux pane."
            case .lookupFailed(let reason):
                return reason
            }
        }

        /// Whether the command should report failure to its caller.
        ///
        /// Either way the command did not do what it was asked, so by default both exit nonzero
        /// and a calling script can tell. `--quiet-if-unresolved` is how a caller says not to fail
        /// it for this -- which is the per-event caller's business to declare, not ours to assume
        /// on its behalf. Deciding unilaterally that one of these is never a failure would leave
        /// the flag governing only whether a message is printed, and a script reading `$?` would
        /// see success after nothing happened.
        ///
        /// Because this is exactly `!quiet`, the reason is reported by the thrown error or not at
        /// all; there is no quiet-but-reported case.
        func isFailure(quiet: Bool) -> Bool {
            return !quiet
        }
    }

    /// Resolve an explicit `--session` value. Pure, so the rules can be tested without opening a
    /// connection.
    func explicitTarget(_ sessionId: String, allowAll: Bool) throws -> String {
        // Normalize FIRST, then branch. normalizeSessionId strips a "wXtYpZ:" prefix and passes
        // the magic words through untouched, so "w0t0p0:all" fails a raw == "all" test, skips both
        // guards below, and is returned as "all" anyway by the last line -- fanning a set across
        // every session, or silently ignoring a --tmux address that was supposed to refuse it.
        //
        // "active" is passed through deliberately: the built-ins these commands call resolve it
        // the same way iTermAPIHelper always has, which is not the same as the active-session
        // default (that one needs a key window; "active" does not). Resolving it here would
        // quietly narrow it.
        let normalized = APIClient.normalizeSessionId(sessionId)
        if normalized == "all" {
            guard allowAll else {
                throw IT2Error.invalidArgument(
                    "\u{201C}all\u{201D} is not a target for this command; it acts on one session. Name a session ID, or omit --session for the active one.")
            }
            // A tmux pane names exactly one session, so the two cannot both be meant.
            if usesTmuxAddressing {
                throw IT2Error.invalidArgument(
                    "--session all cannot be combined with --tmux: a tmux pane names one session.")
            }
            return "all"
        }
        return normalized
    }

    /// Whether a tmux pane address was requested at all.
    var usesTmuxAddressing: Bool {
        if case .notRequested = resolution {
            return false
        }
        return true
    }

    var resolution: Resolution {
        if tmux == nil && tmuxPane == nil {
            return .notRequested
        }
        guard let tmux, let tmuxPane, let address = TmuxAddress(tmux: tmux, pane: tmuxPane) else {
            return .malformed
        }
        return .address(address)
    }

    /// Reject a malformed pair at parse time, before the command opens a connection or does
    /// anything else. Bad addressing is a usage error, not a target to be guessed at.
    ///
    /// This runs even when the command also got an explicit --session, which takes precedence and
    /// would make these values unused. An option group cannot see its siblings, and the help text
    /// says so rather than pretending otherwise: passing a broken --tmux is a mistake worth
    /// hearing about either way.
    func validate() throws {
        if case .malformed = resolution {
            throw ValidationError(Self.malformedMessage)
        }
    }

    static let malformedMessage = "Could not parse the tmux pane address. --tmux should be the value of $TMUX (\u{201C}<socket path>,<server pid>,<session id>\u{201D}) and --tmux-pane the value of $TMUX_PANE (\u{201C}%0\u{201D}); both are required together."
}

extension APIClient {
    /// The session showing a tmux pane, or nil when nothing is. Nil is a normal outcome: iTerm2 may
    /// not be driving that server, the pane may be gone, or the server identity may not have
    /// arrived yet on a connection that just came up.
    /// `origin` names the machine the address was collected on: empty for this Mac, otherwise the
    /// conductor's clientUniqueID from `IT2Context`. The rest of the address is only meaningful
    /// within one machine, so iTerm2 uses this to pick which tmux servers may answer.
    func sessionIdForTmuxPane(_ address: TmuxAddress, origin: String?) throws -> String? {
        let arguments = ["socket_path: \(jsonString(address.socketPath))",
                         "server_pid: \(address.serverPID)",
                         "pane: \(address.pane)",
                         "origin: \(jsonString(origin ?? ""))"]
        let invoke = ITMInvokeFunctionRequest()
        invoke.app = ITMInvokeFunctionRequest_App()
        invoke.invocation = "iterm2.session_id_for_tmux_pane(\(arguments.joined(separator: ", ")))"

        let request = ITMClientOriginatedMessage()
        request.id_p = nextId()
        request.invokeFunctionRequest = invoke

        let response = try send(request)
        guard response.submessageOneOfCase == .invokeFunctionResponse,
              let invokeResp = response.invokeFunctionResponse else {
            throw IT2Error.apiError("No invoke function response")
        }
        if invokeResp.dispositionOneOfCase == .error {
            let reason = invokeResp.error?.errorReason ?? "unknown"
            throw IT2Error.apiError("Tmux pane lookup failed: \(reason)")
        }
        let guid = trimJSONQuotes(invokeResp.success?.jsonResult)
        return guid.isEmpty ? nil : guid
    }

    /// Resolve the session a command should act on.
    ///
    /// Throws, with the reason, unless the caller passed `--quiet-if-unresolved`. Returns nil when
    /// it did: the command should then stop and exit 0 without doing its work, and without saying
    /// anything, which is what a caller running on every event asked for.
    ///
    /// This is the one place the reporting policy lives. Every tmux-addressable command calls it,
    /// so a change to the policy -- or a new command -- cannot end up with a stale copy of it.
    func resolveTarget(_ sessionId: String?,
                       tmuxOptions: TmuxPaneOptions,
                       allowAll: Bool = false,
                       ctx: IT2Context) throws -> String? {
        let resolved: String?
        do {
            resolved = try resolveSessionId(sessionId,
                                            tmuxOptions: tmuxOptions,
                                            allowAll: allowAll,
                                            origin: ctx.originIdentifier)
        } catch IT2Error.apiError(let reason) where tmuxOptions.usesTmuxAddressing {
            // A failed pane-lookup RPC has to obey the same policy as a miss. Letting it escape
            // meant --quiet-if-unresolved covered only the empty answer, so a per-event caller
            // would report on every event for as long as the condition lasted -- exactly what the
            // flag exists to prevent. Only the lookup is caught: an invalidArgument (a bad
            // --session, say) is a usage error and stays loud regardless.
            return try reportUnresolved(.lookupFailed(reason), tmuxOptions: tmuxOptions, ctx: ctx)
        }
        if let resolved {
            return resolved
        }
        // A remote miss is an ordinary miss now that the lookup actually runs for remote callers:
        // it means no tmux -CC on that same ssh connection is showing the pane, which reads the
        // same way to a user as the local case.
        let unresolved: TmuxPaneOptions.Unresolved = .paneNotFound
        // Two outcomes, not three. Failing is exactly "the caller did not pass
        // --quiet-if-unresolved", so either this throws and runToExitCode prints the reason, or
        // the caller asked to be spared and gets silence. There is deliberately no
        // report-but-succeed path: printing on a caller that opted into quiet is the per-event
        // noise the flag exists to prevent.
        return try reportUnresolved(unresolved, tmuxOptions: tmuxOptions, ctx: ctx)
    }

    /// Apply the reporting policy to a reason the target could not be resolved. Always returns nil
    /// when it returns at all; the return type exists so callers can `return try ...`.
    private func reportUnresolved(_ unresolved: TmuxPaneOptions.Unresolved,
                                  tmuxOptions: TmuxPaneOptions,
                                  ctx: IT2Context) throws -> String? {
        if unresolved.isFailure(quiet: tmuxOptions.quietIfUnresolved) {
            throw IT2Error.targetNotFound(unresolved.message)
        }
        return nil
    }

    /// Resolve the target session for a command that accepts both `--session` and a tmux pane.
    ///
    /// An explicit `--session` wins. Otherwise the tmux pane is resolved by iTerm2. With no tmux
    /// options at all, the usual active-session default applies.
    ///
    /// Returns nil when tmux addressing was requested and produced nothing. Prefer `resolveTarget`,
    /// which owns what a command should then do about it.
    ///
    /// Throws on malformed tmux options rather than falling through to the active session: that
    /// would put an update on whatever the user is currently looking at, which is worse than the
    /// misdelivery this addressing exists to prevent.
    ///
    /// `allowAll` is for the one command that can genuinely act on every session: the server fans
    /// a variable SET out over all of them (iTermAPIHelper -handleSessionScopeVariableRequest:).
    /// Everything else here resolves a single GUID and invokes a per-session built-in, where "all"
    /// would arrive as a GUID that matches nothing.
    func resolveSessionId(_ sessionId: String?,
                          tmuxOptions: TmuxPaneOptions,
                          allowAll: Bool = false,
                          origin: String? = nil) throws -> String? {
        if let sessionId {
            return try tmuxOptions.explicitTarget(sessionId, allowAll: allowAll)
        }
        switch tmuxOptions.resolution {
        case .notRequested:
            return try resolveSessionId(nil)
        case .malformed:
            // Normally unreachable: TmuxPaneOptions.validate() rejects this at parse time. Kept so
            // a caller that builds the options by hand still fails closed rather than retargeting.
            throw IT2Error.invalidArgument(TmuxPaneOptions.malformedMessage)
        case .address(let address):
            // The address is only meaningful on the machine it was collected on: pids collide, and
            // /private/tmp/tmux-<uid>/default is byte-identical across machines sharing a uid. So
            // hand iTerm2 the origin along with it and let the locator restrict the search to
            // servers on that machine. Over SSH integration that is the conductor this invocation
            // arrived on, which resolves a remote `tmux -CC`'s own panes and can never reach a
            // local server; locally it is nil, which can never reach a remote one.
            return try sessionIdForTmuxPane(address, origin: origin)
        }
    }
}
