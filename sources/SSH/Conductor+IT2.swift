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
import Security  // SecRandomCopyBytes for the it2 auth nonce

// it2.py <-> demux frames: [1 byte type][4 byte big-endian length][payload].
private enum IT2FrameType {
    static let hello = UInt8(ascii: "H")   // up:   json {nonce, argv, cwd, term, isatty, cols, rows}
    static let cancel = UInt8(ascii: "C")  // up:   empty (remote Ctrl-C)
    static let stdout = UInt8(ascii: "O")  // down: raw bytes
    static let stderr = UInt8(ascii: "E")  // down: raw bytes
    static let exit = UInt8(ascii: "X")    // down: json {code}, last frame
}

// Terminal context captured by the remote client at invocation time. Parsed from
// HELLO; not all fields are forwarded to the runner yet.
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
                logger("Malformed it2 data frame for \(connid)")
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
                dropConnection(connid, conn)
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
    // Lazily builds the demux, wiring it to the framer senders and the in-process
    // runner. The nonce is read lazily on each HELLO (not snapshotted here): the
    // demux can be built by the first %it2 frame before startup assigns it2Nonce,
    // and the empty nonce must stop authorizing as soon as the real one is set.
    func it2DemuxForHandling() -> ConductorIT2Demux {
        if let existing = it2Demux {
            return existing
        }
        let identifier = clientUniqueID
        let displayName = "ssh " + sshIdentity.compactDescription
        let demux = ConductorIT2Demux(
            nonce: { [weak self] in self?.it2Nonce },
            send: { [weak self] connid, data in self?.it2Send(connid: connid, data: data) },
            close: { [weak self] connid in self?.it2Close(connid: connid) },
            run: { argv, _, stdout, stderr, completion in
                let cancel = IT2RunCancel()
                iTermInProcessIt2.run(withArguments: argv,
                                      originIdentifier: identifier,
                                      originDisplayName: displayName,
                                      stdoutHandler: { line in DispatchQueue.main.async { stdout(line) } },
                                      stderrHandler: { line in DispatchQueue.main.async { stderr(line) } },
                                      cancellationHandler: { cancelBlock in cancel.setCancelBlock(cancelBlock) },
                                      completion: { code in DispatchQueue.main.async { completion(code) } })
                return cancel
            },
            logger: { [weak self] message in self?.DLog(message) })
        it2Demux = demux
        return demux
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
        let socketPath = "\(home)/.iterm2/it2/\(Self.it2RandomHex(byteCount: 8)).sock"
        it2Nonce = nonce
        it2SocketPath = socketPath
        env["IT2_SOCK"] = socketPath
        env["IT2_NONCE"] = nonce
    }

    private static func it2RandomHex(byteCount: Int) -> String {
        var bytes = [Int8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess {
            return (Data(bytes: bytes, count: byteCount) as NSData).it_hexEncoded()
        }
        // SecRandomCopyBytes effectively never fails; a UUID keeps us unpredictable
        // rather than crashing if it somehow does.
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}
