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

    private let tempDir: URL
    private let topLevelNames: [String]
    private let send: (KittyDnDMessage) -> Void
    private let limits: Limits
    private let timeout: TimeInterval
    private var completion: (([URL]?) -> Void)?

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
    // Bumped on each unit of progress; the idle timeout only fires if it is
    // unchanged after `timeout` seconds.
    private var activityToken = 0
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
         completion: @escaping ([URL]?) -> Void) {
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
            finish([])
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

    /// (Re)arm the idle timeout. It aborts the fetch only if `timeout` seconds
    /// pass with NO further progress, so a steadily-progressing large transfer is
    /// not killed by an absolute deadline while a genuinely stalled peer still is.
    private func armIdleTimeout() {
        activityToken += 1
        let token = activityToken
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.finished, token == self.activityToken else { return }
            self.finish(nil)
        }
    }

    /// A t=k data push from the program: a regular file (no X, or X=0), a symlink
    /// (X=1, skipped), or a directory (X=handle, a null-separated child list).
    func receive(_ message: KittyDnDMessage) {
        guard !finished else { return }
        entryCount += 1
        if entryCount > limits.maxEntries {
            finish(nil)
            return
        }
        // Charge every payload (directory listings included) against the byte
        // budget so a giant listing cannot exhaust memory.
        let payload = message.dataPayload ?? Data()
        totalBytes += payload.count
        if totalBytes > limits.maxBytes {
            finish(nil)
            return
        }
        guard let dest = resolveDest(message), let slot = slotKey(message) else {
            // An entry we did not expect (unknown handle / out-of-range child).
            // Ignore it without touching the outstanding count.
            return
        }
        // Ignore a duplicate push for a slot we already accounted for.
        guard seenSlots.insert(slot).inserted else { return }
        armIdleTimeout()   // progress: reset the stall deadline
        let topLevelIndex = topLevelIndex(of: message)
        let typeFlag = message.metadata["X"].flatMap(Int.init) ?? 0

        switch typeFlag {
        case 1:
            // Symlink: skip entirely. Its target is attacker-controlled and
            // meaningless here, and following it at the drop destination could
            // exfiltrate a local file.
            completeOne()
        case 2...:
            // Directory: register its children as newly outstanding, then create
            // the directory. The children arrive later via Y=handle:y=num.
            let names = payload.split(separator: 0)
                .map { KittyDnDController.sanitizeComponent(String(decoding: $0, as: UTF8.self)) }
            // Bound the declared child count so a program cannot inflate the
            // outstanding set without bound.
            if pending + names.count > limits.maxEntries {
                finish(nil)
                return
            }
            handleDir[typeFlag] = dest
            handleChildNames[typeFlag] = names
            recordMaterialized(dest, for: message)
            pending += names.count
            Task { @MainActor in
                let ok = await KittyDnDController.writeOffMainThread {
                    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                }
                guard !self.finished else { return }
                if ok {
                    self.completeOne()   // the directory itself is now materialized
                } else {
                    self.entryFailed(topLevelIndex: topLevelIndex)
                }
            }
        default:
            // Regular file.
            recordMaterialized(dest, for: message)
            Task { @MainActor in
                let ok = await KittyDnDController.writeOffMainThread {
                    try FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try payload.write(to: dest)
                }
                guard !self.finished else { return }
                if ok {
                    self.completeOne()
                } else {
                    self.entryFailed(topLevelIndex: topLevelIndex)
                }
            }
        }
    }

    /// A t=R error for an outstanding entry: skip it (materialize nothing) and
    /// count it done, rather than failing the whole drag.
    func receiveError(_ message: KittyDnDMessage) {
        guard !finished, resolveDest(message) != nil, let slot = slotKey(message) else { return }
        guard seenSlots.insert(slot).inserted else { return }
        armIdleTimeout()
        entryFailed(topLevelIndex: topLevelIndex(of: message))
    }

    /// Abandon the fetch (a reset or a superseding offer). Resumes the caller with
    /// nil so it can clean up.
    func abort() {
        finish(nil)
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

    /// A stable key identifying the entry a message addresses, for dedup.
    private func slotKey(_ message: KittyDnDMessage) -> String? {
        if let parent = message.metadata["Y"], let num = message.metadata["y"] {
            return "Y=\(parent):y=\(num)"
        }
        if let idx = message.metadata["x"] {
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
            finish(ordered)
        }
    }

    private func finish(_ urls: [URL]?) {
        guard !finished else { return }
        finished = true
        let completion = self.completion
        self.completion = nil
        completion?(urls)
    }
}
