//
//  TmuxPaneLocator.swift
//  iTerm2SharedARC
//
//  Maps a tmux pane, named the way a process running inside it can name itself, to the PTYSession
//  showing that pane under control mode.
//
//  A process in a tmux pane cannot learn its iTerm2 session ID. TERM_SESSION_ID is injected only
//  when iTerm2 forks the job (PTYSession.m), and a tmux pane is forked by the tmux server, so the
//  value a pane inherits is whatever the server picked up when it started. What a pane always has
//  is $TMUX and $TMUX_PANE:
//
//      TMUX=/private/tmp/tmux-501/default,52533,0
//              socket path              pid   session id
//      TMUX_PANE=%0
//
//  Socket path and pid are only meaningful within one machine: /private/tmp/tmux-501/default is
//  byte-identical on any two Macs sharing a uid, and pids collide freely. So a request also
//  carries an ORIGIN naming the connection it arrived over -- nil for this Mac, otherwise the
//  clientUniqueID of the SSH-integration conductor -- and a controller reports the same for its
//  own gateway. Only controllers with a matching origin are considered, which is what lets a
//  tmux -CC running on a remote host resolve its own panes while a local request can never be
//  captured by a remote server (or the reverse).
//
//  That is a same-connection test, not a same-host one, and it is enough because the controller
//  steers the pane's call onto its own connection: on attach it publishes the conductor's socket
//  path and nonce as a per-client user option on the tmux server, which it2 prefers over the copy
//  the pane inherited (TmuxController's advertiseIT2Client). The most recently attached client
//  whose record is still present and still attached wins. So a
//  reattach from a second ssh connection to the same host, or after an iTerm2 relaunch, arrives
//  over the connection that is showing the pane, and only that controller is asked.
//
//  Socket path and pid locate a connected tmux server; the pane id then identifies the session
//  showing it. The session id is not used: a pane id is unique across the whole server
//  (next_window_pane_id in tmux's window.c), so it adds nothing -- and it is the one field that
//  can be wrong, since $TMUX is baked into a pane's environment at creation and move-window can
//  move the pane to another session afterwards. If no connected server answers, there is nothing to report to and the update is
//  dropped. Non-control-mode tmux always lands there, deliberately: iTerm2 is not driving that
//  server and cannot know which tmux window the session is even rendering, so naming one would be
//  a guess about a tab that may be showing something else entirely.
//

import Foundation

@objc(iTermTmuxPaneLocator)
class TmuxPaneLocator: NSObject {
    // The session displaying the given pane, or nil when no connected tmux server answers to this
    // address.
    //
    // Nil is an ordinary answer, not an error: the server may be detached, the connection may
    // still be coming up, or this may be non-control-mode tmux, which iTerm2 does not drive. The
    // caller reports nothing in every one of those cases, because there is no session that can
    // honestly be said to be showing this pane.
    static func session(socketPath: String,
                        serverPID: pid_t,
                        pane: Int32,
                        origin: String?) -> PTYSession? {
        guard addressIsInRange(socketPath: socketPath, serverPID: serverPID, pane: pane) else {
            RLogOncePerKey("range:\(socketPath),\(serverPID),\(pane)",
                           "TmuxPaneLocator: rejecting out-of-range address pid=\(serverPID) pane=%\(pane) socketPathEmpty=\(socketPath.isEmpty)")
            DLog("TmuxPaneLocator: rejected socketPath=\(socketPath)")
            return nil
        }
        let controllers = TmuxControllerRegistry.sharedInstance().allControllers() ?? []
        // What each controller reported, captured from the same reads the decision used, so the
        // miss diagnostic below cannot disagree with it (see the comment on the locality reads).
        var candidates: [String] = []

        for controller in controllers {
            // Read the locality pair once. Neither is a plain getter: both re-ask the kernel when
            // the answer is unknown, which can issue a syscall and move the retry bookkeeping.
            // Reading either again further down would let the diagnostic disagree with what
            // decide() was given. This runs on the main queue, so the two reads describe the same
            // moment.
            let controllerPID = controller.serverPid
            let controllerSocketPath = controller.serverSocketPath
            let controllerOrigin = controller.serverOriginIdentifier
            let isLocal = controller.serverIsLocal
            let localityKnown = controller.serverLocalityKnown
            candidates.append("[socketPath=\(controllerSocketPath ?? "(nil)") pid=\(controllerPID) sessionID=\(controller.sessionId) local=\(isLocal) localityKnown=\(localityKnown) origin=\(controllerOrigin ?? "(local)")]")
            let matchable = canMatch(controllerPID: controllerPID,
                                     controllerSocketPath: controllerSocketPath,
                                     controllerOrigin: controllerOrigin,
                                     isLocal: isLocal,
                                     requestedPID: serverPID,
                                     requestedSocketPath: socketPath,
                                     requestedOrigin: origin)
            // Only meaningful for a local request: serverIsLocal is a kernel lookup on this Mac,
            // which says nothing about a server on the far side of an ssh connection.
            if origin == nil && !matchable && controllerPID == serverPID && !isLocal {
                // Only shout once locality has actually been determined. serverIsLocal is also NO
                // while the kernel lookup has yet to succeed, which usually resolves within
                // seconds. Logging that loudly would claim pane addressing is broken for a server
                // that starts working shortly after -- and, because this is once-per-key, would
                // consume the slot so a genuine misclassification is never reported at all.
                if localityKnown {
                    RLogOncePerKey("nonlocal-pid-match:\(socketPath),\(serverPID)",
                                   "TmuxPaneLocator: controller for pid \(serverPID) matches the requested server but reports a non-local tmux server, so it cannot be matched. If that session is in fact local, pane addressing will not work for it.")
                } else {
                    DLog("TmuxPaneLocator: locality for pid \(serverPID) not determined yet; waiting for it to settle")
                }
            }
            guard matchable else {
                continue
            }
            // A pane id is unique across the server, so at most one controller opened it and the
            // first holder is the answer. Which tmux session it belongs to never enters into it.
            if let session = controller.session(forWindowPane: pane) {
                return session
            }
        }

        // No connected server answers to this address. That is all a miss means, and there is
        // nothing further to try: a pane can only be placed by the controller driving its server.
        // Partly-connected is not a distinct case -- the controller has simply not finished
        // identifying itself, and the next hook event a moment later will resolve.
        //
        // Two log forms. The retrospective ring is always on and ships in user-submitted debug
        // logs, so what goes there omits the socket path: $TMUX reflects whatever `tmux -S` was
        // given, which is often under $HOME and can carry a user or project name. The full form
        // goes to DLog, which only runs when the user turned debug logging on.
        let address = "pid=\(serverPID) pane=%\(pane)"
        RLogOncePerKey("miss:\(address)",
                       "TmuxPaneLocator: no connected tmux server matches \(address). Dropping the update.")
        DLog("TmuxPaneLocator: socketPath=\(socketPath); candidates: \(candidates.joined(separator: " "))")
        return nil
    }

    /// Whether this controller may be asked if it holds the pane. Split out from the loop so the
    /// rules can be exercised without a live tmux server.
    static func canMatch(controllerPID: pid_t,
                         controllerSocketPath: String?,
                         controllerOrigin: String?,
                         isLocal: Bool,
                         requestedPID: pid_t,
                         requestedSocketPath: String,
                         requestedOrigin: String?) -> Bool {
        // A controller that has not identified itself yet has pid 0 and simply does not match.
        // Nothing special is owed to that state: the caller drops this event and the next one, a
        // moment later, finds the controller ready.
        guard controllerPID != 0, controllerPID == requestedPID else {
            return false
        }
        // Same machine? The two branches establish that differently, and neither subsumes the
        // other.
        if let requestedOrigin {
            // The call arrived over SSH integration. The conductor names one connection on both
            // sides, and the call was routed onto the gateway's connection by the environment the
            // controller advertised on attach (see the file comment), so equality settles it
            // outright. serverIsLocal is deliberately NOT consulted: it asks this Mac's kernel
            // about a pid on another machine, so it is at best meaningless and at worst a false
            // positive on a colliding pid.
            guard controllerOrigin == requestedOrigin else {
                return false
            }
        } else {
            // The call arrived locally, so only a local server can be meant. Both tests are
            // load-bearing. The origin test rejects a controller whose gateway runs over ssh
            // integration, whatever this Mac's kernel says about a colliding pid. serverIsLocal
            // then covers the case the origin cannot see: a gateway reached by PLAIN ssh has no
            // conductor, so it reports a nil origin exactly like a local one, and only the kernel
            // lookup reveals that no local process owns that pid.
            guard controllerOrigin == nil, isLocal else {
                return false
            }
        }
        // Cross-check the socket path when we have it. A pid identifies a running server uniquely,
        // but a stale $TMUX whose pid has since been recycled by a different tmux server would
        // match on pid alone. tmux before 2.2 has no #{socket_path}, so accept a nil.
        if let controllerSocketPath, controllerSocketPath != requestedSocketPath {
            return false
        }
        return true
    }

    // The bounds a pane address must satisfy, split out so they can be tested without a live tmux
    // server. Kept in step with TmuxAddress.init in it2cli/Sources/it2core/TmuxAddress.swift.
    static func addressIsInRange(socketPath: String, serverPID: pid_t, pane: Int32) -> Bool {
        // An empty socket path has to be rejected here too, not just by the CLI parser: the
        // cross-check in canMatch skips controllers whose own path is nil (tmux before 2.2), so an
        // empty path would otherwise still match one of those by pid alone.
        return !socketPath.isEmpty && serverPID > 0 && pane >= 0
    }
}
