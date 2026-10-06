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
        /// The remote it2.py this connection told its login shell to run (IT2_PY). Kept rather
        /// than recomputed: after an upgrade restores the connection, the new build's hash was
        /// never uploaded to this host.
        var pyPath: String?
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
    var pyPath: String? { get { persisted.pyPath } set { persisted.pyPath = newValue } }
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
    /// The bytes the remote it2 read from its stdin, when its command takes a payload there.
    /// Nil when there was none; a hook's JSON arrives this way.
    var stdin: Data?
    /// The allowlisted slice of the remote's environment. See IT2ClientContext.allowedEnvNames.
    var environment: [String: String]

    /// The only environment variables accepted from a remote host.
    ///
    /// An allowlist, applied here as well as in it2.py. The remote's environment holds
    /// credentials, tokens and paths that have no business reaching the Mac, and a remote host
    /// is not a trust boundary we control: it2.py filtering is a courtesy, this is the rule.
    /// PATH in particular must never arrive this way.
    static let allowedEnvNames: Set<String> = ["TMUX", "TMUX_PANE", "TERM_SESSION_ID",
                                               "IT2_SUITE", "IT2_PY"]

    /// `environment` reduced to the allowlist.
    static func filteredEnvironment(_ raw: [String: String]) -> [String: String] {
        return raw.filter { allowedEnvNames.contains($0.key) }
    }
}

// What a remote it2 call does before running, given the API setting and the connection's
// authorization state.
//
// A Claude Code hook must never block and never complain. It fires on every tool call, so
// waiting on the authorization prompt stalls the agent, and printing an error puts the same text
// in its transcript over and over. A hook that cannot run yet therefore completes at once,
// successfully and silently; while the decision is still open it also raises the prompt, so that
// once the user answers, the NEXT hook succeeds. An interactive command keeps the old behaviour:
// it waits for the prompt and reports a denial, which is useful to a person who typed it.
enum IT2RunPolicy: Equatable {
    /// Ask (or use the cached answer), then run or report a denial.
    case authorizeThenRun
    /// Interactive command with the API off: say why.
    case reportAPIDisabled
    /// Hook that cannot run and has nothing to ask: finish with 0 and no output.
    case succeedSilently
    /// Hook on a connection with no decision yet: raise the prompt, but finish now.
    case promptThenSucceedSilently

    /// The only commands that must never block. Matches it2.py's STDIN_CONSUMING_COMMANDS so the
    /// two ends agree on what a hook is.
    static let nonBlockingCommands: Set<String> = ["handle-agent-hook"]

    /// Whether this invocation is a hook. The first non-flag argument names the command, the same
    /// rule it2.py's wants_stdin uses.
    static func isNonBlockingHook(argv: [String]) -> Bool {
        guard let command = argv.first(where: { !$0.hasPrefix("-") }) else {
            return false
        }
        return nonBlockingCommands.contains(command)
    }

    static func decide(argv: [String], apiEnabled: Bool, decision: Bool?) -> IT2RunPolicy {
        let hook = isNonBlockingHook(argv: argv)
        guard apiEnabled else {
            return hook ? .succeedSilently : .reportAPIDisabled
        }
        guard hook else {
            return .authorizeThenRun
        }
        switch decision {
        case .none:
            return .promptThenSucceedSilently
        case .some(true):
            return .authorizeThenRun
        case .some(false):
            return .succeedSilently
        }
    }
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
    /// The HELLO protocol this build speaks. it2.py sends its own as "protocol"; a client that
    /// omits it predates the field and is served. Bump this, and it2.py's PROTOCOL_VERSION with
    /// it, when the HELLO gains something a command cannot run correctly without.
    static let protocolVersion = 1

    /// Whether a HELLO's "protocol" value is one this build can serve.
    static func canServe(protocolValue: Any?) -> Bool {
        guard let protocolValue else {
            return true
        }
        guard let number = protocolValue as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let version = Int(exactly: number) else {
            return false
        }
        return version <= protocolVersion
    }

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
                             String(localized: "IT2Proxy.RequestTooLarge", defaultValue: "it2: request too large (over \(String(describing: Self.maxFrameLength / (1 << 20))) MiB over SSH integration); run it locally instead", comment: "Error when an it2 request exceeds the size cap; the number is the cap in MiB"))
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
            sendLine(connid, IT2FrameType.stderr, String(localized: "IT2Proxy.MalformedRequest", defaultValue: "it2: malformed request", comment: "Error when the it2 HELLO payload is not valid JSON"))
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
            sendLine(connid, IT2FrameType.stderr, String(localized: "IT2Proxy.AuthorizationFailed", defaultValue: "it2: authorization failed", comment: "Error when the it2 HELLO nonce does not match"))
            finish(connid, code: 1)
            return
        }
        let argv = (object["argv"] as? [Any])?.compactMap { $0 as? String } ?? []
        // After the nonce, so an unauthenticated caller learns nothing. A newer client may rely
        // on fields this build would silently ignore, so refuse it rather than run it half
        // understood.
        guard Self.canServe(protocolValue: object["protocol"]) else {
            logger("it2 HELLO protocol \(String(describing: object["protocol"])) is newer than \(Self.protocolVersion) for \(connid)")
            if IT2RunPolicy.isNonBlockingHook(argv: argv) {
                // A hook never complains; see IT2RunPolicy.
                finish(connid, code: 0)
                return
            }
            sendLine(connid, IT2FrameType.stderr, String(localized: "IT2Proxy.NewerProtocol", defaultValue: "it2: this it2 is newer than the iTerm2 it is connected to. Upgrade iTerm2.", comment: "Error when a remote it2 client speaks a newer protocol than this iTerm2 understands"))
            finish(connid, code: 2)
            return
        }
        // Undecodable stdin is not fatal: the command simply has no payload, which is a better
        // outcome than refusing to run it.
        let stdin = (object["stdin"] as? String).flatMap { Data(base64Encoded: $0) }
        let rawEnvironment = (object["env"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        let context = IT2ClientContext(cwd: object["cwd"] as? String ?? "",
                                       term: object["term"] as? String ?? "",
                                       isatty: object["isatty"] as? Bool ?? false,
                                       cols: object["cols"] as? Int ?? 0,
                                       rows: object["rows"] as? Int ?? 0,
                                       stdin: stdin,
                                       environment: IT2ClientContext.filteredEnvironment(rawEnvironment))
        // There is otherwise no way to tell from outside whether a payload crossed the wire: a
        // hook with nothing usable in it exits silently by design. Names only, never values:
        // these are allowlisted but still came from a remote host.
        DLog("it2 HELLO conn=\(connid) argv=\(argv) stdin=\(stdin?.count ?? 0) bytes env=\(context.environment.keys.sorted())")
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

    /// Whether `connid` is still open, i.e. its command has not finished. For tests: a command
    /// held on the authorization prompt keeps its connection open, and one that completed does
    /// not, which is the property "hooks never block" is about.
    func hasOpenConnection(_ connid: String) -> Bool {
        return connections[connid] != nil
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
    /// Overrides the Python API setting for the it2 run path, for tests only. The real setting is
    /// a global preference, and flipping it from a test would leak into every other test and into
    /// the user's own suite.
    static var it2APIEnabledForTesting: Bool?

    /// Test seams for the always-allow grant check. The real check downloads a file through the
    /// framer, and on a conductor with no framer that awaits a reply that never comes, so a test
    /// using it would hang rather than fail.
    static var hostGrantStoreForTesting: IT2HostGrantStore?
    static var hostGrantVerifierForTesting: ((IT2HostGrant, String) async -> Bool)?

    /// The grant store every conductor path uses. One accessor, so no path can bypass the test
    /// store: minting once wrote to the shared store directly while checking used the seam.
    static var hostGrantStore: IT2HostGrantStore {
        return hostGrantStoreForTesting ?? .shared
    }

    /// Replaces the in-process it2 runner, for tests only, so a test can see which origin a
    /// remote command would run with. Returns the exit code.
    static var it2RunForTesting: ((_ argv: [String], _ originIdentifier: String, _ originSessionID: String?) -> Int32)?

    // Single source of the origin label for this connection, used for both the Script
    // Console attribution (originDisplayName) and the user-facing authorization
    // announcement, so the console entry and the permission prompt can never diverge.
    var it2DisplayName: String {
        // Localization unneeded
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
        // Read through a closure, not captured once: the delegate is replaced across an SSH
        // recovery, and a GUID captured when the demux was built would name a session that no
        // longer exists. Weak, so the demux cannot keep the conductor alive.
        let originSessionID: () -> String? = { [weak self] in self?.delegate?.guid }
        let demux = ConductorIT2Demux(
            nonce: { [weak self] in self?.it2Nonce },
            send: { [weak self] connid, data in self?.it2Send(connid: connid, data: data) },
            close: { [weak self] connid in self?.it2Close(connid: connid) },
            // The 2nd parameter is the IT2ClientContext the demux parses from HELLO. Its stdin
            // and (allowlisted) environment are forwarded below, because a command whose payload
            // arrives on stdin -- a Claude Code hook -- cannot work without them. The sizing
            // fields (cwd/term/cols/rows) are still unused; this is the place to wire them.
            run: { [weak self] argv, clientContext, stdoutSink, stderrSink, completionSink in
                let cancel = IT2RunCancel()
                // A remote command with no explicit target addresses this session. Logged
                // because a nil here is the difference between "landed on the right tab" and
                // "landed on whatever was focused", and nothing else would show which.
                let resolvedOriginSessionID = originSessionID()
                self?.DLog("it2 run argv=\(argv) originSession=\(resolvedOriginSessionID ?? "(none)")")
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
                let isHook = IT2RunPolicy.isNonBlockingHook(argv: argv)
                switch IT2RunPolicy.decide(argv: argv,
                                           apiEnabled: Conductor.it2APIEnabledForTesting ?? iTermAPIHelper.isEnabled(),
                                           decision: self.it2Authorized) {
                case .reportAPIDisabled:
                    emitStderr(String(localized: "IT2Proxy.APINotEnabled", defaultValue: "The iTerm2 Python API is not enabled (Settings > General > Magic).", comment: "Error when the iTerm2 Python API is disabled"))
                    finish(2)
                    return cancel
                case .succeedSilently:
                    self.DLog("it2 hook not run (API off or access denied); completing silently")
                    finish(0)
                    return cancel
                case .promptThenSucceedSilently:
                    // Raise the prompt and let the answer be cached, but do not hold the hook
                    // for it: the agent would stall until the user noticed. The next hook after
                    // the user answers runs normally.
                    self.DLog("it2 hook on an undecided connection; prompting without blocking")
                    self.authorizeIT2(callerTmuxPane: clientContext.environment["TMUX_PANE"]) { _ in }
                    finish(0)
                    return cancel
                case .authorizeThenRun:
                    break
                }
                // it2-over-ssh always requires an explicit per-connection grant; the
                // local "allow all apps to connect" setting deliberately does not apply
                // to a remote reaching back in over the conductor channel.
                self.authorizeIT2(callerTmuxPane: clientContext.environment["TMUX_PANE"]) { granted in
                    guard !cancel.isCancelled else {
                        // Remote disconnected while the prompt was up; nothing to run.
                        finish(1)
                        return
                    }
                    guard granted else {
                        // The decision can flip between the policy check and here (the user
                        // answered "deny" to a prompt another call raised). A hook still stays
                        // quiet about it.
                        if isHook {
                            finish(0)
                            return
                        }
                        emitStderr(String(localized: "IT2Proxy.PermissionDenied", defaultValue: "Permission denied: iTerm2 API access was not granted for this session.", comment: "Error when the user has not granted it2-over-ssh API access"))
                        finish(1)
                        return
                    }
                    // stdout/stderr sinks call sendLine, which only enqueues (thread-safe) and
                    // lets the demux's joiner coalesce+flush on main -- so no per-line main hop
                    // here. completion must still marshal to main: finish() drains the queue and
                    // touches `connections` (main-only).
                    if let runForTesting = Conductor.it2RunForTesting {
                        finish(runForTesting(argv, identifier, resolvedOriginSessionID))
                        return
                    }
                    iTermInProcessIt2.run(withArguments: argv,
                                          originIdentifier: identifier,
                                          originDisplayName: displayName,
                                          originSessionID: resolvedOriginSessionID,
                                          stdinData: clientContext.stdin,
                                          environment: clientContext.environment,
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
    func authorizeIT2(callerTmuxPane: String? = nil, then completion: @escaping (Bool) -> Void) {
        if let decided = it2Authorized {
            completion(decided)
            return
        }
        let promise = it2AuthPromise ?? makeIT2AuthorizationPromise(callerTmuxPane: callerTmuxPane)
        promise.then { value in
            completion(value.boolValue)
        }
    }

    private func makeIT2AuthorizationPromise(callerTmuxPane: String?) -> iTermPromise<NSNumber> {
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
            // A host the user chose to always allow: read its half of the grant back before
            // bothering them. Only when that fails do we ask.
            if let grant = Conductor.hostGrantStore.grant(forHost: self.sshIdentity.stringIdentifier),
               let home = self.homeDirectory {
                // Hold the seal while the file is read, so a match can resolve it and a teardown
                // in the meantime can fail it closed. No announcement is on screen yet, so the
                // orphan-dismissal hazard described below does not apply until one is presented.
                self.it2AuthSeal = seal
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    let verified: Bool
                    if let verifier = Conductor.hostGrantVerifierForTesting {
                        verified = await verifier(grant, home)
                    } else {
                        verified = await self.hostGrantVerifies(grant, home: home)
                    }
                    // Resolved while reading (torn down, say): nothing left to decide, and no
                    // prompt should appear for a connection that is gone.
                    guard self.it2AuthSeal != nil else {
                        return
                    }
                    if verified {
                        self.resolveIT2Authorization(true, persist: true)
                        return
                    }
                    guard let delegate = self.delegate else {
                        self.resolveIT2Authorization(false, persist: false)
                        return
                    }
                    // Fall back to asking. Release the seal and take it back after presenting,
                    // for the same reason as the direct path below.
                    self.it2AuthSeal = nil
                    self.presentIT2AuthorizationPrompt(delegate: delegate, seal: seal, callerTmuxPane: callerTmuxPane)
                }
                return
            }
            self.presentIT2AuthorizationPrompt(delegate: delegate, seal: seal, callerTmuxPane: callerTmuxPane)
        }
        it2AuthPromise = promise
        promise.then { [weak self] _ in
            self?.it2AuthPromise = nil  // release the transient promise once resolved
        }
        return promise
    }

    private func presentIT2AuthorizationPrompt(delegate: ConductorDelegate, seal: iTermPromiseSeal, callerTmuxPane: String?) {
        delegate.conductorRequestIT2Authorization(guid: guid,
                                                  displayName: it2DisplayName,
                                                  callerTmuxPane: callerTmuxPane) { [weak self] granted, remember, alwaysForHost in
            self?.resolveIT2Authorization(granted, persist: remember)
            if granted && alwaysForHost {
                self?.mintHostGrant()
            }
        }
        // Assign the seal AFTER presenting: queueAnnouncement synchronously dismisses
        // any orphan announcement with the same identifier, whose completion(-2)
        // re-enters resolveIT2Authorization. Assigning only now keeps that orphan
        // dismissal from resolving this fresh, not-yet-shown prompt.
        it2AuthSeal = seal
    }

    /// Whether the host's half of `grant` matches. Any failure to read it (the file is gone,
    /// the host was rebuilt, the transfer failed) is simply "no", which falls back to asking.
    ///
    /// A mismatch does not delete the Mac's record. A transient read error would otherwise wipe
    /// a valid grant, and a genuinely stale one is replaced the next time the user picks Always
    /// Allow, since adding a grant replaces any existing record for that host.
    func hostGrantVerifies(_ grant: IT2HostGrant, home: String) async -> Bool {
        do {
            let data = try await download("\(home)/\(IT2GrantToken.remoteRelativePath)",
                                          chunk: nil,
                                          uniqueID: nil)
            let verified = IT2GrantToken.verify(fileContents: String(decoding: data, as: UTF8.self),
                                                against: grant)
            DLog("it2 host grant for \(grant.host): \(verified ? "verified" : "does not match")")
            return verified
        } catch {
            DLog("it2 host grant for \(grant.host) could not be read: \(error)")
            return false
        }
    }

    /// Give this host a grant so future connections are allowed without asking. The host keeps
    /// the secret; the Mac records only its hash, and only once the host has it, so a failed
    /// write cannot leave a record that would make every connection read a file that is not
    /// there before asking anyway.
    func mintHostGrant() {
        let host = sshIdentity.stringIdentifier
        let token = IT2GrantToken.mint()
        framerExecPythonStatements(statements: IT2GrantToken.remoteWriteStatements(id: token.id,
                                                                                   secret: token.secret)) { [weak self] ok, output in
            guard ok else {
                // Host names stay out of RLog, which ships in user-submitted debug logs.
                RLog("Could not write the it2 grant to the remote host")
                self?.DLog("it2 grant write to \(host) failed: \(output)")
                return
            }
            Conductor.hostGrantStore.add(IT2HostGrant(host: host,
                                                      id: token.id,
                                                      secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                                      granted: Date()))
            self?.DLog("it2 host grant minted for \(host)")
        }
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

    // What a remote `it2` needs to reach iTerm2 over THIS connection: the same socket path and
    // nonce the login shell received as IT2_SOCK and IT2_NONCE. A tmux -CC controller publishes
    // this record on its server so a program in a pane can find the connection currently showing
    // it, instead of the one that happened to start the server (see TmuxController's
    // advertiseIT2Client). Nil until activateIT2Proxy has minted them. The keys are what it2.py
    // reads back. "py" names the interpreter this connection uploaded; it2.py re-execs it so the
    // client version and the connection are chosen together. Absent for a connection restored
    // from before it was recorded, and it2.py then just keeps running itself.
    @objc var it2ClientRecord: [String: String]? {
        guard let socketPath = it2SocketPath, let nonce = it2Nonce else {
            return nil
        }
        var record = ["sock": socketPath, "nonce": nonce]
        if let pyPath = it2Proxy.pyPath {
            record["py"] = pyPath
        }
        return record
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
        if !granted {
            // Otherwise an always-allow grant would re-allow this host on its very next
            // connection, and switching it off here would seem not to have worked.
            Conductor.hostGrantStore.remove(host: sshIdentity.stringIdentifier)
        }
        it2Authorized = granted
        // No-op when no prompt is pending; otherwise dismisses the on-screen announcement and
        // fulfills the shared promise so every concurrent it2 command unblocks with `granted`.
        resolveIT2Authorization(granted, persist: true)
    }

    // Activate the it2 CLI proxy for this session: mint the auth nonce + a remote
    // socket path and inject IT2_SOCK/IT2_NONCE into the login shell's environment,
    // so the remote it2 (uploaded to ~/.iterm2/bin, materialized by the shell-integration
    // scripts, or installed by hand) can find and authenticate to the socket. framer binds
    // the socket once framing starts (see it2Listen in doFraming). Called at getshell for
    // every connection with a known home, injected or not; see Conductor.remoteSetup.
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
        // Name the interpreter THIS iTerm2 uploaded. Several builds can have written copies to
        // the same host, each under its own content hash, and the wrapper's built-in fallback
        // only knows the hash it was built with.
        let pyPath = iTermRemoteIt2.remotePyPath(home: home, hash: iTermRemoteIt2.bundledPyHash)
        it2Proxy.pyPath = pyPath
        env["IT2_PY"] = pyPath
        // PATH is deliberately NOT set here. These variables reach the remote through a
        // `setenv` conductor command, and conductor.sh's handler does `export ${name}=${value}`
        // in its OWN process, which needs PATH for awk, head, grep, base64, tar, stty and dd.
        // A prepend cannot be expressed through that channel either: the value is not
        // re-expanded, so a literal $PATH stays literal, and this dictionary never carries a
        // PATH to extend in the first place.
        //
        // Sending an absolute PATH here broke every conductor command issued after getshell,
        // including the payload upload, and the resulting "command not found" errors escaped
        // the conductor parser onto the screen. ~/.iterm2/bin is put on PATH by the
        // shell-integration scripts instead, where the real PATH is in hand; exporting it there
        // also reaches a hook's `sh -c`, which is the case this exists for.
    }

    // AF_UNIX sun_path is 104 bytes on macOS and 108 on Linux; the remote OS is unknown,
    // so bound to the smaller with margin. Prefer ~/.iterm2/it2/<hex>.sock, but a long
    // remote $HOME (e.g. an NFS-mounted home) would overflow the bind -- and it2Listen is
    // fire-and-forget, so that failure would be silent. Fall back to a short /tmp path in
    // that case (the framer still creates its parent 0700 and binds the socket 0600, and
    // the random directory name resists pre-creation) so it2 keeps working there.
    static func it2SocketPath(home: String) -> String {
        let name = it2RandomHex(byteCount: 8) + ".sock"
        let homePath = "\(home)/.iterm2/it2/\(name)"
        if homePath.utf8.count <= 100 {
            return homePath
        }
        // Rare enough, and visible enough in /tmp, that a debug log should say why.
        RLog("it2 socket for a home of \(home.utf8.count) bytes would exceed the socket path limit; using /tmp")
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
