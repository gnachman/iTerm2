//
//  iTermScreenshotOnDemandPreview.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/26.
//

import AppKit

/// A custom NSView that renders terminal lines on-demand as they become visible.
/// Only visible tiles are kept in memory, allowing preview of very large line ranges
/// without holding the entire image in memory.
@objc(iTermScreenshotOnDemandPreview)
class iTermScreenshotOnDemandPreview: NSView {
    /// The text view to render from
    @objc weak var textView: PTYTextView?

    /// The range of lines to display (0-based buffer-relative)
    @objc var lineRange: NSRange = NSRange(location: 0, length: 0) {
        didSet {
            if lineRange != oldValue {
                invalidateIntrinsicContentSize()
                invalidateTileCache()
            }
        }
    }

    /// The redaction manager for applying redactions
    @objc var redactionManager: iTermScreenshotRedactionManager?

    /// The redaction method to use
    @objc var redactionMethod: iTermBlurredScreenshotObscureMethod?

    /// The session, used to render the background (configured image with its mode/blend,
    /// or solid color) behind the tiles so the preview matches the saved screenshot. The
    /// background is drawn one dirty-rect-sized slice at a time, mirroring the tiled
    /// content rendering, so no full-content bitmap is held. When nil, the terminal's
    /// background color is used.
    @objc weak var session: PTYSession? {
        didSet {
            needsDisplay = true
        }
    }

    /// Number of lines per tile for caching
    private let linesPerTile = 50

    /// Cache of rendered tiles (key: tile index, value: rendered image)
    private var tileCache = NSCache<NSNumber, NSImage>()

    /// Currently rendering tile indices (to avoid duplicate work)
    private var renderingTiles = Set<Int>()

    /// Generation counter for invalidation
    private var cacheGeneration: UInt64 = 0

    /// Line height from the terminal
    private var lineHeight: CGFloat {
        return textView?.lineHeight ?? 15.0
    }

    /// Width of the terminal content
    private var contentWidth: CGFloat {
        return textView?.frame.size.width ?? 400.0
    }

    override var isFlipped: Bool {
        return true
    }

    // Not opaque: the area outside the image content must let the checkerboard clip view
    // behind it show through. If this view were opaque, its layer would fill the gutter
    // (the region not covered by image content) with black.
    override var isOpaque: Bool {
        return false
    }

    override var intrinsicContentSize: NSSize {
        let height = CGFloat(lineRange.length) * lineHeight
        return NSSize(width: contentWidth, height: height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        // Keep the layer transparent and clipped to bounds so nothing outside the image
        // content paints over the checkerboard behind this view.
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        // Configure cache limits - keep ~20 tiles in memory
        tileCache.countLimit = 20
    }

    /// Invalidates the entire tile cache
    @objc func invalidateTileCache() {
        cacheGeneration &+= 1
        tileCache.removeAllObjects()
        renderingTiles.removeAll()
        needsDisplay = true
    }

    /// Draws the session background (the configured image with its mode/blend, or the
    /// solid background color) so the preview matches the saved screenshot.
    private func drawBackground(_ dirtyRect: NSRect) {
        // Render only the dirty region's slice (the view is flipped, so convert to the
        // background's bottom-left origin space) to keep memory bounded like the tiles.
        if let session = session, bounds.height > 0 {
            let sliceRect = NSRect(x: dirtyRect.origin.x,
                                   y: bounds.height - dirtyRect.maxY,
                                   width: dirtyRect.width,
                                   height: dirtyRect.height)
            if let slice = session.screenshotBackgroundSlice(for: sliceRect, ofTotalSize: bounds.size) {
                slice.draw(in: dirtyRect,
                           from: .zero,
                           operation: .copy,
                           fraction: 1.0,
                           respectFlipped: true,
                           hints: nil)
                return
            }
        }
        (textView?.colorMap?.color(forKey: kColorMapBackground) ?? .black).setFill()
        dirtyRect.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView = textView, lineRange.length > 0 else {
            drawBackground(dirtyRect)
            return
        }

        // Fill background first
        drawBackground(dirtyRect)

        // Calculate which tiles are visible
        let visibleTiles = tilesIntersecting(dirtyRect)

        for tileIndex in visibleTiles {
            let tileRect = rectForTile(tileIndex)

            // Check cache first
            if let cachedImage = tileCache.object(forKey: NSNumber(value: tileIndex)) {
                cachedImage.draw(in: tileRect,
                                from: .zero,
                                operation: .sourceOver,
                                fraction: 1.0,
                                respectFlipped: true,
                                hints: nil)
            } else {
                // Render tile synchronously for now (async would require more infrastructure)
                if let tileImage = renderTile(at: tileIndex) {
                    tileCache.setObject(tileImage, forKey: NSNumber(value: tileIndex))
                    tileImage.draw(in: tileRect,
                                  from: .zero,
                                  operation: .sourceOver,
                                  fraction: 1.0,
                                  respectFlipped: true,
                                  hints: nil)
                }
            }
        }
    }

    /// Returns the range of tile indices that intersect the given rect
    private func tilesIntersecting(_ rect: NSRect) -> Range<Int> {
        guard lineRange.length > 0 else { return 0..<0 }

        let totalTiles = (lineRange.length + linesPerTile - 1) / linesPerTile

        // In flipped coordinates, Y=0 is at top
        let firstVisibleLine = max(0, Int(floor(rect.minY / lineHeight)))
        let lastVisibleLine = min(lineRange.length - 1, Int(ceil(rect.maxY / lineHeight)))

        let firstTile = firstVisibleLine / linesPerTile
        let lastTile = min(totalTiles - 1, lastVisibleLine / linesPerTile)

        guard firstTile <= lastTile else { return 0..<0 }
        return firstTile..<(lastTile + 1)
    }

    /// Returns the rect for the given tile index (in view coordinates)
    private func rectForTile(_ tileIndex: Int) -> NSRect {
        let firstLineInTile = tileIndex * linesPerTile
        let linesInTile = min(linesPerTile, lineRange.length - firstLineInTile)

        return NSRect(
            x: 0,
            y: CGFloat(firstLineInTile) * lineHeight,
            width: contentWidth,
            height: CGFloat(linesInTile) * lineHeight
        )
    }

    /// Returns the line range for the given tile index (in buffer coordinates)
    private func lineRangeForTile(_ tileIndex: Int) -> NSRange {
        let firstLineInTile = tileIndex * linesPerTile
        let linesInTile = min(linesPerTile, lineRange.length - firstLineInTile)

        return NSRange(
            location: lineRange.location + firstLineInTile,
            length: linesInTile
        )
    }

    /// Renders a tile at the given index
    private func renderTile(at tileIndex: Int) -> NSImage? {
        guard let textView = textView else { return nil }

        let tileLineRange = lineRangeForTile(tileIndex)
        guard tileLineRange.length > 0 else { return nil }

        // Render the lines using the existing method
        guard var renderedImage = textView.renderLines(toImage: tileLineRange) else {
            return nil
        }

        // Apply redactions if any
        if let redactionManager = redactionManager, let method = redactionMethod {
            let redactionRects = redactionManager.imageRects(
                for: textView,
                lineRange: tileLineRange,
                annotationType: .redaction
            )

            if !redactionRects.isEmpty {
                if let obscuredImage = iTermAnnotatedScreenshot.applyObscuring(
                    to: renderedImage,
                    imageRects: redactionRects,
                    method: method
                ) {
                    renderedImage = obscuredImage
                }
            }

            // Apply highlights
            let groupedHighlightRects = redactionManager.groupedHighlightRects(
                for: textView,
                lineRange: tileLineRange
            )
            if !groupedHighlightRects.isEmpty {
                let bgColor = textView.colorMap?.color(forKey: kColorMapBackground) ?? .black
                if let highlightedImage = iTermAnnotatedScreenshot.applyHighlights(
                    to: renderedImage,
                    groupedRects: groupedHighlightRects,
                    outlineColor: .systemYellow,
                    outlineWidth: 3,
                    shadowRadius: 20,
                    backgroundColor: bgColor
                ) {
                    renderedImage = highlightedImage
                }
            }
        }

        return renderedImage
    }

    // MARK: - Mouse Events

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow hit testing for subviews (like the overlay)
        return super.hitTest(point)
    }
}
