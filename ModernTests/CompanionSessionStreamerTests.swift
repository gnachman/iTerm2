//
//  CompanionSessionStreamerTests.swift
//  iTerm2 ModernTests
//
//  Integration test for the streamer assembly (pacer + pool + real HEVC encoder):
//  a subscribe produces a keyframe media frame plus a matching stream config; an
//  unchanged tick produces nothing; a later change produces a non-keyframe frame
//  without re-sending the config. Skips where HEVC encode is unavailable.
//

import XCTest
import CoreGraphics
@testable import iTerm2SharedARC

private final class FakeFrameSource: CompanionFrameSource {
    let columns: Int
    let rows: Int
    let scale: Double
    var cellGeometry = CompanionCellGeometry(cellWidth: 8, cellHeight: 16, leftMargin: 0, topMargin: 0)
    var liveTop: Int64 = 0
    var canResize = true
    private let pixelWidth: Int
    private let pixelHeight: Int
    private var image: CGImage

    init(pixelWidth: Int, pixelHeight: Int, columns: Int, rows: Int, scale: Double) {
        self.columns = columns
        self.rows = rows
        self.scale = scale
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.image = Self.makeImage(width: pixelWidth, height: pixelHeight, fill: 0x60)
    }

    /// Change the rendered content so a subsequent frame is not deduped.
    func setFill(_ fill: UInt8) {
        image = Self.makeImage(width: pixelWidth, height: pixelHeight, fill: fill)
    }

    private static func makeImage(width: Int, height: Int, fill: UInt8) -> CGImage {
        let bytes = [UInt8](repeating: fill, count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func renderCurrentScreen() -> CGImage? { image }
}

/// Lock-protected sink, since encoder callbacks fire on a VideoToolbox thread.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var _configs = [CompanionStreamConfig]()
    private var _medias = [CompanionMediaFrame]()
    func addConfig(_ c: CompanionStreamConfig) { lock.lock(); _configs.append(c); lock.unlock() }
    func addMedia(_ m: CompanionMediaFrame) { lock.lock(); _medias.append(m); lock.unlock() }
    var configs: [CompanionStreamConfig] { lock.lock(); defer { lock.unlock() }; return _configs }
    var medias: [CompanionMediaFrame] { lock.lock(); defer { lock.unlock() }; return _medias }
}

final class CompanionSessionStreamerTests: XCTestCase {
    private func skipIfNoEncoder() throws {
        do {
            _ = try CompanionVideoEncoder(width: 320, height: 240) { _ in }
        } catch {
            throw XCTSkip("HEVC encoding unavailable on this machine: \(error)")
        }
    }

    func testSubscribeProducesKeyframeAndConfig() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 7, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)
        streamer.flush()

        XCTAssertEqual(out.configs.count, 1)
        let config = try XCTUnwrap(out.configs.first)
        XCTAssertEqual(config.streamID, 7)
        XCTAssertEqual(config.generationId, 1)
        XCTAssertEqual(config.pixelWidth, 320)
        XCTAssertEqual(config.pixelHeight, 240)
        XCTAssertEqual(config.columns, 80)
        XCTAssertEqual(config.rows, 25)
        XCTAssertEqual(config.scale, 2)
        XCTAssertEqual(config.canResize, true)
        XCTAssertGreaterThanOrEqual(try CompanionHEVCFraming.decodeParameterSets(config.codecExtradata).count, 2)

        XCTAssertEqual(out.medias.count, 1)
        let media = try XCTUnwrap(out.medias.first)
        XCTAssertEqual(media.streamID, 7)
        XCTAssertEqual(media.sequence, 0)
        XCTAssertTrue(media.flags.contains(.keyframe))
        XCTAssertTrue(media.flags.contains(.configChanged))
        XCTAssertGreaterThanOrEqual(try CompanionHEVCFraming.decodeAccessUnit(media.payload).count, 1)
    }

    func testUnchangedTickProducesNothing() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)
        streamer.flush()
        let countAfterFirst = out.medias.count

        // No screen change: a later tick must not emit.
        streamer.tick(nowMilliseconds: 1000)
        streamer.flush()
        XCTAssertEqual(out.medias.count, countAfterFirst)
    }

    func testLaterChangeProducesNonKeyframeWithoutResendingConfig() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // keyframe + config
        streamer.flush()

        source.setFill(0x90)  // actually change the pixels
        streamer.screenDidChange()
        streamer.tick(nowMilliseconds: 1000)  // well past the cap interval
        streamer.flush()

        XCTAssertEqual(out.medias.count, 2)
        XCTAssertEqual(out.configs.count, 1, "config must not be re-sent when geometry is unchanged")
        let second = out.medias[1]
        XCTAssertEqual(second.sequence, 1)
        XCTAssertFalse(second.flags.contains(.keyframe))
        XCTAssertFalse(second.flags.contains(.configChanged))
    }

    func testCanResizeChangeResendsConfigUnderSameGeneration() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // keyframe + config, canResize true
        streamer.flush()
        XCTAssertEqual(out.configs.first?.canResize, true)

        // The window becomes non-resizable (e.g. maximized). Detected when the next
        // frame is captured, which forces a keyframe on the following tick; the config
        // is re-sent with the new flag but under the SAME generation (geometry is
        // unchanged, so the phone must not drop its history tiles).
        source.canResize = false
        source.setFill(0x90)
        streamer.screenDidChange()
        streamer.tick(nowMilliseconds: 1000)  // captures the change, requests a keyframe
        streamer.flush()
        streamer.tick(nowMilliseconds: 2000)  // emits the forced keyframe + resent config
        streamer.flush()

        let last = try XCTUnwrap(out.configs.last)
        XCTAssertEqual(last.canResize, false)
        XCTAssertEqual(last.generationId, 1, "a resizability change must not bump the generation")
    }

    func testCanResizeFlipOnIdleScreenResendsConfig() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // keyframe + config, canResize true
        streamer.flush()
        XCTAssertEqual(out.configs.count, 1)
        XCTAssertEqual(out.configs.first?.canResize, true)

        // Flip resizability with NO pixel change and NO screenDidChange (e.g. toggling
        // the width lock on an idle session). Detection lives in the pre-dedup block,
        // so the change still forces a config resend + keyframe THIS tick, under the
        // same generation, even though nothing on screen moved.
        source.canResize = false
        streamer.tick(nowMilliseconds: 1000)
        streamer.flush()

        XCTAssertEqual(out.configs.count, 2, "an idle-screen resizability flip must still resend the config")
        XCTAssertEqual(out.configs.last?.canResize, false)
        XCTAssertEqual(out.configs.last?.generationId, 1, "a resizability change must not bump the generation")
    }

    func testKeyframeResendReusesGenerationEndToEnd() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // keyframe + config, generation 1
        streamer.flush()

        // A decode-error recovery: request a keyframe with NO geometry change. The
        // config is re-sent (so the phone can reconfigure its decoder) but under the
        // SAME generation, so the phone does not discard its history/selection state.
        streamer.requestKeyframe()
        streamer.tick(nowMilliseconds: 1000)
        streamer.flush()

        XCTAssertEqual(out.configs.count, 2, "a keyframe request must re-send the config")
        XCTAssertEqual(out.configs[0].generationId, 1)
        XCTAssertEqual(out.configs[1].generationId, 1, "a bare resend must not bump the generation")
    }

    func testCellGeometryChangeBumpsGenerationEndToEnd() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // generation 1
        streamer.flush()

        // A font change that keeps the pixel dimensions but changes the cell size:
        // the generation MUST bump so the phone re-lays-out, which is exactly the
        // case whose selection the mac must then re-push.
        source.cellGeometry = CompanionCellGeometry(cellWidth: 9, cellHeight: 18, leftMargin: 5, topMargin: 0)
        streamer.requestKeyframe()
        streamer.tick(nowMilliseconds: 1000)
        streamer.flush()

        XCTAssertEqual(out.configs.count, 2)
        XCTAssertEqual(out.configs[1].generationId, 2, "a cell-geometry change must bump the generation")
    }

    func testUnchangedPixelsAreDeduped() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // keyframe of the initial content
        streamer.flush()
        XCTAssertEqual(out.medias.count, 1)

        // A dirty tick whose rendered pixels are identical (e.g. a cursor-blink
        // repaint) must not emit a frame -- an idle screen costs nothing.
        streamer.screenDidChange()
        streamer.tick(nowMilliseconds: 1000)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 1, "identical pixels must be deduped")

        // A real change does emit.
        source.setFill(0x91)
        streamer.screenDidChange()
        streamer.tick(nowMilliseconds: 2000)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 2)
    }

    func testInsuranceKeyframeAfterActivitySettles() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)        // keyframe
        streamer.flush()

        source.setFill(0x90)
        streamer.screenDidChange()
        streamer.tick(nowMilliseconds: 100)      // P-frame (content change)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 2)
        XCTAssertFalse(out.medias[1].flags.contains(.keyframe))

        // Idle tick past the settle delay: the current screen is re-sent as a
        // keyframe even though nothing changed and it is not deduped.
        streamer.tick(nowMilliseconds: 500)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 3, "insurance keyframe emitted after activity settled")
        XCTAssertTrue(out.medias[2].flags.contains(.keyframe))

        // It happens once: a further idle tick does not keep emitting keyframes.
        streamer.tick(nowMilliseconds: 1000)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 3, "insurance keyframe is sent once, not repeatedly")
    }

    func testUpdateFrameRateCapLowersEmissionRate() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)   // keyframe
        streamer.flush()
        XCTAssertEqual(out.medias.count, 1)

        // The phone lowers the cap to 1 fps on the running stream (e.g. on cellular).
        streamer.updateFrameRateCap(1)

        // A change 100 ms later would emit at the original 30 fps (33 ms interval),
        // but the 1 fps cap now suppresses it -- FPS drops, quality is untouched.
        source.setFill(0x90)
        streamer.screenDidChange()
        streamer.tick(nowMilliseconds: 100)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 1, "the lowered cap must suppress the change")

        // Past the 1 s interval the pending change is emitted as a normal P-frame.
        streamer.tick(nowMilliseconds: 1100)
        streamer.flush()
        XCTAssertEqual(out.medias.count, 2)
        XCTAssertFalse(out.medias[1].flags.contains(.keyframe))
    }

    func testConfigAndFramesCarryGeometry() throws {
        try skipIfNoEncoder()
        let source = FakeFrameSource(pixelWidth: 320, pixelHeight: 240, columns: 80, rows: 25, scale: 2)
        source.cellGeometry = CompanionCellGeometry(cellWidth: 13, cellHeight: 27, leftMargin: 0, topMargin: 0)
        source.liveTop = 4321
        let out = Collector()
        let streamer = CompanionSessionStreamer(streamID: 1, source: source, maxFrameRate: 30,
                                                onConfig: { out.addConfig($0) },
                                                onMedia: { out.addMedia($0) })
        streamer.start()
        streamer.tick(nowMilliseconds: 0)
        streamer.flush()

        // The config carries the cell geometry, and the keyframe carries the
        // generation it was rendered under plus the live top line.
        XCTAssertEqual(out.configs.first?.cellGeometry,
                       CompanionCellGeometry(cellWidth: 13, cellHeight: 27, leftMargin: 0, topMargin: 0))
        let frame = try XCTUnwrap(out.medias.first)
        XCTAssertEqual(frame.liveTop, 4321)
        XCTAssertEqual(frame.generationId, out.configs.first?.generationId)
        XCTAssertGreaterThan(frame.generationId, 0)
    }

    // MARK: Config resend vs generation bump

    private func geometry(columns: Int = 80,
                          cell: CompanionCellGeometry? = CompanionCellGeometry(cellWidth: 8, cellHeight: 16, leftMargin: 10, topMargin: 0))
    -> CompanionSessionStreamer.ConfigGeometry {
        CompanionSessionStreamer.ConfigGeometry(pixelWidth: 800, pixelHeight: 400,
                                                columns: columns, rows: 25, cellGeometry: cell)
    }

    func testFirstConfigSendsAndBumpsGeneration() {
        let d = CompanionSessionStreamer.configResendDecision(sent: nil, current: geometry(),
                                                              mustResend: false, generationId: 0)
        XCTAssertTrue(d.send)
        XCTAssertEqual(d.generationId, 1)
    }

    func testUnchangedGeometryWithoutResendDoesNothing() {
        let g = geometry()
        let d = CompanionSessionStreamer.configResendDecision(sent: g, current: g,
                                                              mustResend: false, generationId: 3)
        XCTAssertFalse(d.send)
        XCTAssertEqual(d.generationId, 3)
    }

    func testKeyframeResendKeepsGeneration() {
        // A decode-error recovery resends the config with unchanged geometry: the
        // phone must reconfigure its decoder WITHOUT a new generation (which would
        // wipe its history-tile cache and selection).
        let g = geometry()
        let d = CompanionSessionStreamer.configResendDecision(sent: g, current: g,
                                                              mustResend: true, generationId: 3)
        XCTAssertTrue(d.send)
        XCTAssertEqual(d.generationId, 3, "a bare resend must not bump the generation")
    }

    func testGeometryChangeBumpsGeneration() {
        let d = CompanionSessionStreamer.configResendDecision(sent: geometry(columns: 80),
                                                              current: geometry(columns: 100),
                                                              mustResend: false, generationId: 3)
        XCTAssertTrue(d.send)
        XCTAssertEqual(d.generationId, 4)
    }

    func testCellGeometryChangeBumpsGenerationEvenWithSamePixels() {
        // A font change can keep the pixel dimensions but change the cell size.
        let a = geometry(cell: CompanionCellGeometry(cellWidth: 8, cellHeight: 16, leftMargin: 10, topMargin: 0))
        let b = geometry(cell: CompanionCellGeometry(cellWidth: 9, cellHeight: 18, leftMargin: 10, topMargin: 0))
        let d = CompanionSessionStreamer.configResendDecision(sent: a, current: b,
                                                              mustResend: false, generationId: 5)
        XCTAssertTrue(d.send)
        XCTAssertEqual(d.generationId, 6)
    }

    func testGeometryChangeWithResendBumpsOnlyOnce() {
        let d = CompanionSessionStreamer.configResendDecision(sent: geometry(columns: 80),
                                                              current: geometry(columns: 100),
                                                              mustResend: true, generationId: 3)
        XCTAssertTrue(d.send)
        XCTAssertEqual(d.generationId, 4)
    }

    // MARK: Resolution-aware bitrate

    func testBitrateScalesWithResolution() {
        // A large window must not get the same bitrate as a small one. Both are
        // below the default ceiling here, so the target is purely pixel-driven.
        let small = CompanionSessionStreamer.targetBitrate(width: 1280, height: 800,
                                                           frameRate: 30, ceiling: 24_000_000)
        let large = CompanionSessionStreamer.targetBitrate(width: 5512, height: 5760,
                                                           frameRate: 30, ceiling: 24_000_000)
        XCTAssertGreaterThan(large, small)
        // Four times the pixels -> four times the target (linear in pixel count).
        // Dimensions chosen so both land between the floor and ceiling.
        let base = CompanionSessionStreamer.targetBitrate(width: 2000, height: 2000,
                                                          frameRate: 30, ceiling: 100_000_000)
        let quad = CompanionSessionStreamer.targetBitrate(width: 4000, height: 4000,
                                                          frameRate: 30, ceiling: 100_000_000)
        XCTAssertEqual(quad, base * 4)
    }

    func testBitrateClampedToFloorAndCeiling() {
        // A tiny window still gets at least the floor.
        let tiny = CompanionSessionStreamer.targetBitrate(width: 64, height: 64,
                                                         frameRate: 30, ceiling: 24_000_000)
        XCTAssertEqual(tiny, CompanionSessionStreamer.minimumBitrate)
        // A huge window is capped at the ceiling, not the raw pixel-driven value.
        let huge = CompanionSessionStreamer.targetBitrate(width: 8000, height: 8000,
                                                        frameRate: 60, ceiling: 24_000_000)
        XCTAssertEqual(huge, 24_000_000)
    }

    func testBitrateMultiplierScalesTargetBeforeClamping() {
        let w = 3000, h = 3000  // large enough that neither result hits the floor
        let base = CompanionSessionStreamer.targetBitrate(width: w, height: h,
                                                          frameRate: 30, ceiling: 100_000_000)
        let doubled = CompanionSessionStreamer.targetBitrate(width: w, height: h,
                                                            frameRate: 30, ceiling: 100_000_000,
                                                            multiplier: 2.0)
        XCTAssertEqual(doubled, base * 2)
        // A non-positive multiplier is ignored (treated as 1), never zeroing the rate.
        let zeroed = CompanionSessionStreamer.targetBitrate(width: w, height: h,
                                                           frameRate: 30, ceiling: 100_000_000,
                                                           multiplier: 0)
        XCTAssertEqual(zeroed, base)
        // The multiplier is still bounded by the ceiling.
        let capped = CompanionSessionStreamer.targetBitrate(width: w, height: h,
                                                          frameRate: 30, ceiling: base,
                                                          multiplier: 10.0)
        XCTAssertEqual(capped, base)
    }

    // MARK: Resolution-aware frame rate

    func testFrameRateHeldForSmallWindowThrottledForLarge() {
        // A small window runs at the full requested rate.
        let small = CompanionSessionStreamer.effectiveFrameRate(width: 1280, height: 800,
                                                               maxFrameRate: 30)
        XCTAssertEqual(small, 30, accuracy: 0.001)
        // A large window is throttled below the requested rate but not below the floor.
        let large = CompanionSessionStreamer.effectiveFrameRate(width: 5512, height: 5760,
                                                               maxFrameRate: 30)
        XCTAssertLessThan(large, 30)
        XCTAssertGreaterThanOrEqual(large, CompanionSessionStreamer.minFrameRate)
    }

    func testThrottlingBoundsBitrateAsResolutionGrows() {
        // The point of throttling: emitting fewer frames of a big window keeps the
        // bitrate far below what the full frame rate would demand, while per-frame
        // sharpness (bitrate / fps) is unchanged.
        let w = 5512, h = 5760
        let fullRate = 30.0
        let throttled = CompanionSessionStreamer.effectiveFrameRate(width: w, height: h,
                                                                    maxFrameRate: fullRate)
        let bitrateFull = CompanionSessionStreamer.targetBitrate(width: w, height: h,
                                                                 frameRate: fullRate, ceiling: 100_000_000)
        let bitrateThrottled = CompanionSessionStreamer.targetBitrate(width: w, height: h,
                                                                      frameRate: throttled, ceiling: 100_000_000)
        XCTAssertLessThan(bitrateThrottled, bitrateFull)
    }

    func testFrameRateFloorNeverExceedsRequestedMax() {
        // A phone that asks for a low rate is not sped up by the floor.
        let fps = CompanionSessionStreamer.effectiveFrameRate(width: 6000, height: 6000,
                                                             maxFrameRate: 5)
        XCTAssertEqual(fps, 5, accuracy: 0.001)
    }
}
