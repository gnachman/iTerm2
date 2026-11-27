//
//  iTermCursorBlinkFadeCurveIconTests.swift
//  ModernTests
//
//  Characterization tests for iTermCursorBlinkFadeCurveIcon, which makes the
//  26 by 16 point template images that plot a cursor blink fade curve in the
//  profile settings' fade curve menus. Each image is drawn into an offscreen
//  bitmap of 26 by 16 pixels in sRGB with the Aqua appearance. The tests
//  compare where the stroke lies in each pixel column with the curve that
//  iTermCursorBlinkFadeAnimator computes, and measure the stroke's
//  thickness, with tolerances wide enough for any rasterizer's
//  antialiasing. The curve is stroked in black, so no system color setting
//  changes the pixels. The classes are found by their runtime names and
//  their class methods are sent by selector.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// Class methods of the icon's class and of iTermCursorBlinkFadeAnimator,
// sent by name through AnyObject.
@objc private protocol CurveIconSelectors {
    @objc(imageForCurve:fadeOut:)
    func image(forCurve curve: Int, fadeOut: Bool) -> NSImage

    @objc(easedProgressForCurve:atProgress:)
    func easedProgress(forCurve curve: Int, atProgress t: CGFloat) -> CGFloat
}

final class iTermCursorBlinkFadeCurveIconTests: XCTestCase {
    private let unitClassName = "iTermCursorBlinkFadeCurveIcon"

    // The icon's geometry: its size in points, and the inset of the plot
    // from each edge.
    private let width = 26
    private let height = 16
    private let inset = 2.0
    // The stroke width, in points.
    private let lineWidth = 1.25
    // How far, in pixels, the stroke's measured center in a column may lie
    // from the curve. Antialiasing moves the measured center by at most
    // about 0.07 pixels, and plotting the linear curve in place of any other
    // moves it by up to 3 pixels.
    private let centerTolerance = 0.5
    // How far a column's summed opacity may differ from the stroke width.
    // It measured within 0.01 of 1.25 where the curve is nearly flat; the
    // tolerance still tells 1.25 from 1 and from 1.5.
    private let thicknessTolerance = 0.1

    private var iconClass: AnyClass? {
        return NSClassFromString(unitClassName)
    }

    private func classMethods(_ cls: AnyClass) -> [String: String] {
        guard let metaclass = object_getClass(cls) else {
            return [:]
        }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(metaclass, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    private func image(_ curve: Int, fadeOut: Bool) -> NSImage? {
        guard let cls = iconClass else {
            XCTFail("no class")
            return nil
        }
        return (cls as AnyObject).image?(forCurve: curve, fadeOut: fadeOut)
    }

    // The image drawn into a fresh transparent 26 by 16 pixel sRGB bitmap.
    private func pixels(_ image: NSImage) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: 26,
                                         pixelsHigh: 16,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 26 * 4,
                                         bitsPerPixel: 32)?.retagging(with: .sRGB),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            XCTFail("no bitmap")
            return nil
        }
        rep.size = NSSize(width: 26, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(x: 0, y: 0, width: 26, height: 16),
                       from: .zero,
                       operation: .copy,
                       fraction: 1)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // The RGBA samples of every pixel, row by row from the top.
    private func bytes(_ rep: NSBitmapImageRep) -> [UInt8] {
        var result = [UInt8]()
        var pixel = [Int](repeating: 0, count: 4)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                rep.getPixel(&pixel, atX: x, y: y)
                result.append(contentsOf: pixel.map { UInt8(clamping: $0) })
            }
        }
        return result
    }

    private func drawing(_ curve: Int, fadeOut: Bool) -> [UInt8] {
        guard let image = image(curve, fadeOut: fadeOut), let rep = pixels(image) else {
            return []
        }
        return bytes(rep)
    }

    // The alpha of the pixel in column x and row y, counted from the top.
    private func alpha(_ bytes: [UInt8], _ x: Int, _ y: Int) -> UInt8 {
        return bytes[(y * 26 + x) * 4 + 3]
    }

    func testClassExistsWithItsSuperclass() {
        guard let cls = iconClass else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSObject.self)
    }

    func testSelectorsAndEncodings() {
        guard let cls = iconClass else {
            XCTFail("no class")
            return
        }
        XCTAssertEqual(classMethods(cls)["imageForCurve:fadeOut:"], "@28@0:8q16B24")
    }

    func testImageIsATemplateOfTheIconSize() {
        for curve in 0...3 {
            for fadeOut in [false, true] {
                guard let image = image(curve, fadeOut: fadeOut) else {
                    return
                }
                XCTAssertEqual(image.size, NSSize(width: 26, height: 16))
                XCTAssertTrue(image.isTemplate)
            }
        }
    }

    // The y, in points from the bottom, at which the icon should plot the
    // curve at horizontal position x, in points from the left.
    private func expectedY(_ curve: Int, fadeOut: Bool, x: Double) -> Double? {
        guard let animatorClass = NSClassFromString("iTermCursorBlinkFadeAnimator") else {
            XCTFail("no animator class")
            return nil
        }
        let plotWidth = Double(width) - inset * 2
        let plotHeight = Double(height) - inset * 2
        let t = (x - inset) / plotWidth
        guard let eased = (animatorClass as AnyObject).easedProgress?(forCurve: curve, atProgress: t) else {
            XCTFail("no curve function")
            return nil
        }
        let y = fadeOut ? 1 - eased : eased
        return inset + y * plotHeight
    }

    // The alpha-weighted mean height of the stroke in pixel column x, in
    // points from the bottom, or nil for an empty column.
    private func measuredY(_ pixels: [UInt8], column x: Int) -> Double? {
        var total = 0.0
        var weighted = 0.0
        for row in 0..<height {
            let a = Double(alpha(pixels, x, row))
            total += a
            weighted += a * (Double(height) - (Double(row) + 0.5))
        }
        return total > 0 ? weighted / total : nil
    }

    // The summed opacity of pixel column x, in pixels of full coverage.
    private func coverage(_ pixels: [UInt8], column x: Int) -> Double {
        return (0..<height).reduce(0.0) { $0 + Double(alpha(pixels, x, $1)) / 255 }
    }

    // In every column of the plot, the stroke is centered on the curve,
    // which pins each curve's shape, the fade-out flip and the inset.
    func testStrokeFollowsTheCurveInEveryColumn() {
        for curve in 0...3 {
            for fadeOut in [false, true] {
                let pixels = drawing(curve, fadeOut: fadeOut)
                guard !pixels.isEmpty else {
                    return
                }
                for x in Int(inset)..<(width - Int(inset)) {
                    guard let measured = measuredY(pixels, column: x),
                          let expected = expectedY(curve, fadeOut: fadeOut, x: Double(x) + 0.5) else {
                        XCTFail("curve \(curve) fadeOut \(fadeOut) column \(x) is empty")
                        continue
                    }
                    XCTAssertEqual(measured, expected, accuracy: centerTolerance,
                                   "curve \(curve) fadeOut \(fadeOut) column \(x)")
                }
            }
        }
    }

    // Where the curve is nearly flat, a column's summed opacity is the
    // stroke's width.
    func testStrokeIsOneAndAQuarterPointsThick() {
        // Ease in near its start and ease out near its end have slopes
        // under a tenth of a pixel per pixel there.
        for (curve, column) in [(1, 3), (2, 22)] {
            for fadeOut in [false, true] {
                let pixels = drawing(curve, fadeOut: fadeOut)
                guard !pixels.isEmpty else {
                    return
                }
                XCTAssertEqual(coverage(pixels, column: column), lineWidth, accuracy: thicknessTolerance,
                               "curve \(curve) fadeOut \(fadeOut) column \(column)")
            }
        }
    }

    // Values outside the enumeration plot the linear curve.
    func testUnknownCurvesDrawTheLinearCurve() {
        for fadeOut in [false, true] {
            let linear = drawing(0, fadeOut: fadeOut)
            XCTAssertFalse(linear.isEmpty)
            XCTAssertEqual(drawing(4, fadeOut: fadeOut), linear)
            XCTAssertEqual(drawing(-1, fadeOut: fadeOut), linear)
        }
    }

    // Every pixel is black, at some opacity, and the two-point inset is
    // empty except where the round caps and the line's width reach into it.
    func testOnlyBlackIsDrawnInsideTheInset() {
        for curve in 0...3 {
            for fadeOut in [false, true] {
                let pixels = drawing(curve, fadeOut: fadeOut)
                guard !pixels.isEmpty else {
                    return
                }
                for i in stride(from: 0, to: pixels.count, by: 4) {
                    XCTAssertEqual(pixels[i], 0)
                    XCTAssertEqual(pixels[i + 1], 0)
                    XCTAssertEqual(pixels[i + 2], 0)
                }
                for y in 0..<16 {
                    XCTAssertEqual(alpha(pixels, 0, y), 0, "curve \(curve) fadeOut \(fadeOut) row \(y)")
                    XCTAssertEqual(alpha(pixels, 25, y), 0, "curve \(curve) fadeOut \(fadeOut) row \(y)")
                }
                // The round cap at the start point, at the left inset and
                // 2 points from the bottom (fade in) or the top (fade out),
                // reaches 0.625 points left of the inset into column 1.
                // Counted from the top, that point is on the boundary of
                // rows 13 and 14 for fade in and of rows 1 and 2 for fade
                // out.
                let capRow = fadeOut ? 2 : 13
                XCTAssertGreaterThan(alpha(pixels, 1, capRow), 0, "curve \(curve) fadeOut \(fadeOut)")
            }
        }
    }

    // The fade-in plot rises from the bottom left to the top right, and the
    // fade-out plot falls from the top left to the bottom right. Each is
    // the other's mirror image, to within one level of antialiasing.
    func testFadeOutFlipsThePlotVertically() {
        for curve in 0...3 {
            let fadeIn = drawing(curve, fadeOut: false)
            let fadeOut = drawing(curve, fadeOut: true)
            guard !fadeIn.isEmpty, !fadeOut.isEmpty else {
                return
            }
            // Rows are counted from the top: row 13 is the bottom of the
            // plot and row 2 its top.
            XCTAssertGreaterThan(alpha(fadeIn, 2, 13), 0, "curve \(curve)")
            XCTAssertGreaterThan(alpha(fadeIn, 23, 2), 0, "curve \(curve)")
            XCTAssertGreaterThan(alpha(fadeOut, 2, 2), 0, "curve \(curve)")
            XCTAssertGreaterThan(alpha(fadeOut, 23, 13), 0, "curve \(curve)")
            for y in 0..<16 {
                for x in 0..<26 {
                    let difference = abs(Int(alpha(fadeOut, x, y)) - Int(alpha(fadeIn, x, 15 - y)))
                    XCTAssertLessThanOrEqual(difference, 1, "curve \(curve) x \(x) y \(y)")
                }
            }
        }
    }
}
