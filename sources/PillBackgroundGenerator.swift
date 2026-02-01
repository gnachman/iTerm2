//
//  PillBackgroundGenerator.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/31/26.
//

import AppKit

@objc(iTermPillBackgroundGenerator)
class PillBackgroundGenerator: NSObject {
    // Visual styling parameters
    private static let gradientIntensity: CGFloat = 0.07
    private static let containerOpacity: CGFloat = 0.95
    private static let dividerOpacity: CGFloat = 0.3
    private static let dividerWidth: CGFloat = 1.0

    /// Generate a pill-shaped background image with gradient and dividers
    /// - Parameters:
    ///   - size: The size of the pill in points
    ///   - dividerXPositions: X positions (in points, relative to the image) where dividers should be drawn
    ///   - backgroundColor: The base background color for the pill
    ///   - foregroundColor: The foreground color (used for dividers)
    ///   - pressedSegmentIndex: Index of the pressed segment (-1 for none)
    ///   - scale: The backing scale factor (2.0 for retina)
    /// - Returns: An NSImage containing the pill background
    @objc static func generatePillImage(size: NSSize,
                                         dividerXPositions: [NSNumber],
                                         backgroundColor: NSColor,
                                         foregroundColor: NSColor,
                                         pressedSegmentIndex: Int,
                                         scale: CGFloat) -> NSImage {
        let dividers = dividerXPositions.map { CGFloat($0.doubleValue) }
        return generatePillImageInternal(size: size,
                                         dividerXPositions: dividers,
                                         backgroundColor: backgroundColor,
                                         foregroundColor: foregroundColor,
                                         pressedSegmentIndex: pressedSegmentIndex,
                                         scale: scale)
    }

    private static func generatePillImageInternal(size: NSSize,
                                                   dividerXPositions: [CGFloat],
                                                   backgroundColor: NSColor,
                                                   foregroundColor: NSColor,
                                                   pressedSegmentIndex: Int,
                                                   scale: CGFloat) -> NSImage {
        // Create image at scaled size for retina
        let scaledSize = NSSize(width: size.width * scale, height: size.height * scale)

        return NSImage(size: scaledSize, flipped: true) { rect in
            // Apply overall opacity by modifying colors
            let opaqueBackground = backgroundColor.withAlphaComponent(containerOpacity)

            // Determine gradient colors based on background brightness
            let (topColor, bottomColor) = gradientColors(for: opaqueBackground)

            // Draw the pill shape
            let cornerRadius = scaledSize.height / 2.0
            let pillPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: cornerRadius,
                                        yRadius: cornerRadius)

            // Fill with gradient
            if let gradient = NSGradient(starting: topColor, ending: bottomColor) {
                gradient.draw(in: pillPath, angle: -90) // -90 = top to bottom
            }

            // Draw pressed segment highlight if applicable
            if pressedSegmentIndex >= 0 {
                let scaledDividers = dividerXPositions.map { $0 * scale }
                let segmentRect = segmentBounds(
                    index: pressedSegmentIndex,
                    dividers: scaledDividers,
                    pillWidth: scaledSize.width,
                    pillHeight: scaledSize.height)

                // Create highlight color by blending background towards foreground
                let highlightColor = intensifyColor(opaqueBackground, towards: foregroundColor, factor: 0.4)

                // Clip to pill shape and fill segment
                NSGraphicsContext.saveGraphicsState()
                pillPath.addClip()
                highlightColor.setFill()
                segmentRect.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // Draw pill outline
            let outlineColor = foregroundColor.withAlphaComponent(dividerOpacity)
            outlineColor.setStroke()
            pillPath.lineWidth = scale
            pillPath.stroke()

            // Draw dividers
            let dividerColor = foregroundColor.withAlphaComponent(dividerOpacity)
            dividerColor.setStroke()

            for xPos in dividerXPositions {
                let scaledX = xPos * scale
                let dividerInset = 2.0 * scale
                let dividerPath = NSBezierPath()
                dividerPath.lineWidth = dividerWidth * scale
                dividerPath.move(to: NSPoint(x: scaledX, y: dividerInset))
                dividerPath.line(to: NSPoint(x: scaledX, y: scaledSize.height - dividerInset))
                dividerPath.stroke()
            }

            return true
        }
    }

    /// Calculate the bounds of a segment within the pill
    private static func segmentBounds(index: Int, dividers: [CGFloat], pillWidth: CGFloat, pillHeight: CGFloat) -> NSRect {
        let leftX: CGFloat
        let rightX: CGFloat

        if index == 0 {
            leftX = 0
        } else {
            leftX = dividers[index - 1]
        }

        if index >= dividers.count {
            rightX = pillWidth
        } else {
            rightX = dividers[index]
        }

        return NSRect(x: leftX, y: 0, width: rightX - leftX, height: pillHeight)
    }

    /// Create a more intense version of a color by blending it towards another color
    private static func intensifyColor(_ color: NSColor, towards targetColor: NSColor, factor: CGFloat) -> NSColor {
        guard let rgbColor = color.usingColorSpace(.sRGB),
              let rgbTarget = targetColor.usingColorSpace(.sRGB) else {
            return color
        }
        let r = rgbColor.redComponent + (rgbTarget.redComponent - rgbColor.redComponent) * factor
        let g = rgbColor.greenComponent + (rgbTarget.greenComponent - rgbColor.greenComponent) * factor
        let b = rgbColor.blueComponent + (rgbTarget.blueComponent - rgbColor.blueComponent) * factor
        return NSColor(srgbRed: r, green: g, blue: b, alpha: rgbColor.alphaComponent)
    }

    /// Determine gradient colors based on background brightness to avoid blending with the background.
    /// - Parameter backgroundColor: The base background color
    /// - Returns: Tuple of (topColor, bottomColor) for the gradient
    private static func gradientColors(for backgroundColor: NSColor) -> (NSColor, NSColor) {
        // Get brightness to determine which gradient strategy to use
        let brightness = getBrightness(of: backgroundColor)

        if brightness < 0.2 {
            // Dark background: both gradient colors should be lighter than background
            // Brighter on top, slightly less bright on bottom
            let topColor = adjustBrightness(of: backgroundColor, by: gradientIntensity * 2)
            let bottomColor = adjustBrightness(of: backgroundColor, by: gradientIntensity)
            return (topColor, bottomColor)
        } else if brightness > 0.8 {
            // Light background: both gradient colors should be darker than background
            // Darker on bottom, slightly less dark on top
            let topColor = adjustBrightness(of: backgroundColor, by: -gradientIntensity)
            let bottomColor = adjustBrightness(of: backgroundColor, by: -gradientIntensity * 2)
            return (topColor, bottomColor)
        } else {
            // Mid-tone background: original algorithm (lighter on top, darker on bottom)
            let topColor = adjustBrightness(of: backgroundColor, by: gradientIntensity)
            let bottomColor = adjustBrightness(of: backgroundColor, by: -gradientIntensity)
            return (topColor, bottomColor)
        }
    }

    /// Get the brightness component of a color
    /// - Parameter color: The color to analyze
    /// - Returns: Brightness value from 0.0 (black) to 1.0 (white)
    private static func getBrightness(of color: NSColor) -> CGFloat {
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return 0.5  // Default to mid-tone if conversion fails
        }

        var brightness: CGFloat = 0
        rgbColor.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return brightness
    }

    /// Adjust the brightness of a color
    /// - Parameters:
    ///   - color: The original color
    ///   - amount: Positive to lighten, negative to darken (0.0-1.0 range)
    /// - Returns: The adjusted color
    private static func adjustBrightness(of color: NSColor, by amount: CGFloat) -> NSColor {
        // Convert to a color space that supports component access
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return color
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Adjust brightness, clamping to valid range
        let newBrightness = max(0.0, min(1.0, brightness + amount))

        return NSColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha)
    }
}
