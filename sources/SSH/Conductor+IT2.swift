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

// The it2-over-ssh proxy state that must travel together across an SSH recovery. Grouped
// into one value so a reconnect copies a single value (one adopt assignment, one
// ConductorRecovery field, one init(recovery:) assignment) and a future field touches
// only this struct -- rather than five hand-synchronized carriers where omitting one
// silently reverts the field to nil after recovery (a lost grant or a nonce that fails
// every HELLO). `nonce` authenticates incoming it2.py HELLOs; `socketPath` is the remote
// unix socket; `authorized` is the user's per-connection API grant.
struct IT2ProxyState: Codable, Equatable {
    var nonce: String?
    var socketPath: String?
    var authorized: Bool?
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

// Reconstructs and dispatches it2 RPC connections. All methods must be called on
// the main thread; the injected `run` closure may deliver its stdout/stderr/
// completion on any thread, so the production adapter marshals those to main
// before they reach this class.
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
    private static let maxFrameLength = 1 << 20  // 1 MiB
    // Bound concurrent connections so a same-user process that opens many sockets (each
    // able to pin up to maxFrameLength of never-completing partial frame) cannot grow
    // our main-thread heap without limit. Worst case buffered ~ maxConnections * 1 MiB.
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
                    sendLine(connid, IT2FrameType.stderr, "it2: request too large")
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
        guard !expected.isEmpty, helloNonce == expected else {
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
        guard connections[connid] != nil else {
            return  // connection closed underneath us; drop
        }
        sendFrame(connid, type: type, payload: Data((line + "\n").utf8))
    }

    private func finish(_ connid: String, code: Int32) {
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
                    iTermInProcessIt2.run(withArguments: argv,
                                          originIdentifier: identifier,
                                          originDisplayName: displayName,
                                          stdoutHandler: { line in DispatchQueue.main.async { stdoutSink(line) } },
                                          stderrHandler: { line in DispatchQueue.main.async { stderrSink(line) } },
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
