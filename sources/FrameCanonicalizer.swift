//
//  FrameCanonicalizer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/2/26.
//

import Foundation

@MainActor
@objc(iTermFrameCanonicalizer)
class FrameCanonicalizer: NSObject {
    private let preserveSize: Bool
    private let windowType: iTermWindowType
    private let screenVisibleFrame: NSRect
    private let screenVisibleFrameIgnoringHiddenDock: NSRect
    private let initialFrame: NSRect
    private let windowSizeHelper: TerminalWindowSizeHelper
    private let cellSize: NSSize
    private let percentage: iTermPercentage
    private let decorationSize: NSSize
    private let screen: NSScreen?
    private let window: NSWindow?

    @objc(initPreservingSize:windowType:screenVisibleFrame:screenVisibleFrameIgnoringHiddenDock:initialFrame:cellSize:percentage:decorationSize:windowSizeHelper:screen:window:)
    init(preserveSize: Bool,
         windowType: iTermWindowType,
         screenVisibleFrame: NSRect,
         screenVisibleFrameIgnoringHiddenDock: NSRect,
         initialFrame: NSRect,
         cellSize: NSSize,
         percentage: iTermPercentage,
         decorationSize: NSSize,  // width must be iTermScrollbarWidth()
         windowSizeHelper: TerminalWindowSizeHelper,
         screen: NSScreen?,
         window: NSWindow?) {
        self.preserveSize = preserveSize
        self.windowType = windowType
        self.screenVisibleFrame = screenVisibleFrame
        self.screenVisibleFrameIgnoringHiddenDock = screenVisibleFrameIgnoringHiddenDock
        self.initialFrame = initialFrame
        self.cellSize = cellSize
        self.percentage = percentage
        self.decorationSize = decorationSize
        self.windowSizeHelper = windowSizeHelper
        self.screen = screen
        self.window = window

        super.init()
    }

    @objc
    func canonicalized() -> NSRect {
        switch windowType {
        case .WINDOW_TYPE_NORMAL, .WINDOW_TYPE_NO_TITLE_BAR, .WINDOW_TYPE_COMPACT,
                .WINDOW_TYPE_LION_FULL_SCREEN, .WINDOW_TYPE_ACCESSORY:
            return canonicalizedNoOp()
        case .WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return canonicalizedTraditionalFullScreen()
        case .WINDOW_TYPE_CENTERED:
            return canonicalizedCentered()
        case .WINDOW_TYPE_TOP_PERCENTAGE:
            return canonicalizedTopPercentage()
        case .WINDOW_TYPE_TOP_CELLS:
            return canonicalizedTopCells()
        case .WINDOW_TYPE_BOTTOM_PERCENTAGE:
            return canonicalizeBottomPercentage()
        case .WINDOW_TYPE_BOTTOM_CELLS:
            return canonicalizedBottomCells()
        case .WINDOW_TYPE_LEFT_PERCENTAGE:
            return canonicalizedLeftPercentage()
        case .WINDOW_TYPE_LEFT_CELLS:
            return canonicalizedLeftCells()
        case .WINDOW_TYPE_RIGHT_PERCENTAGE:
            return canonicalizedRightPercentage()
        case .WINDOW_TYPE_RIGHT_CELLS:
            return canonicalizedRightCells()
        case .WINDOW_TYPE_MAXIMIZED, .WINDOW_TYPE_COMPACT_MAXIMIZED:
            return canonicalizedMaximized()

        @unknown default:
            it_fatalError()
        }
    }

    private var preferredSizeForEdgeAlignedWindow: NSSize {
        return NSSize(width: windowSizeHelper.width(screenVisibleSize: screenVisibleFrame.size,
                                                    charWidth: cellSize.width,
                                                    decorationWidth: decorationSize.width,
                                                    fallback: initialFrame.width),
                      height: windowSizeHelper.height(screenVisibleSize: screenVisibleFrame.size,
                                                      lineHeight: cellSize.height,
                                                      decorationHeight: decorationSize.height,
                                                      fallback: initialFrame.height))
    }

    private var percentageBasedSize: NSSize {
        let percentWidth = round(screenVisibleFrameIgnoringHiddenDock.size.width * percentage.width / 100)
        let percentHeight = round(screenVisibleFrameIgnoringHiddenDock.size.height * percentage.height / 100)
        let cellBasedSize = preferredSizeForEdgeAlignedWindow
        return NSSize(width: percentage.width < 0 ? cellBasedSize.width : percentWidth,
                      height: percentage.height < 0 ? cellBasedSize.height : percentHeight)
    }

    private func horizontallyCenteredXOrigin(forWidth width: CGFloat) -> CGFloat {
        return screenVisibleFrameIgnoringHiddenDock.origin.x + (screenVisibleFrameIgnoringHiddenDock.size.width - width) / 2
    }

    private func topAlignedYOrigin(forHeight height: CGFloat) -> CGFloat {
        return screenVisibleFrame.origin.y + screenVisibleFrame.size.height - height
    }

    private func verticallyCenteredYOrigin(forHeight height: CGFloat) -> CGFloat {
        return screenVisibleFrameIgnoringHiddenDock.origin.y + (screenVisibleFrameIgnoringHiddenDock.size.height - height) / 2
    }

    private func canonicalizedCentered() -> NSRect {
        var frame = initialFrame
        DLog("Window type = CENTERED. \(windowSizeHelper)")
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            frame.size = preferredSizeForEdgeAlignedWindow
        }
        frame = iTermRectCenteredHorizontallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock)
        frame = iTermRectCenteredVerticallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock)
        DLog("Canonical frame for centered window is \(frame)")
        return frame
    }

    private func canonicalizedTopPercentage() -> NSRect {
        DLog("Window type = TOP_PERCENTAGE. \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            if percentage.height < 0 {
                frame.size.height = preferredSizeForEdgeAlignedWindow.height
            } else {
                frame.size.height = percentageBasedSize.height
            }
            frame.size.width = percentageBasedSize.width
        }
        frame.origin.x = horizontallyCenteredXOrigin(forWidth: frame.width)
        frame.origin.y = topAlignedYOrigin(forHeight: frame.height)
        DLog("Canonical frame for top of screen window is \(frame)")
        return frame
    }

    private func canonicalizedTopCells() -> NSRect {
        DLog("Window type = TOP. \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            frame.size.width = min(frame.width, screenVisibleFrameIgnoringHiddenDock.width)
            frame.size.height = preferredSizeForEdgeAlignedWindow.height
        }
        frame = iTermRectCenteredHorizontallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock)
        frame.origin.y = topAlignedYOrigin(forHeight: frame.height)
        DLog("Canonical frame for top of screen window is \(frame)")
        return frame
    }

    private func canonicalizeBottomPercentage() -> NSRect {
        DLog("Window type = BOTTOM_PERCENTAGE. \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            if percentage.height < 0 {
                frame.size.height = preferredSizeForEdgeAlignedWindow.height
            } else {
                frame.size.height = percentageBasedSize.height
            }
            frame.size.width = percentageBasedSize.width
        }
        frame.origin.x = horizontallyCenteredXOrigin(forWidth: frame.width)
        frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y

        if frame.size.width > 0 {
            return frame
        }
        return NSRect.zero
    }

    private func canonicalizedBottomCells() -> NSRect {
        DLog("Window type = BOTTOM. \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            frame.size.height = preferredSizeForEdgeAlignedWindow.height
            frame.size.width = min(frame.width, screenVisibleFrameIgnoringHiddenDock.width)
        }
        frame = iTermRectCenteredHorizontallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock)
        frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y

        if frame.size.width > 0 {
            return frame
        }
        return NSRect.zero
    }

    private func canonicalizedLeftPercentage() -> NSRect {
        DLog("Window type = LEFT_PERCENTAGE \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of columns, grow it.
            if percentage.width < 0 {
                frame.size.width = preferredSizeForEdgeAlignedWindow.width
            } else {
                frame.size.width = percentageBasedSize.width
            }
            frame.size.height = percentageBasedSize.height
        }
        frame.origin.y = verticallyCenteredYOrigin(forHeight: frame.height)
        frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x

        return frame
    }

    private func canonicalizedLeftCells() -> NSRect {
        DLog("Window type = LEFT. \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of columns, grow it.
            frame.size.width = preferredSizeForEdgeAlignedWindow.width
            frame.size.height = min(frame.height, screenVisibleFrameIgnoringHiddenDock.height)
        }
        frame = iTermRectCenteredVerticallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock)
        frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x

        return frame
    }

    private func canonicalizedRightPercentage() -> NSRect {
        DLog("Window type = RIGHT_PERCENTAGE. \(windowSizeHelper)")
        var frame = initialFrame
        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of columns, grow it.
            if percentage.width < 0 {
                frame.size.width = preferredSizeForEdgeAlignedWindow.width
            } else {
                frame.size.width = percentageBasedSize.width
            }
            frame.size.height = percentageBasedSize.height
        }
        frame.origin.y = verticallyCenteredYOrigin(forHeight: frame.height)
        frame.origin.x = screenVisibleFrameIgnoringHiddenDock.maxX - frame.width

        return frame
    }

    private func canonicalizedRightCells() -> NSRect {
        DLog("Window type = RIGHT \(windowSizeHelper)")
        var frame = initialFrame

        if !preserveSize {
            // If the screen grew and the window was smaller than the desired number of columns, grow it.
            frame.size.width = preferredSizeForEdgeAlignedWindow.width
            frame.size.height = min(frame.height, screenVisibleFrameIgnoringHiddenDock.height)
        }
        frame = iTermRectCenteredVerticallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock)
        frame.origin.x = screenVisibleFrameIgnoringHiddenDock.maxX - frame.width

        return frame
    }

    private func canonicalizedMaximized() -> NSRect {
        DLog("Window type = MAXIMIZED or COMPACT_MAXIMIZED")
        return screen?.visibleFrameIgnoringHiddenDock() ?? NSRect.zero
    }

    private func canonicalizedNoOp() -> NSRect {
        DLog("Window type = NORMAL, NO_TITLE_BAR, WINDOW_TYPE_COMPACT, WINDOW_TYPE_ACCESSORY, or LION_FULL_SCREEN")
        return initialFrame
    }

    private func canonicalizedTraditionalFullScreen() -> NSRect {
        DLog("Window type = FULL SCREEN")
        if let screen, screen.frame.size.width > 0 {
            return windowSizeHelper.traditionalFullScreenFrame(forScreen: screen, forWindow: window)
        }
        return NSRect.zero
    }
}
