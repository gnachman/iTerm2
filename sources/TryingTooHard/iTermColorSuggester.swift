//
//  iTermColorSuggester.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

import AppKit

// Picks a seeded random pair of text and background colors in L*a*b*, with
// the background's lightness at least minimumDifference (in [0,1)) away
// from the default background's. The default text color is not used.
@objc(iTermColorSuggester)
class iTermColorSuggester: NSObject {
    @objc let suggestedTextColor: NSColor
    @objc let suggestedBackgroundColor: NSColor

    private struct LightnessAndAngle {
        var l: CGFloat
        var theta: CGFloat
    }

    // The colors are optional because the Objective-C messaged them: a nil
    // background gives a zero L*a*b* color (lightness 0), and the caller's
    // -[iTermColorMap colorForKey:] returns nil for a missing key.
    @objc(initWithDefaultTextColor:defaultBackgroundColor:minimumDifference:seed:)
    init(defaultTextColor: NSColor?,
         defaultBackgroundColor: NSColor?,
         minimumDifference: CGFloat,
         seed: Int) {
        it_betaAssert(Thread.isMainThread, "iTermColorSuggester is used on the main thread only")
        let defaultBackgroundLAB = defaultBackgroundColor?.labColor() ?? iTermLABColor()

        // The process-wide drand48 generator, as before: its state after this
        // initializer is observable.
        srand48(seed)
        var textLAB: iTermLABColor
        var backgroundLAB: iTermLABColor
        repeat {
            let laa = Self.randomLightnessAndAngle()
            textLAB = Self.textLAB(laa)
            backgroundLAB = Self.backgroundLAB(laa)
        } while abs(backgroundLAB.l / 100.0 - defaultBackgroundLAB.l / 100.0) < minimumDifference
        suggestedTextColor = NSColor.withLABColor(textLAB)
        suggestedBackgroundColor = NSColor.withLABColor(backgroundLAB)
        super.init()
    }

    private static func randomLightnessAndAngle() -> LightnessAndAngle {
        var laa = LightnessAndAngle(l: CGFloat(drand48()) * 100.0, theta: 0)
        if laa.l < 50 {
            laa.l /= 2.0
        } else {
            laa.l = 100 - (laa.l - 50) / 2.0
        }
        laa.theta = CGFloat(drand48()) * .pi * 2
        return laa
    }

    // Round trip through RGB to keep it in gamut.
    private static func clampedLAB(_ lab: iTermLABColor) -> iTermLABColor {
        return iTermLABFromSRGB(iTermSRGBFromLAB(lab))
    }

    private static func textLAB(_ laa: LightnessAndAngle) -> iTermLABColor {
        let lab = iTermLABColor(l: laa.l,
                                a: sin(laa.theta) * 100.0,
                                b: cos(laa.theta) * 100.0)
        return clampedLAB(lab)
    }

    private static func backgroundLAB(_ laa: LightnessAndAngle) -> iTermLABColor {
        let lab = iTermLABColor(l: 100.0 - laa.l,
                                a: sin(laa.theta + .pi / 2) * 100.0,
                                b: cos(laa.theta + .pi / 2) * 100.0)
        return clampedLAB(lab)
    }
}
