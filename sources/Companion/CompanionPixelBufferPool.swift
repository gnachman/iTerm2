//
//  CompanionPixelBufferPool.swift
//  iTerm2
//
//  Converts a rendered terminal frame (a CGImage from PTYTextView's offscreen
//  CoreGraphics render path) into a BGRA CVPixelBuffer to feed the VideoToolbox
//  HEVC encoder. A pool recycles buffers so steady-state streaming does not
//  allocate per frame; the pool is rebuilt when the frame dimensions change (a
//  resize). Buffers are IOSurface-backed so the encoder can take them without a
//  CPU copy.
//
//  Orientation: the output buffer's row 0 is the top of the source image (the
//  standard top-down layout video encoders expect), achieved by flipping the
//  drawing context, since a CGBitmapContext's native origin is bottom-left.
//

import CoreGraphics
import CoreVideo
import Foundation

final class CompanionPixelBufferPool {
    private(set) var width: Int
    private(set) var height: Int
    private var pool: CVPixelBufferPool?

    enum PoolError: Error, Equatable {
        case invalidDimensions
        case poolCreationFailed
        case bufferCreationFailed
        case contextCreationFailed
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Draw `image` into a recycled BGRA pixel buffer. Rebuilds the pool first if
    /// `image`'s dimensions differ from the current size.
    func pixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        if pool == nil || image.width != width || image.height != height {
            width = image.width
            height = image.height
            try rebuildPool()
        }
        guard let pool else { throw PoolError.poolCreationFailed }

        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess,
              let buffer = created else {
            throw PoolError.bufferCreationFailed
        }
        try draw(image, into: buffer)
        return buffer
    }

    private func rebuildPool() throws {
        guard width > 0, height > 0 else { throw PoolError.invalidDimensions }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            // IOSurface-backed buffers can be encoded without a CPU round-trip.
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var created: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created) == kCVReturnSuccess,
              let pool = created else {
            throw PoolError.poolCreationFailed
        }
        self.pool = pool
    }

    private func draw(_ image: CGImage, into buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw PoolError.contextCreationFailed
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue  // 32BGRA
        guard let context = CGContext(data: base,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else {
            throw PoolError.contextCreationFailed
        }
        // A bitmap context over this buffer already has memory row 0 at the top,
        // so drawing without a flip lands the image's top row in buffer row 0
        // (the top-down layout the encoder expects).
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.clear(rect)
        context.draw(image, in: rect)
    }
}
