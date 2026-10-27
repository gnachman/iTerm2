//
//  ProcessInfoProviderKey.swift
//  iTerm2SharedARC
//
//  Which pid a session's processes are known by in the provider -[PTYSession processInfoProvider]
//  returns. The two have to be chosen together: a remote provider keys its processes by pids on
//  the remote host, so asking it about the local ssh's pid misses and the session's job name falls
//  back to the raw deepest foreground job.
//

import Foundation

@objc(iTermProcessInfoProviderKey)
final class ProcessInfoProviderKey: NSObject {
    /// Mirrors -[PTYSession processInfoProvider], branch for branch:
    /// - A framer pane uses its host's provider, which knows it by its pid on that host.
    /// - A tmux pane without a connection of its own uses its gateway's provider: for a remote
    ///   tmux server, keyed by the pane's pid there.
    /// - A session with no framing connection uses the local process cache.
    /// - A session framing its own connection uses that connection's provider, keyed by the
    ///   login shell's pid on the host.
    /// `remotePanePID` is 0 when there is none, as is `framedPID`.
    @objc(pidForFramerPane:tmuxPaneOfGateway:hasConductor:framing:framedPID:remotePanePID:effectivePID:)
    static func pid(framerPane: Bool,
                    tmuxPaneOfGateway: Bool,
                    hasConductor: Bool,
                    framing: Bool,
                    framedPID: pid_t,
                    remotePanePID: pid_t,
                    effectivePID: pid_t) -> pid_t {
        if framerPane {
            return remotePanePID != 0 ? remotePanePID : effectivePID
        }
        if tmuxPaneOfGateway && !hasConductor {
            return remotePanePID != 0 ? remotePanePID : effectivePID
        }
        if !framing {
            return effectivePID
        }
        return framedPID != 0 ? framedPID : effectivePID
    }
}
