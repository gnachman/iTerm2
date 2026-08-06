//
//  KittyDnDDragHost.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  The drag host performs the actual native OS drag on the program's behalf when
//  the program offers data to be dragged out of the terminal. In production it is
//  implemented by the terminal view (which stands up an NSDraggingSession);
//  faked in tests. The host reports the drag's progress back to the controller,
//  which relays it to the program as t=e events.
//

import Foundation

/// An image to use as the drag thumbnail, pre-sent by the program via t=p at a
/// negative index.
struct KittyDnDDragImage: Equatable {
    /// 24 = RGB, 32 = RGBA, 100 = PNG.
    var format: Int
    var width: Int
    var height: Int
    var data: Data
}

/// Everything the program has offered for a drag, assembled from t=o (MIME types
/// and operations), t=p (per-MIME data and the optional thumbnail), and started
/// by t=P.
struct KittyDnDDragOffer: Equatable {
    /// Offered MIME types, in the 0-based index order used by t=p / t=e.
    var mimeTypes: [String]
    /// Pre-sent data keyed by 0-based MIME index. May be missing entries if the
    /// program defers them to the lazy t=e data-request path.
    var data: [Int: Data]
    /// Allowed operations: 1 copy, 2 move, 3 either.
    var operations: Int
    /// Optional drag thumbnail.
    var image: KittyDnDDragImage?
}

/// The outcome of trying to start a native drag, so the controller can pick the
/// right protocol error code.
enum KittyDnDDragStartResult {
    /// The drag started.
    case started
    /// The gesture is gone (no pending gesture, or the mouse button was already
    /// released): the user let go before the program committed. Maps to EPERM.
    case gestureGone
    /// A genuine environmental failure (no view, no draggable items). Maps to EIO.
    case failed
}

@MainActor
protocol KittyDnDDragHost: AnyObject {
    /// Begin a native OS drag for `offer`, reporting the outcome.
    func beginDrag(_ offer: KittyDnDDragOffer) -> KittyDnDDragStartResult

    /// Cancel an in-progress native drag, if any (best effort).
    func cancelDrag()

    /// Forget any pending drag gesture (a stored past mouse event) that has not
    /// yet turned into a drag, so a later t=P cannot start a phantom drag from it.
    func clearPendingGesture()
}
