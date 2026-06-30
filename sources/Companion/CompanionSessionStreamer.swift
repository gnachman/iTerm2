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
import CoreText
import CoreVideo
import Foundation
import QuartzCore

/// The session-side inputs the streamer needs: the geometry of the rendered
/// frame and a way to render the current visible screen.
protocol CompanionFrameSource: AnyObject {
    var columns: Int { get }
    var rows: Int { get }
    /// Encoded pixels per Mac point (the render scale).
    var scale: Double { get }
    /// Cell/margin geometry (in encoded pixels) for touch-to-cell mapping. Read on
    /// the main thread alongside a render; stable except across resize/font/scale.
    var cellGeometry: CompanionCellGeometry { get }
    /// Absolute line number of the top visible row right now (overflow-adjusted).
    /// Changes whenever the screen scrolls, so it is captured per frame.
    var liveTop: Int64 { get }
    /// Oldest available absolute line (== total scrollback overflow) and the total
    /// available lines, so the phone can lay out the history canvas. Captured at
    /// config time.
    var firstAbsLine: Int64 { get }
    var totalLines: Int { get }
    /// Render the current visible screen, or nil if it cannot be produced now.
    /// The encoder and pool size themselves to the returned image's dimensions.
    func renderCurrentScreen() -> CGImage?
}

extension CompanionFrameSource {
    // Defaults so test fakes need not supply history extent.
    var firstAbsLine: Int64 { 0 }
    var totalLines: Int { 0 }
}

final class CompanionSessionStreamer: @unchecked Sendable {
    let streamID: UInt32

    private let source: CompanionFrameSource
    private let averageBitRate: Int
    private let onConfig: (CompanionStreamConfig) -> Void
    private let onMedia: (CompanionMediaFrame) -> Void
    /// Called on the main thread when the rolling byte budget is used up, so the
    /// owner can pause the stream (end it with .dataLimitReached) before the
    /// relay force-closes the connection for exceeding its room quota.
    private let onDataLimitReached: () -> Void

    private let lock = NSLock()
    private var budget: CompanionStreamBudget
    private var dataLimitHit = false
    private var inFlight: CompanionInFlightLimiter
    private var pacer: CompanionStreamPacer
    private var pool: CompanionPixelBufferPool?
    private var encoder: CompanionVideoEncoder?
    /// Monotonic number stamped into each emitted frame's pixels (CDIAG) and used
    /// as that frame's media sequence, so a screen recording's visible number
    /// matches the logs. Set in tick(), read in handleEncoded.
    private var frameNumber: UInt32 = 0
    private var pendingFrameNumber: UInt32 = 0
    private var generationId: UInt32 = 0
    private var sentConfigDimensions: (Int, Int)?
    /// Content hash of the last frame handed to the encoder. A frame whose pixels
    /// match it is skipped (the phone already shows it), so a static screen costs
    /// nothing even though cosmetic repaints keep driving tick(). Cleared on a
    /// resize so the first frame at a new size always encodes.
    private var lastSentHash: UInt64?
    /// Geometry captured on the main thread at render time, applied to the config
    /// and media frame built later on the encoder thread. cellGeometry changes only
    /// on resize; liveTop changes per frame.
    private var lastCellGeometry: CompanionCellGeometry?
    private var lastRenderedLiveTop: Int64 = 0
    /// When the last frame was emitted and whether it was a keyframe, to drive the
    /// insurance keyframe (below).
    private var lastEmitAt: TimeInterval = 0
    private var lastEmitWasKeyframe = false
    /// After activity settles, re-send the current screen as a self-contained
    /// keyframe. The stream is change-driven P-frames, so if any frame is dropped
    /// (in transport, or at the phone's display decoder) the shown frame stays
    /// stale until the next frame -- which, once idle, never comes, so the screen
    /// looks frozen until the user nudges it. A keyframe shortly after the last
    /// change is decodable on its own and corrects any such drift.
    private let insuranceKeyframeDelay: TimeInterval = 0.3

    // CDIAG flow-control stats, logged once a second while streaming. Counters are
    // for the current one-second bucket; reset on each log. Touched from tick()
    // (main) and handleEncoded (encoder thread), so guarded by `lock`.
    private var statLastLog: TimeInterval = 0
    private var statEmitted = 0
    private var statDeduped = 0
    private var statPaced = 0
    private var statBytes = 0

    init(streamID: UInt32,
         source: CompanionFrameSource,
         maxFrameRate: Double = 30,
         averageBitRate: Int = 1_000_000,
         dailyByteBudget: Int = 400 * 1024 * 1024,
         onConfig: @escaping (CompanionStreamConfig) -> Void,
         onMedia: @escaping (CompanionMediaFrame) -> Void,
         onDataLimitReached: @escaping () -> Void = {}) {
        self.streamID = streamID
        self.source = source
        self.averageBitRate = averageBitRate
        self.onConfig = onConfig
        self.onMedia = onMedia
        self.onDataLimitReached = onDataLimitReached
        self.budget = CompanionStreamBudget(limitBytes: dailyByteBudget)
        self.inFlight = CompanionInFlightLimiter()
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
        let nowSeconds = TimeInterval(nowMilliseconds) / 1000.0
        lock.lock()
        let exhausted = budget.isExhausted(now: nowSeconds)
        // A pending keyframe (subscribe/resume) must go even if the receiver is
        // behind; otherwise the limiter coalesces to the latest screen. Checking
        // before evaluate() avoids consuming the dirty flag when we skip.
        let blocked = !exhausted && !pacer.isKeyframeRequested && !inFlight.mayEmit()
        var decision = (exhausted || blocked) ? nil : pacer.evaluate(now: nowSeconds)
        // Nothing to send, but the last frame was a P-frame and activity has been
        // quiet a moment: re-send the current screen as a keyframe so a dropped
        // P-frame cannot leave the phone showing a stale frame indefinitely.
        if decision == nil && !exhausted && !blocked
            && lastEmitAt > 0 && !lastEmitWasKeyframe
            && nowSeconds - lastEmitAt >= insuranceKeyframeDelay {
            pacer.requestKeyframe()
            decision = pacer.evaluate(now: nowSeconds)
        }
        if blocked { statPaced += 1 }
        let statsLine = takeFlowStatsLine(now: nowSeconds)
        lock.unlock()
        if let statsLine { RLog(statsLine) }
        if exhausted {
            // Pause before the relay force-closes us for exceeding its quota.
            if !dataLimitHit {
                dataLimitHit = true
                onDataLimitReached()
            }
            return
        }
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
            lock.lock(); statDeduped += 1; lock.unlock()
            return
        }
        lastSentHash = hash
        // Capture geometry on this (main) thread; handleEncoded stamps it onto the
        // config/media frame from the encoder thread.
        let cellGeometry = source.cellGeometry
        let liveTop = source.liveTop
        let thisFrame = frameNumber
        frameNumber &+= 1
        // Optionally burn the frame number into the pixels (after the dedup hash,
        // so it does not defeat dedup) so a screen recording shows which frame is
        // visible. Behind an advanced setting; off by default.
        if iTermAdvancedSettingsModel.companionStreamFrameNumbers() {
            stampFrameNumber(thisFrame, into: pixelBuffer)
        }
        lock.lock()
        inFlight.noteSent(ptsMilliseconds: nowMilliseconds)
        statEmitted += 1
        lastCellGeometry = cellGeometry
        lastRenderedLiveTop = liveTop
        lastEmitAt = nowSeconds
        lastEmitWasKeyframe = decision.keyframe
        pendingFrameNumber = thisFrame
        lock.unlock()
        encoder.encode(pixelBuffer, ptsMilliseconds: nowMilliseconds, forceKeyframe: decision.keyframe)
    }

    /// If at least a second has elapsed, return the flow-control stats line for
    /// the bucket and reset it; otherwise nil. Must be called with `lock` held.
    private func takeFlowStatsLine(now: TimeInterval) -> String? {
        if statLastLog == 0 { statLastLog = now }
        guard now - statLastLog >= 1 else { return nil }
        let usedMB = (budget.limitBytes - budget.remaining(now: now)) / (1024 * 1024)
        let limitMB = budget.limitBytes / (1024 * 1024)
        let line = "CDIAG flow stream=\(streamID) emitted=\(statEmitted) deduped=\(statDeduped) "
            + "paced=\(statPaced) bytes=\(statBytes) lead=\(inFlight.leadMilliseconds)ms "
            + "queue=\(inFlight.queueDepth) budgetUsed=\(usedMB)MB/\(limitMB)MB"
        statEmitted = 0
        statDeduped = 0
        statPaced = 0
        statBytes = 0
        statLastLog = now
        return line
    }

    /// Apply a streamAck from the phone so the limiter can pace against how far
    /// behind the receiver is. Safe to call from any thread.
    func noteAck(ptsMilliseconds: UInt64, queueDepth: Int) {
        lock.lock(); inFlight.noteAck(ptsMilliseconds: ptsMilliseconds, queueDepth: queueDepth); lock.unlock()
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
                    rows: source.rows,
                    cellGeometry: lastCellGeometry,
                    firstAbsLine: source.firstAbsLine,
                    totalLines: source.totalLines))
                flags.insert(.configChanged)
            }
        }
        let media = CompanionMediaFrame(streamID: streamID,
                                        sequence: pendingFrameNumber,
                                        ptsMilliseconds: frame.ptsMilliseconds,
                                        flags: flags,
                                        payload: frame.accessUnit,
                                        generationId: generationId,
                                        liveTop: lastRenderedLiveTop)
        // Charge the rolling budget; tick() pauses the stream once it is spent.
        budget.record(bytes: media.payload.count, now: CACurrentMediaTime())
        statBytes += media.payload.count
        onMedia(media)
    }

    // MARK: CDIAG frame-number overlay

    /// Burn "#N" into the top-left of the BGRA pixel buffer. Uses the same
    /// no-flip BGRA context CompanionPixelBufferPool uses to draw the frame (so a
    /// drawn CGImage lands upright), compositing a pre-rendered label image.
    private func stampFrameNumber(_ number: UInt32, into pixelBuffer: CVPixelBuffer) {
        guard let label = labelImage(for: number) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: base,
                                  width: CVPixelBufferGetWidth(pixelBuffer),
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo) else {
            return
        }
        // High y = top of the (upright) frame in this context, matching the pool.
        ctx.draw(label, in: CGRect(x: 4, y: height - label.height - 4,
                                   width: label.width, height: label.height))
    }

    /// A small green-on-translucent-black "#N" image, drawn in a standard
    /// bottom-left CG context (CTLine draws upright), so compositing it upright.
    private func labelImage(for number: UInt32) -> CGImage? {
        let width = 640, height = 160
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 104, nil)
        let attrs = [kCTFontAttributeName: font,
                     kCTForegroundColorAttributeName: CGColor(red: 0, green: 1, blue: 0, alpha: 1)] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, "#\(number)" as CFString, attrs) else { return nil }
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: 24, y: 36)
        CTLineDraw(line, ctx)
        return ctx.makeImage()
    }
}
