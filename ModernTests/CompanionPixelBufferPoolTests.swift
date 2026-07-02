//
//  CompanionPixelBufferPoolTests.swift
//  iTerm2 ModernTests
//
//  The pool converts a rendered CGImage into a BGRA pixel buffer for the HEVC
//  encoder. These tests pin the output format, pixel fidelity, top-down
//  orientation (the encoder expects row 0 = top of image), and that a dimension
//  change rebuilds the pool.
//

import XCTest
import CoreGraphics
import CoreVideo
@testable import iTerm2SharedARC

final class CompanionPixelBufferPoolTests: XCTestCase {
    /// Build a top-down RGBA CGImage from explicit per-pixel colors. `rows[0]` is
    /// the top row; each pixel is (r, g, b) with alpha 255.
    private func makeImage(_ rows: [[(UInt8, UInt8, UInt8)]]) -> CGImage {
        let height = rows.count
        let width = rows[0].count
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for row in rows {
            for (r, g, b) in row {
                bytes.append(contentsOf: [r, g, b, 255])  // RGBA, top-down
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// Read a pixel from a 32BGRA buffer as (r, g, b). Memory order is B,G,R,A.
    private func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.advanced(by: y * bpr + x * 4).assumingMemoryBound(to: UInt8.self)
        return (p[2], p[1], p[0])  // R, G, B
    }

    func testOutputDimensionsAndFormat() throws {
        let pool = CompanionPixelBufferPool(width: 4, height: 3)
        let image = makeImage(Array(repeating: Array(repeating: (UInt8(10), UInt8(20), UInt8(30)), count: 4), count: 3))
        let buffer = try pool.pixelBuffer(from: image)
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 4)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 3)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_32BGRA)
    }

    func testSolidColorPixelFidelity() throws {
        let pool = CompanionPixelBufferPool(width: 2, height: 2)
        let red = makeImage(Array(repeating: Array(repeating: (UInt8(255), UInt8(0), UInt8(0)), count: 2), count: 2))
        let buffer = try pool.pixelBuffer(from: red)
        let (r, g, b) = pixel(buffer, x: 1, y: 1)
        XCTAssertEqual(r, 255)
        XCTAssertEqual(g, 0)
        XCTAssertEqual(b, 0)
    }

    func testTopDownOrientation() throws {
        // Top row red, bottom row blue in the source; buffer row 0 must be red.
        let pool = CompanionPixelBufferPool(width: 2, height: 2)
        let image = makeImage([
            [(255, 0, 0), (255, 0, 0)],   // top
            [(0, 0, 255), (0, 0, 255)]    // bottom
        ])
        let buffer = try pool.pixelBuffer(from: image)
        XCTAssertEqual(pixel(buffer, x: 0, y: 0).0, 255, "top row should be red")
        XCTAssertEqual(pixel(buffer, x: 0, y: 0).2, 0, "top row should not be blue")
        XCTAssertEqual(pixel(buffer, x: 0, y: 1).2, 255, "bottom row should be blue")
        XCTAssertEqual(pixel(buffer, x: 0, y: 1).0, 0, "bottom row should not be red")
    }

    func testResizeRebuildsPool() throws {
        let pool = CompanionPixelBufferPool(width: 2, height: 2)
        _ = try pool.pixelBuffer(from: makeImage(Array(repeating: Array(repeating: (UInt8(0), UInt8(0), UInt8(0)), count: 2), count: 2)))
        let bigger = makeImage(Array(repeating: Array(repeating: (UInt8(0), UInt8(0), UInt8(0)), count: 8), count: 6))
        let buffer = try pool.pixelBuffer(from: bigger)
        XCTAssertEqual(pool.width, 8)
        XCTAssertEqual(pool.height, 6)
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 8)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 6)
    }
}
