//
//  iTermHDRTextTests.swift
//  iTerm2 ModernTests
//
//  Pins the rules for HDR text that both renderers share: when the focused
//  pane's text is brightened (+[iTermCursor hdrTextGainForRequestedBrightness:...])
//  and the color it is brightened to (iTermHDRTextBoostedColor, the CPU twin of
//  the text shader's iTermHDRBoostTextColor).
//

import XCTest
@testable import iTerm2SharedARC

final class iTermHDRTextTests: XCTestCase {
    private let dark = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    private let light = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)

    private func gain(requested: CGFloat = 3,
                      enabled: Bool = true,
                      focused: Bool = true,
                      background: NSColor? = nil,
                      headroom: CGFloat = 16) -> CGFloat {
        return iTermCursor.hdrTextGain(forRequestedBrightness: requested,
                                       profileEnabled: enabled,
                                       focused: focused,
                                       background: background ?? dark,
                                       potentialHeadroom: headroom)
    }

    // MARK: - Gain

    func testGainIsRequestedBrightnessWhenEverythingApplies() {
        XCTAssertEqual(gain(), 3)
    }

    func testNoBoostWhenProfileSettingIsOff() {
        XCTAssertEqual(gain(enabled: false), 1)
    }

    func testNoBoostWhenPaneIsNotFocused() {
        XCTAssertEqual(gain(focused: false), 1)
    }

    func testNoBoostOnLightBackground() {
        XCTAssertEqual(gain(background: light), 1)
    }

    func testNoBoostWithoutHeadroom() {
        XCTAssertEqual(gain(headroom: 1), 1)
        XCTAssertEqual(gain(headroom: 0), 1)
    }

    func testGainIsCappedAtHeadroom() {
        XCTAssertEqual(gain(requested: 6, headroom: 2.5), 2.5)
    }

    func testGainIsCappedAtMaximum() {
        XCTAssertEqual(gain(requested: 100, headroom: 100), iTermHDRTextMaximumBrightness)
    }

    func testGainIsNeverBelowOne() {
        XCTAssertEqual(gain(requested: 0.5), 1)
    }

    // MARK: - Boosted color

    private func boost(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat,
                       gain: CGFloat, headroom: CGFloat) -> iTermHDRTextColor {
        return iTermHDRTextBoostedColor(iTermHDRTextColor(red: red, green: green, blue: blue),
                                        gain,
                                        headroom)
    }

    private func linear(_ encoded: CGFloat) -> CGFloat {
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    func testGainOfOneLeavesColorUnchanged() {
        let result = boost(0.2, 0.5, 0.8, gain: 1, headroom: 16)
        XCTAssertEqual(result.red, 0.2)
        XCTAssertEqual(result.green, 0.5)
        XCTAssertEqual(result.blue, 0.8)
    }

    // White brightened by the gain must match the HDR cursor's encoding of the
    // same brightness, so "3x" means the same thing for the cursor and text.
    func testWhiteMatchesHDRCursorEncoding() {
        let result = boost(1, 1, 1, gain: 3, headroom: 16)
        let cursor = iTermCursor.hdrCursorComponentValue(forRequestedBrightness: 3, headroom: 16)
        XCTAssertEqual(result.red, cursor, accuracy: 1e-9)
        XCTAssertEqual(result.green, cursor, accuracy: 1e-9)
        XCTAssertEqual(result.blue, cursor, accuracy: 1e-9)
    }

    // The gain multiplies light, so in linear terms every channel scales by it.
    func testGainIsAppliedInLinearLight() {
        let result = boost(0.5, 0.25, 0.1, gain: 2, headroom: 16)
        XCTAssertEqual(linear(result.red), 2 * linear(0.5), accuracy: 1e-9)
        XCTAssertEqual(linear(result.green), 2 * linear(0.25), accuracy: 1e-9)
        XCTAssertEqual(linear(result.blue), 2 * linear(0.1), accuracy: 1e-9)
    }

    // When the brightest channel would pass the headroom, the whole color is
    // scaled down together, so the ratios between channels (the hue) are kept.
    func testHueIsKeptWhenClampedToHeadroom() {
        let result = boost(1, 0.5, 0.2, gain: 8, headroom: 2)
        XCTAssertEqual(linear(result.red), 2, accuracy: 1e-9)
        XCTAssertEqual(linear(result.green) / linear(result.red),
                       linear(0.5) / linear(1),
                       accuracy: 1e-9)
        XCTAssertEqual(linear(result.blue) / linear(result.red),
                       linear(0.2) / linear(1),
                       accuracy: 1e-9)
    }

    // A color already at the headroom is not dimmed.
    func testColorIsNeverDimmed() {
        let result = boost(1, 1, 1, gain: 3, headroom: 1)
        XCTAssertEqual(result.red, 1, accuracy: 1e-9)
    }

    func testBlackStaysBlack() {
        let result = boost(0, 0, 0, gain: 8, headroom: 16)
        XCTAssertEqual(result.red, 0)
        XCTAssertEqual(result.green, 0)
        XCTAssertEqual(result.blue, 0)
    }

    // MARK: - Legacy renderer

    // The legacy renderer, like the legacy HDR cursor, can't set a color above
    // 1.0, so it adds the difference with plusLighter passes of at most 1.0 each.
    // That relies on an extended-range context accumulating past 1.0.
    func testPlusLighterAccumulatesPastWhiteInExtendedRangeContext() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.floatComponents.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: 1,
                                              height: 1,
                                              bitsPerComponent: 32,
                                              bytesPerRow: 16,
                                              space: colorSpace,
                                              bitmapInfo: bitmapInfo))
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [0.6, 0.6, 0.6, 1])!)
        context.fill(rect)
        context.setBlendMode(.plusLighter)
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!)
        context.fill(rect)
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [0.3, 0.3, 0.3, 1])!)
        context.fill(rect)

        let data = try XCTUnwrap(context.data)
        let red = data.assumingMemoryBound(to: Float.self)[0]
        XCTAssertEqual(red, 1.9, accuracy: 1e-3)
    }
}
