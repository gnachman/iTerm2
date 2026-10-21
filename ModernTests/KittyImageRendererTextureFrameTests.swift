//
//  KittyImageRendererTextureFrameTests.swift
//  iTerm2 ModernTests
//
//  Issue 13146: the Metal renderer sampled the mirrored vertical band of a
//  directly placed Kitty image whose source rectangle was cropped vertically.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyImageRendererTextureFrameTests: XCTestCase {
    private let imageSize = NSSize(width: 40, height: 40)

    // KittyImageController stores a placement's source rectangle in the image's
    // bottom-left-origin space, so a Kitty crop of y=top,h=height in the
    // protocol's top-left-origin space becomes this.
    private func sourceFrame(kittyY: CGFloat, kittyHeight: CGFloat) -> NSRect {
        return NSRect(x: 0, y: kittyY, width: imageSize.width, height: kittyHeight)
            .flipped(in: imageSize.height)
    }

    // The texture frame is in normalized Metal texture coordinates, where v=0 is
    // the image's top row, inverted so that minY is the bottom edge of the band.
    private func assertTextureFrame(_ actual: NSRect,
                                    topV: CGFloat,
                                    bottomV: CGFloat,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        XCTAssertEqual(actual.minX, 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, bottomV, accuracy: 0.0001, "bottom edge", file: file, line: line)
        XCTAssertEqual(actual.origin.y + actual.size.height, topV, accuracy: 0.0001, "top edge", file: file, line: line)
    }

    func testUncroppedSamplesWholeImage() {
        let frame = KittyImageRendererTransientState.textureFrame(
            sourceFrame: NSRect(origin: .zero, size: imageSize),
            imageSize: imageSize)
        assertTextureFrame(frame, topV: 0, bottomV: 1)
    }

    func testTopHalfCropSamplesTopOfTexture() {
        let frame = KittyImageRendererTransientState.textureFrame(
            sourceFrame: sourceFrame(kittyY: 0, kittyHeight: 20),
            imageSize: imageSize)
        assertTextureFrame(frame, topV: 0, bottomV: 0.5)
    }

    func testBottomHalfCropSamplesBottomOfTexture() {
        let frame = KittyImageRendererTransientState.textureFrame(
            sourceFrame: sourceFrame(kittyY: 20, kittyHeight: 20),
            imageSize: imageSize)
        assertTextureFrame(frame, topV: 0.5, bottomV: 1)
    }

    func testSingleRowCropSamplesThatRow() {
        // herdr places a multi-row image one cell row at a time like this.
        let frame = KittyImageRendererTransientState.textureFrame(
            sourceFrame: sourceFrame(kittyY: 10, kittyHeight: 10),
            imageSize: imageSize)
        assertTextureFrame(frame, topV: 0.25, bottomV: 0.5)
    }
}
