//
//  KittyDnDSSHEndpointAdapter.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Reports whether the session's SSHEndpoint is a remote host (an SSH-integration
//  conductor) or localhost. Resolved lazily on each use because a session's
//  conductor can come and go.
//

import Foundation

@available(macOS 11.0, *)
@MainActor
final class KittyDnDSSHEndpointAdapter: KittyDnDEndpoint {
    private let endpointProvider: () -> SSHEndpoint

    init(endpointProvider: @escaping () -> SSHEndpoint) {
        self.endpointProvider = endpointProvider
    }

    var isRemoteHost: Bool {
        // LocalhostEndpoint is the only local endpoint; a conductor is remote.
        return !(endpointProvider() is LocalhostEndpoint)
    }
}
