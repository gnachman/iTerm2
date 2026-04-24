//
//  ConductorRegistry.swift
//  iTerm2
//
//  Created by George Nachman on 6/10/25.
//

// Tracks framing conductors.
@MainActor
class ConductorRegistry {
    static let instance = ConductorRegistry()
    private(set) var conductors: [SSHIdentity: [WeakBox<Conductor>]] = [:]

    var isEmpty: Bool {
        return conductors.isEmpty
    }

    func addConductor(_ conductor: Conductor, for identity: SSHIdentity) {
        let existing = conductors[identity]?.compactMap { $0.value } ?? []
        if !existing.contains(conductor) {
            conductors[identity] = existing.map { WeakBox($0) } + [WeakBox(conductor)]
        }
        if existing.isEmpty {
            if #available (macOS 11.0, *) {
                NotificationCenter.default.post(name: SSHFilePanel.connectedHostsDidChangeNotification,
                                                object: nil)
            }
        }
    }

    func remove(conductorGUID: String, sshIdentity: SSHIdentity) {
        if conductors[sshIdentity] != nil {
            let existing = conductors[sshIdentity]?.compactMap(\.value) ?? []
            let updated = existing.filter { $0.guid != conductorGUID }
            if updated.isEmpty {
                conductors.removeValue(forKey: sshIdentity)
            } else {
                conductors[sshIdentity] = updated.map { WeakBox($0) }
            }
            if #available (macOS 11.0, *) {
                if updated.count < existing.count {
                    NotificationCenter.default.post(name: SSHFilePanel.connectedHostsDidChangeNotification,
                                                    object: nil)
                }
            }
        }
    }

    subscript (identity: SSHIdentity) -> [Conductor] {
        get {
            return conductors[identity]?.compactMap(\.value) ?? []
        }
    }

    func conductors(for url: URL) -> [Conductor] {
        return conductors.flatMap { (entry) -> [Conductor] in
            let key = entry.key
            if key.hostname != url.host && key.host != url.host {
                return []
            }
            if let user = url.user, let sshUser = key.username, user != sshUser {
                return []
            }
            if let port = url.port,
                port != 0,
               (key.port != Int(port) || key.port == 0 && port == 22) {
                return []
            }
            return entry.value.compactMap { $0.value }
        }
    }
}

@available(macOS 11, *)
extension ConductorRegistry: SSHFilePanelDataSource {
    func remoteFilePanelSSHEndpoints(for identity: SSHIdentity) -> [SSHEndpoint] {
        return self[identity].filter { $0.delegate != nil }
    }

    func remoteFilePanelConnectedHosts() -> [SSHIdentity] {
        return conductors.keys.filter {
            !self[$0].isEmpty
        }
    }

}
