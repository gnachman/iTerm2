//
//  PulseAudioProtocolTests.swift
//  iTerm2
//
//  Unit tests for PulseAudioPStream and PulseAudioTagstruct wire codecs
//  (20-byte big-endian pstream framing, incremental chunk reassembly, bounds
//  guards, and round-trip encoding/decoding of all PA_TAG_* primitives).
//

import AVFAudio
import Foundation
#if !STANDALONE_SWIFT_TEST
import XCTest
@testable import iTerm2SharedARC
#endif

final class PulseAudioProtocolTests: XCTestCase {

    func testPStreamRoundTripAndSingleByteChunking() throws {
        let f1 = PulsePStreamFrame.controlPacket(Data([0x4C, 0x00, 0x00, 0x00, 0x08]))
        let f2 = PulsePStreamFrame.audioBlock(channel: 3,
                                              payload: Data((0..<512).map { UInt8($0 & 0xFF) }),
                                              offset: -4096,
                                              flags: 1)
        var wire = f1.encode()
        wire.append(f2.encode())

        let reader = PulsePStreamReader()
        var decoded: [PulsePStreamFrame] = []
        for byte in wire {
            decoded.append(contentsOf: try reader.feed(Data([byte])))
        }

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0], f1)
        XCTAssertTrue(decoded[0].isControlPacket)
        XCTAssertEqual(decoded[1], f2)
        XCTAssertFalse(decoded[1].isControlPacket)
        XCTAssertEqual(reader.bufferedByteCount, 0)
    }

    func testPStreamRejectsOversizedAndSHMFrames() {
        let reader = PulsePStreamReader(maxPayloadLength: 1024)
        var badLen = Data()
        badLen.append(contentsOf: [0x00, 0x00, 0x08, 0x00]) // 2048 > 1024
        badLen.append(contentsOf: Array(repeating: UInt8(0), count: 16))
        XCTAssertThrowsError(try reader.feed(badLen)) { err in
            XCTAssertEqual(err as? PulsePStreamError, .frameTooLarge(2048))
        }

        var shmHeader = Data()
        shmHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x10])
        shmHeader.append(contentsOf: Array(repeating: UInt8(0), count: 12))
        shmHeader.append(contentsOf: [0x80, 0x00, 0x00, 0x00]) // PA_FLAG_SHMDATA
        XCTAssertThrowsError(try reader.feed(shmHeader)) { err in
            XCTAssertEqual(err as? PulsePStreamError, .unexpectedSHMFrame(0x8000_0000))
        }
    }

    func testTagstructAllPrimitivesRoundTrip() throws {
        var writer = PulseTagstructWriter()
        writer.putString("iterm2_mac_speaker")
        writer.putString(nil)
        writer.putU32(0xDEAD_BEEF)
        writer.putU8(0x7F)
        writer.putU64(0x0123_4567_89AB_CDEF)
        writer.putS64(-987_654_321_000)
        writer.putBoolean(true)
        writer.putBoolean(false)
        let cookie = Data((0..<256).map { UInt8($0) })
        writer.putArbitrary(cookie)
        let spec = PulseSampleSpec(format: PulseSampleFormat.s16le.rawValue, channels: 2, rate: 48_000)
        writer.putSampleSpec(spec)
        let tv = PulseTimeval(tvSec: 1_700_000_000, tvUsec: 456_789)
        writer.putTimeval(tv)
        writer.putUsec(25_000)
        let cmap = PulseChannelMap.defaultMap(channels: 2)
        writer.putChannelMap(cmap)
        let cvol = PulseCVolume.norm(channels: 2)
        writer.putCVolume(cvol)
        writer.putVolume(PulseCVolume.norm)
        let props = PulseProplist(strings: [
            "application.name": "agy",
            "media.role": "phone"
        ])
        writer.putProplist(props)
        let fmt = PulseFormatInfo(encoding: PulseFormatInfo.encodingPCM,
                                  proplist: PulseProplist(strings: ["format.sample_format": "\"s16le\""]))
        writer.putFormatInfo(fmt)

        var reader = PulseTagstructReader(data: writer.data)
        XCTAssertEqual(try reader.getString(), "iterm2_mac_speaker")
        XCTAssertNil(try reader.getString())
        XCTAssertEqual(try reader.getU32(), 0xDEAD_BEEF)
        XCTAssertEqual(try reader.getU8(), 0x7F)
        XCTAssertEqual(try reader.getU64(), 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(try reader.getS64(), -987_654_321_000)
        XCTAssertTrue(try reader.getBoolean())
        XCTAssertFalse(try reader.getBoolean())
        XCTAssertEqual(try reader.getArbitrary(expectedLength: 256), cookie)
        XCTAssertEqual(try reader.getSampleSpec(), spec)
        XCTAssertEqual(try reader.getTimeval(), tv)
        XCTAssertEqual(try reader.getUsec(), 25_000)
        XCTAssertEqual(try reader.getChannelMap(), cmap)
        XCTAssertEqual(try reader.getCVolume(), cvol)
        XCTAssertEqual(try reader.getVolume(), PulseCVolume.norm)
        let decodedProps = try reader.getProplist()
        XCTAssertEqual(decodedProps.string(forKey: "application.name"), "agy")
        XCTAssertEqual(decodedProps.string(forKey: "media.role"), "phone")
        let decodedFmt = try reader.getFormatInfo()
        XCTAssertEqual(decodedFmt, fmt)
        XCTAssertTrue(reader.isAtEnd)
    }

    func testTagstructBoundsChecks() {
        // Unterminated string
        var badStr = Data([PulseTag.string.rawValue])
        badStr.append(contentsOf: "no-null".utf8)
        var r1 = PulseTagstructReader(data: badStr)
        XCTAssertThrowsError(try r1.getString()) { err in
            XCTAssertEqual(err as? PulseTagstructError, .unterminatedString)
        }

        // Channel count > 32
        let badMap = Data([PulseTag.channelMap.rawValue, 99])
        var r2 = PulseTagstructReader(data: badMap)
        XCTAssertThrowsError(try r2.getChannelMap())

        // Arbitrary > 64 KiB
        var badArb = Data([PulseTag.arbitrary.rawValue])
        badArb.append(contentsOf: [0x00, 0x10, 0x00, 0x00]) // 1 MiB
        var r3 = PulseTagstructReader(data: badArb)
        XCTAssertThrowsError(try r3.getArbitrary())
    }

    // MARK: - PulseAudioSession State Machine Tests

    private final class MockAudioBackend: PulseAudioBackend {
        var allowMic = true
        var writtenPlayback = Data()
        var onConsumedCallbacks: [UUID: (Int) -> Void] = [:]
        var onCaptureCallbacks: [UUID: (Data) -> Void] = [:]

        func openPlaybackStream(id: UUID, spec: PulseSampleSpec, prebufBytes: Int, corked: Bool, onDataConsumed: @escaping (Int) -> Void) -> Bool {
            onConsumedCallbacks[id] = onDataConsumed
            return true
        }
        func writePlaybackData(id: UUID, data: Data) {
            writtenPlayback.append(data)
            onConsumedCallbacks[id]?(data.count)
        }
        func setPlaybackCorked(id: UUID, corked: Bool) {}
        func flushPlaybackStream(id: UUID) {}
        func drainPlaybackStream(id: UUID, completion: @escaping () -> Void) { completion() }
        func playbackLatencyUsec(id: UUID) -> UInt64 { 12_000 }
        func closePlaybackStream(id: UUID) { onConsumedCallbacks.removeValue(forKey: id) }

        func requestMicrophoneAuthorization(completion: @escaping (Bool) -> Void) {
            completion(allowMic)
        }
        func openRecordStream(id: UUID, spec: PulseSampleSpec, fragSize: Int, corked: Bool, onCaptureData: @escaping (Data) -> Void) -> Bool {
            onCaptureCallbacks[id] = onCaptureData
            return true
        }
        func setRecordCorked(id: UUID, corked: Bool) {}
        func flushRecordStream(id: UUID) {}
        func recordLatencyUsec(id: UUID) -> UInt64 { 10_000 }
        func closeRecordStream(id: UUID) { onCaptureCallbacks.removeValue(forKey: id) }
    }

    func testSessionAuthMasksSHMAndMemfdAndHandlesPlaybackAndMicConsent() throws {
        let backend = MockAudioBackend()
        let downReader = PulsePStreamReader()
        var downFrames: [PulsePStreamFrame] = []
        var closed = false

        let session = PulseAudioSession(
            connid: "c1",
            backend: backend,
            sendFrame: { bytes in
                if let parsed = try? downReader.feed(bytes) {
                    downFrames.append(contentsOf: parsed)
                }
            },
            closeTransport: { closed = true }
        )

        // 1. AUTH with SHM (0x80000000) | MEMFD (0x40000000) | v35 -> must reply v35 with both bits 0
        var auth = PulseTagstructWriter()
        auth.putU32(PulseCommand.auth.rawValue)
        auth.putU32(1)
        auth.putU32(0xC000_0000 | 35)
        auth.putArbitrary(Data(repeating: 0xAA, count: 256))
        session.receive(PulsePStreamFrame.controlPacket(auth.data).encode())

        XCTAssertFalse(closed)
        XCTAssertEqual(downFrames.count, 1)
        var rAuth = PulseTagstructReader(data: downFrames[0].payload)
        XCTAssertEqual(try rAuth.getU32(), PulseCommand.reply.rawValue)
        XCTAssertEqual(try rAuth.getU32(), 1)
        XCTAssertEqual(try rAuth.getU32(), 35) // SHM=0, MEMFD=0!

        // 2. Denied microphone stream returns PA_ERR_ACCESS (1)
        downFrames.removeAll()
        backend.allowMic = false
        var recReq = PulseTagstructWriter()
        recReq.putU32(PulseCommand.createRecordStream.rawValue)
        recReq.putU32(2)
        recReq.putSampleSpec(.defaultCapture)
        recReq.putChannelMap(.defaultMap(channels: 1))
        recReq.putU32(PulseAudioSession.invalidIndex)
        recReq.putString(nil)
        recReq.putU32(PulseAudioSession.invalidIndex)
        recReq.putBoolean(false)
        recReq.putU32(1920)
        for _ in 0..<7 { recReq.putBoolean(false) } // v12
        recReq.putBoolean(false) // peak
        recReq.putBoolean(false) // adjust_latency
        recReq.putProplist(PulseProplist())
        recReq.putU32(PulseAudioSession.invalidIndex)
        recReq.putBoolean(false) // v14
        recReq.putBoolean(false) // v15
        recReq.putBoolean(false) // v15
        recReq.putU8(0) // v22 n_formats
        recReq.putCVolume(.norm(channels: 1))
        for _ in 0..<5 { recReq.putBoolean(false) }

        session.receive(PulsePStreamFrame.controlPacket(recReq.data).encode())
        XCTAssertEqual(downFrames.count, 1)
        var rDenied = PulseTagstructReader(data: downFrames[0].payload)
        XCTAssertEqual(try rDenied.getU32(), PulseCommand.error.rawValue)
        XCTAssertEqual(try rDenied.getU32(), 2)
        XCTAssertEqual(try rDenied.getU32(), PulseErrorCode.access.rawValue)

        // 3. Allowed microphone stream emits audio blocks on assigned channel
        downFrames.removeAll()
        backend.allowMic = true
        session.receive(PulsePStreamFrame.controlPacket(recReq.data).encode())
        XCTAssertEqual(downFrames.count, 1)
        var rAllowed = PulseTagstructReader(data: downFrames[0].payload)
        XCTAssertEqual(try rAllowed.getU32(), PulseCommand.reply.rawValue)
        XCTAssertEqual(try rAllowed.getU32(), 2)
        let recChannel = try rAllowed.getU32()

        downFrames.removeAll()
        let samplePCM = Data([0x12, 0x34, 0x56, 0x78])
        backend.onCaptureCallbacks.values.first?(samplePCM)
        XCTAssertEqual(downFrames.count, 1)
        XCTAssertEqual(downFrames[0].channel, recChannel)
        XCTAssertEqual(downFrames[0].payload, samplePCM)
    }

    // MARK: - PulsePCMCodec & SSHAudioEngine Resampling Tests

    func testPCMCodecFormatsAndResampler() throws {
        // Test s16le, float32le, s32le, u8, ulaw, alaw round-trips
        let formats: [PulseSampleFormat] = [.s16le, .s16be, .float32le, .float32be, .s32le, .s24le, .u8, .ulaw, .alaw]
        for fmt in formats {
            let spec = PulseSampleSpec(format: fmt.rawValue, channels: 2, rate: 48_000)
            guard let avFmt = PulsePCMCodec.floatFormat(sampleRate: 48_000, channels: 2),
                  let srcBuf = AVAudioPCMBuffer(pcmFormat: avFmt, frameCapacity: 64),
                  let chData = srcBuf.floatChannelData else {
                XCTAssertTrue(false, "Failed to allocate AVAudioPCMBuffer")
                return
            }
            srcBuf.frameLength = 64
            for i in 0..<64 {
                let s = Float(sin(Double(i) * 0.2) * 0.5)
                chData[0][i] = s
                chData[1][i] = -s
            }
            let encoded = PulsePCMCodec.encodeFromFloatBuffer(srcBuf, spec: spec)
            XCTAssertEqual(encoded.count, 64 * spec.frameSize)
            guard let decoded = PulsePCMCodec.decodeToFloatBuffer(encoded, spec: spec),
                  let decCh = decoded.floatChannelData else {
                XCTAssertTrue(false, "Failed to decode format \(fmt)")
                return
            }
            XCTAssertEqual(decoded.frameLength, 64)
            let tol: Float = (fmt == .u8 || fmt == .ulaw || fmt == .alaw) ? 0.05 : 0.001
            for i in 0..<64 {
                XCTAssertTrue(abs(decCh[0][i] - chData[0][i]) <= tol, "Mismatch in \(fmt) ch0 at \(i)")
                XCTAssertTrue(abs(decCh[1][i] - chData[1][i]) <= tol, "Mismatch in \(fmt) ch1 at \(i)")
            }
        }

        // Test SSHAudioEngine 48kHz stereo -> 16kHz mono s16le downconversion via AVAudioConverter
        let engine = SSHAudioEngine(enableHardwareGraph: false, authorizeMicrophone: { $0(true) })
        let streamID = UUID()
        let recSpec = PulseSampleSpec(format: PulseSampleFormat.s16le.rawValue, channels: 1, rate: 16_000)
        // Open corked so headless test does not touch hardware mic tap, then uncork only for conversion helper
        XCTAssertTrue(engine.openRecordStream(id: streamID, spec: recSpec, fragSize: 640, corked: false, onCaptureData: { _ in }))

        guard let inFmt = PulsePCMCodec.floatFormat(sampleRate: 48_000, channels: 2),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 4800),
              let inCh = inBuf.floatChannelData else {
            XCTAssertTrue(false, "Failed to build 48kHz input buffer")
            return
        }
        inBuf.frameLength = 4800 // 100ms at 48kHz -> ~1600 frames (3200 bytes) at 16kHz mono s16le
        for i in 0..<4800 {
            let v = Float(sin(2.0 * .pi * 440.0 * Double(i) / 48_000.0) * 0.6)
            inCh[0][i] = v
            inCh[1][i] = v
        }

        var totalConvertedBytes = 0
        for _ in 0..<10 {
            let chunks = engine.convertCapturedBufferForActiveStreams(inBuf)
            XCTAssertEqual(chunks.count, 1)
            XCTAssertEqual(chunks[0].0, streamID)
            totalConvertedBytes += chunks[0].1.count
        }
        // 1.0s @ 16kHz mono s16le == 32,000 bytes minus ~240-frame FIR priming tail
        XCTAssertTrue(totalConvertedBytes >= 31_000 && totalConvertedBytes <= 32_128,
                      "unexpected converted byte count \(totalConvertedBytes)")
        engine.shutdownAll()
    }

    func testPlaybackRingPrebufferTriggerFlushCreditsAndCenteredResampling() throws {
        let engine = SSHAudioEngine(enableHardwareGraph: false, authorizeMicrophone: { $0(true) })
        let id = UUID()
        let spec = PulseSampleSpec(format: PulseSampleFormat.s16le.rawValue, channels: 1, rate: 16_000)
        var consumedTotal = 0
        XCTAssertTrue(engine.openPlaybackStream(id: id, spec: spec, prebufBytes: 1920, corked: false, onDataConsumed: { bytes in
            consumedTotal += bytes
        }))

        // Generate 410ms (41 x 10ms = 41 x 320 bytes) of continuous 440 Hz mono s16le sine wave.
        func makeSineChunk(startSample: Int, count: Int) -> Data {
            var data = Data(capacity: count * 2)
            for i in 0..<count {
                let s = Int16(clamping: Int((sin(2.0 * .pi * 440.0 * Double(startSample + i) / 16_000.0) * 16_384.0).rounded()))
                var le = s.littleEndian
                withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
            }
            return data
        }

        // First 10ms packet is below 60ms prebuf -> render must hold output at zero.
        engine.writePlaybackData(id: id, data: makeSineChunk(startSample: 0, count: 160))
        let held = try XCTUnwrap(engine.renderPlaybackForTesting(id: id, frames: 480))
        XCTAssertTrue(held.left.allSatisfy { $0 == 0 })
        XCTAssertEqual(held.consumedBytes, 0)

        // Feed remaining 40 chunks and render smoothly at 48kHz stereo.
        for chunkIdx in 1...40 {
            engine.writePlaybackData(id: id, data: makeSineChunk(startSample: chunkIdx * 160, count: 160))
        }
        var renderedLeft: [Float] = []
        var renderedRight: [Float] = []
        for _ in 0..<38 {
            let block = try XCTUnwrap(engine.renderPlaybackForTesting(id: id, frames: 480))
            renderedLeft.append(contentsOf: block.left)
            renderedRight.append(contentsOf: block.right)
            consumedTotal += block.consumedBytes
        }

        XCTAssertEqual(renderedLeft.count, renderedRight.count)
        for i in 0..<renderedLeft.count {
            XCTAssertEqual(renderedLeft[i], renderedRight[i], accuracy: 1e-6, "mono must play centered on both channels")
        }

        // Skip initial 64-sample fade-in and inspect continuous sine smoothness (max step <= 0.08 @ 48kHz).
        let activeSlice = Array(renderedLeft.dropFirst(200).prefix(480 * 30))
        let rms = sqrt(activeSlice.map { $0 * $0 }.reduce(0, +) / Float(activeSlice.count))
        XCTAssertGreaterThan(rms, 0.25)
        for i in 1..<activeSlice.count {
            XCTAssertLessThan(abs(activeSlice[i] - activeSlice[i - 1]), 0.08, "discontinuity at sample \(i)")
        }
        XCTAssertGreaterThan(consumedTotal, 10_000)

        // Flush, push tiny 5ms packet below prebuf, triggerPlaybackStream -> plays immediately.
        engine.flushPlaybackStream(id: id)
        engine.writePlaybackData(id: id, data: makeSineChunk(startSample: 0, count: 80))
        let heldAgain = try XCTUnwrap(engine.renderPlaybackForTesting(id: id, frames: 240))
        XCTAssertTrue(heldAgain.left.allSatisfy { $0 == 0 })

        engine.triggerPlaybackStream(id: id)
        let triggered = try XCTUnwrap(engine.renderPlaybackForTesting(id: id, frames: 240))
        let peak = triggered.left.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.1)
        engine.shutdownAll()
    }

    func testPulseSessionFlushRestoresWriteCreditAndMinimumNetworkBuffers() throws {
        let backend = MockAudioBackend()
        let downReader = PulsePStreamReader()
        var downFrames: [PulsePStreamFrame] = []
        let session = PulseAudioSession(
            connid: "c-flush",
            backend: backend,
            sendFrame: { bytes in
                if let parsed = try? downReader.feed(bytes) {
                    downFrames.append(contentsOf: parsed)
                }
            },
            closeTransport: {}
        )

        var auth = PulseTagstructWriter()
        auth.putU32(PulseCommand.auth.rawValue)
        auth.putU32(1)
        auth.putU32(35)
        auth.putArbitrary(Data(repeating: 0x11, count: 256))
        session.receive(PulsePStreamFrame.controlPacket(auth.data).encode())

        // Request tiny 10ms SHM buffer sizes: session must enforce >= 120ms SSH floor.
        downFrames.removeAll()
        var pbReq = PulseTagstructWriter()
        pbReq.putU32(PulseCommand.createPlaybackStream.rawValue)
        pbReq.putU32(2)
        pbReq.putSampleSpec(.defaultPlayback) // 48kHz 2ch s16le => 192,000 B/s
        pbReq.putChannelMap(.defaultMap(channels: 2))
        pbReq.putU32(PulseAudioSession.invalidIndex)
        pbReq.putString(nil)
        pbReq.putU32(PulseAudioSession.invalidIndex) // maxlength
        pbReq.putBoolean(false) // corked
        pbReq.putU32(1920) // reqTlength (10ms)
        pbReq.putU32(PulseAudioSession.invalidIndex) // reqPrebuf
        pbReq.putU32(480) // reqMinreq
        pbReq.putU32(0) // syncid
        pbReq.putCVolume(.norm(channels: 2))
        for _ in 0..<7 { pbReq.putBoolean(false) } // v12
        pbReq.putBoolean(false) // muted
        pbReq.putBoolean(false) // adjust_latency
        pbReq.putProplist(PulseProplist())
        pbReq.putBoolean(false) // volume_set
        pbReq.putBoolean(false) // early_requests
        for _ in 0..<5 { pbReq.putBoolean(false) } // v15 + v17 + v18
        pbReq.putU8(0) // v21 n_formats
        session.receive(PulsePStreamFrame.controlPacket(pbReq.data).encode())

        XCTAssertEqual(downFrames.count, 1)
        var rCreate = PulseTagstructReader(data: downFrames[0].payload)
        XCTAssertEqual(try rCreate.getU32(), PulseCommand.reply.rawValue)
        XCTAssertEqual(try rCreate.getU32(), 2)
        _ = try rCreate.getU32() // pbChannel
        _ = try rCreate.getU32() // sink_input_idx
        let grantedMissing = try rCreate.getU32()
        _ = try rCreate.getU32() // maxlength
        let grantedTlength = try rCreate.getU32()
        let grantedPrebuf = try rCreate.getU32()
        let grantedMinreq = try rCreate.getU32()
        XCTAssertGreaterThanOrEqual(grantedMissing, 23_040) // >= 120ms @ 192KB/s
        XCTAssertGreaterThanOrEqual(grantedTlength, 23_040) // >= 120ms @ 192KB/s
        XCTAssertGreaterThanOrEqual(grantedPrebuf, grantedMinreq)

        // Write 4096 bytes directly on channel without consuming to simulate buffered audio.
        downFrames.removeAll()
        // Prevent MockAudioBackend from calling onConsumedCallbacks synchronously:
        let noConsumeBackend = MockPulseWithoutConsume()
        let session2 = PulseAudioSession(
            connid: "c-flush-2",
            backend: noConsumeBackend,
            sendFrame: { bytes in
                if let parsed = try? downReader.feed(bytes) {
                    downFrames.append(contentsOf: parsed)
                }
            },
            closeTransport: {}
        )
        session2.receive(PulsePStreamFrame.controlPacket(auth.data).encode())
        downFrames.removeAll()
        session2.receive(PulsePStreamFrame.controlPacket(pbReq.data).encode())
        var r2 = PulseTagstructReader(data: downFrames[0].payload)
        _ = try r2.getU32()
        _ = try r2.getU32()
        let ch2 = try r2.getU32()

        downFrames.removeAll()
        session2.receive(PulsePStreamFrame.audioBlock(channel: ch2, payload: Data(repeating: 0x01, count: 4096)).encode())

        var flushReq = PulseTagstructWriter()
        flushReq.putU32(PulseCommand.flushPlaybackStream.rawValue)
        flushReq.putU32(3)
        flushReq.putU32(ch2)
        session2.receive(PulsePStreamFrame.controlPacket(flushReq.data).encode())

        let requests = downFrames.compactMap { frame -> UInt32? in
            var rd = PulseTagstructReader(data: frame.payload)
            guard (try? rd.getU32()) == PulseCommand.request.rawValue else { return nil }
            _ = try? rd.getU32()
            guard (try? rd.getU32()) == ch2 else { return nil }
            return try? rd.getU32()
        }
        XCTAssertEqual(requests, [4096])
    }

    private final class MockPulseWithoutConsume: PulseAudioBackend {
        func openPlaybackStream(id: UUID, spec: PulseSampleSpec, prebufBytes: Int, corked: Bool, onDataConsumed: @escaping (Int) -> Void) -> Bool { true }
        func writePlaybackData(id: UUID, data: Data) {}
        func setPlaybackCorked(id: UUID, corked: Bool) {}
        func flushPlaybackStream(id: UUID) {}
        func drainPlaybackStream(id: UUID, completion: @escaping () -> Void) { completion() }
        func playbackLatencyUsec(id: UUID) -> UInt64 { 15_000 }
        func closePlaybackStream(id: UUID) {}
        func requestMicrophoneAuthorization(completion: @escaping (Bool) -> Void) { completion(false) }
        func openRecordStream(id: UUID, spec: PulseSampleSpec, fragSize: Int, corked: Bool, onCaptureData: @escaping (Data) -> Void) -> Bool { false }
        func setRecordCorked(id: UUID, corked: Bool) {}
        func flushRecordStream(id: UUID) {}
        func recordLatencyUsec(id: UUID) -> UInt64 { 15_000 }
        func closeRecordStream(id: UUID) {}
    }
}
