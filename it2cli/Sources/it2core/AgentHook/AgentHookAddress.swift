import Foundation

// Deciding which iTerm2 session a hook event belongs to, and phrasing that as it2 arguments.

/// How to tell iTerm2 which session this hook belongs to, phrased as it2 arguments.
struct AgentHookAddress {
    /// The addressing options to pass to every it2 invocation.
    let args: [String]
}

/// Work out how to tell iTerm2 which session this hook belongs to, and phrase it as it2 arguments.
///
/// Outside tmux, TERM_SESSION_ID ("w0t0p0:D1B2BAE2-...") names the session directly. Inside a tmux
/// control-mode pane it does not: iTerm2 injects that variable only when it forks the job itself,
/// and the tmux server forks the pane, so a pane inherits whatever the server happened to pick up
/// when it started -- usually the control-mode gateway, which iTerm2 buries as soon as tmux opens
/// its windows. Updates sent there are accepted and then invisible.
///
/// $TMUX and $TMUX_PANE are always present in a pane and always describe that pane, and iTerm2 owns
/// the pane-to-session mapping under control mode, so prefer them whenever they exist.
///
/// Plain (non-control-mode) tmux sets them too, and there the lookup always misses, because iTerm2
/// is not driving that server. Nothing is reported in that case and that is deliberate: iTerm2
/// cannot know which tmux window the session is rendering, so attaching a status to it would be a
/// claim about a tab that may be showing something else. TERM_SESSION_ID is NOT used as a stand-in
/// -- inside a pane it names whichever session started the server, which after a detach and
/// reattach is an unrelated live shell.
///
/// The same two variables work on a host reached through iTerm2's ssh integration: the it2 call
/// tunnels back over the conductor, which tells iTerm2 which connection the address arrived on,
/// and the lookup is restricted to tmux servers attached over that connection. Nothing here needs
/// to know whether it is running locally or remotely; `environment` is the hook's, wherever it
/// ran, never this process's.
///
/// A plain shell on such a host has neither tmux nor TERM_SESSION_ID (the variable does not cross
/// ssh). There `originSessionID`, the session the call arrived on as iTerm2 itself recorded it,
/// is the address. It never comes from the hook's own input. A pane address still wins over it:
/// the origin is the session showing the connection, which is not necessarily the pane's tab.
///
/// `inProcess` says the call is already running inside iTerm2 (a remote call through the
/// conductor), so iTerm2 is reachable whatever the environment says. It is separate from the
/// origin because iTerm2 withholds the origin for a call from a tmux pane whose connection's
/// session is a tmux gateway.
func resolveAgentHookAddress(environment: [String: String],
                             originSessionID: String? = nil,
                             inProcess: Bool = false,
                             localSocketExists: ([String: String]) -> Bool = localIt2SocketExists) -> AgentHookAddress? {
    let termSessionGUID: String? = environment["TERM_SESSION_ID"].flatMap { value in
        // "w0t0p0:D1B2BAE2-3D01-4BB6-9021-27D6CF210957" -- the GUID is everything after the colon.
        value.firstIndex(of: ":").map { String(value[value.index(after: $0)...]) }
    }
    let addressArgs: [String]
    // $TMUX alone decides this. A half-set pair ($TMUX without $TMUX_PANE) still means the process is
    // inside tmux, where TERM_SESSION_ID cannot be trusted, so it must take the guard below and report
    // nothing rather than dropping to the --session branch.
    let tmux = environment["TMUX"] ?? ""
    if !tmux.isEmpty {
        let tmuxPane = environment["TMUX_PANE"] ?? ""
        // The same rule the CLI's parser applies, so the address is never handed to it2 in a form
        // it would reject with a usage error on every hook event. $TMUX is an ordinary
        // environment variable a user can clobber, and tmux itself emits a -1 session id for
        // server-side jobs, so this is not hypothetical.
        guard TmuxAddress(tmux: tmux, pane: tmuxPane) != nil else {
            // Inside tmux with an address that does not parse. Report nothing rather than falling back
            // to TERM_SESSION_ID: being in a pane is exactly the case where that variable cannot be
            // trusted. Under control mode it names the gateway, or -- after a detach and reattach --
            // an ordinary session that used to be one, and writing status there paints an unrelated
            // tab. The pane path refuses that fallback deliberately (see TmuxPaneLocator); the
            // --session path has no such protection, so it must not be used from in here.
            return nil
        }
        // "--name=value", like every other option: a tmux socket path may begin with "-" (tmux -S
        // takes it verbatim), and as a separate argv element that would be read as the next
        // option name -- failing the whole command on every hook event.
        addressArgs = shortcutOptionArgs("--tmux", tmux) + shortcutOptionArgs("--tmux-pane", tmuxPane)
    } else if let termSessionGUID {
        addressArgs = shortcutOptionArgs("--session", termSessionGUID)
    } else if let originSessionID, !originSessionID.isEmpty {
        addressArgs = shortcutOptionArgs("--session", originSessionID)
    } else {
        // No tmux, no TERM_SESSION_ID: nothing to address.
        return nil
    }

    // Bail only when iTerm2 is genuinely unreachable. it2 connects to a fixed local unix socket with
    // cookie auth (SocketConnection.socketPath()) or, on the far side of ssh integration, through
    // IT2_SOCK. What this guards is an agent in tmux on a host reached over plain ssh, where there
    // is neither: without it, every hook event would try to connect, fail, and print its error.
    // --quiet-if-unresolved does not cover that; it is about unresolved panes, not an unreachable
    // app. Purely a transport question, so nothing about session IDs belongs in it: with the Python
    // API preference off there is no socket but every session still has TERM_SESSION_ID, and the
    // same goes for a stale value left behind after iTerm2 quits.
    // A call running inside iTerm2, as one with an origin always is, has nothing to reach.
    let it2IsReachable = inProcess
        || (originSessionID.map { !$0.isEmpty } ?? false)
        || (environment["IT2_SOCK"] != nil)
        || localSocketExists(environment)
    if !it2IsReachable {
        return nil
    }

    return AgentHookAddress(args: addressArgs)
}

/// Whether some iTerm2 on this Mac has a local API socket that it2 could plausibly use.
///
/// Outside tmux, it2 connects to the socket of the suite in the pane's IT2_SUITE (default
/// "iTerm2"), so that one socket is checked. Inside tmux, it2 prefers whichever suite the
/// controllers attached to the server have advertised there (see TmuxOwnership), and that may
/// not be the suite the pane inherited, so any suite with a live socket counts. This is a coarse
/// gate whose only job is to avoid a doomed connection attempt on every hook event; the socket
/// path lookup makes the precise choice.
func localIt2SocketExists(_ environment: [String: String]) -> Bool {
    guard let appSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory,
                                                              .userDomainMask,
                                                              true).first else {
        return false
    }
    let fm = FileManager.default
    let suite = environment["IT2_SUITE"] ?? "iTerm2"
    if fm.fileExists(atPath: "\(appSupport)/\(suite)/private/socket") {
        return true
    }
    guard !(environment["TMUX"] ?? "").isEmpty,
          let entries = try? fm.contentsOfDirectory(atPath: appSupport) else {
        return false
    }
    return entries.contains { fm.fileExists(atPath: "\(appSupport)/\($0)/private/socket") }
}
