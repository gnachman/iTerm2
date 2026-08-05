//
//  KittyDnDController.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  The per-session state machine. It mediates between OSC 72 escape sequences
//  (from the program running in the terminal) and the AppKit drag machinery, and
//  drives the three-tier routing for dropped files. It is @MainActor because it
//  calls the @MainActor SSH endpoint and the main-thread drag machinery.
//
//  This file implements the accept-drop direction (a program accepting a drop
//  onto the terminal window). The offer/start-drag direction is added in a later
//  phase.
//

import Foundation

/// The data available from an in-progress or completed drop, as seen by the
/// controller. The AppKit adapter implements this over NSDraggingInfo; faked in
/// tests. The MIME order defines the 1-based index space used by t=r requests.
@MainActor
protocol KittyDnDDropData: AnyObject {
    var mimeTypes: [String] { get }
    /// Local file URLs for the drop, used for text/uri-list and Tier 2
    /// materialization. Empty for non-file drops.
    var fileURLs: [URL] { get }
    /// The bytes for the given 1-based MIME index, or nil if unavailable.
    func data(forMimeIndex index: Int) -> Data?
}

@MainActor
final class KittyDnDController {
    private let ourMachineID: String
    private let endpoint: KittyDnDEndpoint
    private weak var dragHost: KittyDnDDragHost?
    private let report: (String) -> Void
    private var reassembler = KittyDnDChunkReassembler()
    // The multiplexer routing id from a t=a/t=o registration that set the i key.
    // Once set, every escape code we send carries it so a multiplexer (e.g. tmux)
    // can route our replies back to the right pane. Cleared on reset().
    private var multiplexerID: String?

    // Accept-drop state.
    private(set) var isAcceptingDrops = false
    // The MIME types the program announced it accepts. Currently informational
    // (our drop path sends the pasteboard's full list); exposed for tests.
    private(set) var acceptedMimeTypes: [String] = []
    // The operation the program said it will perform for the current drag, from
    // its t=m:o reply: 0 = not accepted, 1 = copy, 2 = move. nil means it has not
    // replied yet, in which case the drop is not (yet) accepted. Reset when a drag
    // enters or leaves.
    private(set) var acceptedDropOperation: Int?
    private var peerMachineID: String?
    private var currentDrop: KittyDnDDropData?
    // Whether the current drop originated from our own drag-out in this same
    // session. Latched at drop time so deferred over-the-pty reads are still
    // refused after the native drag ends. Security: a program that both offers a
    // drag and accepts drops could otherwise read local files by dropping its own
    // drag onto itself.
    private var currentDropIsSelfDrag = false

    // Open directory handles for the cross-machine traversal, mapping a handle to
    // that directory's ordered child URLs. Handles start at 2 (0 and 1 are
    // reserved by the protocol for the file/symlink type indicators).
    private var directoryHandles: [Int: [URL]] = [:]
    private var nextDirectoryHandle = 2
    // Bumped at every drop-context boundary (new drag cycle, new drop, drop
    // completion, reset). An async filesystem read captures it before awaiting and
    // discards its result if it changed, so a read still in flight when the drop
    // is superseded or completed cannot stream stale data or resurrect a freed
    // directory handle. This makes the "discard queued requests" guarantee real.
    private var acceptGeneration = 0
    // The final operation from the last drop-completion signal (t=r:o=operation):
    // 0 means the drop was canceled, nonzero is the action the program took.
    private(set) var lastCompletedDropOperation: Int?

    // Offer / drag-out state.
    private(set) var isOfferingDrags = false
    // Whether a native drag we started (a drag-out) is currently running. Used to
    // recognize a same-window self-drag when a drop lands here.
    private var selfDragInProgress = false
    // Whether a local drag start is mid-flight in the async deferred-data pull
    // window (before the native drag begins). Guards against a second t=P starting
    // a duplicate drag or draining the first pull's data.
    private var startingDrag = false
    private var offerMimeTypes: [String] = []
    private var offerOperations = 0
    private var offerData: [Int: Data] = [:]
    // Drag thumbnails the program pre-sent, keyed by their (negative) index: -1 is
    // the first image, -2 the second, and so on. The drag uses the first.
    private var offerImages: [Int: KittyDnDDragImage] = [:]
    /// Cap on a single drag image's byte size (raw or encoded), to bound the work
    /// of converting it for display. Beyond this the drag is refused with EFBIG.
    private static let maxImageBytes = 64 * 1024 * 1024
    /// Bounds on pre-sent offer data, so an offering program cannot grow memory
    /// with arbitrary indices or unbounded payloads.
    private static let maxOfferImages = 16
    private static let maxOfferBytes = 256 * 1024 * 1024

    /// The primary drag thumbnail (index -1, else the first provided).
    private var primaryOfferImage: KittyDnDDragImage? {
        guard let key = offerImages.keys.max() else { return nil }
        return offerImages[key]
    }
    // Completion handlers for outstanding lazy data requests, keyed by 0-based
    // MIME index (the program answers a t=e:x=5 request with t=e:y=idx;data).
    private var pendingDataRequests: [Int: (Data?) -> Void] = [:]

    // The in-progress fetch of a remote program's offered files (dragging them
    // out). It collects the t=k pushes; case "k"/"R" route to it. nil when no
    // remote drag-out is being assembled.
    private var remoteDragFetch: KittyDnDRemoteDragFetch?
    // Temp directory on this machine holding files fetched from a remote program
    // for an in-progress drag-out; removed when the drag finishes.
    private var remoteDragTempDir: URL?
    // Bumped whenever the offer state is reset. An async remote-file build
    // captures it and aborts if it changes, so a superseded build cannot stomp a
    // newer drag's state.
    private var offerGeneration = 0

    init(ourMachineID: String,
         endpoint: KittyDnDEndpoint,
         dragHost: KittyDnDDragHost? = nil,
         report: @escaping (String) -> Void) {
        self.ourMachineID = ourMachineID
        self.endpoint = endpoint
        self.dragHost = dragHost
        self.report = report
    }

    /// Whether the program is on a different machine than us, and so a dropped
    /// file must be transferred in-band (X=1) rather than handed over as a local
    /// path. True if either the machine-id handshake says so, or the session has
    /// a remote endpoint (an SSH-integration conductor), which is ground truth
    /// even when the program sent no machine id.
    private var isRemoteDrop: Bool {
        return KittyDnDMachineID.isRemote(theirID: peerMachineID, ourID: ourMachineID)
            || endpoint.isRemoteHost
    }

    /// Whether the offering program is on a different machine, so its offered
    /// file:// URIs are not readable here and must be fetched from it via t=k.
    private var isRemoteOffer: Bool {
        return KittyDnDMachineID.isRemote(theirID: peerMachineID, ourID: ourMachineID)
            || endpoint.isRemoteHost
    }

    /// Discard all drag-and-drop state. Called when a new shell prompt appears
    /// (the program that used the protocol has exited), so accept/offer state,
    /// open directory handles, and any partially-reassembled message do not leak
    /// into whatever runs next, mirroring how the terminal resets other modes at
    /// a prompt.
    func reset() {
        isAcceptingDrops = false
        acceptedMimeTypes = []
        acceptedDropOperation = nil
        peerMachineID = nil
        currentDrop = nil
        currentDropIsSelfDrag = false
        // NOTE: selfDragInProgress is deliberately NOT cleared here. reset() runs
        // at a new shell prompt (OSC 133), which a program can emit at will while
        // its native drag is still live, so clearing the guard here would let it
        // disarm the self-drag EPERM check mid-drag and then read local files by
        // dropping onto itself. The flag is authoritatively cleared only when the
        // native drag truly ends (dragFinished), which always fires.
        acceptGeneration += 1
        directoryHandles.removeAll()
        nextDirectoryHandle = 2
        lastCompletedDropOperation = nil
        // Keep the multiplexer routing id while a native drag is still live (the
        // same reason selfDragInProgress survives reset): the drag's remaining
        // lifecycle events must stay routable to the right pane. It is dropped at
        // the next prompt reset once no drag is in flight.
        if !selfDragInProgress {
            multiplexerID = nil
        }
        isOfferingDrags = false
        // Forget any pending drag gesture so a later t=P cannot start a phantom
        // drag from a stale event.
        dragHost?.clearPendingGesture()
        // Do NOT delete the remote drag-out temp files while a native drag is
        // still live (a prompt can appear mid-drag when the offering program
        // exits): they back the live drag's uri-list, and dragFinished's delayed
        // cleanup will dispose of them. Only clean up when no drag is in flight.
        if !selfDragInProgress {
            cleanupRemoteDragTempDir()
        }
        resetOfferInProgress()   // clears offer fields and drains pending requests
        reassembler = KittyDnDChunkReassembler()
    }

    // MARK: - Inbound OSC 72

    /// Feed one OSC 72 sequence's raw content (everything after "72;"). Chunked
    /// messages are reassembled internally.
    func handleInboundSequence(_ content: String) {
        guard let message = reassembler.accept(content) else {
            return
        }
        // A t=a or t=o registration carrying an i key sets the multiplexer routing
        // id for all our subsequent sends. (t=q is a one-off whose response echoes
        // its own i, handled in handleQuery, so it does not update this.)
        if message.type == "a" || message.type == "o", let i = message.metadata["i"] {
            multiplexerID = i
        }
        switch message.type {
        case "q":
            handleQuery(message)
        case "a":
            handleAccept(message)
        case "A":
            isAcceptingDrops = false
        case "r":
            handleDataRequest(message)
        case "m":
            // The program's acceptance reply to a move: t=m:o=O tells us the
            // operation it will perform (0 not accepted, 1 copy, 2 move). The
            // AppKit adapter reads acceptedDropOperation to set the OS drag
            // feedback and to gate the drop.
            if let operation = message.intValue("o") {
                acceptedDropOperation = operation
            }
        case "o":
            handleOffer(message)
        case "p":
            handlePreSend(message)
        case "P":
            handleStartDrag(message)
        case "e":
            handleDragDataReply(message)
        case "E":
            handleDragStatus(message)
        case "k":
            // A t=k push from a remote program for an in-progress drag-out: the
            // top-level entry we requested, or one of its children (unsolicited).
            remoteDragFetch?.receive(message)
        case "R":
            // An error reply to an outstanding t=k entry, if any.
            remoteDragFetch?.receiveError(message)
        default:
            // Unknown messages are ignored (forward compatibility).
            break
        }
    }

    private func handleQuery(_ message: KittyDnDMessage) {
        var metadata = ["t": "q"]
        if let i = message.metadata["i"] {
            metadata["i"] = i
        }
        send(KittyDnDMessage(metadata: metadata))
    }

    private func handleAccept(_ message: KittyDnDMessage) {
        // x=2 unregisters; anything else (including absent) registers.
        let x = message.intValue("x")
        if x == 2 {
            isAcceptingDrops = false
            return
        }
        isAcceptingDrops = true
        // A (re)registration starts a fresh acceptance negotiation: forget any
        // operation left over from a previous drag, so a drag that enters while
        // the program was momentarily not accepting cannot inherit a stale accept
        // (dragEntered's reset is skipped when isAcceptingDrops was false).
        acceptedDropOperation = nil
        // Payload is plain text: space-separated MIME types, optionally including
        // the peer's machine id ("1:<hex>").
        let tokens = (message.textPayload ?? "")
            .split(separator: " ")
            .map(String.init)
        if let machineID = tokens.first(where: Self.isMachineIDToken) {
            // The machine id is a stable property of the peer's connection: it
            // cannot change without the program itself changing machines, which
            // does not happen mid-session. So we keep whatever we last learned
            // and only update it when a new id is actually supplied (a program
            // may include it once and omit it on later re-registrations). We
            // normalize to lower case to match our own lower-case hex.
            peerMachineID = machineID.lowercased()
        }
        // `t=a:x=1 ; machine id` is the dedicated machine-id registration escape
        // code and is distinct from the MIME-list registration (`t=a ; mimes`).
        // It must not clear the MIME types the program announced earlier, so only
        // the MIME-list form updates acceptedMimeTypes.
        if x != 1 {
            acceptedMimeTypes = tokens.filter { !Self.isMachineIDToken($0) }
        }
    }

    // MARK: - AppKit drag events (accept-drop)

    func dragEntered(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                     operations: Int, mimeTypes: [String]) {
        guard isAcceptingDrops else { return }
        // A new drag cycle: forget any drop from the previous cycle so a stray
        // t=r cannot read stale data, including open directory handles that
        // pointed into the previous drop's files.
        currentDrop = nil
        currentDropIsSelfDrag = false
        lastCompletedDropOperation = nil
        acceptedDropOperation = nil
        acceptGeneration += 1
        directoryHandles.removeAll()
        nextDirectoryHandle = 2
        sendMoveOrDrop(type: "m", cellX: cellX, cellY: cellY, pixelX: pixelX,
                       pixelY: pixelY, operations: operations, mimeTypes: mimeTypes)
    }

    func dragMoved(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int, operations: Int) {
        guard isAcceptingDrops else { return }
        sendMoveOrDrop(type: "m", cellX: cellX, cellY: cellY, pixelX: pixelX,
                       pixelY: pixelY, operations: operations, mimeTypes: nil)
    }

    func dragExited() {
        guard isAcceptingDrops else { return }
        // The drag left; a re-enter starts a fresh acceptance negotiation.
        acceptedDropOperation = nil
        sendMoveOrDrop(type: "m", cellX: -1, cellY: -1, pixelX: 0, pixelY: 0,
                       operations: 0, mimeTypes: nil)
    }

    /// - Parameter originatedInSameWindow: whether the AppKit layer determined the
    ///   drag came from a Kitty drag-out in the same OS window (e.g. another split
    ///   pane). The spec requires EPERM for a drop whose drag originated in the
    ///   same window, which per-session state alone cannot detect across panes.
    func performDrop(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                     operations: Int, drop: KittyDnDDropData,
                     originatedInSameWindow: Bool = false) {
        guard isAcceptingDrops else { return }
        currentDrop = drop
        // A fresh drop: the previous drop's completed-operation no longer applies,
        // and any read still in flight from before must not stream into this drop.
        lastCompletedDropOperation = nil
        acceptGeneration += 1
        // Latch whether this drop is our own drag-out landing here (same session,
        // via selfDragInProgress) or a drag from another pane of the same window
        // (via the AppKit signal), so the later asynchronous over-the-pty data
        // reads are refused even after the native drag has ended.
        currentDropIsSelfDrag = selfDragInProgress || originatedInSameWindow
        sendMoveOrDrop(type: "M", cellX: cellX, cellY: cellY, pixelX: pixelX,
                       pixelY: pixelY, operations: operations, mimeTypes: drop.mimeTypes)
    }

    /// The program signaled it finished reading the dropped data (t=r:o=op).
    /// Record the final operation and discard all per-drop state so a later stray
    /// request cannot read stale data or use a now-invalid directory handle.
    private func finishDrop(operation: Int) {
        lastCompletedDropOperation = operation
        currentDrop = nil
        currentDropIsSelfDrag = false
        acceptedDropOperation = nil
        acceptGeneration += 1
        directoryHandles.removeAll()
        nextDirectoryHandle = 2
    }

    // MARK: - Data request handling

    private func handleDataRequest(_ message: KittyDnDMessage) {
        // t=r:o=operation with no addressing keys (x / Y) is the drop-completion
        // signal: the program has finished reading. It is not a data request, so
        // it must not draw an error. Discard the per-drop state and any queued
        // directory handles; o=0 (or absent) means the drop was canceled.
        if message.metadata["x"] == nil, message.metadata["Y"] == nil,
           message.metadata["o"] != nil {
            finishDrop(operation: message.intValue("o") ?? 0)
            return
        }
        // Security: refuse to serve data for a drop that came from our own
        // drag-out in this same session. Echo the request's addressing keys.
        if currentDropIsSelfDrag {
            var addressing: [String: String] = [:]
            for key in ["x", "y", "Y"] where message.metadata[key] != nil {
                addressing[key] = message.metadata[key]
            }
            sendError(baseMetadata: addressing, code: "EPERM")
            return
        }
        // A directory-handle request is part of the cross-machine traversal and
        // is not tied to the MIME index.
        if let handle = message.intValue("Y") {
            handleDirectoryRequest(handle: handle, message: message)
            return
        }
        let requestedIndex = message.intValue("x")
        guard let drop = currentDrop else {
            // No drop in progress: the request is not valid.
            sendDataError(index: requestedIndex, code: "EINVAL")
            return
        }
        guard let index = requestedIndex else {
            // A data request with no MIME index is malformed.
            sendDataError(index: nil, code: "EINVAL")
            return
        }
        guard index >= 1, index <= drop.mimeTypes.count else {
            // Spec: "Terminals must reply with ENOENT if the index is out of bounds."
            sendDataError(index: index, code: "ENOENT")
            return
        }
        let mime = drop.mimeTypes[index - 1]

        // A sub-index (y) request is the cross-machine path: the program asks for
        // one file entry within the uri-list so it can pull the actual bytes.
        if let entryIndex = message.intValue("y") {
            guard mime == "text/uri-list" else {
                // Sub-indexing only applies to a uri-list entry.
                sendError(baseMetadata: ["x": String(index), "y": String(entryIndex)],
                          code: "EINVAL")
                return
            }
            guard entryIndex >= 1, entryIndex <= drop.fileURLs.count else {
                sendError(baseMetadata: ["x": String(index), "y": String(entryIndex)],
                          code: "ENOENT")
                return
            }
            answerFilesystemEntry(url: drop.fileURLs[entryIndex - 1],
                                  responseMetadata: ["x": String(index),
                                                     "y": String(entryIndex)])
            return
        }

        if mime == "text/uri-list" {
            answerURIList(index: index, drop: drop)
        } else if let data = drop.data(forMimeIndex: index) {
            sendData(index: index, data: data, extraMetadata: [:])
        } else {
            sendDataError(index: index, code: "ENOENT")
        }
    }

    // MARK: - Cross-machine file/dir transfer (in-band)

    private func handleDirectoryRequest(handle: Int, message: KittyDnDMessage) {
        guard let children = directoryHandles[handle] else {
            sendError(baseMetadata: ["Y": String(handle)], code: "EINVAL")
            return
        }
        guard let num = message.intValue("x") else {
            // No index: the program is done with this directory; free it.
            directoryHandles.removeValue(forKey: handle)
            return
        }
        guard num >= 1, num <= children.count else {
            sendError(baseMetadata: ["Y": String(handle), "x": String(num)], code: "ENOENT")
            return
        }
        answerFilesystemEntry(url: children[num - 1],
                              responseMetadata: ["Y": String(handle), "x": String(num)])
    }

    /// Respond to a request for one filesystem entry: stream a regular file's
    /// bytes, a symlink's target (X=1), or a directory's entry names plus a new
    /// handle (X=handle). The dropped files are local to us, so this is the
    /// terminal-reads-and-streams half of the protocol's cross-machine support.
    private func answerFilesystemEntry(url: URL, responseMetadata: [String: String]) {
        // Capture the drop context now; if it changes while we read (the drop was
        // completed, superseded, or reset), discard the result so we neither
        // stream stale bytes nor resurrect a freed directory handle.
        let generation = acceptGeneration
        Task { @MainActor in
            do {
                let entry = try await Self.readEntryOffMainThread(url)
                guard generation == self.acceptGeneration else { return }
                switch entry {
                case .regularFile(let data):
                    sendChunkedData(baseMetadata: responseMetadata, data: data)
                case .symlink(let target):
                    var metadata = responseMetadata
                    metadata["X"] = "1"
                    sendChunkedData(baseMetadata: metadata, data: Data(target.utf8))
                case .directory(let children):
                    let handle = allocateDirectoryHandle(children: children)
                    var metadata = responseMetadata
                    metadata["X"] = String(handle)
                    let names = children.map { $0.lastPathComponent }.joined(separator: "\u{0}")
                    sendChunkedData(baseMetadata: metadata, data: Data(names.utf8))
                }
            } catch is EntryTypeError {
                // Spec: EINVAL if the entry is not a regular file, symlink, or
                // directory (e.g. a socket or FIFO).
                guard generation == self.acceptGeneration else { return }
                sendError(baseMetadata: responseMetadata, code: "EINVAL")
            } catch {
                guard generation == self.acceptGeneration else { return }
                sendError(baseMetadata: responseMetadata, code: "EIO")
            }
        }
    }

    private func allocateDirectoryHandle(children: [URL]) -> Int {
        let handle = nextDirectoryHandle
        nextDirectoryHandle += 1
        directoryHandles[handle] = children
        return handle
    }

    private func answerURIList(index: Int, drop: KittyDnDDropData) {
        // Return the local file URIs. For a remote drop they are foreign to the
        // program, so flag X=1; the program then pulls each file's bytes in-band
        // by sub-index (t=r:x=idx:y=entry). For a local drop the paths are
        // directly usable and no flag is set.
        let uris = drop.fileURLs.map { Self.directoryAwareURIString($0) }
        let extra = isRemoteDrop ? ["X": "1"] : [:]
        sendData(index: index,
                 data: Data(uris.joined(separator: "\r\n").utf8),
                 extraMetadata: extra)
    }

    /// The absolute file:// string for `url`, with a trailing slash if it points
    /// to a directory on disk. Spec: "All file:// URLs that point to directories
    /// must end with a /." The on-disk type is authoritative because a URL handed
    /// to us may have been built without directory awareness.
    static func directoryAwareURIString(_ url: URL) -> String {
        let string = url.absoluteString
        guard url.isFileURL, !string.hasSuffix("/") else {
            return string
        }
        // A symlink is served to the program as a symlink (X=1), not a directory,
        // even if it points at one, so never give it a directory trailing slash.
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            return string
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return string + "/"
        }
        return string
    }

    // MARK: - Offer / drag-out (inbound)

    private func handleOffer(_ message: KittyDnDMessage) {
        switch message.intValue("x") {
        case 1:
            isOfferingDrags = true
            let tokens = (message.textPayload ?? "").split(separator: " ").map(String.init)
            if let machineID = tokens.first(where: Self.isMachineIDToken) {
                peerMachineID = machineID.lowercased()
            }
        case 2:
            isOfferingDrags = false
            // Disabling offers ends any in-progress drag negotiation, so drain
            // outstanding data-request completions rather than leaking them, and
            // forget any pending gesture so it cannot start a later phantom drag.
            dragHost?.clearPendingGesture()
            resetOfferInProgress()
        default:
            // A t=o with neither x nor o is not a declaration; ignore it rather
            // than destroying an in-progress offer (unknown variants are no-ops).
            guard message.metadata["o"] != nil else {
                return
            }
            // The program's offer declaration for a started gesture: operations
            // plus the offered MIME list. Abandon any prior half-built offer and
            // drain its outstanding data requests before starting fresh.
            resetOfferInProgress()
            offerOperations = message.intValue("o") ?? 0
            offerMimeTypes = (message.textPayload ?? "")
                .split(separator: " ")
                .map(String.init)
                .filter { !Self.isMachineIDToken($0) }
        }
    }

    private func handlePreSend(_ message: KittyDnDMessage) {
        guard let index = message.intValue("x") else {
            return
        }
        let data = message.dataPayload ?? Data()
        if index < 0 {
            // Negative index: a drag thumbnail image (-1 first, -2 second, ...).
            // Bound the number of thumbnails and the cumulative offer size so a
            // program cannot store unbounded data with arbitrary indices.
            guard index >= -Self.maxOfferImages else { return }
            let existing = offerImages[index]?.data.count ?? 0
            guard withinOfferBudget(replacing: existing, adding: data.count) else { return }
            offerImages[index] = KittyDnDDragImage(format: message.intValue("y") ?? 0,
                                                   width: message.intValue("X") ?? 0,
                                                   height: message.intValue("Y") ?? 0,
                                                   data: data)
        } else {
            // Only accept indices within the announced offer's MIME list, and keep
            // the cumulative pre-sent size under budget.
            guard index < offerMimeTypes.count else { return }
            let existing = offerData[index]?.count ?? 0
            guard withinOfferBudget(replacing: existing, adding: data.count) else { return }
            offerData[index] = data
        }
    }

    /// Whether storing `adding` bytes (after removing `replacing` bytes for an
    /// index being overwritten) keeps the total pre-sent offer data under budget.
    private func withinOfferBudget(replacing: Int, adding: Int) -> Bool {
        let current = offerData.values.reduce(0) { $0 + $1.count }
            + offerImages.values.reduce(0) { $0 + $1.data.count }
        return current - replacing + adding <= Self.maxOfferBytes
    }

    /// Validate the pre-sent drag images against the spec: raw RGB/RGBA data must
    /// match the declared dimensions (else EINVAL), and no image may exceed the
    /// size cap (else EFBIG). Returns the error code to report, or nil if OK.
    private func offerImageError() -> String? {
        for (_, image) in offerImages {
            switch image.format {
            case 24, 32:
                let bytesPerPixel = image.format == 32 ? 4 : 3
                guard image.width > 0, image.height > 0 else { return "EINVAL" }
                // Compute width*height*bpp without trapping on overflow from
                // attacker-controlled dimensions.
                let (area, o1) = image.width.multipliedReportingOverflow(by: image.height)
                let (expected, o2) = o1 ? (0, true) : area.multipliedReportingOverflow(by: bytesPerPixel)
                if o1 || o2 { return "EFBIG" }
                if image.data.count != expected { return "EINVAL" }
                if expected > Self.maxImageBytes { return "EFBIG" }
            default:
                // PNG (100), text (0), or an unknown format: no fixed size to
                // check, just guard the byte cap.
                if image.data.count > Self.maxImageBytes { return "EFBIG" }
            }
        }
        return nil
    }

    private func handleStartDrag(_ message: KittyDnDMessage) {
        // t=P:x=-1 starts the drag; other x values change the drag image, which
        // we do not support yet.
        guard message.intValue("x") == -1 else {
            return
        }
        // Ignore a t=P while a drag is already live or being assembled, so a
        // duplicate does not start a second native drag or drain an in-flight
        // deferred-data pull.
        guard !selfDragInProgress, !startingDrag, remoteDragFetch == nil else {
            return
        }
        // Reject malformed or oversized drag images before starting.
        if let code = offerImageError() {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: code))
            resetOfferInProgress()
            return
        }
        // If the program is remote and offering files, its file:// URIs are not
        // readable here. Fetch each one from the program via t=k, materialize
        // copies in a temp directory, and drag those local copies. Otherwise the
        // offered URIs are local and we drag them directly.
        if isRemoteOffer, let uriListIndex = offerMimeTypes.firstIndex(of: "text/uri-list") {
            // Mark the start in progress synchronously: handleInboundSequence runs
            // on the main actor, so a duplicate t=P in the same read batch would
            // otherwise pass the guard above (remoteDragFetch is only assigned
            // inside the async task) and spawn a second concurrent fetch.
            startingDrag = true
            Task { @MainActor in
                await self.beginRemoteFileDrag(uriListIndex: uriListIndex)
            }
            return
        }
        // The program may pre-send some MIME data (t=p) and defer the rest,
        // expecting the terminal to pull it on demand. Pull anything not
        // pre-sent via t=e:x=5 before starting the drag. The common case (all
        // data pre-sent) stays synchronous.
        let missing = offerMimeTypes.indices.filter { offerData[$0] == nil }
        guard missing.isEmpty else {
            startingDrag = true
            Task { @MainActor in await self.beginLocalDragFetchingMissing(missing) }
            return
        }
        beginDrag(with: KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                          data: offerData,
                                          operations: offerOperations,
                                          image: primaryOfferImage))
    }

    /// Request each offered MIME the program did not pre-send (the lazy delivery
    /// path), then start the drag once the data is in hand.
    private func beginLocalDragFetchingMissing(_ missing: [Int]) async {
        // The async pull window is over once we return (we either start the drag,
        // which sets selfDragInProgress, or bail); clear the guard either way.
        defer { startingDrag = false }
        let generation = offerGeneration
        for index in missing {
            let data: Data? = await withCheckedContinuation { continuation in
                requestDragData(mimeIndex: index) { continuation.resume(returning: $0) }
            }
            // A reset / new offer while awaiting supersedes this drag.
            guard generation == offerGeneration else { return }
            if let data {
                offerData[index] = data
            }
        }
        guard generation == offerGeneration else { return }
        beginDrag(with: KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                          data: offerData,
                                          operations: offerOperations,
                                          image: primaryOfferImage))
    }

    private func beginDrag(with offer: KittyDnDDragOffer) {
        guard let dragHost, dragHost.beginDrag(offer) else {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:could not start drag"))
            cleanupRemoteDragTempDir()
            resetOfferInProgress()
            return
        }
        // A native drag we started is now running: a drop that lands on this same
        // session is a self-drag and its data reads must be refused (EPERM).
        selfDragInProgress = true
        send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "OK"))
    }

    /// Fetch the offered files from the remote program via t=k into a temp dir,
    /// then drag those local copies. The terminal requests only the top-level
    /// uri-list entries; the program pushes directory children unsolicited, which
    /// KittyDnDRemoteDragFetch assembles.
    private func beginRemoteFileDrag(uriListIndex: Int) async {
        // The start is no longer pending once we return (we either begin the drag,
        // which sets selfDragInProgress, or bail); clear the idempotency guard.
        defer { startingDrag = false }
        // Discard any temp dir from a prior build, and take a generation so that a
        // reset / new offer arriving while we await can abort this build instead
        // of stomping the newer one.
        cleanupRemoteDragTempDir()
        let generation = offerGeneration
        let names = Self.uriListNames(offerData[uriListIndex])
        guard !names.isEmpty else {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EINVAL:no files"))
            resetOfferInProgress()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iterm2-kittydnd-\(UUID().uuidString)")

        var fetchRef: KittyDnDRemoteDragFetch?
        let localURLs: [URL]? = await withCheckedContinuation { continuation in
            let fetch = KittyDnDRemoteDragFetch(
                tempDir: tempDir,
                topLevelNames: names,
                send: { [weak self] in self?.send($0) },
                completion: { continuation.resume(returning: $0) })
            fetchRef = fetch
            self.remoteDragFetch = fetch
            fetch.start()
        }
        // Only clear the reference if it is still ours (a newer offer may have
        // replaced it while we awaited).
        if remoteDragFetch === fetchRef {
            remoteDragFetch = nil
        }

        guard generation == offerGeneration else {
            // Superseded by a reset / newer offer while fetching; discard quietly.
            Self.removeItemOffMainThread(tempDir)
            return
        }
        guard let localURLs, !localURLs.isEmpty else {
            // Aborted, resource-limited, or nothing usable (e.g. all symlinks).
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:no usable files"))
            Self.removeItemOffMainThread(tempDir)
            resetOfferInProgress()
            return
        }
        remoteDragTempDir = tempDir
        // Replace the uri-list in the offer with the local temp copies. Directory
        // entries get a trailing slash per the spec.
        var data = offerData
        data[uriListIndex] = Data(localURLs.map { Self.directoryAwareURIString($0) }
            .joined(separator: "\r\n").utf8)
        beginDrag(with: KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                          data: data,
                                          operations: offerOperations,
                                          image: primaryOfferImage))
    }

    private func cleanupRemoteDragTempDir() {
        guard let dir = remoteDragTempDir else { return }
        remoteDragTempDir = nil
        Self.removeItemOffMainThread(dir)
    }

    /// Remove the drag-out temp dir after a delay, so a drop landing in another
    /// terminal session (which reads the files lazily after the drag ends) has
    /// time to finish, while still guaranteeing eventual cleanup.
    private func scheduleDelayedTempCleanup() {
        guard let dir = remoteDragTempDir else { return }
        remoteDragTempDir = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            Self.removeItemOffMainThread(dir)
        }
    }

    static func removeItemOffMainThread(_ url: URL) {
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func handleDragDataReply(_ message: KittyDnDMessage) {
        // The program's reply to a t=e:x=5 lazy data request: t=e:y=idx;data.
        guard let index = message.intValue("y"),
              let completion = pendingDataRequests.removeValue(forKey: index) else {
            return
        }
        completion(message.dataPayload)
    }

    private func handleDragStatus(_ message: KittyDnDMessage) {
        // t=E from the program. y=-1 cancels the whole drag; otherwise it is an
        // error reply to a lazy data request for that MIME index.
        guard let y = message.intValue("y") else {
            return
        }
        if y == -1 {
            dragHost?.cancelDrag()
            resetOfferInProgress()
        } else if let completion = pendingDataRequests.removeValue(forKey: y) {
            completion(nil)
        }
    }

    // MARK: - Offer / drag-out (from AppKit / drag host)

    /// The AppKit adapter detected a drag gesture starting over the terminal.
    func dragGestureDetected(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int) {
        guard isOfferingDrags else { return }
        send(KittyDnDMessage(metadata: [
            "t": "o",
            "x": String(cellX),
            "y": String(cellY),
            "X": String(pixelX),
            "Y": String(pixelY),
        ]))
    }

    /// The native drag was accepted by a destination that prefers the MIME type
    /// at `preferredMimeIndex`.
    func dragAccepted(preferredMimeIndex: Int) {
        send(KittyDnDMessage(metadata: ["t": "e", "x": "1", "y": String(preferredMimeIndex)]))
    }

    func dragActionChanged(operation: Int) {
        send(KittyDnDMessage(metadata: ["t": "e", "x": "2", "o": String(operation)]))
    }

    func dragDropped() {
        send(KittyDnDMessage(metadata: ["t": "e", "x": "3"]))
    }

    func dragFinished(canceled: Bool) {
        send(KittyDnDMessage(metadata: ["t": "e", "x": "4", "y": canceled ? "1" : "0"]))
        // The native drag has truly ended: it is now safe to drop the self-drag
        // guard. This is the ONLY place it is cleared, so no program-controllable
        // inbound sequence (offer/cancel messages, or an OSC 133 prompt that
        // triggers reset()) can disarm the EPERM check while the drag is live.
        selfDragInProgress = false
        // Do NOT delete the temp copies immediately: when the drop lands in
        // another terminal session, that session reads these files lazily over
        // the pty AFTER the drag ends, so deleting now would make its read fail.
        // Remove them after a delay long enough for such a read to finish.
        scheduleDelayedTempCleanup()
        resetOfferInProgress()
    }

    /// Ask the program for the data at `mimeIndex` (the lazy path, used when it
    /// was not pre-sent). `completion` is called with the bytes, or nil on error.
    func requestDragData(mimeIndex: Int, completion: @escaping (Data?) -> Void) {
        // Fail any request already outstanding for this index so its completion
        // is never leaked when we overwrite it.
        pendingDataRequests[mimeIndex]?(nil)
        pendingDataRequests[mimeIndex] = completion
        send(KittyDnDMessage(metadata: ["t": "e", "x": "5", "y": String(mimeIndex)]))
    }

    private func resetOfferInProgress() {
        offerGeneration += 1
        // NOTE: selfDragInProgress is deliberately NOT cleared here. This runs
        // from program-controlled inbound messages (t=o:x=2, a new offer, t=E
        // cancel) that do not actually end the live OS drag (cancelDrag is
        // best-effort and cannot stop a running NSDraggingSession). Clearing it
        // here would let a program turn off the self-drag guard mid-drag and then
        // read local files by dropping its own drag onto itself. It is cleared
        // only when the native drag truly ends (dragFinished) or on reset().
        offerMimeTypes = []
        offerOperations = 0
        offerData = [:]
        offerImages = [:]
        for (_, completion) in pendingDataRequests {
            completion(nil)
        }
        pendingDataRequests = [:]
        // Abandon any in-progress remote drag-out fetch (resumes its awaiter with
        // nil so beginRemoteFileDrag cleans up its temp dir).
        remoteDragFetch?.abort()
        remoteDragFetch = nil
    }

    // MARK: - Remote drag-out helpers

    /// Base names of the entries in a text/uri-list payload, sanitized to a
    /// single safe path component each.
    private static func uriListNames(_ data: Data?) -> [String] {
        guard let data, let list = String(data: data, encoding: .utf8) else {
            return []
        }
        return list
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { sanitizeComponent(URL(string: $0)?.lastPathComponent ?? "") }
    }

    /// Reduce an untrusted name from a remote program to a single safe path
    /// component so it cannot escape the temp directory.
    static func sanitizeComponent(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "item"
        }
        return cleaned
    }

    static func writeOffMainThread(_ block: @escaping @Sendable () throws -> Void) async -> Bool {
        return await Task.detached(priority: .utility) {
            do {
                try block()
                return true
            } catch {
                return false
            }
        }.value
    }

    // MARK: - Outbound helpers

    private func sendMoveOrDrop(type: String, cellX: Int, cellY: Int,
                               pixelX: Int, pixelY: Int, operations: Int,
                               mimeTypes: [String]?) {
        let metadata = [
            "t": type,
            "x": String(cellX),
            "y": String(cellY),
            "X": String(pixelX),
            "Y": String(pixelY),
            "o": String(operations),
        ]
        if let mimeTypes {
            send(KittyDnDMessage(metadata: metadata,
                                 textPayload: mimeTypes.joined(separator: " ")))
        } else {
            send(KittyDnDMessage(metadata: metadata))
        }
    }

    private func sendData(index: Int, data: Data, extraMetadata: [String: String]) {
        var metadata = extraMetadata
        metadata["x"] = String(index)
        sendChunkedData(baseMetadata: metadata, data: data)
    }

    /// Send a t=r data response, chunked. `baseMetadata` supplies the addressing
    /// keys (x / y / Y and any X type flag); t=r is added here.
    private func sendChunkedData(baseMetadata: [String: String], data: Data) {
        var metadata = baseMetadata
        metadata["t"] = "r"
        for message in KittyDnDChunker.messages(baseMetadata: metadata, data: data) {
            send(message)
        }
    }

    private func sendDataError(index: Int?, code: String) {
        sendError(baseMetadata: index.map { ["x": String($0)] } ?? [:], code: code)
    }

    /// Send a t=R error response echoing the request's addressing keys.
    private func sendError(baseMetadata: [String: String], code: String) {
        var metadata = baseMetadata
        metadata["t"] = "R"
        send(KittyDnDMessage(metadata: metadata, textPayload: code))
    }

    private func send(_ message: KittyDnDMessage) {
        var message = message
        // Stamp the multiplexer id on every outbound message (and every chunk,
        // which each pass through here) unless the message already carries an
        // explicit i (e.g. a query response echoing the query's own i).
        if let multiplexerID, message.metadata["i"] == nil {
            message.metadata["i"] = multiplexerID
        }
        report(message.serialized())
    }

    // MARK: - File IO

    /// One filesystem entry as needed by the cross-machine transfer.
    private enum FilesystemEntry {
        case regularFile(Data)
        case symlink(String)        // link target
        case directory([URL])       // sorted child URLs
    }

    /// Thrown when an entry is neither a regular file, symlink, nor directory
    /// (e.g. a socket or FIFO). Mapped to EINVAL per the spec.
    private struct EntryTypeError: Error {}

    /// Classify and read `url` off the main thread. A symlink is reported as a
    /// symlink (not followed); a directory yields its sorted children. A special
    /// file (socket, FIFO, device) throws EntryTypeError and is NEVER opened for
    /// reading, since opening a FIFO would block.
    private static func readEntryOffMainThread(_ url: URL) async throws -> FilesystemEntry {
        return try await Task.detached(priority: .utility) {
            let values = try url.resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true {
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                return .symlink(target)
            }
            if values.isDirectory == true {
                let children = try FileManager.default
                    .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                return .directory(children)
            }
            guard values.isRegularFile == true else {
                throw EntryTypeError()
            }
            return .regularFile(try Data(contentsOf: url))
        }.value
    }

    // MARK: - Machine id

    private static func isMachineIDToken(_ token: String) -> Bool {
        guard token.hasPrefix("1:") else { return false }
        let hex = token.dropFirst(2)
        return hex.count == 64 && hex.allSatisfy { $0.isHexDigit }
    }
}
