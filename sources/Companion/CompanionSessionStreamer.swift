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

    /// The config fields that define a generation: a change to any of them means the
    /// phone must re-render / re-lay-out (and drop cached history tiles). Notably
    /// firstAbsLine/totalLines/liveTop are NOT here (they move constantly and are
    /// carried out-of-band), so a routine config resend with unchanged geometry does
    /// not bump the generation.
    struct ConfigGeometry: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        var columns: Int
        var rows: Int
        var cellGeometry: CompanionCellGeometry?
    }

    struct ConfigResendDecision: Equatable {
        var send: Bool
        var generationId: UInt32
    }

    /// Decide whether to (re)send the stream config and what generation to stamp on
    /// it. The generation is bumped only when the geometry actually changed; a forced
    /// resend with unchanged geometry keeps the current generation.
    static func configResendDecision(sent: ConfigGeometry?,
                                     current: ConfigGeometry,
                                     mustResend: Bool,
                                     generationId: UInt32) -> ConfigResendDecision {
        let changed = (sent != current)
        guard changed || mustResend else {
            return ConfigResendDecision(send: false, generationId: generationId)
        }
        return ConfigResendDecision(send: true,
                                    generationId: changed ? generationId &+ 1 : generationId)
    }

    private let source: CompanionFrameSource
    /// The requested frame-rate cap. Mutable: the phone can retune it live via
    /// updateStreamParams (the one quality-preserving adaptation lever for a
    /// terminal). Guarded by `lock`.
    private var maxFrameRate: Double
    private let bitrateCeiling: Int
    private let onConfig: (CompanionStreamConfig) -> Void
    private let onMedia: (CompanionMediaFrame) -> Void
    /// Called on the main thread when the history window changes by trim/clear
    /// (firstAbsLine advances or totalLines drops): (firstAbsLine, totalLines).
    private let onExtentChanged: (Int64, Int) -> Void
    private var lastSeenFirstAbsLine: Int64 = -1
    private var lastSeenTotalLines = -1
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
    /// Monotonic number stamped into each emitted frame's pixels and used
    /// as that frame's media sequence, so a screen recording's visible number
    /// matches the logs. Set in tick(), read in handleEncoded.
    private var frameNumber: UInt32 = 0
    private var pendingFrameNumber: UInt32 = 0
    private var generationId: UInt32 = 0
    /// The geometry of the last config sent to the phone. generationId is bumped
    /// only when this actually changes; a bare resend (e.g. decode-error recovery)
    /// keeps the generation so the phone reconfigures its decoder without treating
    /// it as a new generation (which would wipe its history-tile cache and
    /// selection).
    private var sentConfigGeometry: ConfigGeometry?
    /// Set when the config must be re-sent on the next keyframe even though the
    /// geometry is unchanged (a phone keyframe request, or a fresh encoder whose
    /// parameter sets the phone has not seen).
    private var mustResendConfig = false
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
    /// Config geometry captured on the main thread at render time and applied to the
    /// stream config from the encoder callback thread. The frame source is
    /// main-thread-only (it dereferences PTYSession/VT100Screen/window), so reading
    /// these off the VideoToolbox thread in handleEncoded races resize/output/trim
    /// and can tear the config (columns/rows out of sync with the encoded pixels).
    private var lastScale: Double = 2
    private var lastColumns = 0
    private var lastRows = 0
    private var lastFirstAbsLine: Int64 = 0
    private var lastTotalLines = 0
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

    // Flow-control stats, logged once a second while streaming. Counters are
    // for the current one-second bucket; reset on each log. Touched from tick()
    // (main) and handleEncoded (encoder thread), so guarded by `lock`.
    private var statLastLog: TimeInterval = 0
    private var statEmitted = 0
    private var statDeduped = 0
    private var statPaced = 0
    private var statBytes = 0

    /// Bits allotted per pixel per frame for the encoder's average-bitrate target.
    /// Screen content is mostly static text and the stream is change-driven and
    /// deduped, so this governs per-frame quality (how hard the rate control
    /// compresses a frame it does encode) far more than steady-state bandwidth.
    /// Kept small so a small window stays a few Mbps while a Retina 5K window lands
    /// around 20 Mbps rather than the crushed, fixed 1 Mbps that made large windows
    /// look blurry.
    static let bitsPerPixelPerFrame = 0.02

    /// Floor so a tiny window still gets a usable bitrate.
    static let minimumBitrate = 1_000_000
    /// Ceiling used when the phone does not request a maximum. Generous so a large
    /// Retina window is not starved; the phone can lower it via maxBitrate.
    static let defaultBitrateCeiling = 24_000_000

    /// Peak pixels-per-second the feed targets. Since per-frame sharpness is
    /// `bitsPerPixelPerFrame` regardless of rate, total bandwidth is
    /// pixels x fps x bitsPerPixelPerFrame; holding pixels x fps at this budget
    /// keeps Mbps bounded as the window grows. 180 Mpx/s lets a ~6 Mpx fullscreen
    /// Retina laptop hold the full requested rate; bigger windows are throttled.
    static let maxPixelsPerSecond = 180_000_000.0
    /// Frame-rate floor so even a very large window stays watchable/interactive
    /// rather than being throttled toward zero.
    static let minFrameRate = 10.0

    /// The frame rate to actually emit at for a frame of the given pixel count:
    /// `maxFrameRate` for small windows, throttled toward `minFrameRate` for large
    /// ones so pixels x fps stays near `maxPixelsPerSecond`. A low requested max is
    /// respected (the floor never raises the rate above what the phone asked for).
    static func effectiveFrameRate(width: Int, height: Int, maxFrameRate: Double) -> Double {
        let pixels = Double(width * height)
        guard pixels > 0, maxFrameRate > 0 else { return maxFrameRate }
        let throttled = maxPixelsPerSecond / pixels
        let floor = min(minFrameRate, maxFrameRate)
        return max(floor, min(maxFrameRate, throttled))
    }

    /// Encoder average bitrate scaled to the frame's pixel count and (effective)
    /// frame rate, clamped to [minimumBitrate, ceiling]. Recomputed whenever the
    /// encoder is (re)built for a new size, so the feed's quality tracks the window
    /// instead of being pinned to a fixed rate that collapses as the window grows.
    /// `multiplier` is the user's advanced-setting quality knob (1 = default); it
    /// scales the pixel-derived rate before clamping.
    static func targetBitrate(width: Int, height: Int, frameRate: Double, ceiling: Int,
                              multiplier: Double = 1.0) -> Int {
        let raw = Double(width * height) * bitsPerPixelPerFrame * max(1, frameRate)
        let scaled = raw * (multiplier > 0 ? multiplier : 1.0)
        return max(minimumBitrate, min(ceiling, Int(scaled)))
    }

    init(streamID: UInt32,
         source: CompanionFrameSource,
         maxFrameRate: Double = 30,
         bitrateCeiling: Int = CompanionSessionStreamer.defaultBitrateCeiling,
         dailyByteBudget: Int = 400 * 1024 * 1024,
         onConfig: @escaping (CompanionStreamConfig) -> Void,
         onMedia: @escaping (CompanionMediaFrame) -> Void,
         onExtentChanged: @escaping (Int64, Int) -> Void = { _, _ in },
         onDataLimitReached: @escaping () -> Void = {}) {
        self.streamID = streamID
        self.source = source
        self.maxFrameRate = maxFrameRate > 0 ? maxFrameRate : 30
        self.bitrateCeiling = bitrateCeiling
        self.onConfig = onConfig
        self.onMedia = onMedia
        self.onExtentChanged = onExtentChanged
        self.onDataLimitReached = onDataLimitReached
        self.budget = CompanionStreamBudget(limitBytes: dailyByteBudget)
        // The in-flight limiter's back-off thresholds are user-tunable (advanced
        // settings); they are read once per stream, so a change applies to new streams.
        self.inFlight = CompanionInFlightLimiter(
            maxLeadMilliseconds: UInt64(max(0, Int(iTermAdvancedSettingsModel.companionStreamMaxLeadMilliseconds()))),
            maxQueueDepth: max(0, Int(iTermAdvancedSettingsModel.companionStreamMaxQueueDepth())))
        self.pacer = CompanionStreamPacer(minInterval: maxFrameRate > 0 ? 1.0 / maxFrameRate : 0)
    }

    /// The generation stamped on the most recent config. Bumped only on a real
    /// geometry change; the owner watches this to re-push state (e.g. the selection)
    /// that the phone discards when the generation advances.
    var currentGenerationId: UInt32 {
        lock.lock(); defer { lock.unlock() }
        return generationId
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
    /// Also force the next keyframe to re-send the stream config: the phone requests
    /// a keyframe precisely when it has no usable config (dropped in a race with
    /// activeStreamID, or undecodable), and without this the config would only be
    /// re-sent on a geometry change. The resend keeps the current generation (the
    /// geometry has not changed) so the phone reconfigures its decoder without
    /// wiping its history-tile cache and selection.
    func requestKeyframe() {
        lock.lock()
        pacer.requestKeyframe()
        mustResendConfig = true
        lock.unlock()
    }

    /// Evaluate the pacer at `nowMilliseconds` and, if it says to emit, render and
    /// encode a frame. Call on the main thread.
    func tick(nowMilliseconds: UInt64) {
        let nowSeconds = TimeInterval(nowMilliseconds) / 1000.0
        // Fire extent changes every tick, before any emit guard: a trim or clear
        // changes firstAbsLine/totalLines WITHOUT changing pixels, so it must not
        // depend on a frame being emitted (the pacer/dedup guards below would
        // otherwise return first and the phone would keep stale history forever).
        // Two integer reads on this (main) thread; growth rides liveTop, so only a
        // firstAbsLine advance or a totalLines drop needs an event.
        let currentFirstAbs = source.firstAbsLine
        let currentTotal = source.totalLines
        if currentFirstAbs != lastSeenFirstAbsLine || currentTotal < lastSeenTotalLines {
            onExtentChanged(currentFirstAbs, currentTotal)
        }
        lastSeenFirstAbsLine = currentFirstAbs
        lastSeenTotalLines = currentTotal
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
        // Capture ALL geometry on this (main) thread; handleEncoded stamps it onto
        // the config/media frame from the encoder callback thread, which must never
        // touch the main-thread-only frame source.
        let cellGeometry = source.cellGeometry
        let liveTop = source.liveTop
        let scale = source.scale
        let columns = source.columns
        let rows = source.rows
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
        lastScale = scale
        lastColumns = columns
        lastRows = rows
        lastFirstAbsLine = currentFirstAbs
        lastTotalLines = currentTotal
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
        let line = "flow stream=\(streamID) emitted=\(statEmitted) deduped=\(statDeduped) "
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

    /// Retune the frame-rate cap on a running stream (from the phone's
    /// updateStreamParams). This is the ONLY live adaptation lever for a terminal:
    /// per-frame quality (bits per pixel) is left untouched so text stays legible,
    /// and only how often frames are emitted changes. The effective rate is still
    /// clamped by the current resolution's throttle, so a big window is not sped up
    /// past what its bandwidth allows. No encoder rebuild: the pacer just recoalesces
    /// to the new interval. A value <= 0 restores the 30 fps default.
    func updateFrameRateCap(_ requestedMaxFrameRate: Double) {
        lock.lock()
        let newMax = requestedMaxFrameRate > 0 ? requestedMaxFrameRate : 30
        maxFrameRate = newMax
        let width = pool?.width ?? 0
        let height = pool?.height ?? 0
        let effective = width > 0 && height > 0
            ? Self.effectiveFrameRate(width: width, height: height, maxFrameRate: newMax)
            : newMax
        pacer.setMinInterval(effective > 0 ? 1.0 / effective : 0)
        lock.unlock()
        RLog("stream \(streamID) updateFrameRateCap max=\(newMax) effective=\(effective)")
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
        // pool/encoder are read in handleEncoded (on the encoder callback thread)
        // under lock, so read and write them here under lock too. Build the new
        // encoder outside the lock (its creation is slow and can fail) and swap it in
        // atomically.
        lock.lock()
        let reuse = pool?.width == width && pool?.height == height && encoder != nil
        let currentMaxFrameRate = maxFrameRate
        lock.unlock()
        if reuse { return true }

        let newPool = CompanionPixelBufferPool(width: width, height: height)
        // Throttle the frame rate for large frames first, then size the bitrate to
        // that effective rate: a big window emits fewer frames of the same per-frame
        // sharpness rather than the same frame count at a ballooning bitrate.
        let frameRate = Self.effectiveFrameRate(width: width, height: height,
                                                maxFrameRate: currentMaxFrameRate)
        let bitRate = Self.targetBitrate(width: width, height: height,
                                         frameRate: frameRate, ceiling: bitrateCeiling,
                                         multiplier: iTermAdvancedSettingsModel.companionStreamBitrateMultiplier())
        let newEncoder: CompanionVideoEncoder
        do {
            newEncoder = try CompanionVideoEncoder(width: width, height: height,
                                                   averageBitRate: bitRate) { [weak self] frame in
                self?.handleEncoded(frame)
            }
        } catch {
            DLog("Companion streamer: cannot create HEVC encoder: \(error)")
            return false
        }
        RLog("stream \(streamID) encoder \(width)x\(height) fps=\(frameRate) bitrate=\(bitRate) (ceiling=\(bitrateCeiling))")
        lock.lock()
        pool = newPool
        encoder = newEncoder
        // The change-driven Timer still ticks at the requested max, but the pacer
        // now coalesces emission down to the resolution-throttled effective rate.
        pacer.setMinInterval(frameRate > 0 ? 1.0 / frameRate : 0)
        lastSentHash = nil  // a new size invalidates the dedup baseline
        // A fresh encoder has fresh parameter sets the phone has not seen, so force a
        // config resend. The geometry comparison bumps the generation if the pixel
        // dimensions actually changed.
        mustResendConfig = true
        lock.unlock()
        return true
    }

    private func handleEncoded(_ frame: CompanionVideoEncoder.EncodedFrame) {
        lock.lock(); defer { lock.unlock() }
        var flags: CompanionMediaFrame.Flags = []
        if frame.isKeyframe { flags.insert(.keyframe) }
        if let parameterSets = frame.parameterSets {
            let geometry = ConfigGeometry(pixelWidth: pool?.width ?? 0,
                                          pixelHeight: pool?.height ?? 0,
                                          columns: lastColumns,
                                          rows: lastRows,
                                          cellGeometry: lastCellGeometry)
            let decision = Self.configResendDecision(sent: sentConfigGeometry,
                                                     current: geometry,
                                                     mustResend: mustResendConfig,
                                                     generationId: generationId)
            if decision.send {
                generationId = decision.generationId
                sentConfigGeometry = geometry
                mustResendConfig = false
                onConfig(CompanionStreamConfig(
                    streamID: streamID,
                    generationId: generationId,
                    codecExtradata: CompanionHEVCFraming.encodeParameterSets(parameterSets),
                    pixelWidth: geometry.pixelWidth,
                    pixelHeight: geometry.pixelHeight,
                    scale: lastScale,
                    columns: lastColumns,
                    rows: lastRows,
                    cellGeometry: lastCellGeometry,
                    firstAbsLine: lastFirstAbsLine,
                    totalLines: lastTotalLines))
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

    // MARK: Frame-number overlay

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
