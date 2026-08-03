//
//  KittyDnDBridge.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  ObjC-facing entry point that owns the per-session KittyDnDController and wires
//  it to the session. PTYSession creates one lazily on the first OSC 72 sequence
//  and forwards inbound sequences to it; the controller's reports are written
//  back to the pty via the supplied report block.
//
//  This phase wires the inbound (program -> terminal) path, the report path, and
//  the endpoint (so a remote SSH-integration session can materialize dropped
//  files). The AppKit drag adapter (drops onto the window, drags out of it) is
//  wired in a later phase.
//

import Foundation

/// Supplies session state the bridge needs. Implemented by PTYSession.
@objc(iTermKittyDnDBridgeDataSource)
protocol KittyDnDBridgeDataSource: AnyObject {
    /// The session's current SSH-integration conductor, or nil when the session
    /// is on localhost. Resolved on each use because it can come and go. Only
    /// read on the main thread.
    var kittyDnDConductor: Conductor? { get }
}

@available(macOS 11.0, *)
@objc(iTermKittyDnDBridge)
@MainActor
class KittyDnDBridge: NSObject {
    private let controller: KittyDnDController
    private weak var dataSource: KittyDnDBridgeDataSource?

    /// - Parameters:
    ///   - dataSource: supplies the session's current endpoint.
    ///   - report: writes the given bytes back to the pty (i.e. to the program
    ///     running in the terminal), like a terminal report.
    @objc init(dataSource: KittyDnDBridgeDataSource,
               report: @escaping (Data) -> Void) {
        let endpoint = KittyDnDSSHEndpointAdapter(endpointProvider: { [weak dataSource] () -> SSHEndpoint in
            if let conductor = dataSource?.kittyDnDConductor {
                return conductor
            }
            return LocalhostEndpoint.instance
        })
        controller = KittyDnDController(
            ourMachineID: KittyDnDMachineID.localHashed(),
            endpoint: endpoint,
            dragHost: nil,
            report: { osc72 in report(Data(osc72.utf8)) })
        super.init()
        self.dataSource = dataSource
    }

    /// Feed one OSC 72 sequence's raw content (everything after "72;").
    @objc func handleInboundSequence(_ content: String) {
        controller.handleInboundSequence(content)
    }
}
