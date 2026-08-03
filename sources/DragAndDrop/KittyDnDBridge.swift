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
//  This phase wires the inbound (program -> terminal) path and the report path.
//  The AppKit drag adapter (drops onto the window, drags out of it) is wired in a
//  later phase.
//

import Foundation

@available(macOS 11.0, *)
@objc(iTermKittyDnDBridge)
@MainActor
class KittyDnDBridge: NSObject {
    private let controller: KittyDnDController

    /// - Parameter report: writes the given bytes back to the pty (i.e. to the
    ///   program running in the terminal), like a terminal report.
    @objc init(report: @escaping (Data) -> Void) {
        let endpoint = KittyDnDSSHEndpointAdapter(endpointProvider: { LocalhostEndpoint.instance })
        controller = KittyDnDController(
            ourMachineID: KittyDnDMachineID.localHashed(),
            endpoint: endpoint,
            dragHost: nil,
            report: { osc72 in report(Data(osc72.utf8)) })
        super.init()
    }

    /// Feed one OSC 72 sequence's raw content (everything after "72;").
    @objc func handleInboundSequence(_ content: String) {
        controller.handleInboundSequence(content)
    }
}
