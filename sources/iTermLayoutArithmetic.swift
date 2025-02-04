//
//  iTermLayoutArithmetic.swift
//  iTerm2
//
//  Created by George Nachman on 2/1/25.
//

extension iTermWindowType {
    var isEdgeSpanning: Bool {
        switch self {
        case .WINDOW_TYPE_TOP_PARTIAL, .WINDOW_TYPE_BOTTOM_PARTIAL, .WINDOW_TYPE_LEFT_PARTIAL, .WINDOW_TYPE_RIGHT_PARTIAL:
            false
        default:
            true
        }
    }
}

@objc(iTermLayoutArithmetic)
class LayoutArithmetic: NSObject {
    @objc
    static var margins: NSSize {
        NSSize(width: CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins)),
               height: CGFloat(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)))
    }
}

// Convert between different size types
/// Some terms used here:
///   * `window decoration size`: The sum of points used outside the tabview. Includes the toolbelt, title bar, window chrome, etc.
///   * `window size`: The size of a window's frame. includes everything in the window (title bar, etc.)
///   * `content size`: The size of a tab excluding scrollbars.
///   * `tab size`: Content size plus scrollbars
///   * `sessionView size`: tab size plus internal decorations
@objc
extension LayoutArithmetic {
    // MARK: - Compute sessionview size
    @objc
    static func sessionViewSizeFromGridSize(_ gridSize: VT100GridSize,
                                            cellSize: NSSize,
                                            hasScrollbar: Bool,
                                            scrollerStyle: NSScroller.Style,
                                            internalDecorationSize: NSSize) -> NSSize {
        return tabSizeFromGridSize(gridSize,
                                   cellSize: cellSize,
                                   hasScrollbar: hasScrollbar,
                                   scrollerStyle: scrollerStyle) + internalDecorationSize
    }

    // MARK: - Compute tab size
    @objc
    static func tabSizeFromGridSize(_ gridSize: VT100GridSize,
                                           cellSize: NSSize,
                                           hasScrollbar: Bool,
                                           scrollerStyle: NSScroller.Style) -> NSSize {
        let contentSize = contentSizeFromGridSize(gridSize,
                                                  cellSize: cellSize)
        return tabSizeFromContentSize(contentSize,
                                      hasScrollbar: hasScrollbar,
                                      scrollerStyle: scrollerStyle)
    }

    @objc
    static func tabSizeFromWindowSize(_ windowSize: NSSize,
                                      decorationSize: NSSize,
                                      internalDecorationSize: NSSize) -> NSSize {
        return windowSize - decorationSize - internalDecorationSize
    }

    @objc(tabSizeFromContentSize:hasScrollbar:scrollerStyle:)
    static func tabSizeFromContentSize(_ contentSize: NSSize,
                                       hasScrollbar: Bool,
                                       scrollerStyle: NSScroller.Style) -> NSSize {
        PTYScrollView.frameSize(forContentSize: contentSize,
                                horizontalScrollerClass: nil,
                                verticalScrollerClass: hasScrollbar ? PTYScroller.self : nil,
                                borderType: .noBorder,
                                controlSize: .regular,
                                scrollerStyle: scrollerStyle)
    }

    // MARK: - Compute window size

    @objc
    static func windowSizeFromGridSize(_ gridSize: VT100GridSize,
                                       cellSize: NSSize,
                                       decorationSize: NSSize,
                                       internalDecorationSize: NSSize) -> NSSize {
        return margins * 2.0 + gridSize * cellSize + decorationSize + internalDecorationSize
    }

    @objc
    static func windowSizeFromTabSize(_ tabSize: NSSize,
                                      decorationSize: NSSize,
                                      internalDecorationSize: NSSize) -> NSSize {
        return tabSize + decorationSize + internalDecorationSize
    }

    // MARK: - Compute grid size

    @objc(gridSizeFromContentSize:cellSize:)
    static func gridSizeFromContentSize(_ contentSize: NSSize,
                                        cellSize: NSSize) -> VT100GridSize {
        let temp = (contentSize - margins * 2) / max(cellSize, NSSize(width: 1.0, height: 1.0))
        return VT100GridSize(width: Int32(clamping: temp.width),
                             height: Int32(clamping: temp.height))
    }

    // MARK: - Compute content size

    @objc(contentSizeFromGridSize:cellSize:)
    static func contentSizeFromGridSize(_ gridSize: VT100GridSize,
                                       cellSize: NSSize) -> NSSize {
        return gridSize * cellSize + margins * 2
    }

    @objc
    static func contentSizeFromTabSize(_ tabSize: NSSize,
                                       hasScrollbar: Bool,
                                       scrollerStyle: NSScroller.Style) -> NSSize {
        return NSScrollView.contentSize(forFrameSize: tabSize,
                                        horizontalScrollerClass: nil,
                                        verticalScrollerClass: hasScrollbar ? PTYScroller.self : nil,
                                        borderType: .noBorder,
                                        controlSize: .regular,
                                        scrollerStyle: scrollerStyle)
    }
}

// MARK: - Frame Canonicalization
extension LayoutArithmetic {
    private enum Alignment {
        case left
        case right
        case top
        case bottom

        func sizeByAdjustingPerpindicularDimension(original: NSSize,
                                                   desired: NSSize,
                                                   maximum: NSSize) -> NSSize {
            switch self {
            case .top, .bottom:
                NSSize(width: original.width,
                       height: min(desired.height, maximum.height))
            case .left, .right:
                NSSize(width: min(desired.width, maximum.width),
                       height: original.height)
            }
        }

        func sizeByAdjustingParallelDimension(original: NSSize,
                                              desired: NSSize,
                                              maximum: NSSize) -> NSSize {
            switch self {
            case .top, .bottom:
                NSSize(width: min(desired.width, maximum.width),
                       height: original.height)
            case .left, .right:
                NSSize(width: original.width,
                       height: min(desired.height, maximum.height))
            }
        }

        func perpindicularSize(_ size: NSSize) -> CGFloat {
            switch self {
            case .left, .right:
                size.width
            case .top, .bottom:
                size.height
            }
        }

        func perpindicularSize(_ size: VT100GridSize) -> Int32 {
            switch self {
            case .left, .right:
                size.width
            case .top, .bottom:
                size.height
            }
        }

        func parallelSize(_ size: NSSize) -> CGFloat {
            switch self {
            case .left, .right:
                size.height
            case .top, .bottom:
                size.width
            }
        }

        func parallelSize(_ size: VT100GridSize) -> Int32 {
            switch self {
            case .left, .right:
                size.height
            case .top, .bottom:
                size.width
            }
        }

        func frameByCenteringParallel(frame: NSRect, enclosingFrame: NSRect) -> NSRect {
            switch self {
            case .top, .bottom:
                iTermRectCenteredHorizontallyWithinRect(frame, enclosingFrame)
            case .left, .right:
                iTermRectCenteredVerticallyWithinRect(frame, enclosingFrame)
            }
        }

        func frameByPerpindicularFilling(frame: NSRect, enclosingContainer: NSRect) -> NSRect {
            switch self {
            case .top, .bottom:
                return NSRect(x: enclosingContainer.minX,
                              y: frame.minY,
                              width: enclosingContainer.width,
                              height: frame.height)
            case .left, .right:
                return NSRect(x: frame.minX,
                              y: enclosingContainer.minY,
                              width: frame.width,
                              height: enclosingContainer.height)
            }
        }

        func perpindicularOrigin(screenVisibleFrame: NSRect, frame: NSRect) -> NSPoint {
            switch self {
            case .top:
                return NSPoint(x: frame.minX,
                               y: screenVisibleFrame.maxY - frame.height)
            case .bottom:
                return NSPoint(x: frame.minX,
                               y: screenVisibleFrame.minY)
            case .left:
                return NSPoint(x: screenVisibleFrame.minX,
                               y: frame.minY)
            case .right:
                return NSPoint(x: screenVisibleFrame.maxX - frame.width,
                               y: frame.minY)
            }
        }
    }

    private static func canonicalFrame(alignment: Alignment,
                                       desiredGridSize: VT100GridSize,
                                       preserveSize: Bool,
                                       frame: inout NSRect,
                                       screenVisibleFrame: NSRect,
                                       windowSizeForDesiredGridSize: NSSize,
                                       edgeSpanning: Bool,
                                       screenVisibleFrameIgnoringHiddenDock: NSRect) -> NSRect {
        DLog("alignment=\(alignment) desiredGridSize=\(desiredGridSize.debugDescription)")
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of rows/columns, grow it.
            let desiredSize = if alignment.perpindicularSize(desiredGridSize) > 0 {
                windowSizeForDesiredGridSize
            } else {
                frame.size
            }
            frame.size = alignment.sizeByAdjustingPerpindicularDimension(
                original: frame.size,
                desired: desiredSize,
                maximum: screenVisibleFrame.size)
        }
        if !edgeSpanning {
            if !preserveSize {
                frame.size = alignment.sizeByAdjustingParallelDimension(
                    original: frame.size,
                    desired: frame.size,
                    maximum: screenVisibleFrameIgnoringHiddenDock.size)
            }
            frame = alignment.frameByCenteringParallel(
                frame: frame,
                enclosingFrame: screenVisibleFrameIgnoringHiddenDock)
        } else {
            frame = alignment.frameByPerpindicularFilling(
                frame: frame,
                enclosingContainer: screenVisibleFrameIgnoringHiddenDock)
        }
        frame.origin = alignment.perpindicularOrigin(screenVisibleFrame: screenVisibleFrameIgnoringHiddenDock,
                                                       frame: frame)

        DLog("Canonical frame for \(alignment)-of-screen window is \(frame)")
        return frame
    }

    @objc
    static func canonicalFrame(windowType: iTermWindowType,
                               desiredGridSize: VT100GridSize,
                               preserveSize: Bool,
                               screenFrame: NSRect,
                               screenVisibleFrame: NSRect,
                               screenVisibleFrameIgnoringHiddenDock: NSRect,
                               originalFrame: NSRect,
                               cellSize: NSSize,
                               windowDecorationSize: NSSize,
                               internalDecorationSize: NSSize,
                               traditionalFrame: NSRect) -> NSRect {
        let edgeSpanning = windowType.isEdgeSpanning
        let windowSizeForDesiredGridSize = windowSizeFromGridSize(desiredGridSize,
                                                                  cellSize: cellSize,
                                                                  decorationSize: windowDecorationSize,
                                                                  internalDecorationSize: internalDecorationSize)
        var frame = originalFrame
        switch windowType {
        case .WINDOW_TYPE_TOP_PARTIAL, .WINDOW_TYPE_TOP:
            return canonicalFrame(alignment: .top,
                                  desiredGridSize: desiredGridSize,
                                  preserveSize: preserveSize,
                                  frame: &frame,
                                  screenVisibleFrame: screenVisibleFrame,
                                  windowSizeForDesiredGridSize: windowSizeForDesiredGridSize,
                                  edgeSpanning: edgeSpanning,
                                  screenVisibleFrameIgnoringHiddenDock: screenVisibleFrameIgnoringHiddenDock)
        case .WINDOW_TYPE_BOTTOM_PARTIAL, .WINDOW_TYPE_BOTTOM:
            return canonicalFrame(alignment: .bottom,
                                  desiredGridSize: desiredGridSize,
                                  preserveSize: preserveSize,
                                  frame: &frame,
                                  screenVisibleFrame: screenVisibleFrame,
                                  windowSizeForDesiredGridSize: windowSizeForDesiredGridSize,
                                  edgeSpanning: edgeSpanning,
                                  screenVisibleFrameIgnoringHiddenDock: screenVisibleFrameIgnoringHiddenDock)

        case .WINDOW_TYPE_LEFT_PARTIAL, .WINDOW_TYPE_LEFT:
            return canonicalFrame(alignment: .left,
                                  desiredGridSize: desiredGridSize,
                                  preserveSize: preserveSize,
                                  frame: &frame,
                                  screenVisibleFrame: screenVisibleFrame,
                                  windowSizeForDesiredGridSize: windowSizeForDesiredGridSize,
                                  edgeSpanning: edgeSpanning,
                                  screenVisibleFrameIgnoringHiddenDock: screenVisibleFrameIgnoringHiddenDock)

        case .WINDOW_TYPE_RIGHT_PARTIAL, .WINDOW_TYPE_RIGHT:
            return canonicalFrame(alignment: .right,
                                  desiredGridSize: desiredGridSize,
                                  preserveSize: preserveSize,
                                  frame: &frame,
                                  screenVisibleFrame: screenVisibleFrame,
                                  windowSizeForDesiredGridSize: windowSizeForDesiredGridSize,
                                  edgeSpanning: edgeSpanning,
                                  screenVisibleFrameIgnoringHiddenDock: screenVisibleFrameIgnoringHiddenDock)

        case .WINDOW_TYPE_MAXIMIZED, .WINDOW_TYPE_COMPACT_MAXIMIZED:
            DLog("Window type = MAXIMIZED or COMPACT_MAXIMIZED")
            return screenVisibleFrameIgnoringHiddenDock

        case .WINDOW_TYPE_NORMAL, .WINDOW_TYPE_NO_TITLE_BAR, .WINDOW_TYPE_COMPACT, .WINDOW_TYPE_LION_FULL_SCREEN, .WINDOW_TYPE_ACCESSORY:
            DLog("Window type = NORMAL, NO_TITLE_BAR, WINDOW_TYPE_COMPACT, WINDOW_TYPE_ACCSSORY, or LION_FULL_SCREEN")
            return frame

        case .WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            DLog("Window type = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN")
            if screenFrame.width > 0 {
                return traditionalFrame
            }
            return .zero

        @unknown default:
            it_fatalError("\(windowType) unknown")
        }
    }
}

// MARK: - Comparison

// Returns the number of points over or under the an ideal size.
// Will never exceed +/- cell size/2.
// Example: If the line height is 10 (no margin) and you give a proposed size of 101,
// 1 is returned. If you give a proposed size of 99, -1 is returned.
extension LayoutArithmetic {
    @objc
    static func pointError(forSize proposedSize: NSSize,
                           cellSize: NSSize,
                           internalDecorationSize:  NSSize) -> NSSize {
        let temp = (proposedSize - internalDecorationSize - margins * 2)
            .truncatingRemainder(dividingBy: cellSize)
            .map { $0.isNaN ? 0.0 : $0 }
        return zip(temp, cellSize).map {
            $0 > $1 / 2 ? $0 - $1 : $0
        }
    }
}

// MARK: - PTYTextView utilities
extension LayoutArithmetic {
    @objc
    static func frameInTextViewForCoord(_ coord: VT100GridCoord,
                                        cellSize: NSSize) -> NSRect {
        return NSRect(x: max(0, floor(margins.width + CGFloat(coord.x) * cellSize.width)),
                      y: max(0, CGFloat(coord.y) * cellSize.height),
                      width: cellSize.width,
                      height: cellSize.height)
    }

    @objc
    static func widthFillingFrameInTextViewForGridRect(_ gridRect: VT100GridRect,
                                                       boundsWidth: CGFloat,
                                                       cellSize:NSSize) -> NSRect {
        let originFrame = frameInTextViewForCoord(gridRect.origin, cellSize: cellSize)
        return NSRect(x: originFrame.minX,
                      y: originFrame.minY,
                      width: boundsWidth - margins.width * 2,
                      height: CGFloat(gridRect.size.height) * cellSize.height)
    }

    @objc
    static func frameInTextViewForGridRect(_ gridRect: VT100GridRect,
                                           cellSize: NSSize) -> NSRect {
        return NSRect(x: margins.width + CGFloat(gridRect.origin.x) * cellSize.width,
                      y: CGFloat(gridRect.origin.y) * cellSize.height,
                      width: cellSize.width * CGFloat(gridRect.size.width),
                      height: cellSize.height * CGFloat(gridRect.size.height))
    }

    @objc
    static func frameInTextViewForCoordRange(_ coordRange: VT100GridCoordRange,
                                             width: Int32,
                                             cellSize: NSSize) -> NSRect {
        let startTopLeft = frameInTextViewForCoord(coordRange.start, cellSize: cellSize).origin
        let endBottomRight = frameInTextViewForCoord(coordRange.end + VT100GridSize(width: 0, height: 1),
                                                     cellSize: cellSize).origin

        let minX = if startTopLeft.x <= endBottomRight.x {
            startTopLeft.x
        } else {
            margins.width
        }

        let maxX = if coordRange.start.y == coordRange.end.y {
            endBottomRight.x
        } else {
            margins.width + CGFloat(width) * cellSize.width
        }
        return NSRect(x: minX,
                      y: startTopLeft.y,
                      width: maxX - minX,
                      height: endBottomRight.y - startTopLeft.y)
    }

    @objc
    static func gridRect(visibleRect: NSRect,
                         excess: CGFloat,
                         cellSize: NSSize,
                         maxWidth: Int32) -> VT100GridRect {
        let lastVisibleRow = (Int32(clamping: visibleRect.maxY - excess)) / Int32(clamping: cellSize.height)
        let numberOfVisibleRows = Int32(clamping:visibleRect.height - excess - margins.height) / Int32(clamping: cellSize.height)

        return VT100GridRect(
            origin: VT100GridCoord(
                x: Int32(clamping: (max(0.0, visibleRect.minX - margins.width)) / cellSize.width),
                y: Int32(clamping: lastVisibleRow - numberOfVisibleRows)),
            size: VT100GridSize(
                width: min(maxWidth, Int32(clamping: (visibleRect.width - margins.width * 2) / cellSize.width)),
                height: numberOfVisibleRows))
    }

    @objc
    static func firstVisibleRowInTextView(documentVisibleRect: NSRect,  // enclosingScrollView.documentVisibleRect
                                          cellSize:NSSize) -> Int32 {
        return Int32(clamping: documentVisibleRect.minY / cellSize.height)
    }

    @objc
    static func frameInTextViewForLastVisibleLine(visibleRect: NSRect,
                                                  excess: CGFloat,
                                                  numberOfLines: Int32,
                                                  numberOfIMELines: Int32,
                                                  cellSize: NSSize) -> NSRect {
        var result = visibleRect
        result.origin.y = CGFloat(numberOfLines + numberOfIMELines - 1) * cellSize.height + excess
        result.size.height = cellSize.height
        return result
    }

    @objc(frameInTextViewForAbsLineRange:cumulativeOverflow:cellSize:viewWidth:)
    static func frameInTextViewForAbsLineRange(range: NSRange,
                                               cumulativeOverflow: Int64,
                                               cellSize: NSSize,
                                               viewWidth: CGFloat) -> NSRect {
        return NSRect(x: 0,
                      y: CGFloat(Int64(range.location) - cumulativeOverflow) * cellSize.height - margins.height,
                      width: viewWidth,
                      height: cellSize.height * CGFloat(range.length))
    }

    @objc(frameInTextViewForLineRange:cellSize:viewWidth:)
    static func frameInTextViewForLineRange(range: NSRange,
                                            cellSize: NSSize,
                                            viewWidth: CGFloat) -> NSRect {
        return frameInTextViewForAbsLineRange(range: range,
                                              cumulativeOverflow: 0,
                                              cellSize: cellSize,
                                              viewWidth: viewWidth)
    }

    @objc(frameInTextViewOfLinesAroundLine:radius:cellSize:visibleRect:)
    static func frameInTextViewOfLines(aroundLine line: Int32,
                                       radius: Int32,
                                       cellSize: NSSize,
                                       bounds: NSRect) -> NSRect {
        let range = NSRange(from: max(0, Int(line - radius)),
                            to: Int(line + radius + 1))
        return frameInTextViewForLineRange(range: range,
                                           cellSize: cellSize,
                                           viewWidth: bounds.width).intersection(bounds)
    }

    // NOTE: This returns a rect that can go past the bottom of the actual visible rect. This is
    // bugwards compatible with the previous implementation.
    @objc(frameInTextViewExcludingTopMargin:fromLine:cellSize:visibleRect:)
    static func frameInTextView(excludingTopMargin excludeTopMargin: Bool,
                                fromLine line: Int32,
                                cellSize: NSSize,
                                visibleRect: NSRect) -> NSRect {
        var rect = visibleRect
        rect.origin.y = CGFloat(line) * cellSize.height
        if excludeTopMargin {
            rect.size.height -= margins.height
        } else {
            rect.origin.y -= margins.height
        }
        return rect

    }

    @objc
    static func textViewExcessHeight(forContentSize contentSize: NSSize,
                                     cellSize: NSSize) -> CGFloat {
        let vmargin = margins.height
        var visibleRectExcludingTopAndBottomMargins = NSRect(origin: .zero, size: contentSize)
        visibleRectExcludingTopAndBottomMargins.size.height -= vmargin * 2  // Height without top and bottom margins.
        let rows = Int32(clamping: visibleRectExcludingTopAndBottomMargins.size.height / cellSize.height)
        let heightOfTextRows = CGFloat(rows) * cellSize.height
        let bottomMarginHeight = vmargin
        let visibleHeightExceptTopMargin = visibleRectExcludingTopAndBottomMargins.height + bottomMarginHeight
        return max(visibleHeightExceptTopMargin - heightOfTextRows,
                   bottomMarginHeight)  // Never have less than margins.height excess, but it can be more (if another tab has a bigger font)

    }

    @objc(heightForTextViewLineCount:excess:cellSize:)
    static func heightForTextViewLines(count: Int32,
                                       excess: CGFloat,
                                       cellSize: NSSize) -> CGFloat {
        return CGFloat(count) * cellSize.height + excess
    }

    @objc
    static func textViewLineAt(yCoordinate: CGFloat,
                               cellSize: NSSize) -> Int32 {
        return Int32(clamping: yCoordinate / CGFloat(cellSize.height))
    }

    @objc(gridCoordForTextViewPointWithPoint:cellSize:roundUp:upperBound:)
    static func gridCoordForTextViewPoint(_ point: NSPoint,
                                         cellSize: NSSize,
                                          roundUp: Bool,
                                          upperBound: Int32) -> VT100GridCoord {
        let fractionalLine = point.y / cellSize.height
        return VT100GridCoord(x: Int32(clamping: (point.x - margins.width) / cellSize.width),
                              y: min(upperBound, max(0, Int32(clamping:  roundUp ? ceil(fractionalLine) : fractionalLine))))

    }

    @objc
    static func coordOffsetInTextView(fromPoint originPoint: NSPoint,
                                      toPoint point: NSPoint,
                                      cellSize: NSSize,
                                      maxCoord: VT100GridCoord) -> VT100GridCoord {
        return min(maxCoord,
                   VT100GridCoord(x: Int32(clamping: max(0.0, point.x - originPoint.x) / cellSize.width),
                                  y: Int32(clamping: max(0.0, point.y - originPoint.y) / cellSize.height)))

    }

    @objc
    static func coordForPoint(_ locationInTextView: NSPoint,
                              allowRightMarginOverflow: Bool,
                              cellSize: NSSize,
                              gridSize: VT100GridSize,
                              numberOfLines: Int32,
                              horizontalFraction: CGFloat,
                              origin: NSPoint) -> VT100GridCoord {
        let xLimit = allowRightMarginOverflow ? gridSize.width : gridSize.width - 1
        let floatX = (locationInTextView.x + origin.x - margins.width + cellSize.width * horizontalFraction) / cellSize.width
        let x = min(xLimit, max(0, Int32(clamping: floatX)))

        let floatY = (locationInTextView.y + origin.y) / cellSize.height
        let y = min(numberOfLines - 1, Int32(clamping: floatY))
        return VT100GridCoord(x: x, y: y)
    }
}
