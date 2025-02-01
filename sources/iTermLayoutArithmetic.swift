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

    static func windowSize(cellSize: NSSize,
                           windowDecorationSize: NSSize,
                           gridSize: VT100GridSize) -> NSSize {
        return NSSize(width: cellSize.width * CGFloat(gridSize.width) + 2 * margins.width + windowDecorationSize.width + iTermScrollbarWidth(),
                      height: cellSize.height * CGFloat(gridSize.height) + 2 * margins.height + windowDecorationSize.height)
    }

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
                               traditionalFrame: NSRect) -> NSRect {
        let edgeSpanning = windowType.isEdgeSpanning
        let windowSizeForDesiredGridSize = windowSize(cellSize: cellSize,
                                                      windowDecorationSize: windowDecorationSize,
                                                      gridSize: desiredGridSize)
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
