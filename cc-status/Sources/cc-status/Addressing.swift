import Foundation

// Deciding which iTerm2 session a hook event belongs to, and phrasing that as it2 arguments.

/// How to tell iTerm2 which session this hook belongs to, phrased as it2 arguments.
struct Address {
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
/// and the lookup is restricted to tmux servers attached over that connection. it2 itself picks
/// the connection from the records the attached iTerm2s published on the tmux server (one per
/// attached client, so a later attacher leaving does not strand the pane on an earlier one), and
/// a reattach from elsewhere or an iTerm2 relaunch does not strand it either. Nothing here needs
/// to know whether it is running locally or remotely.
func resolveAddress(_ environment: [String: String]) -> Address? {
    let termSessionGUID: String? = environment["TERM_SESSION_ID"].flatMap { value in
        // "w0t0p0:D1B2BAE2-3D01-4BB6-9021-27D6CF210957" -- the GUID is everything after the colon.
        value.firstIndex(of: ":").map { String(value[value.index(after: $0)...]) }
    }
    let addressArgs: [String]
    // $TMUX alone decides this. A half-set pair ($TMUX without $TMUX_PANE) still means the process is
    // inside tmux, where TERM_SESSION_ID cannot be trusted, so it must take the guard below and report
    // nothing rather than dropping to the --session branch. The guard rejects it: an empty pane string
    // fails the "%" prefix test.
    let insideTmux = !(environment["TMUX"] ?? "").isEmpty
    if insideTmux {
        let tmux = environment["TMUX"]!
        let tmuxPane = environment["TMUX_PANE"] ?? ""
        guard tmuxAddressLooksWellFormed(tmux: tmux, pane: tmuxPane) else {
            // Inside tmux with an address that does not parse. Report nothing rather than falling back
            // to TERM_SESSION_ID: being in a pane is exactly the case where that variable cannot be
            // trusted. Under control mode it names the gateway, or -- after a detach and reattach --
            // an ordinary session that used to be one, and writing status there paints an unrelated
            // tab. The pane path refuses that fallback deliberately (see TmuxPaneLocator); the
            // --session path has no such protection, so it must not be used from in here.
            return nil
        }
        // "--name=value", like every other option below: a tmux socket path may begin with "-"
        // (tmux -S takes it verbatim, and $TMUX is an ordinary variable a user can clobber), and as a
        // separate argv element that would be read as the next option name -- failing the whole
        // command on every hook event, which is what the "=" form exists to prevent.
        let args = optionArgs("--tmux", tmux) + optionArgs("--tmux-pane", tmuxPane)
        addressArgs = args
    } else if let termSessionGUID {
        addressArgs = optionArgs("--session", termSessionGUID)
    } else {
        // No tmux, no TERM_SESSION_ID: nothing to address.
        return nil
    }

    // Bail only when iTerm2 is genuinely unreachable. it2 connects to a fixed local unix socket with
    // cookie auth (SocketConnection.socketPath()) or, on the far side of ssh integration, through
    // IT2_SOCK. What this guards is Claude Code in tmux on a host reached over plain ssh, where there
    // is neither: without it, every hook event would spawn an it2 that cannot connect and print its
    // error plus our own line. --quiet-if-unresolved does not cover that; it is about unresolved
    // panes, not an unreachable app.
    // Purely a transport question, so nothing about session IDs belongs in it. A TERM_SESSION_ID does
    // not make it2 able to connect: with the Python API preference off there is no socket but every
    // session still has the variable, and the same goes for a stale value left behind after iTerm2
    // quits. Requiring its absence too would leave those cases forking a doomed it2 one to three times
    // per tool call for the whole session, which is what this exists to prevent.
    let it2IsReachable = (environment["IT2_SOCK"] != nil) || localIt2SocketExists(environment)
    if !it2IsReachable {
        return nil
    }

    return Address(args: addressArgs)
}

/// Whether some iTerm2 on this Mac has a local API socket that it2 could plausibly use.
///
/// Outside tmux, it2 connects to the socket of the suite in the pane's IT2_SUITE (default
/// "iTerm2"), so that one socket is checked. Inside tmux, it2 prefers whichever suite the
/// controllers attached to the server have advertised there (see TmuxOwnership in
/// it2cli/Sources/it2core/Transport/SocketConnection.swift), and that may not be the suite the
/// pane inherited. Asking tmux from here would duplicate that reader, so instead any suite with
/// a live socket counts. This is a coarse gate whose only job is to avoid forking a doomed it2 on
/// every hook event; it2 itself makes the precise choice.
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

/// Whether these values will parse as a pane address, checked before handing them to it2.
///
/// it2 rejects a malformed --tmux with a usage error and a nonzero exit. Without this check, one
/// bad $TMUX would make every single hook event print ArgumentParser's error and usage text to
/// stderr and set no status at all -- worse than simply using TERM_SESSION_ID, and a breach of the
/// rule that a status update never disrupts the user's turn. $TMUX is an ordinary environment
/// variable a user can clobber, and tmux itself emits a -1 session id for server-side jobs, so this
/// is not hypothetical.
///
/// This deliberately duplicates TmuxAddress.init in it2cli/Sources/it2core/TmuxAddress.swift, which
/// is the canonical rule and carries the tests; cc-status is top-level code in an executable target
/// and cannot share it. Neither direction of drift is harmless, so keep them in step: stricter
/// here means the caller reports nothing at all for that session (the call site exits rather than
/// falling back to TERM_SESSION_ID, which cannot be trusted from inside a pane), and looser means
/// it2 fails to parse and prints usage on every hook event.
func tmuxAddressLooksWellFormed(tmux: String, pane: String) -> Bool {
    let fields = tmux.split(separator: ",", omittingEmptySubsequences: false)
    guard fields.count >= 3 else {
        return false
    }
    // The socket path is everything before the last two fields: it is a filename and may contain
    // commas.
    let path = fields[0..<(fields.count - 2)].joined(separator: ",")
    guard !path.isEmpty,
          let serverPID = Int32(fields[fields.count - 2]), serverPID > 0,
          let sessionID = Int32(fields[fields.count - 1]), sessionID >= 0 else {
        return false
    }
    guard pane.hasPrefix("%"), let paneNumber = Int32(pane.dropFirst()), paneNumber >= 0 else {
        return false
    }
    return true
}

/// Render an option as argv elements.
///
/// "--name=value" so a value beginning with "-" is not read as the next option name: detail text is
/// arbitrary model output and a bulleted message starts with "-", which as a separate element
/// fails the whole command. The exception is an EMPTY value, which ArgumentParser rejects in the
/// "=" form as a missing value ("--detail=" is an error) -- it has to go as two elements, which is
/// unambiguous anyway since an empty string cannot be mistaken for an option name. cc-status sends
/// an empty --detail deliberately, to clear stale detail on most events.
func optionArgs(_ name: String, _ value: String) -> [String] {
    return value.isEmpty ? [name, value] : ["\(name)=\(value)"]
}
