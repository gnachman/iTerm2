//
//  Conductor+IT2.swift
//  iTerm2SharedARC
//
//  Demultiplexes the remote it2 CLI proxy. framer.py accepts unix-socket
//  connections from the remote `it2.py` and relays each one to iTerm2 as
//  "%it2 <connid> open|data <base64>|close" conductor frames (see SSH_IT2 /
//  VT100ConductorParser). This reconstructs it2.py's length-prefixed wire
//  protocol per connection, runs the embedded it2 command tree in-process
//  through the API server, and streams stdout/stderr/exit back down.
//
//  See OtherResources/it2.py for the client side of the wire protocol and
//  sources/API/iTermInProcessIt2.h for the in-process runner.
//

import Foundation

// Compare two strings' UTF-8 bytes for equality without a byte-position-dependent early exit,
// for security tokens (the it2 HELLO nonce). The actual comparison uses timingsafe_bcmp -- the
// platform's maintained constant-time primitive -- rather than a hand-rolled loop, whose data
// independence a high-level optimizer gives no guarantee of preserving. (The Array(utf8)
// conversion is not itself constant-time, but the per-byte comparison an attacker would time
// is.) The length is not secret -- the nonce is a fixed-width hex string -- so an early length
// check is fine, and timingsafe_bcmp requires equal-length buffers anyway.
func it2ConstantTimeEqual(_ a: String, _ b: String) -> Bool {
    let ab = Array(a.utf8)
    let bb = Array(b.utf8)
    guard ab.count == bb.count, !ab.isEmpty else {
        return ab.isEmpty && bb.isEmpty
    }
    return ab.withUnsafeBytes { ap in
        bb.withUnsafeBytes { bp in
            timingsafe_bcmp(ap.baseAddress, bp.baseAddress, ap.count) == 0
        }
    }
}

// The it2-over-ssh proxy state that must travel together across an SSH recovery. Grouped
// into one value so a reconnect copies a single value (one adopt assignment, one
// ConductorRecovery field, one init(recovery:) assignment) and a future field touches
// only this struct -- rather than five hand-synchronized carriers where omitting one
// silently reverts the field to nil after recovery (a lost grant or a nonce that fails
// every HELLO). `nonce` authenticates incoming it2.py HELLOs; `socketPath` is the remote
// unix socket; `authorized` is the user's per-connection API grant.
struct IT2ProxyState: Equatable {
    // The persisted core. Synthesized Codable, so whether a field is saved is answered by the
    // TYPE (add a persistent field here and it is encoded/decoded automatically) rather than by
    // remembering to edit a CodingKeys allowlist. On-disk shape is {nonce, socketPath,
    // authorized}, unchanged from before this split (see IT2ProxyState's Codable below, which
    // just delegates to this core).
    struct Persisted: Codable, Equatable {
        var nonce: String?
        var socketPath: String?
        var authorized: Bool?
    }
    var persisted: Persisted

    // Whether framer's most recent it2Listen actually bound the socket. Gates it2ProxyActive
    // (the "Remote host can control iTerm2" menu). A TRANSIENT runtime flag: it lives OUTSIDE
    // `persisted`, so it is carried by value across an in-process SSH recovery (adopt ->
    // ConductorRecovery -> init(recovery:)) but is never written to disk. On state restoration
    // the framer is relaunched and it2Listen re-runs, re-establishing it from that status
    // rather than restoring it stale. That it is not persisted is now structural (this field
    // is simply not part of `persisted`), not a CodingKeys allowlist to keep in sync.
    var listenSucceeded: Bool

    init(nonce: String? = nil, socketPath: String? = nil, authorized: Bool? = nil,
         listenSucceeded: Bool = false) {
        self.persisted = Persisted(nonce: nonce, socketPath: socketPath, authorized: authorized)
        self.listenSucceeded = listenSucceeded
    }

    // Flat accessors so call sites read/write it2Proxy.nonce/socketPath/authorized as before.
    var nonce: String? { get { persisted.nonce } set { persisted.nonce = newValue } }
    var socketPath: String? { get { persisted.socketPath } set { persisted.socketPath = newValue } }
    var authorized: Bool? { get { persisted.authorized } set { persisted.authorized = newValue } }
}

extension IT2ProxyState: Codable {
    // Persist only the core; `listenSucceeded` is transient and resets to its default on
    // decode. Delegating to Persisted (not a manual key list) keeps "what is saved" defined by
    // the Persisted type.
    init(from decoder: Decoder) throws {
        persisted = try Persisted(from: decoder)
        listenSucceeded = false
    }
    func encode(to encoder: Encoder) throws {
        try persisted.encode(to: encoder)
    }
}

// it2.py <-> demux frames: [1 byte type][4 byte big-endian length][payload].
private enum IT2FrameType {
    static let hello = UInt8(ascii: "H")   // up:   json {nonce, argv, cwd, term, isatty, cols, rows}
    static let cancel = UInt8(ascii: "C")  // up:   empty (remote Ctrl-C)
    static let stdout = UInt8(ascii: "O")  // down: raw bytes
    static let stderr = UInt8(ascii: "E")  // down: raw bytes
    static let exit = UInt8(ascii: "X")    // down: json {code}, last frame
}

// Terminal context captured by the remote client at invocation time, parsed from HELLO
// and delivered to the RunFunction (verified by ConductorIT2DemuxTests). The production
// runner does not yet forward it on to the embedded command -- terminal sizing / TERM /
// isatty for it2-over-ssh is future work -- so nothing downstream consumes it today.
struct IT2ClientContext {
    var cwd: String
    var term: String
    var isatty: Bool
    var cols: Int
    var rows: Int
}

// A handle that stops an in-flight command (e.g. `monitor --follow`).
protocol IT2Cancellable: AnyObject {
    func cancel()
}

// Reconstructs and dispatches it2 RPC connections. Threading contract: everything that touches
// `connections` -- handle(), startCommand(), finish(), drainSinkQueue() -- is MAIN-thread only.
// The one exception is sendLine(): the injected `run` closure's stdout/stderr sinks call it
// directly on the runner's background queue (only `completion` is marshalled to main), so it
// must stay off-main-safe -- it only appends to the thread-safe sinkQueue and pokes the
// sinkFlusher, never touching `connections`. The flusher hops the actual emission to main.
// Do NOT add main-only work (e.g. reading `connections`) to sendLine or the off-main race this
// coalescing refactor removed comes back.
final class ConductorIT2Demux {
    // Runs argv and streams results. Returns a handle to cancel the run.
    typealias RunFunction = (_ argv: [String],
                             _ context: IT2ClientContext,
                             _ stdout: @escaping (String) -> Void,
                             _ stderr: @escaping (String) -> Void,
                             _ completion: @escaping (Int32) -> Void) -> IT2Cancellable

    // Only tiny HELLO/CANCEL frames ever flow up; reject anything absurd so a
    // client on the (0600, same-user) socket cannot make us buffer unboundedly on
    // the main thread by declaring a huge length and trickling bytes.
    // The only up-direction frame that carries a large payload is the HELLO, whose JSON holds
    // the full argv/cwd/term. macOS ARG_MAX is ~1 MiB for argv, and JSON escaping can inflate
    // that several-fold, so a 1 MiB cap rejected commands that succeed locally. 16 MiB gives
    // comfortable headroom over a fully-escaped ARG_MAX argv while still bounding a
    // never-completing partial frame. (Down-frames are NOT bounded by this; see sendFrame.)
    private static let maxFrameLength = 16 << 20  // 16 MiB
    // Bound concurrent connections so a same-user process that opens many sockets (each
    // able to pin up to maxFrameLength of never-completing partial frame) cannot grow
    // our main-thread heap without limit. Worst case buffered ~ maxConnections * maxFrameLength.
    private static let maxConnections = 32

    // Read lazily at HELLO time, not captured at construction: the demux is built
    // on the first %it2 frame, which can precede startup assigning the session
    // nonce. A snapshot would pin an empty nonce and reject every HELLO forever.
    private let nonce: () -> String?
    private let send: (String, Data) -> Void
    private let closeConnection: (String) -> Void
    private let run: RunFunction
    private let logger: (String) -> Void

    private final class Connection {
        var buffer = Data()            // accumulated raw bytes awaiting whole frames
        var started = false            // HELLO consumed; a command was launched
        var cancellable: IT2Cancellable?
    }
    private var connections = [String: Connection]()

    // Coalesced down-output. sendLine enqueues (thread-safe, from whatever thread the runner
    // delivers a line on); the joiner batches a whole burst into ONE main-thread drainSinkQueue,
    // which merges consecutive same-(connid,type) lines into a single frame. That cuts the
    // per-line main-thread hop + base64 + framer-command overhead under a firehose (a large
    // `session read`, a busy `monitor --follow`). Ordering is preserved: the queue is FIFO and
    // finish() drains it before emitting the exit frame.
    private struct SinkEvent {
        let connid: String
        let type: UInt8
        let bytes: Data
    }
    private let sinkQueue = ProducerConsumerQueue<SinkEvent>()
    private let sinkFlusher: IdempotentOperationJoiner

    init(nonce: @escaping () -> String?,
         send: @escaping (String, Data) -> Void,
         close: @escaping (String) -> Void,
         run: @escaping RunFunction,
         logger: @escaping (String) -> Void = { _ in }) {
        self.nonce = nonce
        self.send = send
        self.closeConnection = close
        self.run = run
        self.logger = logger
        self.sinkFlusher = IdempotentOperationJoiner.asyncJoiner(.main)
    }

    // Entry point: the payload after "%it2 ", i.e. "<connid> open" /
    // "<connid> data <base64>" / "<connid> close".
    func handle(_ line: String) {
        let parts = line.split(separator: " ",
                               maxSplits: 2,
                               omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else {
            logger("Malformed it2 frame: \(line)")
            return
        }
        let connid = parts[0]
        switch parts[1] {
        case "open":
            open(connid)
        case "data":
            guard parts.count >= 3, let data = Data(base64Encoded: parts[2]) else {
                // An undecodable chunk would desync the length-prefixed reassembly: the
                // next chunk appends contiguously and parseFrames reads a bogus type/
                // length from mid-payload. Tear the connection down rather than misparse
                // (mirrors framer.py handle_it2send aborting on the analogous failure).
                logger("Malformed it2 data frame for \(connid); dropping connection")
                if let conn = connections[connid] {
                    dropConnection(connid, conn)
                }
                return
            }
            appendData(connid, data)
        case "close":
            close(connid)
        default:
            logger("Unknown it2 event \(parts[1]) for \(connid)")
        }
    }

    // MARK: - Events

    private func open(_ connid: String) {
        if connections[connid] != nil {
            logger("Duplicate it2 open for \(connid)")
            return
        }
        guard connections.count < Self.maxConnections else {
            // Refuse and tell framer to close the accepted socket rather than buffering
            // an unbounded number of connections.
            logger("it2 connection cap (\(Self.maxConnections)) reached; refusing \(connid)")
            closeConnection(connid)
            return
        }
        connections[connid] = Connection()
    }

    private func appendData(_ connid: String, _ data: Data) {
        guard let conn = connections[connid] else {
            logger("it2 data for unknown connid \(connid)")
            return
        }
        conn.buffer.append(data)
        parseFrames(connid, conn)
    }

    private func close(_ connid: String) {
        guard let conn = connections.removeValue(forKey: connid) else {
            return
        }
        // The remote client went away; stop the command if it is still running.
        conn.cancellable?.cancel()
    }

    // Tear down every connection (conductor unhook / quit / deinit). Cancels any
    // in-flight command so its it2core thread and registered in-process API
    // connection are released; does not send frames down since the conductor
    // channel is going away.
    func cancelAll() {
        let conns = connections
        connections.removeAll()
        for (_, conn) in conns {
            conn.cancellable?.cancel()
        }
    }

    // MARK: - Frame parsing (up)

    // Buffers here only ever hold HELLO/CANCEL, both tiny, so simple re-slicing is
    // fine; bulk data flows the other way.
    private func parseFrames(_ connid: String, _ conn: Connection) {
        while conn.buffer.count >= 5 {
            let type = conn.buffer[conn.buffer.startIndex]
            let length = conn.buffer.readBigEndianUInt32(at: conn.buffer.startIndex + 1)
            if Int(length) > Self.maxFrameLength {
                logger("it2 frame length \(length) exceeds cap for \(connid); dropping connection")
                if conn.started {
                    dropConnection(connid, conn)
                } else {
                    // The oversize frame is the HELLO (no command running yet): return an
                    // actionable error and exit code instead of a bare socket close, so a
                    // legitimate-but-large invocation does not surface as the generic
                    // "connection closed before completion". Safe because the declared
                    // length is known up front without buffering the payload; once a
                    // command has started we drop silently (above) to avoid racing its
                    // output down the same channel.
                    sendLine(connid, IT2FrameType.stderr,
                             "it2: request too large (over \(Self.maxFrameLength / (1 << 20)) MiB over SSH integration); run it locally instead")
                    finish(connid, code: 2)
                }
                return
            }
            let total = 5 + Int(length)
            guard conn.buffer.count >= total else {
                return
            }
            let payload = Data(conn.buffer.dropFirst(5).prefix(Int(length)))
            conn.buffer = Data(conn.buffer.dropFirst(total))
            handleFrame(connid, conn, type: type, payload: payload)
        }
    }

    // Adversarial/malformed input: stop the command, tell framer to close the
    // socket, and forget the connection.
    private func dropConnection(_ connid: String, _ conn: Connection) {
        conn.cancellable?.cancel()
        connections.removeValue(forKey: connid)
        closeConnection(connid)
    }

    private func handleFrame(_ connid: String, _ conn: Connection, type: UInt8, payload: Data) {
        switch type {
        case IT2FrameType.hello:
            startCommand(connid, conn, hello: payload)
        case IT2FrameType.cancel:
            logger("it2 cancel for \(connid)")
            conn.cancellable?.cancel()
        default:
            logger("Unexpected it2 frame type \(type) for \(connid)")
        }
    }

    private func startCommand(_ connid: String, _ conn: Connection, hello: Data) {
        if conn.started {
            logger("Duplicate HELLO for \(connid)")
            return
        }
        conn.started = true
        guard let object = try? JSONSerialization.jsonObject(with: hello) as? [String: Any] else {
            logger("Malformed HELLO for \(connid)")
            sendLine(connid, IT2FrameType.stderr, "it2: malformed request")
            finish(connid, code: 2)
            return
        }
        let expected = nonce() ?? ""
        let helloNonce = object["nonce"] as? String ?? ""
        // Constant-time compare: this token authenticates remote control of the local API, so
        // do not use `==`, which short-circuits on the first differing byte and could let a
        // same-user process timing many connections recover the nonce byte by byte.
        guard !expected.isEmpty, it2ConstantTimeEqual(helloNonce, expected) else {
            logger("it2 HELLO nonce mismatch for \(connid)")
            sendLine(connid, IT2FrameType.stderr, "it2: authorization failed")
            finish(connid, code: 1)
            return
        }
        let argv = (object["argv"] as? [Any])?.compactMap { $0 as? String } ?? []
        let context = IT2ClientContext(cwd: object["cwd"] as? String ?? "",
                                       term: object["term"] as? String ?? "",
                                       isatty: object["isatty"] as? Bool ?? false,
                                       cols: object["cols"] as? Int ?? 0,
                                       rows: object["rows"] as? Int ?? 0)
        conn.cancellable = run(argv,
                               context,
                               { [weak self] line in self?.sendLine(connid, IT2FrameType.stdout, line) },
                               { [weak self] line in self?.sendLine(connid, IT2FrameType.stderr, line) },
                               { [weak self] code in self?.finish(connid, code: code) })
    }

    // MARK: - Emit (down)

    // The embedded runner delivers output a line at a time with the trailing
    // newline stripped (the standalone binary's sink re-adds it), so re-add "\n"
    // to reproduce byte-for-byte what a local it2 would print.
    private func sendLine(_ connid: String, _ type: UInt8, _ line: String) {
        // Enqueue only (thread-safe): this may be called off the main thread by the runner, so
        // it must NOT touch `connections` (main-only). The connection check and the actual
        // frame emission happen in drainSinkQueue on the main thread. Build the newline-
        // terminated bytes without the intermediate `line + "\n"` String allocation.
        var bytes = Data(line.utf8)
        bytes.append(0x0a)
        sinkQueue.produce(SinkEvent(connid: connid, type: type, bytes: bytes))
        sinkFlusher.setNeedsUpdate { [weak self] in self?.drainSinkQueue() }
    }

    // Main thread only. Drains buffered output, coalescing consecutive same-(connid,type) lines
    // into one frame. Called by the joiner (async, once per burst) and synchronously by finish()
    // (so a command's output always precedes its exit frame).
    private func drainSinkQueue() {
        var batchConnid: String?
        var batchType: UInt8 = 0
        var batchBytes = Data()
        func flushBatch() {
            if let connid = batchConnid, !batchBytes.isEmpty, connections[connid] != nil {
                sendFrame(connid, type: batchType, payload: batchBytes)
            }
            batchConnid = nil
            batchBytes = Data()
        }
        while let event = sinkQueue.tryConsume() {
            if batchConnid == event.connid && batchType == event.type {
                batchBytes.append(event.bytes)
            } else {
                flushBatch()
                batchConnid = event.connid
                batchType = event.type
                batchBytes = event.bytes
            }
        }
        flushBatch()
    }

    private func finish(_ connid: String, code: Int32) {
        // Flush any buffered output first (all connections) so this command's stdout/stderr
        // always precedes its exit frame on the wire, regardless of the joiner's timing.
        drainSinkQueue()
        // Removal from `connections` is the single guard against a double finish
        // (same as close()): a second call finds nothing and no-ops.
        guard connections[connid] != nil else {
            return
        }
        // Fixed-shape single-integer JSON; nothing to escape or fail on.
        sendFrame(connid, type: IT2FrameType.exit, payload: Data("{\"code\":\(code)}".utf8))
        connections.removeValue(forKey: connid)
        closeConnection(connid)
    }

    private func sendFrame(_ connid: String, type: UInt8, payload: Data) {
        // The wire length is a u32. Guard the (practically unreachable) >4 GiB single
        // frame so an absurd payload fails soft here instead of trapping in UInt32(_:).
        // Down-frames legitimately carry large API responses, so the bound is the wire
        // format's own limit, not the tiny up-direction maxFrameLength.
        guard payload.count <= Int(UInt32.max) else {
            logger("it2 down-frame for \(connid) exceeds u32 length (\(payload.count)); dropping")
            return
        }
        var frame = Data(capacity: 5 + payload.count)
        frame.append(type)
        frame.appendBigEndian(UInt32(payload.count))
        frame.append(payload)
        send(connid, frame)
    }
}

// Bridges the async, thread-safe cancel block from iTermInProcessIt2 to the
// synchronous IT2Cancellable the demux holds. cancel() may arrive before the
// runner hands us its cancel block (a fast remote Ctrl-C), so remember the
// request and fire as soon as the block is set.
final class IT2RunCancel: IT2Cancellable {
    private let lock = NSLock()
    private var block: (() -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    // Called by the runner (background) once the command is ready to cancel.
    func setCancelBlock(_ block: @escaping () -> Void) {
        lock.lock()
        let fireNow = cancelled
        if !cancelled {
            self.block = block
        }
        lock.unlock()
        if fireNow {
            block()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let block = self.block
        self.block = nil
        lock.unlock()
        block?()
    }
}

extension Conductor {
    // Single source of the origin label for this connection, used for both the Script
    // Console attribution (originDisplayName) and the user-facing authorization
    // announcement, so the console entry and the permission prompt can never diverge.
    var it2DisplayName: String {
        "ssh " + sshIdentity.compactDescription
    }

    // Copy the it2 proxy state (nonce/socket/authorization) from the conductor being
    // recovered onto this one (the recovery shim built by screenBeginFramerRecovery),
    // so it survives the begin-recovery..end-recovery hand-off into the post-recovery
    // conductor (handleRecovery reads these off the shim). The framer has no source for
    // them -- framerSave stores only dcsID/sshargs/boolArgs/clientUniqueID and no nonce
    // is re-minted on recovery -- so this in-process copy is the only carrier. The
    // authorization grant in particular must never be re-derived from the remote. The
    // caller keeps `other` alive across the (root single-hop) unhook that would
    // otherwise release it before the shim exists.
    @objc(adoptIT2RecoveryStateFrom:)
    func adoptIT2RecoveryState(from other: Conductor?) {
        guard let other else {
            return
        }
        it2Proxy = other.it2Proxy
        // Tear down the retiring conductor's in-flight it2 commands as part of the hand-off.
        // On a ROOT recovery it unhooks and cancels these itself, but on a NESTED recovery it
        // is retained as this conductor's parent and never unhooks or deinits -- so without
        // this, a streaming command (e.g. `monitor --follow`) on it would leak its it2Demux, a
        // background it2core thread blocked in receiveMessage, and a registered in-process API
        // connection for the life of the session, relying on a depth-routed close frame that
        // is not guaranteed to reach the old demux. cancelAll() is idempotent, so the redundant
        // root-path call is a no-op; the fresh conductor builds its own demux on the next frame.
        other.it2Demux?.cancelAll()
    }

    // Lazily builds the demux, wiring it to the framer senders and the in-process
    // runner. The nonce is read lazily on each HELLO (not snapshotted here): the
    // demux can be built by the first %it2 frame before startup assigns it2Nonce,
    // and the empty nonce must stop authorizing as soon as the real one is set.
    func it2DemuxForHandling() -> ConductorIT2Demux {
        if let existing = it2Demux {
            return existing
        }
        let identifier = clientUniqueID
        let displayName = it2DisplayName
        let demux = ConductorIT2Demux(
            nonce: { [weak self] in self?.it2Nonce },
            send: { [weak self] connid, data in self?.it2Send(connid: connid, data: data) },
            close: { [weak self] connid in self?.it2Close(connid: connid) },
            // The 2nd parameter is the IT2ClientContext (cwd/term/isatty/cols/rows) the demux
            // parses from HELLO and the demux tests assert is delivered here. It is
            // intentionally dropped ('_') for now: iTermInProcessIt2.run below forwards only
            // argv. THIS is the one place to wire it when remote sizing/cwd/TERM lands -- pass
            // it into iTermInProcessIt2.run and honor it there; the wire (it2.py) and the demux
            // delivery are already in place.
            run: { [weak self] argv, _, stdoutSink, stderrSink, completionSink in
                let cancel = IT2RunCancel()
                // The demux requires stderr/completion on the main thread. The guard/deny
                // paths below run inline during the (main-thread) run() call, so marshal
                // through a fresh main-loop turn; deferring also avoids re-entering the
                // demux's finish() before it stores conn.cancellable. (These are only
                // called, never passed to the runner's @Sendable block params.)
                let emitStderr = { (line: String) in DispatchQueue.main.async { stderrSink(line) } }
                let finish = { (code: Int32) in DispatchQueue.main.async { completionSink(code) } }
                guard let self else {
                    finish(1)
                    return cancel
                }
                guard iTermAPIHelper.isEnabled() else {
                    emitStderr("The iTerm2 Python API is not enabled (Settings > General > Magic).")
                    finish(2)
                    return cancel
                }
                // it2-over-ssh always requires an explicit per-connection grant; the
                // local "allow all apps to connect" setting deliberately does not apply
                // to a remote reaching back in over the conductor channel.
                self.authorizeIT2 { granted in
                    guard !cancel.isCancelled else {
                        // Remote disconnected while the prompt was up; nothing to run.
                        finish(1)
                        return
                    }
                    guard granted else {
                        emitStderr("Permission denied: iTerm2 API access was not granted for this session.")
                        finish(1)
                        return
                    }
                    // stdout/stderr sinks call sendLine, which only enqueues (thread-safe) and
                    // lets the demux's joiner coalesce+flush on main -- so no per-line main hop
                    // here. completion must still marshal to main: finish() drains the queue and
                    // touches `connections` (main-only).
                    iTermInProcessIt2.run(withArguments: argv,
                                          originIdentifier: identifier,
                                          originDisplayName: displayName,
                                          stdoutHandler: { line in stdoutSink(line) },
                                          stderrHandler: { line in stderrSink(line) },
                                          cancellationHandler: { cancelBlock in cancel.setCancelBlock(cancelBlock) },
                                          completion: { code in DispatchQueue.main.async { completionSink(code) } })
                }
                return cancel
            },
            logger: { [weak self] message in self?.DLog(message) })
        it2Demux = demux
        return demux
    }

    // Ensure this connection is authorized to use the it2-over-ssh API, then call
    // `completion(granted)` on the main thread. A decision (this run or restored from a
    // prior run) short-circuits; otherwise a single in-session announcement is presented
    // and its answer is fanned out (via an iTermPromise) to every concurrent it2 command
    // so they share one prompt. Must be called on the main thread.
    func authorizeIT2(then completion: @escaping (Bool) -> Void) {
        if let decided = it2Authorized {
            completion(decided)
            return
        }
        let promise = it2AuthPromise ?? makeIT2AuthorizationPromise()
        promise.then { value in
            completion(value.boolValue)
        }
    }

    private func makeIT2AuthorizationPromise() -> iTermPromise<NSNumber> {
        let promise = iTermPromise<NSNumber> { [weak self] seal in
            guard let self else {
                seal.fulfill(NSNumber(value: false))
                return
            }
            // The Conductor owns the seal so it can guarantee exactly-once resolution:
            // the announcement can be dropped on session teardown without ever firing
            // its completion, and an unresolved iTermPromise seal asserts on dealloc.
            guard let delegate = self.delegate else {
                // No session to prompt on: track the seal, then fail closed.
                self.it2AuthSeal = seal
                self.resolveIT2Authorization(false, persist: false)
                return
            }
            delegate.conductorRequestIT2Authorization(guid: self.guid,
                                                      displayName: self.it2DisplayName) { [weak self] granted, remember in
                self?.resolveIT2Authorization(granted, persist: remember)
            }
            // Assign the seal AFTER presenting: queueAnnouncement synchronously dismisses
            // any orphan announcement with the same identifier, whose completion(-2)
            // re-enters resolveIT2Authorization. Assigning only now keeps that orphan
            // dismissal from resolving this fresh, not-yet-shown prompt.
            self.it2AuthSeal = seal
        }
        it2AuthPromise = promise
        promise.then { [weak self] _ in
            self?.it2AuthPromise = nil  // release the transient promise once resolved
        }
        return promise
    }

    // Resolve the single pending authorization prompt exactly once (nil-guarded via the
    // seal). `persist` records the decision in restorable state so it survives restart;
    // fail-closed teardown paths pass false so a torn-down prompt is not remembered as a
    // denial. Safe to call when no prompt is pending (no-op).
    func resolveIT2Authorization(_ granted: Bool, persist: Bool) {
        guard let seal = it2AuthSeal else {
            return
        }
        it2AuthSeal = nil
        // Dismiss the on-screen prompt so a programmatic resolve (teardown) does not leave
        // a dead announcement whose later click is silently ignored. On the user-answer
        // path the announcement is already dismissing itself, so this is a no-op. Clearing
        // the seal above makes the dismissal's re-entrant completion(-2) a no-op too.
        delegate?.conductorDismissIT2AuthorizationPrompt(guid: guid)
        if persist {
            it2Authorized = granted
        }
        seal.fulfill(NSNumber(value: granted))
    }

    // Dismiss an in-flight authorization prompt on this (retiring) conductor without
    // remembering a decision. Called during the SSH recovery hand-off so a prompt still
    // on screen does not linger pointing at the dead conductor and silently swallow the
    // user's later click; the surviving conductor carries any already-decided grant (see
    // adoptIT2RecoveryState) and re-prompts on the next command if still undecided.
    @objc func resolveIT2AuthorizationFailClosed() {
        resolveIT2Authorization(false, persist: false)
    }

    // MARK: - Shell > SSH > "Remote host can control iTerm2" menu item

    // Whether the it2-over-ssh proxy is actually live on this connection: the framer is
    // framing, activateIT2Proxy injected the socket/nonce, AND framer's it2Listen reported a
    // successful bind. Gates the menu item's enabled state so it is disabled for a plain
    // (non-it2-capable) ssh session, a broken/unframed one, or one where the socket bind
    // failed (so the menu never looks enabled while the remote it2 silently cannot connect).
    @objc var it2ProxyActive: Bool {
        return framing && it2Nonce != nil && it2ListenSucceeded
    }

    // Checkmark state for the menu item: whether this connection currently has an explicit
    // grant (from the announcement or a previous menu toggle). A nil/denied decision is
    // unchecked. Kept distinct from it2Authorized (an optional tri-state) so the ObjC menu
    // code deals in a plain BOOL.
    @objc var it2AuthorizedByUser: Bool {
        return it2Authorized == true
    }

    // Toggle handler for the menu item. Grants or revokes it2-over-ssh access for THIS
    // connection and persists the decision to restorable state, exactly as answering the
    // in-session announcement would. If an announcement is currently pending (a blocked it2
    // command is waiting on an answer), this also resolves it now so the command proceeds or
    // aborts immediately rather than waiting for a click. In-flight commands that already
    // passed the gate (e.g. a running `monitor --follow`) are unaffected by a revoke; only
    // subsequent commands see the new decision. Must be called on the main thread.
    @objc func setIT2AuthorizationFromMenu(_ granted: Bool) {
        it2Authorized = granted
        // No-op when no prompt is pending; otherwise dismisses the on-screen announcement and
        // fulfills the shared promise so every concurrent it2 command unblocks with `granted`.
        resolveIT2Authorization(granted, persist: true)
    }

    // Activate the it2 CLI proxy for this session: mint the auth nonce + a remote
    // socket path and inject IT2_SOCK/IT2_NONCE into the login shell's environment,
    // so the remote it2 (materialized by the shell-integration scripts) can find and
    // authenticate to the socket. framer binds the socket once framing starts (see
    // it2Listen in doFraming). Called from the shell-integration path, which is what
    // provides `it2` on the remote and implies we will frame.
    //
    // The socket lives in a dedicated directory under the user's home (framer
    // creates it 0700 before binding), not in a shared world-writable place: the
    // socket is chmod 0600, but an owner-only parent directory is the portable
    // guarantee that no other local user can reach it. `home` is the remote $HOME
    // resolved from getshell.
    func activateIT2Proxy(home: String, env: inout [String: String]) {
        let nonce = Self.it2RandomHex(byteCount: 16)
        let socketPath = Self.it2SocketPath(home: home)
        it2Nonce = nonce
        it2SocketPath = socketPath
        env["IT2_SOCK"] = socketPath
        env["IT2_NONCE"] = nonce
    }

    // AF_UNIX sun_path is 104 bytes on macOS and 108 on Linux; the remote OS is unknown,
    // so bound to the smaller with margin. Prefer ~/.iterm2/it2/<hex>.sock, but a long
    // remote $HOME (e.g. an NFS-mounted home) would overflow the bind -- and it2Listen is
    // fire-and-forget, so that failure would be silent. Fall back to a short /tmp path in
    // that case (the framer still creates its parent 0700 and binds the socket 0600, and
    // the random directory name resists pre-creation) so it2 keeps working there.
    private static func it2SocketPath(home: String) -> String {
        let name = it2RandomHex(byteCount: 8) + ".sock"
        let homePath = "\(home)/.iterm2/it2/\(name)"
        if homePath.utf8.count <= 100 {
            return homePath
        }
        return "/tmp/.it2-\(it2RandomHex(byteCount: 4))/\(name)"
    }

    private static func it2RandomHex(byteCount: Int) -> String {
        // Delegates to the shared secure-RNG-to-hex helper rather than re-implementing
        // SecRandomCopyBytes. SecRandomCopyBytes effectively never fails; the UUID
        // fallback keeps us unpredictable (and the right length) if it somehow does.
        String.makeSecureHexString(byteCount: byteCount)
            ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(byteCount * 2))
    }
}
