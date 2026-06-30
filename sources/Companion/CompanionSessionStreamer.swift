//
//  CompanionSessionStreamer.swift
//  iTerm2
//
//  Drives one session's live stream: the change-driven pacer decides when to
//  emit, the frame source renders the visible screen, the pixel pool converts it,
//  and the HEVC encoder compresses it. Encoded frames are assembled into media
//  frames (with a stream config on the first frame / on geometry change) and
//  handed to the host bridge via the onMedia / onConfig closures.
//
//  The session/render integration sits behind CompanionFrameSource so this type
//  has no dependency on PTYSession and can be tested with a fake source. tick()
//  must be called on the main thread (the real frame source renders there);
//  encoder callbacks arrive on a VideoToolbox thread and are serialized with the
//  lock.
//

import CoreGraphics
import Foundation

/// The session-side inputs the streamer needs: the geometry of the rendered
/// frame and a way to render the current visible screen.
protocol CompanionFrameSource: AnyObject {
    var columns: Int { get }
    var rows: Int { get }
    /// Encoded pixels per Mac point (the render scale).
    var scale: Double { get }
    /// Render the current visible screen, or nil if it cannot be produced now.
    /// The encoder and pool size themselves to the returned image's dimensions.
    func renderCurrentScreen() -> CGImage?
}

final class CompanionSessionStreamer: @unchecked Sendable {
    let streamID: UInt32

    private let source: CompanionFrameSource
    private let averageBitRate: Int
    private let onConfig: (CompanionStreamConfig) -> Void
    private let onMedia: (CompanionMediaFrame) -> Void

    private let lock = NSLock()
    private var pacer: CompanionStreamPacer
    private var pool: CompanionPixelBufferPool?
    private var encoder: CompanionVideoEncoder?
    private var sequence: UInt32 = 0
    private var generationId: UInt32 = 0
    private var sentConfigDimensions: (Int, Int)?
    /// Content hash of the last frame handed to the encoder. A frame whose pixels
    /// match it is skipped (the phone already shows it), so a static screen costs
    /// nothing even though cosmetic repaints keep driving tick(). Cleared on a
    /// resize so the first frame at a new size always encodes.
    private var lastSentHash: UInt64?

    init(streamID: UInt32,
         source: CompanionFrameSource,
         maxFrameRate: Double = 30,
         averageBitRate: Int = 1_000_000,
         onConfig: @escaping (CompanionStreamConfig) -> Void,
         onMedia: @escaping (CompanionMediaFrame) -> Void) {
        self.streamID = streamID
        self.source = source
        self.averageBitRate = averageBitRate
        self.onConfig = onConfig
        self.onMedia = onMedia
        self.pacer = CompanionStreamPacer(minInterval: maxFrameRate > 0 ? 1.0 / maxFrameRate : 0)
    }

    /// Begin streaming: the first emitted frame is a keyframe.
    func start() {
        lock.lock(); pacer.requestKeyframe(); lock.unlock()
    }

    /// The session's screen changed (drive from the render cadence / dirty hook).
    func screenDidChange() {
        lock.lock(); pacer.noteDirty(); lock.unlock()
    }

    /// Force the next frame to be a keyframe, promptly (subscribe/resume/recovery).
    func requestKeyframe() {
        lock.lock(); pacer.requestKeyframe(); lock.unlock()
    }

    /// Evaluate the pacer at `nowMilliseconds` and, if it says to emit, render and
    /// encode a frame. Call on the main thread.
    func tick(nowMilliseconds: UInt64) {
        lock.lock()
        let decision = pacer.evaluate(now: TimeInterval(nowMilliseconds) / 1000.0)
        lock.unlock()
        guard let decision else { return }
        guard let image = source.renderCurrentScreen() else { return }
        guard ensureEncoder(width: image.width, height: image.height),
              let encoder, let pool,
              let pixelBuffer = try? pool.pixelBuffer(from: image) else {
            return
        }
        // Skip frames whose pixels are unchanged so an idle screen (cosmetic
        // repaints like cursor blink) costs zero bytes. A forced keyframe always
        // encodes -- a (re)subscribe/resume needs a fresh IDR even if static.
        let hash = CompanionPixelBufferHash.hash(pixelBuffer)
        if !decision.keyframe && hash == lastSentHash {
            return
        }
        lastSentHash = hash
        encoder.encode(pixelBuffer, ptsMilliseconds: nowMilliseconds, forceKeyframe: decision.keyframe)
    }

    /// Flush in-flight frames (teardown, and to make encoding synchronous in tests).
    func flush() {
        encoder?.finish()
    }

    func stop() {
        encoder?.finish()
        encoder = nil
        pool = nil
    }

    /// Ensure an encoder/pool exist for the given dimensions, recreating them on a
    /// size change. Returns false if the encoder cannot be created.
    private func ensureEncoder(width: Int, height: Int) -> Bool {
        if let pool, pool.width == width, pool.height == height, encoder != nil {
            return true
        }
        pool = CompanionPixelBufferPool(width: width, height: height)
        lastSentHash = nil  // a new size invalidates the dedup baseline
        do {
            encoder = try CompanionVideoEncoder(width: width, height: height,
                                                averageBitRate: averageBitRate) { [weak self] frame in
                self?.handleEncoded(frame)
            }
        } catch {
            DLog("Companion streamer: cannot create HEVC encoder: \(error)")
            encoder = nil
            return false
        }
        sentConfigDimensions = nil  // a new size needs a fresh stream config
        return true
    }

    private func handleEncoded(_ frame: CompanionVideoEncoder.EncodedFrame) {
        lock.lock(); defer { lock.unlock() }
        var flags: CompanionMediaFrame.Flags = []
        if frame.isKeyframe { flags.insert(.keyframe) }
        if let parameterSets = frame.parameterSets {
            let dimensions = (pool?.width ?? 0, pool?.height ?? 0)
            if sentConfigDimensions == nil || sentConfigDimensions! != dimensions {
                generationId &+= 1
                sentConfigDimensions = dimensions
                onConfig(CompanionStreamConfig(
                    streamID: streamID,
                    generationId: generationId,
                    codecExtradata: CompanionHEVCFraming.encodeParameterSets(parameterSets),
                    pixelWidth: dimensions.0,
                    pixelHeight: dimensions.1,
                    scale: source.scale,
                    columns: source.columns,
                    rows: source.rows))
                flags.insert(.configChanged)
            }
        }
        let media = CompanionMediaFrame(streamID: streamID,
                                        sequence: sequence,
                                        ptsMilliseconds: frame.ptsMilliseconds,
                                        flags: flags,
                                        payload: frame.accessUnit)
        sequence &+= 1
        onMedia(media)
    }
}
