//
//  KittyDnDRemoteDragFetch.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Collects the files a remote program pushes when the terminal drags that
//  program's offered files OUT to another app. The terminal cannot read the
//  program's file:// URIs (they live on the remote host), so it fetches the
//  bytes over the pty and materializes local temp copies to drag.
//
//  Per the spec, the terminal requests ONLY the top-level text/uri-list entries
//  (t=k:x=idx). For a directory entry the program PUSHES the directory listing
//  (X=handle, a null-separated child list) and then every descendant UNSOLICITED
//  via Y=parent-handle:y=num escape codes: "Clients must send all children of
//  directories, recursively, terminals must not make requests for children of
//  directories, only for the entries from the text/uri-list." This collector
//  therefore never requests children; it receives the pushed tree and assembles
//  it, tracking how many entries are still outstanding so it knows when the whole
//  transfer is done.
//

import Foundation

@MainActor
final class KittyDnDRemoteDragFetch {
    /// Resource limits bounding a malicious or buggy program's push, so it cannot
    /// exhaust disk or memory. On breach the fetch is aborted (the spec allows a
    /// terminal to "impose resource limits ... if a limit is breached ... abort
    /// the drag").
    struct Limits {
        var maxEntries = 65_536
        var maxBytes = 2 * 1024 * 1024 * 1024
    }

    /// The result of a fetch. On failure the protocol error code lets the caller
    /// send the right t=E (EMFILE for a resource-limit breach, EIO otherwise).
    enum Outcome {
        case success([URL])
        case failure(code: String)
    }

    private let tempDir: URL
    private let topLevelNames: [String]
    private let send: (KittyDnDMessage) -> Void
    private let limits: Limits
    private let timeout: TimeInterval
    private var completion: ((Outcome) -> Void)?

    // Destination path for each 1-based top-level entry, and the local URL of
    // each one actually materialized (a file or a directory; a skipped symlink or
    // errored entry has none). The drag's uri-list is built from these in order.
    private var topLevelDest: [Int: URL] = [:]
    private var topLevelURL: [Int: URL] = [:]

    // Open directory handles the program declared (X=handle): the local dir the
    // handle maps to, and its ordered, sanitized child names (so a Y=handle:y=num
    // push resolves to a path).
    private var handleDir: [Int: URL] = [:]
    private var handleChildNames: [Int: [String]] = [:]

    // Entries requested/declared but whose data has not yet been fully received.
    private var pending = 0
    private var entryCount = 0
    private var totalBytes = 0
    private var finished = false
    // In-flight write/mkdir tasks. If the fetch finishes early (abort/timeout)
    // while a write is running, completion is deferred until these drain, so the
    // caller does not delete the temp dir out from under a write that would
    // recreate it (leaking the recreated tree).
    private var activeWrites = 0
    private var deferredResult: Outcome?
    // The pending idle-timeout, canceled and replaced on each unit of progress so
    // stale timers do not pile up during a large transfer.
    private var idleWorkItem: DispatchWorkItem?
    // Addressing keys of entries already accounted for, so a duplicate or
    // contradictory push (a second data push, or a data push plus a t=R error for
    // the same address) cannot decrement the outstanding count twice and finish
    // the drag with a truncated tree.
    private var seenSlots: Set<String> = []

    init(tempDir: URL,
         topLevelNames: [String],
         limits: Limits = Limits(),
         timeout: TimeInterval = 30,
         send: @escaping (KittyDnDMessage) -> Void,
         completion: @escaping (Outcome) -> Void) {
        self.tempDir = tempDir
        self.topLevelNames = topLevelNames
        self.limits = limits
        self.timeout = timeout
        self.send = send
        self.completion = completion
    }

    /// Request every top-level uri-list entry. Directory children arrive
    /// unsolicited afterward.
    func start() {
        guard !topLevelNames.isEmpty else {
            finish(.success([]))
            return
        }
        // Bound the top-level entry count BEFORE the fan-out below (one t=k request
        // and two URL allocations per entry). The maxEntries check in receive()
        // fires only after the fan-out, so without this a uri-list with millions of
        // entries would hang the main thread and balloon memory before any limit.
        guard topLevelNames.count <= limits.maxEntries else {
            finish(.failure(code: "EMFILE"))
            return
        }
        pending = topLevelNames.count
        for (offset, name) in topLevelNames.enumerated() {
            let idx = offset + 1
            // Each top-level entry lives in its own numbered subdirectory so two
            // entries with the same basename cannot overwrite each other.
            topLevelDest[idx] = tempDir
                .appendingPathComponent(String(idx))
                .appendingPathComponent(name)
            send(KittyDnDMessage(metadata: ["t": "k", "x": String(idx)]))
        }
        armIdleTimeout()
    }

    /// Note any inbound activity from the peer (including a chunk of a large file
    /// that has not completed a message yet) so the idle timeout does not fire on
    /// a healthy, steadily-progressing transfer.
    func noteActivity() {
        guard !finished else { return }
        armIdleTimeout()
    }

    /// (Re)arm the idle timeout. It aborts the fetch only if `timeout` seconds
    /// pass with NO further progress, so a steadily-progressing large transfer is
    /// not killed by an absolute deadline while a genuinely stalled peer still is.
    private func armIdleTimeout() {
        idleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.finished else { return }
            self.finish(.failure(code: "EIO:remote drag-out stalled"))
        }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    /// A t=k data push from the program: a regular file (no X, or X=0), a symlink
    /// (X=1, skipped), or a directory (X=handle, a null-separated child list).
    func receive(_ message: KittyDnDMessage) {
        guard !finished else { return }
        entryCount += 1
        if entryCount > limits.maxEntries {
            finish(.failure(code: "EMFILE"))
            return
        }
        // Charge every payload (directory listings included) against the byte
        // budget so a giant listing cannot exhaust memory.
        let payload = message.dataPayload ?? Data()
        totalBytes += payload.count
        if totalBytes > limits.maxBytes {
            finish(.failure(code: "EMFILE"))
            return
        }
        guard let dest = resolveDest(message), let slot = slotKey(message) else {
            // An entry we did not expect (unknown handle / out-of-range child).
            // Ignore it without touching the outstanding count.
            return
        }
        // Ignore a duplicate push for a slot we already accounted for.
        guard seenSlots.insert(slot).inserted else { return }
        let topLevelIndex = topLevelIndex(of: message)
        let typeFlag = message.metadata["X"].flatMap(Int.init) ?? 0

        // X: absent or 0 = regular file, 1 = symlink, ANY OTHER integer (including
        // negatives) = a directory handle. The spec defines a handle as "an
        // arbitrary integer (handle) other than 0 or 1"; kitty emits unsigned ones
        // but a conforming client may use negatives.
        switch typeFlag {
        case 0:
            // Regular file.
            recordMaterialized(dest, for: message)
            performWrite({
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try payload.write(to: dest)
            }, onSuccess: { self.completeOne() },
               onFailure: { self.entryFailed(topLevelIndex: topLevelIndex) })
        case 1:
            // Symlink: skip entirely. Its target is attacker-controlled and
            // meaningless here, and following it at the drop destination could
            // exfiltrate a local file.
            completeOne()
        default:
            // Directory: register its children as newly outstanding, then create
            // the directory. The children arrive later via Y=handle:y=num.
            let names = payload.split(separator: 0)
                .map { KittyDnDController.sanitizeComponent(String(decoding: $0, as: UTF8.self)) }
            // Bound the declared child count so a program cannot inflate the
            // outstanding set without bound.
            if pending + names.count > limits.maxEntries {
                finish(.failure(code: "EMFILE"))
                return
            }
            handleDir[typeFlag] = dest
            handleChildNames[typeFlag] = names
            recordMaterialized(dest, for: message)
            pending += names.count
            performWrite({
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            }, onSuccess: { self.completeOne() },
               onFailure: { self.entryFailed(topLevelIndex: topLevelIndex) })
        }
    }

    /// Run a filesystem write off the main thread while tracking it, so an early
    /// finish waits for it before the temp dir is removed.
    private func performWrite(_ block: @escaping @Sendable () throws -> Void,
                              onSuccess: @escaping () -> Void,
                              onFailure: @escaping () -> Void) {
        activeWrites += 1
        Task { @MainActor in
            let ok = await KittyDnDController.writeOffMainThread(block)
            self.activeWrites -= 1
            if self.finished {
                self.deliverDeferredIfDrained()
                return
            }
            if ok { onSuccess() } else { onFailure() }
        }
    }

    /// A per-entry error for an outstanding entry: skip it (materialize nothing)
    /// and count it done, rather than failing the whole drag. Returns true if the
    /// message addressed a fetch slot (so the caller does not also route it
    /// elsewhere); a message not addressed to this fetch returns false and is
    /// handled by the caller. The spec's client error form is t=E ; the terminal
    /// also tolerates t=R (a terminal-to-client type) as an extension.
    @discardableResult
    func receiveError(_ message: KittyDnDMessage) -> Bool {
        guard !finished, resolveDest(message) != nil, let slot = slotKey(message) else {
            return false
        }
        // Addressed to a known slot: consume it. A duplicate (already-seen slot) is
        // still "ours" and must not fall through to the generic drag-status path.
        guard seenSlots.insert(slot).inserted else { return true }
        entryFailed(topLevelIndex: topLevelIndex(of: message))
        return true
    }

    /// Abandon the fetch (a reset or a superseding offer). The caller discards the
    /// result on a generation mismatch, so the code here is not surfaced.
    func abort() {
        finish(.failure(code: "EIO"))
    }

    // MARK: - Private

    private func resolveDest(_ message: KittyDnDMessage) -> URL? {
        if let parent = message.intValue("Y"), let num = message.intValue("y") {
            guard let dir = handleDir[parent], let names = handleChildNames[parent],
                  num >= 1, num <= names.count else {
                return nil
            }
            return dir.appendingPathComponent(names[num - 1])
        }
        if let idx = message.intValue("x"), let dest = topLevelDest[idx] {
            return dest
        }
        return nil
    }

    /// A stable key identifying the entry a message addresses, for dedup. Built
    /// from the PARSED integers (the same values resolveDest uses), so that two
    /// spellings of the same address (e.g. x=1 and x=01) map to one slot and
    /// cannot both pass the seen-set guard and double-count.
    private func slotKey(_ message: KittyDnDMessage) -> String? {
        if let parent = message.intValue("Y"), let num = message.intValue("y") {
            return "Y=\(parent):y=\(num)"
        }
        if let idx = message.intValue("x") {
            return "x=\(idx)"
        }
        return nil
    }

    /// The 1-based top-level index a message addresses, or nil for a child.
    private func topLevelIndex(of message: KittyDnDMessage) -> Int? {
        return message.metadata["Y"] == nil ? message.intValue("x") : nil
    }

    /// Record the local URL for a TOP-LEVEL entry (the drag offers top-level
    /// items; a directory's children live inside it and are not listed directly).
    private func recordMaterialized(_ url: URL, for message: KittyDnDMessage) {
        if message.metadata["Y"] == nil, let idx = message.intValue("x") {
            topLevelURL[idx] = url
        }
    }

    /// An entry's I/O failed: drop it from the drag (so we do not offer a path
    /// that was never written) and count it done, rather than aborting the whole
    /// transfer over one bad entry.
    private func entryFailed(topLevelIndex idx: Int?) {
        if let idx {
            topLevelURL.removeValue(forKey: idx)
        }
        completeOne()
    }

    private func completeOne() {
        guard !finished else { return }
        pending -= 1
        if pending <= 0 {
            let ordered = topLevelNames.indices.compactMap { topLevelURL[$0 + 1] }
            finish(.success(ordered))
        }
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        idleWorkItem?.cancel()
        idleWorkItem = nil
        if activeWrites > 0 {
            // Wait for in-flight writes so the caller does not remove the temp dir
            // while a write is still creating files in it.
            deferredResult = outcome
            return
        }
        deliver(outcome)
    }

    private func deliverDeferredIfDrained() {
        guard activeWrites == 0, let outcome = deferredResult else { return }
        deferredResult = nil
        deliver(outcome)
    }

    private func deliver(_ outcome: Outcome) {
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
    }
}
