//
//  iTermCacheableImageTests.swift
//  ModernTests
//
//  Characterization tests for iTermCacheableImage, the one-entry cache of a
//  session's custom tab icon. Written against the Objective-C class before
//  its port to Swift and meant to run unchanged against the port: they use
//  only the selector -imageAtPath:ofSize:flipped:, as Swift imports it.
//
//  Every fixture is generated here, in a fresh temporary directory. Nothing
//  depends on the display's scale: sizes are those the cache returns, and
//  colors are sampled after drawing into a bitmap of known size.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermCacheableImageTests: XCTestCase {
    private var directory = ""
    private let iconSize = NSSize(width: 16, height: 16)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func path(_ name: String) -> String {
        return (directory as NSString).appendingPathComponent(name)
    }

    // An opaque PNG whose top half is one color and bottom half another.
    static func pngData(width: Int, height: Int,
                         top: (UInt8, UInt8, UInt8) = (255, 0, 0),
                         bottom: (UInt8, UInt8, UInt8) = (0, 0, 255)) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: width,
                                   pixelsHigh: height,
                                   bitsPerSample: 8,
                                   samplesPerPixel: 4,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4,
                                   bitsPerPixel: 32)!
        let bytes = rep.bitmapData!
        for y in 0..<height {
            let color = y < height / 2 ? top : bottom
            for x in 0..<width {
                let offset = y * width * 4 + x * 4
                bytes[offset] = color.0
                bytes[offset + 1] = color.1
                bytes[offset + 2] = color.2
                bytes[offset + 3] = 255
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }

    @discardableResult
    private func writeImage(_ name: String, width: Int = 16, height: Int = 16) -> String {
        let result = path(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: result,
                                                     contents: Self.pngData(width: width, height: height)))
        return result
    }

    // Draws the image into a bitmap of its own size and reports whether the
    // top and bottom quarters are mostly red or mostly blue.
    private func topAndBottom(of image: NSImage) -> (top: String, bottom: String) {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: width,
                                   pixelsHigh: height,
                                   bitsPerSample: 8,
                                   samplesPerPixel: 4,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        func name(atRow y: Int) -> String {
            let color = rep.colorAt(x: width / 2, y: y)!.usingColorSpace(.deviceRGB)!
            if color.redComponent > 0.5 && color.blueComponent < 0.5 {
                return "red"
            }
            if color.blueComponent > 0.5 && color.redComponent < 0.5 {
                return "blue"
            }
            return "other"
        }
        // colorAt(x:y:) counts rows from the top.
        return (name(atRow: height / 4), name(atRow: height * 3 / 4))
    }

    // MARK: - Hits and misses

    func testSameInputsReturnTheIdenticalImage() {
        let cache = iTermCacheableImage()
        let file = writeImage("a.png")
        let first = cache.image(atPath: file, of: iconSize, flipped: false)
        XCTAssertNotNil(first)
        XCTAssertTrue(cache.image(atPath: file, of: iconSize, flipped: false) === first)
        XCTAssertTrue(cache.image(atPath: file, of: iconSize, flipped: false) === first)
    }

    func testAnEqualButSeparatelyBuiltPathHits() {
        let cache = iTermCacheableImage()
        writeImage("a.png")
        let first = cache.image(atPath: path("a.png"), of: iconSize, flipped: false)
        XCTAssertNotNil(first)
        let rebuilt = String(directory) + "/" + "a" + ".png"
        XCTAssertTrue(cache.image(atPath: rebuilt, of: iconSize, flipped: false) === first)
    }

    func testAnotherPathMissesAndOnlyOneEntryIsKept() {
        let cache = iTermCacheableImage()
        let a = writeImage("a.png")
        let b = writeImage("b.png")
        let first = cache.image(atPath: a, of: iconSize, flipped: false)
        let other = cache.image(atPath: b, of: iconSize, flipped: false)
        XCTAssertNotNil(first)
        XCTAssertNotNil(other)
        XCTAssertTrue(other !== first)
        XCTAssertTrue(cache.image(atPath: a, of: iconSize, flipped: false) !== first)
    }

    func testAnotherSizeMissesAndOnlyOneEntryIsKept() {
        let cache = iTermCacheableImage()
        let a = writeImage("a.png")
        let first = cache.image(atPath: a, of: iconSize, flipped: false)
        let other = cache.image(atPath: a, of: NSSize(width: 20, height: 20), flipped: false)
        XCTAssertNotNil(first)
        XCTAssertNotNil(other)
        XCTAssertTrue(other !== first)
        let again = cache.image(atPath: a, of: iconSize, flipped: false)
        XCTAssertNotNil(again)
        XCTAssertTrue(again !== first)
        XCTAssertTrue(again !== other)
    }

    func testFlippingMissesAndOnlyOneEntryIsKept() {
        let cache = iTermCacheableImage()
        let a = writeImage("a.png")
        let first = cache.image(atPath: a, of: iconSize, flipped: false)
        let other = cache.image(atPath: a, of: iconSize, flipped: true)
        XCTAssertNotNil(first)
        XCTAssertNotNil(other)
        XCTAssertTrue(other !== first)
        let again = cache.image(atPath: a, of: iconSize, flipped: false)
        XCTAssertNotNil(again)
        XCTAssertTrue(again !== first)
        XCTAssertTrue(again !== other)
    }

    // The key is compared literally, UTF-16 unit by unit, as
    // -isEqualToString: does. The file system may open both spellings of a
    // name as one file (APFS looks names up without regard to
    // normalization), but the cache still treats them as different keys.
    func testPrecomposedAndDecomposedSpellingsOfANameMiss() {
        let cache = iTermCacheableImage()
        let precomposed = path("caf\u{E9}.png")
        let decomposed = path("cafe\u{301}.png")
        XCTAssertNotEqual(Array(precomposed.utf16), Array(decomposed.utf16))
        writeImage("caf\u{E9}.png")
        let first = cache.image(atPath: precomposed, of: iconSize, flipped: false)
        XCTAssertNotNil(first)
        let second = cache.image(atPath: decomposed, of: iconSize, flipped: false)
        XCTAssertTrue(second !== first)
        let third = cache.image(atPath: precomposed, of: iconSize, flipped: false)
        XCTAssertNotNil(third)
        XCTAssertTrue(third !== first)
        if second != nil {
            XCTAssertTrue(third !== second)
        }
    }

    // MARK: - Failed loads

    func testNilPathGivesNilAndAGoodPathLoadsAfterIt() {
        let cache = iTermCacheableImage()
        XCTAssertNil(cache.image(atPath: nil, of: iconSize, flipped: false))
        XCTAssertNil(cache.image(atPath: nil, of: iconSize, flipped: false))
        XCTAssertNotNil(cache.image(atPath: writeImage("a.png"), of: iconSize, flipped: false))
    }

    func testAFailedLoadIsNeverAHit() {
        let cache = iTermCacheableImage()
        let file = path("later.png")
        XCTAssertNil(cache.image(atPath: file, of: iconSize, flipped: false))
        writeImage("later.png")
        XCTAssertNotNil(cache.image(atPath: file, of: iconSize, flipped: false))
    }

    func testAFailedLoadReplacesTheEntry() {
        let cache = iTermCacheableImage()
        let a = writeImage("a.png")
        let first = cache.image(atPath: a, of: iconSize, flipped: false)
        XCTAssertNotNil(first)
        XCTAssertNil(cache.image(atPath: path("missing.png"), of: iconSize, flipped: false))
        let again = cache.image(atPath: a, of: iconSize, flipped: false)
        XCTAssertNotNil(again)
        XCTAssertTrue(again !== first)
    }

    func testPathsThatAreNotReadableImagesGiveNil() throws {
        let text = path("text.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: text, contents: Data("hello".utf8)))
        let empty = path("empty.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: empty, contents: Data()))
        let signatureOnly = path("signature.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: signatureOnly,
                                                     contents: Self.pngData(width: 16, height: 16).prefix(8)))
        let folder = path("folder")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)

        for candidate in ["", path("missing.png"), folder, text, empty, signatureOnly] {
            let cache = iTermCacheableImage()
            XCTAssertNil(cache.image(atPath: candidate, of: iconSize, flipped: false), candidate)
            XCTAssertNil(cache.image(atPath: candidate, of: iconSize, flipped: true), candidate)
        }
    }

    // MARK: - Size and flipping

    func testTheNaturalSizeIsKept() throws {
        let cache = iTermCacheableImage()
        let image = try XCTUnwrap(cache.image(atPath: writeImage("a.png"), of: iconSize, flipped: false))
        XCTAssertEqual(image.size, iconSize)
        XCTAssertEqual(topAndBottom(of: image).top, "red")
        XCTAssertEqual(topAndBottom(of: image).bottom, "blue")
    }

    func testAnotherSizeIsProduced() throws {
        let cache = iTermCacheableImage()
        let requested = NSSize(width: 24, height: 10)
        let image = try XCTUnwrap(cache.image(atPath: writeImage("a.png"), of: requested, flipped: false))
        XCTAssertEqual(image.size, requested)
        XCTAssertEqual(topAndBottom(of: image).top, "red")
        XCTAssertEqual(topAndBottom(of: image).bottom, "blue")
    }

    func testFlippingAtTheNaturalSizeSwapsTopAndBottom() throws {
        let cache = iTermCacheableImage()
        let image = try XCTUnwrap(cache.image(atPath: writeImage("a.png"), of: iconSize, flipped: true))
        XCTAssertEqual(image.size, iconSize)
        XCTAssertEqual(topAndBottom(of: image).top, "blue")
        XCTAssertEqual(topAndBottom(of: image).bottom, "red")
    }

    func testFlippingAtAnotherSizeSwapsTopAndBottom() throws {
        let cache = iTermCacheableImage()
        let requested = NSSize(width: 32, height: 32)
        let image = try XCTUnwrap(cache.image(atPath: writeImage("a.png"), of: requested, flipped: true))
        XCTAssertEqual(image.size, requested)
        XCTAssertEqual(topAndBottom(of: image).top, "blue")
        XCTAssertEqual(topAndBottom(of: image).bottom, "red")
    }

    // The app only asks for 16x16; a zero size is a boundary value.
    func testAZeroSizeGivesAnEmptyImage() throws {
        let cache = iTermCacheableImage()
        let image = try XCTUnwrap(cache.image(atPath: writeImage("a.png"), of: .zero, flipped: false))
        XCTAssertEqual(image.size, .zero)
    }
}

// Kept apart from the tests above because creating a PTYSession reaches an
// existing, untriaged nullability violation, so this class cannot run clean
// under the nullability sanitizer while the class above can. The first one
// (nil passed to -screenRestoreState:) was a wrong annotation, fixed on
// 2026-11-21; the next is nil passed to -[NSMutableSet unionSet:] in
// -[iTermGenericEvaluator evaluateSynchronously:sideEffectsAllowed:completion:]
// (see docs/swift-migration/bugs.md).
final class iTermCacheableImageSessionTests: XCTestCase {
    private var directory = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
        try super.tearDownWithError()
    }

    func testASessionWithACustomIconUsesTheCache() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let file = (directory as NSString).appendingPathComponent("icon.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: file,
                                                     contents: iTermCacheableImageTests.pngData(width: 32, height: 32)))
        session.profile = [KEY_ICON: NSNumber(value: iTermProfileIcon.custom.rawValue),
                           KEY_ICON_PATH: file]
        let first = try XCTUnwrap(session.tabGraphic)
        XCTAssertEqual(first.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(session.tabGraphic === first)

        session.profile = [KEY_ICON: NSNumber(value: iTermProfileIcon.custom.rawValue),
                           KEY_ICON_PATH: (directory as NSString).appendingPathComponent("missing.png")]
        XCTAssertNil(session.tabGraphic)
    }
}
