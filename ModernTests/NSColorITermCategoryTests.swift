//
//  NSColorITermCategoryTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermNSColorCategoryTests.m. Covers the sRGB <-> LAB conversions in
//  NSColor+iTerm.h.
//

import XCTest
@testable import iTerm2SharedARC

final class NSColorITermCategoryTests: XCTestCase {

    // The tolerances on these tests are much larger than I'd like. I have not found two reference
    // implementations that agree with each other any more closely, unfortunately.
    private func assertLAB(fromSRGB r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                           isL l: CGFloat, a: CGFloat, b labB: CGFloat,
                           file: StaticString = #filePath,
                           line: UInt = #line) {
        let lab = iTermLABFromSRGB(iTermSRGBColor(r: r, g: g, b: b))
        XCTAssertEqual(lab.l, l, accuracy: 1, file: file, line: line)
        XCTAssertEqual(lab.a, a, accuracy: 1, file: file, line: line)
        XCTAssertEqual(lab.b, labB, accuracy: 1, file: file, line: line)
    }

    // This is really a test that iTermSRGBFromLAB is an inverse of iTermLABFromSRGB. These are
    // not ground-truth values because as noted above I can't find any.
    private func assertSRGB(fromLAB l: CGFloat, _ a: CGFloat, _ b: CGFloat,
                            isR r: CGFloat, g: CGFloat, b srgbB: CGFloat,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        let srgb = iTermSRGBFromLAB(iTermLABColor(l: l, a: a, b: b))
        XCTAssertEqual(srgb.r, r, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(srgb.g, g, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(srgb.b, srgbB, accuracy: 0.01, file: file, line: line)
    }

    // MARK: - iTermLABFromSRGB

    func testLABFromSRGB_PureRed() {
        assertLAB(fromSRGB: 1, 0, 0, isL: 54, a: 80, b: 67)
    }

    func testLABFromSRGB_Pink() {
        assertLAB(fromSRGB: 0.8, 0.2, 0.5, isL: 48, a: 65, b: -7)
    }

    func testLABFromSRGB_PaleLavender() {
        assertLAB(fromSRGB: 0.9, 0.8, 0.9, isL: 85, a: 13, b: -9)
    }

    func testLABFromSRGB_DarkGreen() {
        assertLAB(fromSRGB: 0.1, 0.2, 0.1, isL: 18, a: -16, b: 13)
    }

    // MARK: - iTermSRGBFromLAB

    func testSRGBFromLAB_PureRed() {
        assertSRGB(fromLAB: 53.23, 80.10, 67.22, isR: 1, g: 0, b: 0)
    }

    func testSRGBFromLAB_Pink() {
        assertSRGB(fromLAB: 47.94, 64.62, -6.94, isR: 0.8, g: 0.2, b: 0.5)
    }

    func testSRGBFromLAB_PaleLavender() {
        assertSRGB(fromLAB: 84.80, 13.32, -9.32, isR: 0.9, g: 0.8, b: 0.9)
    }

    func testSRGBFromLAB_DarkGreen() {
        assertSRGB(fromLAB: 18.60, -16.39, 13.17, isR: 0.1, g: 0.2, b: 0.1)
    }
}
