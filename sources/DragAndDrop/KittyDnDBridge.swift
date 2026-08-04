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
import AppKit

/// Supplies session state the bridge needs. Implemented by PTYSession.
@objc(iTermKittyDnDBridgeDataSource)
protocol KittyDnDBridgeDataSource: AnyObject {
    /// The session's current SSH-integration conductor, or nil when the session
    /// is on localhost. Resolved on each use because it can come and go. Only
    /// read on the main thread.
    var kittyDnDConductor: Conductor? { get }

    /// The terminal view a drag-out originates from.
    var kittyDnDView: NSView? { get }
}

@available(macOS 11.0, *)
@objc(iTermKittyDnDBridge)
@MainActor
class KittyDnDBridge: NSObject {
    private let controller: KittyDnDController
    private let dragHost: KittyDnDViewDragHost
    private weak var dataSource: KittyDnDBridgeDataSource?

    /// - Parameters:
    ///   - dataSource: supplies the session's current endpoint and view.
    ///   - report: writes the given bytes back to the pty (i.e. to the program
    ///     running in the terminal), like a terminal report.
    @objc init(dataSource: KittyDnDBridgeDataSource,
               report: @escaping (Data) -> Void) {
        let host = KittyDnDViewDragHost(dataSource: dataSource)
        dragHost = host
        let endpoint = KittyDnDSSHEndpointAdapter(endpointProvider: { [weak dataSource] () -> SSHEndpoint in
            if let conductor = dataSource?.kittyDnDConductor {
                return conductor
            }
            return LocalhostEndpoint.instance
        })
        controller = KittyDnDController(
            ourMachineID: KittyDnDMachineID.localHashed(),
            endpoint: endpoint,
            dragHost: host,
            report: { osc72 in report(Data(osc72.utf8)) })
        super.init()
        self.dataSource = dataSource
        host.controller = controller
    }

    /// Feed one OSC 72 sequence's raw content (everything after "72;").
    @objc func handleInboundSequence(_ content: String) {
        controller.handleInboundSequence(content)
    }

    /// Discard all drag-and-drop state (e.g. when a new shell prompt appears).
    @objc func reset() {
        controller.reset()
    }

    // MARK: - Offer / drag-out (from PTYMouseHandler)

    /// Whether the program has enabled drag offers. PTYMouseHandler checks this
    /// to decide whether a drag gesture should be handed to the program.
    @objc var isOfferingDrags: Bool {
        return controller.isOfferingDrags
    }

    /// Tell the program a drag gesture started, and remember the event so the
    /// native drag can begin from it once the program says go (t=P).
    @objc(noteDragGestureAtCellX:cellY:pixelX:pixelY:event:)
    func noteDragGesture(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int, event: NSEvent) {
        dragHost.pendingEvent = event
        controller.dragGestureDetected(cellX: cellX, cellY: cellY,
                                       pixelX: pixelX, pixelY: pixelY)
    }

    // MARK: - Accept-drop (from PTYTextView)

    /// Whether the program has announced it accepts drops. PTYTextView checks
    /// this to decide whether to route a drag to the program.
    @objc var isAcceptingDrops: Bool {
        return controller.isAcceptingDrops
    }

    @objc(draggingEnteredWithCellX:cellY:pixelX:pixelY:operation:pasteboard:)
    func draggingEntered(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                         operation: Int, pasteboard: NSPasteboard) {
        let mimeTypes = KittyDnDPasteboardDropData(pasteboard: pasteboard).mimeTypes
        controller.dragEntered(cellX: cellX, cellY: cellY, pixelX: pixelX,
                               pixelY: pixelY, operations: operation, mimeTypes: mimeTypes)
    }

    @objc(draggingUpdatedWithCellX:cellY:pixelX:pixelY:operation:)
    func draggingUpdated(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                         operation: Int) {
        controller.dragMoved(cellX: cellX, cellY: cellY, pixelX: pixelX,
                             pixelY: pixelY, operations: operation)
    }

    @objc func draggingExited() {
        controller.dragExited()
    }

    @objc(performDropWithCellX:cellY:pixelX:pixelY:operation:pasteboard:)
    func performDrop(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                     operation: Int, pasteboard: NSPasteboard) {
        let drop = KittyDnDPasteboardDropData(pasteboard: pasteboard)
        controller.performDrop(cellX: cellX, cellY: cellY, pixelX: pixelX,
                               pixelY: pixelY, operations: operation, drop: drop)
    }
}
