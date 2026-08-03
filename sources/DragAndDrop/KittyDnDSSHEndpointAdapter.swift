//
//  KittyDnDSSHEndpointAdapter.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Adapts the session's SSHEndpoint (a conductor for an SSH-integration session,
//  or LocalhostEndpoint otherwise) to the controller's KittyDnDEndpoint. The
//  endpoint is resolved lazily on each use because a session's conductor can come
//  and go over its lifetime.
//

import Foundation

@available(macOS 11.0, *)
@MainActor
final class KittyDnDSSHEndpointAdapter: KittyDnDEndpoint {
    private let endpointProvider: () -> SSHEndpoint

    init(endpointProvider: @escaping () -> SSHEndpoint) {
        self.endpointProvider = endpointProvider
    }

    var canMaterializeFiles: Bool {
        // Localhost drops are handled with local file URIs (Tier 1); only a real
        // remote endpoint (a conductor) materializes files on the far host.
        return !(endpointProvider() is LocalhostEndpoint)
    }

    func materializeFile(named name: String, contents: Data) async throws -> String {
        let endpoint = endpointProvider()
        let directory = "\(endpoint.homeDirectory ?? "/tmp")/.iterm2-dnd"
        // Best effort: the directory may already exist.
        try? await endpoint.mkdir(directory)
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        let path = "\(directory)/\(UUID().uuidString)-\(safeName)"
        try await endpoint.create(path, content: contents)
        return path
    }
}
