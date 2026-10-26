//
//  TmuxPaneInferredHost.swift
//  iTerm2SharedARC
//
//  A tmux Integration pane learns its host only from its own shell, through shell integration,
//  which often isn't loaded there. When the tmux server runs on a host reached through SSH
//  Integration, every pane is on that host, which the connection knows (its identity, and the
//  hostname it discovered there). So a pane whose shell hasn't said otherwise takes the
//  connection's host, and what keys on a session's host (git status, host-based status bar
//  components, badges) works there. The gateway session's own reported host can't stand in: it
//  too has one only when shell integration runs there.
//
//  Without this a pane keeps the default every session starts with, this Mac's name and user
//  (-[PTYSession didFinishInitialization]), so a remote pane reads as local: git status looks for
//  its directory on this Mac and finds nothing.
//
//  The host is only published as the pane's host variables. It is not reported in the pane's
//  history, and it fires no host-changed triggers nor automatic profile switching, which are for
//  hosts a shell actually reports. A host the pane's shell reports always wins. The pane's
//  directory already comes from tmux (#{pane_current_path}, iTermWorkingDirectoryPoller).
//

import Foundation

enum TmuxPaneInferredHost {
    struct Host: Equatable {
        var hostname: String
        var username: String?
    }

    enum Decision: Equatable {
        /// Publish this as the pane's host.
        case publish(Host)
        /// Remove the host published earlier: it no longer applies.
        case clear
        case leave
    }

    /// - Parameters:
    ///   - paneReportedHost: the pane's shell has reported a host.
    ///   - gatewayOnSSHIntegration: tmux runs on a host reached through SSH Integration: the
    ///     gateway's connection is framing and its foreground job there is tmux. A gateway that
    ///     went on from that host (a plain ssh, a container) runs tmux somewhere else.
    ///   - gatewayHost: that connection's host.
    ///   - published: what this published for the pane before, if anything.
    static func decide(paneReportedHost: Bool,
                       gatewayOnSSHIntegration: Bool,
                       gatewayHost: Host?,
                       published: Host?) -> Decision {
        guard !paneReportedHost else {
            // The shell's own report replaced whatever was published.
            return .leave
        }
        guard gatewayOnSSHIntegration, let gatewayHost, !gatewayHost.hostname.isEmpty else {
            return published == nil ? .leave : .clear
        }
        return gatewayHost == published ? .leave : .publish(gatewayHost)
    }
}

extension PTYSession {
    /// Brings the inferred host of this tmux pane up to date. Call when the pane appears, and when
    /// its gateway's host or connection changes.
    @objc func updateInferredTmuxHost() {
        guard isTmuxClient else {
            return
        }
        let gateway = tmuxGateway
        let conductor = gateway?.conductor
        // The name the host gave itself where known; it and the identity's both match the
        // connection (SSHIdentity.matches), which is what reading git state there checks.
        let gatewayHost = conductor.map {
            // $USER there, since ssh may log in as a user from ~/.ssh/config that the identity
            // doesn't name.
            TmuxPaneInferredHost.Host(hostname: $0.discoveredHostname ?? $0.sshIdentity.hostname,
                                      username: $0.sshIdentity.username ?? $0.environmentVariables["USER"])
        }
        let job = gateway?.genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String
        let tmuxRunsThere = conductor?.framing == true && (job.map { ($0 as NSString).lastPathComponent.hasPrefix("tmux") } ?? false)
        let decision = TmuxPaneInferredHost.decide(paneReportedHost: currentHost != nil,
                                                   gatewayOnSSHIntegration: tmuxRunsThere,
                                                   gatewayHost: gatewayHost,
                                                   published: swiftState.inferredTmuxHost)
        switch decision {
        case .leave:
            if currentHost != nil {
                swiftState.inferredTmuxHost = nil
            }
        case .publish(let host):
            DLog("PTYSession[\(guid)]: tmux pane takes its gateway's host \(host.hostname)")
            swiftState.inferredTmuxHost = host
            genericScope.setValuesFrom([iTermVariableKeySessionHostname: host.hostname,
                                        iTermVariableKeySessionUsername: host.username ?? NSNull(),
                                        iTermVariableKeySessionIsLocalhost: NSNumber(value: false)])
        case .clear:
            DLog("PTYSession[\(guid)]: tmux pane's inferred host no longer applies")
            swiftState.inferredTmuxHost = nil
            // Back to the defaults every session starts with.
            genericScope.setValuesFrom([iTermVariableKeySessionHostname: Host.fullyQualifiedDomainName(),
                                        iTermVariableKeySessionUsername: NSUserName(),
                                        iTermVariableKeySessionIsLocalhost: NSNull()])
        }
    }
}
