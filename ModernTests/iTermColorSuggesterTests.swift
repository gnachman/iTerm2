//
//  iTermColorSuggesterTests.swift
//  ModernTests
//
//  Characterization tests for iTermColorSuggester, which picks a seeded
//  random text and background color pair for a new trigger. Written against
//  the Objective-C class before its port to Swift and meant to run unchanged
//  against the port: they use only its initializer and two properties, as
//  Swift imports them.
//
//  The class seeds the process-wide drand48 generator, so each test that
//  depends on its sequence seeds it itself, through the class or srand48.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermColorSuggesterTests: XCTestCase {
    private let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private let gray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)

    private func suggest(text: NSColor? = nil,
                         background: NSColor,
                         minimumDifference: CGFloat = 0.25,
                         seed: Int) -> iTermColorSuggester {
        return iTermColorSuggester(defaultTextColor: text ?? white,
                                   defaultBackgroundColor: background,
                                   minimumDifference: minimumDifference,
                                   seed: seed)
    }

    private func components(_ color: NSColor) -> [CGFloat] {
        let srgb = color.usingColorSpace(.sRGB)!
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
    }

    private func assertComponents(_ color: NSColor, _ expected: [CGFloat],
                                  file: StaticString = #filePath, line: UInt = #line) {
        let actual = components(color)
        XCTAssertEqual(actual.count, expected.count, "actual \(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 1e-9, "actual \(actual)", file: file, line: line)
        }
    }

    // Lightness as -[NSColor labColor] computes it, which is what the class
    // uses for the default background. It swaps green and blue
    // (docs/swift-migration/bugs.md), which does not matter for the gray
    // defaults used here.
    private func defaultLightness(_ color: NSColor) -> CGFloat {
        return color.labColor().l
    }

    // Lightness of a result, from its sRGB components in order. The class
    // compared the lightness of the L*a*b* color it then converted to sRGB.
    private func resultLightness(_ color: NSColor) -> CGFloat {
        let c = components(color)
        return iTermLABFromSRGB(iTermSRGBColor(r: c[0], g: c[1], b: c[2])).l
    }

    // MARK: - Golden values

    // Recorded from the Objective-C class. They pin the whole computation:
    // the order of the two draws, the folding of lightness away from 50,
    // the background's complementary lightness and quarter-turned hue, the
    // clamping round trip, and the retry loop.

    func testGoldenValuesOnBlack() {
        let cs = suggest(background: black, seed: 1)
        assertComponents(cs.suggestedTextColor,
                         [0.0, 0.07936068624258041, 0.5797866582870483, 1.0])
        assertComponents(cs.suggestedBackgroundColor,
                         [0.0, 0.9999873042106628, 0.9999164938926697, 1.0])
    }

    func testGoldenValuesOnWhite() {
        let cs = suggest(background: white, seed: 12345)
        assertComponents(cs.suggestedTextColor,
                         [0.04705577343702316, 0.1617143154144287, 4.6100512918201275e-06, 1.0])
        assertComponents(cs.suggestedBackgroundColor,
                         [1.0, 0.528312087059021, 0.5337218642234802, 1.0])
    }

    func testGoldenValuesWithNoMinimumDifference() {
        let cs = suggest(background: gray, minimumDifference: 0, seed: 7)
        assertComponents(cs.suggestedTextColor,
                         [0.0, 0.22835341095924377, 0.3626052141189575, 1.0])
        assertComponents(cs.suggestedBackgroundColor,
                         [0.7230584025382996, 0.9206520318984985, 0.0002794315223582089, 1.0])
    }

    func testGoldenValuesForANegativeSeed() {
        let cs = suggest(background: black, minimumDifference: 0.5, seed: -987654321)
        assertComponents(cs.suggestedTextColor,
                         [0.5436128973960876, 0.0003488629008643329, 8.118816913338378e-05, 1.0])
        assertComponents(cs.suggestedBackgroundColor,
                         [0.37868982553482056, 0.8169755935668945, 0.9999157786369324, 1.0])
    }

    // MARK: - Determinism

    func testSameInputsGiveTheSameColors() {
        let a = suggest(background: black, seed: 42)
        srand48(999)  // Disturb the shared generator in between.
        _ = drand48()
        let b = suggest(background: black, seed: 42)
        XCTAssertEqual(components(a.suggestedTextColor), components(b.suggestedTextColor))
        XCTAssertEqual(components(a.suggestedBackgroundColor), components(b.suggestedBackgroundColor))
    }

    func testDifferentSeedsGiveDifferentColors() {
        let a = suggest(background: black, seed: 1)
        let b = suggest(background: black, seed: 2)
        XCTAssertNotEqual(components(a.suggestedTextColor), components(b.suggestedTextColor))
        XCTAssertNotEqual(components(a.suggestedBackgroundColor), components(b.suggestedBackgroundColor))
    }

    func testTheDefaultTextColorIsIgnored() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        for seed in [3, 4, 5] {
            let a = suggest(text: red, background: gray, seed: seed)
            let b = suggest(text: black, background: gray, seed: seed)
            XCTAssertEqual(components(a.suggestedTextColor), components(b.suggestedTextColor))
            XCTAssertEqual(components(a.suggestedBackgroundColor), components(b.suggestedBackgroundColor))
        }
    }

    // MARK: - The minimum difference

    func testBackgroundLightnessIsFarEnoughFromTheDefault() {
        // Lightness is in 0...100, so a minimum the default leaves no room
        // for never terminates: gray (about 53) allows less than 0.46.
        for background in [black, white, gray] {
            let defaultL = defaultLightness(background)
            for minimum in [CGFloat(0.1), 0.25, 0.4] {
                for seed in 0..<20 {
                    let cs = suggest(background: background, minimumDifference: minimum, seed: seed)
                    let l = resultLightness(cs.suggestedBackgroundColor)
                    XCTAssertGreaterThanOrEqual(abs(l / 100 - defaultL / 100), minimum - 1e-4,
                                                "seed \(seed) minimum \(minimum) default L \(defaultL)")
                }
            }
        }
    }

    // MARK: - The shared generator

    // With no minimum difference the first attempt is accepted: the class
    // reseeds drand48 with the seed and takes exactly two numbers from it,
    // so the next one is the third of that sequence.
    func testOneAttemptTakesTwoNumbersFromTheSharedGenerator() {
        for seed in [0, 1, 77, -5] {
            srand48(seed)
            _ = drand48()
            _ = drand48()
            let third = drand48()
            srand48(123)  // Make sure the class is what reseeds it.
            _ = suggest(background: gray, minimumDifference: 0, seed: seed)
            XCTAssertEqual(drand48(), third, "seed \(seed)")
        }
    }

    // MARK: - Gamut

    func testResultsAreInTheSRGBGamutAndOpaque() {
        for seed in 0..<30 {
            let cs = suggest(background: seed % 2 == 0 ? black : white, seed: seed)
            for color in [cs.suggestedTextColor, cs.suggestedBackgroundColor] {
                let c = components(color)
                for value in c.prefix(3) {
                    XCTAssertGreaterThanOrEqual(value, -1e-9, "seed \(seed) \(c)")
                    XCTAssertLessThanOrEqual(value, 1 + 1e-9, "seed \(seed) \(c)")
                }
                XCTAssertEqual(c[3], 1, "seed \(seed)")
            }
        }
    }
}
