//
//  CompanionPixelBufferHashTests.swift
//  iTerm2 ModernTests
//
//  The streamer skips re-encoding a frame whose hash matches the last sent one,
//  so the hash must be stable for identical content and change for any visible
//  difference (including a single pixel).
//

import XCTest
import CoreGraphics
import CoreVideo
@testable import iTerm2SharedARC

final class CompanionPixelBufferHashTests: XCTestCase {
    private func buffer(width: Int, height: Int, fill: UInt8) -> CVPixelBuffer {
        let pool = CompanionPixelBufferPool(width: width, height: height)
        let bytes = [UInt8](repeating: fill, count: width * height * 4)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        // swiftlint:disable:next force_try
        return try! pool.pixelBuffer(from: image)
    }

    func testIdenticalContentHashesEqual() {
        let a = buffer(width: 64, height: 48, fill: 0x33)
        let b = buffer(width: 64, height: 48, fill: 0x33)
        XCTAssertEqual(CompanionPixelBufferHash.hash(a), CompanionPixelBufferHash.hash(b))
    }

    func testDifferentContentHashesDiffer() {
        let a = buffer(width: 64, height: 48, fill: 0x33)
        let b = buffer(width: 64, height: 48, fill: 0x34)
        XCTAssertNotEqual(CompanionPixelBufferHash.hash(a), CompanionPixelBufferHash.hash(b))
    }

    func testStableAcrossRepeatedHashing() {
        let a = buffer(width: 100, height: 30, fill: 0xAB)
        XCTAssertEqual(CompanionPixelBufferHash.hash(a), CompanionPixelBufferHash.hash(a))
    }

    func testSinglePixelChangeChangesHash() throws {
        // Flip one pixel in an otherwise-uniform buffer; the hash must change.
        let width = 40, height = 20
        let base = buffer(width: width, height: height, fill: 0x10)
        let h1 = CompanionPixelBufferHash.hash(base)

        CVPixelBufferLockBaseAddress(base, [])
        let ptr = CVPixelBufferGetBaseAddress(base)!.assumingMemoryBound(to: UInt8.self)
        // Change a pixel near the end (exercises the row/word path).
        ptr[(height - 1) * CVPixelBufferGetBytesPerRow(base) + (width - 1) * 4] ^= 0xFF
        CVPixelBufferUnlockBaseAddress(base, [])

        XCTAssertNotEqual(h1, CompanionPixelBufferHash.hash(base))
    }

    func testDimensionsAffectHash() {
        // Same fill, different size: must not collide.
        let a = buffer(width: 64, height: 48, fill: 0x00)
        let b = buffer(width: 48, height: 64, fill: 0x00)
        XCTAssertNotEqual(CompanionPixelBufferHash.hash(a), CompanionPixelBufferHash.hash(b))
    }
}
