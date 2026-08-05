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

    // Outstanding t=k remote-file fetches (dragging a remote program's files
    // out), keyed by the request's addressing keys. The program answers a
    // t=k request with the file bytes / symlink target / directory listing.
    private var pendingRemoteFetches: [String: (KittyDnDMessage?) -> Void] = [:]
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
        peerMachineID = nil
        currentDrop = nil
        directoryHandles.removeAll()
        nextDirectoryHandle = 2
        isOfferingDrags = false
        cleanupRemoteDragTempDir()
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
        case "k":
            // The program's response to a t=k remote-file fetch (drag-out).
            resolveRemoteFetch(message, failed: false)
        case "R":
            // An error reply to an outstanding t=k fetch, if any.
            resolveRemoteFetch(message, failed: true)
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
        // t=r cannot read stale data, including open directory handles that
        // pointed into the previous drop's files.
        currentDrop = nil
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
        // Return the local file URIs. For a remote drop they are foreign to the
        // program, so flag X=1; the program then pulls each file's bytes in-band
        // by sub-index (t=r:x=idx:y=entry). For a local drop the paths are
        // directly usable and no flag is set.
        let uris = drop.fileURLs.map { $0.absoluteString }
        let extra = isRemoteDrop ? ["X": "1"] : [:]
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
        // If the program is remote and offering files, its file:// URIs are not
        // readable here. Fetch each one from the program via t=k, materialize
        // copies in a temp directory, and drag those local copies. Otherwise the
        // offered URIs are local and we drag them directly.
        if isRemoteOffer, let uriListIndex = offerMimeTypes.firstIndex(of: "text/uri-list") {
            Task { @MainActor in
                await self.beginRemoteFileDrag(uriListIndex: uriListIndex)
            }
            return
        }
        beginDrag(with: KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                          data: offerData,
                                          operations: offerOperations,
                                          image: offerImage))
    }

    private func beginDrag(with offer: KittyDnDDragOffer) {
        guard let dragHost, dragHost.beginDrag(offer) else {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:could not start drag"))
            cleanupRemoteDragTempDir()
            resetOfferInProgress()
            return
        }
        send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "OK"))
    }

    /// Fetch the offered files from the remote program via t=k into a temp dir,
    /// then drag those local copies.
    private func beginRemoteFileDrag(uriListIndex: Int) async {
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
        var localURLs: [URL] = []
        for (offset, name) in names.enumerated() {
            // Each entry gets its own numbered subdirectory so two entries with
            // the same basename cannot overwrite each other.
            let dest = tempDir.appendingPathComponent(String(offset + 1)).appendingPathComponent(name)
            let ok = await materializeRemoteEntry(request: ["x": String(offset + 1)], to: dest)
            guard generation == offerGeneration else {
                Self.removeItemOffMainThread(tempDir)   // superseded; discard our work
                return
            }
            if !ok {
                send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:fetch failed"))
                Self.removeItemOffMainThread(tempDir)
                resetOfferInProgress()
                return
            }
            // A refused entry (e.g. an unsafe symlink) writes nothing; skip it.
            if FileManager.default.fileExists(atPath: dest.path) {
                localURLs.append(dest)
            }
        }
        guard generation == offerGeneration else {
            Self.removeItemOffMainThread(tempDir)
            return
        }
        guard !localURLs.isEmpty else {
            send(KittyDnDMessage(metadata: ["t": "E"], textPayload: "EIO:no usable files"))
            Self.removeItemOffMainThread(tempDir)
            resetOfferInProgress()
            return
        }
        remoteDragTempDir = tempDir
        // Replace the uri-list in the offer with the local temp copies.
        var data = offerData
        data[uriListIndex] = Data(localURLs.map { $0.absoluteString }.joined(separator: "\r\n").utf8)
        beginDrag(with: KittyDnDDragOffer(mimeTypes: offerMimeTypes,
                                          data: data,
                                          operations: offerOperations,
                                          image: offerImage))
    }

    /// Fetch one remote entry (identified by `request`, a t=k addressing dict)
    /// and write it to `dest`. Returns false only on a hard failure (a refused
    /// entry, e.g. an unsafe symlink, returns true but writes nothing).
    private func materializeRemoteEntry(request: [String: String], to dest: URL) async -> Bool {
        guard let message = await fetchRemoteEntry(request) else {
            return false
        }
        let payload = message.dataPayload ?? Data()
        // Type: absent or 0 = regular file, 1 = symlink, >=2 = directory handle.
        let typeFlag = message.metadata["X"].flatMap(Int.init) ?? 0
        switch typeFlag {
        case 1:
            // The symlink target is controlled by the untrusted remote and is
            // meaningless on this machine; a symlink into the dragged tree could
            // also exfiltrate a local file if the drop destination follows it.
            // Skip symlinks entirely.
            return true
        case 2...:
            let created = await Self.writeOffMainThread {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            }
            guard created else { return false }
            let childNames = payload.split(separator: 0)
                .map { Self.sanitizeComponent(String(decoding: $0, as: UTF8.self)) }
            for (offset, childName) in childNames.enumerated() {
                let ok = await materializeRemoteEntry(
                    request: ["Y": String(typeFlag), "y": String(offset + 1)],
                    to: dest.appendingPathComponent(childName))
                if !ok { return false }
            }
            return true
        default:
            // Regular file (X absent or 0).
            return await Self.writeOffMainThread {
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try payload.write(to: dest)
            }
        }
    }

    /// Send one t=k request and await the reassembled response (nil on error).
    private func fetchRemoteEntry(_ request: [String: String]) async -> KittyDnDMessage? {
        let key = Self.remoteFetchKey(request)
        return await withCheckedContinuation { (continuation: CheckedContinuation<KittyDnDMessage?, Never>) in
            pendingRemoteFetches[key]?(nil)   // fail any stale fetch for this key
            pendingRemoteFetches[key] = { continuation.resume(returning: $0) }
            var metadata = request
            metadata["t"] = "k"
            send(KittyDnDMessage(metadata: metadata))
        }
    }

    private func resolveRemoteFetch(_ message: KittyDnDMessage, failed: Bool) {
        let key = Self.remoteFetchKey(message.metadata)
        guard let completion = pendingRemoteFetches.removeValue(forKey: key) else {
            return
        }
        completion(failed ? nil : message)
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

    private static func removeItemOffMainThread(_ url: URL) {
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
        offerMimeTypes = []
        offerOperations = 0
        offerData = [:]
        offerImage = nil
        for (_, completion) in pendingDataRequests {
            completion(nil)
        }
        pendingDataRequests = [:]
        for (_, completion) in pendingRemoteFetches {
            completion(nil)
        }
        pendingRemoteFetches = [:]
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
    private static func sanitizeComponent(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "item"
        }
        return cleaned
    }

    private static func remoteFetchKey(_ metadata: [String: String]) -> String {
        if let parent = metadata["Y"], let child = metadata["y"] {
            return "Y=\(parent):y=\(child)"
        }
        if let index = metadata["x"] {
            return "x=\(index)"
        }
        return ""
    }

    private static func writeOffMainThread(_ block: @escaping @Sendable () throws -> Void) async -> Bool {
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
        report(message.serialized())
    }

    // MARK: - File IO

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
