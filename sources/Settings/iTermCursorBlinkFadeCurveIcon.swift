//
//  iTermCursorBlinkFadeCurveIcon.swift
//  iTerm2
//
//  Generates small template images that visualize a cursor blink fade curve,
//  used as the icons in the fade-in/fade-out curve popup menus.
//

import AppKit

@objc(iTermCursorBlinkFadeCurveIcon)
class iTermCursorBlinkFadeCurveIcon: NSObject {
    // A small template image plotting the curve with time on the x axis and
    // opacity on the y axis. When fadeOut is true the plot is flipped
    // vertically so it shows opacity falling from 1 to 0 (the fade-out shape)
    // instead of rising from 0 to 1. The curve is sampled from
    // iTermCursorBlinkFadeAnimator so the picture always matches the
    // animation.
    @objc(imageForCurve:fadeOut:)
    class func image(forCurve curve: iTermCursorBlinkFadeCurve, fadeOut: Bool) -> NSImage {
        let size = NSSize(width: 26, height: 16)
        let image = NSImage(size: size, flipped: false) { dstRect in
            let inset = 2.0
            let left = dstRect.minX + inset
            let bottom = dstRect.minY + inset
            let plotWidth = dstRect.width - inset * 2.0
            let plotHeight = dstRect.height - inset * 2.0

            let path = NSBezierPath()
            let samples = 32
            for i in 0...samples {
                let t = CGFloat(i) / CGFloat(samples)
                var y = iTermCursorBlinkFadeAnimator.easedProgress(for: curve, atProgress: t)
                if fadeOut {
                    // x axis is time, y axis is opacity. Fade-out falls from 1
                    // to 0, which is the fade-in shape flipped vertically.
                    y = 1.0 - y
                }
                let point = NSPoint(x: left + t * plotWidth,
                                    y: bottom + y * plotHeight)
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.line(to: point)
                }
            }
            path.lineWidth = 1.25
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // Color is irrelevant for a template image; the menu tints it to
            // match the text color and selection state.
            NSColor.black.set()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
