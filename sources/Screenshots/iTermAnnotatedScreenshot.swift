//
//  iTermAnnotatedScreenshot.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/5/26.
//

import AppKit
import CoreImage

/// Manages async blur operations with cancellation support
private class BlurWorkQueue {
    private let queue = DispatchQueue(label: "com.iterm2.screenshot.blur", qos: .userInitiated)
    private let lock = NSLock()
    private var currentWorkId: UInt64 = 0
    private var pendingWorkId: UInt64 = 0

    struct WorkItem {
        let id: UInt64
        let cgImage: CGImage
        let rects: [CGRect]
        let radius: CGFloat
        let imageSize: NSSize
        let completion: (NSImage?) -> Void
    }

    /// Submit new blur work, canceling any pending work
    func submit(cgImage: CGImage,
                rects: [CGRect],
                radius: CGFloat,
                imageSize: NSSize,
                completion: @escaping (NSImage?) -> Void) {
        lock.lock()
        currentWorkId += 1
        let workId = currentWorkId
        pendingWorkId = workId
        lock.unlock()

        queue.async { [weak self] in
            self?.processWork(WorkItem(
                id: workId,
                cgImage: cgImage,
                rects: rects,
                radius: radius,
                imageSize: imageSize,
                completion: completion
            ))
        }
    }

    private func processWork(_ item: WorkItem) {
        // Check if this work is still current before starting
        lock.lock()
        let isCurrent = item.id == pendingWorkId
        lock.unlock()

        guard isCurrent else {
            // Work was superseded, skip it
            return
        }

        // Do the heavy blur work
        let result = performBlur(cgImage: item.cgImage, rects: item.rects, radius: item.radius)

        // Check again if still current before delivering result
        lock.lock()
        let stillCurrent = item.id == pendingWorkId
        lock.unlock()

        guard stillCurrent else {
            return
        }

        // Deliver result on main queue
        DispatchQueue.main.async {
            if let processedCGImage = result {
                item.completion(NSImage(cgImage: processedCGImage, size: item.imageSize))
            } else {
                item.completion(nil)
            }
        }
    }

    private func performBlur(cgImage: CGImage, rects: [CGRect], radius: CGFloat) -> CGImage? {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        // Create a bitmap context for compositing
        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Draw the original image
        let fullRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        context.draw(cgImage, in: fullRect)

        // Create a CIImage from the original
        let ciImage = CIImage(cgImage: cgImage)

        // Clamp to extent before blurring to prevent edge fade
        let clampedImage = ciImage.clampedToExtent()

        // Apply Gaussian blur to the clamped image
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        blurFilter.setValue(clampedImage, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurredCIImage = blurFilter.outputImage else {
            return nil
        }

        // Crop back to original bounds
        let croppedBlurred = blurredCIImage.cropped(to: ciImage.extent)

        // Render the blurred image to a CGImage
        let ciContext = CIContext(options: nil)
        guard let blurredCGImage = ciContext.createCGImage(croppedBlurred, from: ciImage.extent) else {
            return nil
        }

        // For each rect, replace the original content with the blurred portion
        for rect in rects {
            context.saveGState()
            context.clip(to: rect)
            context.setBlendMode(.copy)
            context.draw(blurredCGImage, in: CGRect(x: 0, y: 0,
                                                     width: cgImage.width,
                                                     height: cgImage.height))
            context.restoreGState()
        }

        return context.makeImage()
    }
}

@objc(iTermAnnotatedScreenshot)
class iTermAnnotatedScreenshot: NSObject {
    private static let blurQueue = BlurWorkQueue()

    @objc static func captureAndSave(window: NSWindow,
                                     selectionRegions: [iTermBlurredScreenshotSelectionRegion],
                                     method: iTermBlurredScreenshotObscureMethod,
                                     lineRange: NSRange,
                                     terminalInfo: iTermScreenshotTerminalInfo?,
                                     completion: @escaping (URL?) -> Void) {
        // Render lines directly from the text view (same as preview) to support scrollback
        guard let info = terminalInfo, let textView = info.textView else {
            completion(nil)
            return
        }

        // Render the line range to an image
        guard var renderedImage = textView.renderLines(toImage: lineRange) else {
            completion(nil)
            return
        }

        // Apply redactions using image coordinates.
        // The selectionRegions contain rects that are already in image coordinates,
        // computed by the redaction manager's imageRects(for:lineRange:) method.
        let imageRects = selectionRegions.flatMap { $0.windowRects }

        if !imageRects.isEmpty {
            if let obscuredImage = applyObscuring(
                to: renderedImage,
                imageRects: imageRects,
                method: method
            ) {
                renderedImage = obscuredImage
            }
        }

        // Convert NSImage to CGImage and save
        guard let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }

        let url = saveToDesktop(image: cgImage)
        completion(url)
    }

    @objc static func applyObscuring(to cgImage: CGImage,
                                     windowRects: [NSValue],
                                     method: iTermBlurredScreenshotObscureMethod,
                                     scaleFactor: CGFloat) -> CGImage? {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        // Create a bitmap context for compositing
        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Draw the original image
        let fullRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        context.draw(cgImage, in: fullRect)

        // Convert window-relative rects to context coordinates.
        // Window coordinates from convertRect:toView:nil have origin at bottom-left of content area.
        // CGContext coordinates also have origin at bottom-left.
        // After drawing the CGImage, the content area's bottom is at Y=0 in the context.
        // So we just need to scale from points to pixels - no coordinate flipping needed.
        let convertedRects = windowRects.map { value -> CGRect in
            let rect = value.rectValue
            return CGRect(
                x: rect.origin.x * scaleFactor,
                y: rect.origin.y * scaleFactor,
                width: rect.size.width * scaleFactor,
                height: rect.size.height * scaleFactor
            )
        }

        switch method.kind {
        case .blur(let radius):
            applyBlur(to: context, cgImage: cgImage, rects: convertedRects, radius: radius)
        case .solidColor(let color):
            applySolidColor(to: context, rects: convertedRects, color: color)
        }

        return context.makeImage()
    }

    private static func applyBlur(to context: CGContext,
                                  cgImage: CGImage,
                                  rects: [CGRect],
                                  radius: CGFloat) {
        // Create a CIImage from the original
        let ciImage = CIImage(cgImage: cgImage)

        // Clamp to extent before blurring to prevent edge fade.
        // Without this, the blur filter samples transparent pixels outside
        // the image bounds, causing the blur to fade toward the edges.
        let clampedImage = ciImage.clampedToExtent()

        // Apply Gaussian blur to the clamped image
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return
        }
        blurFilter.setValue(clampedImage, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurredCIImage = blurFilter.outputImage else {
            return
        }

        // Crop back to original bounds (clampedToExtent makes it infinite)
        let croppedBlurred = blurredCIImage.cropped(to: ciImage.extent)

        // Render the blurred image to a CGImage
        let ciContext = CIContext(options: nil)
        guard let blurredCGImage = ciContext.createCGImage(croppedBlurred, from: ciImage.extent) else {
            return
        }

        // For each rect, replace the original content with the blurred portion
        for rect in rects {
            context.saveGState()
            context.clip(to: rect)

            // Use copy blend mode to replace pixels instead of compositing
            context.setBlendMode(.copy)

            // Draw the blurred image (it will be clipped to the rect)
            context.draw(blurredCGImage, in: CGRect(x: 0, y: 0,
                                                     width: cgImage.width,
                                                     height: cgImage.height))
            context.restoreGState()
        }
    }

    private static func applySolidColor(to context: CGContext,
                                        rects: [CGRect],
                                        color: NSColor) {
        // Convert NSColor to CGColor, handling color space conversion
        let cgColor: CGColor
        if let converted = color.usingColorSpace(.deviceRGB) {
            cgColor = converted.cgColor
        } else {
            cgColor = color.cgColor
        }

        context.setFillColor(cgColor)

        for rect in rects {
            context.fill(rect)
        }
    }

    /// Applies obscuring to an NSImage (for preview) - synchronous version
    @objc static func applyObscuring(to image: NSImage,
                                     imageRects: [NSValue],
                                     method: iTermBlurredScreenshotObscureMethod) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // The imageRects are in points, but the CGImage is in pixels.
        // Calculate scale factor as pixel dimensions / point dimensions.
        let scaleFactor = CGFloat(cgImage.height) / image.size.height

        guard let processedCGImage = applyObscuring(
            to: cgImage,
            windowRects: imageRects,
            method: method,
            scaleFactor: scaleFactor
        ) else {
            return nil
        }

        return NSImage(cgImage: processedCGImage, size: image.size)
    }

    /// Applies obscuring to an NSImage asynchronously (for preview with blur)
    /// Cancels any pending blur operations when called again
    @objc static func applyObscuringAsync(to image: NSImage,
                                          imageRects: [NSValue],
                                          method: iTermBlurredScreenshotObscureMethod,
                                          completion: @escaping (NSImage?) -> Void) {
        // For non-blur methods, do synchronously
        guard method.isBlur else {
            completion(applyObscuring(to: image, imageRects: imageRects, method: method))
            return
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }

        let scaleFactor = CGFloat(cgImage.height) / image.size.height

        // Convert rects to pixel coordinates
        let convertedRects = imageRects.map { value -> CGRect in
            let rect = value.rectValue
            return CGRect(
                x: rect.origin.x * scaleFactor,
                y: rect.origin.y * scaleFactor,
                width: rect.size.width * scaleFactor,
                height: rect.size.height * scaleFactor
            )
        }

        // Submit to async blur queue (cancels any pending work)
        blurQueue.submit(
            cgImage: cgImage,
            rects: convertedRects,
            radius: method.blurRadius,
            imageSize: image.size,
            completion: completion
        )
    }

    private static func saveToDesktop(image: CGImage) -> URL? {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        return saveToDesktop(nsImage: nsImage)
    }

    /// Saves an NSImage to the Desktop as a PNG file
    @objc static func saveToDesktop(nsImage: NSImage) -> URL? {
        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "iTerm2-Screenshot-\(timestamp).png"

        // Get Desktop path
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            return nil
        }

        let fileURL = desktopURL.appendingPathComponent(filename)

        // Create PNG data
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Highlight Support

    /// Applies highlights (outline with shadow) to an NSImage.
    /// Each inner array of rects represents one sub-selection that should be outlined together.
    /// The backgroundColor is used to adjust shadow opacity for visibility on dark backgrounds.
    @objc static func applyHighlights(to image: NSImage,
                                       groupedRects: [[NSValue]],
                                       outlineColor: NSColor,
                                       outlineWidth: CGFloat,
                                       shadowRadius: CGFloat,
                                       backgroundColor: NSColor) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleFactor = CGFloat(cgImage.height) / image.size.height

        guard let processedCGImage = applyHighlights(
            to: cgImage,
            groupedRects: groupedRects,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth,
            shadowRadius: shadowRadius,
            scaleFactor: scaleFactor,
            backgroundIsDark: backgroundColor.isDark
        ) else {
            return nil
        }

        return NSImage(cgImage: processedCGImage, size: image.size)
    }

    private static func applyHighlights(to cgImage: CGImage,
                                         groupedRects: [[NSValue]],
                                         outlineColor: NSColor,
                                         outlineWidth: CGFloat,
                                         shadowRadius: CGFloat,
                                         scaleFactor: CGFloat,
                                         backgroundIsDark: Bool) -> CGImage? {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Draw the original image
        let fullRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        context.draw(cgImage, in: fullRect)

        // Convert outline color
        let cgOutlineColor: CGColor
        if let converted = outlineColor.usingColorSpace(.deviceRGB) {
            cgOutlineColor = converted.cgColor
        } else {
            cgOutlineColor = outlineColor.cgColor
        }

        let strokeWidth = outlineWidth * scaleFactor
        let scaledShadowRadius = shadowRadius * scaleFactor

        // Pre-compute all outline paths
        var allOutlinePaths: [CGPath] = []

        for group in groupedRects {
            let convertedRects = group.map { value -> CGRect in
                let rect = value.rectValue
                return CGRect(
                    x: rect.origin.x * scaleFactor,
                    y: rect.origin.y * scaleFactor,
                    width: rect.size.width * scaleFactor,
                    height: rect.size.height * scaleFactor
                )
            }
            allOutlinePaths.append(createOutlinePath(for: convertedRects))
        }

        // Create a combined clip path that excludes ALL highlight interiors
        // This ensures shadows don't render inside any highlighted region
        let combinedClipPath = CGMutablePath()
        combinedClipPath.addRect(fullRect)
        for outlinePath in allOutlinePaths {
            combinedClipPath.addPath(outlinePath)
        }

        // Shadow color: use white on dark backgrounds (black shadow is invisible on dark),
        // black on light backgrounds
        let shadowColor: NSColor
        let shadowAlpha: CGFloat
        if backgroundIsDark {
            shadowColor = .white
            shadowAlpha = 1.0
        } else {
            shadowColor = .black
            shadowAlpha = 1.0
        }
        let shadowCGColor = shadowColor.withAlphaComponent(shadowAlpha).cgColor

        // Draw outlines with shadow, clipping to exclude highlight interiors
        context.saveGState()

        // Clip using even-odd rule: the combined path has the full rect as outer boundary
        // and each highlight path as inner holes, so drawing only affects the exterior
        context.addPath(combinedClipPath)
        context.clip(using: .evenOdd)

        context.setShadow(offset: .zero, blur: scaledShadowRadius, color: shadowCGColor)
        context.setStrokeColor(cgOutlineColor)
        context.setLineWidth(strokeWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        for outlinePath in allOutlinePaths {
            context.addPath(outlinePath)
            context.strokePath()
        }
        context.restoreGState()

        return context.makeImage()
    }

    /// Creates a polygon path that traces the outer boundary of a set of adjacent line rects.
    /// Rects are assumed to be vertically adjacent (representing lines of a selection).
    private static func createOutlinePath(for rects: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        guard !rects.isEmpty else { return path }

        if rects.count == 1 {
            path.addRect(rects[0])
            return path
        }

        // Sort by maxY descending (top to bottom visually, since origin is bottom-left)
        let sorted = rects.sorted { $0.maxY > $1.maxY }

        // Start at top-left of first rect
        path.move(to: CGPoint(x: sorted[0].minX, y: sorted[0].maxY))

        // Go to top-right of first rect
        path.addLine(to: CGPoint(x: sorted[0].maxX, y: sorted[0].maxY))

        // Trace DOWN the right edge
        for i in 0..<sorted.count {
            let rect = sorted[i]

            // Go down to bottom-right of current rect
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

            // If there's a rect below with different right edge, add horizontal segment
            if i < sorted.count - 1 {
                let nextRect = sorted[i + 1]
                if abs(nextRect.maxX - rect.maxX) > 0.5 {
                    path.addLine(to: CGPoint(x: nextRect.maxX, y: rect.minY))
                }
            }
        }

        // Now at bottom-right of last rect, go to bottom-left
        let last = sorted[sorted.count - 1]
        path.addLine(to: CGPoint(x: last.minX, y: last.minY))

        // Trace UP the left edge
        for i in (0..<sorted.count).reversed() {
            let rect = sorted[i]

            // Go up to top-left of current rect
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

            // If there's a rect above with different left edge, add horizontal segment
            if i > 0 {
                let prevRect = sorted[i - 1]
                if abs(prevRect.minX - rect.minX) > 0.5 {
                    path.addLine(to: CGPoint(x: prevRect.minX, y: rect.maxY))
                }
            }
        }

        path.closeSubpath()
        return path
    }
}
