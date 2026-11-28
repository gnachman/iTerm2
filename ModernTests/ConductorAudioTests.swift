//
//  ConductorAudioTests.swift
//  iTerm2
//
//  Unit tests for SSHAudioProxyState, SSHAudioSocketPath, AudioGrantToken,
//  AudioHostGrantStore, AudioAuthorizationOutcome, ConductorAudioDemux,
//  FramerFlowController (.pulse lane), and Conductor+Audio integration.
//

import Foundation
#if !STANDALONE_SWIFT_TEST
import XCTest
@testable import iTerm2SharedARC
#endif

private final class MockPulseBackend: PulseAudioBackend {
    var micAllowed = true
    var micPromptCount = 0
    var activePlaybackIDs = Set<UUID>()
    var activeRecordIDs = Set<UUID>()
    var recordHandlers: [UUID: (Data) -> Void] = [:]

    func openPlaybackStream(id: UUID,
                            spec: PulseSampleSpec,
                            prebufBytes: Int,
                            corked: Bool,
                            onDataConsumed: @escaping (Int) -> Void) -> Bool {
        activePlaybackIDs.insert(id)
        return true
    }

    func writePlaybackData(id: UUID, data: Data) {}
    func setPlaybackCorked(id: UUID, corked: Bool) {}
    func flushPlaybackStream(id: UUID) {}
    func drainPlaybackStream(id: UUID, completion: @escaping () -> Void) { completion() }
    func playbackLatencyUsec(id: UUID) -> UInt64 { 15_000 }
    func closePlaybackStream(id: UUID) { activePlaybackIDs.remove(id) }

    func requestMicrophoneAuthorization(completion: @escaping (Bool) -> Void) {
        micPromptCount += 1
        completion(micAllowed)
    }

    func openRecordStream(id: UUID,
                          spec: PulseSampleSpec,
                          fragSize: Int,
                          corked: Bool,
                          onCaptureData: @escaping (Data) -> Void) -> Bool {
        activeRecordIDs.insert(id)
        recordHandlers[id] = onCaptureData
        return true
    }

    func setRecordCorked(id: UUID, corked: Bool) {}
    func flushRecordStream(id: UUID) {}
    func recordLatencyUsec(id: UUID) -> UInt64 { 15_000 }
    func closeRecordStream(id: UUID) {
        activeRecordIDs.remove(id)
        recordHandlers.removeValue(forKey: id)
    }
}

private final class InMemoryAudioGrantBacking: AudioHostGrantBacking {
    var data: Data?
    func loadGrantData() -> Data? { data }
    func saveGrantData(_ data: Data?) { self.data = data }
}

final class ConductorAudioTests: XCTestCase {

    // MARK: - SSHAudioProxyState & Socket Path

    func testSSHAudioProxyStatePersistsFieldsAndResetsTransientListenFlag() throws {
        var state = SSHAudioProxyState(socketPath: "/home/u/.iterm2/pulse/abc.sock",
                                       micAuthorized: true,
                                       muted: true,
                                       listenSucceeded: true)
        XCTAssertTrue(state.listenSucceeded)
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SSHAudioProxyState.self, from: encoded)
        XCTAssertEqual(decoded.socketPath, "/home/u/.iterm2/pulse/abc.sock")
        XCTAssertEqual(decoded.micAuthorized, true)
        XCTAssertTrue(decoded.muted)
        XCTAssertFalse(decoded.listenSucceeded, "listenSucceeded must reset across Codable state restoration")

        state.listenSucceeded = false
        XCTAssertEqual(decoded, state)
    }

    func testSSHAudioSocketPathUsesHomeWhenShortAndTmpWhenExceedingSunPathBudget() {
        let short = SSHAudioSocketPath.make(home: "/home/alice")
        XCTAssertFalse(short.usedTmpFallback)
        XCTAssertTrue(short.path.hasPrefix("/home/alice/.iterm2/pulse/"), short.path)
        XCTAssertTrue(short.path.hasSuffix(".sock"), short.path)
        XCTAssertLessThanOrEqual(short.path.utf8.count, SSHAudioSocketPath.maxUnixSocketUTF8Bytes)

        let longHome = "/Volumes/nfs/corporate/engineering/users/" + String(repeating: "x", count: 60)
        let fallback = SSHAudioSocketPath.make(home: longHome)
        XCTAssertTrue(fallback.usedTmpFallback)
        XCTAssertTrue(fallback.path.hasPrefix("/tmp/.it2-pulse-"), fallback.path)
        XCTAssertTrue(fallback.path.hasSuffix("/native"), fallback.path)
        XCTAssertLessThanOrEqual(fallback.path.utf8.count, SSHAudioSocketPath.maxUnixSocketUTF8Bytes)
    }

    // MARK: - Cryptographic Host Grants & Authorization Outcome

    func testAudioGrantTokenMintVerifyAndStoreLifecycle() {
        let token = AudioGrantToken.mint()
        XCTAssertTrue(AudioGrantToken.isHex(token.id))
        XCTAssertTrue(AudioGrantToken.isHex(token.secret))
        XCTAssertEqual(token.id.count, 32)
        XCTAssertEqual(token.secret.count, 64)

        let grant = AudioHostGrant(host: "user@delu:22",
                                   id: token.id,
                                   secretSHA256: AudioGrantToken.sha256Hex(token.secret),
                                   granted: Date())
        let contents = AudioGrantToken.fileContents(id: token.id, secret: token.secret)
        XCTAssertTrue(AudioGrantToken.verify(fileContents: contents, against: grant))
        XCTAssertFalse(AudioGrantToken.verify(fileContents: "\(token.id):deadbeef\n", against: grant))
        XCTAssertFalse(AudioGrantToken.verify(fileContents: "0000:\(token.secret)\n", against: grant))

        let py = AudioGrantToken.remoteWriteStatements(id: token.id, secret: token.secret, replacing: "abcd1234")
        XCTAssertTrue(py.contains(".iterm2/audio-grants"))
        XCTAssertTrue(py.contains("abcd1234"))

        let backing = InMemoryAudioGrantBacking()
        var revokedHosts: [String] = []
        let store = AudioHostGrantStore(backing: backing) { host in
            revokedHosts.append(host)
        }
        store.add(grant)
        XCTAssertEqual(store.grant(forHost: "user@delu:22"), grant)
        store.revoke(host: "user@delu:22")
        XCTAssertNil(store.grant(forHost: "user@delu:22"))
        XCTAssertEqual(revokedHosts, ["user@delu:22"])
    }

    func testAudioAuthorizationOutcomeButtonMapping() {
        let allow = AudioAuthorizationOutcome(selection: AudioAuthorizationOutcome.allowIndex)
        XCTAssertTrue(allow.granted)
        XCTAssertTrue(allow.remember)
        XCTAssertFalse(allow.alwaysForHost)

        let always = AudioAuthorizationOutcome(selection: AudioAuthorizationOutcome.alwaysAllowThisHostIndex)
        XCTAssertTrue(always.granted)
        XCTAssertTrue(always.remember)
        XCTAssertTrue(always.alwaysForHost)

        let deny = AudioAuthorizationOutcome(selection: AudioAuthorizationOutcome.denyIndex)
        XCTAssertFalse(deny.granted)
        XCTAssertTrue(deny.remember)
        XCTAssertFalse(deny.alwaysForHost)

        let dismissed = AudioAuthorizationOutcome(selection: -2)
        XCTAssertFalse(dismissed.granted)
        XCTAssertFalse(dismissed.remember)
        XCTAssertFalse(dismissed.alwaysForHost)
    }

    // MARK: - ConductorAudioDemux Multiplexing & Revocation

    private func buildControlFrame(command: PulseCommand, tag: UInt32, body: (inout PulseTagstructWriter) -> Void) -> Data {
        var writer = PulseTagstructWriter()
        writer.putU32(command.rawValue)
        writer.putU32(tag)
        body(&writer)
        return PulsePStreamFrame.controlPacket(writer.data).encode()
    }

    private func buildAuthFrame(tag: UInt32 = 1) -> Data {
        return buildControlFrame(command: .auth, tag: tag) { w in
            w.putU32(35 | 0x8000_0000 | 0x4000_0000)
            w.putArbitrary(Data(repeating: 0xAA, count: 256))
        }
    }

    private func buildCreateRecordStreamFrame(tag: UInt32 = 2) -> Data {
        return buildControlFrame(command: .createRecordStream, tag: tag) { w in
            let spec = PulseSampleSpec(format: PulseSampleFormat.s16le.rawValue, channels: 1, rate: 16_000)
            w.putSampleSpec(spec)
            w.putChannelMap(PulseChannelMap.defaultMap(channels: 1))
            w.putU32(PulseAudioSession.invalidIndex)
            w.putString(nil)
            w.putU32(65_536) // maxlength
            w.putBoolean(false) // corked = false -> immediately active
            w.putU32(3_200) // fragsize
            w.putBoolean(false) // no_remap
            w.putBoolean(false) // no_reformat
            w.putBoolean(false) // fix_format
            w.putBoolean(false) // fix_rate
            w.putBoolean(false) // fix_channels
            w.putBoolean(false) // no_move
            w.putBoolean(false) // variable_rate
            w.putBoolean(false) // peak_detect
            w.putBoolean(false) // adjust_latency
            w.putProplist(PulseProplist(strings: ["media.name": "agy-voice"]))
            w.putU32(PulseAudioSession.invalidIndex) // direct_on_input
            w.putBoolean(false) // early_requests
            w.putBoolean(false) // dont_inhibit_auto_suspend
            w.putBoolean(false) // fail_on_suspend
            w.putU8(0) // n_formats
            w.putCVolume(PulseCVolume.norm(channels: 1))
            w.putBoolean(false) // muted
            w.putBoolean(false) // volume_set
            w.putBoolean(false) // muted_set
            w.putBoolean(false) // relative_volume
            w.putBoolean(false) // passthrough
        }
    }

    func testDemuxMultiplexesConnectionsAndRevocationClosesActiveCapture() throws {
        let backend = MockPulseBackend()
        var downstream: [(String, Data)] = []
        var closedConns: [String] = []
        var activityEvents = 0

        let demux = ConductorAudioDemux(
            backend: backend,
            send: { connid, data in downstream.append((connid, data)) },
            close: { connid in closedConns.append(connid) },
            onActivityChanged: { activityEvents += 1 })

        demux.handle("c1 open")
        demux.handle("c2 open")
        XCTAssertEqual(demux.openConnectionCount, 2)
        XCTAssertTrue(demux.hasOpenConnection("c1"))
        XCTAssertTrue(demux.hasOpenConnection("c2"))

        // Authenticate both connections and open an active record stream on c1.
        let authB64 = buildAuthFrame(tag: 1).base64EncodedString()
        demux.handle("c1 data \(authB64)")
        demux.handle("c2 data \(authB64)")
        XCTAssertEqual(downstream.count, 2)

        let recB64 = buildCreateRecordStreamFrame(tag: 2).base64EncodedString()
        demux.handle("c1 data \(recB64)")
        XCTAssertTrue(demux.isCapturingAudio)
        XCTAssertEqual(backend.activeRecordIDs.count, 1)
        XCTAssertGreaterThan(activityEvents, 0)

        // Revoking microphone permission mid-session closes c1 (capturing) while keeping c2 alive!
        demux.closeCaptureConnections()
        XCTAssertFalse(demux.isCapturingAudio)
        XCTAssertFalse(demux.hasOpenConnection("c1"))
        XCTAssertTrue(demux.hasOpenConnection("c2"))
        XCTAssertEqual(closedConns, ["c1"])
        XCTAssertEqual(backend.activeRecordIDs.count, 0)

        // Malformed base64 on c2 drops c2 and notifies framer to close socket.
        demux.handle("c2 data !!!not-base64!!!")
        XCTAssertFalse(demux.hasOpenConnection("c2"))
        XCTAssertEqual(closedConns, ["c1", "c2"])
    }

    func testDemuxEnforcesMaxConnectionsCap() {
        let backend = MockPulseBackend()
        var closedConns: [String] = []
        let demux = ConductorAudioDemux(
            backend: backend,
            send: { _, _ in },
            close: { connid in closedConns.append(connid) })

        for i in 0..<ConductorAudioDemux.maxConnections {
            demux.handle("c\(i) open")
        }
        XCTAssertEqual(demux.openConnectionCount, ConductorAudioDemux.maxConnections)
        XCTAssertTrue(closedConns.isEmpty)

        demux.handle("overflow open")
        XCTAssertEqual(demux.openConnectionCount, ConductorAudioDemux.maxConnections)
        XCTAssertFalse(demux.hasOpenConnection("overflow"))
        XCTAssertEqual(closedConns, ["overflow"])

        demux.closeAll()
        XCTAssertEqual(demux.openConnectionCount, 0)
    }

    // MARK: - FramerFlowController (.pulse lane)

    func testFramerFlowControllerGrantsAndReplenishesPulseFlow() {
        var commands: [FramerFlowController.Command] = []
        var now: TimeInterval = 1_000
        let controller = FramerFlowController(now: now, recovering: false) { cmd in
            commands.append(cmd)
        }
        controller.pingDidReply(roundTrip: 0.04, now: now)
        controller.flowDidStart(.it2, now: now)
        controller.flowDidStart(.pulse, now: now)

        let initialPulseGrant = commands.compactMap { cmd -> Int? in
            if case let .grant(.pulse, bytes) = cmd { return bytes }
            return nil
        }
        XCTAssertEqual(initialPulseGrant.count, 1)
        let credit = initialPulseGrant[0]
        XCTAssertGreaterThan(credit, 0)

        commands.removeAll()
        controller.frameDidArrive(now: now,
                                  flow: .pulse,
                                  sendMilliseconds: 5_000,
                                  bytes: credit,
                                  limited: true,
                                  exempt: false)
        now += 0.03
        controller.tick(now: now)
        XCTAssertTrue(commands.isEmpty, "credit must not replenish before audio demux consumes bytes")

        controller.flowDidConsume(.pulse, bytes: credit, now: now)
        now += 0.03
        controller.tick(now: now)
        let replenished = commands.compactMap { cmd -> Int? in
            if case let .grant(.pulse, bytes) = cmd { return bytes }
            return nil
        }
        XCTAssertEqual(replenished.count, 1)
        XCTAssertGreaterThanOrEqual(replenished[0], credit)
    }

    func testFramerFlowControllerPulseHasHighFloorImmediateReplenishAndNoFalseRecalls() {
        var commands: [FramerFlowController.Command] = []
        var now: TimeInterval = 2_000
        let controller = FramerFlowController(now: now, recovering: false) { cmd in
            commands.append(cmd)
        }
        controller.pingDidReply(roundTrip: 0.04, now: now)
        controller.flowDidStart(.it2, now: now)
        controller.flowDidStart(.pulse, now: now)

        let initialPulseGrant = commands.compactMap { cmd -> Int? in
            if case let .grant(.pulse, bytes) = cmd { return bytes }
            return nil
        }.first
        XCTAssertNotNil(initialPulseGrant)
        XCTAssertGreaterThanOrEqual(initialPulseGrant ?? 0, 256 * 1024)
        XCTAssertGreaterThanOrEqual(controller.window(of: .pulse) ?? 0, 256 * 1024)

        // Consuming >= 1/4 of the .pulse window replenishes immediately on replenish(.pulse),
        // without triggering creditRecalls despite .pulse exceeding the shared leader window.
        commands.removeAll()
        let burst = 70_000
        controller.frameDidArrive(now: now,
                                  flow: .pulse,
                                  sendMilliseconds: 10_000,
                                  bytes: burst,
                                  limited: false,
                                  exempt: false)
        controller.flowDidConsume(.pulse, bytes: burst, now: now)
        controller.replenish(.pulse, now: now)

        let immediateGrants = commands.compactMap { cmd -> Int? in
            if case let .grant(.pulse, bytes) = cmd { return bytes }
            return nil
        }
        XCTAssertEqual(immediateGrants, [burst])
        now += 0.2
        controller.tick(now: now)
        XCTAssertEqual(controller.statistics.creditRecalls, 0)
    }

#if !STANDALONE_SWIFT_TEST
    // MARK: - Full Conductor + Audio Integration (Xcode ModernTests)

    func testPulseFramerCommandWireEncoding() {
        let listen = Conductor.Command.framerPulseListen(path: "/tmp/.it2-pulse-abcd/native")
        XCTAssertEqual(listen.stringValue, "pulselisten\n/tmp/.it2-pulse-abcd/native")
        XCTAssertTrue(listen.isFramer)

        let send = Conductor.Command.framerPulseSend(connid: "p7", data: Data("pcm".utf8))
        XCTAssertEqual(send.stringValue, "pulsesend\np7\ncGNt")
        XCTAssertTrue(send.isFramer)

        let close = Conductor.Command.framerPulseClose(connid: "p7")
        XCTAssertEqual(close.stringValue, "pulseclose\np7")
        XCTAssertTrue(close.isFramer)
    }

    @MainActor
    func testConductorAudioRecoveryAndRestorableState() throws {
        let source = Conductor("localhost", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                               varsToSend: [:], clientVars: [:], initialDirectory: nil,
                               shouldInjectShellIntegration: false, parent: nil)
        source.pulseSocketPath = "/home/u/.iterm2/pulse/1234.sock"
        source.audioMicAuthorized = true
        source.setRemoteAudioMuted(true)
        source.pulseListenSucceeded = true

        let shim = Conductor("localhost", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                             varsToSend: [:], clientVars: [:], initialDirectory: nil,
                             shouldInjectShellIntegration: false, parent: nil)
        shim.adoptAudioRecoveryState(from: source)
        XCTAssertEqual(shim.pulseSocketPath, "/home/u/.iterm2/pulse/1234.sock")
        XCTAssertEqual(shim.audioMicAuthorized, true)
        XCTAssertTrue(shim.isRemoteAudioMuted)
        XCTAssertTrue(shim.pulseListenSucceeded)

        let recovery = ConductorRecovery(pid: 42, dcsID: "dcs", tree: [:], sshargs: "localhost",
                                         boolArgs: "", clientUniqueID: "cid", version: 2,
                                         flow: nil, parent: nil,
                                         it2Proxy: shim.it2Proxy,
                                         audioProxy: shim.audioProxy)
        let recovered = Conductor(recovery: recovery)
        XCTAssertEqual(recovered.pulseSocketPath, "/home/u/.iterm2/pulse/1234.sock")
        XCTAssertEqual(recovered.audioMicAuthorized, true)
        XCTAssertTrue(recovered.isRemoteAudioMuted)
        XCTAssertTrue(recovered.pulseListenSucceeded)

        let json = try XCTUnwrap(recovered.jsonValue)
        let restored = try XCTUnwrap(Conductor.create(json, delegate: nil))
        XCTAssertEqual(restored.pulseSocketPath, "/home/u/.iterm2/pulse/1234.sock")
        XCTAssertEqual(restored.audioMicAuthorized, true)
        XCTAssertTrue(restored.isRemoteAudioMuted)
        XCTAssertFalse(restored.pulseListenSucceeded)
    }

    // MARK: - VT100Parser %pulse Framing

    private func parseStream(_ bytes: [UInt8], parser: VT100Parser) -> [VT100Token] {
        bytes.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        var tokens = [VT100Token]()
        for i in 0..<CVectorCount(&vector) {
            tokens.append(CVectorGetObject(&vector, i) as! VT100Token)
        }
        return tokens
    }

    private func makeHookedParser() -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        let hook = Array("\u{1b}P2000p0 boolargs -\n".utf8)
        _ = parseStream(hook, parser: p)
        return p
    }

    private func osc134(_ payload: String) -> [UInt8] {
        Array("\u{1b}]134;:\(payload)\u{1b}\\".utf8)
    }

    func testPulseFrameDeliveredWholeAndNestedGetsChildDepth() {
        let parser = makeHookedParser()
        let b64 = String(repeating: "QUJD", count: 1024)
        let payload = "p5 data \(b64)"
        let tokens = parseStream(osc134("%pulse \(payload)"), parser: parser)
        let pulse = tokens.filter { $0.type == SSH_PULSE }
        XCTAssertEqual(pulse.count, 1)
        XCTAssertEqual(pulse.first?.string, payload)

        let nestedParser = makeHookedParser()
        var inner = Array("\u{1b}P2000p0 boolargs -\n".utf8)
        inner += osc134("%pulse p9 open")
        var stream = osc134("%output out1 100 -1 0")
        stream += inner
        stream += osc134("%end out1")
        let nestedTokens = parseStream(stream, parser: nestedParser)
        let nestedPulse = nestedTokens.filter { $0.type == SSH_PULSE }
        XCTAssertEqual(nestedPulse.count, 1)
        XCTAssertEqual(nestedPulse.first?.string, "p9 open")
        let info = SSHInfoDescription(nestedPulse.first!.sshInfo)
        XCTAssertFalse(info.contains("invalid"), info)
        XCTAssertTrue(info.contains("depth=1"), info)
    }
#endif
}
