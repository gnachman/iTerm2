//
//  PulseAudioSession.swift
//  iTerm2SharedARC
//
//  Per-connection PulseAudio Native Protocol v35 state machine (`SHM=0`,
//  `MEMFD=0`), translating `libpulse` control/data frames into `PulseAudioBackend`
//  calls with zero external C library dependencies.
//

import Foundation

enum PulseCommand: UInt32 {
    case error = 0
    case timeout = 1
    case reply = 2
    case createPlaybackStream = 3
    case deletePlaybackStream = 4
    case createRecordStream = 5
    case deleteRecordStream = 6
    case exit = 7
    case auth = 8
    case setClientName = 9
    case lookupSink = 10
    case lookupSource = 11
    case drainPlaybackStream = 12
    case stat = 13
    case getPlaybackLatency = 14
    case createUploadStream = 15
    case deleteUploadStream = 16
    case finishUploadStream = 17
    case playSample = 18
    case removeSample = 19
    case getServerInfo = 20
    case getSinkInfo = 21
    case getSinkInfoList = 22
    case getSourceInfo = 23
    case getSourceInfoList = 24
    case getModuleInfo = 25
    case getModuleInfoList = 26
    case getClientInfo = 27
    case getClientInfoList = 28
    case getSinkInputInfo = 29
    case getSinkInputInfoList = 30
    case getSourceOutputInfo = 31
    case getSourceOutputInfoList = 32
    case getSampleInfo = 33
    case getSampleInfoList = 34
    case subscribe = 35
    case setSinkVolume = 36
    case setSinkInputVolume = 37
    case setSourceVolume = 38
    case setSinkMute = 39
    case setSourceMute = 40
    case corkPlaybackStream = 41
    case flushPlaybackStream = 42
    case triggerPlaybackStream = 43
    case setDefaultSink = 44
    case setDefaultSource = 45
    case setPlaybackStreamName = 46
    case setRecordStreamName = 47
    case killClient = 48
    case killSinkInput = 49
    case killSourceOutput = 50
    case loadModule = 51
    case unloadModule = 52
    case getRecordLatency = 57
    case corkRecordStream = 58
    case flushRecordStream = 59
    case prebufPlaybackStream = 60
    case request = 61
    case overflow = 62
    case underflow = 63
    case playbackStreamKilled = 64
    case recordStreamKilled = 65
    case subscribeEvent = 66
    case moveSinkInput = 67
    case moveSourceOutput = 68
    case setSinkInputMute = 69
    case suspendSink = 70
    case suspendSource = 71
    case setPlaybackStreamBufferAttr = 72
    case setRecordStreamBufferAttr = 73
    case updatePlaybackStreamSampleRate = 74
    case updateRecordStreamSampleRate = 75
    case updateRecordStreamProplist = 80
    case updatePlaybackStreamProplist = 81
    case updateClientProplist = 82
    case removeRecordStreamProplist = 83
    case removePlaybackStreamProplist = 84
    case removeClientProplist = 85
    case started = 86
    case `extension` = 87
    case getCardInfo = 88
    case getCardInfoList = 89
    case setCardProfile = 90
    case clientEvent = 91
    case playbackStreamEvent = 92
    case recordStreamEvent = 93
    case playbackBufferAttrChanged = 94
    case recordBufferAttrChanged = 95
    case setSinkPort = 96
    case setSourcePort = 97
    case setSourceOutputVolume = 98
    case setSourceOutputMute = 99
    case setPortLatencyOffset = 100
    case enableSRBChannel = 101
    case disableSRBChannel = 102
    case registerMemfdShmid = 103
    case sendObjectMessage = 104
}

enum PulseErrorCode: UInt32 {
    case ok = 0
    case access = 1
    case command = 2
    case invalid = 3
    case exist = 4
    case noEntity = 5
    case connectionRefused = 6
    case protocolError = 7
    case timeout = 8
    case internalError = 10
    case version = 17
    case notSupported = 19
    case noExtension = 21
}

protocol PulseAudioBackend: AnyObject {
    func openPlaybackStream(id: UUID,
                            spec: PulseSampleSpec,
                            prebufBytes: Int,
                            corked: Bool,
                            onDataConsumed: @escaping (Int) -> Void) -> Bool
    func writePlaybackData(id: UUID, data: Data)
    func setPlaybackCorked(id: UUID, corked: Bool)
    func triggerPlaybackStream(id: UUID)
    func setPlaybackVolume(id: UUID, gain: Float)
    func flushPlaybackStream(id: UUID)
    func drainPlaybackStream(id: UUID, completion: @escaping () -> Void)
    func playbackLatencyUsec(id: UUID) -> UInt64
    func closePlaybackStream(id: UUID)

    func requestMicrophoneAuthorization(completion: @escaping (Bool) -> Void)
    func openRecordStream(id: UUID,
                          spec: PulseSampleSpec,
                          fragSize: Int,
                          corked: Bool,
                          onCaptureData: @escaping (Data) -> Void) -> Bool
    func setRecordCorked(id: UUID, corked: Bool)
    func flushRecordStream(id: UUID)
    func recordLatencyUsec(id: UUID) -> UInt64
    func closeRecordStream(id: UUID)
}

extension PulseAudioBackend {
    func triggerPlaybackStream(id: UUID) {}
    func setPlaybackVolume(id: UUID, gain: Float) {}
}

final class PulseAudioSession {
    static let protocolVersion: UInt32 = 35
    static let protocolVersionMask: UInt32 = 0x0000_FFFF
    static let cookieLength: UInt32 = 256
    static let invalidIndex: UInt32 = 0xFFFF_FFFF
    static let sinkIndex: UInt32 = 0
    static let sourceIndex: UInt32 = 0
    static let sinkName = "iterm2_mac_speaker"
    static let sourceName = "iterm2_mac_mic"
    static let monitorSourceName = "iterm2_mac_speaker.monitor"
    static let serverName = "PulseAudio (on iTerm2 SSH)"
    static let serverVersion = "17.0"
    static let maxStreamsPerConnection = 32

    private final class PlaybackStreamState {
        let id = UUID()
        let channel: UInt32
        let sinkInputIndex: UInt32
        var spec: PulseSampleSpec
        var channelMap: PulseChannelMap
        var proplist: PulseProplist
        var maxlength: UInt32
        var tlength: UInt32
        var prebuf: UInt32
        var minreq: UInt32
        var corked: Bool
        var muted: Bool
        var volume: PulseCVolume
        var writeIndex: Int64 = 0
        var readIndex: Int64 = 0
        var pendingCreditBytes: Int = 0
        var startedSent = false

        init(channel: UInt32,
             sinkInputIndex: UInt32,
             spec: PulseSampleSpec,
             channelMap: PulseChannelMap,
             proplist: PulseProplist,
             maxlength: UInt32,
             tlength: UInt32,
             prebuf: UInt32,
             minreq: UInt32,
             corked: Bool,
             muted: Bool,
             volume: PulseCVolume) {
            self.channel = channel
            self.sinkInputIndex = sinkInputIndex
            self.spec = spec
            self.channelMap = channelMap
            self.proplist = proplist
            self.maxlength = maxlength
            self.tlength = tlength
            self.prebuf = prebuf
            self.minreq = minreq
            self.corked = corked
            self.muted = muted
            self.volume = volume
        }
    }

    private final class RecordStreamState {
        let id = UUID()
        let channel: UInt32
        let sourceOutputIndex: UInt32
        var spec: PulseSampleSpec
        var channelMap: PulseChannelMap
        var proplist: PulseProplist
        var maxlength: UInt32
        var fragsize: UInt32
        var corked: Bool
        var muted: Bool
        var volume: PulseCVolume
        var writeIndex: Int64 = 0
        var readIndex: Int64 = 0

        init(channel: UInt32,
             sourceOutputIndex: UInt32,
             spec: PulseSampleSpec,
             channelMap: PulseChannelMap,
             proplist: PulseProplist,
             maxlength: UInt32,
             fragsize: UInt32,
             corked: Bool,
             muted: Bool,
             volume: PulseCVolume) {
            self.channel = channel
            self.sourceOutputIndex = sourceOutputIndex
            self.spec = spec
            self.channelMap = channelMap
            self.proplist = proplist
            self.maxlength = maxlength
            self.fragsize = fragsize
            self.corked = corked
            self.muted = muted
            self.volume = volume
        }
    }

    let connid: String
    private weak var backend: PulseAudioBackend?
    private let sendFrame: (Data) -> Void
    private let closeTransport: () -> Void
    private let onActivityChanged: () -> Void

    private let reader = PulsePStreamReader()
    private(set) var negotiatedVersion: UInt32 = 35
    private(set) var isAuthorized = false
    private(set) var clientIndex: UInt32 = 1
    private(set) var clientProplist = PulseProplist()
    private var nextStreamChannel: UInt32 = 1
    private var playbackStreams: [UInt32: PlaybackStreamState] = [:]
    private var recordStreams: [UInt32: RecordStreamState] = [:]
    private var isClosed = false

    init(connid: String,
         backend: PulseAudioBackend,
         sendFrame: @escaping (Data) -> Void,
         closeTransport: @escaping () -> Void,
         onActivityChanged: @escaping () -> Void = {}) {
        self.connid = connid
        self.backend = backend
        self.sendFrame = sendFrame
        self.closeTransport = closeTransport
        self.onActivityChanged = onActivityChanged
    }

    var hasActivePlayback: Bool {
        playbackStreams.values.contains { !$0.corked }
    }

    var hasActiveCapture: Bool {
        recordStreams.values.contains { !$0.corked }
    }

    var hasAnyRecordStream: Bool {
        !recordStreams.isEmpty
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        let pbIDs = playbackStreams.values.map(\.id)
        let recIDs = recordStreams.values.map(\.id)
        playbackStreams.removeAll()
        recordStreams.removeAll()
        reader.reset()
        for id in pbIDs {
            backend?.closePlaybackStream(id: id)
        }
        for id in recIDs {
            backend?.closeRecordStream(id: id)
        }
        onActivityChanged()
    }

    func receive(_ data: Data) {
        guard !isClosed else { return }
        do {
            let frames = try reader.feed(data)
            for frame in frames {
                if isClosed {
                    break
                }
                if frame.isControlPacket {
                    try handleControlPacket(frame.payload)
                } else {
                    handleAudioBlock(frame)
                }
            }
        } catch {
            close()
            closeTransport()
        }
    }

    // MARK: - Control Dispatch

    private func handleControlPacket(_ payload: Data) throws {
        var r = PulseTagstructReader(data: payload)
        let rawCmd = try r.getU32()
        let tag = try r.getU32()

        guard let cmd = PulseCommand(rawValue: rawCmd) else {
            sendError(tag: tag, code: .command)
            return
        }

        if cmd != .auth && !isAuthorized {
            sendError(tag: tag, code: .access)
            return
        }

        switch cmd {
        case .auth:
            try handleAuth(tag: tag, reader: &r)
        case .setClientName:
            try handleSetClientName(tag: tag, reader: &r)
        case .exit:
            sendSimpleAck(tag: tag)
            close()
            closeTransport()
        case .getServerInfo:
            handleGetServerInfo(tag: tag)
        case .lookupSink:
            try handleLookup(tag: tag, isSink: true, reader: &r)
        case .lookupSource:
            try handleLookup(tag: tag, isSink: false, reader: &r)
        case .getSinkInfo:
            try handleGetDeviceInfo(tag: tag, isSink: true, reader: &r)
        case .getSinkInfoList:
            handleGetDeviceInfoList(tag: tag, isSink: true)
        case .getSourceInfo:
            try handleGetDeviceInfo(tag: tag, isSink: false, reader: &r)
        case .getSourceInfoList:
            handleGetDeviceInfoList(tag: tag, isSink: false)
        case .getCardInfoList, .getModuleInfoList, .getSampleInfoList:
            sendSimpleAck(tag: tag)
        case .getCardInfo, .getModuleInfo, .getSampleInfo:
            sendError(tag: tag, code: .noEntity)
        case .getClientInfoList:
            handleGetClientInfoList(tag: tag)
        case .getClientInfo:
            try handleGetClientInfo(tag: tag, reader: &r)
        case .getSinkInputInfoList:
            handleGetSinkInputInfoList(tag: tag)
        case .getSinkInputInfo:
            try handleGetSinkInputInfo(tag: tag, reader: &r)
        case .getSourceOutputInfoList:
            handleGetSourceOutputInfoList(tag: tag)
        case .getSourceOutputInfo:
            try handleGetSourceOutputInfo(tag: tag, reader: &r)
        case .stat:
            handleStat(tag: tag)
        case .subscribe:
            _ = try r.getU32()
            sendSimpleAck(tag: tag)
        case .createPlaybackStream:
            try handleCreatePlaybackStream(tag: tag, reader: &r)
        case .deletePlaybackStream:
            let ch = try r.getU32()
            guard let stream = playbackStreams.removeValue(forKey: ch) else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            backend?.closePlaybackStream(id: stream.id)
            sendSimpleAck(tag: tag)
            onActivityChanged()
        case .corkPlaybackStream:
            let ch = try r.getU32()
            let cork = try r.getBoolean()
            guard let stream = playbackStreams[ch] else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            stream.corked = cork
            backend?.setPlaybackCorked(id: stream.id, corked: cork)
            sendSimpleAck(tag: tag)
            onActivityChanged()
        case .flushPlaybackStream, .triggerPlaybackStream, .prebufPlaybackStream:
            let ch = try r.getU32()
            guard let stream = playbackStreams[ch] else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            if cmd == .flushPlaybackStream {
                let flushed = Int(max(0, stream.writeIndex - stream.readIndex))
                backend?.flushPlaybackStream(id: stream.id)
                stream.readIndex = stream.writeIndex
                if flushed > 0 {
                    sendPlaybackRequestCredit(channel: ch, bytes: flushed, force: true)
                }
            } else if cmd == .triggerPlaybackStream {
                backend?.triggerPlaybackStream(id: stream.id)
            }
            sendSimpleAck(tag: tag)
        case .drainPlaybackStream:
            let ch = try r.getU32()
            guard let stream = playbackStreams[ch], let backend else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            backend.drainPlaybackStream(id: stream.id) { [weak self] in
                guard let self, !self.isClosed else { return }
                self.sendSimpleAck(tag: tag)
            }
        case .getPlaybackLatency:
            try handleGetPlaybackLatency(tag: tag, reader: &r)
        case .setPlaybackStreamBufferAttr:
            try handleSetPlaybackBufferAttr(tag: tag, reader: &r)
        case .createRecordStream:
            try handleCreateRecordStream(tag: tag, reader: &r)
        case .deleteRecordStream:
            let ch = try r.getU32()
            guard let stream = recordStreams.removeValue(forKey: ch) else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            backend?.closeRecordStream(id: stream.id)
            sendSimpleAck(tag: tag)
            onActivityChanged()
        case .corkRecordStream:
            let ch = try r.getU32()
            let cork = try r.getBoolean()
            guard let stream = recordStreams[ch] else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            if !cork, let backend {
                backend.requestMicrophoneAuthorization { [weak self] granted in
                    guard let self, !self.isClosed else { return }
                    guard granted else {
                        if let removed = self.recordStreams.removeValue(forKey: ch) {
                            self.backend?.closeRecordStream(id: removed.id)
                        }
                        self.sendError(tag: tag, code: .access)
                        self.onActivityChanged()
                        return
                    }
                    guard let active = self.recordStreams[ch] else {
                        self.sendError(tag: tag, code: .noEntity)
                        return
                    }
                    active.corked = false
                    self.backend?.setRecordCorked(id: active.id, corked: false)
                    self.sendSimpleAck(tag: tag)
                    self.onActivityChanged()
                }
            } else {
                stream.corked = cork
                backend?.setRecordCorked(id: stream.id, corked: cork)
                sendSimpleAck(tag: tag)
                onActivityChanged()
            }
        case .flushRecordStream:
            let ch = try r.getU32()
            guard let stream = recordStreams[ch] else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            backend?.flushRecordStream(id: stream.id)
            stream.readIndex = stream.writeIndex
            sendSimpleAck(tag: tag)
        case .getRecordLatency:
            try handleGetRecordLatency(tag: tag, reader: &r)
        case .setRecordStreamBufferAttr:
            try handleSetRecordBufferAttr(tag: tag, reader: &r)
        case .setSinkInputVolume:
            let idx = try r.getU32()
            let cvol = try r.getCVolume()
            guard let stream = playbackStreams.values.first(where: { $0.sinkInputIndex == idx }) else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            stream.volume = cvol
            backend?.setPlaybackVolume(id: stream.id, gain: Self.linearGain(for: stream))
            sendSimpleAck(tag: tag)
        case .setSinkInputMute:
            let idx = try r.getU32()
            let mute = try r.getBoolean()
            guard let stream = playbackStreams.values.first(where: { $0.sinkInputIndex == idx }) else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            stream.muted = mute
            backend?.setPlaybackVolume(id: stream.id, gain: Self.linearGain(for: stream))
            sendSimpleAck(tag: tag)
        case .updateClientProplist, .updatePlaybackStreamProplist, .updateRecordStreamProplist,
             .removeClientProplist, .removePlaybackStreamProplist, .removeRecordStreamProplist,
             .setPlaybackStreamName, .setRecordStreamName, .setSinkVolume,
             .setSourceVolume, .setSinkMute, .setSourceMute,
             .setSourceOutputVolume, .setSourceOutputMute, .setDefaultSink, .setDefaultSource,
             .suspendSink, .suspendSource, .updatePlaybackStreamSampleRate, .updateRecordStreamSampleRate:
            sendSimpleAck(tag: tag)
        case .extension:
            sendError(tag: tag, code: .noExtension)
        default:
            sendError(tag: tag, code: .notSupported)
        }
    }

    // MARK: - Auth & Introspection

    private func handleAuth(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let rawVersion = try reader.getU32()
        _ = try reader.getArbitrary(expectedLength: Self.cookieLength)
        let clientVersion = rawVersion & Self.protocolVersionMask
        guard clientVersion >= 8 else {
            sendError(tag: tag, code: .version)
            return
        }
        negotiatedVersion = min(clientVersion, Self.protocolVersion)
        isAuthorized = true

        // Reply with SHM=0 (bit 31 clear) and MEMFD=0 (bit 30 clear) so libpulse uses pure
        // stream-socket pstream packets for all audio blocks.
        var reply = makeReply(tag: tag)
        reply.putU32(negotiatedVersion)
        sendControl(reply)
    }

    private func handleSetClientName(tag: UInt32, reader: inout PulseTagstructReader) throws {
        if negotiatedVersion < 13 {
            if let name = try reader.getString() {
                clientProplist = PulseProplist(strings: ["application.name": name])
            }
        } else {
            clientProplist = try reader.getProplist()
        }
        var reply = makeReply(tag: tag)
        if negotiatedVersion >= 13 {
            reply.putU32(clientIndex)
        }
        sendControl(reply)
    }

    private func handleGetServerInfo(tag: UInt32) {
        var reply = makeReply(tag: tag)
        reply.putString(Self.serverName)
        reply.putString(Self.serverVersion)
        reply.putString(NSUserName())
        reply.putString(ProcessInfo.processInfo.hostName)
        reply.putSampleSpec(.defaultPlayback)
        reply.putString(Self.sinkName)
        reply.putString(Self.sourceName)
        reply.putU32(0x4954_3241) // 'IT2A' server cookie
        if negotiatedVersion >= 15 {
            reply.putChannelMap(.defaultMap(channels: 2))
        }
        sendControl(reply)
    }

    private func handleLookup(tag: UInt32, isSink: Bool, reader: inout PulseTagstructReader) throws {
        let name = try reader.getString()
        if isSink {
            if matchesSink(index: Self.invalidIndex, name: name) {
                var reply = makeReply(tag: tag)
                reply.putU32(Self.sinkIndex)
                sendControl(reply)
            } else {
                sendError(tag: tag, code: .noEntity)
            }
        } else {
            if matchesSource(index: Self.invalidIndex, name: name) {
                var reply = makeReply(tag: tag)
                reply.putU32(Self.sourceIndex)
                sendControl(reply)
            } else {
                sendError(tag: tag, code: .noEntity)
            }
        }
    }

    private func handleGetDeviceInfo(tag: UInt32, isSink: Bool, reader: inout PulseTagstructReader) throws {
        let idx = try reader.getU32()
        let name = try reader.getString()
        var reply = makeReply(tag: tag)
        if isSink {
            guard matchesSink(index: idx, name: name) else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            fillSinkInfo(&reply)
        } else {
            guard matchesSource(index: idx, name: name) else {
                sendError(tag: tag, code: .noEntity)
                return
            }
            fillSourceInfo(&reply)
        }
        sendControl(reply)
    }

    private func handleGetDeviceInfoList(tag: UInt32, isSink: Bool) {
        var reply = makeReply(tag: tag)
        if isSink {
            fillSinkInfo(&reply)
        } else {
            fillSourceInfo(&reply)
        }
        sendControl(reply)
    }

    private func fillSinkInfo(_ w: inout PulseTagstructWriter) {
        let spec = PulseSampleSpec.defaultPlayback
        let map = PulseChannelMap.defaultMap(channels: spec.channels)
        let desc = "iTerm2 Mac Speaker"
        w.putU32(Self.sinkIndex)
        w.putString(Self.sinkName)
        w.putString(desc)
        w.putSampleSpec(spec)
        w.putChannelMap(map)
        w.putU32(Self.invalidIndex) // module
        w.putCVolume(.norm(channels: spec.channels))
        w.putBoolean(false) // mute
        w.putU32(Self.invalidIndex) // monitor_source index
        w.putString(nil) // monitor_source name
        w.putUsec(15_000) // actual latency
        w.putString("iTerm2CoreAudio")
        w.putU32(0x0002 | 0x0040) // PA_SINK_LATENCY | PA_SINK_DYNAMIC_LATENCY
        if negotiatedVersion >= 13 {
            w.putProplist(PulseProplist(strings: [
                "device.description": desc,
                "device.class": "sound",
                "device.icon_name": "audio-speakers"
            ]))
            w.putUsec(15_000) // configured latency
        }
        if negotiatedVersion >= 15 {
            w.putVolume(PulseCVolume.norm) // base_volume
            w.putU32(hasActivePlayback ? 0 : 1) // PA_SINK_RUNNING (0) or PA_SINK_IDLE (1)
            w.putU32(65537) // n_volume_steps
            w.putU32(Self.invalidIndex) // card
        }
        if negotiatedVersion >= 16 {
            w.putU32(0) // n_ports
            w.putString(nil) // active_port
        }
        if negotiatedVersion >= 21 {
            w.putU8(1)
            w.putFormatInfo(.defaultPCM)
        }
    }

    private func fillSourceInfo(_ w: inout PulseTagstructWriter) {
        let spec = PulseSampleSpec.defaultCapture
        let map = PulseChannelMap.defaultMap(channels: spec.channels)
        let desc = "iTerm2 Mac Microphone"
        w.putU32(Self.sourceIndex)
        w.putString(Self.sourceName)
        w.putString(desc)
        w.putSampleSpec(spec)
        w.putChannelMap(map)
        w.putU32(Self.invalidIndex) // module
        w.putCVolume(.norm(channels: spec.channels))
        w.putBoolean(false) // mute
        w.putU32(Self.invalidIndex) // monitor_of_sink index
        w.putString(nil) // monitor_of_sink name
        w.putUsec(15_000) // actual latency
        w.putString("iTerm2CoreAudio")
        w.putU32(0x0002 | 0x0040) // PA_SOURCE_LATENCY | PA_SOURCE_DYNAMIC_LATENCY
        if negotiatedVersion >= 13 {
            w.putProplist(PulseProplist(strings: [
                "device.description": desc,
                "device.class": "sound",
                "device.icon_name": "audio-input-microphone"
            ]))
            w.putUsec(15_000)
        }
        if negotiatedVersion >= 15 {
            w.putVolume(PulseCVolume.norm)
            w.putU32(hasActiveCapture ? 0 : 1) // PA_SOURCE_RUNNING (0) or PA_SOURCE_IDLE (1)
            w.putU32(65537)
            w.putU32(Self.invalidIndex)
        }
        if negotiatedVersion >= 16 {
            w.putU32(0)
            w.putString(nil)
        }
        if negotiatedVersion >= 22 {
            w.putU8(1)
            w.putFormatInfo(.defaultPCM)
        }
    }

    private func handleGetClientInfoList(tag: UInt32) {
        var reply = makeReply(tag: tag)
        fillClientInfo(&reply)
        sendControl(reply)
    }

    private func handleGetClientInfo(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let idx = try reader.getU32()
        guard idx == clientIndex else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        var reply = makeReply(tag: tag)
        fillClientInfo(&reply)
        sendControl(reply)
    }

    private func fillClientInfo(_ w: inout PulseTagstructWriter) {
        w.putU32(clientIndex)
        w.putString(clientProplist.string(forKey: "application.name") ?? "SSH Client")
        w.putU32(Self.invalidIndex)
        w.putString("protocol-native.c")
        if negotiatedVersion >= 13 {
            w.putProplist(clientProplist)
        }
    }

    private func handleGetSinkInputInfoList(tag: UInt32) {
        var reply = makeReply(tag: tag)
        for ch in playbackStreams.keys.sorted() {
            if let s = playbackStreams[ch] {
                fillSinkInputInfo(&reply, stream: s)
            }
        }
        sendControl(reply)
    }

    private func handleGetSinkInputInfo(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let idx = try reader.getU32()
        guard let s = playbackStreams.values.first(where: { $0.sinkInputIndex == idx }) else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        var reply = makeReply(tag: tag)
        fillSinkInputInfo(&reply, stream: s)
        sendControl(reply)
    }

    private func fillSinkInputInfo(_ w: inout PulseTagstructWriter, stream: PlaybackStreamState) {
        w.putU32(stream.sinkInputIndex)
        w.putString(stream.proplist.string(forKey: "media.name") ?? "Playback")
        w.putU32(Self.invalidIndex)
        w.putU32(clientIndex)
        w.putU32(Self.sinkIndex)
        w.putSampleSpec(stream.spec)
        w.putChannelMap(stream.channelMap)
        w.putCVolume(stream.volume)
        w.putUsec(backend?.playbackLatencyUsec(id: stream.id) ?? 0)
        w.putUsec(15_000)
        w.putString("auto")
        w.putString("protocol-native.c")
        if negotiatedVersion >= 11 {
            w.putBoolean(stream.muted)
        }
        if negotiatedVersion >= 13 {
            w.putProplist(stream.proplist)
        }
        if negotiatedVersion >= 19 {
            w.putBoolean(stream.corked)
        }
        if negotiatedVersion >= 20 {
            w.putBoolean(true)
            w.putBoolean(true)
        }
        if negotiatedVersion >= 21 {
            w.putFormatInfo(.defaultPCM)
        }
    }

    private func handleGetSourceOutputInfoList(tag: UInt32) {
        var reply = makeReply(tag: tag)
        for ch in recordStreams.keys.sorted() {
            if let s = recordStreams[ch] {
                fillSourceOutputInfo(&reply, stream: s)
            }
        }
        sendControl(reply)
    }

    private func handleGetSourceOutputInfo(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let idx = try reader.getU32()
        guard let s = recordStreams.values.first(where: { $0.sourceOutputIndex == idx }) else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        var reply = makeReply(tag: tag)
        fillSourceOutputInfo(&reply, stream: s)
        sendControl(reply)
    }

    private func fillSourceOutputInfo(_ w: inout PulseTagstructWriter, stream: RecordStreamState) {
        w.putU32(stream.sourceOutputIndex)
        w.putString(stream.proplist.string(forKey: "media.name") ?? "Capture")
        w.putU32(Self.invalidIndex)
        w.putU32(clientIndex)
        w.putU32(Self.sourceIndex)
        w.putSampleSpec(stream.spec)
        w.putChannelMap(stream.channelMap)
        w.putUsec(backend?.recordLatencyUsec(id: stream.id) ?? 0)
        w.putUsec(15_000)
        w.putString("auto")
        w.putString("protocol-native.c")
        if negotiatedVersion >= 13 {
            w.putProplist(stream.proplist)
        }
        if negotiatedVersion >= 19 {
            w.putBoolean(stream.corked)
        }
        if negotiatedVersion >= 22 {
            w.putCVolume(stream.volume)
            w.putBoolean(stream.muted)
            w.putBoolean(true)
            w.putBoolean(true)
            w.putFormatInfo(.defaultPCM)
        }
    }

    private func handleStat(tag: UInt32) {
        var reply = makeReply(tag: tag)
        reply.putU32(0)
        reply.putU32(0)
        reply.putU32(0)
        reply.putU32(0)
        reply.putU32(0)
        sendControl(reply)
    }

    // MARK: - Playback Streams

    private func handleCreatePlaybackStream(tag: UInt32, reader: inout PulseTagstructReader) throws {
        var legacyName: String?
        if negotiatedVersion < 13 {
            legacyName = try reader.getString()
        }
        var spec = try reader.getSampleSpec()
        var map = try reader.getChannelMap()
        let sinkIdx = try reader.getU32()
        let sinkName = try reader.getString()
        let reqMaxlength = try reader.getU32()
        let corked = try reader.getBoolean()
        let reqTlength = try reader.getU32()
        let reqPrebuf = try reader.getU32()
        let reqMinreq = try reader.getU32()
        _ = try reader.getU32() // syncid
        var volume = try reader.getCVolume()

        if negotiatedVersion >= 12 {
            for _ in 0..<7 { _ = try reader.getBoolean() }
        }
        var muted = false
        var proplist = PulseProplist()
        if negotiatedVersion >= 13 {
            muted = try reader.getBoolean()
            _ = try reader.getBoolean() // adjust_latency
            proplist = try reader.getProplist()
        } else if let legacyName {
            proplist = PulseProplist(strings: ["media.name": legacyName])
        }
        if negotiatedVersion >= 14 {
            _ = try reader.getBoolean() // volume_set
            _ = try reader.getBoolean() // early_requests
        }
        if negotiatedVersion >= 15 {
            for _ in 0..<3 { _ = try reader.getBoolean() }
        }
        if negotiatedVersion >= 17 {
            _ = try reader.getBoolean() // relative_volume
        }
        if negotiatedVersion >= 18 {
            _ = try reader.getBoolean() // passthrough
        }
        var negotiatedFormat = PulseFormatInfo.defaultPCM
        if negotiatedVersion >= 21 {
            let nFormats = try reader.getU8()
            for i in 0..<nFormats {
                let fmt = try reader.getFormatInfo()
                if i == 0 {
                    negotiatedFormat = fmt
                }
            }
            if nFormats > 0 && !spec.isValid {
                spec = Self.resolveSpec(from: negotiatedFormat, fallback: .defaultPlayback)
                map = .defaultMap(channels: spec.channels)
                volume = .norm(channels: spec.channels)
            }
        }

        guard spec.isValid else {
            sendError(tag: tag, code: .invalid)
            return
        }
        guard matchesSink(index: sinkIdx, name: sinkName) else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        if map.positions.count != Int(spec.channels) {
            map = .defaultMap(channels: spec.channels)
        }
        if volume.values.count != Int(spec.channels) {
            volume = .norm(channels: spec.channels)
        }

        let fsize = max(spec.frameSize, 1)
        let minNetworkTlength = Self.alignToFrame(max(fsize * Int(spec.rate) * 120 / 1000, 4096), frameSize: fsize)
        let defaultTarget = UInt32(Self.alignToFrame(max(fsize * Int(spec.rate) * 180 / 1000, 8192), frameSize: fsize))
        let tlength = (reqTlength == Self.invalidIndex || reqTlength == 0)
            ? defaultTarget
            : UInt32(Self.alignToFrame(min(max(Int(reqTlength), minNetworkTlength), 1024 * 1024), frameSize: fsize))
        let maxlength = (reqMaxlength == Self.invalidIndex || reqMaxlength == 0)
            ? max(tlength * 4, 131_072)
            : max(reqMaxlength, tlength)
        let defaultMinreq = Self.alignToFrame(max(fsize * Int(spec.rate) * 20 / 1000, fsize), frameSize: fsize)
        let rawMinreq = (reqMinreq == Self.invalidIndex || reqMinreq == 0) ? defaultMinreq : Int(reqMinreq)
        let minreq = UInt32(Self.alignToFrame(min(max(rawMinreq, fsize), max(Int(tlength) / 4, fsize)), frameSize: fsize))
        let defaultPrebuf = Self.alignToFrame(
            min(max(fsize * Int(spec.rate) * 60 / 1000, Int(minreq)), max(Int(tlength) / 2, Int(minreq))),
            frameSize: fsize)
        let prebuf = (reqPrebuf == Self.invalidIndex)
            ? UInt32(defaultPrebuf)
            : UInt32(Self.alignToFrame(min(Int(reqPrebuf), Int(tlength)), frameSize: fsize))

        guard playbackStreams.count < Self.maxStreamsPerConnection else {
            sendError(tag: tag, code: .internalError)
            return
        }
        let ch = allocateChannel()
        let stream = PlaybackStreamState(channel: ch,
                                         sinkInputIndex: ch,
                                         spec: spec,
                                         channelMap: map,
                                         proplist: proplist,
                                         maxlength: maxlength,
                                         tlength: tlength,
                                         prebuf: prebuf,
                                         minreq: minreq,
                                         corked: corked,
                                         muted: muted,
                                         volume: volume)
        guard let backend,
              backend.openPlaybackStream(id: stream.id,
                                         spec: spec,
                                         prebufBytes: Int(prebuf),
                                         corked: corked,
                                         onDataConsumed: { [weak self] consumed in
                                             self?.handlePlaybackConsumed(channel: ch, bytes: consumed)
                                         }) else {
            sendError(tag: tag, code: .internalError)
            return
        }
        backend.setPlaybackVolume(id: stream.id, gain: Self.linearGain(for: stream))

        playbackStreams[ch] = stream
        onActivityChanged()

        var reply = makeReply(tag: tag)
        reply.putU32(ch) // stream index == data channel
        reply.putU32(stream.sinkInputIndex)
        reply.putU32(tlength) // initial missing byte request
        if negotiatedVersion >= 9 {
            reply.putU32(maxlength)
            reply.putU32(tlength)
            reply.putU32(prebuf)
            reply.putU32(minreq)
        }
        if negotiatedVersion >= 12 {
            reply.putSampleSpec(spec)
            reply.putChannelMap(map)
            reply.putU32(Self.sinkIndex)
            reply.putString(Self.sinkName)
            reply.putBoolean(false) // suspended
        }
        if negotiatedVersion >= 13 {
            reply.putUsec(spec.bytesToUsec(Int(tlength)))
        }
        if negotiatedVersion >= 21 {
            reply.putFormatInfo(negotiatedFormat)
        }
        sendControl(reply)
    }

    private func handleAudioBlock(_ frame: PulsePStreamFrame) {
        guard let stream = playbackStreams[frame.channel], !frame.payload.isEmpty else {
            return
        }
        stream.writeIndex += Int64(frame.payload.count)
        backend?.writePlaybackData(id: stream.id, data: frame.payload)
        if !stream.startedSent && negotiatedVersion >= 13 {
            stream.startedSent = true
            var started = PulseTagstructWriter()
            started.putU32(PulseCommand.started.rawValue)
            started.putU32(Self.invalidIndex)
            started.putU32(stream.channel)
            sendControl(started)
        }
    }

    private func handlePlaybackConsumed(channel: UInt32, bytes: Int) {
        guard !isClosed, bytes > 0, let stream = playbackStreams[channel] else {
            return
        }
        stream.readIndex = min(stream.writeIndex, stream.readIndex + Int64(bytes))
        sendPlaybackRequestCredit(channel: channel, bytes: bytes, force: false)
    }

    private func sendPlaybackRequestCredit(channel: UInt32, bytes: Int, force: Bool) {
        guard !isClosed, bytes > 0, let stream = playbackStreams[channel] else {
            return
        }
        stream.pendingCreditBytes += bytes
        let threshold = max(Int(stream.minreq), stream.spec.frameSize)
        if force || stream.pendingCreditBytes >= threshold {
            let grant = UInt32(clamping: stream.pendingCreditBytes)
            stream.pendingCreditBytes = 0
            var req = PulseTagstructWriter()
            req.putU32(PulseCommand.request.rawValue)
            req.putU32(Self.invalidIndex)
            req.putU32(channel)
            req.putU32(grant)
            sendControl(req)
        }
    }

    private static func linearGain(for stream: PlaybackStreamState) -> Float {
        if stream.muted {
            return 0.0
        }
        guard !stream.volume.values.isEmpty else {
            return 1.0
        }
        let avg = stream.volume.values.map { Double($0) }.reduce(0, +) / Double(stream.volume.values.count)
        let norm = max(0.0, min(2.0, avg / Double(PulseCVolume.norm)))
        return Float(pow(norm, 3.0))
    }

    private func handleGetPlaybackLatency(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let ch = try reader.getU32()
        let clientTV = try reader.getTimeval()
        guard let stream = playbackStreams[ch] else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        let sinkUsec = backend?.playbackLatencyUsec(id: stream.id) ?? 15_000
        var reply = makeReply(tag: tag)
        reply.putUsec(sinkUsec)
        reply.putUsec(0)
        reply.putBoolean(!stream.corked && stream.writeIndex > 0)
        reply.putTimeval(clientTV)
        reply.putTimeval(.now())
        reply.putS64(stream.writeIndex)
        reply.putS64(stream.readIndex)
        if negotiatedVersion >= 13 {
            reply.putU64(0) // underrun_for
            reply.putU64(UInt64(max(stream.readIndex, 0))) // playing_for
        }
        sendControl(reply)
    }

    private func handleSetPlaybackBufferAttr(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let ch = try reader.getU32()
        let maxl = try reader.getU32()
        let tl = try reader.getU32()
        let preb = try reader.getU32()
        let minr = try reader.getU32()
        if negotiatedVersion >= 13 { _ = try reader.getBoolean() }
        if negotiatedVersion >= 14 { _ = try reader.getBoolean() }
        guard let stream = playbackStreams[ch] else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        if maxl != Self.invalidIndex && maxl > 0 { stream.maxlength = maxl }
        if tl != Self.invalidIndex && tl > 0 { stream.tlength = tl }
        if preb != Self.invalidIndex { stream.prebuf = preb }
        if minr != Self.invalidIndex && minr > 0 { stream.minreq = minr }
        var reply = makeReply(tag: tag)
        reply.putU32(stream.maxlength)
        reply.putU32(stream.tlength)
        reply.putU32(stream.prebuf)
        reply.putU32(stream.minreq)
        if negotiatedVersion >= 13 {
            reply.putUsec(stream.spec.bytesToUsec(Int(stream.tlength)))
        }
        sendControl(reply)
    }

    // MARK: - Record Streams

    private func handleCreateRecordStream(tag: UInt32, reader: inout PulseTagstructReader) throws {
        var legacyName: String?
        if negotiatedVersion < 13 {
            legacyName = try reader.getString()
        }
        var spec = try reader.getSampleSpec()
        var map = try reader.getChannelMap()
        let sourceIdx = try reader.getU32()
        let sourceName = try reader.getString()
        let reqMaxlength = try reader.getU32()
        let corked = try reader.getBoolean()
        let reqFragsize = try reader.getU32()

        if negotiatedVersion >= 12 {
            for _ in 0..<7 { _ = try reader.getBoolean() }
        }
        var proplist = PulseProplist()
        if negotiatedVersion >= 13 {
            _ = try reader.getBoolean() // peak_detect
            _ = try reader.getBoolean() // adjust_latency
            proplist = try reader.getProplist()
            _ = try reader.getU32() // direct_on_input_idx
        } else if let legacyName {
            proplist = PulseProplist(strings: ["media.name": legacyName])
        }
        if negotiatedVersion >= 14 {
            _ = try reader.getBoolean() // early_requests
        }
        if negotiatedVersion >= 15 {
            _ = try reader.getBoolean() // dont_inhibit_auto_suspend
            _ = try reader.getBoolean() // fail_on_suspend
        }
        var negotiatedFormat = PulseFormatInfo.defaultPCM
        var volume = PulseCVolume.norm(channels: max(spec.channels, 1))
        var muted = false
        if negotiatedVersion >= 22 {
            let nFormats = try reader.getU8()
            for i in 0..<nFormats {
                let fmt = try reader.getFormatInfo()
                if i == 0 {
                    negotiatedFormat = fmt
                }
            }
            volume = try reader.getCVolume()
            muted = try reader.getBoolean()
            for _ in 0..<4 { _ = try reader.getBoolean() }
            if nFormats > 0 && !spec.isValid {
                spec = Self.resolveSpec(from: negotiatedFormat, fallback: .defaultCapture)
                map = .defaultMap(channels: spec.channels)
                volume = .norm(channels: spec.channels)
            }
        }

        guard spec.isValid else {
            sendError(tag: tag, code: .invalid)
            return
        }
        guard matchesSource(index: sourceIdx, name: sourceName) else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        if map.positions.count != Int(spec.channels) {
            map = .defaultMap(channels: spec.channels)
        }
        if volume.values.count != Int(spec.channels) {
            volume = .norm(channels: spec.channels)
        }

        let fsize = max(spec.frameSize, 1)
        let minFrag = Self.alignToFrame(max(fsize * Int(spec.rate) / 100, fsize), frameSize: fsize)
        let defaultFrag = UInt32(Self.alignToFrame(max(fsize * Int(spec.rate) / 50, 1024), frameSize: fsize))
        let fragsize = (reqFragsize == Self.invalidIndex || reqFragsize == 0)
            ? defaultFrag
            : UInt32(Self.alignToFrame(min(max(Int(reqFragsize), minFrag), 262_144), frameSize: fsize))
        let maxlength = (reqMaxlength == Self.invalidIndex || reqMaxlength == 0)
            ? max(fragsize * 16, 65_536)
            : max(reqMaxlength, fragsize)

        guard let backend else {
            sendError(tag: tag, code: .internalError)
            return
        }

        backend.requestMicrophoneAuthorization { [weak self] granted in
            guard let self, !self.isClosed else { return }
            guard granted else {
                self.sendError(tag: tag, code: .access)
                return
            }
            guard self.recordStreams.count < Self.maxStreamsPerConnection else {
                self.sendError(tag: tag, code: .internalError)
                return
            }
            let ch = self.allocateChannel()
            let stream = RecordStreamState(channel: ch,
                                           sourceOutputIndex: ch,
                                           spec: spec,
                                           channelMap: map,
                                           proplist: proplist,
                                           maxlength: maxlength,
                                           fragsize: fragsize,
                                           corked: corked,
                                           muted: muted,
                                           volume: volume)
            guard let activeBackend = self.backend,
                  activeBackend.openRecordStream(id: stream.id,
                                                 spec: spec,
                                                 fragSize: Int(fragsize),
                                                 corked: corked,
                                                 onCaptureData: { [weak self] pcm in
                                                     self?.handleCaptureProduced(channel: ch, data: pcm)
                                                 }) else {
                self.sendError(tag: tag, code: .internalError)
                return
            }
            self.recordStreams[ch] = stream
            self.onActivityChanged()

            var reply = self.makeReply(tag: tag)
            reply.putU32(ch)
            reply.putU32(stream.sourceOutputIndex)
            if self.negotiatedVersion >= 9 {
                reply.putU32(maxlength)
                reply.putU32(fragsize)
            }
            if self.negotiatedVersion >= 12 {
                reply.putSampleSpec(spec)
                reply.putChannelMap(map)
                reply.putU32(Self.sourceIndex)
                reply.putString(Self.sourceName)
                reply.putBoolean(false)
            }
            if self.negotiatedVersion >= 13 {
                reply.putUsec(spec.bytesToUsec(Int(fragsize)))
            }
            if self.negotiatedVersion >= 22 {
                reply.putFormatInfo(negotiatedFormat)
            }
            self.sendControl(reply)
        }
    }

    private func handleCaptureProduced(channel: UInt32, data: Data) {
        guard !isClosed, !data.isEmpty, let stream = recordStreams[channel], !stream.corked else {
            return
        }
        stream.writeIndex += Int64(data.count)
        stream.readIndex = stream.writeIndex
        let frame = PulsePStreamFrame.audioBlock(channel: channel, payload: data)
        sendFrame(frame.encode())
    }

    private func handleGetRecordLatency(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let ch = try reader.getU32()
        let clientTV = try reader.getTimeval()
        guard let stream = recordStreams[ch] else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        let srcUsec = backend?.recordLatencyUsec(id: stream.id) ?? 15_000
        var reply = makeReply(tag: tag)
        reply.putUsec(0)
        reply.putUsec(srcUsec)
        reply.putBoolean(!stream.corked)
        reply.putTimeval(clientTV)
        reply.putTimeval(.now())
        reply.putS64(stream.writeIndex)
        reply.putS64(stream.readIndex)
        sendControl(reply)
    }

    private func handleSetRecordBufferAttr(tag: UInt32, reader: inout PulseTagstructReader) throws {
        let ch = try reader.getU32()
        let maxl = try reader.getU32()
        let frag = try reader.getU32()
        if negotiatedVersion >= 13 { _ = try reader.getBoolean() }
        if negotiatedVersion >= 14 { _ = try reader.getBoolean() }
        guard let stream = recordStreams[ch] else {
            sendError(tag: tag, code: .noEntity)
            return
        }
        if maxl != Self.invalidIndex && maxl > 0 { stream.maxlength = maxl }
        if frag != Self.invalidIndex && frag > 0 { stream.fragsize = frag }
        var reply = makeReply(tag: tag)
        reply.putU32(stream.maxlength)
        reply.putU32(stream.fragsize)
        if negotiatedVersion >= 13 {
            reply.putUsec(stream.spec.bytesToUsec(Int(stream.fragsize)))
        }
        sendControl(reply)
    }

    // MARK: - Helpers

    private func allocateChannel() -> UInt32 {
        defer { nextStreamChannel &+= 1 }
        if nextStreamChannel == 0 || nextStreamChannel == Self.invalidIndex {
            nextStreamChannel = 1
        }
        return nextStreamChannel
    }

    private func matchesSink(index: UInt32, name: String?) -> Bool {
        if index != Self.invalidIndex {
            return index == Self.sinkIndex
        }
        guard let name, !name.isEmpty else { return true }
        return name == Self.sinkName || name == "@DEFAULT_SINK@"
    }

    private func matchesSource(index: UInt32, name: String?) -> Bool {
        if index != Self.invalidIndex {
            return index == Self.sourceIndex
        }
        guard let name, !name.isEmpty else { return true }
        return name == Self.sourceName || name == "@DEFAULT_SOURCE@"
    }

    private static func alignToFrame(_ value: Int, frameSize: Int) -> Int {
        guard frameSize > 1 else { return max(value, 1) }
        let rem = value % frameSize
        return rem == 0 ? max(value, frameSize) : (value + (frameSize - rem))
    }

    private static func resolveSpec(from formatInfo: PulseFormatInfo, fallback: PulseSampleSpec) -> PulseSampleSpec {
        var spec = fallback
        if let rawRate = formatInfo.proplist.string(forKey: "format.rate")?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")),
           let rate = UInt32(rawRate), rate >= 1, rate <= PulseSampleSpec.maxRate {
            spec.rate = rate
        }
        if let rawCh = formatInfo.proplist.string(forKey: "format.channels")?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")),
           let ch = UInt8(rawCh), ch >= 1, ch <= PulseSampleSpec.maxChannels {
            spec.channels = ch
        }
        if let rawFmt = formatInfo.proplist.string(forKey: "format.sample_format")?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) {
            switch rawFmt {
            case "u8": spec.format = PulseSampleFormat.u8.rawValue
            case "s16le": spec.format = PulseSampleFormat.s16le.rawValue
            case "s16be": spec.format = PulseSampleFormat.s16be.rawValue
            case "float32le": spec.format = PulseSampleFormat.float32le.rawValue
            case "float32be": spec.format = PulseSampleFormat.float32be.rawValue
            case "s32le": spec.format = PulseSampleFormat.s32le.rawValue
            case "s32be": spec.format = PulseSampleFormat.s32be.rawValue
            default: break
            }
        }
        return spec
    }

    private func makeReply(tag: UInt32) -> PulseTagstructWriter {
        var w = PulseTagstructWriter()
        w.putU32(PulseCommand.reply.rawValue)
        w.putU32(tag)
        return w
    }

    private func sendSimpleAck(tag: UInt32) {
        sendControl(makeReply(tag: tag))
    }

    private func sendError(tag: UInt32, code: PulseErrorCode) {
        var w = PulseTagstructWriter()
        w.putU32(PulseCommand.error.rawValue)
        w.putU32(tag)
        w.putU32(code.rawValue)
        sendControl(w)
    }

    private func sendControl(_ writer: PulseTagstructWriter) {
        let frame = PulsePStreamFrame.controlPacket(writer.data)
        sendFrame(frame.encode())
    }
}
