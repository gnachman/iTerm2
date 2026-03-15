//
//  iTermScreenshotLineRangeView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/6/26.
//

import AppKit

/// A minimap-style view for selecting a range of lines for screenshot capture.
/// Shows a vertical representation of all terminal content with draggable handles.
class iTermScreenshotLineRangeView: NSView {

    // MARK: - Properties

    /// Total number of lines in the terminal (scrollback + visible)
    var totalLines: Int = 100 {
        didSet {
            if totalLines != oldValue {
                clampRange()
                needsDisplay = true
            }
        }
    }

    /// Number of lines currently visible on screen
    var visibleLines: Int = 24 {
        didSet {
            if visibleLines != oldValue {
                needsDisplay = true
            }
        }
    }

    /// First visible line index (for showing current scroll position)
    var firstVisibleLine: Int = 0 {
        didSet {
            if firstVisibleLine != oldValue {
                needsDisplay = true
            }
        }
    }

    /// Start of selected range (0-based, inclusive)
    var rangeStart: Int = 0 {
        didSet {
            if rangeStart != oldValue {
                clampRange()
                needsDisplay = true
                onRangeChanged?(rangeStart, rangeEnd)
            }
        }
    }

    /// End of selected range (0-based, inclusive)
    var rangeEnd: Int = 23 {
        didSet {
            if rangeEnd != oldValue {
                clampRange()
                needsDisplay = true
                onRangeChanged?(rangeStart, rangeEnd)
            }
        }
    }

    /// Callback when the range changes (called during drag - use for lightweight UI updates)
    var onRangeChanged: ((Int, Int) -> Void)?

    /// Callback when dragging ends (use for expensive operations like re-rendering preview)
    var onRangeChangeEnded: ((Int, Int) -> Void)?

    /// Pre-rendered minimap image from iTermTextDrawingHelper
    var minimapImage: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    /// Lines that have selection (absolute line numbers)
    var selectedLines: Set<Int> = [] {
        didSet {
            needsDisplay = true
        }
    }

    // MARK: - Private Properties

    private let handleHeight: CGFloat = 8
    private let handleColor = NSColor.controlAccentColor
    private let selectedRangeColor = NSColor.controlAccentColor.withAlphaComponent(0.3)
    private let visibleRangeColor = NSColor.systemGray.withAlphaComponent(0.2)
    private let outsideRangeColor = NSColor.black.withAlphaComponent(0.5)

    private enum DragMode {
        case none
        case topHandle
        case bottomHandle
        case range
    }

    private var dragMode: DragMode = .none
    private var dragStartY: CGFloat = 0
    private var dragStartRangeStart: Int = 0
    private var dragStartRangeEnd: Int = 0
    private var trackingArea: NSTrackingArea?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursorForLocation(convert(event.locationInWindow, from: nil))
    }

    private func updateCursorForLocation(_ location: NSPoint) {
        let contentRect = bounds.insetBy(dx: 2, dy: 2)
        let (startY, endY) = yRangeForLines(rangeStart, rangeEnd, in: contentRect)

        // Check if over top handle area (including above when handles overlap)
        let handleHitZone = handleHeight * 1.5
        let overTopHandle = location.y >= startY - handleHitZone && location.y <= startY + handleHitZone
        let overBottomHandle = location.y >= endY - handleHitZone && location.y <= endY + handleHitZone

        if overTopHandle || overBottomHandle {
            NSCursor.resizeUpDown.set()
        } else if location.y < startY && location.y > endY {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard totalLines > 0 else { return }

        let bounds = self.bounds
        let contentRect = bounds.insetBy(dx: 2, dy: 2)

        // Background
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        // Draw terminal content (minimap)
        drawTerminalContent(in: contentRect)

        // Draw selection highlight
        drawSelection(in: contentRect)

        // Draw visible range indicator
        drawVisibleRange(in: contentRect)

        // Draw outside-selection overlay (darkened areas)
        drawOutsideSelectionOverlay(in: contentRect)

        // Draw selected range border
        drawSelectedRange(in: contentRect)

        // Draw handles
        drawHandles(in: contentRect)
    }

    private func drawTerminalContent(in rect: NSRect) {
        guard let image = minimapImage else {
            // If no minimap image, just fill with a neutral gray
            NSColor.darkGray.setFill()
            NSBezierPath(rect: rect).fill()
            return
        }

        // Draw the pre-rendered minimap image
        image.draw(in: rect,
                   from: NSZeroRect,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }

    private func drawSelection(in rect: NSRect) {
        guard !selectedLines.isEmpty else { return }

        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.6).setFill()

        let lineHeight = rect.height / CGFloat(totalLines)

        for line in selectedLines {
            // Y position: line 0 is at the top
            let y = rect.maxY - CGFloat(line + 1) * lineHeight
            let lineRect = NSRect(x: rect.minX, y: y, width: rect.width, height: max(1, lineHeight))
            NSBezierPath(rect: lineRect).fill()
        }
    }

    private func drawVisibleRange(in rect: NSRect) {
        let (startY, endY) = yRangeForLines(firstVisibleLine, firstVisibleLine + visibleLines - 1, in: rect)
        let visibleRect = NSRect(x: rect.minX, y: endY, width: rect.width, height: startY - endY)

        // Draw a subtle border around visible area
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let borderPath = NSBezierPath(rect: visibleRect)
        borderPath.lineWidth = 1
        borderPath.stroke()
    }

    private func drawOutsideSelectionOverlay(in rect: NSRect) {
        let (rangeStartY, rangeEndY) = yRangeForLines(rangeStart, rangeEnd, in: rect)

        // Top overlay (above selection)
        if rangeStartY < rect.maxY {
            let topRect = NSRect(x: rect.minX, y: rangeStartY, width: rect.width, height: rect.maxY - rangeStartY)
            outsideRangeColor.setFill()
            NSBezierPath(rect: topRect).fill()
        }

        // Bottom overlay (below selection)
        if rangeEndY > rect.minY {
            let bottomRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rangeEndY - rect.minY)
            outsideRangeColor.setFill()
            NSBezierPath(rect: bottomRect).fill()
        }
    }

    private func drawSelectedRange(in rect: NSRect) {
        let (startY, endY) = yRangeForLines(rangeStart, rangeEnd, in: rect)
        let selectedRect = NSRect(x: rect.minX, y: endY, width: rect.width, height: startY - endY)

        // Border around selected range
        handleColor.setStroke()
        let borderPath = NSBezierPath(rect: selectedRect)
        borderPath.lineWidth = 2
        borderPath.stroke()
    }

    private func drawHandles(in rect: NSRect) {
        let (startY, endY) = yRangeForLines(rangeStart, rangeEnd, in: rect)

        // Top handle
        let topHandleRect = NSRect(x: rect.minX, y: startY - handleHeight / 2,
                                    width: rect.width, height: handleHeight)
        drawHandle(in: topHandleRect, isTop: true)

        // Bottom handle
        let bottomHandleRect = NSRect(x: rect.minX, y: endY - handleHeight / 2,
                                       width: rect.width, height: handleHeight)
        drawHandle(in: bottomHandleRect, isTop: false)
    }

    private func drawHandle(in rect: NSRect, isTop: Bool) {
        // Draw handle background
        handleColor.setFill()
        let barRect = NSRect(x: rect.minX + 2, y: rect.midY - 2,
                             width: rect.width - 4, height: 4)
        NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()

        // Draw grip lines
        NSColor.white.withAlphaComponent(0.8).setStroke()
        for i in -1...1 {
            let lineY = rect.midY + CGFloat(i) * 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX - 6, y: lineY))
            path.line(to: NSPoint(x: rect.midX + 6, y: lineY))
            path.lineWidth = 1
            path.stroke()
        }
    }

    // MARK: - Coordinate Conversion

    private func yRangeForLines(_ startLine: Int, _ endLine: Int, in rect: NSRect) -> (startY: CGFloat, endY: CGFloat) {
        guard totalLines > 0 else { return (rect.maxY, rect.minY) }

        let lineHeight = rect.height / CGFloat(totalLines)
        // Lines are numbered from top (0) to bottom
        // Y coordinates go from bottom (0) to top (height)
        let startY = rect.maxY - CGFloat(startLine) * lineHeight
        let endY = rect.maxY - CGFloat(endLine + 1) * lineHeight
        return (startY, endY)
    }

    private func lineForY(_ y: CGFloat, in rect: NSRect) -> Int {
        guard totalLines > 0 else { return 0 }

        let lineHeight = rect.height / CGFloat(totalLines)
        let line = Int((rect.maxY - y) / lineHeight)
        return max(0, min(totalLines - 1, line))
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let contentRect = bounds.insetBy(dx: 2, dy: 2)
        let (startY, endY) = yRangeForLines(rangeStart, rangeEnd, in: contentRect)

        let distToTop = abs(location.y - startY)
        let distToBottom = abs(location.y - endY)
        let handleHitZone = handleHeight * 1.5

        // When handles overlap or are close, decide based on click position:
        // - Clicking above the midpoint grabs the top handle
        // - Clicking below the midpoint grabs the bottom handle
        let handleMidpoint = (startY + endY) / 2
        let handlesOverlap = abs(startY - endY) < handleHeight * 2

        if handlesOverlap {
            // Handles overlap - use position relative to midpoint
            if location.y >= handleMidpoint && distToTop < handleHitZone * 2 {
                dragMode = .topHandle
            } else if location.y < handleMidpoint && distToBottom < handleHitZone * 2 {
                dragMode = .bottomHandle
            } else {
                dragMode = .none
            }
        } else if distToTop < handleHitZone {
            dragMode = .topHandle
        } else if distToBottom < handleHitZone {
            dragMode = .bottomHandle
        } else if location.y < startY && location.y > endY {
            dragMode = .range
            NSCursor.closedHand.set()
        } else {
            dragMode = .none
        }

        dragStartY = location.y
        dragStartRangeStart = rangeStart
        dragStartRangeEnd = rangeEnd
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragMode != .none else { return }

        let location = convert(event.locationInWindow, from: nil)
        let contentRect = bounds.insetBy(dx: 2, dy: 2)
        let currentLine = lineForY(location.y, in: contentRect)
        let deltaLines = currentLine - lineForY(dragStartY, in: contentRect)

        // Calculate new values without triggering callbacks yet
        var newStart = rangeStart
        var newEnd = rangeEnd

        switch dragMode {
        case .topHandle:
            newStart = max(0, min(rangeEnd - 1, currentLine))
        case .bottomHandle:
            newEnd = max(rangeStart + 1, min(totalLines - 1, currentLine))
        case .range:
            let rangeSize = dragStartRangeEnd - dragStartRangeStart
            let proposedStart = dragStartRangeStart + deltaLines
            let proposedEnd = dragStartRangeEnd + deltaLines

            if proposedStart >= 0 && proposedEnd < totalLines {
                newStart = proposedStart
                newEnd = proposedEnd
            } else if proposedStart < 0 {
                newStart = 0
                newEnd = rangeSize
            } else {
                newEnd = totalLines - 1
                newStart = totalLines - 1 - rangeSize
            }
        case .none:
            return
        }

        // Only update if values actually changed
        let startChanged = newStart != rangeStart
        let endChanged = newEnd != rangeEnd

        if startChanged || endChanged {
            // Temporarily disable callbacks during batch update
            let savedCallback = onRangeChanged
            onRangeChanged = nil

            if startChanged { rangeStart = newStart }
            if endChanged { rangeEnd = newEnd }

            onRangeChanged = savedCallback
            // Call callback once after both values are set
            onRangeChanged?(rangeStart, rangeEnd)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode != .none {
            // Notify that dragging has ended - use for expensive operations
            onRangeChangeEnded?(rangeStart, rangeEnd)
            // Restore cursor based on current position
            updateCursorForLocation(convert(event.locationInWindow, from: nil))
        }
        dragMode = .none
    }

    // MARK: - Helpers

    private func clampRange() {
        rangeStart = max(0, min(totalLines - 1, rangeStart))
        rangeEnd = max(rangeStart, min(totalLines - 1, rangeEnd))
    }

    /// Set the range to show the currently visible lines
    func selectVisibleRange() {
        rangeStart = firstVisibleLine
        rangeEnd = min(totalLines - 1, firstVisibleLine + visibleLines - 1)
    }

    /// Set the range to show all lines
    func selectAllLines() {
        rangeStart = 0
        rangeEnd = totalLines - 1
    }
}
