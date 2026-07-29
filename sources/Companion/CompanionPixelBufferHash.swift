//
//  CompanionPixelBufferHash.swift
//  iTerm2
//
//  A fast content hash of a rendered frame, used by the live streamer to skip
//  re-encoding a frame whose pixels are identical to the one already sent. A
//  terminal is static most of the time, and cosmetic repaints (cursor blink,
//  focus changes) drive the render even when nothing visible changed; hashing
//  lets those cost zero bytes so an idle stream stays well under the relay's
//  daily byte budget, regardless of what triggered the redraw.
//
//  The hash covers only the live pixel bytes (excluding any row padding), read
//  as 64-bit words for speed, with a byte tail. It is FNV-1a: not cryptographic,
//  just a cheap change detector.
//

import CoreVideo
import Foundation

enum CompanionPixelBufferHash {
    /// Content hash of a 32-bit (4 bytes/pixel) pixel buffer. Two buffers with
    /// identical visible pixels hash equal; a one-cell change changes the hash.
    static func hash(_ pixelBuffer: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }

        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowBytes = width * 4  // hash visible pixels only, not row padding

        var h: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        // Fold the dimensions in so a resize never collides with old content.
        h = (h ^ UInt64(truncatingIfNeeded: width)) &* prime
        h = (h ^ UInt64(truncatingIfNeeded: height)) &* prime

        let wordCount = rowBytes / 8
        let tailStart = wordCount * 8
        for row in 0..<height {
            let rowBase = base.advanced(by: row * bytesPerRow)
            let words = rowBase.assumingMemoryBound(to: UInt64.self)
            for i in 0..<wordCount {
                h = (h ^ words[i]) &* prime
            }
            let bytes = rowBase.assumingMemoryBound(to: UInt8.self)
            for i in tailStart..<rowBytes {
                h = (h ^ UInt64(bytes[i])) &* prime
            }
        }
        return h
    }
}
