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
    private let image: CGImage

    init(pixelWidth: Int, pixelHeight: Int, columns: Int, rows: Int, scale: Double) {
        self.columns = columns
        self.rows = rows
        self.scale = scale
        let bytes = [UInt8](repeating: 0x60, count: pixelWidth * pixelHeight * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        self.image = CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                             bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
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
}
