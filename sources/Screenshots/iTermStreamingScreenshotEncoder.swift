//
//  iTermStreamingScreenshotEncoder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/26.
//

import AppKit

/// Coordinates streaming screenshot encoding, rendering lines incrementally
/// and writing to PNG without holding the full image in memory.
@objc(iTermStreamingScreenshotEncoder)
class iTermStreamingScreenshotEncoder: NSObject {
    private weak var textView: PTYTextView?
    private let lineRange: NSRange
    private let destinationURL: URL
    private let redactionManager: iTermScreenshotRedactionManager?
    private let redactionMethod: iTermBlurredScreenshotObscureMethod?
    private let backgroundColor: NSColor

    private var pngWriter: iTermStreamingPNGWriter?
    private var cancelled = false
    private var encoding = false

    /// Progress callback: (currentLine, totalLines)
    @objc var onProgress: ((Int, Int) -> Void)?

    /// Completion callback: URL on success, nil on failure/cancel
    @objc var onCompletion: ((URL?) -> Void)?

    /// Lines to render per batch for progress updates
    private let batchSize = 1000

    /// Initialize the encoder.
    /// @param textView The text view to render from
    /// @param lineRange The range of lines to encode (0-based buffer-relative)
    /// @param destinationURL Where to write the PNG file
    /// @param redactionManager Optional manager for redaction annotations
    /// @param redactionMethod Optional method for applying redactions
    @objc init(textView: PTYTextView,
               lineRange: NSRange,
               destinationURL: URL,
               redactionManager: iTermScreenshotRedactionManager?,
               redactionMethod: iTermBlurredScreenshotObscureMethod?) {
        self.textView = textView
        self.lineRange = lineRange
        self.destinationURL = destinationURL
        self.redactionManager = redactionManager
        self.redactionMethod = redactionMethod
        self.backgroundColor = textView.colorMap?.color(forKey: kColorMapBackground) ?? .black
        super.init()
    }

    /// Start the encoding process. Runs on a background thread.
    @objc func start() {
        guard !encoding else { return }
        encoding = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.encodeAllRows()
        }
    }

    /// Cancel the encoding process.
    @objc func cancel() {
        cancelled = true
        pngWriter?.cancel()
    }

    // MARK: - Private

    private func encodeAllRows() {
        guard !cancelled, let textView = textView else {
            completeWith(nil)
            return
        }

        // Calculate dimensions
        let lineHeight = textView.lineHeight
        let scale = textView.window?.backingScaleFactor ?? 2.0
        let width = textView.frame.size.width
        let pixelWidth = Int(width * scale)
        let pixelHeight = Int(CGFloat(lineRange.length) * lineHeight * scale)

        guard pixelWidth > 0 && pixelHeight > 0 else {
            completeWith(nil)
            return
        }

        // Create PNG writer
        guard let writer = iTermStreamingPNGWriter(
            destinationURL: destinationURL,
            width: pixelWidth,
            height: pixelHeight,
            scaleFactor: scale
        ) else {
            completeWith(nil)
            return
        }
        pngWriter = writer

        // Get redaction rects if any
        var redactionRects: [NSValue] = []
        if let manager = redactionManager {
            redactionRects = manager.imageRects(for: textView,
                                                 lineRange: lineRange,
                                                 annotationType: .redaction)
        }

        NSLog("StreamingEncoder: lineRange=\(lineRange), got \(redactionRects.count) redaction rects")
        for (i, rect) in redactionRects.enumerated() {
            NSLog("StreamingEncoder: redactionRect[\(i)]=\(rect.rectValue)")
        }

        // Keep redaction rects in point coordinates - applyObscuring will scale them
        // Note: these are in NSImage coordinates (Y=0 at bottom)
        let pointRedactionRects = redactionRects

        // Render and encode line by line (or in small batches)
        var currentLine = lineRange.location
        let endLine = lineRange.location + lineRange.length

        while currentLine < endLine && !cancelled {
            // Render a batch of lines
            let remainingLines = endLine - currentLine
            let linesToRender = min(batchSize, remainingLines)
            let batchRange = NSRange(location: currentLine, length: linesToRender)

            // Render the batch on the main thread (required for drawing)
            var batchImage: NSImage?
            DispatchQueue.main.sync {
                batchImage = textView.renderLines(toImage: batchRange)
            }

            guard let image = batchImage else {
                cancel()
                completeWith(nil)
                return
            }

            // Apply redactions if needed
            var processedImage = image
            if !pointRedactionRects.isEmpty, let method = redactionMethod {
                // Filter rects that apply to this batch (in point coordinates)
                let batchImageHeight = CGFloat(linesToRender) * lineHeight
                let batchStartY = CGFloat(lineRange.location + lineRange.length - currentLine - linesToRender) * lineHeight

                NSLog("StreamingEncoder batch: currentLine=\(currentLine), linesToRender=\(linesToRender), batchStartY=\(batchStartY), batchImageHeight=\(batchImageHeight)")

                let batchRects = pointRedactionRects.filter { value in
                    let rect = value.rectValue
                    // Check if rect overlaps with this batch's Y range (in NSImage coords, Y=0 at bottom)
                    let overlaps = rect.maxY > batchStartY && rect.minY < batchStartY + batchImageHeight
                    NSLog("StreamingEncoder filter: rect=\(rect), overlaps=\(overlaps)")
                    return overlaps
                }.map { value -> NSValue in
                    // Adjust Y coordinates to be relative to this batch
                    var rect = value.rectValue
                    rect.origin.y -= batchStartY
                    NSLog("StreamingEncoder adjusted rect: \(rect)")
                    return NSValue(rect: rect)
                }

                NSLog("StreamingEncoder: applying \(batchRects.count) rects to batch")

                if !batchRects.isEmpty {
                    if let obscured = iTermAnnotatedScreenshot.applyObscuring(
                        to: processedImage,
                        imageRects: batchRects,
                        method: method
                    ) {
                        processedImage = obscured
                    }
                }
            }

            // Apply highlights if needed
            if let manager = redactionManager {
                let groupedHighlightRects = manager.groupedHighlightRects(for: textView, lineRange: batchRange)
                if !groupedHighlightRects.isEmpty {
                    if let highlighted = iTermAnnotatedScreenshot.applyHighlights(
                        to: processedImage,
                        groupedRects: groupedHighlightRects,
                        outlineColor: .systemYellow,
                        outlineWidth: 3,
                        shadowRadius: 20,
                        backgroundColor: backgroundColor
                    ) {
                        processedImage = highlighted
                    }
                }
            }

            // Extract pixel data from the image
            guard let cgImage = processedImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let pixelData = extractPixelData(from: cgImage) else {
                cancel()
                completeWith(nil)
                return
            }

            // Write rows to PNG
            let rowsInBatch = cgImage.height
            pixelData.withUnsafeBytes { rawPtr in
                guard let ptr = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                _ = writer.writeRows(ptr, count: rowsInBatch)
            }

            currentLine += linesToRender

            // Report progress
            let completed = currentLine - lineRange.location
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(completed, self?.lineRange.length ?? 0)
            }
        }

        // Finalize
        if cancelled {
            writer.cancel()
            completeWith(nil)
        } else {
            let success = writer.finalize()
            completeWith(success ? destinationURL : nil)
        }
    }

    private func extractPixelData(from cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        var pixelData = Data(count: totalBytes)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let success = pixelData.withUnsafeMutableBytes { rawPtr -> Bool in
            guard let ptr = rawPtr.baseAddress else { return false }

            guard let context = CGContext(
                data: ptr,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }

            // Draw the image (flipped because CGImage has Y=0 at top-left)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return success ? pixelData : nil
    }

    private func completeWith(_ url: URL?) {
        DispatchQueue.main.async { [weak self] in
            self?.encoding = false
            self?.onCompletion?(url)
        }
    }
}
