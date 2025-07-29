//
//  TerminalWindowSizeHelper.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

@objc(iTermTerminalWindowSizeHelper)
@MainActor
class TerminalWindowSizeHelper: NSObject {
    // For top/left/bottom of screen windows, this is the size it really wants to be.
    // Initialized to -1 in -init and then set to the size of the first session
    // forever.
    private var desiredRows: Int32?
    private var desiredColumns: Int32?

    struct SessionSize {
        var gridSize: VT100GridSize
        var pointSize: NSSize
    }

    typealias Profile = [AnyHashable: Any]
}

// API
@objc
@MainActor
extension TerminalWindowSizeHelper {
    override var description: String {
        standardDescription(
            with: ["desiredGridSize=\(desiredColumns.d) x \(desiredRows.d)"])
    }

    @objc(willLoadArrangement:)
    func willLoad(arrangement: [AnyHashable: Any]) {
        desiredRows = arrangement[TERMINAL_ARRANGEMENT_DESIRED_ROWS] as? Int32
        desiredColumns = arrangement[TERMINAL_ARRANGEMENT_DESIRED_COLUMNS] as? Int32
    }

    @objc(populateInArrangement:)
    func populate(in arrangement: iTermEncoderAdapter) {
        arrangement.setObject(
            desiredRows ?? -1,
            forKey: TERMINAL_ARRANGEMENT_DESIRED_ROWS)
        arrangement.setObject(
            desiredColumns ?? -1,
            forKey: TERMINAL_ARRANGEMENT_DESIRED_COLUMNS)
    }

    @objc(widthForScreenVisibleSize:charWidth:decorationWidth:fallback:)
    func width(screenVisibleSize: NSSize,
               charWidth: CGFloat,
               decorationWidth: CGFloat,
               fallbacK: CGFloat) -> CGFloat {
        let hmargin = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
        if let desiredColumns {
            return min(screenVisibleSize.width,
                       charWidth * CGFloat(desiredColumns) + decorationWidth + 2.0 * hmargin)
        } else {
            return min(screenVisibleSize.width, fallbacK)
        }
    }


    @objc(heightForScreenVisibleSize:lineHeight:decorationHeight:fallback:)
    func height(screenVisibleSize: NSSize,
                lineHeight: CGFloat,
                decorationHeight: CGFloat,
                fallbacK: CGFloat) -> CGFloat {
        let vmargin = iTermPreferences.double(forKey: kPreferenceKeyTopBottomMargins)
        if let desiredRows {
            return min(screenVisibleSize.height,
                       ceil(lineHeight * CGFloat(desiredRows)) + decorationHeight + 2.0 * vmargin)
        } else {
            return min(screenVisibleSize.height, fallbacK)
        }
    }

    @objc(didEndLiveResizeVerticallyConstrained:)
    func didEndLiveResize(verticallyConstrained: Bool) {
        if verticallyConstrained {
            desiredRows = nil
        } else {
            desiredColumns = nil
        }
    }

    @objc(preferredSizeForCellSize:decorationSize:profile:)
    func preferredSize(cellSize: NSSize,
                       decorationSize: NSSize,
                       profile: Profile?) -> NSSize {
        let isBrowser = (profile as? NSDictionary)?.profileIsBrowser ?? false
        let sessionSize = if isBrowser {
            VT100GridSizeMake(
                Int32(clamping: min(iTermMaxInitialSessionSize,
                                    iTermProfilePreferences.integer(forKey: KEY_WIDTH,
                                                                    inProfile: profile ?? [:]))),
                Int32(clamping: min(iTermMaxInitialSessionSize,
                                    iTermProfilePreferences.integer(forKey: KEY_HEIGHT,
                                                                    inProfile: profile ?? [:]))))
        } else {
            VT100GridSizeMake(
                Int32(clamping: min(iTermMaxInitialSessionSize,
                                    iTermProfilePreferences.integer(forKey: KEY_COLUMNS,
                                                                    inProfile: profile ?? [:]))),
                Int32(clamping: min(iTermMaxInitialSessionSize,
                                    iTermProfilePreferences.integer(forKey: KEY_ROWS,
                                                                    inProfile: profile ?? [:]))))
        }
        let hmargin = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
        let vmargin = iTermPreferences.double(forKey: kPreferenceKeyTopBottomMargins)

        return NSSize(
            width: hmargin * 2.0 + CGFloat(sessionSize.width) * cellSize.width + decorationSize.width,
            height: vmargin * 2.0 + CGFloat(sessionSize.height) * cellSize.height + decorationSize.height)
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
                     rightExtra: CGFloat) -> SessionSize {
        let forNewWindow = (existingViewSize == nil)
        var gridSize = gridSizeFromState(andProfile: profile, forNewWindow: forNewWindow)
        let cellSize = Self.cellSize(profile: profile)
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
        return SessionSize(gridSize: gridSize, pointSize: sessionSize)
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

    static func gridSize(profile: Profile) -> VT100GridSize {
        if (profile as NSDictionary).profileIsBrowser {
            return VT100GridSize(width: iTermProfilePreferences.int(forKey: KEY_WIDTH, inProfile: profile),
                                 height: iTermProfilePreferences.int(forKey: KEY_HEIGHT, inProfile: profile))
        } else {
            return VT100GridSize(width: iTermProfilePreferences.int(forKey: KEY_COLUMNS, inProfile: profile),
                                 height: iTermProfilePreferences.int(forKey: KEY_ROWS, inProfile: profile))
        }
    }

    func gridSizeFromState(andProfile profile: Profile,
                                   forNewWindow: Bool) -> VT100GridSize {
        var result = Self.gridSize(profile: profile)
        if forNewWindow, let desiredRows, let desiredColumns {
            result = VT100GridSize(width: desiredColumns, height: desiredRows)
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
