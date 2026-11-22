//
//  ConductorAudioDemux.swift
//  iTerm2SharedARC
//
//  State carrier, cryptographic microphone host grants, socket path allocator,
//  and per-connection demultiplexer for first-class PulseAudio-over-SSH
//  (`%pulse <connid> open|data <b64>|close`).
//

import CryptoKit
import Foundation
import Security

/// SSH audio proxy state carried across SSH recovery and app state restoration.
/// Mirrors `IT2ProxyState` so `listenSucceeded` remains a transient runtime flag
/// that resets on decode while `socketPath`, `micAuthorized`, and `muted` persist.
public struct SSHAudioProxyState: Equatable {
    public struct Persisted: Codable, Equatable {
        public var socketPath: String?
        public var micAuthorized: Bool?
        public var muted: Bool

        public init(socketPath: String? = nil,
                    micAuthorized: Bool? = nil,
                    muted: Bool = false) {
            self.socketPath = socketPath
            self.micAuthorized = micAuthorized
            self.muted = muted
        }
    }

    public var persisted: Persisted
    public var listenSucceeded: Bool

    public init(socketPath: String? = nil,
                micAuthorized: Bool? = nil,
                muted: Bool = false,
                listenSucceeded: Bool = false) {
        self.persisted = Persisted(socketPath: socketPath,
                                   micAuthorized: micAuthorized,
                                   muted: muted)
        self.listenSucceeded = listenSucceeded
    }

    public var socketPath: String? {
        get { persisted.socketPath }
        set { persisted.socketPath = newValue }
    }

    public var micAuthorized: Bool? {
        get { persisted.micAuthorized }
        set { persisted.micAuthorized = newValue }
    }

    public var muted: Bool {
        get { persisted.muted }
        set { persisted.muted = newValue }
    }
}

extension SSHAudioProxyState: Codable {
    public init(from decoder: Decoder) throws {
        persisted = try Persisted(from: decoder)
        listenSucceeded = false
    }

    public func encode(to encoder: Encoder) throws {
        try persisted.encode(to: encoder)
    }
}

/// Cryptographically random socket path builder respecting the portable 100-byte
/// `AF_UNIX` `sun_path` limit (macOS 104 bytes, Linux 108 bytes).
enum SSHAudioSocketPath {
    static let maxUnixSocketUTF8Bytes = 100

    static func randomHex(byteCount: Int) -> String {
        guard byteCount > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        var generator = SystemRandomNumberGenerator()
        return (0..<byteCount).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255, using: &generator))
        }.joined()
    }

    static func make(home: String,
                     randomHex: (Int) -> String = Self.randomHex) -> (path: String, usedTmpFallback: Bool) {
        let name = randomHex(8) + ".sock"
        let homePath = "\(home)/.iterm2/pulse/\(name)"
        if homePath.utf8.count <= maxUnixSocketUTF8Bytes {
            return (homePath, false)
        }
        return ("/tmp/.it2-pulse-\(randomHex(4))/native", true)
    }
}

/// Persistent "Always Allow This Host" record for remote microphone capture,
/// stored separately from `IT2HostGrant` so granting microphone capture never
/// grants `it2` API control (or vice versa).
struct AudioHostGrant: Codable, Equatable {
    let host: String
    let id: String
    let secretSHA256: String
    let granted: Date
}

enum AudioGrantToken {
    static let remoteDirectoryRelativePath = ".iterm2/audio-grants"

    static func remoteRelativePath(id: String) -> String {
        precondition(isHex(id), "an audio grant id must be lowercase hex")
        return remoteDirectoryRelativePath + "/" + id
    }

    static func mint() -> (id: String, secret: String) {
        return (SSHAudioSocketPath.randomHex(byteCount: 16),
                SSHAudioSocketPath.randomHex(byteCount: 32))
    }

    static func sha256Hex(_ value: String) -> String {
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func fileContents(id: String, secret: String) -> String {
        return "\(id):\(secret)\n"
    }

    static func verify(fileContents: String, against grant: AudioHostGrant) -> Bool {
        let line = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return false
        }
        guard String(parts[0]) == grant.id else {
            return false
        }
        return constantTimeEqualUTF8(sha256Hex(String(parts[1])), grant.secretSHA256)
    }

    static func remoteWriteStatements(id: String, secret: String, replacing: String? = nil) -> String {
        precondition(isHex(id) && isHex(secret), "audio grant token must be lowercase hex")
        let removal: String
        if let replacing, replacing != id {
            precondition(isHex(replacing), "audio grant id must be lowercase hex")
            removal = """

            try:
                os.remove(os.path.join(d, "\(replacing)"))
            except OSError:
                pass
            """
        } else {
            removal = ""
        }
        return """
        import os, tempfile
        d = os.path.expanduser("~/\(remoteDirectoryRelativePath)")
        os.makedirs(d, mode=0o700, exist_ok=True)
        os.chmod(d, 0o700)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".new.")
        try:
            os.fchmod(fd, 0o600)
            os.write(fd, b"\(id):\(secret)\\n")
        finally:
            os.close(fd)
        os.replace(tmp, os.path.join(d, "\(id)"))
        """ + removal
    }

    static func isHex(_ value: String) -> Bool {
        return !value.isEmpty && value.unicodeScalars.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }
    }

    private static func constantTimeEqualUTF8(_ a: String, _ b: String) -> Bool {
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
}

protocol AudioHostGrantBacking: AnyObject {
    func loadGrantData() -> Data?
    func saveGrantData(_ data: Data?)
}

final class AudioHostGrantStore {
    private let backing: AudioHostGrantBacking
    private let onRevokeHost: ((String) -> Void)?

    init(backing: AudioHostGrantBacking,
         onRevokeHost: ((String) -> Void)? = nil) {
        self.backing = backing
        self.onRevokeHost = onRevokeHost
    }

    var all: [AudioHostGrant] {
        guard let data = backing.loadGrantData() else {
            return []
        }
        return (try? JSONDecoder().decode([AudioHostGrant].self, from: data)) ?? []
    }

    func grant(forHost host: String) -> AudioHostGrant? {
        return all.first { $0.host == host }
    }

    func add(_ grant: AudioHostGrant) {
        save(all.filter { $0.host != grant.host } + [grant])
    }

    func remove(host: String) {
        save(all.filter { $0.host != host })
    }

    func revoke(host: String) {
        remove(host: host)
        onRevokeHost?(host)
    }

    private func save(_ grants: [AudioHostGrant]) {
        if grants.isEmpty {
            backing.saveGrantData(nil)
            return
        }
        backing.saveGrantData(try? JSONEncoder().encode(grants))
    }
}

/// Maps the user's button selection on the in-session microphone consent announcement.
@objc(iTermAudioAuthorizationOutcome)
final class AudioAuthorizationOutcome: NSObject {
    @objc static let allowIndex = 0
    @objc static let alwaysAllowThisHostIndex = 1
    @objc static let denyIndex = 2

    @objc let granted: Bool
    @objc let remember: Bool
    @objc let alwaysForHost: Bool

    @objc init(selection: Int) {
        alwaysForHost = (selection == Self.alwaysAllowThisHostIndex)
        granted = (selection == Self.allowIndex || alwaysForHost)
        remember = (granted || selection == Self.denyIndex)
        super.init()
    }
}

/// Main-thread demultiplexer for `%pulse <connid> open|data <b64>|close` frames.
final class ConductorAudioDemux {
    static let maxConnections = 64

    private let backend: PulseAudioBackend
    private let send: (String, Data) -> Void
    private let closeConnection: (String) -> Void
    private let onActivityChanged: () -> Void
    private let logger: (String) -> Void
    private var sessions: [String: PulseAudioSession] = [:]

    init(backend: PulseAudioBackend,
         send: @escaping (String, Data) -> Void,
         close: @escaping (String) -> Void,
         onActivityChanged: @escaping () -> Void = {},
         logger: @escaping (String) -> Void = { _ in }) {
        self.backend = backend
        self.send = send
        self.closeConnection = close
        self.onActivityChanged = onActivityChanged
        self.logger = logger
    }

    var openConnectionCount: Int {
        sessions.count
    }

    func hasOpenConnection(_ connid: String) -> Bool {
        sessions[connid] != nil
    }

    var isPlayingAudio: Bool {
        sessions.values.contains { $0.hasActivePlayback }
    }

    var isCapturingAudio: Bool {
        sessions.values.contains { $0.hasActiveCapture }
    }

    /// Dispatches a `%pulse <connid> <open|data|close> [payload]` line from Conductor.
    /// Returns the number of decoded payload bytes consumed for `"data"` frames, or 0 otherwise.
    @discardableResult
    func handle(_ payload: String) -> Int {
        let parts = payload.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            logger("Malformed %pulse frame: \(payload)")
            return 0
        }
        let connid = String(parts[0])
        guard !connid.isEmpty else {
            return 0
        }
        let event = parts[1]
        switch event {
        case "open":
            if let stale = sessions.removeValue(forKey: connid) {
                stale.close()
            }
            guard sessions.count < Self.maxConnections else {
                logger("pulse connection cap (\(Self.maxConnections)) reached; closing \(connid)")
                closeConnection(connid)
                return 0
            }
            let session = PulseAudioSession(
                connid: connid,
                backend: backend,
                sendFrame: { [weak self] data in
                    self?.send(connid, data)
                },
                closeTransport: { [weak self] in
                    self?.dropAndCloseTransport(connid: connid)
                },
                onActivityChanged: { [weak self] in
                    self?.onActivityChanged()
                })
            sessions[connid] = session
            return 0

        case "data":
            guard parts.count == 3, let session = sessions[connid] else {
                return 0
            }
            guard let decoded = Data(base64Encoded: String(parts[2])) else {
                logger("Malformed base64 in %pulse data for \(connid)")
                dropAndCloseTransport(connid: connid)
                return 0
            }
            session.receive(decoded)
            return decoded.count

        case "close":
            if let session = sessions.removeValue(forKey: connid) {
                session.close()
            }
            return 0

        default:
            logger("Unknown %pulse event '\(event)' for \(connid)")
            return 0
        }
    }

    /// Terminates any connection holding a microphone record stream (including corked streams),
    /// used when the user revokes microphone permission mid-session.
    func closeCaptureConnections() {
        let captureIDs = sessions.compactMap { connid, session in
            session.hasAnyRecordStream ? connid : nil
        }
        for connid in captureIDs {
            dropAndCloseTransport(connid: connid)
        }
    }

    /// Closes all active sessions locally (e.g., on SSH unhook, recovery handoff, or user disconnect).
    func closeAll(notifyTransport: Bool = false) {
        let all = sessions
        sessions.removeAll()
        for (connid, session) in all {
            session.close()
            if notifyTransport {
                closeConnection(connid)
            }
        }
    }

    private func dropAndCloseTransport(connid: String) {
        if let session = sessions.removeValue(forKey: connid) {
            session.close()
        }
        closeConnection(connid)
    }
}
