//
//  PSMTahoeTabStyle.swift
//  iTerm2
//
//  Created by George Nachman on 8/21/25.
//

import Cocoa

let kPSMMetalObjectCounterRadius: CGFloat = 7.0
let kPSMMetalCounterMinWidth: CGFloat = 20

@objc
class PSMTahoeTabStyle: NSObject, NSCoding, PSMTabStyle {
    // MARK: - Private Properties
    private var _closeButton: NSImage?
    private var _closeButtonDown: NSImage?
    private var _closeButtonOver: NSImage?
    private var _addTabButtonImage: NSImage?
    private var _addTabButtonPressedImage: NSImage?
    private var _addTabButtonRolloverImage: NSImage?
    private var _orientation: PSMTabBarOrientation = .horizontalOrientation
    @objc static let tabBarHeight = 36.0
    
    // MARK: - PSMTabStyle Properties
    @objc weak var tabBar: PSMTabBarControl?
    
    @objc var tabBarColor: NSColor {
        return NSColor(srgbRed: 225.0 / 255.0,
                       green: 225.0 / 255.0,
                       blue: 225.0 / 255.0,
                       alpha: 1)
    }
    
    @objc var orientation: PSMTabBarOrientation {
        return _orientation
    }
    
    @objc var windowIsMainAndAppIsActive: Bool {
        guard let window = tabBar?.window else { return false }
        return window.isMainWindow && NSApp.isActive
    }
    
    @objc var accessoryAppearance: NSAppearance? {
        return nil
    }
    
    @objc var edgeDragHeight: CGFloat {
        guard let delegate = tabBar?.delegate,
              let size = delegate.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.dragEdgeHeight) as? NSNumber else {
            return 0
        }
        return CGFloat(size.doubleValue)
    }
    
    @objc var intercellSpacing: CGFloat {
        2.0
    }
    
    @objc var supportsMultiLineLabels: Bool {
        guard let tabBar = tabBar else { return false }
        return tabBar.bounds.height >= 28
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // Load close buttons
        let bundle = Bundle(for: type(of: self))
        _closeButton = bundle.image(forResource: "TabClose_Front")
        _closeButton?.isTemplate = true
        _closeButtonDown = bundle.image(forResource: "TabClose_Front_Pressed")
        _closeButtonDown?.isTemplate = true
        _closeButtonOver = bundle.image(forResource: "TabClose_Front_Rollover")
        _closeButtonOver?.isTemplate = true
        
        // Load "new tab" buttons
        var addTabImageName = "YosemiteAddTab"
        addTabImageName = "BigSurAddTab"
        
        if let bundle = PSMTabBarControl.bundle() {
            _addTabButtonImage = NSImage(byReferencingFile: bundle.pathForImageResource(addTabImageName) ?? "")
            _addTabButtonPressedImage = NSImage(byReferencingFile: bundle.pathForImageResource(addTabImageName) ?? "")
            _addTabButtonRolloverImage = NSImage(byReferencingFile: bundle.pathForImageResource(addTabImageName) ?? "")
            
            _addTabButtonImage?.isTemplate = true
            _addTabButtonPressedImage?.isTemplate = true
            _addTabButtonRolloverImage?.isTemplate = true
        }
    }
    
    // MARK: - NSCoding
    
    func encode(with coder: NSCoder) {
        if coder.allowsKeyedCoding {
            coder.encode(_closeButton, forKey: "metalCloseButton")
            coder.encode(_closeButtonDown, forKey: "metalCloseButtonDown")
            coder.encode(_closeButtonOver, forKey: "metalCloseButtonOver")
            coder.encode(_addTabButtonImage, forKey: "addTabButtonImage")
            coder.encode(_addTabButtonPressedImage, forKey: "addTabButtonPressedImage")
            coder.encode(_addTabButtonRolloverImage, forKey: "addTabButtonRolloverImage")
        }
    }
    
    required init?(coder: NSCoder) {
        super.init()
        if coder.allowsKeyedCoding {
            _closeButton = coder.decodeObject(forKey: "metalCloseButton") as? NSImage
            _closeButtonDown = coder.decodeObject(forKey: "metalCloseButtonDown") as? NSImage
            _closeButtonOver = coder.decodeObject(forKey: "metalCloseButtonOver") as? NSImage
            _addTabButtonImage = coder.decodeObject(forKey: "addTabButtonImage") as? NSImage
            _addTabButtonPressedImage = coder.decodeObject(forKey: "addTabButtonPressedImage") as? NSImage
            _addTabButtonRolloverImage = coder.decodeObject(forKey: "addTabButtonRolloverImage") as? NSImage
        }
    }
    
    // MARK: - PSMTabStyle Protocol
    
    @objc func name() -> String {
        return "Yosemite"
    }
    
    // MARK: - Control Specific
    
    @objc func leftMarginForTabBarControl() -> Float {
        return Float(tabBar?.insets.left ?? 0)
    }
    
    @objc func rightMarginForTabBarControl(withOverflow: Bool, addTabButton: Bool) -> Float {
        if withOverflow || addTabButton {
            if #available(macOS 26, *) {
                return 32.0 + Float(tabBar?.insets.right ?? 0)
            }
            return 24.0
        }
        return 0
    }
    
    @objc func topMarginForTabBarControl() -> Float {
        return Float(tabBar?.insets.top ?? 0)
    }
    
    // MARK: - Add Tab Button
    
    @objc func addTabButtonImage() -> NSImage? {
        return _addTabButtonImage
    }
    
    @objc func addTabButtonPressedImage() -> NSImage? {
        return _addTabButtonPressedImage
    }
    
    @objc func addTabButtonRolloverImage() -> NSImage? {
        return _addTabButtonRolloverImage
    }
    
    // MARK: - Cell Specific
    
    @objc func dragRect(forTabCell cell: PSMTabBarCell, orientation tabOrientation: PSMTabBarOrientation) -> NSRect {
        var dragRect = cell.frame
        dragRect.size.width += 1
        
        if (Int(cell.tabState) & PSMTab_SelectedMask) != 0 {
            if tabOrientation != .horizontalOrientation {
                dragRect.size.height += 1.0
                dragRect.origin.y -= 1.0
                dragRect.origin.x += 2.0
                dragRect.size.width -= 3.0
            }
        } else if tabOrientation == .verticalOrientation {
            dragRect.origin.x -= 1
        }
        
        return dragRect
    }
    
    @objc func closeButtonRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        let cellFrame = cell.frame
        
        if !cell.hasCloseButton {
            return NSZeroRect
        }
        
        var result = NSRect()
        result.size = _closeButton?.size ?? NSZeroSize
        result.origin.x = cellFrame.origin.x + kSPMTabBarCellInternalXMargin
        result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0)
        
        return result
    }
    
    @objc func iconRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        let cellFrame = cell.frame
        
        if !cell.hasIcon {
            return NSZeroRect
        }
        
        let minX: CGFloat
        if cell.count > 0 {
            let objectCounterRect = self.objectCounterRect(forTabCell: cell)
            minX = objectCounterRect.minX
        } else if !cell.indicator.isHidden {
            minX = indicatorRect(forTabCell: cell).minX - kSPMTabBarCellInternalXMargin
        } else {
            minX = cellFrame.maxX - kSPMTabBarCellInternalXMargin
        }
        
        var result = NSRect()
        result.size = NSSize(width: kPSMTabBarIconWidth, height: kPSMTabBarIconWidth)
        result.origin.x = minX - kPSMTabBarCellIconPadding - kPSMTabBarIconWidth
        result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0) - 1
        
        if let window = cell.controlView?.window, window.backingScaleFactor > 1 {
            result.origin.y += 0.5
        }
        
        return result
    }
    
    @objc func indicatorRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        let cellFrame = cell.frame
        
        let minX: CGFloat
        if cell.count > 0 {
            // Indicator to the left of the tab number
            let objectCounterRect = self.objectCounterRect(forTabCell: cell)
            minX = objectCounterRect.minX
        } else {
            // Indicator on the right edge of the tab
            minX = cellFrame.maxX - kSPMTabBarCellInternalXMargin
        }
        
        var result = NSRect()
        result.size = NSSize(width: kPSMTabBarIndicatorWidth, height: kPSMTabBarIndicatorWidth)
        result.origin.x = minX - kPSMTabBarCellIconPadding - kPSMTabBarIndicatorWidth
        result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0)
        
        return result
    }
    
    @objc func objectCounterRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        let cellFrame = cell.frame
        
        if cell.count == 0 {
            return NSZeroRect
        }
        
        var countWidth = retinaRoundUpCell(cell, value: attributedObjectCountValue(forTabCell: cell).size().width)
        countWidth += (2 * kPSMMetalObjectCounterRadius - 6.0)
        if countWidth < kPSMMetalCounterMinWidth {
            countWidth = kPSMMetalCounterMinWidth
        }
        
        var result = NSRect()
        result.size = NSSize(width: countWidth, height: 2 * kPSMMetalObjectCounterRadius)
        result.origin.x = cellFrame.origin.x + cellFrame.size.width - kSPMTabBarCellInternalXMargin - result.size.width
        result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0)
        
        return result
    }

    
    @objc
    func minimumWidth(ofTabCell cell: PSMTabBarCell!) -> Float {
        return Float(ceil(widthOfLeftMatterInCell(cell) +
                         kPSMMinimumTitleWidth +
                         widthOfRightMatterInCell(cell)))
    }
    
    @objc
    func desiredWidth(ofTabCell cell: PSMTabBarCell!) -> Float {
        return Float(ceil(widthOfLeftMatterInCell(cell) +
                         widthOfAttributedStringInCell(cell) +
                         widthOfRightMatterInCell(cell)))
    }
    
    // MARK: - Cell Values
    
    @objc func attributedObjectCountValue(forTabCell cell: PSMTabBarCell) -> NSAttributedString {
        let count = cell.count
        var contents = String(count)
        let modifierString = cell.modifierString ?? ""
        
        if modifierString.count > 0 && count < 9 {
            contents = modifierString + contents
        } else if modifierString.count > 0 && cell.isLast {
            contents = modifierString + "9"
        } else {
            contents = ""
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor(for: cell)
        ]
        
        return NSAttributedString(string: contents, attributes: attributes)
    }
    
    @objc func cachedTitleInputs(forTabCell cell: PSMTabBarCell) -> PSMCachedTitleInputs {
        let parseHTML = tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.htmlTabTitles) as? NSNumber ?? NSNumber(value: false)
        
        let tabViewItem = cell.representedObject as? NSTabViewItem
        let tab = tabViewItem?.identifier as? PSMTabBarControlRepresentedObjectIdentifierProtocol
        let graphic = tab?.psmTabGraphic?()
        
        return PSMCachedTitleInputs(
            title: cell.stringValue,
            truncationStyle: cell.truncationStyle,
            color: textColor(for: cell),
            graphic: graphic,
            orientation: _orientation,
            fontSize: fontSize,
            parseHTML: parseHTML.boolValue
        )
    }
    
    @objc func cachedSubtitleInputs(forTabCell cell: PSMTabBarCell) -> PSMCachedTitleInputs? {
        guard let subtitle = cell.subtitleString else {
            return nil
        }
        
        let parseHTML = tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.htmlTabTitles) as? NSNumber ?? NSNumber(value: false)
        let color = textColor(for: cell)
        
        return PSMCachedTitleInputs(
            title: subtitle,
            truncationStyle: cell.truncationStyle,
            color: color.withAlphaComponent(color.alphaComponent * 0.7),
            graphic: nil,
            orientation: _orientation,
            fontSize: subtitleFontSize,
            parseHTML: parseHTML.boolValue
        )
    }

    func adjustedCellRect(_ rect: NSRect, generic: NSRect) -> NSRect {
        var frame = rect
        frame.origin.y = 0.5
        frame.size.height = generic.height - 1
        return frame
    }

    // MARK: - Drawing
    
    @objc func drawTabCell(_ cell: PSMTabBarCell, highlightAmount: CGFloat) {
        let horizontal = (_orientation == .horizontalOrientation)
        let isFirst = (cell == tabBar?.cells()?.first as? PSMTabBarCell)
        let isLast = (cell == tabBar?.cells()?.lastObject as? PSMTabBarCell)
        
        if cell.state == .on {
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize.zero
            shadow.shadowColor = NSColor.black
            shadow.shadowBlurRadius = 10.0
            shadow.set()
            cell.frame.fill()
        }
        drawCellBackgroundAndFrameHorizontallyOriented(
            horizontal,
            inRect: cell.frame,
            selected: cell.state == .on,
            withTabColor: cell.tabColor,
            isFirst: isFirst,
            isLast: isLast,
            highlightAmount: highlightAmount
        )
        
        drawInterior(with: cell, inView: cell.controlView, highlightAmount: highlightAmount)
    }
    
    private let barHeight = 28.0
    private var barRadius: CGFloat { barHeight / 2.0 }
    let containerSideInset = CGFloat(8)
    let containerTopInset = CGFloat(0)
    let containerBottomInset = CGFloat(0)

    @objc func drawBackground(in rect: NSRect, color: NSColor?, horizontal: Bool) {
        if _orientation == .verticalOrientation && (tabBar?.frame.size.width ?? 0) < 2 {
            return
        }
        
        NSGraphicsContext.saveGraphicsState()
        
        NSColor.windowBackgroundColor.set()
        rect.fill(using: .sourceOver)

        color?.set()
        
        NSBezierPath(roundedRect: NSRect(x: containerSideInset - 0.5,
                                         y: containerTopInset,
                                         width: rect.width - containerSideInset * 2 + 1,
                                         height: barHeight),
                     xRadius: barRadius,
                     yRadius: barRadius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    @objc func drawTabBar(_ bar: PSMTabBarControl, in rect: NSRect, clipRect: NSRect, horizontal: Bool, withOverflow: Bool) {
        if _orientation != bar.orientation {
            _orientation = bar.orientation
        }
        
        if tabBar !== bar {
            tabBar = bar
        }
        

        let backgroundColor = NSColor(white: 0.9, alpha: 1.0)
        var backgroundRect = rect
        if bar.showAddTabButton {
            backgroundRect.size.width -= 32.0
        }
        drawBackground(in: backgroundRect, color: backgroundColor, horizontal: horizontal)

        // no tab view == not connected
        guard let _ = bar.tabView else {
            var labelRect = rect
            labelRect.size.height -= 4.0
            labelRect.origin.y += 4.0
            
            let contents = "PSMTabBarControl"
            let attrStr = NSMutableAttributedString(string: contents)
            let range = NSRange(location: 0, length: contents.count)
            attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: range)
            
            let centeredParagraphStyle = NSMutableParagraphStyle()
            centeredParagraphStyle.alignment = .center
            attrStr.addAttribute(.paragraphStyle, value: centeredParagraphStyle, range: range)
            
            attrStr.draw(in: labelRect)
            return
        }
        // draw cells
        var drawableCells = ((bar.cells() as? [PSMTabBarCell]) ?? []).filter { cell in
            return !cell.isInOverflowMenu && NSIntersectsRect(cell.frame.insetBy(dx: -1, dy: -1), clipRect)
        }
        if let i = drawableCells.firstIndex(where: { $0.state == .on }) {
            let cell = drawableCells.remove(at: i)
            drawableCells.append(cell)
        }
        for cell in drawableCells {
            cell.draw(withFrame: cell.frame, in: bar)
        }

        if let selectedCell = drawableCells.first, selectedCell.state == .on {
            selectedCell.drawPostHocDecorations(onSelectedCell: selectedCell, tabBarControl: bar)
        }
    }
    
    @objc func accessoryFillColor() -> NSColor {
        return NSColor.windowBackgroundColor
    }
    
    @objc func accessoryStrokeColor() -> NSColor {
        return NSColor.darkGray
    }
    
    @objc func fill(_ path: NSBezierPath) {
        accessoryFillColor().set()
        path.fill()
        NSColor(calibratedWhite: 0.0, alpha: 0.2).set()
        path.fill()
        accessoryStrokeColor().set()
        path.stroke()
    }
    
    @objc func accessoryTextColor() -> NSColor {
        return NSColor.black
    }
    
    @objc func useLightControls() -> Bool {
        return false
    }
    
    // MARK: - Subclass Methods
    
    @objc func topLineColorSelected(_ selected: Bool) -> NSColor {
        return NSColor.clear
    }
    
    @objc func verticalLineColorSelected(_ selected: Bool) -> NSColor {
        return NSColor(white: 0, alpha: 0.07)
    }
    
    @objc func anyTabHasColor() -> Bool {
        guard let cells = tabBar?.cells() as? [PSMTabBarCell] else { return false }
        return cells.contains { $0.tabColor != nil }
    }
    
    @objc func tabColorBrightness(_ cell: PSMTabBarCell) -> CGFloat {
        let color = effectiveBackgroundColor(forTabWithTabColor: cell.tabColor,
                                            selected: cell.state == .on,
                                            highlightAmount: 0,
                                            window: cell.controlView?.window)
        
        // This gets blended over a NSVisualEffectView, whose color is a mystery. Assume it's
        // related to light/dark mode.
        let names = [NSAppearance.Name.darkAqua,
                    NSAppearance.Name.vibrantDark,
                    NSAppearance.Name.aqua,
                    NSAppearance.Name.vibrantLight]
        let bestMatch = tabBar?.effectiveAppearance.bestMatch(from: names)
        let frontAlpha = color.alphaComponent
        let frontBrightness = color.it_hspBrightness()
        let backBrightness: CGFloat
        
        if bestMatch == .darkAqua || bestMatch == .vibrantDark {
            backBrightness = 0
        } else {
            backBrightness = 1
        }
        return backBrightness * (1 - frontAlpha) + frontAlpha * frontBrightness
    }
    
    @objc func insetsForTabBarDividers() -> NSEdgeInsets {
        return NSEdgeInsets(top: 0, left: 0.5, bottom: 0, right: 2)
    }
    
    @objc func backgroundInsetsWithHorizontalOrientation(_ horizontal: Bool) -> NSEdgeInsets {
        return NSEdgeInsetsZero
    }
    
    @objc func effectiveBackgroundColor(forTabWithTabColor tabColor: NSColor?,
                                       selected: Bool,
                                       highlightAmount: CGFloat,
                                       window: NSWindow?) -> NSColor {
        DLog("Computing effective background color for tab with color \(String(describing: tabColor)) selected=\(selected) highlight=\(highlightAmount)")
        let base = backgroundColorSelected(selected, highlightAmount: highlightAmount).it_srgbForColor(in: window)
        DLog("base=\(base)")
        
        if let tabColor = tabColor {
            let cellbg = cellBackgroundColor(forTabColor: tabColor, selected: selected)
            DLog("cellbg=\(cellbg)")
            let overcoat = cellbg.it_srgbForColor(in: window)
            DLog("overcoat=\(overcoat)")
            
            let a = overcoat.alphaComponent
            let q = 1 - a
            let r = q * base.redComponent + a * overcoat.redComponent
            let g = q * base.greenComponent + a * overcoat.greenComponent
            let b = q * base.blueComponent + a * overcoat.blueComponent
            
            var components: [CGFloat] = [r, g, b, 1]
            let result = NSColor(colorSpace: tabColor.colorSpace, components: &components, count: 4)
            DLog("return \(String(describing: result))")
            return result
        } else {
            DLog("return base \(base)")
            return base
        }
    }
    
    @objc func drawCellBackgroundSelected(_ selected: Bool,
                                        inRect cellFrame: NSRect,
                                        withTabColor tabColor: NSColor?,
                                        highlightAmount: CGFloat,
                                        horizontal: Bool) {
        if let tabColor = tabColor {
            let color = cellBackgroundColor(forTabColor: tabColor, selected: selected)
            // Alpha the inactive tab's colors a bit to make it clear which tab is active.
            color.set()
        } else {
            backgroundColorSelected(selected, highlightAmount: highlightAmount).set()
        }

        let radius = barRadius - 2.5
        if selected || tabColor != nil {
            NSBezierPath(roundedRect: cellFrame.insetBy(dx: 2.0, dy: 2.0), xRadius: radius, yRadius: radius).fill()
        }
        if selected {
            NSColor.white.set()
            NSBezierPath(roundedRect: cellFrame.insetBy(dx: 2.0, dy: 2.0), xRadius: radius, yRadius: radius).stroke()
        }
        
    }

    @objc func drawSubtitle(_ cachedSubtitle: PSMCachedTitle?,
                          x labelPosition: CGFloat,
                          cell: PSMTabBarCell,
                          hasIcon drewIcon: Bool,
                          iconRect: NSRect,
                          reservedSpace: CGFloat,
                          cellFrame: NSRect,
                          labelOffset: CGFloat,
                          mainLabelHeight: CGFloat) {
        guard let cachedSubtitle = cachedSubtitle, !cachedSubtitle.isEmpty else {
            return
        }
        
        var labelRect = NSRect()
        labelRect.origin.x = labelPosition
        var boundingSize = NSSize()
        var truncate = false
        
        labelRect.size.width = widthForLabel(inCell: cell,
                                            labelPosition: labelPosition,
                                            hasIcon: drewIcon,
                                            iconRect: iconRect,
                                            cachedTitle: cachedSubtitle,
                                            reservedSpace: reservedSpace,
                                            boundingSize: &boundingSize,
                                            truncate: &truncate)
        
        labelRect.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - boundingSize.height) / 2.0) + labelOffset + mainLabelHeight + verticalOffsetForSubtitle()
        labelRect.size.height = boundingSize.height
        
        let attributedString = cachedSubtitle.attributedStringForcingLeftAlignment(truncate, truncatedForWidth: labelRect.size.width)
        if truncate {
            labelRect.origin.x += reservedSpace
        }
        
        attributedString.draw(in: labelRect)
    }
    
    @objc func widthForLabel(inCell cell: PSMTabBarCell,
                             labelPosition: CGFloat,
                             hasIcon drewIcon: Bool,
                             iconRect: NSRect,
                             cachedTitle: PSMCachedTitle,
                             reservedSpace: CGFloat,
                             boundingSize boundingSizePtr: UnsafeMutablePointer<NSSize>,
                             truncate truncatePtr: UnsafeMutablePointer<Bool>) -> CGFloat {
        let cellFrame = cell.frame
        var labelRect = NSRect(x: labelPosition,
                               y: 0,
                               width: cellFrame.size.width - (labelPosition - cellFrame.origin.x) - kPSMTabBarCellPadding,
                               height: cellFrame.size.height)
        
        if drewIcon {
            // Reduce size of label if there is an icon or activity indicator
            labelRect.size.width -= iconRect.size.width + kPSMTabBarCellIconPadding
        } else if !cell.indicator.isHidden {
            labelRect.size.width -= cell.indicator.frame.size.width + kPSMTabBarCellIconPadding
        }
        
        if cell.count > 0 {
            labelRect.size.width -= (objectCounterRect(forTabCell: cell).size.width + kPSMTabBarCellPadding)
        }
        
        let boundingSize = cachedTitle.boundingRect(with: labelRect.size).size
        
        var truncate = false
        if _orientation == .horizontalOrientation {
            let effectiveLeftMargin = (labelRect.size.width - boundingSize.width) / 2
            if effectiveLeftMargin < reservedSpace {
                labelRect.size.width -= reservedSpace
                truncate = true
            }
        }
        
        truncatePtr.pointee = truncate
        boundingSizePtr.pointee = boundingSize
        
        return labelRect.size.width
    }
    
    @objc func willDrawSubtitle(_ subtitle: PSMCachedTitle?) -> Bool {
        return supportsMultiLineLabels && subtitle != nil && !subtitle!.isEmpty
    }
    
    @objc func verticalOffsetForTitleWhenSubtitlePresent() -> CGFloat {
        return -5
    }
    
    @objc func verticalOffsetForSubtitle() -> CGFloat {
        return -2
    }
    
    @objc func shouldDrawTopLineSelected(_ selected: Bool, attached: Bool, position: PSMTabPosition) -> Bool {
        switch position {
        case .bottomTab, .leftTab:
            return true
        case .topTab:
            if !attached {
                return false
            }
            if !selected {
                return true
            }
            // Leave out the line on the selected tab when it's attached to the tabbar so it looks like
            // it's the same surface.
            return false
        @unknown default:
            it_fatalError()
        }
    }
    
    @objc func textColorDefaultSelected(_ selected: Bool, backgroundColor: NSColor?, windowIsMainAndAppIsActive mainAndActive: Bool) -> NSColor {
        let value: CGFloat
        if mainAndActive {
            value = 70
        } else {
            if selected {
                value = 177
            } else {
                value = 161
            }
        }
        return NSColor(srgbRed: value/255.0, green: value/255.0, blue: value/255.0, alpha: 1)
    }
    
    @objc func textColor(for cell: PSMTabBarCell) -> NSColor {
        DLog("cell=\(cell)")
        let selected = (cell.state == .on)
        
        if anyTabHasColor() {
            DLog("anyTabHasColor. computing tab color brightness.")
            let cellBrightness = tabColorBrightness(cell)
            DLog("brightness of \(cell) is \(cellBrightness)")
            
            if selected {
                DLog("is selected")
                // Select cell when any cell has a tab color
                if cellBrightness > 0.5 {
                    DLog("is bright. USE BLACK TEXT COLOR")
                    // bright tab
                    return NSColor.black
                } else {
                    DLog("is dark. Use white text")
                    // dark tab
                    return NSColor.white
                }
            } else {
                DLog("Not selected")
                // Non-selected cell when any cell has a tab color
                let prominence = (tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.coloredUnselectedTabTextProminence) as? NSNumber)?.doubleValue ?? 0.5
                if cellBrightness > 0.5 {
                    // Light tab
                    return NSColor(white: 0, alpha: prominence)
                } else {
                    // Dark tab
                    return NSColor(white: 1, alpha: prominence)
                }
            }
        } else {
            DLog("No tab has color")
            // No cell has a tab color
            let mainAndActive = windowIsMainAndAppIsActive
            if selected {
                DLog("selected")
                return textColorDefaultSelected(true, backgroundColor: nil, windowIsMainAndAppIsActive: mainAndActive)
            } else {
                DLog("not selected")
                return textColorDefaultSelected(false, backgroundColor: nil, windowIsMainAndAppIsActive: mainAndActive)
            }
        }
    }
    
    @objc func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected {
            return NSColor(white: 0.97, alpha: 1.0)
        } else {
            return NSColor(white: 0, alpha: highlightAmount * 0.2)
        }
    }
    
    @objc func drawPostHocDecorations(onSelectedCell cell: PSMTabBarCell, tabBarControl bar: PSMTabBarControl) {
        if anyTabHasColor() {
            let brightness = tabColorBrightness(cell)
            var rect = cell.frame.insetBy(dx: -0.5, dy: 0.5)
            
            let strengthNumber = bar.delegate?.tabView?(bar, valueOfOption: PSMTabBarControlOptionKey.coloredSelectedTabOutlineStrength) as? NSNumber ?? NSNumber(value: 0.5)
            let strength = strengthNumber.doubleValue
            let keyMainAndActive = windowIsMainAndAppIsActive
            let alpha = min(max(strength, 0), 1) * (keyMainAndActive ? 1 : 0.6)
            
            let outerColor: NSColor
            let innerColor: NSColor
            if brightness > 0.5 {
                outerColor = NSColor(white: 1, alpha: alpha)
                innerColor = NSColor(white: 0, alpha: alpha)
            } else {
                outerColor = NSColor(white: 0, alpha: alpha)
                innerColor = NSColor(white: 1, alpha: alpha)
            }
            
            outerColor.set()
            let width = min(max(strength, 1), 3)
            rect = rect.insetBy(dx: width - 1, dy: width - 1)
            var path = NSBezierPath(rect: rect)
            path.lineWidth = width
            path.stroke()
            
            innerColor.set()
            rect = rect.insetBy(dx: width, dy: width)
            path = NSBezierPath(rect: rect)
            path.lineWidth = width
            path.stroke()
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func retinaRoundUpCell(_ cell: PSMTabBarCell, value: CGFloat) -> CGFloat {
        guard let window = cell.controlView?.window else {
            return ceil(value)
        }
        
        var scale = window.backingScaleFactor
        if scale == 0 {
            scale = NSScreen.main?.backingScaleFactor ?? 1
        }
        if scale == 0 {
            scale = 1
        }
        
        return ceil(scale * value) / scale
    }
    
    private func widthOfLeftMatterInCell(_ cell: PSMTabBarCell) -> CGFloat {
        var resultWidth: CGFloat = 0.0
        
        // left margin
        resultWidth = kSPMTabBarCellInternalXMargin
        
        // close button?
        resultWidth += (_closeButton?.size.width ?? 0) + kPSMTabBarCellPadding
        
        // icon?
        if cell.hasIcon {
            resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellIconPadding
        }
        
        return resultWidth
    }
    
    private func widthOfRightMatterInCell(_ cell: PSMTabBarCell) -> CGFloat {
        var resultWidth: CGFloat = 0
        
        // object counter?
        if cell.count > 0 {
            resultWidth += objectCounterRect(forTabCell: cell).size.width + kPSMTabBarCellPadding
        } else {
            resultWidth += (_closeButton?.size.width ?? 0) + kPSMTabBarCellPadding
        }
        
        // indicator?
        if !cell.indicator.isHidden {
            resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth
        }
        
        // right margin
        resultWidth += kSPMTabBarCellInternalXMargin
        
        return resultWidth
    }
    
    private func widthOfAttributedStringInCell(_ cell: PSMTabBarCell) -> CGFloat {
        let attributedString = cell.attributedStringValue
        if !cell.previousAttributedString.isEqual(to: attributedString) {
            cell.previousAttributedString = attributedString
            let width = attributedString.size().width
            cell.previousWidthOfAttributedString = width
            return width
        } else {
            return cell.previousWidthOfAttributedString
        }
    }
    
    private var fontSize: CGFloat {
        if let override = tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
            return CGFloat(override.doubleValue)
        }
        return 11.0
    }
    
    private var subtitleFontSize: CGFloat {
        return round(fontSize * 0.8)
    }
    
    private func bottomLineColorSelected(_ selected: Bool) -> NSColor {
        return NSColor(srgbRed: 230.0/255.0, green: 230.0/255.0, blue: 230.0/255.0, alpha: 1)
    }
    
    @available(macOS 10.16, *)
    private func bigSurBackgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected {
            // Reveal the visual effect view with material NSVisualEffectMaterialTitlebar beneath the tab bar.
            return NSColor.clear
        }
        // `base` gives how much darker the unselected tab is as an alpha value.
        let base = (tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.lightModeInactiveTabDarkness) as? NSNumber)?.doubleValue ?? 0.1
        return NSColor(white: 0, alpha: base + (1 - base) * (highlightAmount * 0.05))
    }
    
    @available(macOS 10.14, *)
    private func mojaveBackgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        var colors: [CGFloat] = [0, 0, 0]
        let keyMainAndActive = windowIsMainAndAppIsActive
        
        if keyMainAndActive {
            if selected {
                colors[0] = 210.0 / 255.0
                colors[1] = 210.0 / 255.0
                colors[2] = 210.0 / 255.0
            } else {
                let color = tabBarColor
                colors[0] = color.redComponent
                colors[1] = color.greenComponent
                colors[2] = color.blueComponent
            }
        } else {
            if selected {
                colors[0] = 246.0 / 255.0
                colors[1] = 246.0 / 255.0
                colors[2] = 246.0 / 255.0
            } else {
                let color = tabBarColor
                colors[0] = color.redComponent
                colors[1] = color.greenComponent
                colors[2] = color.blueComponent
            }
        }
        
        let highlightedColors: [CGFloat] = [0, 0, 0]
        var a: CGFloat = 0
        if !selected {
            a = highlightAmount * 0.05
        }
        
        for i in 0..<3 {
            colors[i] = colors[i] * (1.0 - a) + highlightedColors[i] * a
        }
        
        return NSColor(srgbRed: colors[0], green: colors[1], blue: colors[2], alpha: 1)
    }
    
    private func cellBackgroundColor(forTabColor tabColor: NSColor, selected: Bool) -> NSColor {
        // Alpha the non-key window's tab colors a bit to make it clearer which window is key.
        let keyMainAndActive = windowIsMainAndAppIsActive
        let alpha: CGFloat
        
        if keyMainAndActive {
            alpha = selected ? 1 : 0.4
        } else {
            alpha = selected ? 0.6 : 0.3
        }
        
        var components: [CGFloat] = [0, 0, 0, 0]
        tabColor.getComponents(&components)
        for i in 0..<3 {
            components[i] = components[i] * alpha + 0.5 * (1 - alpha)
        }
        
        return NSColor(colorSpace: tabColor.colorSpace, components: &components, count: 4)
    }
    
    private func drawHorizontalLine(inFrame rect: NSRect, y: CGFloat) {
        NSRect(x: rect.minX, y: y, width: rect.size.width + 1, height: 1).fill(using: .sourceOver)
    }
    
    private func drawVerticalLine(inFrame rect: NSRect, x: CGFloat) {
        let topInset: CGFloat = 1
        let bottomInset: CGFloat = 0
        let modifiedRect = NSRect(x: x, y: rect.minY + topInset, width: 1, height: rect.size.height - topInset - bottomInset)
        modifiedRect.fill(using: .sourceOver)
    }
    
    private func drawCellBackgroundAndFrameHorizontallyOriented(_ horizontal: Bool,
                                                               inRect cellFrame: NSRect,
                                                               selected: Bool,
                                                               withTabColor tabColor: NSColor?,
                                                               isFirst: Bool?,
                                                               isLast: Bool?,
                                                               highlightAmount: CGFloat) {
        drawCellBackgroundSelected(selected,
                                   inRect: cellFrame,
                                   withTabColor: tabColor,
                                   highlightAmount: highlightAmount,
                                   horizontal: horizontal)
        
        if horizontal {
        } else {
            // Bottom line
            verticalLineColorSelected(selected).set()
            let insets = insetsForTabBarDividers()
            var modifiedFrame = cellFrame
            modifiedFrame.origin.x += insets.left
            modifiedFrame.size.width -= (insets.left + insets.right)
            drawHorizontalLine(inFrame: modifiedFrame, y: modifiedFrame.maxY - 1)
        }
    }
    
    private func drawInterior(with cell: PSMTabBarCell, inView controlView: NSView?, highlightAmount: CGFloat) {
        let cellFrame = cell.frame
        var labelPosition = cellFrame.origin.x + kSPMTabBarCellInternalXMargin
        
        // close button
        var closeButtonSize = NSZeroSize
        let closeButtonRect = cell.closeButtonRect(forFrame: cellFrame)
        var closeButton = _closeButton
        
        if cell.closeButtonOver {
            closeButton = _closeButtonOver
        }
        if cell.closeButtonPressed {
            closeButton = _closeButtonDown
        }
        
        let closeButtonTintColor: NSColor
        let colorKey: UnsafeRawPointer
        if tabColorBrightness(cell) < 0.5 {
            colorKey = PSMTabStyleLightColorKey
            closeButtonTintColor = NSColor.white
        } else {
            colorKey = PSMTabStyleDarkColorKey
            closeButtonTintColor = NSColor.black
        }
        
        closeButton = closeButton?.it_cachingImage(withTintColor: closeButtonTintColor, key: colorKey)
        
        var reservedSpace: CGFloat = 0
        closeButtonSize = closeButton?.size ?? NSZeroSize
        let cachedTitle = cell.cachedTitle
        
        if cell.hasCloseButton {
            if cell.isCloseButtonSuppressed && _orientation == .horizontalOrientation {
                // Do not use this much space on the left for the label, but the label is centered as
                // though it is not reserved if it's not too long.
                reservedSpace = closeButtonSize.width + kPSMTabBarCellPadding
            } else {
                labelPosition += closeButtonSize.width + kPSMTabBarCellPadding
            }
        }
        
        // Draw close button
        var closeButtonAlpha: CGFloat = 0
        if cell.hasCloseButton && cell.closeButtonVisible {
            if cell.isCloseButtonSuppressed {
                closeButtonAlpha = highlightAmount
            } else {
                closeButtonAlpha = 1
            }
            
            let keyMainAndActive = windowIsMainAndAppIsActive
            if !keyMainAndActive {
                closeButtonAlpha /= 2
            }
            
            closeButton?.draw(at: closeButtonRect.origin,
                             from: NSZeroRect,
                             operation: .sourceOver,
                             fraction: closeButtonAlpha)
        }
        
        // Draw graphic icon (i.e., the app icon, not new-output indicator icon) over close button.
        if let graphic = cachedTitle?.inputs.graphic {
            let width = drawGraphic(withCellFrame: cellFrame, image: graphic, alpha: 1 - closeButtonAlpha)
            if _orientation == .horizontalOrientation {
                reservedSpace = max(reservedSpace, width)
            } else {
                labelPosition = max(labelPosition, width + kPSMTabBarCellPadding)
            }
        }
        
        // icon
        var drewIcon = false
        var iconRect = NSZeroRect
        if cell.hasIcon {
            // There is an icon. Draw it as long as the amount of space left for the label is more than
            // the size of the icon. This is a heuristic to roughly prioritize the label over the icon.
            var boundingSize = NSSize()
            var truncate = false
            let labelWidth = widthForLabel(inCell: cell,
                                          labelPosition: labelPosition,
                                          hasIcon: true,
                                          iconRect: iconRect,
                                          cachedTitle: cachedTitle!,
                                          reservedSpace: reservedSpace,
                                          boundingSize: &boundingSize,
                                          truncate: &truncate)
            let tabViewItem = cell.representedObject as? NSTabViewItem
            let tab = tabViewItem?.identifier as? PSMTabBarControlRepresentedObjectIdentifierProtocol
            let icon = tab?.icon?()
            let minimumLabelWidth = (tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.minimumSpaceForLabel) as? NSNumber)?.doubleValue ?? 0
            
            if labelWidth > minimumLabelWidth {
                drewIcon = true
                iconRect = self.iconRect(forTabCell: cell)
                
                // center in available space (in case icon image is smaller than kPSMTabBarIconWidth)
                if let iconSize = icon?.size {
                    if iconSize.width < kPSMTabBarIconWidth {
                        iconRect.origin.x += (kPSMTabBarIconWidth - iconSize.width) / 2.0
                    }
                    if iconSize.height < kPSMTabBarIconWidth {
                        iconRect.origin.y -= (kPSMTabBarIconWidth - iconSize.height) / 2.0
                    }
                }
                
                icon?.draw(in: iconRect,
                          from: NSZeroRect,
                          operation: .sourceOver,
                          fraction: 1.0,
                          respectFlipped: true,
                          hints: nil)
            }
        }
        
        // object counter
        if cell.count > 0 {
            let myRect = objectCounterRect(forTabCell: cell)
            // draw attributed string centered in area
            var counterStringRect = NSRect()
            let counterString = attributedObjectCountValue(forTabCell: cell)
            counterStringRect.size = counterString.size()
            counterStringRect.origin.x = myRect.origin.x + floor((myRect.size.width - counterStringRect.size.width) / 2.0)
            counterStringRect.origin.y = myRect.origin.y + floor((myRect.size.height - counterStringRect.size.height) / 2.0)
            counterString.draw(in: counterStringRect)
        }
        
        // label rect
        var mainLabelHeight: CGFloat = 0
        let cachedSubtitle = cell.cachedSubtitle
        let labelOffset = willDrawSubtitle(cachedSubtitle) ? verticalOffsetForTitleWhenSubtitlePresent() : 0
        
        if let cachedTitle = cachedTitle, !cachedTitle.isEmpty {
            var labelRect = NSRect()
            labelRect.origin.x = labelPosition
            var boundingSize = NSSize()
            var truncate = false
            
            labelRect.size.width = widthForLabel(inCell: cell,
                                                labelPosition: labelPosition,
                                                hasIcon: drewIcon,
                                                iconRect: iconRect,
                                                cachedTitle: cachedTitle,
                                                reservedSpace: reservedSpace,
                                                boundingSize: &boundingSize,
                                                truncate: &truncate)
            
            labelRect.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - boundingSize.height) / 2.0) + labelOffset
            labelRect.size.height = boundingSize.height
            
            let attributedString = cachedTitle.attributedStringForcingLeftAlignment(truncate,
                                                                                    truncatedForWidth: labelRect.size.width)
            if truncate {
                labelRect.origin.x += reservedSpace
            }
            
            attributedString.draw(in: labelRect)
            mainLabelHeight = labelRect.height
        }
        
        if supportsMultiLineLabels {
            drawSubtitle(cachedSubtitle,
                        x: labelPosition,
                        cell: cell,
                        hasIcon: drewIcon,
                        iconRect: iconRect,
                        reservedSpace: reservedSpace,
                        cellFrame: cellFrame,
                        labelOffset: labelOffset,
                        mainLabelHeight: mainLabelHeight)
        }
    }
    
    private func drawGraphic(withCellFrame cellFrame: NSRect, image: NSImage, alpha: CGFloat) -> CGFloat {
        let rect = NSRect(x: cellFrame.minX + 6,
                         y: cellFrame.minY + (cellFrame.height - kPSMTabBarIconWidth) / 2.0,
                         width: kPSMTabBarIconWidth,
                         height: kPSMTabBarIconWidth)
        image.draw(in: rect,
                  from: NSZeroRect,
                  operation: .sourceOver,
                  fraction: alpha,
                  respectFlipped: true,
                  hints: nil)
        return rect.width + kPSMTabBarCellPadding + 2
    }
}

// MARK: - Debugging

private func DLog(_ message: String) {
    // Implementation depends on how gDebugLogging is set up in your project
    // For now, this is a no-op in Swift
    #if DEBUG
    // print("[PSMTahoeTabStyle] \(message)")
    #endif
}
