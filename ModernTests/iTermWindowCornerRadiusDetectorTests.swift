//
//  iTermWindowCornerRadiusDetectorTests.swift
//  ModernTests
//
//  Verifies that window corner radius detection works at any window opacity
//  (regression test for the heavy border clipping its corners on low-opacity
//  windows) and that the per-OS fallback radius is sane.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermWindowCornerRadiusDetectorTests: XCTestCase {

    // MARK: - Synthetic corner builder

    /// Build a premultiplied-RGBA crop whose origin (0, 0) is a window's
    /// top-left corner rounded with `radius` pixels. The interior carries
    /// `interiorAlpha`; pixels in the cut corner (outside the quarter circle
    /// centered at (radius, radius)) are fully transparent. A one-pixel
    /// antialiased ramp is applied along the boundary to mimic a real capture.
    private func makeCornerBuffer(cornerSize: Int,
                                  radius: Double,
                                  interiorAlpha: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: cornerSize * cornerSize * 4)
        for y in 0..<cornerSize {
            for x in 0..<cornerSize {
                let fx = Double(x)
                let fy = Double(y)
                // Coverage of the window mask at this pixel, in [0, 1].
                let coverage: Double
                if fx >= radius || fy >= radius {
                    // Straight edge region: fully inside the window.
                    coverage = 1.0
                } else {
                    // Rounded region: inside iff within the quarter circle.
                    let dx = fx - radius
                    let dy = fy - radius
                    let dist = (dx * dx + dy * dy).squareRoot()
                    // 1px antialiased ramp around dist == radius.
                    coverage = max(0.0, min(1.0, radius - dist + 0.5))
                }
                let alpha = Int((Double(interiorAlpha) * coverage).rounded())
                let offset = (y * cornerSize + x) * 4
                // Premultiplied: store alpha in all channels (value is irrelevant
                // to detection, which reads only the alpha byte).
                rgba[offset + 0] = UInt8(alpha)
                rgba[offset + 1] = UInt8(alpha)
                rgba[offset + 2] = UInt8(alpha)
                rgba[offset + 3] = UInt8(alpha)
            }
        }
        return rgba
    }

    private func detect(radius: Double,
                        interiorAlpha: Int,
                        cornerSize: Int = 50,
                        scale: CGFloat = 1.0) -> CGFloat? {
        let buffer = makeCornerBuffer(cornerSize: cornerSize,
                                      radius: radius,
                                      interiorAlpha: interiorAlpha)
        return iTermWindowCornerRadiusDetector.cornerRadiusInPoints(
            premultipliedRGBA: buffer,
            cornerSize: cornerSize,
            backingScaleFactor: scale)
    }

    // MARK: - Detection at varying opacity

    // Edge points are sampled at integer pixels, so the fitted radius carries a
    // sub-2px bias that is largest at small radii. Real Retina captures are 2x
    // larger in pixels, halving the relative error.
    private let radiusAccuracy: CGFloat = 2.0

    func testDetectsRadiusForOpaqueWindow() {
        let detected = detect(radius: 12, interiorAlpha: 255)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 12, accuracy: radiusAccuracy)
    }

    func testDetectsRadiusForTenPercentOpacityWindow() {
        // 10% opacity -> interior alpha ~26. The old fixed threshold of 180
        // never triggered here, so detection used to fail entirely (returned
        // nil). This is the core regression covered by issue 12882: it must now
        // produce a usable measurement.
        let detected = detect(radius: 12, interiorAlpha: 26)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 12, accuracy: radiusAccuracy)
    }

    func testDetectsRadiusForFivePercentOpacityWindow() {
        let detected = detect(radius: 20, interiorAlpha: 13)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 20, accuracy: 1.0)
    }

    func testDetectionIsOpacityIndependent() {
        // The measured radius must not depend on how transparent the window is.
        let radius = 16.0
        let opaque = detect(radius: radius, interiorAlpha: 255)
        let translucent = detect(radius: radius, interiorAlpha: 26)
        XCTAssertNotNil(opaque)
        XCTAssertNotNil(translucent)
        XCTAssertEqual(opaque!, translucent!, accuracy: 1.0)
    }

    func testHonorsBackingScaleFactor() {
        // 24px radius at 2x backing scale is a 12pt radius.
        let detected = detect(radius: 24, interiorAlpha: 26, scale: 2.0)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 12, accuracy: 1.0)
    }

    func testDetectsLargeTahoeStyleRadius() {
        let detected = detect(radius: 30, interiorAlpha: 26, cornerSize: 50)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 30, accuracy: 1.5)
    }

    // MARK: - Failure cases

    func testFullyTransparentWindowReturnsNil() {
        // Nothing opaque enough to measure -> no edge points -> nil.
        let detected = detect(radius: 12, interiorAlpha: 0)
        XCTAssertNil(detected)
    }

    func testRejectsUndersizedBuffer() {
        let tooSmall = [UInt8](repeating: 0, count: 10)
        let detected = iTermWindowCornerRadiusDetector.cornerRadiusInPoints(
            premultipliedRGBA: tooSmall,
            cornerSize: 50,
            backingScaleFactor: 1.0)
        XCTAssertNil(detected)
    }

    func testRejectsNonPositiveScale() {
        let buffer = makeCornerBuffer(cornerSize: 50, radius: 12, interiorAlpha: 255)
        let detected = iTermWindowCornerRadiusDetector.cornerRadiusInPoints(
            premultipliedRGBA: buffer,
            cornerSize: 50,
            backingScaleFactor: 0.0)
        XCTAssertNil(detected)
    }

    // MARK: - Fallback radius

    func testFallbackRadiusIsSane() {
        let fallback = iTermWindowCornerRadiusDetector.fallbackCornerRadius
        XCTAssertGreaterThanOrEqual(fallback, 12)
        XCTAssertLessThanOrEqual(fallback, 30)
    }

    func testFallbackRadiusMatchesRunningOS() {
        let fallback = iTermWindowCornerRadiusDetector.fallbackCornerRadius
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if major >= 26 {
            XCTAssertEqual(fallback, 16)
        } else {
            XCTAssertEqual(fallback, 12)
        }
    }
}
