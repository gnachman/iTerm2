//
//  iTermTmuxClientTracker.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/26.
//

import Foundation

/// Tracks attached tmux clients and determines which iTerm2 instance should respond to OSC queries.
///
/// Multi-client coordination protocol:
/// - If ANY native (non-control-mode) client is attached, control-mode clients do NOT respond
/// - Otherwise, the control-mode client with lexicographically smallest client_name responds
@objc(iTermTmuxClientTracker)
class TmuxClientTracker: NSObject {
    // client_name -> isControlMode (true = control mode, false = native)
    private var attachedClients: [String: Bool] = [:]

    private weak var gateway: TmuxGateway?
    private let sessionID: Int

    // Our own tmux client name (queried from tmux, not the UI-friendly name)
    private let tmuxClientName: String

    /// Returns true if this iTerm2 instance should respond to OSC queries.
    @objc var isResponsibleForQueries: Bool {
        // If any native (non-control-mode) client is attached, don't respond
        if attachedClients.values.contains(false) {
            return false
        }
        // Among control-mode clients, check if we're the first lexicographically
        let controlClients = attachedClients.filter { $0.value }.keys.sorted()
        guard let first = controlClients.first else {
            return false
        }
        return first == tmuxClientName
    }

    @objc init(gateway: TmuxGateway, sessionID: Int, tmuxClientName: String) {
        self.gateway = gateway
        self.sessionID = sessionID
        self.tmuxClientName = tmuxClientName
        super.init()
    }

    /// Initialize state by querying list-clients
    @objc func updateClients(completion: @escaping () -> Void) {
        let command = "list-clients -t '$\(sessionID)' -F '#{client_name}\t#{client_control_mode}'"
        gateway?.sendCommand(command,
                             responseTarget: self,
                             responseSelector: #selector(didListClients(_:completion:)),
                             responseObject: completion as AnyObject,
                             flags: 1)  // kTmuxGatewayCommandShouldTolerateErrors
    }

    @objc private func didListClients(_ result: String, completion: AnyObject) {
        // Parse "client_name\t0" or "client_name\t1" lines
        attachedClients.removeAll()
        result.split(separator: "\n").forEach { line in
            let parts = line.split(separator: "\t")
            if parts.count == 2 {
                let name = String(parts[0])
                let isControlMode = parts[1] == "1"
                attachedClients[name] = isControlMode
            }
        }
        if let completionBlock = completion as? () -> Void {
            completionBlock()
        }
    }

    /// Handle %client-session-changed notification
    /// This can be either a control mode or non-control mode client, so refresh the list
    @objc func handleClientSessionChanged(_ clientName: String) {
        updateClients(completion: {})
    }

    /// Handle %client-detached notification
    @objc func handleClientDetached(_ clientName: String) {
        attachedClients.removeValue(forKey: clientName)
    }
}
