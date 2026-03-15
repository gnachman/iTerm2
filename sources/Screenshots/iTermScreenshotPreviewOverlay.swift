//
//  iTermScreenshotPreviewOverlay.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/11/26.
//

import AppKit

/// Overlay view for the screenshot preview that handles selection interaction
/// and displays the current selection from the terminal.
@objc(iTermScreenshotPreviewOverlay)
class iTermScreenshotPreviewOverlay: NSView {
    /// The text view to sync selection with
    @objc weak var textView: PTYTextView?

    /// The line range currently being displayed in the preview
    @objc var lineRange: NSRange = NSRange(location: 0, length: 0)

    /// Callback when selection changes due to interaction in this view
    var onSelectionChanged: (() -> Void)?

    /// Character dimensions from the terminal
    @objc var charWidth: CGFloat = 1
    @objc var lineHeight: CGFloat = 1

    /// Selection rects to display (in image coordinates, Y=0 at top in flipped view)
    private var selectionRects: [NSRect] = []

    /// Is a drag in progress?
    private var isDragging = false

    /// Starting point of the drag (in terminal coordinates)
    private var dragStartCoord: (x: Int32, y: Int64)?

    override var isFlipped: Bool {
        // Use flipped coordinates to match image rendering (Y=0 at top)
        return true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Transparent background - we only draw selection highlights
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Update the selection display based on the terminal's current selection
    @objc func updateSelectionFromTextView() {
        guard let textView = textView,
              let selection = textView.selection,
              selection.hasSelection else {
            selectionRects = []
            needsDisplay = true
            return
        }

        var rects: [NSRect] = []

        // Get scrollback overflow to convert absolute coords to buffer-relative
        let overflow = textView.dataSource?.totalScrollbackOverflow() ?? 0

        // Get all sub-selections and convert to image coordinates
        for sub in selection.allSubSelections {
            let absRange = sub.absRange
            // Convert absolute line numbers to buffer-relative by subtracting overflow
            let startLine = Int(absRange.coordRange.start.y) - Int(overflow)
            let endLine = Int(absRange.coordRange.end.y) - Int(overflow)

            // Only include lines that are in our displayed range
            let displayStart = lineRange.location
            let displayEnd = lineRange.location + lineRange.length - 1

            guard startLine <= endLine else { continue }

            for line in startLine...endLine {
                guard line >= displayStart && line <= displayEnd else { continue }

                // Calculate columns for this line
                var startCol: Int
                var endCol: Int

                if sub.selectionMode == .kiTermSelectionModeBox {
                    // Live box selection - columns are from start.x to end.x
                    let x1 = Int(absRange.coordRange.start.x)
                    let x2 = Int(absRange.coordRange.end.x)
                    startCol = min(x1, x2)
                    endCol = max(x1, x2)
                } else if sub.originatedFromBoxSelection {
                    // Decomposed box selection - use stored column bounds
                    startCol = Int(sub.boxColumnBounds.location)
                    endCol = Int(sub.boxColumnBounds.location + sub.boxColumnBounds.length)
                } else {
                    // Regular selection
                    if line == startLine {
                        startCol = Int(absRange.coordRange.start.x)
                    } else {
                        startCol = 0
                    }

                    if line == endLine {
                        endCol = Int(absRange.coordRange.end.x)
                    } else {
                        endCol = Int(textView.dataSource?.width() ?? 80)
                    }
                }

                // Convert to image coordinates (flipped - Y=0 at top)
                let lineInImage = line - displayStart
                let rect = NSRect(
                    x: CGFloat(startCol) * charWidth,
                    y: CGFloat(lineInImage) * lineHeight,
                    width: CGFloat(endCol - startCol) * charWidth,
                    height: lineHeight
                )
                rects.append(rect)
            }
        }

        selectionRects = rects
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw selection highlights
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5).setFill()
        for rect in selectionRects {
            NSBezierPath(rect: rect).fill()
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard let textView = textView else { return }

        let locationInView = convert(event.locationInWindow, from: nil)
        let coord = imagePointToTerminalCoord(locationInView)

        // Use box selection mode if Option key is held
        let selectionMode: iTermSelectionMode = event.modifierFlags.contains(.option)
            ? .kiTermSelectionModeBox
            : .kiTermSelectionModeCharacter

        // Start a new selection
        textView.selection?.begin(
            at: coord,
            mode: selectionMode,
            resume: false,
            append: event.modifierFlags.contains(.shift)
        )

        dragStartCoord = (x: coord.x, y: coord.y)
        isDragging = true

        onSelectionChanged?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let textView = textView else { return }

        let locationInView = convert(event.locationInWindow, from: nil)
        let coord = imagePointToTerminalCoord(locationInView)

        // Extend the selection
        _ = textView.selection?.moveEndpoint(to: coord)

        onSelectionChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let textView = textView else { return }

        // End the live selection
        textView.selection?.endLive()

        isDragging = false
        dragStartCoord = nil

        onSelectionChanged?()
    }

    /// Convert a point in this view (image coordinates) to terminal absolute coordinates
    private func imagePointToTerminalCoord(_ point: NSPoint) -> VT100GridAbsCoord {
        // In flipped coordinates, Y=0 is at top (line 0 of displayed content)
        let lineInImage = Int(point.y / lineHeight)
        let column = Int(point.x / charWidth)

        // lineRange.location is buffer-relative, need to convert to absolute
        let overflow = textView?.dataSource?.totalScrollbackOverflow() ?? 0
        let bufferLine = lineRange.location + lineInImage

        // Clamp to valid range (in buffer coordinates)
        let clampedBufferLine = max(lineRange.location, min(bufferLine, lineRange.location + lineRange.length - 1))
        let clampedColumn = max(0, column)

        // Convert to absolute coordinates by adding overflow
        let absoluteLine = Int64(clampedBufferLine) + overflow

        return VT100GridAbsCoordMake(Int32(clampedColumn), absoluteLine)
    }
}
