//
//  SSHAudioEngine.swift
//  iTerm2SharedARC
//
//  macOS CoreAudio / AVAudioEngine backend for `PulseAudioSession`, supporting
//  multi-stream playback mixing, hardware sample-rate conversion, and lazy mic
//  tap teardown (clearing the macOS menu-bar mic indicator when idle).
//

import AVFAudio
import AVFoundation
import Foundation
import os.lock

/// Pure Swift codec converting between PulseAudio's wire PCM formats (`PulseSampleSpec`) and
/// standard non-interleaved `Float32` `AVAudioPCMBuffer`s.
enum PulsePCMCodec {

    static func floatFormat(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat? {
        if channels <= 2 {
            return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
        }
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)) else {
            return nil
        }
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
    }

    static func decodeToFloatBuffer(_ data: Data, spec: PulseSampleSpec) -> AVAudioPCMBuffer? {
        guard spec.isValid, let fmt = spec.parsedFormat else { return nil }
        let frameSize = spec.frameSize
        guard frameSize > 0 else { return nil }
        let frameCount = data.count / frameSize
        guard frameCount > 0 else { return nil }

        let channels = Int(spec.channels)
        guard let avFormat = floatFormat(sampleRate: Double(spec.rate),
                                         channels: AVAudioChannelCount(channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: avFormat,
                                            frameCapacity: AVAudioFrameCount(frameCount)),
              let floatChannels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let bps = fmt.bytesPerSample
        data.withUnsafeBytes { rawPtr in
            guard let base = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return }
            for frame in 0..<frameCount {
                let frameBase = frame * frameSize
                for ch in 0..<channels {
                    let sampleOffset = frameBase + ch * bps
                    floatChannels[ch][frame] = decodeSample(base.advanced(by: sampleOffset), format: fmt)
                }
            }
        }
        return buffer
    }

    static func encodeFromFloatBuffer(_ buffer: AVAudioPCMBuffer, spec: PulseSampleSpec) -> Data {
        guard spec.isValid,
              let fmt = spec.parsedFormat,
              let floatChannels = buffer.floatChannelData else {
            return Data()
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return Data() }
        let outChannels = Int(spec.channels)
        let inChannels = Int(buffer.format.channelCount)
        let bps = fmt.bytesPerSample
        var out = Data(count: frames * outChannels * bps)

        out.withUnsafeMutableBytes { outRaw in
            guard let dst = outRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            for frame in 0..<frames {
                for ch in 0..<outChannels {
                    let sample: Float
                    if outChannels == 1 && inChannels >= 2 {
                        sample = 0.5 * (floatChannels[0][frame] + floatChannels[1][frame])
                    } else if ch < inChannels {
                        sample = floatChannels[ch][frame]
                    } else {
                        sample = inChannels > 0 ? floatChannels[0][frame] : 0
                    }
                    let clamped = max(-1.0, min(1.0, sample))
                    encodeSample(clamped, to: dst.advanced(by: (frame * outChannels + ch) * bps), format: fmt)
                }
            }
        }
        return out
    }

    private static func decodeSample(_ p: UnsafePointer<UInt8>, format: PulseSampleFormat) -> Float {
        switch format {
        case .u8:
            return (Float(Int(p[0]) - 128)) / 128.0
        case .alaw:
            return Float(decodeALaw(p[0])) / 32768.0
        case .ulaw:
            return Float(decodeULaw(p[0])) / 32768.0
        case .s16le:
            let v = Int16(bitPattern: UInt16(p[0]) | (UInt16(p[1]) << 8))
            return Float(v) / 32768.0
        case .s16be:
            let v = Int16(bitPattern: (UInt16(p[0]) << 8) | UInt16(p[1]))
            return Float(v) / 32768.0
        case .float32le:
            let bits = UInt32(p[0]) | (UInt32(p[1]) << 8) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 24)
            return Float(bitPattern: bits)
        case .float32be:
            let bits = (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
            return Float(bitPattern: bits)
        case .s32le:
            let bits = UInt32(p[0]) | (UInt32(p[1]) << 8) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 24)
            return Float(Double(Int32(bitPattern: bits)) / 2147483648.0)
        case .s32be:
            let bits = (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
            return Float(Double(Int32(bitPattern: bits)) / 2147483648.0)
        case .s24le:
            let raw = (UInt32(p[0]) << 8) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 24)
            return Float(Double(Int32(bitPattern: raw)) / 2147483648.0)
        case .s24be:
            let raw = (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8)
            return Float(Double(Int32(bitPattern: raw)) / 2147483648.0)
        case .s24_32le:
            let raw = (UInt32(p[0]) << 8) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 24)
            return Float(Double(Int32(bitPattern: raw)) / 2147483648.0)
        case .s24_32be:
            let raw = (UInt32(p[1]) << 24) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 8)
            return Float(Double(Int32(bitPattern: raw)) / 2147483648.0)
        }
    }

    private static func encodeSample(_ sample: Float, to p: UnsafeMutablePointer<UInt8>, format: PulseSampleFormat) {
        switch format {
        case .u8:
            let s = Int((sample * 127.0).rounded()) + 128
            p[0] = UInt8(clamping: s)
        case .alaw:
            let s = Int16(clamping: Int((sample * 32767.0).rounded()))
            p[0] = encodeALaw(s)
        case .ulaw:
            let s = Int16(clamping: Int((sample * 32767.0).rounded()))
            p[0] = encodeULaw(s)
        case .s16le:
            let u = UInt16(bitPattern: Int16(clamping: Int((sample * 32767.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u)
            p[1] = UInt8(truncatingIfNeeded: u >> 8)
        case .s16be:
            let u = UInt16(bitPattern: Int16(clamping: Int((sample * 32767.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u >> 8)
            p[1] = UInt8(truncatingIfNeeded: u)
        case .float32le:
            let u = sample.bitPattern
            p[0] = UInt8(truncatingIfNeeded: u)
            p[1] = UInt8(truncatingIfNeeded: u >> 8)
            p[2] = UInt8(truncatingIfNeeded: u >> 16)
            p[3] = UInt8(truncatingIfNeeded: u >> 24)
        case .float32be:
            let u = sample.bitPattern
            p[0] = UInt8(truncatingIfNeeded: u >> 24)
            p[1] = UInt8(truncatingIfNeeded: u >> 16)
            p[2] = UInt8(truncatingIfNeeded: u >> 8)
            p[3] = UInt8(truncatingIfNeeded: u)
        case .s32le:
            let u = UInt32(bitPattern: Int32(clamping: Int64((Double(sample) * 2147483647.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u)
            p[1] = UInt8(truncatingIfNeeded: u >> 8)
            p[2] = UInt8(truncatingIfNeeded: u >> 16)
            p[3] = UInt8(truncatingIfNeeded: u >> 24)
        case .s32be:
            let u = UInt32(bitPattern: Int32(clamping: Int64((Double(sample) * 2147483647.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u >> 24)
            p[1] = UInt8(truncatingIfNeeded: u >> 16)
            p[2] = UInt8(truncatingIfNeeded: u >> 8)
            p[3] = UInt8(truncatingIfNeeded: u)
        case .s24le:
            let u = UInt32(bitPattern: Int32(clamping: Int64((Double(sample) * 8388607.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u)
            p[1] = UInt8(truncatingIfNeeded: u >> 8)
            p[2] = UInt8(truncatingIfNeeded: u >> 16)
        case .s24be:
            let u = UInt32(bitPattern: Int32(clamping: Int64((Double(sample) * 8388607.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u >> 16)
            p[1] = UInt8(truncatingIfNeeded: u >> 8)
            p[2] = UInt8(truncatingIfNeeded: u)
        case .s24_32le:
            let u = UInt32(bitPattern: Int32(clamping: Int64((Double(sample) * 8388607.0).rounded())))
            p[0] = UInt8(truncatingIfNeeded: u)
            p[1] = UInt8(truncatingIfNeeded: u >> 8)
            p[2] = UInt8(truncatingIfNeeded: u >> 16)
            p[3] = (u & 0x0080_0000) != 0 ? 0xFF : 0x00
        case .s24_32be:
            let u = UInt32(bitPattern: Int32(clamping: Int64((Double(sample) * 8388607.0).rounded())))
            p[0] = (u & 0x0080_0000) != 0 ? 0xFF : 0x00
            p[1] = UInt8(truncatingIfNeeded: u >> 16)
            p[2] = UInt8(truncatingIfNeeded: u >> 8)
            p[3] = UInt8(truncatingIfNeeded: u)
        }
    }

    private static func decodeULaw(_ byte: UInt8) -> Int16 {
        let u = ~byte
        let sign = (u & 0x80) != 0
        let exponent = Int((u >> 4) & 0x07)
        let mantissa = Int(u & 0x0F)
        let magnitude = (((mantissa << 3) + 0x84) << exponent) - 0x84
        return Int16(clamping: sign ? -magnitude : magnitude)
    }

    private static func encodeULaw(_ sample: Int16) -> UInt8 {
        let bias = 0x84
        let clip = 32635
        var pcm = Int(sample)
        var mask = 0xFF
        if pcm < 0 {
            pcm = -pcm
            mask = 0x7F
        }
        if pcm > clip { pcm = clip }
        pcm += bias
        var exp = 7
        var expMask = 0x4000
        while exp > 0 && (pcm & expMask) == 0 {
            exp -= 1
            expMask >>= 1
        }
        let mant = (pcm >> (exp + 3)) & 0x0F
        return UInt8((exp << 4) | mant) ^ UInt8(mask)
    }

    private static func decodeALaw(_ byte: UInt8) -> Int16 {
        let a = byte ^ 0x55
        let sign = (a & 0x80) == 0
        let exponent = Int((a >> 4) & 0x07)
        let mantissa = Int(a & 0x0F)
        var value = (mantissa << 4) + 8
        if exponent != 0 {
            value = (value + 0x100) << (exponent - 1)
        }
        return Int16(clamping: sign ? -value : value)
    }

    private static func encodeALaw(_ sample: Int16) -> UInt8 {
        var pcm = Int(sample)
        var mask = 0xD5
        if pcm < 0 {
            pcm = -pcm - 1
            mask = 0x55
        }
        if pcm > 32767 { pcm = 32767 }
        var exp = 7
        var expMask = 0x4000
        while exp > 0 && (pcm & expMask) == 0 {
            exp -= 1
            expMask >>= 1
        }
        let mant = (pcm >> (exp == 0 ? 4 : (exp + 3))) & 0x0F
        return UInt8((exp << 4) | mant) ^ UInt8(mask)
    }
}

/// Lock-protected, zero-allocation real-time stereo PCM ring buffer for jitter absorption,
/// prebuffering, de-click fade-in/out ramps, and byte-accurate PulseAudio credit accounting.
final class PlaybackRingBuffer: @unchecked Sendable {
    let sampleRate: Double
    private let clientFrameSize: Int
    private let initialPrebufFrames: Int
    private let underrunReprimeFrames: Int
    private let fadeLength = 64

    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private var left: UnsafeMutablePointer<Float>
    private var right: UnsafeMutablePointer<Float>
    private var capacity: Int
    private var readPos = 0
    private var writePos = 0
    private var availableFrames = 0

    private var activePrebufFrames: Int
    private var isPrimed = false
    private var forceStart = false
    private var corked: Bool
    private var gain: Float = 1.0
    private var fadeInRemaining = 0
    private var lastLeft: Float = 0.0
    private var lastRight: Float = 0.0
    private var unconsumedWireBytes = 0
    private var pendingConsumedWireBytes = 0

    init(sampleRate: Double,
         spec: PulseSampleSpec,
         prebufBytes: Int,
         corked: Bool) {
        let safeRate = max(sampleRate, 8_000.0)
        let fsize = max(spec.frameSize, 1)
        self.sampleRate = safeRate
        self.clientFrameSize = fsize
        let cap = max(Int((safeRate * 4.0).rounded()), 16_384)
        self.capacity = cap
        self.left = .allocate(capacity: cap)
        self.right = .allocate(capacity: cap)
        self.left.initialize(repeating: 0, count: cap)
        self.right.initialize(repeating: 0, count: cap)
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock_s())

        let prebufSec = spec.rate > 0 ? Double(prebufBytes / fsize) / Double(spec.rate) : 0.060
        let prebufFrames = Int((prebufSec * safeRate).rounded())
        let minInitialFrames = Int((safeRate * 0.020).rounded())
        self.initialPrebufFrames = min(max(prebufFrames, minInitialFrames), cap / 2)
        self.underrunReprimeFrames = min(max(self.initialPrebufFrames, Int((safeRate * 0.040).rounded())), cap / 2)
        self.activePrebufFrames = self.initialPrebufFrames
        self.corked = corked
    }

    deinit {
        left.deallocate()
        right.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body()
    }

    func push(left srcLeft: UnsafePointer<Float>?,
              right srcRight: UnsafePointer<Float>?,
              frameCount: Int,
              wireBytes: Int) {
        withLock {
            if frameCount > 0, let srcLeft {
                let srcR = srcRight ?? srcLeft
                let maxCapacityFrames = max(Int((sampleRate * 10.0).rounded()), 65_536)
                let toWrite = min(frameCount, maxCapacityFrames)
                let srcOffset = frameCount - toWrite
                if availableFrames + toWrite > maxCapacityFrames {
                    let drop = (availableFrames + toWrite) - maxCapacityFrames
                    readPos = (readPos + drop) % capacity
                    availableFrames = max(0, availableFrames - drop)
                }
                ensureCapacityLocked(needed: min(availableFrames + toWrite, maxCapacityFrames),
                                     maxCapacity: maxCapacityFrames)
                let first = min(toWrite, capacity - writePos)
                left.advanced(by: writePos).update(from: srcLeft.advanced(by: srcOffset), count: first)
                right.advanced(by: writePos).update(from: srcR.advanced(by: srcOffset), count: first)
                let second = toWrite - first
                if second > 0 {
                    left.update(from: srcLeft.advanced(by: srcOffset + first), count: second)
                    right.update(from: srcR.advanced(by: srcOffset + first), count: second)
                }
                writePos = (writePos + toWrite) % capacity
                availableFrames += toWrite
            }
            if wireBytes > 0 {
                unconsumedWireBytes += wireBytes
            }
        }
    }

    private func ensureCapacityLocked(needed: Int, maxCapacity: Int) {
        guard needed > capacity, capacity < maxCapacity else { return }
        let newCap = min(max(capacity * 2, needed), maxCapacity)
        let newLeft = UnsafeMutablePointer<Float>.allocate(capacity: newCap)
        let newRight = UnsafeMutablePointer<Float>.allocate(capacity: newCap)
        newLeft.initialize(repeating: 0, count: newCap)
        newRight.initialize(repeating: 0, count: newCap)
        if availableFrames > 0 {
            let first = min(availableFrames, capacity - readPos)
            newLeft.update(from: left.advanced(by: readPos), count: first)
            newRight.update(from: right.advanced(by: readPos), count: first)
            let second = availableFrames - first
            if second > 0 {
                newLeft.advanced(by: first).update(from: left, count: second)
                newRight.advanced(by: first).update(from: right, count: second)
            }
        }
        left.deallocate()
        right.deallocate()
        left = newLeft
        right = newRight
        capacity = newCap
        readPos = 0
        writePos = availableFrames
    }

    func setCorked(_ value: Bool) {
        withLock {
            corked = value
            if value {
                isPrimed = false
                forceStart = false
            }
        }
    }

    func setGain(_ value: Float) {
        withLock {
            gain = max(0.0, min(2.0, value))
        }
    }

    func trigger() {
        withLock {
            forceStart = true
        }
    }

    func flush() {
        withLock {
            readPos = 0
            writePos = 0
            availableFrames = 0
            unconsumedWireBytes = 0
            pendingConsumedWireBytes = 0
            isPrimed = false
            forceStart = false
            activePrebufFrames = initialPrebufFrames
            fadeInRemaining = 0
            lastLeft = 0
            lastRight = 0
        }
    }

    var queuedFrames: Int {
        withLock { availableFrames }
    }

    var isDrained: Bool {
        withLock {
            availableFrames == 0 && unconsumedWireBytes == 0 && pendingConsumedWireBytes == 0
        }
    }

    /// Renders `frames` stereo samples into `outLeft` / `outRight` using zero heap allocations.
    /// Returns `true` if any non-silent audio or de-click ramp was written.
    @discardableResult
    func render(frames: Int,
                outLeft: UnsafeMutablePointer<Float>,
                outRight: UnsafeMutablePointer<Float>) -> Bool {
        guard frames > 0 else { return false }
        return withLock {
            if corked {
                isPrimed = false
                forceStart = false
                return writeDecayAndZeroLocked(fromIndex: 0, totalFrames: frames, outLeft: outLeft, outRight: outRight)
            }

            if !isPrimed {
                if availableFrames >= activePrebufFrames || (forceStart && availableFrames > 0) {
                    isPrimed = true
                    fadeInRemaining = (lastLeft == 0 && lastRight == 0) ? fadeLength : 0
                } else {
                    return writeDecayAndZeroLocked(fromIndex: 0, totalFrames: frames, outLeft: outLeft, outRight: outRight)
                }
            }

            let take = min(frames, availableFrames)
            let prevAvail = availableFrames
            if take > 0 {
                let g = gain
                for i in 0..<take {
                    let idx = (readPos + i) % capacity
                    var scale = g
                    if fadeInRemaining > 0 {
                        let step = fadeLength - fadeInRemaining + 1
                        scale *= Float(step) / Float(fadeLength)
                        fadeInRemaining -= 1
                    }
                    let l = left[idx] * scale
                    let r = right[idx] * scale
                    outLeft[i] = l
                    outRight[i] = r
                    lastLeft = l
                    lastRight = r
                }
                readPos = (readPos + take) % capacity
                availableFrames -= take
                accountConsumedBytesLocked(takenFrames: take, previousAvailable: prevAvail)
            }

            if take < frames {
                _ = writeDecayAndZeroLocked(fromIndex: take, totalFrames: frames, outLeft: outLeft, outRight: outRight)
                isPrimed = false
                forceStart = false
                activePrebufFrames = underrunReprimeFrames
                if availableFrames == 0 && unconsumedWireBytes > 0 {
                    pendingConsumedWireBytes += unconsumedWireBytes
                    unconsumedWireBytes = 0
                }
            }
            return take > 0
        }
    }

    private func writeDecayAndZeroLocked(fromIndex start: Int,
                                         totalFrames: Int,
                                         outLeft: UnsafeMutablePointer<Float>,
                                         outRight: UnsafeMutablePointer<Float>) -> Bool {
        let rem = totalFrames - start
        guard rem > 0 else { return false }
        let decay = (lastLeft != 0 || lastRight != 0) ? min(rem, fadeLength) : 0
        if decay > 0 {
            for i in 0..<decay {
                let ramp = Float(decay - 1 - i) / Float(decay)
                outLeft[start + i] = lastLeft * ramp
                outRight[start + i] = lastRight * ramp
            }
        }
        let zeroCount = rem - decay
        if zeroCount > 0 {
            outLeft.advanced(by: start + decay).update(repeating: 0, count: zeroCount)
            outRight.advanced(by: start + decay).update(repeating: 0, count: zeroCount)
        }
        lastLeft = 0
        lastRight = 0
        return decay > 0
    }

    private func accountConsumedBytesLocked(takenFrames: Int, previousAvailable: Int) {
        guard takenFrames > 0, previousAvailable > 0, unconsumedWireBytes > 0 else { return }
        let consumed: Int
        if takenFrames == previousAvailable {
            consumed = unconsumedWireBytes
        } else {
            let raw = Int((Int64(unconsumedWireBytes) * Int64(takenFrames)) / Int64(previousAvailable))
            consumed = min(unconsumedWireBytes, (raw / clientFrameSize) * clientFrameSize)
        }
        unconsumedWireBytes -= consumed
        pendingConsumedWireBytes += consumed
    }

    /// Simulates consumption at `sampleRate` when running without CoreAudio hardware output.
    func consumeVirtual(elapsed: TimeInterval) {
        let frames = max(1, Int((sampleRate * elapsed).rounded()))
        withLock {
            guard !corked else {
                isPrimed = false
                forceStart = false
                return
            }
            if !isPrimed {
                if availableFrames >= activePrebufFrames || (forceStart && availableFrames > 0) {
                    isPrimed = true
                } else {
                    return
                }
            }
            let take = min(frames, availableFrames)
            let prevAvail = availableFrames
            if take > 0 {
                readPos = (readPos + take) % capacity
                availableFrames -= take
                accountConsumedBytesLocked(takenFrames: take, previousAvailable: prevAvail)
            }
            if take < frames {
                isPrimed = false
                forceStart = false
                activePrebufFrames = underrunReprimeFrames
                if availableFrames == 0 && unconsumedWireBytes > 0 {
                    pendingConsumedWireBytes += unconsumedWireBytes
                    unconsumedWireBytes = 0
                }
            }
        }
    }

    func harvestCreditsAndDrainState() -> (consumedBytes: Int, isDrained: Bool) {
        withLock {
            let bytes = pendingConsumedWireBytes
            pendingConsumedWireBytes = 0
            let drained = (availableFrames == 0 && unconsumedWireBytes == 0 && bytes == 0)
            return (bytes, drained)
        }
    }
}

final class SSHAudioEngine: PulseAudioBackend {
    typealias AuthorizationHandler = (@escaping (Bool) -> Void) -> Void

    private final class PlaybackChannel {
        let id: UUID
        let spec: PulseSampleSpec
        let ring: PlaybackRingBuffer
        let sourceNode: AVAudioSourceNode?
        let renderStereoFormat: AVAudioFormat
        let converterInputFormat: AVAudioFormat
        let converterOutputFormat: AVAudioFormat
        let converter: AVAudioConverter?
        var corked: Bool
        var remainder = Data()
        var drainWaiters: [() -> Void] = []
        let onDataConsumed: (Int) -> Void

        init?(id: UUID,
              spec: PulseSampleSpec,
              renderFormat: AVAudioFormat,
              prebufBytes: Int,
              corked: Bool,
              attachSourceNode: Bool,
              onDataConsumed: @escaping (Int) -> Void) {
            let normalizedCh: AVAudioChannelCount = spec.channels == 1 ? 1 : 2
            guard let srcFmt = PulsePCMCodec.floatFormat(sampleRate: Double(spec.rate), channels: normalizedCh),
                  let dstFmt = PulsePCMCodec.floatFormat(sampleRate: renderFormat.sampleRate, channels: normalizedCh) else {
                return nil
            }
            self.id = id
            self.spec = spec
            self.ring = PlaybackRingBuffer(sampleRate: renderFormat.sampleRate,
                                           spec: spec,
                                           prebufBytes: prebufBytes,
                                           corked: corked)
            self.renderStereoFormat = renderFormat
            self.converterInputFormat = srcFmt
            self.converterOutputFormat = dstFmt
            if Int(spec.rate) != Int(renderFormat.sampleRate.rounded()),
               let conv = AVAudioConverter(from: srcFmt, to: dstFmt) {
                conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
                conv.primeMethod = .normal
                self.converter = conv
            } else {
                self.converter = nil
            }
            if attachSourceNode {
                let ring = self.ring
                self.sourceNode = AVAudioSourceNode(format: renderFormat) { isSilence, _, frameCount, audioBufferList -> OSStatus in
                    let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                    guard abl.count >= 2,
                          let outL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                          let outR = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                        isSilence.pointee = true
                        return noErr
                    }
                    let wroteAudio = ring.render(frames: Int(frameCount), outLeft: outL, outRight: outR)
                    isSilence.pointee = ObjCBool(!wroteAudio)
                    return noErr
                }
            } else {
                self.sourceNode = nil
            }
            self.corked = corked
            self.onDataConsumed = onDataConsumed
        }
    }

    private final class RecordChannel {
        let id: UUID
        let spec: PulseSampleSpec
        let fragSize: Int
        let targetFloatFormat: AVAudioFormat
        var converter: AVAudioConverter?
        var converterSourceFormat: AVAudioFormat?
        var corked: Bool
        var accum = Data()
        let onCaptureData: (Data) -> Void

        init?(id: UUID,
              spec: PulseSampleSpec,
              fragSize: Int,
              corked: Bool,
              onCaptureData: @escaping (Data) -> Void) {
            guard let fmt = PulsePCMCodec.floatFormat(sampleRate: Double(spec.rate),
                                                      channels: AVAudioChannelCount(spec.channels)) else {
                return nil
            }
            self.id = id
            self.spec = spec
            self.fragSize = max(fragSize, max(spec.frameSize, 2))
            self.targetFloatFormat = fmt
            self.corked = corked
            self.onCaptureData = onCaptureData
        }
    }

    private let engine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.googlecode.iterm2.ssh-audio", qos: .userInteractive)
    private let audioQueueKey = DispatchSpecificKey<UInt8>()
    private var creditTimer: DispatchSourceTimer?
    private var lastCreditTickTime: CFAbsoluteTime = 0
    private var playbackChannels: [UUID: PlaybackChannel] = [:]
    private var recordChannels: [UUID: RecordChannel] = [:]
    private var inputTapInstalled = false
    private var hardwareRenderingActive = false
    private var engineAvailable = true
    private var engineAvailableLocked = true
    private let authorizeMicrophone: AuthorizationHandler

    var isMuted: Bool = false {
        didSet {
            if engine.isRunning {
                engine.mainMixerNode.outputVolume = isMuted ? 0.0 : 1.0
            }
        }
    }

    init(enableHardwareGraph: Bool = true,
         authorizeMicrophone: @escaping AuthorizationHandler) {
        self.engineAvailable = enableHardwareGraph
        self.engineAvailableLocked = enableHardwareGraph
        self.authorizeMicrophone = authorizeMicrophone
        audioQueue.setSpecific(key: audioQueueKey, value: 1)
    }

    deinit {
        if Thread.isMainThread {
            shutdownAll()
        } else {
            let engine = self.engine
            let hadTap = self.inputTapInstalled
            creditTimer?.cancel()
            DispatchQueue.main.async {
                if hadTap {
                    engine.inputNode.removeTap(onBus: 0)
                }
                if engine.isRunning {
                    engine.stop()
                }
            }
        }
    }

    private func withAudioQueueSync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: audioQueueKey) == 1 {
            return body()
        }
        return audioQueue.sync(execute: body)
    }

    func shutdownAll() {
        let (pbIDs, recIDs) = withAudioQueueSync {
            (Array(playbackChannels.keys), Array(recordChannels.keys))
        }
        for id in pbIDs {
            closePlaybackStream(id: id)
        }
        for id in recIDs {
            closeRecordStream(id: id)
        }
        withAudioQueueSync {
            stopCreditTimerLocked()
        }
        stopEngineIfIdle()
    }

    private func resolveRenderStereoFormat() -> AVAudioFormat {
        let fallback = AVAudioFormat(standardFormatWithSampleRate: 48_000.0, channels: 2)!
        guard engineAvailable else {
            return fallback
        }
        let hwRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let mixerRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let candidate = hwRate > 0 ? hwRate : (mixerRate > 0 ? mixerRate : 48_000.0)
        guard candidate >= 8_000.0 && candidate <= 384_000.0,
              let format = AVAudioFormat(standardFormatWithSampleRate: candidate, channels: 2) else {
            return fallback
        }
        return format
    }

    // MARK: - PulseAudioBackend (Playback)

    func openPlaybackStream(id: UUID,
                            spec: PulseSampleSpec,
                            prebufBytes: Int,
                            corked: Bool,
                            onDataConsumed: @escaping (Int) -> Void) -> Bool {
        let renderFormat = resolveRenderStereoFormat()
        guard let ch = PlaybackChannel(id: id,
                                       spec: spec,
                                       renderFormat: renderFormat,
                                       prebufBytes: prebufBytes,
                                       corked: corked,
                                       attachSourceNode: engineAvailable,
                                       onDataConsumed: onDataConsumed) else {
            return false
        }
        if engineAvailable, let sourceNode = ch.sourceNode {
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: renderFormat)
        }
        withAudioQueueSync {
            playbackChannels[id] = ch
            startCreditTimerIfNeededLocked()
        }
        updateEngineState()
        return true
    }

    func writePlaybackData(id: UUID, data: Data) {
        guard !data.isEmpty else { return }
        audioQueue.async { [weak self] in
            guard let self, let ch = self.playbackChannels[id] else { return }
            let frameSize = max(ch.spec.frameSize, 1)
            ch.remainder.append(data)
            let alignedCount = (ch.remainder.count / frameSize) * frameSize
            guard alignedCount > 0 else { return }

            let alignedData = Data(ch.remainder.prefix(alignedCount))
            ch.remainder.removeFirst(alignedCount)
            self.decodeAndPushPlayback(alignedData, wireBytes: alignedCount, to: ch)
        }
    }

    private func decodeAndPushPlayback(_ alignedData: Data, wireBytes: Int, to ch: PlaybackChannel) {
        guard let decoded = PulsePCMCodec.decodeToFloatBuffer(alignedData, spec: ch.spec),
              let normalized = normalizePlaybackBuffer(decoded, targetChannels: ch.converterInputFormat.channelCount) else {
            ch.ring.push(left: nil, right: nil, frameCount: 0, wireBytes: wireBytes)
            return
        }
        guard let converter = ch.converter else {
            pushNormalizedBuffer(normalized, wireBytes: wireBytes, to: ch)
            return
        }

        let ratio = ch.converterOutputFormat.sampleRate / normalized.format.sampleRate
        let outCap = AVAudioFrameCount(max(ceil(Double(normalized.frameLength) * ratio) + 256.0, 256.0))
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: ch.converterOutputFormat, frameCapacity: outCap) else {
            ch.ring.push(left: nil, right: nil, frameCount: 0, wireBytes: wireBytes)
            return
        }
        var provided = false
        var convError: NSError?
        let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return normalized
        }
        if status == .haveData || status == .inputRanDry {
            pushNormalizedBuffer(outBuf, wireBytes: wireBytes, to: ch)
        } else {
            ch.ring.push(left: nil, right: nil, frameCount: 0, wireBytes: wireBytes)
        }
    }

    private func flushPlaybackConverterTailLocked(_ ch: PlaybackChannel) {
        guard let converter = ch.converter else { return }
        let outCap: AVAudioFrameCount = 512
        guard let tailBuf = AVAudioPCMBuffer(pcmFormat: ch.converterOutputFormat, frameCapacity: outCap) else {
            converter.reset()
            return
        }
        var convError: NSError?
        let status = converter.convert(to: tailBuf, error: &convError) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        if (status == .haveData || status == .endOfStream), tailBuf.frameLength > 0 {
            pushNormalizedBuffer(tailBuf, wireBytes: 0, to: ch)
        }
        converter.reset()
    }

    private func pushNormalizedBuffer(_ buf: AVAudioPCMBuffer, wireBytes: Int, to ch: PlaybackChannel) {
        guard let ptrs = buf.floatChannelData else { return }
        let count = Int(buf.frameLength)
        let outL = ptrs[0]
        let outR = Int(buf.format.channelCount) >= 2 ? ptrs[1] : ptrs[0]
        ch.ring.push(left: outL, right: outR, frameCount: count, wireBytes: wireBytes)
    }

    private func normalizePlaybackBuffer(_ buffer: AVAudioPCMBuffer,
                                         targetChannels: AVAudioChannelCount) -> AVAudioPCMBuffer? {
        let inChannels = buffer.format.channelCount
        if inChannels == targetChannels {
            return buffer
        }
        guard let fmt = PulsePCMCodec.floatFormat(sampleRate: buffer.format.sampleRate, channels: targetChannels),
              let dst = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: buffer.frameLength),
              let srcPtr = buffer.floatChannelData,
              let dstPtr = dst.floatChannelData else {
            return nil
        }
        let frames = Int(buffer.frameLength)
        dst.frameLength = buffer.frameLength
        if targetChannels == 2 && inChannels >= 2 {
            dstPtr[0].update(from: srcPtr[0], count: frames)
            dstPtr[1].update(from: srcPtr[1], count: frames)
        } else if targetChannels == 2 && inChannels == 1 {
            dstPtr[0].update(from: srcPtr[0], count: frames)
            dstPtr[1].update(from: srcPtr[0], count: frames)
        } else {
            dstPtr[0].update(from: srcPtr[0], count: frames)
        }
        return dst
    }

    func setPlaybackCorked(id: UUID, corked: Bool) {
        withAudioQueueSync {
            guard let ch = playbackChannels[id] else { return }
            ch.corked = corked
            ch.ring.setCorked(corked)
        }
        updateEngineState()
    }

    func triggerPlaybackStream(id: UUID) {
        withAudioQueueSync {
            playbackChannels[id]?.ring.trigger()
        }
    }

    func setPlaybackVolume(id: UUID, gain: Float) {
        withAudioQueueSync {
            playbackChannels[id]?.ring.setGain(gain)
        }
    }

    func flushPlaybackStream(id: UUID) {
        let waiters: [() -> Void] = withAudioQueueSync {
            guard let ch = playbackChannels[id] else { return [] }
            ch.remainder.removeAll(keepingCapacity: true)
            ch.converter?.reset()
            ch.ring.flush()
            let pending = ch.drainWaiters
            ch.drainWaiters.removeAll()
            return pending
        }
        for w in waiters {
            w()
        }
    }

    func drainPlaybackStream(id: UUID, completion: @escaping () -> Void) {
        let immediatelyDrained: Bool = withAudioQueueSync {
            guard let ch = playbackChannels[id] else { return true }
            flushPlaybackConverterTailLocked(ch)
            ch.ring.trigger()
            if ch.ring.isDrained {
                return true
            }
            ch.drainWaiters.append(completion)
            return false
        }
        if immediatelyDrained {
            completion()
        }
    }

    func playbackLatencyUsec(id: UUID) -> UInt64 {
        guard engine.isRunning else { return 15_000 }
        let outLat = engine.outputNode.presentationLatency
        return UInt64(max(outLat, 0.010) * 1_000_000.0)
    }

    func closePlaybackStream(id: UUID) {
        let removed: (PlaybackChannel?, Bool) = withAudioQueueSync {
            let ch = playbackChannels.removeValue(forKey: id)
            let empty = playbackChannels.isEmpty
            if empty {
                stopCreditTimerLocked()
            }
            return (ch, empty)
        }
        guard let ch = removed.0 else { return }
        let waiters = withAudioQueueSync {
            let pending = ch.drainWaiters
            ch.drainWaiters.removeAll()
            return pending
        }
        if let sourceNode = ch.sourceNode, sourceNode.engine === engine {
            engine.disconnectNodeOutput(sourceNode)
            engine.detach(sourceNode)
        }
        for w in waiters {
            w()
        }
        updateEngineState()
    }

    /// Deterministic unit-test helper: flushes queued playback writes and renders `frames` stereo samples.
    func renderPlaybackForTesting(id: UUID, frames: Int) -> (left: [Float], right: [Float], consumedBytes: Int)? {
        guard frames > 0 else { return nil }
        return withAudioQueueSync {
            guard let ch = playbackChannels[id] else { return nil }
            var outL = [Float](repeating: 0, count: frames)
            var outR = [Float](repeating: 0, count: frames)
            outL.withUnsafeMutableBufferPointer { lBuf in
                outR.withUnsafeMutableBufferPointer { rBuf in
                    _ = ch.ring.render(frames: frames, outLeft: lBuf.baseAddress!, outRight: rBuf.baseAddress!)
                }
            }
            let (consumed, drained) = ch.ring.harvestCreditsAndDrainState()
            if consumed > 0 {
                ch.onDataConsumed(consumed)
            }
            if drained && !ch.drainWaiters.isEmpty {
                let waiters = ch.drainWaiters
                ch.drainWaiters.removeAll()
                waiters.forEach { $0() }
            }
            return (outL, outR, consumed)
        }
    }

    // MARK: - Credit & Virtual Playback Timer

    private func startCreditTimerIfNeededLocked() {
        guard creditTimer == nil else { return }
        lastCreditTickTime = CFAbsoluteTimeGetCurrent()
        let timer = DispatchSource.makeTimerSource(queue: audioQueue)
        timer.schedule(deadline: .now() + .milliseconds(10),
                       repeating: .milliseconds(10),
                       leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.creditTimerTickLocked()
        }
        timer.resume()
        creditTimer = timer
    }

    private func stopCreditTimerLocked() {
        creditTimer?.cancel()
        creditTimer = nil
        lastCreditTickTime = 0
    }

    private func creditTimerTickLocked() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = lastCreditTickTime > 0 ? min(max(now - lastCreditTickTime, 0.001), 0.1) : 0.010
        lastCreditTickTime = now

        var dispatches: [(Int, [() -> Void], (Int) -> Void)] = []
        for ch in playbackChannels.values {
            if !engineAvailableLocked || !hardwareRenderingActive {
                ch.ring.consumeVirtual(elapsed: elapsed)
            }
            let (consumed, drained) = ch.ring.harvestCreditsAndDrainState()
            var waiters: [() -> Void] = []
            if drained && !ch.drainWaiters.isEmpty {
                waiters = ch.drainWaiters
                ch.drainWaiters.removeAll()
            }
            if consumed > 0 || !waiters.isEmpty {
                dispatches.append((consumed, waiters, ch.onDataConsumed))
            }
        }
        guard !dispatches.isEmpty else { return }
        DispatchQueue.main.async {
            for (consumed, waiters, callback) in dispatches {
                if consumed > 0 {
                    callback(consumed)
                }
                for w in waiters {
                    w()
                }
            }
        }
    }

    // MARK: - PulseAudioBackend (Capture)

    func requestMicrophoneAuthorization(completion: @escaping (Bool) -> Void) {
        authorizeMicrophone { hostAllowed in
            guard hostAllowed else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .denied, .restricted:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func openRecordStream(id: UUID,
                          spec: PulseSampleSpec,
                          fragSize: Int,
                          corked: Bool,
                          onCaptureData: @escaping (Data) -> Void) -> Bool {
        guard let rec = RecordChannel(id: id,
                                      spec: spec,
                                      fragSize: fragSize,
                                      corked: corked,
                                      onCaptureData: onCaptureData) else {
            return false
        }
        withAudioQueueSync {
            recordChannels[id] = rec
        }
        updateEngineState()
        return true
    }

    func setRecordCorked(id: UUID, corked: Bool) {
        withAudioQueueSync {
            guard let rec = recordChannels[id] else { return }
            rec.corked = corked
            if corked {
                rec.accum.removeAll(keepingCapacity: true)
                rec.converter?.reset()
            }
        }
        updateEngineState()
    }

    func flushRecordStream(id: UUID) {
        withAudioQueueSync {
            recordChannels[id]?.accum.removeAll(keepingCapacity: true)
            recordChannels[id]?.converter?.reset()
        }
    }

    func recordLatencyUsec(id: UUID) -> UInt64 {
        guard engine.isRunning else { return 15_000 }
        let inLat = engine.inputNode.presentationLatency
        return UInt64(max(inLat, 0.010) * 1_000_000.0)
    }

    func closeRecordStream(id: UUID) {
        let removed = withAudioQueueSync {
            recordChannels.removeValue(forKey: id) != nil
        }
        guard removed else { return }
        updateEngineState()
    }

    // MARK: - Engine Lifecycle

    private func updateEngineState() {
        let (needsPlayback, needsRecord) = withAudioQueueSync {
            (playbackChannels.values.contains { !$0.corked },
             recordChannels.values.contains { !$0.corked })
        }

        if !needsPlayback && !needsRecord {
            stopEngineIfIdle()
            return
        }

        guard engineAvailable else { return }
        let hasAudioInputDevice = AVCaptureDevice.default(for: .audio) != nil

        if needsRecord && !inputTapInstalled && hasAudioInputDevice {
            let inputNode = engine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)
            if hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 {
                inputNode.installTap(onBus: 0, bufferSize: 960, format: hwFormat) { [weak self] buffer, _ in
                    self?.handleCapturedBuffer(buffer)
                }
                inputTapInstalled = true
            }
        } else if !needsRecord && inputTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }

        if !engine.isRunning {
            engine.mainMixerNode.outputVolume = isMuted ? 0.0 : 1.0
            do {
                try engine.start()
                withAudioQueueSync {
                    hardwareRenderingActive = engine.isRunning
                }
            } catch {
                engineAvailable = false
                withAudioQueueSync {
                    engineAvailableLocked = false
                    hardwareRenderingActive = false
                }
            }
        } else {
            withAudioQueueSync {
                hardwareRenderingActive = true
            }
        }
    }

    private func stopEngineIfIdle() {
        if inputTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        withAudioQueueSync {
            hardwareRenderingActive = false
        }
    }

    private static func copyPCMBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameLength),
              let srcCh = src.floatChannelData,
              let dstCh = dst.floatChannelData else {
            return nil
        }
        let frames = Int(src.frameLength)
        let channels = Int(src.format.channelCount)
        dst.frameLength = src.frameLength
        for c in 0..<channels {
            dstCh[c].update(from: srcCh[c], count: frames)
        }
        return dst
    }

    private func handleCapturedBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let snapshot = Self.copyPCMBuffer(inputBuffer) else { return }
        audioQueue.async { [weak self] in
            guard let self else { return }
            let convertedChunks = self.convertCapturedBufferLocked(snapshot)
            var readySlices: [(() -> Void)] = []
            for (id, bytes) in convertedChunks {
                guard let rec = self.recordChannels[id], !rec.corked else { continue }
                rec.accum.append(bytes)
                var slices: [Data] = []
                while rec.accum.count >= rec.fragSize {
                    slices.append(Data(rec.accum.prefix(rec.fragSize)))
                    rec.accum.removeFirst(rec.fragSize)
                }
                if !slices.isEmpty {
                    let callback = rec.onCaptureData
                    readySlices.append {
                        for slice in slices {
                            callback(slice)
                        }
                    }
                }
            }
            guard !readySlices.isEmpty else { return }
            DispatchQueue.main.async {
                for deliver in readySlices {
                    deliver()
                }
            }
        }
    }

    /// Converts an incoming `AVAudioPCMBuffer` into each active record stream's wire format.
    func convertCapturedBufferForActiveStreams(_ inputBuffer: AVAudioPCMBuffer) -> [(UUID, Data)] {
        withAudioQueueSync {
            convertCapturedBufferLocked(inputBuffer)
        }
    }

    private func convertCapturedBufferLocked(_ inputBuffer: AVAudioPCMBuffer) -> [(UUID, Data)] {
        var out: [(UUID, Data)] = []
        let rawFormat = inputBuffer.format
        guard rawFormat.sampleRate > 0, rawFormat.channelCount > 0 else { return [] }

        for rec in recordChannels.values where !rec.corked {
            guard let normalized = normalizeCaptureChannels(inputBuffer,
                                                            targetChannels: rec.targetFloatFormat.channelCount) else {
                continue
            }
            let srcFormat = normalized.format
            if srcFormat == rec.targetFloatFormat {
                let wire = PulsePCMCodec.encodeFromFloatBuffer(normalized, spec: rec.spec)
                if !wire.isEmpty {
                    out.append((rec.id, wire))
                }
                continue
            }

            if rec.converter == nil || rec.converterSourceFormat != srcFormat {
                let conv = AVAudioConverter(from: srcFormat, to: rec.targetFloatFormat)
                conv?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
                conv?.primeMethod = .normal
                rec.converter = conv
                rec.converterSourceFormat = srcFormat
            }
            guard let converter = rec.converter else { continue }

            let ratio = rec.targetFloatFormat.sampleRate / srcFormat.sampleRate
            let outCapacity = AVAudioFrameCount(max(ceil(Double(normalized.frameLength) * ratio) + 64.0, 64.0))
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: rec.targetFloatFormat, frameCapacity: outCapacity) else {
                continue
            }

            var providedInput = false
            var convError: NSError?
            let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
                if providedInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                providedInput = true
                outStatus.pointee = .haveData
                return normalized
            }
            if (status == .haveData || status == .inputRanDry), outBuf.frameLength > 0 {
                let wire = PulsePCMCodec.encodeFromFloatBuffer(outBuf, spec: rec.spec)
                if !wire.isEmpty {
                    out.append((rec.id, wire))
                }
            }
        }
        return out
    }

    private func normalizeCaptureChannels(_ inputBuffer: AVAudioPCMBuffer,
                                          targetChannels: AVAudioChannelCount) -> AVAudioPCMBuffer? {
        let inCh = Int(inputBuffer.format.channelCount)
        let outCh = Int(targetChannels)
        if inCh == outCh {
            return inputBuffer
        }
        guard let fmt = PulsePCMCodec.floatFormat(sampleRate: inputBuffer.format.sampleRate, channels: targetChannels),
              let dst = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: inputBuffer.frameLength),
              let srcPtr = inputBuffer.floatChannelData,
              let dstPtr = dst.floatChannelData else {
            return nil
        }
        let frames = Int(inputBuffer.frameLength)
        dst.frameLength = inputBuffer.frameLength
        if outCh == 1 && inCh >= 2 {
            let inv = 1.0 / Float(inCh)
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<inCh {
                    sum += srcPtr[c][i]
                }
                dstPtr[0][i] = sum * inv
            }
        } else if outCh == 2 && inCh == 1 {
            dstPtr[0].update(from: srcPtr[0], count: frames)
            dstPtr[1].update(from: srcPtr[0], count: frames)
        } else {
            for c in 0..<outCh {
                dstPtr[c].update(from: srcPtr[min(c, inCh - 1)], count: frames)
            }
        }
        return dst
    }
}
