//
//  CompanionHEVCSampleBuilderTests.swift
//  iTerm2 ModernTests
//
//  Validates the full encode -> wire -> reconstruct path the iOS app relies on:
//  the encoder's parameter sets rebuild a format description whose dimensions
//  match the source, and the access unit rebuilds a ready, valid CMSampleBuffer
//  tagged for immediate display. Skips where HEVC encode is unavailable.
//

import XCTest
import CoreGraphics
import CoreMedia
@testable import iTerm2SharedARC

final class CompanionHEVCSampleBuilderTests: XCTestCase {
    func testMakeFormatDescriptionRejectsEmptyParameterSets() {
        XCTAssertThrowsError(try CompanionHEVCSampleBuilder.makeFormatDescription(parameterSets: [])) { error in
            XCTAssertEqual(error as? CompanionHEVCSampleBuilder.BuildError, .noParameterSets)
        }
    }

    func testReconstructsFormatAndSampleFromEncoderOutput() throws {
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

        let bytes = [UInt8](repeating: 0x40, count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let pool = CompanionPixelBufferPool(width: width, height: height)
        encoder.encode(try pool.pixelBuffer(from: image), ptsMilliseconds: 0, forceKeyframe: true)
        encoder.finish()

        lock.lock(); let captured = frames; lock.unlock()
        let keyframe = try XCTUnwrap(captured.first { $0.isKeyframe })
        let parameterSets = try XCTUnwrap(keyframe.parameterSets)

        // Parameter sets rebuild a format description matching the source size.
        let format = try CompanionHEVCSampleBuilder.makeFormatDescription(parameterSets: parameterSets)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        XCTAssertEqual(Int(dimensions.width), width)
        XCTAssertEqual(Int(dimensions.height), height)

        // The access unit rebuilds a ready, valid sample buffer with the PTS and
        // the display-immediately attachment.
        let sample = try CompanionHEVCSampleBuilder.makeSampleBuffer(
            accessUnit: keyframe.accessUnit, format: format,
            ptsMilliseconds: 0, displayImmediately: true)
        XCTAssertTrue(CMSampleBufferIsValid(sample))
        XCTAssertTrue(CMSampleBufferDataIsReady(sample))
        XCTAssertEqual(CMSampleBufferGetNumSamples(sample), 1)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).value, 0)

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [[CFString: Any]]
        XCTAssertEqual(attachments?.first?[kCMSampleAttachmentKey_DisplayImmediately] as? Bool, true)
    }

    func testRebuildFromSerializedExtradataRoundTrips() throws {
        // The path the iOS app actually takes: parameter sets arrive serialized in
        // streamConfig.codecExtradata, are decoded, then rebuilt.
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
        let bytes = [UInt8](repeating: 0x40, count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let pool = CompanionPixelBufferPool(width: width, height: height)
        encoder.encode(try pool.pixelBuffer(from: image), ptsMilliseconds: 5, forceKeyframe: true)
        encoder.finish()
        lock.lock(); let captured = frames; lock.unlock()
        let keyframe = try XCTUnwrap(captured.first { $0.isKeyframe })

        let extradata = CompanionHEVCFraming.encodeParameterSets(try XCTUnwrap(keyframe.parameterSets))
        let decoded = try CompanionHEVCFraming.decodeParameterSets(extradata)
        let format = try CompanionHEVCSampleBuilder.makeFormatDescription(parameterSets: decoded)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        XCTAssertEqual(Int(dimensions.width), width)
        XCTAssertEqual(Int(dimensions.height), height)
    }
}
