//
//  PSMTahoeTabStyle.swift
//  iTerm2
//
//  Created by George Nachman on 8/21/25.
//

import Cocoa

#if compiler(>=6.2)
fileprivate let kPSMMetalObjectCounterRadius: CGFloat = 7.0
fileprivate let kPSMMetalCounterMinWidth: CGFloat = 20
fileprivate let PSMTahoeTabStyleDebuggingEnabled: Bool = false

@objc
@available(macOS 26, *)
class PSMTahoeTabStyle: NSObject, PSMTabStyle {
   
    // MARK: - Private Properties
    private var _closeButton: NSImage?
    private var _closeButtonDown: NSImage?
    private var _closeButtonOver: NSImage?
    private var _orientation: PSMTabBarOrientation = .horizontalOrientation
    
    // MARK: - PSMTabStyle Properties
    @objc weak var tabBar: PSMTabBarControl?
    
    @objc var tabBarColor: NSColor {
        return NSColor(srgbRed: 225.0 / 255.0,
                       green: 225.0 / 255.0,
                       blue: 225.0 / 255.0,
                       alpha: 1)
    }
    
    @objc var orientation: PSMTabBarOrientation {
        set {
            _orientation = newValue
        }
        get {
            return _orientation
        }
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
        1.0
    }
    
    @objc var supportsMultiLineLabels: Bool {
        true
    }
    
    // MARK: - Initialization
    
    class var closeButtonDownColor: NSColor {
        NSColor(white: 0, alpha: 0.27)
    }
    
    class var closeButtonOverColor: NSColor {
        NSColor(white: 0, alpha: 0.10)
    }
    
    class var xmarkSymbolConfiguration: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
    }
    
    override init() {
        super.init()
        
        // Load close buttons
        let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!.withSymbolConfiguration(Self.xmarkSymbolConfiguration)
        let buttonSize = 15.0
        let xSize = 8.0
        _closeButton = NSImage(size: NSSize(width: buttonSize, height: buttonSize), flipped: false, drawingHandler: { rect in
            NSColor.clear.set()
            rect.fill(using: .sourceOver)

            xmark?.draw(in: rect.insetBy(dx: (rect.width - xSize) / 2.0, dy: (rect.height - xSize) / 2.0))
            return true
        })
        _closeButton?.isTemplate = true

        _closeButtonDown = NSImage(size: NSSize(width: buttonSize, height: buttonSize), flipped: false, drawingHandler: { rect in
            NSColor.clear.set()
            rect.fill(using: .sourceOver)

            Self.closeButtonDownColor.set()
            NSBezierPath(ovalIn: rect.insetBy(dx: (rect.width - buttonSize) / 2.0, dy: (rect.height - buttonSize) / 2.0)).fill()
            
            xmark?.draw(in: rect.insetBy(dx: (rect.width - xSize) / 2.0, dy: (rect.height - xSize) / 2.0))
            return true
        })
        _closeButtonDown?.isTemplate = true

        _closeButtonOver = NSImage(size: NSSize(width: buttonSize, height: buttonSize), flipped: false, drawingHandler: { rect in
            NSColor.clear.set()
            rect.fill(using: .sourceOver)

            Self.closeButtonOverColor.set()
            NSBezierPath(ovalIn: rect.insetBy(dx: (rect.width - buttonSize) / 2.0, dy: (rect.height - buttonSize) / 2.0)).fill()
            
            xmark?.draw(in: rect.insetBy(dx: (rect.width - xSize) / 2.0, dy: (rect.height - xSize) / 2.0))
            return true
        })
        _closeButtonOver?.isTemplate = true
    }

    // MARK: - PSMTabStyle Protocol
    
    @objc static var horizontalTabBarHeight = 36.0
    
    var tabBarHeight: CGFloat {
        if orientation == .horizontalOrientation {
            return Self.horizontalTabBarHeight
        } else {
            return max(26.0, iTermAdvancedSettingsModel.defaultTabBarHeight())
        }
    }

    func frameForOverflowButton(withAddTabButton showAddTabButton: Bool, enclosureSize: NSSize, standardHeight: CGFloat) -> NSRect {
        if orientation == .horizontalOrientation {
            return NSRect(x: enclosureSize.width - 36,
                          y: containerTopInset,
                          width: 28,
                          height: 28)
        }
        return NSRect(x: enclosureSize.width - 30, y: enclosureSize.height - 30, width: 24, height: 24)
    }

    @objc func makeAddTabButton(withFrame frame: NSRect) -> PSMRolloverButton {
        return PSMTahoeRolloverButton(symbolName: "plus")
    }
    
    func makeOverflowButton(withFrame frame: NSRect) -> NSButton! {
        return PSMTahoeOverflowButton()
    }

    @objc func name() -> String {
        return "Tahoe"
    }
    
    func frameForAddTabButton(withCellWidths widths: [NSNumber]!, height: CGFloat) -> NSRect {
        guard let tabBar else {
            return .zero
        }
        return NSRect(x: tabBar.bounds.width - 36,
                      y: containerTopInset,
                      width: 28,
                      height: 28)
    }

    // MARK: - Control Specific
    
    @objc func leftMarginForTabBarControl() -> Float {
        return Float(tabBar?.insets.left ?? 0) + 2.0
    }
    
    @objc func rightMarginForTabBarControl(withOverflow: Bool, addTabButton: Bool) -> Float {
        if withOverflow || addTabButton {
            return 32.0 + Float(tabBar?.insets.right ?? 0) + 2.0
        }
        return 2.0
    }
    
    @objc func topMarginForTabBarControl() -> Float {
        return Float(tabBar?.insets.top ?? 0)
    }
    
    // MARK: - Add Tab Button
    
    @objc var addTabButtonSize: NSSize {
        return NSSize(width: 28, height: 28)
    }

    @objc func addTabButtonImage() -> NSImage? {
        return nil
    }
    
    @objc func addTabButtonPressedImage() -> NSImage? {
        return nil
    }
    
    @objc func addTabButtonRolloverImage() -> NSImage? {
        return nil
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
    
    private static func centeredMinY(cell: PSMTabBarCell, height: CGFloat) -> CGFloat {
        cell.frame.origin.y + floor((cell.frame.size.height - height) / 2.0) - 1
    }
    
    @objc func indicatorRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        return Self.indicatorRect(forTabCell: cell,
                                  fontSize: fontSize)
    }
    
    private static func indicatorRect(forTabCell cell: PSMTabBarCell,
                                      fontSize: CGFloat) -> NSRect {
        let cellFrame = cell.frame
        
        let minX: CGFloat
        // Indicator on the right edge of the tab
        minX = cellFrame.maxX - kSPMTabBarCellInternalXMargin
        
        var result = NSRect()
        result.size = NSSize(width: kPSMTabBarIndicatorWidth, height: kPSMTabBarIndicatorWidth)
        result.origin.x = minX - kPSMTabBarCellIconPadding - kPSMTabBarIndicatorWidth
        result.origin.y = cellFrame.origin.y + round((cellFrame.size.height - result.size.height) / 2.0)

        return result
    }
    
    @objc
    func objectCounterRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        return Self.objectCounterRect(forTabCell: cell,
                                      fontSize: fontSize)
    }
    
    private static func objectCounterRect(forTabCell cell: PSMTabBarCell,
                                          fontSize: CGFloat) -> NSRect {
        let cellFrame = cell.frame
        
        if cell.count == 0 {
            return NSZeroRect
        }
        
        var countWidth = retinaRoundUpCell(cell, value: attributedObjectCountValue(forTabCell: cell,
                                                                                   fontSize: fontSize,
                                                                                   textColor: .black).size().width)
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
    
    @objc
    func attributedObjectCountValue(forTabCell cell: PSMTabBarCell) -> NSAttributedString {
        return Self.attributedObjectCountValue(forTabCell: cell,
                                               fontSize: fontSize,
                                               textColor: textColor(for: cell))
    }
    
    private static func attributedObjectCountValue(forTabCell cell: PSMTabBarCell,
                                                   fontSize: CGFloat,
                                                   textColor: NSColor) -> NSAttributedString {
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
            .font: NSFont.systemFont(ofSize: fontSize, weight: .light),
            .foregroundColor: textColor
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
        if _orientation == .horizontalOrientation {
            frame.origin.y = containerTopInset
        } else {
            frame = frame.insetBy(dx: 4, dy: 0)
        }
        frame.size.height = generic.height - 1
        return frame
    }
    
    // MARK: - Drawing
    
    private static let rightDropShadow: NSImage = {
        Bundle(for: PSMTahoeTabStyle.self).image(forResource: "TahoeTabBarShadow")!
    }()
    
    private static let leftDropShadow: NSImage = {
        rightDropShadow.it_horizontallyFlipped()
    }()
    
    private static let maxAlphaForVerticalDropShadows = 0.07
    private static let topDropShadow: NSImage = {
        return NSImage(size: NSSize(width: 16, height: 56), flipped: false) { rect in
            let gradient = NSGradient(starting: .init(white: 0, alpha: 0),
                                      ending: .init(white: 0, alpha: maxAlphaForVerticalDropShadows))!
            gradient.draw(in: rect, angle: 270)
            return true
        }
    }()

    private static let bottomDropShadow: NSImage = {
        return NSImage(size: NSSize(width: 16, height: 56), flipped: false) { rect in
            let gradient = NSGradient(starting: .init(white: 0, alpha: 0),
                                      ending: .init(white: 0, alpha: maxAlphaForVerticalDropShadows))!
            gradient.draw(in: rect, angle: 90)
            return true
        }
    }()

    @objc func dirtyFrame(for cell: PSMTabBarCell!) -> NSRect {
        return cell.frame.insetBy(dx: -Self.leftDropShadow.size.width, dy: -Self.topDropShadow.size.height)
    }
    
    @objc func drawTabCell(_ cell: PSMTabBarCell, highlightAmount: CGFloat) {
        let horizontal = (_orientation == .horizontalOrientation)
        let isFirst = (cell == tabBar?.cells()?.first as? PSMTabBarCell)
        let isLast = (cell == tabBar?.cells()?.lastObject as? PSMTabBarCell)
        
        if tabBar?.window?.isKeyWindow == true {
            if cell.state == .on {
                drawDropShadow(cell: cell)
            }
        }
        drawCellBackgroundAndFrameHorizontallyOriented(
            horizontal,
            inRect: cell.frame,
            selected: cell.state == .on,
            withTabColor: cell.tabColor,
            isFirst: isFirst,
            isLast: isLast,
            highlightAmount: highlightAmount,
            isHighlighted: cell.isHighlighted)
        drawInterior(with: cell, inView: cell.controlView, highlightAmount: highlightAmount)
        
        if PSMTahoeTabStyleDebuggingEnabled {
            NSColor.red.set()
            cell.frame.frame(withWidth: 0.5)
        }
    }
    
    private func drawDropShadow(cell: PSMTabBarCell) {
        let scale = cell.controlView?.window?.backingScaleFactor ?? 2.0
        
        switch orientation {
        case .horizontalOrientation:
            let leftShadow = Self.rightDropShadow
            let shadowSize = leftShadow.size
            // The drop shadow image is the left side of the shadow.
            // The rightmost 30 pixels include the left portion of a tab.
            let offset = CGFloat(30 / scale)
            let leftDestinationRect = NSRect(x: cell.frame.minX - shadowSize.width + offset,
                                             y: cell.frame.minY - 0.5,
                                             width: shadowSize.width,
                                             height: shadowSize.height)
            leftShadow.draw(in: leftDestinationRect)
            
            let rightShadow = Self.leftDropShadow
            let rightDestinationRect = NSRect(x: cell.frame.maxX - offset,
                                              y: cell.frame.minY - 0.5,
                                              width: shadowSize.width,
                                              height: shadowSize.height)
            rightShadow.draw(in: rightDestinationRect)
            
            NSColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.027).set()
            // If the drop shadow image changes you can get the new RGBA values by uncommenting these print statements:
            // print(rightShadow.color(at: CGPoint(x: 0, y: 0))!.usingColorSpace(NSColorSpace.displayP3)!)
            // print(rightShadow.color(at: CGPoint(x: 0, y: shadowSize.height - 1))!.usingColorSpace(NSColorSpace.displayP3)!)
            NSRect(x: cell.frame.minX + offset, y: cell.frame.minY - 0.5, width: cell.frame.width - offset * 2, height: 2).fill()
            
            NSColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.035).set()
            NSRect(x: cell.frame.minX + offset, y: cell.frame.maxY - 1.5, width: cell.frame.width - offset * 2, height: 2).fill()
        case .verticalOrientation:
            let offset = CGFloat(10 / scale)
            let shadowSize = Self.topDropShadow.size
            let topDestinationRect = NSRect(x: cell.frame.minX,
                                            y: cell.frame.minY - shadowSize.height + offset,
                                            width: cell.frame.width,
                                            height: shadowSize.height)
            Self.topDropShadow.draw(in: topDestinationRect)
            
            let bottomDestinationRect = NSRect(x: cell.frame.minX,
                                               y: cell.frame.maxY - offset,
                                               width: cell.frame.width,
                                               height: shadowSize.height)
            Self.bottomDropShadow.draw(in: bottomDestinationRect)
            
            NSColor(white: 0, alpha: Self.maxAlphaForVerticalDropShadows).set()
            let midRect = NSRect(x: cell.frame.minX,
                                 y: cell.frame.minY + offset,
                                 width: cell.frame.width,
                                 height: cell.frame.height - offset * 2)
            midRect.fill()
            break
        @unknown default:
            it_fatalError()
        }
    }

    private let barHeight = 28.0
    private var barRadius: CGFloat { barHeight / 2.0 }
    let containerSideInset = CGFloat(8)
    var containerTopInset: CGFloat {
        tabBar?.insets.top ?? 0.0
    }
    let containerBottomInset = CGFloat(0)
    
    private func clippingPath(rect: NSRect) -> NSBezierPath {
        if orientation == .horizontalOrientation {
            return NSBezierPath(roundedRect: NSRect(x: containerSideInset - 0.5,
                                                    y: containerTopInset,
                                                    width: rect.width - containerSideInset * 2 + 1,
                                                    height: barHeight),
                                xRadius: barRadius,
                                yRadius: barRadius)
        } else {
            return NSBezierPath(rect: rect)
        }
    }
    
    @objc func drawBackground(in rect: NSRect, color: NSColor?, horizontal: Bool) {
        if _orientation == .verticalOrientation && (tabBar?.frame.size.width ?? 0) < 2 {
            return
        }
        
        NSGraphicsContext.saveGraphicsState()
        
        NSColor.clear.set()
        rect.fill(using: .sourceOver)
        
        color?.set()

        clippingPath(rect: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    class var backgroundColor: NSColor {
        NSColor(white: 0.9, alpha: 1.0)
    }
    
    @objc func drawTabBar(_ bar: PSMTabBarControl, in rect: NSRect, clipRect: NSRect, horizontal: Bool, withOverflow: Bool) {
        if _orientation != bar.orientation {
            _orientation = bar.orientation
        }
        
        if tabBar !== bar {
            tabBar = bar
        }
        
        
        let backgroundColor = Self.backgroundColor
        var backgroundRect = rect
        if bar.showAddTabButton {
            backgroundRect.size.width -= 32.0
        }

        drawBackground(in: backgroundRect, color: backgroundColor, horizontal: horizontal)
        NSGraphicsContext.current?.saveGraphicsState()
        defer {
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        clippingPath(rect: backgroundRect).addClip()
        
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

        if drawableCells.count > 0 {
            if let i = drawableCells.firstIndex(where: { $0.state == .on }) {
                let cell = drawableCells.remove(at: i)
                drawableCells.append(cell)
            }
            for cell in drawableCells {
                cell.draw(withFrame: cell.frame, in: bar)
            }
            // For divider drawing, filter out zero-width placeholder cells first
            // so dividers are drawn between actual visible cells
            let cellsForDividers = drawableCells.filter { cell in
                if cell.isPlaceholder {
                    return orientation == .horizontalOrientation ? cell.frame.width > 0 : cell.frame.height > 0
                }
                return true
            }
            let sorted = cellsForDividers.sorted { lhs, rhs in
                if orientation == .horizontalOrientation {
                    lhs.frame.minX < rhs.frame.minX
                } else {
                    lhs.frame.minY < rhs.frame.minY
                }
            }
            for i in 0..<(sorted.count - 1) {
                drawDivider(betweenCell: sorted[i], andCell: sorted[i + 1])
            }
            if let selectedCell = drawableCells.first, selectedCell.state == .on {
                selectedCell.drawPostHocDecorations(onSelectedCell: selectedCell, tabBarControl: bar)
            }
        }
    }

    var dividerColor: NSColor {
        NSColor(displayP3Red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
    }

    func drawDivider(betweenCell leftCell: PSMTabBarCell, andCell rightCell: PSMTabBarCell) {
        if orientation != .horizontalOrientation {
            return
        }
        if leftCell.isHighlighted || rightCell.isHighlighted || leftCell.state == .on || rightCell.state == .on {
            return
        }
        guard let cells = tabBar?.cells() as? [PSMTabBarCell], cells.count >= 3 else {
            return
        }
        dividerColor.set()
        let rect = NSRect(x: leftCell.frame.maxX,
                          y: leftCell.frame.minY + 5,
                          width: 1.0,
                          height: leftCell.frame.height - 10)
        reallyDrawDivider(rect: rect)
    }

    func reallyDrawDivider(rect: NSRect) {
        rect.fill(using: .sourceOver)
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
    
    class var outlineColor: NSColor {
        NSColor.white
    }
    
    @objc func drawCellBackgroundSelected(_ selected: Bool,
                                          inRect cellFrame: NSRect,
                                          withTabColor tabColor: NSColor?,
                                          highlightAmount: CGFloat,
                                          horizontal: Bool,
                                          isHighlighted: Bool) {
        backgroundColorSelected(selected, highlightAmount: isHighlighted ? 1.0 : 0.0).set()
        
        let radius = barRadius - 2.5
        var rect = cellFrame
        rect.origin.y += 2
        rect.size.height -= 3
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.fill()
        if selected {
            drawCellOutline(path: path, rect: rect, radius: radius)
        }

        if let tabColor {
            let color = cellBackgroundColor(forTabColor: tabColor, selected: true)
            color.set()
            if selected {
                // Tint the outline if this cell is selected.
                NSGraphicsContext.current?.saveGraphicsState()
                path.addClip()
                rect.fill(using: .color)
                
                NSColor(white: 1.0, alpha: tabColor.perceivedBrightness).set()
                rect.fill(using: .plusLighter)
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            
            // Tint the inside.
            if selected {
                let path2 = NSBezierPath(roundedRect: rect.insetBy(dx: 1.0, dy: 1.0),
                                         xRadius: radius - 1.0,
                                         yRadius: radius - 1.0)
                path2.fill()
            } else {
                let path2 = NSBezierPath(roundedRect: rect,
                                         xRadius: radius,
                                         yRadius: radius)
                NSGraphicsContext.current?.saveGraphicsState()
                defer {
                    NSGraphicsContext.current?.restoreGraphicsState()
                }
                path2.addClip()
                path2.lineWidth = 4.0
                path2.stroke()

                color.withAlphaComponent(0.1).set()
                path2.fill()
            }
        }
    }
    
    func drawCellOutline(path: NSBezierPath, rect: NSRect, radius: CGFloat) {
        Self.outlineColor.set()
        path.stroke()
    }
    
    func drawSubtitle(cell: PSMTabBarCell,
                      orientation: PSMTabBarOrientation,
                      xOrigin: CGFloat,
                      maxWidth: CGFloat,
                      labelOffset: CGFloat,
                      mainLabelHeight: CGFloat) {
        guard let cachedSubtitle = cell.cachedSubtitle, !cachedSubtitle.isEmpty else {
            return
        }
        
        let attributedString = cachedSubtitle.attributedStringForcingLeftAlignment(orientation == .verticalOrientation,
                                                                                   truncatedForWidth: maxWidth)
        let boundingSize = cachedSubtitle.boundingRect(with: NSSize(width: maxWidth, height: cell.frame.height)).size
        var labelRect = NSRect()
        labelRect.origin.x = xOrigin
        labelRect.origin.y = cell.frame.origin.y + floor((cell.frame.size.height - boundingSize.height) / 2.0) + labelOffset + mainLabelHeight + verticalOffsetForSubtitle()
        labelRect.size.height = boundingSize.height
        labelRect.size.width = maxWidth
        
        attributedString.draw(in: labelRect)
    }
    
    private func subtitleWidth(cell: PSMTabBarCell, orientation: PSMTabBarOrientation) -> CGFloat {
        guard let cachedSubtitle = cell.cachedSubtitle else {
            return 0
        }
        let attributedString = cachedSubtitle.attributedStringForcingLeftAlignment(orientation == .horizontalOrientation,
                                                                                   truncatedForWidth: cell.frame.width)
        return attributedString.size().width
    }
    
    @objc
    func widthForLabel(inCell cell: PSMTabBarCell,
                       labelPosition: CGFloat,
                       hasIcon drewIcon: Bool,
                       iconRect: NSRect,
                       cachedTitle: PSMCachedTitle,
                       reservedSpace: CGFloat,
                       boundingSize boundingSizePtr: UnsafeMutablePointer<NSSize>) -> CGFloat {
        return Self.widthForLabel(inCell: cell,
                                  labelPosition: labelPosition,
                                  hasIcon: drewIcon,
                                  iconRect: iconRect,
                                  cachedTitle: cachedTitle,
                                  reservedSpace: reservedSpace,
                                  fontSize: fontSize,
                                  orientation: _orientation,
                                  boundingSize: boundingSizePtr)
    }
    
    static func widthForLabel(inCell cell: PSMTabBarCell,
                              labelPosition: CGFloat,
                              hasIcon drewIcon: Bool,
                              iconRect: NSRect,
                              cachedTitle: PSMCachedTitle,
                              reservedSpace: CGFloat,
                              fontSize: CGFloat,
                              orientation: PSMTabBarOrientation,
                              boundingSize boundingSizePtr: UnsafeMutablePointer<NSSize>) -> CGFloat {
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
            labelRect.size.width -= (objectCounterRect(forTabCell: cell, fontSize: fontSize).size.width + kPSMTabBarCellPadding)
        }
        
        let boundingSize = cachedTitle.boundingRect(with: labelRect.size).size
        
        if orientation == .horizontalOrientation {
            let effectiveLeftMargin = (labelRect.size.width - boundingSize.width) / 2
            if effectiveLeftMargin < reservedSpace {
                labelRect.size.width -= reservedSpace
            }
        }
        
        boundingSizePtr.pointee = boundingSize
        
        return labelRect.size.width
    }
    
    @objc func willDrawSubtitle(_ subtitle: PSMCachedTitle?) -> Bool {
        return Self.willDrawSubtitle(subtitle)
    }
    
    private static func willDrawSubtitle(_ subtitle: PSMCachedTitle?) -> Bool {
        return subtitle?.isEmpty == false
    }
    
    @objc func verticalOffsetForTitleWhenSubtitlePresent() -> CGFloat {
        return Self.verticalOffsetForTitleWhenSubtitlePresent
    }
    
    private static var verticalOffsetForTitleWhenSubtitlePresent: CGFloat {
        return -5
    }
    
    @objc func verticalOffsetForSubtitle() -> CGFloat {
        return -2
    }
    
    @objc func shouldDrawTopLineSelected(_ selected: Bool, attached: Bool, position: PSMTabPosition) -> Bool {
        return false
    }
    
    @objc
    func textColorDefaultSelected(_ selected: Bool,
                                  backgroundColor: NSColor?,
                                  windowIsMainAndAppIsActive mainAndActive: Bool) -> NSColor {
        return Self.textColorDefaultSelected(selected, backgroundColor: backgroundColor, windowIsMainAndAppIsActive: mainAndActive)
    }
    
    class func textColorDefaultSelected(_ selected: Bool,
                                        backgroundColor: NSColor?,
                                        windowIsMainAndAppIsActive mainAndActive: Bool) -> NSColor {
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
                if cellBrightness > 0.60 {
                    DLog("is bright. USE BLACK TEXT COLOR")
                    // bright tab
                    return NSColor.black
                } else {
                    DLog("is dark. Use white text")
                    // dark tab
                    return NSColor.white
                }
            } else {
                let color = textColorDefaultSelected(false,
                                                     backgroundColor: nil,
                                                     windowIsMainAndAppIsActive: windowIsMainAndAppIsActive)
                return color.withAlphaComponent(0.8)
            }
        }

        let mainAndActive = windowIsMainAndAppIsActive
        let cellBackgroundColor: NSColor? = if let tabColor = cell.tabColor {
            cellBackgroundColor(forTabColor: tabColor, selected: selected)
        } else {
            nil
        }
        if selected {
            DLog("selected")
            return textColorDefaultSelected(
                selected,
                backgroundColor: cellBackgroundColor,
                windowIsMainAndAppIsActive: mainAndActive)
        } else {
            DLog("not selected")
            return textColorDefaultSelected(
                selected,
                backgroundColor: cellBackgroundColor,
                windowIsMainAndAppIsActive: mainAndActive)
        }
    }

    @objc func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected {
            return NSColor(white: 0.97, alpha: 1.0)
        } else {
            if highlightAmount > 0 {
                return NSColor(displayP3Red: 0.86, green: 0.86, blue: 0.86, alpha: 1.0)
            } else {
                return Self.backgroundColor
            }
        }
    }
    
    @objc func drawPostHocDecorations(onSelectedCell cell: PSMTabBarCell,
                                      tabBarControl bar: PSMTabBarControl) {
    }

    // MARK: - Private Helper Methods
    
    private func retinaRoundUpCell(_ cell: PSMTabBarCell, value: CGFloat) -> CGFloat {
        return Self.retinaRoundUpCell(cell, value: value)
    }
    
    private static func retinaRoundUpCell(_ cell: PSMTabBarCell, value: CGFloat) -> CGFloat {
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
        guard let cachedTitle = cell.cachedTitle else { return 0 }
        return ceil(cachedTitle.size.width)
    }
    
    var fontSize: CGFloat {
        if let override = tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
            return CGFloat(override.doubleValue)
        }
        return 11.0
    }
    
    private var subtitleFontSize: CGFloat {
        return round(fontSize * 0.8)
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
    
    private func drawCellBackgroundAndFrameHorizontallyOriented(_ horizontal: Bool,
                                                                inRect cellFrame: NSRect,
                                                                selected: Bool,
                                                                withTabColor tabColor: NSColor?,
                                                                isFirst: Bool?,
                                                                isLast: Bool?,
                                                                highlightAmount: CGFloat,
                                                                isHighlighted: Bool) {
        drawCellBackgroundSelected(selected,
                                   inRect: cellFrame,
                                   withTabColor: tabColor,
                                   highlightAmount: highlightAmount,
                                   horizontal: horizontal,
                                   isHighlighted: isHighlighted)
    }
    
    private func tintedCloseButtonImage(cell: PSMTabBarCell) -> NSImage? {
        let untintedCloseButton = if cell.closeButtonOver {
            _closeButtonOver
        } else if cell.closeButtonPressed {
            _closeButtonDown
        } else {
            _closeButton
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
        
        return untintedCloseButton?.it_cachingImage(withTintColor: closeButtonTintColor, key: colorKey)
    }
    
    private func closeButtonAlpha(cell: PSMTabBarCell, highlightAmount: CGFloat) -> CGFloat {
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
        }
        return closeButtonAlpha
    }
    
    enum SizingMode: CustomDebugStringConvertible {
        case fixed(CGFloat)
        case expanding(minWidth: CGFloat, maxWidth: CGFloat)
        
        var debugDescription: String {
            switch self {
            case .fixed(let value): "Fixed \(value)"
            case .expanding(minWidth: let minValue, maxWidth: let maxValue): "Expanding \(minValue)…\(maxValue)"
            }
        }
    }
    enum Gravity: Int {
        case left
        case center
        case right
    }
    
    protocol LayoutableObject {
        var name: String { get }
        var sizingMode: SizingMode { get }
        // priority=0 means required, otherwise higher priorities are removed before lower ones.
        var priority: Int { get }
        var gravity: Gravity { get }
        var draw: (ResolvedLayout) -> () { get }
    }
    struct ResolvedLayout: CustomDebugStringConvertible {
        var debugDescription: String {
            return "\(type(of: object)) \(object.name) \(object.sizingMode) width=\(width) minX=\(frame.minX)"
        }
        var object: any LayoutableObject
        var width: CGFloat
        var frame: NSRect
        var originalIndex: Int
    }
    struct NewLayout {
        var objects = [any LayoutableObject]()
        var enclosingFrame: NSRect
        
        init(objects: [any LayoutableObject],
             enclosingFrame: NSRect) {
            self.objects = objects
            self.enclosingFrame = enclosingFrame
            // Gravity must increase monotonically
            for i in 1..<objects.count {
                it_assert(objects[i - 1].gravity.rawValue <= objects[i].gravity.rawValue)
            }
        }
        
        func resolve(y: CGFloat) -> [ResolvedLayout] {
            var resolved: [ResolvedLayout] = objects.enumerated().map { ResolvedLayout(object: $1, width: $1.minimumSize, frame: .zero, originalIndex: $0) }
            var minWidth = objects
                .map { $0.minimumSize }
                .reduce(0.0, +)
            var maxWidth = objects
                .map { $0.maximumSize }
                .reduce(0.0, +)
            resolved.sort(by: {
                $0.object.priority < $1.object.priority
            })
            // Remove optional objects until everything fits in the available space
            while minWidth > enclosingFrame.width {
                let obj = resolved.removeLast()
                minWidth -= obj.object.minimumSize
                maxWidth -= obj.object.maximumSize
            }
            
            
            // Grow objects while there is room
            var unassignedSpace = enclosingFrame.width - minWidth
            for cursor in 0..<resolved.count {
                if unassignedSpace <= 0 {
                    break
                }
                let maxGrowth = resolved[cursor].object.maximumSize - resolved[cursor].object.minimumSize
                if maxGrowth > 0 {
                    let growth = min(maxGrowth, unassignedSpace)
                    resolved[cursor].width += growth
                    unassignedSpace -= growth
                }
            }
            
            resolved.sort(by: { $0.originalIndex < $1.originalIndex })
            
            var lefts: [ResolvedLayout]
            var centers: [ResolvedLayout]
            var rights: [ResolvedLayout]
            
            let lastLeftIndex = resolved.lastIndex(where: { $0.object.gravity == .left })
            if let lastLeftIndex {
                lefts = Array(resolved[0...lastLeftIndex])
            } else {
                lefts = []
            }
            if let lastCenterIndex = resolved.lastIndex(where: { $0.object.gravity == .center }) {
                let firstCenterIndex = lastLeftIndex.map { $0 + 1 } ?? 0
                centers = Array(resolved[firstCenterIndex...lastCenterIndex])
            } else {
                centers = []
            }
            if let firstRightIndex = resolved.firstIndex(where: { $0.object.gravity == .right}) {
                rights = Array(resolved[firstRightIndex...]).reversed()
            } else {
                rights = []
            }
            
            var x = enclosingFrame.minX
            for i in 0..<lefts.count {
                lefts[i].frame = NSRect(x: x, y: y, width: lefts[i].width, height: 0)
                x += lefts[i].width
            }
            let maxLeft = x
            
            x = enclosingFrame.maxX
            for i in 0..<rights.count {
                x -= rights[i].width
                rights[i].frame = NSRect(x: x, y: y, width: rights[i].width, height: 0)
            }
            let minRight = x
            
            let totalCenterWidth = centers.reduce(0.0, { $0 + $1.width })
            let availableWidth = minRight - maxLeft
            x = maxLeft + (availableWidth - totalCenterWidth) / 2.0
            for i in 0..<centers.count {
                centers[i].frame = NSRect(x: x, y: y, width: centers[i].width, height: 0)
                x += centers[i].width
            }
            return lefts + centers + rights.reversed()
        }
    }
    
    struct FixedSpacerLO: LayoutableObject, Equatable {
        var name: String
        var width: CGFloat
        var priority: Int
        var gravity: Gravity
        var sizingMode: SizingMode { .fixed(width) }
        var draw: (ResolvedLayout) -> () = { _ in }
        static func == (lhs: FixedSpacerLO, rhs: FixedSpacerLO) -> Bool {
            lhs.name == rhs.name
        }
    }
    
    struct ImageLO: LayoutableObject, Equatable {
        var name: String
        var image: NSImage
        var priority: Int
        var gravity: Gravity
        var preferredWidth: CGFloat?

        var sizingMode: SizingMode { .fixed(preferredWidth ?? image.size.width) }
        var draw: (ResolvedLayout) -> ()
        static func == (lhs: ImageLO, rhs: ImageLO) -> Bool {
            lhs.name == rhs.name
        }
    }
    
    struct TextLO: LayoutableObject, Equatable {
        var name: String
        var priority: Int
        var minWidth: CGFloat
        var attributedStringWidth: CGFloat
        var gravity: Gravity
        var sizingMode: SizingMode { .expanding(minWidth: minWidth, maxWidth: attributedStringWidth) }
        var draw: (ResolvedLayout) -> ()
        static func == (lhs: TextLO, rhs: TextLO) -> Bool {
            lhs.name == rhs.name
        }
    }
    
    struct GroupLO: LayoutableObject, Equatable, CustomDebugStringConvertible {
        var debugDescription: String {
            let memberStrings: [String] = members.map { "  " + $0.description }
            let parts = [description] + memberStrings
            return parts.joined(separator: "\n")
        }
        var name: String
        var priority: Int
        var gravity: Gravity
        var members: [any LayoutableObject]
        
        var draw: (ResolvedLayout) -> () {
            return { resolved in
                // Lay out members and then draw them.
                let nestedLayout = NewLayout(objects: members, enclosingFrame: resolved.frame)
                for resolved in nestedLayout.resolve(y: resolved.frame.minY) {
                    resolved.object.draw(resolved)
                    if PSMTahoeTabStyleDebuggingEnabled {
                        let frame = resolved.frame
                        NSColor.blue.set()
                        NSRect(x: frame.minX, y: 0, width: frame.width, height: 20).frame()
                    }
                }
            }
        }
            
        var sizingMode: PSMTahoeTabStyle.SizingMode {
            var mode = SizingMode.fixed(0)
            for member in members {
                let lowerBoundForElision = if member.priority > 0 {
                    CGFloat(0)
                } else {
                    CGFloat.infinity
                }
                switch member.sizingMode {
                case .fixed(let memberWidth):
                    switch mode {
                    case .fixed(let width):
                        mode = .fixed(width + min(lowerBoundForElision, memberWidth))
                    case .expanding(minWidth: let minWidth, maxWidth: let maxWidth):
                        mode = .expanding(minWidth: minWidth + min(lowerBoundForElision, memberWidth), maxWidth: maxWidth + memberWidth)
                    }
                case .expanding(let minMemberWidth, let maxMemberWidth):
                    switch mode {
                    case .fixed(let width):
                        mode = .expanding(minWidth: min(lowerBoundForElision, minMemberWidth) + width,
                                          maxWidth: maxMemberWidth + width)
                    case .expanding(minWidth: let memberMinWidth, maxWidth: let memberMaxWidth):
                        mode = .expanding(minWidth: min(lowerBoundForElision, minMemberWidth) + memberMinWidth,
                                          maxWidth: maxMemberWidth + memberMaxWidth)
                    }
                }
            }
            return mode
        }
        static func == (lhs: PSMTahoeTabStyle.GroupLO, rhs: PSMTahoeTabStyle.GroupLO) -> Bool {
            lhs.name == rhs.name
        }
    }
    
    
    private func drawInterior(with cell: PSMTabBarCell, inView controlView: NSView?, highlightAmount: CGFloat) {
        var objects = [any LayoutableObject]()
        
        enum Priority: Int {
            case required
            case graphic
            case objectCounter
            case icon
            case closeButton
        }
        enum Name: String {
            case closeButton
            case graphic
            case preLabelSpace
            case label
            case icon
            case objectCounter
        }
        let orientation = self.orientation
        let edgePadding = 6.0
        
        let orientationShift = if orientation == .verticalOrientation {
            1.0
        } else {
            0.0
        }

        // Close button
        if cell.hasCloseButton, let image = _closeButton {
            objects.append(FixedSpacerLO(name: "Leading Spacer", width: edgePadding, priority: Priority.required.rawValue, gravity: .left))
            
            let closeButton = tintedCloseButtonImage(cell: cell)
            let closeButtonAlpha = self.closeButtonAlpha(cell: cell, highlightAmount: highlightAmount)
            objects.append(GroupLO(name: Name.closeButton.rawValue, priority: Priority.closeButton.rawValue, gravity: .left, members: [
                ImageLO(name: "Close Button", image: image, priority: Priority.required.rawValue, gravity: .left) { resolved in
                    if cell.closeButtonVisible {
                        var closeButtonRect = cell.closeButtonRect(forFrame: cell.frame)
                        closeButtonRect.origin.x = resolved.frame.minX
                        closeButtonRect.origin.y += orientationShift
                        closeButton?.draw(at: closeButtonRect.origin,
                                          from: NSZeroRect,
                                          operation: .sourceOver,
                                          fraction: closeButtonAlpha)
                    }
                },
            ]))
        } else {
            objects.append(FixedSpacerLO(name: "Leading Spacer", width: edgePadding, priority: Priority.required.rawValue, gravity: .left))
        }
        
        // Graphic
        if let image = cell.cachedTitle?.inputs.graphic {
            let drawGraphic: (ResolvedLayout) -> () = { resolved in
                var rect = resolved.frame
                rect.origin.y = cell.frame.minY + (cell.frame.height - kPSMTabBarIconWidth) / 2.0 + orientationShift
                rect.size.height = kPSMTabBarIconWidth
                rect.size.width = kPSMTabBarIconWidth
                image.draw(in: rect,
                             from: .zero,
                             operation: .sourceOver,
                             fraction: 1,
                             respectFlipped: true,
                             hints: nil)
            }

            objects.append(GroupLO(name: Name.graphic.rawValue, priority: Priority.graphic.rawValue, gravity: orientation == .horizontalOrientation ? .center : .left, members: [
                ImageLO(name: "Graphic", image: image, priority: Priority.required.rawValue, gravity: .left, preferredWidth: kPSMTabBarIconWidth, draw: drawGraphic),
                FixedSpacerLO(name: Name.preLabelSpace.rawValue, width: 2.0, priority: Priority.required.rawValue, gravity: .left)
            ]))
        }
        
        
        // Label and subtitle
        let subtitleWidth = subtitleWidth(cell: cell, orientation: orientation)
        let labelWidth = max(widthOfAttributedStringInCell(cell), subtitleWidth)
        let supportsMultiLineLabels = self.supportsMultiLineLabels
        // Amount to shift text down from vertically centered so that it matches the OS's rendering
        let textShift = 1.0 + orientationShift
        objects.append(TextLO(name: Name.label.rawValue,
                              priority: Priority.required.rawValue,
                              minWidth: 8,
                              attributedStringWidth: labelWidth,
                              gravity: orientation == .horizontalOrientation ? .center : .left) { resolved in
            let labelOffset: CGFloat
            let mainLabelHeight: CGFloat
            if let cachedTitle = cell.cachedTitle,
               !cachedTitle.isEmpty {
                let attributedString = cachedTitle.attributedStringForcingLeftAlignment(
                    orientation == .verticalOrientation,
                    truncatedForWidth: resolved.frame.size.width)
                var rect = resolved.frame
                let boundingSize = cachedTitle.boundingRect(with: NSSize(width: resolved.frame.width, height: cell.frame.height)).size
                mainLabelHeight = boundingSize.height
                labelOffset = PSMTahoeTabStyle.willDrawSubtitle(cell.cachedSubtitle) ? PSMTahoeTabStyle.verticalOffsetForTitleWhenSubtitlePresent : 0
                rect.origin.y = cell.frame.origin.y + floor((cell.frame.size.height - boundingSize.height) / 2.0) + labelOffset + textShift
                rect.size.height = boundingSize.height
                attributedString.draw(in: rect)
            } else {
                labelOffset = 0
                mainLabelHeight = 0
            }
            
            // Draw subtitle
            if supportsMultiLineLabels {
                self.drawSubtitle(cell: cell,
                                  orientation: orientation,
                                  xOrigin: resolved.frame.minX,
                                  maxWidth: resolved.frame.width,
                                  labelOffset: labelOffset,
                                  mainLabelHeight: mainLabelHeight)
            }
        })

        // Icon
        if cell.hasIcon, let icon = icon(cell: cell) {
            objects.append(GroupLO(name: Name.icon.rawValue, priority: Priority.icon.rawValue, gravity: orientation == .horizontalOrientation ? .center : .left, members: [
                FixedSpacerLO(name: "Pre-Icon Space", width: kPSMTabBarCellIconPadding, priority: Priority.required.rawValue, gravity: .left),
                ImageLO(name: "Icon", image: icon, priority: Priority.required.rawValue, gravity: .left) { resolved in
                    var rect = resolved.frame
                    rect.size.height = kPSMTabBarIconWidth
                    rect.origin.y = Self.centeredMinY(cell: cell, height: kPSMTabBarIconWidth) + orientationShift
                    icon.draw(in: rect,
                              from: NSZeroRect,
                              operation: .sourceOver,
                              fraction: 1.0,
                              respectFlipped: true,
                              hints: nil)
                },
                FixedSpacerLO(name: "Post-Icon Space", width: 1.0, priority: Priority.required.rawValue, gravity: .left),
            ]))
        }
        
        // Counter
        let counterString = attributedObjectCountValue(forTabCell: cell)
        if !counterString.string.isEmpty {
            let counterStringSize = counterString.size()
            let fontSize = self.fontSize
            let gravity: Gravity = orientation == .horizontalOrientation ? .center : .right
            objects.append(GroupLO(name: Name.objectCounter.rawValue, priority: Priority.objectCounter.rawValue, gravity: gravity, members: [
                FixedSpacerLO(name: "Pre-Counter Space", width: 4.0, priority: Priority.required.rawValue, gravity: .left),
                TextLO(name: "Counter",
                       priority: Priority.required.rawValue,
                       minWidth: counterStringSize.width,
                       attributedStringWidth: counterStringSize.width,
                       gravity: .left) { resolved in
                    if cell.count > 0 {
                        let myRect = PSMTahoeTabStyle.objectCounterRect(forTabCell: cell, fontSize: fontSize)
                        var rect = resolved.frame
                        rect.origin.y = myRect.origin.y + floor((myRect.size.height - counterStringSize.height) / 2.0) + textShift
                        rect.size.height = counterStringSize.height
                        counterString.draw(in: rect)
                    }
                }
            ]))
        }

        if !cell.indicator.isHidden {
            objects.append(FixedSpacerLO(name: "Indicator Space", width: kPSMTabBarIndicatorWidth, priority: Priority.required.rawValue, gravity: .right))
        }
        objects.append(FixedSpacerLO(name: "Trailing Spacer", width: edgePadding + 8.0, priority: Priority.required.rawValue, gravity: .right))

        let layout = NewLayout(objects: objects, enclosingFrame: cell.frame)
        let resolved = layout.resolve(y: cell.frame.minY)
        for (i, member) in resolved.enumerated() {
            member.object.draw(member)
            if PSMTahoeTabStyleDebuggingEnabled {
                let frame = member.frame
                NSColor.red.set()
                NSRect(x: frame.minX, y: CGFloat(i), width: frame.width, height: 20).frame()
            }
        }
    }
    
    private func icon(cell: PSMTabBarCell) -> NSImage? {
        let tabViewItem = cell.representedObject as? NSTabViewItem
        let tab = tabViewItem?.identifier as? PSMTabBarControlRepresentedObjectIdentifierProtocol
        return tab?.icon?()
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

@available(macOS 26, *)
extension PSMTahoeTabStyle.LayoutableObject {
    var minimumSize: CGFloat {
        switch sizingMode {
        case .expanding(minWidth: let minWidth, _): minWidth
        case .fixed(let width): width
        }
    }
    
    var maximumSize: CGFloat {
        switch sizingMode {
        case .expanding(_, maxWidth: let maxWidth): maxWidth
        case .fixed(let width): width
        }
    }
    
    var description: String {
        return "\(type(of: self)) \(self.name) \(self.sizingMode) \(self.gravity)"
    }
}

@available(macOS 26, *)
class PSMTahoeDarkTabStyle: PSMTahoeTabStyle {
    @objc
    override var tabBarColor: NSColor {
        return NSColor(srgbRed: 45.0 / 255.0,
                       green:   48.0 / 255.0,
                       blue:    50.0 / 255.0,
                       alpha:    1)
    }
    
    override class var xmarkSymbolConfiguration: NSImage.SymbolConfiguration {
        return super.xmarkSymbolConfiguration.applying(.init(paletteColors: [.white]))
    }
    
    override class var backgroundColor: NSColor {
        return NSColor(displayP3Red: 0.17,
                       green:        0.18,
                       blue:         0.19,
                       alpha:        1.0)
    }
    
    override func accessoryStrokeColor() -> NSColor {
        return NSColor.darkGray
    }
    
    override func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected {
            if tabBar?.window?.isMainWindow == true && NSApp.isActive {
                return NSColor(displayP3Red:  98.0 / 255.0,
                               green:        100.0 / 255.0,
                               blue:         102.0 / 255.0,
                               alpha: 1.0)
            }
            return NSColor(displayP3Red: 83.0 / 255.0,
                           green:        85.0 / 255.0,
                           blue:         87.0 / 255.0,
                           alpha:        1.0)
        } else {
            if highlightAmount > 0 {
                return NSColor(displayP3Red: 0.21,
                               green:        0.21,
                               blue:         0.22,
                               alpha:        1.0)
            } else {
                return Self.backgroundColor
            }
        }
    }
    
    override class func textColorDefaultSelected(_ selected: Bool,
                                                 backgroundColor: NSColor?,
                                                 windowIsMainAndAppIsActive mainAndActive: Bool) -> NSColor {
        if mainAndActive {
            if selected {
                return NSColor(displayP3Red: 239.0 / 255.0,
                               green:        239.0 / 255.0,
                               blue:         239.0 / 255.0,
                               alpha: 1.0)
            } else {
                return NSColor(displayP3Red: 126.0 / 255.0,
                               green:        128.0 / 255.0,
                               blue:         129.0 / 255.0,
                               alpha: 1.0)
            }
        } else {
            if selected {
                return NSColor(displayP3Red: 126.0 / 255.0,
                               green:        127.0 / 255.0,
                               blue:         128.0 / 255.0,
                               alpha: 1.0)
            } else {
                return NSColor(displayP3Red: 119.0 / 255.0,
                               green:        119.0 / 255.0,
                               blue:         119.0 / 255.0,
                               alpha: 1.0)
            }
        }
    }
    
    override func drawCellOutline(path: NSBezierPath, rect: NSRect, radius: CGFloat) {
        let image = Self.leftTabCap
        var dest = rect
        dest.size = image.size
        Self.leftTabCap.draw(in: dest)
        
        dest.origin.x = rect.maxX - image.size.width
        Self.rightTabCap.draw(in: dest)
        
        dest.origin.x = rect.minX + image.size.width
        dest.size.width = rect.width - (2 * image.size.width)
        Self.tabMid.draw(in: dest)
    }
    
    private static let leftTabCap: NSImage = {
        Bundle(for: PSMTahoeTabStyle.self).image(forResource: "TahoeDarkLeftTab")!
    }()
    
    private static let rightTabCap: NSImage = {
        Bundle(for: PSMTahoeTabStyle.self).image(forResource: "TahoeDarkRightTab")!
    }()
    
    private static let tabMid: NSImage = {
        Bundle(for: PSMTahoeTabStyle.self).image(forResource: "TahoeDarkMidTab")!
    }()
    
    override var dividerColor: NSColor {
        NSColor(displayP3Red: 0.271, green: 0.292, blue: 0.301, alpha: 1.0)
    }

    override func useLightControls() -> Bool {
        return true
    }
}

@available(macOS 26, *)
class PSMTahoeOverflowButton: NSButton {
    init() {
        super.init(frame: .zero)
        let symbol = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)!
        symbol.isTemplate = true
        image = symbol
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = .labelColor
        bezelStyle = .glass
        borderShape = .circle
        isBordered = true
        showsBorderOnlyWhileMouseInside = false
        frame = frame
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    override func acceptsFirstMouse(for theEvent: NSEvent?) -> Bool {
        true
    }
    
    override func mouseDown(with event: NSEvent) {
        highlight(true)
        menu?.popUp(positioning: nil,
                    at: NSPoint(x: bounds.midX, y: bounds.midY),
                    in: self)
        highlight(false)
    }
}

@available(macOS 26, *)
class PSMTahoeDarkHighContrastTabStyle: PSMTahoeDarkTabStyle {
    @objc
    override var tabBarColor: NSColor {
        return NSColor(srgbRed: 15.0 / 255.0,
                       green:   18.0 / 255.0,
                       blue:    20.0 / 255.0,
                       alpha:    1.0)
    }
    
    override class var xmarkSymbolConfiguration: NSImage.SymbolConfiguration {
        return super.xmarkSymbolConfiguration.applying(.init(paletteColors: [.white]))
    }
    
    override class var backgroundColor: NSColor {
        return NSColor(displayP3Red: 13.0 / 255.0,
                       green:        16.0 / 255.0,
                       blue:         18.0 / 255.0,
                       alpha:         1.0)
    }
    
    override func accessoryStrokeColor() -> NSColor {
        return NSColor.darkGray
    }
    
    override func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected {
            if tabBar?.window?.isMainWindow == true && NSApp.isActive {
                return NSColor(displayP3Red: 198.0 / 255.0,
                               green:        200.0 / 255.0,
                               blue:         202.0 / 255.0,
                               alpha:          1.0)
            }
            return NSColor(displayP3Red: 53.0 / 255.0,
                           green:        55.0 / 255.0,
                           blue:         57.0 / 255.0,
                           alpha:        1.0)
        } else {
            if highlightAmount > 0 {
                return NSColor(displayP3Red: 24.0 / 255.0,
                               green:        26.0 / 255.0,
                               blue:         28.0 / 255.0,
                               alpha:        1.0)
            } else {
                return Self.backgroundColor
            }
        }
    }
    
    override class func textColorDefaultSelected(_ selected: Bool,
                                                 backgroundColor: NSColor?,
                                                 windowIsMainAndAppIsActive mainAndActive: Bool) -> NSColor {
        if mainAndActive {
            if selected {
                return NSColor(displayP3Red: 255.0 / 255.0,
                               green:        255.0 / 255.0,
                               blue:         255.0 / 255.0,
                               alpha:          1.0)
            } else {
                return NSColor(displayP3Red: 66.0 / 255.0,
                               green:        68.0 / 255.0,
                               blue:         69.0 / 255.0,
                               alpha:         1.0)
            }
        } else {
            if selected {
                return NSColor(displayP3Red: 200.0 / 255.0,
                               green:        200.0 / 255.0,
                               blue:         200.0 / 255.0,
                               alpha:          1.0)
            } else {
                return NSColor(displayP3Red: 180.0 / 255.0,
                               green:        180.0 / 255.0,
                               blue:         180.0 / 255.0,
                               alpha:          1.0)
            }
        }
    }
    
    override func useLightControls() -> Bool {
        return true
    }
    
    override func textColor(for cell: PSMTabBarCell) -> NSColor {
        if anyTabHasColor() {
            return super.textColor(for: cell)
        } else {
            return NSColor.white
        }
    }
    override var fontSize: CGFloat {
        if let override = tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
            return CGFloat(override.doubleValue)
        }
        return 13.0
    }

}


@available(macOS 26, *)
class PSMTahoeLightHighContrastTabStyle: PSMTahoeTabStyle {
    override class var xmarkSymbolConfiguration: NSImage.SymbolConfiguration {
        return super.xmarkSymbolConfiguration.applying(.init(paletteColors: [.black]))
    }
    
    override func accessoryStrokeColor() -> NSColor {
        return NSColor.black
    }
    
    override class func textColorDefaultSelected(_ selected: Bool,
                                                 backgroundColor: NSColor?,
                                                 windowIsMainAndAppIsActive mainAndActive: Bool) -> NSColor {
        let value: CGFloat
        if mainAndActive {
            value = 0
        } else {
            if selected {
                value = 255
            } else {
                value = 255
            }
        }
        return NSColor(srgbRed: value/255.0, green: value/255.0, blue: value/255.0, alpha: 1)
    }
    
    override var fontSize: CGFloat {
        if let override = tabBar?.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
            return CGFloat(override.doubleValue)
        }
        return 13.0
    }
}

#endif
