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
import ImageIO

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

    /// The drag operation to advertise to the OS (kitty op: 0 not accepted, 1 copy,
    /// 2 move). If the program has replied (t=m:o) we honor it; otherwise we
    /// optimistically report the offered operation so a fast drop released before
    /// the reply's pty round trip completes is accepted rather than springing back.
    /// A drop is only refused when the program explicitly answered 0.
    var osDragOperation: Int {
        if let op = acceptedDropOperation {
            return op
        }
        // Optimistically prefer copy (non-destructive) so a move the OS source acts
        // on before the program has confirmed cannot delete the source's only copy;
        // fall back to move only if the source offers move-only (kitty op == 2).
        let offered = lastReportedMove?.operations ?? 1
        return (offered & 1) != 0 ? 1 : 2
    }

    // The last hover (t=m) report we sent, to suppress duplicate stationary moves.
    private struct MoveReport: Equatable {
        var cellX, cellY, pixelX, pixelY, operations: Int
    }
    private var lastReportedMove: MoveReport?
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
    // Addressing keys of filesystem-entry reads currently in flight, so an
    // identical t=r request repeated while one is being served does not spawn a
    // second full read and multiply the memory/IO spike. Keys are scoped by the
    // accept generation so an old drop's completing read cannot remove a new
    // drop's key.
    private var inFlightEntryRequests: Set<String> = []
    // Tail of the serialized chain of entry-response Tasks. Each response awaits
    // the previous so their chunked outputs never interleave on the pty (the
    // streaming send yields, which would otherwise allow interleaving).
    private var responseTail: Task<Void, Never>?
    /// Cap on concurrent filesystem-entry reads. Spec: "if too many requests are
    /// received, terminals must deny the request with EMFILE and end the drop."
    private static let maxConcurrentEntryRequests = 64
    // Whether the program has requested the text/uri-list MIME type for the
    // current drop. A sub-index (y) request before that is EINVAL per the spec.
    private var uriListRequested = false
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
    /// Cap on a drag image's DECODED pixel count (width*height), so a small
    /// compressed PNG declaring huge dimensions cannot force a giant bitmap decode.
    /// 4 bytes/pixel of the byte cap => ~16M pixels (e.g. 4096x4096).
    private static let maxImagePixels = maxImageBytes / 4
    /// Bounds on pre-sent offer data, so an offering program cannot grow memory
    /// with arbitrary indices or unbounded payloads.
    private static let maxOfferImages = 16
    private static let maxOfferBytes = 256 * 1024 * 1024
    /// Cap on simultaneously-open directory handles in the accept-drop traversal,
    /// so a program that re-lists directories in a loop cannot grow memory without
    /// bound. Beyond this a directory request is answered with ENOMEM.
    private static let maxDirectoryHandles = 512
    /// Cap on a single dropped file we will stream to a program (t=r). Beyond this
    /// we answer EFBIG rather than paging gigabytes through the pty write buffer.
    private static let maxServedFileBytes = 2 * 1024 * 1024 * 1024

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
        inFlightEntryRequests.removeAll()
        uriListRequested = false
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
        // Any inbound sequence from the program is a sign of life for an in-progress
        // remote drag-out fetch, including the individual chunks of one large file
        // (which never produce a completed message until m=0). Rearm the fetch's
        // idle timeout here so a healthy long transfer is not aborted mid-stream.
        remoteDragFetch?.noteActivity()
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
            // Forget any latched acceptance so a drop after the program stopped
            // accepting is not reported to the OS as accepted while performDrop
            // silently discards it.
            acceptedDropOperation = nil
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
            acceptedDropOperation = nil
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
        inFlightEntryRequests.removeAll()
        uriListRequested = false
        lastReportedMove = MoveReport(cellX: cellX, cellY: cellY, pixelX: pixelX,
                                      pixelY: pixelY, operations: operations)
        sendMoveOrDrop(type: "m", cellX: cellX, cellY: cellY, pixelX: pixelX,
                       pixelY: pixelY, operations: operations, mimeTypes: mimeTypes)
    }

    func dragMoved(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int, operations: Int) {
        guard isAcceptingDrops else { return }
        // AppKit delivers periodic hover updates (~10/sec) even while the pointer
        // is stationary; skip a move that is identical to the last reported one so
        // we do not stream a train of duplicate t=m over the pty (sustained ssh
        // traffic and remote wakeups for zero information).
        let move = MoveReport(cellX: cellX, cellY: cellY, pixelX: pixelX,
                              pixelY: pixelY, operations: operations)
        guard move != lastReportedMove else { return }
        lastReportedMove = move
        sendMoveOrDrop(type: "m", cellX: cellX, cellY: cellY, pixelX: pixelX,
                       pixelY: pixelY, operations: operations, mimeTypes: nil)
    }

    func dragExited() {
        guard isAcceptingDrops else { return }
        // The drag left; a re-enter starts a fresh acceptance negotiation.
        acceptedDropOperation = nil
        lastReportedMove = nil
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
        inFlightEntryRequests.removeAll()
        uriListRequested = false
    }

    // MARK: - Data request handling

    private func handleDataRequest(_ message: KittyDnDMessage) {
        // A t=r with NO addressing keys (x / y / Y) is the drop-completion signal:
        // the program has finished reading (spec: "a request for data with no MIME
        // type specified"). o defaults to 0 = canceled when absent. A message that
        // carries y is an attempted (malformed) sub-index request, not completion.
        if message.metadata["x"] == nil, message.metadata["Y"] == nil,
           message.metadata["y"] == nil {
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
            guard uriListRequested else {
                // Spec: EINVAL if the client did not first request the uri-list
                // MIME type (the sub-index space is anchored to a list it has seen).
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
            uriListRequested = true
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
        // Only a request with the x key ABSENT is the free-handle form; a present
        // but unparseable x is a malformed request, not a free.
        if message.metadata["x"] == nil {
            directoryHandles.removeValue(forKey: handle)
            return
        }
        guard let num = message.intValue("x") else {
            sendError(baseMetadata: ["Y": String(handle)], code: "EINVAL")
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
        // Cap concurrent reads. Spec: "if too many requests are received, terminals
        // must deny the request with EMFILE and end the drop."
        guard inFlightEntryRequests.count < Self.maxConcurrentEntryRequests else {
            sendError(baseMetadata: responseMetadata, code: "EMFILE")
            finishDrop(operation: 0)
            return
        }
        // Drop an identical request already being served, so a program cannot
        // multiply the read/memory spike by repeating the same t=r in a loop. The
        // key is scoped by generation so an old drop's completing read cannot
        // remove a new drop's key (which would let a duplicate slip through).
        let requestKey = "\(generation):\(Self.entryRequestKey(responseMetadata))"
        guard inFlightEntryRequests.insert(requestKey).inserted else { return }
        enqueueResponse {
            defer { self.inFlightEntryRequests.remove(requestKey) }
            do {
                let entry = try await Self.readEntryOffMainThread(url)
                guard generation == self.acceptGeneration else { return }
                switch entry {
                case .regularFile(let data):
                    guard data.count <= Self.maxServedFileBytes else {
                        self.sendError(baseMetadata: responseMetadata, code: "EFBIG")
                        return
                    }
                    // Stream the (memory-mapped) file one chunk at a time so only a
                    // single chunk's base64 is resident, not the whole file's, and
                    // yielding so a huge file does not freeze the UI.
                    await self.sendChunkedDataStreaming(baseMetadata: responseMetadata, data: data,
                                                        generation: generation)
                case .symlink(let target):
                    var metadata = responseMetadata
                    metadata["X"] = "1"
                    self.sendChunkedData(baseMetadata: metadata, data: Data(target.utf8))
                case .directory(let children):
                    guard self.directoryHandles.count < Self.maxDirectoryHandles else {
                        // Spec: terminals must return ENOMEM on resource exhaustion.
                        self.sendError(baseMetadata: responseMetadata, code: "ENOMEM")
                        return
                    }
                    let handle = self.allocateDirectoryHandle(children: children)
                    var metadata = responseMetadata
                    metadata["X"] = String(handle)
                    let names = children.map { $0.lastPathComponent }.joined(separator: "\u{0}")
                    self.sendChunkedData(baseMetadata: metadata, data: Data(names.utf8))
                }
            } catch is EntryTypeError {
                // Spec: EINVAL if the entry is not a regular file, symlink, or
                // directory (e.g. a socket or FIFO).
                guard generation == self.acceptGeneration else { return }
                self.sendError(baseMetadata: responseMetadata, code: "EINVAL")
            } catch {
                guard generation == self.acceptGeneration else { return }
                self.sendError(baseMetadata: responseMetadata, code: Self.errorCode(for: error))
            }
        }
    }

    /// Run `body` (a filesystem-entry response) on a serialized chain so its
    /// chunked t=r output is emitted contiguously and cannot interleave with
    /// another entry response's chunks on the pty (the reassembler concatenates
    /// same-t chunks and would corrupt them). The streaming file send yields
    /// periodically, so without this a second concurrent entry response could run
    /// in a gap. (The small synchronous uri-list / plain-MIME sends are not routed
    /// here; see docs/kitty-dnd-design.md section 8 for the narrow residual.)
    private func enqueueResponse(_ body: @escaping @MainActor () async -> Void) {
        let previous = responseTail
        responseTail = Task { @MainActor in
            await previous?.value
            await body()
        }
    }

    /// Map a filesystem read error to the spec's protocol code: ENOENT for a
    /// missing file, EPERM for a permission failure, EIO otherwise.
    private static func errorCode(for error: Error) -> String {
        let nsError = error as NSError
        if let posix = error as? POSIXError {
            switch posix.code {
            case .ENOENT: return "ENOENT"
            case .EACCES, .EPERM: return "EPERM"
            default: break
            }
        }
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return "ENOENT"
            case NSFileReadNoPermissionError:
                return "EPERM"
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ENOENT: return "ENOENT"
            case EACCES, EPERM: return "EPERM"
            default: break
            }
        }
        return "EIO"
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
            // Only a program that opted in (t=o:x=1) may declare an offer.
            guard isOfferingDrags else {
                return
            }
            // If the drag gesture has already been terminated (the user let go),
            // reply EPERM instead of pre-sending/pulling data for a doomed drag.
            if let dragHost, !dragHost.hasLiveGesture {
                send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EPERM:drag gesture ended"))
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
        // Pre-sent data is only meaningful during an offer the program has
        // DECLARED (t=o:o=...), which only happens after a live drag gesture. This
        // gates the image branch too, so output the user merely cats cannot park
        // data in offerImages without an active, gesture-backed offer.
        guard !offerMimeTypes.isEmpty else {
            return
        }
        guard let index = message.intValue("x") else {
            return
        }
        let data = message.dataPayload ?? Data()
        if index < 0 {
            // Negative index: a drag thumbnail image (-1 first, -2 second, ...).
            // Bound the number of thumbnails, per-image size, and cumulative offer
            // size; over budget aborts the drag with EFBIG (spec: too much data
            // cancels it).
            guard index >= -Self.maxOfferImages else {
                rejectOffer(code: "EFBIG:too many images")
                return
            }
            guard data.count <= Self.maxImageBytes else {
                rejectOffer(code: "EFBIG:image too large")
                return
            }
            let existing = offerImages[index]?.data.count ?? 0
            guard withinOfferBudget(replacing: existing, adding: data.count) else {
                rejectOffer(code: "EFBIG:offer too large")
                return
            }
            offerImages[index] = KittyDnDDragImage(format: message.intValue("y") ?? 0,
                                                   width: message.intValue("X") ?? 0,
                                                   height: message.intValue("Y") ?? 0,
                                                   data: data)
        } else {
            // Only accept indices within the announced offer's MIME list (a
            // malformed index is ignored), and keep the cumulative pre-sent size
            // under budget (over budget aborts with EFBIG).
            guard index < offerMimeTypes.count else { return }
            let existing = offerData[index]?.count ?? 0
            guard withinOfferBudget(replacing: existing, adding: data.count) else {
                rejectOffer(code: "EFBIG:offer too large")
                return
            }
            offerData[index] = data
        }
    }

    /// The decoded pixel count (width*height) of an image, read from its header
    /// without a full decode. nil if the header cannot be parsed.
    private static func imagePixelCount(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        let (product, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : product
    }

    /// Abort an in-progress drag offer with an error, per the spec's "reply with
    /// t=E ; <code> and cancel the drag".
    private func rejectOffer(code: String) {
        send(KittyDnDMessage(metadata: ["t": "E"], textPayload: code))
        cleanupRemoteDragTempDir()
        resetOfferInProgress()
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
            case 100:
                // PNG: guard the byte cap, and the DECODED pixel dimensions (read
                // from the header without a full decode) so a small compressed file
                // declaring huge dimensions cannot force a multi-GB bitmap decode.
                if image.data.count > Self.maxImageBytes { return "EFBIG" }
                if let pixels = Self.imagePixelCount(image.data),
                   pixels > Self.maxImagePixels {
                    return "EFBIG"
                }
            default:
                // Text (0) or an unknown format: no fixed size to check, just guard
                // the byte cap.
                if image.data.count > Self.maxImageBytes { return "EFBIG" }
            }
        }
        return nil
    }

    private func handleStartDrag(_ message: KittyDnDMessage) {
        // Only a program that opted in (t=o:x=1) may start a drag.
        guard isOfferingDrags else {
            return
        }
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
        guard await pullDeferredOfferData(missing, generation: generation) else {
            return
        }
        beginDrag(with: KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                          data: offerData,
                                          operations: offerOperations,
                                          image: primaryOfferImage))
    }

    /// Pull each of the given offered MIME indices the program did not pre-send
    /// via the t=e:x=5 request path, filling offerData. Returns false if the offer
    /// was superseded (a reset / new offer) while awaiting.
    private func pullDeferredOfferData(_ missing: [Int], generation: Int) async -> Bool {
        for index in missing {
            let data: Data? = await withCheckedContinuation { continuation in
                requestDragData(mimeIndex: index) { continuation.resume(returning: $0) }
            }
            guard generation == offerGeneration else { return false }
            if let data {
                // Charge pulled data against the same budget as pre-sent data, so a
                // program cannot bypass the t=p cap by deferring everything to the
                // pull path. Over budget aborts the drag with EFBIG.
                let existing = offerData[index]?.count ?? 0
                guard withinOfferBudget(replacing: existing, adding: data.count) else {
                    rejectOffer(code: "EFBIG:offer too large")
                    return false
                }
                offerData[index] = data
            }
        }
        return generation == offerGeneration
    }

    private func beginDrag(with offer: KittyDnDDragOffer) {
        let result = dragHost?.beginDrag(offer) ?? .failed
        switch result {
        case .started:
            // A native drag we started is now running: a drop that lands on this
            // same session is a self-drag and its data reads must be refused (EPERM).
            selfDragInProgress = true
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "OK"))
        case .gestureGone:
            // The user let go before the program committed. Spec: reply EPERM when
            // the drag gesture has already been terminated.
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EPERM:drag gesture ended"))
            cleanupRemoteDragTempDir()
            resetOfferInProgress()
        case .failed:
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:could not start drag"))
            cleanupRemoteDragTempDir()
            resetOfferInProgress()
        }
    }

    /// Fetch the offered files from the remote program via t=k into a temp dir,
    /// then drag those local copies. The terminal requests only the top-level
    /// uri-list entries; the program pushes directory children unsolicited, which
    /// KittyDnDRemoteDragFetch assembles.
    private func beginRemoteFileDrag(uriListIndex: Int) async {
        // The start is no longer pending once we return (we either begin the drag,
        // which sets selfDragInProgress, or bail); clear the idempotency guard.
        defer { startingDrag = false }
        let generation = offerGeneration
        // Pre-sending is optional: the program may have deferred the uri-list (or
        // other MIMEs) expecting us to pull them. Do that before reading the list.
        let missing = offerMimeTypes.indices.filter { offerData[$0] == nil }
        guard await pullDeferredOfferData(missing, generation: generation) else {
            return
        }
        // Discard any temp dir from a prior build.
        cleanupRemoteDragTempDir()
        let names = Self.uriListNames(offerData[uriListIndex])
        guard !names.isEmpty else {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EINVAL:no files"))
            resetOfferInProgress()
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iterm2-kittydnd-\(UUID().uuidString)")

        var fetchRef: KittyDnDRemoteDragFetch?
        let outcome: KittyDnDRemoteDragFetch.Outcome = await withCheckedContinuation { continuation in
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
        let localURLs: [URL]
        switch outcome {
        case .success(let urls) where !urls.isEmpty:
            localURLs = urls
        case .success:
            // Nothing usable (e.g. all symlinks).
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:no usable files"))
            Self.removeItemOffMainThread(tempDir)
            resetOfferInProgress()
            return
        case .failure(let code):
            // A resource-limit breach (EMFILE), stall, or IO error: report the code.
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: code))
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

    /// Whether we are assembling an offer that has not yet turned into a live
    /// drag (i.e. we have not sent t=E ; OK). Solicited data replies to our
    /// t=e:x=5 are expected here; any UNSOLICITED t=e/t=E is a protocol error.
    private var offerBeingAssembled: Bool {
        return isOfferingDrags && !selfDragInProgress
    }

    private func handleDragDataReply(_ message: KittyDnDMessage) {
        // The program's reply to a t=e:x=5 lazy data request: t=e:y=idx;data.
        if let index = message.intValue("y"),
           let completion = pendingDataRequests.removeValue(forKey: index) {
            completion(message.dataPayload)
            return
        }
        // An unsolicited t=e before the drag started is a protocol error (spec:
        // "must respond with t=E ; EINVAL and abort the drag").
        if offerBeingAssembled {
            rejectOffer(code: "EINVAL:unexpected t=e")
        }
    }

    private func handleDragStatus(_ message: KittyDnDMessage) {
        // t=E from the program. y=-1 cancels the whole drag; otherwise it is an
        // error reply to a lazy data request for that MIME index.
        guard let y = message.intValue("y") else {
            // A t=E with no y is a generic client error (spec: "If any error
            // occurs in the client while reading the data"). During a remote fetch
            // OR a local deferred-data pull it means the program failed to provide
            // its data, so abort now instead of leaving the user holding a dead
            // drag (there is no timeout on the local pull) until a prompt reset.
            if remoteDragFetch != nil || startingDrag {
                resetOfferInProgress()
            }
            return
        }
        if y == -1 {
            dragHost?.cancelDrag()
            resetOfferInProgress()
        } else if let completion = pendingDataRequests.removeValue(forKey: y) {
            completion(nil)
        } else if offerBeingAssembled {
            // Unsolicited t=E:y before the drag started: protocol error, abort.
            rejectOffer(code: "EINVAL:unexpected t=E")
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

    /// Like sendChunkedData but emits each chunk as it is encoded rather than
    /// materializing the whole base64 array first, so only one chunk's encoding is
    /// resident at a time. With a memory-mapped `data` the raw bytes are OS-paged
    /// too, keeping the footprint of serving a huge dropped file bounded. Rechecks
    /// the drop generation between chunks so a completed/superseded drop stops the
    /// stream promptly.
    private func sendChunkedDataStreaming(baseMetadata: [String: String], data: Data,
                                          generation: Int) async {
        var metadata = baseMetadata
        metadata["t"] = "r"
        let windowSize = KittyDnDChunker.maxRawChunkSize
        var offset = 0
        var sinceYield = 0
        while offset < data.count {
            guard generation == acceptGeneration else { return }
            let end = min(offset + windowSize, data.count)
            var chunk = metadata
            chunk["m"] = "1"
            send(KittyDnDMessage(metadata: chunk, dataPayload: data.subdata(in: offset..<end)))
            offset = end
            // Yield periodically so a huge file does not monopolize the main actor
            // (freezing the UI) and so the generation check above can actually fire
            // after a reset/cancel that happened during the transfer.
            sinceYield += 1
            if sinceYield >= 256 {
                sinceYield = 0
                await Task.yield()
            }
        }
        guard generation == acceptGeneration else { return }
        // End of data: empty payload with m=0.
        var terminator = metadata
        terminator["m"] = "0"
        send(KittyDnDMessage(metadata: terminator, rawPayload: ""))
    }

    /// Stable key for an entry request's addressing keys (x / y / Y), for
    /// in-flight dedup.
    private static func entryRequestKey(_ metadata: [String: String]) -> String {
        return ["Y", "x", "y"].map { "\($0)=\(metadata[$0] ?? "")" }.joined(separator: ":")
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
                // The listing must contain only transferable entries (regular
                // files, symlinks, directories); a special file (socket, FIFO)
                // would otherwise be listed, and a conforming client requesting it
                // gets EINVAL and aborts the whole drop.
                let typeKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
                                                     .isDirectoryKey]
                let children = try FileManager.default
                    .contentsOfDirectory(at: url, includingPropertiesForKeys: Array(typeKeys))
                    .filter { child in
                        guard let v = try? child.resourceValues(forKeys: typeKeys) else {
                            return false
                        }
                        return v.isSymbolicLink == true || v.isDirectory == true
                            || v.isRegularFile == true
                    }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                return .directory(children)
            }
            guard values.isRegularFile == true else {
                throw EntryTypeError()
            }
            // Memory-map so a huge file is not loaded wholly into RAM; the streamed
            // send then base64-encodes it a window at a time.
            return .regularFile(try Data(contentsOf: url, options: .mappedIfSafe))
        }.value
    }

    // MARK: - Machine id

    // A machine id is `version:printable-chars`. We recognize ANY numeric version
    // (not just "1:") so that a future version is still treated as a machine id: a
    // "2:..." id we don't understand differs from our "1:..." id and so is treated
    // as a different machine (spec: "If the terminal sees a version it does not
    // understand, it must assume that the machine id does not match"), and it is
    // kept out of the MIME list. A MIME type ("text/plain") never has this shape.
    private static func isMachineIDToken(_ token: String) -> Bool {
        guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else {
            return false
        }
        let version = token[token.startIndex..<colon]
        // ASCII decimal digits only: a machine-id version is a plain integer, and
        // Character.isNumber would also accept non-ASCII digit scalars.
        return version.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
