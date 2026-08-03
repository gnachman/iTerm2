//
//  CompanionVideoEncoderTests.swift
//  iTerm2 ModernTests
//
//  Smoke test for the streaming HEVC encoder: a real pixel buffer must encode to
//  a keyframe whose parameter sets and access unit parse with the shared framing
//  helpers (the contract the iOS decoder relies on). Skips gracefully if the
//  machine has no HEVC encoder, so it is a capability check, not a flaky test.
//

import XCTest
import CoreGraphics
import CoreVideo
@testable import iTerm2SharedARC

final class CompanionVideoEncoderTests: XCTestCase {
    private func solidImage(width: Int, height: Int) -> CGImage {
        let bytes = [UInt8](repeating: 0x80, count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testEncodesKeyframeWithParseableParameterSetsAndAccessUnit() throws {
        let width = 320, height = 240
        let lock = NSLock()
        var frames = [CompanionVideoEncoder.EncodedFrame]()

        let encoder: CompanionVideoEncoder
        do {
            encoder = try CompanionVideoEncoder(width: width, height: height) { frame in
                lock.lock(); frames.append(frame); lock.unlock()
            }
        } catch {
            throw XCTSkip("HEVC encoding unavailable on this machine: \(error)")
        }

        let pool = CompanionPixelBufferPool(width: width, height: height)
        let pixelBuffer = try pool.pixelBuffer(from: solidImage(width: width, height: height))
        encoder.encode(pixelBuffer, ptsMilliseconds: 0, forceKeyframe: true)
        encoder.finish()  // makes the async encode synchronous for the test

        lock.lock(); let captured = frames; lock.unlock()
        let keyframe = try XCTUnwrap(captured.first { $0.isKeyframe },
                                     "expected at least one keyframe")
        XCTAssertEqual(keyframe.ptsMilliseconds, 0)

        // Parameter sets are present and round-trip through the shared container.
        let params = try XCTUnwrap(keyframe.parameterSets, "keyframe must carry parameter sets")
        XCTAssertGreaterThanOrEqual(params.count, 2, "HEVC keyframe should carry VPS/SPS/PPS")
        let reencoded = CompanionHEVCFraming.encodeParameterSets(params)
        XCTAssertEqual(try CompanionHEVCFraming.decodeParameterSets(reencoded), params)

        // The access unit is valid AVCC with at least one NAL unit.
        let nalUnits = try CompanionHEVCFraming.decodeAccessUnit(keyframe.accessUnit)
        XCTAssertGreaterThanOrEqual(nalUnits.count, 1)
        XCTAssertFalse(nalUnits[0].isEmpty)
    }
}
