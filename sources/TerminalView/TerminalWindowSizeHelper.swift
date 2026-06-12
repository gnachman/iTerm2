//
//  TerminalWindowSizeHelper.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

@objc(iTermTerminalWindowSizeHelper)
@MainActor
class TerminalWindowSizeHelper: NSObject {
    enum Measurement: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .cells(let n): return "\(n) cells"
            case .screenPercentage(let p): return "\(p)%"
            }
        }
        case cells(Int32)
        case screenPercentage(Double)  // 0…100

        var isValid: Bool {
            switch self {
            case .cells(-1): false
            case let .screenPercentage(x) where x < 0: false
            case .cells, .screenPercentage: true
            }
        }
    }
    // For top/left/bottom of screen windows, this is the desired size.
    // nil means "no preference" (use profile defaults or fallback).
    private var desiredRows: Measurement?
    private var desiredColumns: Measurement?

    struct SessionSize {
        var gridSize: VT100GridSize
        var pointSize: NSSize
        var desiredSize: (rows: Measurement, columns: Measurement)
    }

    typealias Profile = [AnyHashable: Any]
}

extension iTermWindowType {
    var percentageEligible: Bool {
        switch self {
        case .WINDOW_TYPE_TOP_PERCENTAGE, .WINDOW_TYPE_BOTTOM_PERCENTAGE,
                .WINDOW_TYPE_LEFT_PERCENTAGE, .WINDOW_TYPE_RIGHT_PERCENTAGE,
                .WINDOW_TYPE_NORMAL, .WINDOW_TYPE_NO_TITLE_BAR,
                .WINDOW_TYPE_COMPACT, .WINDOW_TYPE_CENTERED:
            true
        case .WINDOW_TYPE_TRADITIONAL_FULL_SCREEN,
                .WINDOW_TYPE_LION_FULL_SCREEN, .WINDOW_TYPE_BOTTOM_CELLS, .WINDOW_TYPE_TOP_CELLS,
                .WINDOW_TYPE_LEFT_CELLS, .WINDOW_TYPE_RIGHT_CELLS,
                .WINDOW_TYPE_ACCESSORY, .WINDOW_TYPE_MAXIMIZED,
                .WINDOW_TYPE_COMPACT_MAXIMIZED:
            false
        @unknown default:
            it_fatalError()
        }
    }
}

// API
@objc
@MainActor
extension TerminalWindowSizeHelper {
    override var description: String {
        standardDescription(
            with: ["desiredGridSize=\(desiredColumns.debugDescriptionOrNil) x \(desiredRows.debugDescriptionOrNil)"])
    }

    @objc(willLoadArrangement:)
    func willLoad(arrangement: [AnyHashable: Any]) {
        if let rows = arrangement[TERMINAL_ARRANGEMENT_DESIRED_ROWS] as? Int32, rows >= 0 {
            desiredRows = .cells(rows)
        } else if let percentage = arrangement[TERMINAL_ARRANGEMENT_DESIRED_SCREEN_HEIGHT_PERCENTAGE] as? Double {
            desiredRows = .screenPercentage(percentage)
        } else {
            desiredRows = nil
        }

        if let columns = arrangement[TERMINAL_ARRANGEMENT_DESIRED_COLUMNS] as? Int32, columns >= 0 {
            desiredColumns = .cells(columns)
        } else if let percentage = arrangement[TERMINAL_ARRANGEMENT_DESIRED_SCREEN_WIDTH_PERCENTAGE] as? Double {
            desiredColumns = .screenPercentage(percentage)
        } else {
            desiredColumns = nil
        }
    }

    @objc(populateInArrangement:)
    func populate(in arrangement: iTermEncoderAdapter) {
        switch desiredRows {
        case .none:
            arrangement.setObject(
                -1,
                forKey: TERMINAL_ARRANGEMENT_DESIRED_ROWS)
        case .cells(let cells):
            arrangement.setObject(
                cells,
                forKey: TERMINAL_ARRANGEMENT_DESIRED_ROWS)
        case .screenPercentage(let percentage):
            arrangement.setObject(
                percentage,
                forKey: TERMINAL_ARRANGEMENT_DESIRED_SCREEN_HEIGHT_PERCENTAGE)
        }
        switch desiredColumns {
        case .none:
            arrangement.setObject(
                -1,
                 forKey: TERMINAL_ARRANGEMENT_DESIRED_COLUMNS)
        case .cells(let cells):
            arrangement.setObject(
                cells,
                forKey: TERMINAL_ARRANGEMENT_DESIRED_COLUMNS)
        case .screenPercentage(let percentage):
            arrangement.setObject(
                percentage,
                forKey: TERMINAL_ARRANGEMENT_DESIRED_SCREEN_WIDTH_PERCENTAGE)
        }
    }

    @objc(widthForScreenVisibleSize:charWidth:decorationWidth:fallback:)
    func width(screenVisibleSize: NSSize,
               charWidth: CGFloat,
               decorationWidth: CGFloat,
               fallback: CGFloat) -> CGFloat {
        let hmargin = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
        let desiredPoints = switch desiredColumns {
        case .none:
            fallback
        case .cells(let cells):
            charWidth * CGFloat(cells) + decorationWidth + 2.0 * hmargin
        case .screenPercentage(let percentage):
            screenVisibleSize.width * percentage / 100.0
        }
        return min(screenVisibleSize.width, desiredPoints)
    }


    @objc(heightForScreenVisibleSize:lineHeight:decorationHeight:fallback:)
    func height(screenVisibleSize: NSSize,
                lineHeight: CGFloat,
                decorationHeight: CGFloat,
                fallback: CGFloat) -> CGFloat {
        let vmargin = iTermPreferences.double(forKey: kPreferenceKeyTopBottomMargins)
        let desiredPoints = switch desiredRows {
        case .none:
            fallback
        case .cells(let cells):
            ceil(lineHeight * CGFloat(cells)) + decorationHeight + 2.0 * vmargin
        case .screenPercentage(let percentage):
            screenVisibleSize.height * percentage / 100.0
        }
        return min(screenVisibleSize.height, desiredPoints)
    }

    @objc(didEndLiveResizeVerticallyConstrained:)
    func didEndLiveResize(verticallyConstrained: Bool) {
        if verticallyConstrained {
            desiredRows = nil
        } else {
            desiredColumns = nil
        }
    }

    @nonobjc
    static func measurements(profile: Profile?) -> (rows: Measurement, columns: Measurement) {
        let isBrowser = (profile as? NSDictionary)?.profileIsBrowser ?? false
        if isBrowser {
            return (rows: .cells(iTermProfilePreferences.int(forKey: KEY_HEIGHT,
                                                             inProfile: profile ?? [:])),
                    columns: .cells(iTermProfilePreferences.int(forKey: KEY_WIDTH,
                                                                inProfile: profile ?? [:])))
        }
        let windowTypeRawValue = iTermProfilePreferences.int(forKey: KEY_WINDOW_TYPE,
                                                             inProfile: profile ?? [:])
        let columnCells = iTermProfilePreferences.int(forKey: KEY_COLUMNS,
                                                       inProfile: profile ?? [:])
        let rowCells = iTermProfilePreferences.int(forKey: KEY_ROWS,
                                                    inProfile: profile ?? [:])
        let windowType = iTermWindowType(rawValue: windowTypeRawValue)
        guard windowType?.percentageEligible == true else {
            return (rows: .cells(rowCells), columns: .cells(columnCells))
        }
        let columns: Measurement = {
            if let widthPercentage = profile?[KEY_WIDTH_PERCENTAGE] as? Double {
                if widthPercentage < 0 {
                    return .cells(columnCells)
                }
                return .screenPercentage(widthPercentage)
            }
            if windowType == .WINDOW_TYPE_TOP_PERCENTAGE ||
                windowType == .WINDOW_TYPE_BOTTOM_PERCENTAGE {
                // Migration path for profiles predating the percentage feature. They should span
                // their attached edge.
                return .screenPercentage(100.0)
            }
            return .cells(columnCells)
        }()
        let rows: Measurement = {
            if let heightPercentage = profile?[KEY_HEIGHT_PERCENTAGE] as? Double {
                if heightPercentage < 0 {
                    return .cells(rowCells)
                }
                return .screenPercentage(heightPercentage)
            }
            if windowType == .WINDOW_TYPE_LEFT_PERCENTAGE ||
                windowType == .WINDOW_TYPE_RIGHT_PERCENTAGE {
                // Migration path for profiles predating the percentage feature. They should span
                // their attached edge.
                return .screenPercentage(100.0)
            }
            return .cells(rowCells)
        }()
        return (rows: rows,
                columns: columns)
    }

    @nonobjc
    private static func measurementToCells(measurement: Measurement,
                                           cellSize: CGFloat,
                                           screenSize: CGFloat) -> Int32 {
        DLog("Convert \(measurement) with cellSize \(cellSize) and screenSize \(screenSize)")
        switch measurement {
        case .screenPercentage(let percentage):
            return Int32(clamping: round(screenSize * percentage / (100 * max(1.0, cellSize))))
        case .cells(let count):
            return count
        }
    }

    static func preferredGridSize(cellSize: NSSize,
                                  profile: Profile?,
                                  screenSize: NSSize) -> VT100GridSize {
        let (rows, columns) = measurements(profile: profile)
        return VT100GridSize(width: measurementToCells(measurement: columns,
                                                       cellSize: cellSize.width,
                                                       screenSize: screenSize.width),
                             height: measurementToCells(measurement: rows,
                                                        cellSize: cellSize.height,
                                                        screenSize: screenSize.height)).safe
    }

    @objc(preferredSizeForCellSize:decorationSize:profile:screenSize:)
    func preferredSize(cellSize: NSSize,
                       decorationSize: NSSize,
                       profile: Profile?,
                       screenSize: NSSize) -> NSSize {
        let sessionSize = Self.preferredGridSize(cellSize: cellSize,
                                                 profile: profile,
                                                 screenSize: screenSize)
        let hmargin = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
        let vmargin = iTermPreferences.double(forKey: kPreferenceKeyTopBottomMargins)

        return NSSize(
            width: hmargin * 2.0 + CGFloat(sessionSize.width) * cellSize.width + decorationSize.width,
            height: vmargin * 2.0 + CGFloat(sessionSize.height) * cellSize.height + decorationSize.height)
    }

    @objc
    func fullScreenWindowFrameShouldBeShiftedDownBelowMenuBar(onScreen screen: NSScreen?,
                                                              forWindow window: NSWindow?) -> Bool {
        let wantToHideMenuBar = iTermPreferences.bool(forKey: kPreferenceKeyHideMenuBarInFullscreen)
        let canHideMenuBar = !iTermApplication.shared().isUIElement
        let menuBarIsHidden = !iTermMenuBarObserver.sharedInstance().menuBarVisible(on: screen)
        let canOverlapMenuBar = window is iTermPanel

        DLog("Checking if the fullscreen window frame should be shifted down below the menu bar. " +
             "wantToHideMenuBar=\(wantToHideMenuBar), canHideMenuBar=\(canHideMenuBar)," + "menuIsHidden=\(menuBarIsHidden), canOverlapMenuBar=\(canOverlapMenuBar)")
        if wantToHideMenuBar && canHideMenuBar {
            DLog("Nope");
            return false
        }
        if menuBarIsHidden {
            DLog("Nope")
            return false
        }
        if (canOverlapMenuBar && wantToHideMenuBar) {
            DLog("Nope")
            return false
        }

        DLog("Yep")
        return true
    }

    @objc
    func traditionalFullScreenFrame(forScreen screen: NSScreen?, forWindow window: NSWindow?) -> NSRect {
        let menuBarIsVisible = fullScreenWindowFrameShouldBeShiftedDownBelowMenuBar(
            onScreen: screen,
            forWindow: window)
        if menuBarIsVisible {
            DLog("Subtract menu bar from frame")
            return screen?.frameExceptMenuBar() ?? NSRect.zero
        } else {
            DLog("Do not subtract menu bar from frame")
            return screen?.frame ?? NSRect.zero
        }

    }
}

// Swift-only API
@MainActor
extension TerminalWindowSizeHelper {
    func sessionSize(profile: Profile,
                     existingViewSize: NSSize?,
                     desiredPointSize: NSSize?,
                     hasScrollbar: Bool,
                     scrollerStyle: NSScroller.Style,
                     rightExtra: CGFloat,
                     screenSize: NSSize) -> SessionSize {
        let forNewWindow = (existingViewSize == nil)
        let cellSize = Self.cellSize(profile: profile)
        var gridSize = gridSizeFromState(andProfile: profile,
                                         screenSize: screenSize,
                                         cellSize: cellSize,
                                         forNewWindow: forNewWindow)
        if desiredPointSize == nil, let existingViewSize {
            let contentSize = existingViewSize
            gridSize = Self.gridSize(forContentSize: contentSize,
                                     profile: profile)
        }
        if desiredPointSize == nil, let existingViewSize {
            gridSize = Self.gridSize(forContentSize: existingViewSize,
                                     cellSize: cellSize)
        }
        let sessionSize: NSSize
        if let desiredPointSize {
            sessionSize = desiredPointSize
            let contentSize = Self.scrollViewContentSize(frameSize: desiredPointSize,
                                                         hasScrollbar: hasScrollbar,
                                                         scrollerStyle: scrollerStyle,
                                                         rightExtra: rightExtra)
            gridSize = Self.gridSize(forContentSize: contentSize, cellSize: cellSize)
        } else {
            sessionSize = Self.sessionSize(gridSize: gridSize, cellSize: cellSize)
        }
        return SessionSize(gridSize: gridSize,
                           pointSize: sessionSize,
                           desiredSize: Self.measurements(profile: profile))
    }

    func updateDesiredSize(_ measurements: (rows: Measurement, columns: Measurement)) {
        if desiredRows == nil {
            desiredRows = measurements.rows
        }
        if desiredColumns == nil {
            desiredColumns = measurements.columns
        }
    }
}

// Private methods
@MainActor
private extension TerminalWindowSizeHelper {
    static func sessionSize(gridSize: VT100GridSize,
                            cellSize: NSSize) -> NSSize {
        let hmargin = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
        let vmargin = iTermPreferences.double(forKey: kPreferenceKeyTopBottomMargins)
        return NSSize(
            width: CGFloat(gridSize.width) * cellSize.width + hmargin * 2,
            height: CGFloat(gridSize.height) * cellSize.height + vmargin * 2)
    }

    static func scrollViewContentSize(frameSize: NSSize,
                                      hasScrollbar: Bool,
                                      scrollerStyle: NSScroller.Style,
                                      rightExtra: CGFloat) -> NSSize {
        return PTYScrollView.contentSize(forFrameSize: frameSize,
                                         horizontalScrollerClass: nil,
                                         verticalScrollerClass: hasScrollbar ? PTYScroller.self : nil,
                                         borderType: .noBorder,
                                         controlSize: .regular,
                                         scrollerStyle: scrollerStyle,
                                         rightExtra: rightExtra)
    }

    func gridSizeFromState(andProfile profile: Profile,
                           screenSize: NSSize,
                           cellSize: NSSize,
                           forNewWindow: Bool) -> VT100GridSize {
        var result = Self.preferredGridSize(cellSize: cellSize,
                                            profile: profile,
                                            screenSize: screenSize)
        if forNewWindow, let desiredRows, let desiredColumns {
            result = switch (desiredRows, desiredColumns) {
            case (.cells(let rows), .cells(let columns)):
                VT100GridSize(width: columns, height: rows).safe

            case (.screenPercentage(let heightPercentage), .screenPercentage(let widthPercentage)):
                VT100GridSize(
                    width: Int32(clamping: round(
                        screenSize.width * (widthPercentage / 100.0) / max(1.0, cellSize.width))),
                    height: Int32(clamping: round(
                        screenSize.height * (heightPercentage / 100.0) / max(1.0, cellSize.height)))).safe
            case (.cells(let rows), .screenPercentage(let widthPercentage)):
                VT100GridSize(
                    width: Int32(clamping: round(
                        screenSize.width * (widthPercentage / 100.0) / max(1.0, cellSize.width))),
                    height: rows).safe
            case (.screenPercentage(let heightPercentage), .cells(let columns)):
                VT100GridSize(
                    width: columns,
                    height: Int32(clamping: round(
                        screenSize.height * (heightPercentage / 100.0) / max(1.0, cellSize.height)))).safe
            }
            self.desiredRows = nil
            self.desiredColumns = nil
        }
        return result
    }

    static func cellSize(profile: Profile) -> NSSize {
        if (profile as NSDictionary).profileIsBrowser {
            return NSSize(width: 1.0, height: 1.0)
        }
        return PTYTextView.charSize(
            for: font(profile: profile),
            horizontalSpacing: iTermProfilePreferences.double(forKey: KEY_HORIZONTAL_SPACING, inProfile: profile),
            verticalSpacing: iTermProfilePreferences.double(forKey: KEY_VERTICAL_SPACING, inProfile: profile))
    }

    static func font(profile: Profile) -> NSFont {
        return ITAddressBookMgr.font(withDesc: iTermProfilePreferences.string(forKey: KEY_NORMAL_FONT,
                                                                              inProfile: profile),
                                     ligaturesEnabled: iTermProfilePreferences.bool(forKey: KEY_ASCII_LIGATURES,
                                                                                    inProfile: profile))
    }

    static func gridSize(forContentSize contentSize: NSSize,
                         profile: Profile) -> VT100GridSize {
        let cellSize = self.cellSize(profile: profile)
        return gridSize(forContentSize: contentSize, cellSize: cellSize)
    }

    static func gridSize(forContentSize contentSize: NSSize,
                         cellSize: NSSize) -> VT100GridSize {
        let hmargin = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
        let vmargin = iTermPreferences.double(forKey: kPreferenceKeyTopBottomMargins)
        return VT100GridSize(
            width: Int32(clamping: (contentSize.width - hmargin * 2.0) / cellSize.width),
            height: Int32(clamping: (contentSize.height - vmargin * 2.0) / cellSize.height))
    }
}

extension VT100GridSize {
    var safe: VT100GridSize {
        var temp = self
        temp.width = max(1, min(Int32(iTermMaxInitialSessionSize), temp.width))
        temp.height = max(1, min(Int32(iTermMaxInitialSessionSize), temp.height))
        return temp
    }
}
