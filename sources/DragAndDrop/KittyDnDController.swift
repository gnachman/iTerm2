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
    private let reassembler = KittyDnDChunkReassembler()

    // Accept-drop state.
    private(set) var isAcceptingDrops = false
    private var acceptedMimeTypes: [String] = []
    private var peerMachineID: String?
    private var currentDrop: KittyDnDDropData?

    // Open directory handles for the cross-machine traversal, mapping a handle to
    // that directory's ordered child URLs. Handles start at 2 (0 and 1 are
    // reserved by the protocol for the file/symlink type indicators).
    private var directoryHandles: [Int: [URL]] = [:]
    private var nextDirectoryHandle = 2

    // Offer / drag-out state.
    private(set) var isOfferingDrags = false
    private var offerMimeTypes: [String] = []
    private var offerOperations = 0
    private var offerData: [Int: Data] = [:]
    private var offerImage: KittyDnDDragImage?
    // Completion handlers for outstanding lazy data requests, keyed by 0-based
    // MIME index (the program answers a t=e:x=5 request with t=e:y=idx;data).
    private var pendingDataRequests: [Int: (Data?) -> Void] = [:]

    init(ourMachineID: String,
         endpoint: KittyDnDEndpoint,
         dragHost: KittyDnDDragHost? = nil,
         report: @escaping (String) -> Void) {
        self.ourMachineID = ourMachineID
        self.endpoint = endpoint
        self.dragHost = dragHost
        self.report = report
    }

    /// Whether the peer is on a different machine than us, per the machine-id
    /// handshake. Determines the cross-machine (X=1) behavior.
    private var peerIsRemote: Bool {
        return KittyDnDMachineID.isRemote(theirID: peerMachineID, ourID: ourMachineID)
    }

    // MARK: - Inbound OSC 72

    /// Feed one OSC 72 sequence's raw content (everything after "72;"). Chunked
    /// messages are reassembled internally.
    func handleInboundSequence(_ content: String) {
        guard let message = reassembler.accept(content) else {
            return
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
            // The program's acceptance response to a move; nothing to do here in
            // the accept-drop path (the AppKit adapter reads the chosen operation
            // in a later phase).
            break
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
        if message.intValue("x") == 2 {
            isAcceptingDrops = false
            return
        }
        isAcceptingDrops = true
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
        acceptedMimeTypes = tokens.filter { !Self.isMachineIDToken($0) }
    }

    // MARK: - AppKit drag events (accept-drop)

    func dragEntered(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                     operations: Int, mimeTypes: [String]) {
        guard isAcceptingDrops else { return }
        // A new drag cycle: forget any drop from the previous cycle so a stray
        // t=r cannot read stale data.
        currentDrop = nil
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
        sendMoveOrDrop(type: "m", cellX: -1, cellY: -1, pixelX: 0, pixelY: 0,
                       operations: 0, mimeTypes: nil)
    }

    func performDrop(cellX: Int, cellY: Int, pixelX: Int, pixelY: Int,
                     operations: Int, drop: KittyDnDDropData) {
        guard isAcceptingDrops else { return }
        currentDrop = drop
        sendMoveOrDrop(type: "M", cellX: cellX, cellY: cellY, pixelX: pixelX,
                       pixelY: pixelY, operations: operations, mimeTypes: drop.mimeTypes)
    }

    // MARK: - Data request handling

    private func handleDataRequest(_ message: KittyDnDMessage) {
        // A directory-handle request is part of the cross-machine traversal and
        // is not tied to the MIME index.
        if let handle = message.intValue("Y") {
            handleDirectoryRequest(handle: handle, message: message)
            return
        }
        let requestedIndex = message.intValue("x")
        guard let index = requestedIndex,
              let drop = currentDrop,
              index >= 1, index <= drop.mimeTypes.count else {
            sendDataError(index: requestedIndex, code: "EINVAL")
            return
        }
        let mime = drop.mimeTypes[index - 1]

        // A sub-index (y) request is the cross-machine path: the program asks for
        // one file entry within the uri-list so it can pull the actual bytes.
        if let entryIndex = message.intValue("y") {
            guard mime == "text/uri-list",
                  entryIndex >= 1, entryIndex <= drop.fileURLs.count else {
                sendError(baseMetadata: ["x": String(index), "y": String(entryIndex)],
                          code: "EINVAL")
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
            sendError(baseMetadata: ["Y": String(handle), "x": String(num)], code: "EINVAL")
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
        Task { @MainActor in
            do {
                let entry = try await Self.readEntryOffMainThread(url)
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
            } catch {
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
        if endpoint.canMaterializeFiles {
            // Tier 2: a conductor is present, so the program is on the remote
            // host (ground truth, independent of whether it sent a machine id).
            // Materialize each file on the program's host so the URIs it receives
            // are real local paths there. No cross-machine flag.
            //
            // On partial failure (a later file fails after earlier ones were
            // written) we report EIO and leave any already-written files in the
            // endpoint's temp area; they are harmless and best-effort cleanup is
            // not worth a round trip here.
            Task { @MainActor in
                do {
                    var uris: [String] = []
                    for url in drop.fileURLs {
                        let contents = try await Self.readFileOffMainThread(url)
                        let remotePath = try await endpoint.materializeFile(
                            named: url.lastPathComponent, contents: contents)
                        uris.append("file://\(remotePath)")
                    }
                    sendData(index: index,
                             data: Data(uris.joined(separator: "\r\n").utf8),
                             extraMetadata: [:])
                } catch {
                    sendDataError(index: index, code: "EIO")
                }
            }
            return
        }

        // Tier 1 (local) or Tier 3 (remote with no conductor): return the local
        // file URIs. For Tier 3 they are foreign to the program, flagged X=1.
        let uris = drop.fileURLs.map { $0.absoluteString }
        let extra = peerIsRemote ? ["X": "1"] : [:]
        sendData(index: index,
                 data: Data(uris.joined(separator: "\r\n").utf8),
                 extraMetadata: extra)
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
            // outstanding data-request completions rather than leaking them.
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
            // Negative index: a drag thumbnail image.
            offerImage = KittyDnDDragImage(format: message.intValue("y") ?? 0,
                                           width: message.intValue("X") ?? 0,
                                           height: message.intValue("Y") ?? 0,
                                           data: data)
        } else {
            offerData[index] = data
        }
    }

    private func handleStartDrag(_ message: KittyDnDMessage) {
        // t=P:x=-1 starts the drag; other x values change the drag image, which
        // we do not support yet.
        guard message.intValue("x") == -1 else {
            return
        }
        let offer = KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                      data: offerData,
                                      operations: offerOperations,
                                      image: offerImage)
        guard let dragHost, dragHost.beginDrag(offer) else {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:could not start drag"))
            resetOfferInProgress()
            return
        }
        send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "OK"))
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
        offerMimeTypes = []
        offerOperations = 0
        offerData = [:]
        offerImage = nil
        for (_, completion) in pendingDataRequests {
            completion(nil)
        }
        pendingDataRequests = [:]
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
        report(message.serialized())
    }

    // MARK: - File IO

    /// Read a local file off the main thread so a large dropped file does not
    /// block the UI while it is read into memory.
    private static func readFileOffMainThread(_ url: URL) async throws -> Data {
        return try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
    }

    /// One filesystem entry as needed by the cross-machine transfer.
    private enum FilesystemEntry {
        case regularFile(Data)
        case symlink(String)        // link target
        case directory([URL])       // sorted child URLs
    }

    /// Classify and read `url` off the main thread. A symlink is reported as a
    /// symlink (not followed); a directory yields its sorted children.
    private static func readEntryOffMainThread(_ url: URL) async throws -> FilesystemEntry {
        return try await Task.detached(priority: .utility) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
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
