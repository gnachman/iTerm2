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

    /// A native drag-out session has begun, so the mouse handler should synthesize
    /// the button-release report (the real mouseUp is swallowed by the drag).
    func kittyDnDDragDidBegin()
}

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

    /// Forget a pending drag gesture that ended without a native drag starting
    /// (the mouse was released), so a later t=P cannot start a phantom drag.
    @objc func clearPendingDragGesture() {
        dragHost.clearPendingGesture()
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
        // Derive the hover MIME list from type presence only; the full pasteboard
        // (file URLs, string, image data) is read lazily at drop time.
        let mimeTypes = KittyDnDPasteboardDropData.mimeTypes(for: pasteboard)
        controller.dragEntered(cellX: cellX, cellY: cellY, pixelX: pixelX,
                               pixelY: pixelY, operations: operation, mimeTypes: mimeTypes)
    }

    @objc(draggingUpdatedWithCellX:cellY:pixelX:pixelY:operation:)
    func draggingUpdated(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                         operation: Int) {
        controller.dragMoved(cellX: cellX, cellY: cellY, pixelX: pixelX,
                             pixelY: pixelY, operations: operation)
    }

    /// The drag operation to report to the OS for a forwarded drag. Once the
    /// program replies (t=m:o) we honor it: none if it rejected (o=0), copy for
    /// o=1, move for o=2. Before it replies we OPTIMISTICALLY report the offered
    /// operation (preferring copy) so a fast drop released before the reply's pty
    /// round trip is accepted rather than sprung back; see
    /// KittyDnDController.osDragOperation. PTYTextView returns this from
    /// draggingEntered/Updated and refuses the drop when it is none.
    @objc var forwardedDragOperation: NSDragOperation {
        switch controller.osDragOperation {
        case 1: return .copy
        case 2: return .move
        default: return []
        }
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
