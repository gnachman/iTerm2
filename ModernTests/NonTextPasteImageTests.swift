import AppKit
import XCTest
@testable import iTerm2SharedARC

final class NonTextPasteImageTests: XCTestCase {
    func testTIFFScreenshotBecomesPNGWithoutChangingDimensions() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                   pixelsWide: 3,
                                                   pixelsHigh: 2,
                                                   bitsPerSample: 8,
                                                   samplesPerPixel: 4,
                                                   hasAlpha: true,
                                                   isPlanar: false,
                                                   colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0,
                                                   bitsPerPixel: 0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for x in 0..<3 {
            for y in 0..<2 {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = 255
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        let tiff = try XCTUnwrap(bitmap.representation(using: .tiff, properties: [:]))
        let result = try XCTUnwrap(iTermNonTextPasteHelper.imageForFile(tiff, fileExtension: "tiff"))
        XCTAssertEqual(result.fileExtension, "png")
        XCTAssertEqual(Array(result.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: result.data))
        XCTAssertEqual(decoded.pixelsWide, 3)
        XCTAssertEqual(decoded.pixelsHigh, 2)
        var pixel = [UInt](repeating: 0, count: 4)
        decoded.getPixel(&pixel, atX: 1, y: 1)
        XCTAssertEqual(pixel, [255, 0, 0, 255])
    }

    func testSupportedFormatsPreserveOriginalBytes() throws {
        // Existing compressed images should not be recompressed or lose animation.
        let original = Data([1, 2, 3, 4])
        for ext in ["PNG", "JPEG", "jpg", "gif", "webp"] {
            let result = try XCTUnwrap(iTermNonTextPasteHelper.imageForFile(original, fileExtension: ext))
            XCTAssertEqual(result.data, original)
            XCTAssertEqual(result.fileExtension, ext.lowercased())
        }
    }

    func testInvalidTIFFDoesNotBecomeAnImagePath() {
        XCTAssertNil(iTermNonTextPasteHelper.imageForFile(Data([1, 2, 3]), fileExtension: "tiff"))
    }
}
