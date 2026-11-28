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
    private var _pinImage: NSImage?
    private var _orientation: PSMTabBarOrientation = .horizontalOrientation
    // These are non-nil only in drawTabBar.
    private var anyTabHasColorWhileDrawing: Bool?
    private var titleOptionsWhileDrawing: TitleOptions?
    
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

    // Only a selected tab is filled with its tab color, with black or white
    // text to stand out from it. An unselected one shows its color as a
    // border and a faint tint, so its text is on the bar.
    @objc(richLineColorAppearanceForCell:)
    func richLineColorAppearance(for cell: PSMTabBarCell) -> NSAppearance? {
        guard cell.tabColor != nil, cell.state == .on else {
            return accessoryAppearance
        }
        return PSMTabRichContentRenderer.colorAppearance(contrastingWith: textColor(for: cell))
    }
    
    @objc var edgeDragHeight: CGFloat {
        guard let tabBar, let delegate = tabBar.delegate,
              let size = delegate.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.dragEdgeHeight) as? NSNumber else {
            return 0
        }
        return CGFloat(size.doubleValue)
    }
    
    @objc var intercellSpacing: CGFloat {
        // 2pt of frame spacing leaves ~1pt of clear gap between adjacent selected
        // tabs' outline strokes (each stroke reaches ~0.5pt past its pill), which
        // matches the system tab bar. At 1pt the two strokes met and the group
        // run's enclosing outline overlapped the neighboring tab.
        2.0
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

        // Load pin indicator
        let pinConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium, scale: .medium)
        if let basePin = NSImage(systemSymbolName: SFSymbol.pinFill.rawValue, accessibilityDescription: "Pinned") {
            _pinImage = basePin.withSymbolConfiguration(pinConfig) ?? basePin
            _pinImage?.isTemplate = true
        }
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

    @objc func makeAddTabButton(withFrame frame: NSRect) -> PSMRolloverButton? {
        return PSMTahoeRolloverButton(symbolName: "plus")
    }

    func makeOverflowButton(withFrame frame: NSRect) -> NSButton {
        return PSMTahoeOverflowButton()
    }

    @objc func name() -> String {
        return "Tahoe"
    }
    
    func frameForAddTabButton(withCellWidths widths: [NSNumber]?, height: CGFloat) -> NSRect {
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
        if let margin = marginInsideContainer {
            return margin
        }
        return Float(tabBar?.insets.left ?? 0) + 2.0
    }
    
    @objc func rightMarginForTabBarControl(withOverflow: Bool, addTabButton: Bool) -> Float {
        let accessoryWidth: Float = (withOverflow || addTabButton) ? 32.0 : 0
        if let margin = marginInsideContainer {
            return accessoryWidth + margin
        }
        if withOverflow || addTabButton {
            return accessoryWidth + Float(tabBar?.insets.right ?? 0) + 2.0
        }
        return 2.0
    }

    @objc func leftMarginFollowsInsets() -> Bool {
        return marginInsideContainer == nil
    }

    // On macOS 27 the first and last tabs sit 2pt inside the ends of the bar's
    // rounded container, the same inset they have from its top and bottom. The
    // container's ends don't move with the tab bar's insets (see
    // clippingPath(rect:)), so neither does this.
    private var marginInsideContainer: Float? {
        if #available(macOS 27, *), _orientation == .horizontalOrientation {
            return Float(containerSideInset - 0.5 + 2)
        }
        return nil
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
        if cell.isPinned {
            return NSZeroRect
        }
        let cellFrame = cell.frame

        if !cell.hasCloseButton {
            return NSZeroRect
        }
        
        var result = NSRect()
        result.size = _closeButton?.size ?? NSZeroSize
        // A rich tab draws its close button in its graphic's place, on the
        // first line.
        if let minY = richAccessoryMinY(cell: cell, height: result.size.height) {
            result.origin.x = cellFrame.origin.x + Self.richHorizontalInset
            result.origin.y = minY
        } else {
            result.origin.x = cellFrame.origin.x + kSPMTabBarCellInternalXMargin
            result.origin.y = cellFrame.origin.y + floor((cellFrame.size.height - result.size.height) / 2.0)
        }
        
        return result
    }
    
    private static func centeredMinY(cell: PSMTabBarCell, height: CGFloat) -> CGFloat {
        cell.frame.origin.y + floor((cell.frame.size.height - height) / 2.0) - 1
    }
    
    @objc func indicatorRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        var result = Self.indicatorRect(forTabCell: cell,
                                        fontSize: fontSize)
        if let minY = richAccessoryMinY(cell: cell, height: result.height) {
            result.origin.x = cell.frame.maxX - Self.richHorizontalInset - result.width
            result.origin.y = minY
        }
        return result
    }

    private func richLines(cell: PSMTabBarCell) -> [PSMTabRichLine]? {
        let tab = (cell.representedObject as? NSTabViewItem)?.identifier as? PSMTabBarControlRepresentedObjectIdentifierProtocol
        // No lines draws nothing, so treat it as no rich content.
        guard let lines = tab?.psmTabRichLines?(), !lines.isEmpty else {
            return nil
        }
        return lines
    }

    // The rich lines this tab draws. A pinned tab in a horizontal bar is too
    // narrow for them and shows only its title's first character, but in a
    // vertical bar it is as wide as any other tab, so it draws them.
    private func drawnRichLines(cell: PSMTabBarCell) -> [PSMTabRichLine]? {
        if isCompactPinned(cell) {
            return nil
        }
        return richLines(cell: cell)
    }

    // A pinned tab in a horizontal bar is narrow, so it shows little more than
    // its pin. In a vertical bar it is as wide as any other tab.
    private func isCompactPinned(_ cell: PSMTabBarCell) -> Bool {
        return cell.isPinned && orientation == .horizontalOrientation
    }

    // Whether a pinned tab draws its pin. A compact one has room for only one
    // of its pin and graphic, and prefers the graphic. In a vertical bar the
    // pin goes before the graphic.
    private func showsPinIndicator(cell: PSMTabBarCell) -> Bool {
        return cell.isPinned && (!isCompactPinned(cell) || cell.cachedTitle?.inputs.graphic == nil)
    }

    // How far text is drawn below vertically centered, to match the OS's
    // rendering.
    private var textShift: CGFloat {
        return orientation == .verticalOrientation ? 2.0 : 1.0
    }

    // A tab with rich content lines puts its icons and activity indicator on
    // its first line instead of in its middle, which in a tall tab is between
    // lines. Returns the minY that does that for an accessory of the given
    // height, or nil for other tabs, which keep their centered layout.
    private func richAccessoryMinY(cell: PSMTabBarCell, height: CGFloat) -> CGFloat? {
        guard let lines = drawnRichLines(cell: cell) else {
            return nil
        }
        let midY = PSMTabRichContentRenderer.firstLineMidY(lines: lines,
                                                           in: richContentRect(cell: cell, x: cell.frame.minX, width: cell.frame.width),
                                                           baseFont: NSFont.systemFont(ofSize: fontSize))
        return round(midY - height / 2.0)
    }

    // Where rich content lines are drawn: centered in the tab's background,
    // which is inset from the cell, and lowered like the classic label.
    func richContentRect(cell: PSMTabBarCell, x: CGFloat, width: CGFloat) -> NSRect {
        let background = backgroundRect(for: cell.frame)
        return NSRect(x: x,
                      y: background.minY + textShift,
                      width: width,
                      height: background.height - textShift)
    }

    // 1 (the cell is shorter than its row; adjustedCellRect) + 3 (the
    // background is inset from the cell; backgroundRect) + 2 above and 2
    // below, so the lines don't crowd the rounded corners.
    @objc var richContentChromeHeight: CGFloat {
        return 8
    }

    // A rich tab's margin on each side, clear of its rounded corners.
    private static let richHorizontalInset: CGFloat = 10
    
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
        
        let counter = attributedObjectCountValue(forTabCell: cell, fontSize: fontSize, textColor: .black)
        var countWidth = retinaRoundUpCell(cell, value: objectCountSize(counter, fontSize: fontSize).width)
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
    func minimumWidth(ofTabCell cell: PSMTabBarCell) -> Float {
        if cell.isPinned {
            return Float(tabBar?.pinnedTabWidth ?? 0)
        }
        return Float(ceil(widthOfLeftMatterInCell(cell) +
                          kPSMMinimumTitleWidth +
                          widthOfRightMatterInCell(cell)))
    }

    @objc
    func desiredWidth(ofTabCell cell: PSMTabBarCell) -> Float {
        if cell.isPinned {
            return Float(tabBar?.pinnedTabWidth ?? 0)
        }
        // Rich content replaces the title, so fit its widest line instead.
        let labelWidth: CGFloat
        if let richLines = richLines(cell: cell) {
            labelWidth = PSMTabRichContentRenderer.preferredWidth(lines: richLines,
                                                                  baseFont: NSFont.systemFont(ofSize: fontSize))
        } else {
            labelWidth = widthOfAttributedStringInCell(cell)
        }
        return Float(ceil(widthOfLeftMatterInCell(cell) +
                          labelWidth +
                          widthOfRightMatterInCell(cell)))
    }
    
    // MARK: - Cell Values
    
    @objc
    func attributedObjectCountValue(forTabCell cell: PSMTabBarCell) -> NSAttributedString {
        return Self.attributedObjectCountValue(forTabCell: cell,
                                               fontSize: fontSize,
                                               textColor: textColor(for: cell))
    }
    
    private struct ObjectCountSizeKey: Hashable {
        var string: String
        var fontSize: CGFloat
    }
    private static var objectCountSizes = [ObjectCountSizeKey: NSSize]()

    // Drawing a tab measures its counter several times, but there are only a few different counters
    // and their sizes don't depend on color.
    private static func objectCountSize(_ counter: NSAttributedString, fontSize: CGFloat) -> NSSize {
        let key = ObjectCountSizeKey(string: counter.string, fontSize: fontSize)
        if let size = objectCountSizes[key] {
            return size
        }
        let size = counter.size()
        objectCountSizes[key] = size
        return size
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
    
    private struct TitleOptions {
        var parseHTML = false
        var puaFontProvider: PSMPUAFontProvider?
    }

    private var titleOptions: TitleOptions {
        if let titleOptionsWhileDrawing {
            return titleOptionsWhileDrawing
        }
        guard let tabBar else {
            return TitleOptions()
        }
        let parseHTML = tabBar.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.htmlTabTitles) as? NSNumber
        let puaFontProvider = tabBar.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.puaFontProvider) as? PSMPUAFontProvider
        return TitleOptions(parseHTML: parseHTML?.boolValue ?? false, puaFontProvider: puaFontProvider)
    }

    @objc func cachedTitleInputs(forTabCell cell: PSMTabBarCell) -> PSMCachedTitleInputs {
        let options = titleOptions

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
            parseHTML: options.parseHTML,
            puaFontProvider: options.puaFontProvider
        )
    }
    
    @objc func cachedSubtitleInputs(forTabCell cell: PSMTabBarCell) -> PSMCachedTitleInputs? {
        guard let subtitle = cell.subtitleString else {
            return nil
        }

        let options = titleOptions
        let color = textColor(for: cell)

        var subtitleColor: NSColor
        if let tab = (cell.representedObject as? NSTabViewItem)?.identifier as? PSMTabBarControlRepresentedObjectIdentifierProtocol,
           let statusColor = tab.psmTabStatusSubtitleColor?() {
            subtitleColor = statusColor
        } else {
            subtitleColor = color.withAlphaComponent(color.alphaComponent * 0.7)
        }

        return PSMCachedTitleInputs(
            title: subtitle,
            truncationStyle: cell.truncationStyle,
            color: subtitleColor,
            graphic: nil,
            orientation: _orientation,
            fontSize: subtitleFontSize,
            parseHTML: options.parseHTML,
            puaFontProvider: options.puaFontProvider
        )
    }
    
    func adjustedCellRect(_ rect: NSRect, generic: NSRect) -> NSRect {
        var frame = rect
        if _orientation == .horizontalOrientation {
            frame.origin.y = containerTopInset
            frame.size.height = generic.height - 1
        } else {
            frame = frame.insetBy(dx: 4, dy: 0)
            // A group header row can be shorter than tab rows made tall by
            // rich tab content, and a collapsed group's chip taller. Keep the
            // cell's own height so it doesn't overlap its neighbors.
            frame.size.height = rect.height - 1
        }
        return frame
    }

    func backgroundRect(for cellFrame: NSRect) -> NSRect {
        var rect = cellFrame
        rect.origin.y += 2
        rect.size.height -= 3
        return rect
    }

    // The activity indicator hugs the pill as a rounded outline rather than a
    // bar inside it, so it never crowds the tab title or status subtitle.
    private var progressRingWidth: CGFloat { 2 }

    /// Stadium corner radius for a drawn pill (`height/2`), so fill, stroke,
    /// tab-color tint, progress ring, and dark-theme cap chrome share one
    /// curvature when cell height changes.
    // Round ends at the usual tab height. Tabs made taller by rich tab content
    // get rounded rectangles instead of very round stadiums.
    func pillCornerRadius(for rect: NSRect) -> CGFloat {
        max(0, min(rect.height / 2.0, maximumCornerRadius))
    }

    // Corner radius for a shape drawn `outset` outside a pill (a group's
    // enclosing pill), so its corners stay concentric with the pill's.
    private func outsetCornerRadius(for rect: NSRect, outset: CGFloat) -> CGFloat {
        max(0, min(rect.height / 2.0, maximumCornerRadius + outset))
    }

    // How round corners can get. Only rich tab content caps it: without it, a
    // tab bar made tall by a larger default tab bar height keeps the stadium
    // shapes it always had.
    var maximumCornerRadius: CGFloat {
        (tabBar?.showsRichTabContent ?? false) ? Self.richContentMaximumCornerRadius : .greatestFiniteMagnitude
    }

    @objc func previewOutlinePath(forTabCell cell: PSMTabBarCell, lineWidth: CGFloat) -> NSBezierPath? {
        // Trace the pill just inside its edge, leaving the outside for the progress ring.
        let rect = backgroundRect(for: cell.frame).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = pillCornerRadius(for: rect)
        return roundedPath(rect, radius: radius)
    }

    @objc func progressBarRect(forTabCell cell: PSMTabBarCell) -> NSRect {
        // Grow the bar past the pill on every side so it can render as an
        // outline around the tab. The middle is punched out by the clip path.
        return backgroundRect(for: cell.frame).insetBy(dx: -progressRingWidth,
                                                       dy: -progressRingWidth)
    }

    @objc func progressBarClipPath(forTabCell cell: PSMTabBarCell) -> NSBezierPath? {
        let pillRect = backgroundRect(for: cell.frame)
        let pillRadius = pillCornerRadius(for: pillRect)
        let outerRect = pillRect.insetBy(dx: -progressRingWidth, dy: -progressRingWidth)
        let outerRadius = pillRadius + progressRingWidth
        // Two nested pill shapes with even-odd winding form a ring: the outer
        // one is filled and the inner one, the tab's own shape, is punched out so the
        // tab shows through. PSMTabBarControl applies this as an even-odd layer
        // mask (the winding rule set here is not carried by iterm_CGPath).
        let path = roundedPath(outerRect, radius: outerRadius)
        path.append(roundedPath(pillRect, radius: pillRadius))
        path.windingRule = .evenOdd
        return path
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

    @objc func dirtyFrame(for cell: PSMTabBarCell) -> NSRect {
        return cell.frame.insetBy(dx: -Self.leftDropShadow.size.width, dy: -Self.topDropShadow.size.height)
    }
    
    @objc func drawTabCell(_ cell: PSMTabBarCell, highlightAmount: CGFloat) {
        let horizontal = (_orientation == .horizontalOrientation)
        let isFirst = (cell == tabBar?.cells().firstObject as? PSMTabBarCell)
        let isLast = (cell == tabBar?.cells().lastObject as? PSMTabBarCell)
        
        if tabBar?.window?.isKeyWindow == true && Self.drawsDropShadow {
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
    
    // Draws image filling rect. When rect is taller than scaledHeight, the
    // image's top and bottom halves are drawn scaledHeight / 2 tall at
    // rect's ends and its middle row stretches between them.
    static func draw(_ image: NSImage, in rect: NSRect, scaledHeight: CGFloat) {
        guard rect.height > scaledHeight, scaledHeight > 0 else {
            image.draw(in: rect)
            return
        }
        let size = image.size
        let half = scaledHeight / 2
        // Drawn upright either way, so the image's top half goes at the top
        // as seen, which is minY only in a flipped context.
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let topRect = NSRect(x: rect.minX, y: flipped ? rect.minY : rect.maxY - half,
                             width: rect.width, height: half)
        let bottomRect = NSRect(x: rect.minX, y: flipped ? rect.maxY - half : rect.minY,
                                width: rect.width, height: half)
        let middleRect = NSRect(x: rect.minX, y: rect.minY + half,
                                width: rect.width, height: rect.height - scaledHeight)
        // Source rects are in the image's own coordinates, origin at the bottom.
        let pieces = [(topRect, NSRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)),
                      (bottomRect, NSRect(x: 0, y: 0, width: size.width, height: size.height / 2)),
                      (middleRect, NSRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1))]
        for (destination, source) in pieces {
            image.draw(in: destination,
                       from: source,
                       operation: .sourceOver,
                       fraction: 1,
                       respectFlipped: true,
                       hints: nil)
        }
    }
    
    /// macOS 27 casts no shadow around the selected tab; its outline darkens
    /// along the bottom edge instead (see drawCellOutline).
    static var drawsDropShadow: Bool {
        if #available(macOS 27, *) {
            return false
        }
        return true
    }

    func drawDropShadow(cell: PSMTabBarCell) {
        let scale = cell.controlView?.window?.backingScaleFactor ?? 2.0
        
        switch orientation {
        case .horizontalOrientation:
            let leftShadow = Self.rightDropShadow
            let shadowSize = leftShadow.size
            // The drop shadow image is the left side of the shadow.
            // The rightmost 30 pixels include the left portion of a tab.
            let offset = CGFloat(30 / scale)
            // The images fit a standard tab, whose frame is 1pt shorter.
            // A tab made taller by rich tab content stretches their middles.
            let shadowHeight = (tabBar?.showsRichTabContent ?? false)
                ? max(shadowSize.height, cell.frame.height + 1)
                : shadowSize.height
            let leftDestinationRect = NSRect(x: cell.frame.minX - shadowSize.width + offset,
                                             y: cell.frame.minY - 0.5,
                                             width: shadowSize.width,
                                             height: shadowHeight)
            Self.draw(leftShadow, in: leftDestinationRect, scaledHeight: shadowSize.height)
            
            let rightShadow = Self.leftDropShadow
            let rightDestinationRect = NSRect(x: cell.frame.maxX - offset,
                                              y: cell.frame.minY - 0.5,
                                              width: shadowSize.width,
                                              height: shadowHeight)
            Self.draw(rightShadow, in: rightDestinationRect, scaledHeight: shadowSize.height)
            
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

    // Half the container's height in a standard (36pt) horizontal bar. With
    // rich tab content, corners never get rounder than this.
    private static let richContentMaximumCornerRadius = 14.0
    private static let standardContainerHeight = 28.0
    let containerSideInset = CGFloat(8)
    var containerTopInset: CGFloat {
        tabBar?.insets.top ?? 0.0
    }
    let containerBottomInset = CGFloat(0)
    
    /// The bar's own shape, minus the add-tab button's margin when it is showing.
    private func backgroundRect(forBar bar: PSMTabBarControl, in rect: NSRect) -> NSRect {
        var backgroundRect = rect
        if bar.showAddTabButton {
            backgroundRect.size.width -= 32.0
        }
        return backgroundRect
    }

    /// The shape a per-cell accessory subview (the progress ring, the activity indicator) has to stay
    /// inside, in the bar's coordinates, or nil when there is none.
    ///
    /// An accessory is a subview drawn on top of -drawRect:, so it never sees the graphics clip
    /// `drawTabBar` sets for cells, and without this it follows its tab straight out past the bar's
    /// rounded ends. This is the bar's own painted shape: `drawBackground(in:color:horizontal:)`
    /// fills exactly this path, so an accessory held to it cannot paint where the bar is not.
    ///
    /// Deliberately NOT the clip cells get while the bar is scrollable, which is this path tightened
    /// by (2, 1) so a scrolled pill cannot paint over the rounded border. The progress ring is outset
    /// past its pill by `progressRingWidth` on every side, and `adjustedCellRect` puts the cell's top
    /// at `containerTopInset`, so the ring's top edge lands exactly on the container's. Holding it to
    /// the cell clip would shave the ring's top band, and most of the first and last tab's side
    /// bands, which is the very thing the ring is drawn outset to show.
    @objc func accessoryClipPath(forTabBar bar: PSMTabBarControl) -> NSBezierPath? {
        // Take the axis from the bar rather than the cached one, the way every other query that is
        // handed a bar does, and pass it down instead of writing it back: only drawTabBar syncs the
        // cache, and this runs from layout, where -[iTermTabBarControlView setOrientation:] relays
        // out through -update before it assigns the style's orientation. Updating the cache here
        // would flip it partway through a pass whose earlier half already read the old value.
        guard bar.orientation == .horizontalOrientation else {
            // The vertical clip is the bar's full rect, which no accessory can leave.
            return nil
        }
        return clippingPath(rect: backgroundRect(forBar: bar, in: bar.bounds),
                            orientation: bar.orientation)
    }

    // The bar's rounded container shape. `insetX`/`insetY` shrink it on each side;
    // both default to 0 so the background fill uses the full shape. A scrollable
    // bar insets the *cell* clip (see -drawTabBar:) so scrolled cells can't paint
    // over the rounded border. `orientation` defaults to the cached axis; a caller
    // that runs outside a draw, where the cache can lag the bar, passes the bar's.
    private func clippingPath(rect: NSRect,
                              insetX: CGFloat = 0,
                              insetY: CGFloat = 0,
                              orientation: PSMTabBarOrientation? = nil) -> NSBezierPath {
        if (orientation ?? _orientation) == .horizontalOrientation {
            // 28pt, or the bar less its insets when rich tab content makes the
            // bar taller than that. (Some layouts, such as traditional full
            // screen, have larger insets and still use 28.)
            let height = (tabBar?.showsRichTabContent ?? false)
                ? max(Self.standardContainerHeight,
                      rect.height - containerTopInset - (tabBar?.insets.bottom ?? 0))
                : Self.standardContainerHeight
            let container = NSRect(x: containerSideInset - 0.5,
                                   y: containerTopInset,
                                   width: rect.width - containerSideInset * 2 + 1,
                                   height: height).insetBy(dx: insetX, dy: insetY)
            let radius = max(0, min(container.height / 2.0, maximumCornerRadius))
            if #available(macOS 27, *), radius >= container.height / 2 - 0.001 {
                return PSMTahoeStadiumEnd.bar.path(in: container)
            }
            return NSBezierPath(roundedRect: container, xRadius: radius, yRadius: radius)
        } else {
            return NSBezierPath(rect: rect.insetBy(dx: 0, dy: insetY))
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
        if #available(macOS 27, *), horizontal, let trackRimColor {
            // macOS 27 rims the bar with a 0.5pt line just inside its edge,
            // a little dimmer around the rounded ends.
            let outline = clippingPath(rect: rect)
            let ring = clippingPath(rect: rect)
            ring.append(clippingPath(rect: rect, insetX: 0.5, insetY: 0.5))
            ring.windingRule = .evenOdd
            NSGraphicsContext.saveGraphicsState()
            ring.addClip()
            (trackRimEndColor ?? trackRimColor).set()
            outline.bounds.fill()
            let endLength = PSMTahoeStadiumEnd.bar.length * outline.bounds.height / 2
            trackRimColor.set()
            outline.bounds.insetBy(dx: endLength, dy: 0).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The color of the rim around the bar's rounded ends on macOS 27, when it
    /// differs from trackRimColor.
    var trackRimEndColor: NSColor? {
        return nil
    }

    /// The color of the 0.5pt rim around the bar on macOS 27, or nil for none.
    var trackRimColor: NSColor? {
        return NSColor(displayP3Red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 220.0 / 255.0, alpha: 1.0)
    }
    
    class var backgroundColor: NSColor {
        if #available(macOS 27, *) {
            return NSColor(displayP3Red: 232.0 / 255.0, green: 232.0 / 255.0, blue: 232.0 / 255.0, alpha: 1.0)
        }
        return NSColor(white: 0.9, alpha: 1.0)
    }
    
    @objc func drawTabBar(_ bar: PSMTabBarControl, in rect: NSRect, clipRect: NSRect, horizontal: Bool, withOverflow: Bool) {
        if _orientation != bar.orientation {
            _orientation = bar.orientation
        }
        
        if tabBar !== bar {
            tabBar = bar
        }

        // Drawing one tab asks this several times and answering it examines every tab.
        anyTabHasColorWhileDrawing = nil
        anyTabHasColorWhileDrawing = anyTabHasColor()
        // These are the same for every title and slow to look up.
        titleOptionsWhileDrawing = nil
        titleOptionsWhileDrawing = titleOptions
        defer {
            anyTabHasColorWhileDrawing = nil
            titleOptionsWhileDrawing = nil
        }

        let backgroundColor = Self.backgroundColor
        let backgroundRect = self.backgroundRect(forBar: bar, in: rect)

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
            // Intersect against the shadow-inclusive dirty frame, not just the
            // cell frame: a selected tab's drop shadow reaches past its frame into
            // neighbors, so a partial repaint of an adjacent region (e.g. hovering
            // a group chip) must redraw that cell for its shadow to survive. Using
            // only cell.frame here left the shadow painted over by the bar
            // background and not restored.
            // A collapsed member is normally skipped, but while a collapse/expand
            // animation is sliding its width between full and 0 it must be drawn
            // (its width is > 0 mid-slide; it lands at exactly 0 when fully
            // collapsed, at which point it's skipped again).
            let hiddenByCollapse = cell.isHiddenByCollapse
            let reach = cell.state == .on ? dirtyFrame(for: cell) : cell.frame
            return !cell.isInOverflowMenu && !hiddenByCollapse &&
                NSIntersectsRect(reach, clipRect)
        }

        if drawableCells.count > 0 {
            // When the bar is scrollable, tabs can scroll all the way to the
            // rounded ends. The selected tab's opaque pill would then paint over
            // the bar's rounded border, since a non-scrollable bar only keeps tabs
            // off the ends via its left/right margins. Inset the cell clip so a
            // ring of bar background survives around the rounded ends. The inset
            // matches the pill's own top/bottom margin (see -backgroundRect(for:),
            // which insets 2 top / 1 bottom) so the pill itself is never clipped.
            // Scope this tighter clip to the cells only: the group-run outline
            // (drawn below) is intentionally outset past the cells and must reach
            // the pill edges, so it stays under the full clip set above.
            NSGraphicsContext.current?.saveGraphicsState()
            if bar.tabBarIsScrollable() {
                clippingPath(rect: backgroundRect, insetX: 2, insetY: 1).addClip()
            }
            if let i = drawableCells.firstIndex(where: { $0.state == .on }) {
                let cell = drawableCells.remove(at: i)
                drawableCells.append(cell)
            }
            for cell in drawableCells {
                // Mid-slide a shrinking member can be much shorter than its title,
                // which would otherwise overflow past the group outline; clip it to
                // its frame. But NOT the selected tab: it draws a drop shadow and
                // progress ring OUTSIDE its frame (see drawDropShadow /
                // progressBarRect), and the invariant keeps it out of the animating
                // group, so it is always full height and never needs clipping.
                if bar.collapseAnimating && cell.state != .on {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(rect: cell.frame).addClip()
                    cell.draw(withFrame: cell.frame, in: bar)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    cell.draw(withFrame: cell.frame, in: bar)
                }
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
            // Mid-drag the clip rect can cover only zero-width placeholders, so
            // cellsForDividers filters to empty; guard the count or 0..<(-1)
            // traps.
            if sorted.count > 1 {
                for i in 0..<(sorted.count - 1) {
                    drawDivider(betweenCell: sorted[i], andCell: sorted[i + 1])
                }
            }
            if let selectedCell = drawableCells.first, selectedCell.state == .on {
                selectedCell.drawPostHocDecorations(onSelectedCell: selectedCell, tabBarControl: bar)
            }
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // The container clip above hugs the tab pills with only a 2pt top / 1pt
        // bottom margin and is anchored at `containerSideInset`, but a tab-group
        // run's enclosing outline outsets `groupRunOutset` past those pills on every
        // side and its horizontal extent follows the cell layout (`leftMargin` /
        // `insets`), not `containerSideInset`. Under the tight container clip its top
        // line landed flush with the clip edge (antialiased away), its bottom line
        // fell outside it, and a run touching the first or last tab had its leading
        // or trailing cap shaved, so only partial outlines survived. The run pill is
        // itself a rounded stadium that hugs the tabs, so it never needs the
        // container's rounded corners; drop the container clip and draw the group
        // decorations unclipped. A scrollable bar is still bounded horizontally by
        // the viewport clip in -drawRect: (widened by the run outset), and the
        // scroll-margin strips are handled by the empty-clipRect guard inside
        // -drawTabGroupRunDecorations:. The restore/save keeps the graphics-state
        // stack balanced against the outer save/defer that wraps the whole method.
        NSGraphicsContext.current?.restoreGraphicsState()
        NSGraphicsContext.current?.saveGraphicsState()
        drawTabGroupRunDecorations(forTabBar: bar, clipRect: clipRect)
    }

    // The selected tab is a pill, which is mark enough.
    @objc func sectionGuideMarksSelectedTab() -> Bool {
        return false
    }

    // The selected tab's pill would cover a guide line at its edge.
    @objc func sectionGuideGap() -> CGFloat {
        return 6
    }

    // The chip cell draws nothing; the whole group run's decoration (name
    // capsule + enclosing pill) is drawn here in -drawTabBar:, since the pill
    // spans multiple cells.
    @objc func usesExternalTabGroupDecoration() -> Bool {
        return true
    }

    // Group-decoration geometry, shared by the chip-cell width reservation and
    // the drawing so the name capsule and the colored "B" area stay consistent.
    private static let groupNameCapsulePad: CGFloat = 8    // horizontal padding in the name capsule
    private static let groupNameCapsuleVPad: CGFloat = 5   // vertical padding in a vertical bar's name capsule
    private static let groupNameCapsuleMargin: CGFloat = 1 // group-color margin around the name capsule
    private static let groupBAreaWidth: CGFloat = 3        // colored area between the name capsule and first tab (yields a 4pt name-to-tab gap)
    private static let groupChipToTabGap: CGFloat = 1      // bg gap between that colored area and the first tab
    private static let groupRunOutset: CGFloat = 2         // how far the enclosing pill extends past the wrapped tabs
    // A sub-group's pill does not outset: it sits inside its parent's run, whose
    // own outline already wraps it, so the two outlines stay visibly nested.
    private static let subgroupRunOutset: CGFloat = 0
    private static let collapsedChipChevronWidth: CGFloat = 12  // room for the collapse chevron on a collapsed chip
    private static let collapsedChipAttentionWidth: CGFloat = 20  // room for the attention icon on a collapsed chip
    private static let collapsedChipAttentionIconSize: CGFloat = 16  // side of the attention icon (drawn at the size tabs use)

    // The one font used for every group name/chip label; the measuring and drawing
    // paths must agree, so both read it from here.
    private static var groupNameFont: NSFont {
        NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
    }

    // The collapsed chip's label ("Name  N", or just "N" when unnamed). Shared by
    // the width MEASURE and the DRAW so the reserved chip width always matches the
    // rendered text.
    private static func collapsedChipLabel(forName name: String, count: Int) -> String {
        return name.isEmpty ? "\(count)" : "\(name)  \(count)"
    }

    // Per-group drawing chrome shared by the run and collapsed-chip drawers.
    private func tabGroupChrome(forGroupID groupID: String,
                                bar: PSMTabBarControl) -> (color: NSColor, bg: NSColor, name: String) {
        let group = bar.tabGroupDataSource?.tabGroup(withIdentifier: groupID)
        return (group?.color ?? NSColor.systemBlue, Self.backgroundColor, group?.name ?? "")
    }

    @objc func tabGroupRunOutset() -> CGFloat {
        return Self.groupRunOutset
    }

    // How far `chip`'s group pill extends past the cells it wraps.
    private func runOutset(forChip chip: PSMTabBarCell) -> CGFloat {
        return (chip.tabGroupParentIdentifier?.isEmpty == false) ? Self.subgroupRunOutset : Self.groupRunOutset
    }

    // The left outset the group pill actually uses for `chip` (see -drawTabGroupRun
    // / -drawCollapsedTabGroupChip): neighbor-aware on a horizontal bar (0 when the
    // preceding cell already covers the shared gap), the symmetric constant on a
    // vertical bar. A group's drag image uses this to include the left outline.
    @objc func tabGroupChipLeftOutset(forChip chip: PSMTabBarCell, bar: PSMTabBarControl) -> CGFloat {
        return (bar.orientation == .horizontalOrientation)
            ? leftOutset(forChip: chip, bar: bar)
            : runOutset(forChip: chip)
    }

    @objc func tabGroupChipCellWidth(forName name: String) -> CGFloat {
        let font = Self.groupNameFont
        let textWidth = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        return Self.groupNameCapsuleMargin * 2 + textWidth + Self.groupNameCapsulePad * 2 + Self.groupBAreaWidth
    }

    // A collapsed group is a short capsule with its name, count, and chevron.
    // Its lines would be the members' combined content less the title and
    // subtitle, which is mostly empty, in a chip sized like a whole tab row.
    @objc func showsRichContentOnCollapsedTabGroupChips() -> Bool {
        return false
    }

    @objc func tabGroupChipCellHeight(forName name: String) -> CGFloat {
        let font = Self.groupNameFont
        let textHeight = ceil(font.ascender - font.descender)
        return Self.groupNameCapsuleMargin + (textHeight + Self.groupNameCapsuleVPad * 2) + Self.groupBAreaWidth
    }

    @objc func drawTabGroupRunDecorations(forTabBar bar: PSMTabBarControl, clipRect: NSRect) {
        if bar.suppressTabGroupRunDecoration {
            return
        }
        // An empty clipRect is the "background only" signal used when repainting a
        // scroll margin strip (the stoplight band, the add-button margin). The cell
        // loop already honors it; the run/chip decoration must too, or a chip or
        // outline scrolled into that strip would draw under the window buttons.
        if clipRect.isEmpty {
            return
        }
        let horizontal = (orientation == .horizontalOrientation)
        // The bar owns run detection (placeholder transparency, join-slot
        // union); this style only maps each cell to its visible background
        // rect and draws the geometry it is handed.
        bar.enumerateTabGroupRuns(rectForCell: { [weak self] cell in
            self?.backgroundRect(for: cell.frame) ?? cell.frame
        }, block: { chip, tabsRect, firstTab, gid in
            if horizontal {
                self.drawTabGroupRun(chip: chip, tabsRect: tabsRect, firstTab: firstTab, groupID: gid, bar: bar)
            } else {
                self.drawTabGroupRunVertical(chip: chip, tabsRect: tabsRect, firstTab: firstTab, groupID: gid, bar: bar)
            }
        })
        // A fully collapsed run has no visible member tabs, so the run block
        // above is never invoked for it; its chip draws a self-contained
        // affordance (name + member count + collapse chevron) instead.
        let dropTargetGID = bar.collapsedTabGroupDropTargetIdentifier()
        bar.enumerateCollapsedTabGroupChips { chip, memberCount, gid in
            self.drawCollapsedTabGroupChip(chip: chip,
                                           memberCount: memberCount,
                                           groupID: gid,
                                           bar: bar,
                                           isDropTarget: gid == dropTargetGID)
        }
    }

    // The left outset a group's pill should use. A group covers the background
    // sliver on its left by outsetting there, EXCEPT when the cell just before
    // its chip already belongs to a group: that group's own right outset already
    // covers the shared inter-group gap, so outsetting left too would overlap it.
    private func leftOutset(forChip chip: PSMTabBarCell, bar: PSMTabBarControl) -> CGFloat {
        // A group covers the background sliver on its left by outsetting there,
        // EXCEPT when the cell just before its chip already belongs to a group:
        // that group's own right outset already covers the shared inter-group gap,
        // so outsetting left too would overlap it. The neighbor scan lives on the
        // control (over its cells directly) so this draw-hot path does not bridge
        // the whole cells NSArray into a fresh Swift copy per run per frame.
        if chip.tabGroupParentIdentifier?.isEmpty == false {
            return Self.subgroupRunOutset
        }
        return bar.cellPrecedingChipCoversInterGroupGap(chip) ? 0 : Self.groupRunOutset
    }

    // A collapsed group's chip: a self-contained pill (derived from the chip
    // frame alone, since no member tabs are drawn) showing the group color, a
    // background capsule with the name and member count, and a chevron marking
    // it as expandable.
    private func drawCollapsedTabGroupChip(chip: PSMTabBarCell,
                                           memberCount: Int,
                                           groupID: String,
                                           bar: PSMTabBarControl,
                                           isDropTarget: Bool) {
        let (groupColor, bgColor, name) = tabGroupChrome(forGroupID: groupID, bar: bar)
        let font = Self.groupNameFont
        let textCol = NSColor.labelColor

        let outset = runOutset(forChip: chip)
        let base = backgroundRect(for: chip.frame)
        // Outset on all four sides (like the expanded run) so the outline sits
        // outside where a tab's own outline would be, covering the background
        // sliver around the chip. -leftOutset inspects the previous cell in the
        // (horizontal) _cells order, so it only applies to a horizontal bar; on a
        // vertical bar the "left" is the bar's horizontal edge with no neighbor, so
        // outset symmetrically there (matching the expanded vertical run) rather
        // than insetting the left whenever the cell ABOVE happens to be grouped.
        let leftOut = (bar.orientation == .horizontalOrientation)
            ? leftOutset(forChip: chip, bar: bar)
            : outset
        let pill = NSRect(x: chip.frame.minX - leftOut,
                          y: base.minY - outset,
                          width: chip.frame.width + outset + leftOut,
                          height: base.height + 2 * outset)
        guard pill.width > 0, pill.height > 0 else {
            return
        }
        // Background capsule holding the label and chevron. On a HORIZONTAL bar it
        // fills the pill (centered). On a VERTICAL bar it is a fixed-height band at
        // the TOP of the pill, exactly matching -drawTabGroupRunVertical, so the
        // name sits at the same y whether drawn as the run (expanded / mid-slide)
        // or as this settled chip -- otherwise it jumps half a point at the handoff.
        // Computed and guarded BEFORE any fill: a chip too narrow for its capsule
        // (capsule width == pill.width - 2*margin, e.g. a chip mostly scrolled under
        // the stoplight band) must draw NOTHING, not a bare colored pill blob
        // missing its capsule, label, chevron, and outline.
        let capsuleMargin = Self.groupNameCapsuleMargin
        let textHeight = ceil(font.ascender - font.descender)
        let capsule: NSRect
        if bar.orientation == .horizontalOrientation {
            capsule = pill.insetBy(dx: capsuleMargin, dy: capsuleMargin)
        } else {
            let capsuleHeight = textHeight + Self.groupNameCapsuleVPad * 2
            capsule = NSRect(x: pill.minX + capsuleMargin,
                             y: pill.minY + capsuleMargin,
                             width: pill.width - capsuleMargin * 2,
                             height: capsuleHeight)
        }
        guard capsule.width > 0, capsule.height > 0 else {
            return
        }
        let radius = outsetCornerRadius(for: pill, outset: outset)

        // Group-color pill body.
        groupColor.set()
        roundedPath(pill.insetBy(dx: 0.5, dy: 0.5), radius: radius).fill()

        let capsuleRadius = pillCornerRadius(for: capsule)
        bgColor.set()
        roundedPath(capsule, radius: capsuleRadius).fill()

        // Label: "Name  N" (or just "N" when unnamed), left-aligned, leaving room
        // for the chevron at the right.
        let label = Self.collapsedChipLabel(forName: name, count: memberCount)
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                     .foregroundColor: textCol,
                                                     .paragraphStyle: para]
        let pad = Self.groupNameCapsulePad
        let chevronW = Self.collapsedChipChevronWidth
        let attentionW = Self.collapsedChipAttentionWidth
        let textRect = NSRect(x: capsule.minX + pad,
                              y: capsule.midY - textHeight / 2.0,
                              width: max(0, capsule.width - pad * 2 - attentionW - chevronW),
                              height: textHeight)
        PSMTabSearchHighlight.highlighting(NSAttributedString(string: label, attributes: attrs),
                                           query: tabBar?.searchHighlightQuery).draw(in: textRect)

        // Attention icon for the hidden members, in a slot reserved between the
        // label and the chevron whether or not there is an icon to show.
        if let attention = bar.attentionImage(forTabGroupIdentifier: groupID) {
            let side = Self.collapsedChipAttentionIconSize
            // Center what's drawn, not the canvas: some icons (new output,
            // bell) sit off center in theirs.
            let slotCenter = NSPoint(x: capsule.maxX - pad - chevronW - attentionW / 2.0,
                                     y: capsule.midY)
            let iconRect = PSMIconContentBounds.rect(centeringVisibleContentOf: attention,
                                                     at: slotCenter,
                                                     size: side)
            attention.draw(in: iconRect,
                           from: .zero,
                           operation: .sourceOver,
                           fraction: 1,
                           respectFlipped: true,
                           hints: nil)
        }

        // Downward chevron at the capsule's right edge: the collapse affordance.
        let cx = capsule.maxX - pad - chevronW / 2.0
        let cy = capsule.midY
        let half: CGFloat = 3
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: cx - half, y: cy + half / 2.0))
        chevron.line(to: NSPoint(x: cx, y: cy - half / 2.0))
        chevron.line(to: NSPoint(x: cx + half, y: cy + half / 2.0))
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        textCol.setStroke()
        chevron.stroke()

        // Enclosing outline, identical to the expanded run's (same path, radius,
        // and 1pt width) so a collapsed group's border reads exactly like an
        // expanded one -- not thinner or inset. The solid body fill above stops at
        // pill.insetBy(0.5); this stroke, centered there, carries the group color
        // back out to the pill edge to match.
        groupColor.set()
        let outline = roundedPath(pill.insetBy(dx: 0.5, dy: 0.5), radius: radius)
        outline.lineWidth = 1
        outline.stroke()

        // Drop-target feedback: while a dragged tab is poised to join this
        // collapsed group, ring the pill in the accent color so the user sees the
        // drop lands INSIDE the group (no member cells open a slot to show it).
        if isDropTarget {
            let ring = roundedPath(pill.insetBy(dx: -1.0, dy: -1.0), radius: radius + 1.0)
            ring.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }

    // `nested` needs no extra room here: the pill grows past the chip by the
    // run outset, which is 0 for a sub-group, and this width already assumes
    // none.
    @objc func tabGroupCollapsedChipCellWidth(forName name: String,
                                              memberCount count: Int,
                                              nested: Bool) -> CGFloat {
        let font = Self.groupNameFont
        let label = Self.collapsedChipLabel(forName: name, count: count)
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        return Self.groupNameCapsuleMargin * 2 + Self.groupNameCapsulePad * 2 +
            textWidth + Self.collapsedChipAttentionWidth + Self.collapsedChipChevronWidth
    }

    private func drawTabGroupRun(chip: PSMTabBarCell,
                                 tabsRect: NSRect,
                                 firstTab: PSMTabBarCell?,
                                 groupID: String,
                                 bar: PSMTabBarControl) {
        let (groupColor, bgColor, name) = tabGroupChrome(forGroupID: groupID, bar: bar)
        // Match the collapsed chip's label color (labelColor) so a group's name
        // reads the same collapsed or expanded, rather than taking the first tab's
        // text color.
        let textCol = NSColor.labelColor

        let chipFrame = chip.frame
        // Outset the pill on all four sides so its 1pt outline sits OUTSIDE the
        // tab pills' own outlines (which are inset ~2pt within the bar's dark
        // background), covering the sliver of background around the run. The left
        // needs the outset too: without it the run outline lands on the first
        // tab's outline instead of outside it (asymmetric with the right).
        let outset = runOutset(forChip: chip)
        let leftOut = leftOutset(forChip: chip, bar: bar)
        // Take the pill's vertical extent from the chip (whose height is always
        // valid), not from tabsRect: mid-slide the member frames can be zero-width
        // and momentarily give a degenerate height, which would misplace the name.
        // The chip and tabs share the bar's cell height, so this matches at rest.
        let chipBase = backgroundRect(for: chipFrame)
        let pill = NSRect(x: chipFrame.minX - leftOut,
                          y: chipBase.minY - outset,
                          width: tabsRect.maxX - chipFrame.minX + outset + leftOut,
                          height: chipBase.height + 2 * outset)
        guard pill.width > 0, pill.height > 0 else {
            return
        }
        let radius = outsetCornerRadius(for: pill, outset: outset)

        // Group-color fill for the left of the run: the pill's rounded left cap
        // plus the "B" area, whose RIGHT edge is a concave scoop that hugs the
        // first tab (the "( (" shape), not a convex stadium end. Build it as a
        // rounded-left rect clipped just short of the first tab, minus a circle
        // the size of the pill that carves the concave right edge.
        let firstVis = firstTab.map { backgroundRect(for: $0.frame) } ?? tabsRect
        let bGap = Self.groupChipToTabGap
        let tabRadius = pillCornerRadius(for: firstVis)
        // Clip to the first tab's center so the fill stops there, then fill a
        // rounded-left region and carve a concave that follows the first tab's
        // left curve offset by bGap, so the blue hugs the tab (the "( (" shape).
        let clipRight = firstVis.midX
        if clipRight > pill.minX {
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: pill.minX, y: pill.minY,
                   width: clipRight - pill.minX, height: pill.height).clip()
            let region = roundedPath(NSRect(x: pill.minX,
                                            y: pill.minY,
                                            width: (clipRight - pill.minX) + radius,
                                            height: pill.height),
                                     radius: radius)
            region.append(roundedPath(firstVis.insetBy(dx: -bGap, dy: -bGap), radius: tabRadius + bGap))
            region.windingRule = .evenOdd
            groupColor.set()
            region.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Name capsule (tabbar background) with a group-color margin around it, so
        // the name reads on the bar rather than on the group color.
        let capsuleMargin = Self.groupNameCapsuleMargin
        let font = Self.groupNameFont
        let textWidth = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        let capsulePad = Self.groupNameCapsulePad
        let capsuleHeight = pill.height - capsuleMargin * 2
        let capsuleRadius = min(capsuleHeight / 2.0, maximumCornerRadius)
        let capsuleWidth = textWidth + capsulePad * 2
        let capsule = NSRect(x: pill.minX + capsuleMargin,
                             y: pill.minY + capsuleMargin,
                             width: capsuleWidth,
                             height: capsuleHeight)
        bgColor.set()
        roundedPath(capsule, radius: capsuleRadius).fill()

        if !name.isEmpty {
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                         .foregroundColor: textCol,
                                                         .paragraphStyle: para]
            let textHeight = ceil(font.ascender - font.descender)
            let textRect = NSRect(x: capsule.minX,
                                  y: capsule.midY - textHeight / 2.0,
                                  width: capsule.width,
                                  height: textHeight)
            PSMTabSearchHighlight.highlighting(NSAttributedString(string: name, attributes: attrs),
                                           query: tabBar?.searchHighlightQuery).draw(in: textRect)
        }

        // Enclosing pill outline (1pt), inset a half point so the stroke is crisp.
        groupColor.set()
        let outline = roundedPath(pill.insetBy(dx: 0.5, dy: 0.5), radius: radius)
        outline.lineWidth = 1
        outline.stroke()
    }

    // Vertical bar: the same design rotated 90 degrees. The name capsule spans
    // the bar width at the top of the run, the tabs stack below, the group-color
    // outline encloses all of it, and a group-color connector below the name
    // capsule hugs the first (top) tab.
    private func drawTabGroupRunVertical(chip: PSMTabBarCell,
                                         tabsRect: NSRect,
                                         firstTab: PSMTabBarCell?,
                                         groupID: String,
                                         bar: PSMTabBarControl) {
        let (groupColor, bgColor, name) = tabGroupChrome(forGroupID: groupID, bar: bar)
        // Match the collapsed chip's label color (labelColor) so a group's name
        // reads the same collapsed or expanded, rather than taking the first tab's
        // text color.
        let textCol = NSColor.labelColor

        let chipFrame = chip.frame
        let outset = runOutset(forChip: chip)
        var pill = NSRect(x: tabsRect.minX - outset,
                          y: chipFrame.minY,
                          width: tabsRect.width + 2 * outset,
                          height: tabsRect.maxY + outset - chipFrame.minY)
        // Clamp the bottom to the top of the first cell after the group so the
        // outline never overlaps it. During a slide the last member can be
        // momentarily zero-height, whose backgroundRect extent + outset would
        // otherwise reach ~1pt into the next cell for the first frame or two
        // (before the intercell gap opens up). A no-op when settled (they meet).
        // The scan lives on the control (over its cells directly) so this draw-hot
        // path does not bridge the whole cells NSArray into a fresh Swift copy.
        if let next = bar.firstNonMemberCell(afterChip: chip, groupID: groupID),
           next.frame.minY < pill.maxY {
            pill.size.height = max(0, next.frame.minY - pill.minY)
        }
        guard pill.width > 0, pill.height > 0 else {
            return
        }
        let firstVis = firstTab.map { backgroundRect(for: $0.frame) } ?? tabsRect
        // Two radii. The enclosing pill's corner radius (top cap + outline) must
        // stay STABLE during a vertical collapse/expand slide, so derive it from
        // the chip's expanded header height -- not from the first member, whose
        // height animates 0<->full, nor from the chip's frame, whose height
        // animates too when a collapsed chip shows rich content lines -- either
        // would warp the top cap and the outline. The concave carve below still
        // hugs the (animating) first tab, so it uses the member's own radius. At
        // standard heights the two are equal (chip height == tab height). Rows
        // made taller for rich tab content keep a shorter header, which differs
        // from the tabs' capped radius by a point. Mid-slide the run shows only
        // the name capsule; the collapsed chip's lines appear when it takes over.
        var headerFrame = chipFrame
        headerFrame.size.height = min(chipFrame.height,
                                      bar.height(ofTabGroupChipCell: chip, collapsed: false) - 1)
        let chipHalfHeight = backgroundRect(for: headerFrame).height / 2.0
        let cornerRadius = pillCornerRadius(for: backgroundRect(for: headerFrame)) + outset
        let tabRadius = pillCornerRadius(for: firstVis)
        // Near full collapse the pill gets shorter than twice the (stable) corner
        // radius, so its rounded caps overlap into thin-line artifacts; clamp the
        // radius to half the pill height there.
        let effCorner = min(cornerRadius, pill.height / 2.0)

        // Group-color fill for the top of the run: the rounded top cap plus the
        // connector area, whose BOTTOM edge hugs the first tab's top with a gap.
        // Clip to the first member's middle so the fill is just the top band +
        // connector, NEVER the whole pill (which would paint over every member
        // tab). The carve subtracts the tab, so the visible connector is a fixed
        // strip from the chip band down to the member's (stable) top edge.
        // Once there is less than half a tab of member under the chip, drop the
        // solid fill ENTIRELY and let just the outline stand: near collapse the
        // carve of a near-zero member produces a bad shape, and an outline-only
        // chip is the clean way to bridge to the settled collapsed chip.
        let bGap = Self.groupChipToTabGap
        let connectorVisible = firstVis.height >= chipHalfHeight
        let clipBottom = firstVis.midY
        if connectorVisible && clipBottom > pill.minY {
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: pill.minX, y: pill.minY,
                   width: pill.width, height: clipBottom - pill.minY).clip()
            let region = roundedPath(NSRect(x: pill.minX,
                                            y: pill.minY,
                                            width: pill.width,
                                            height: (clipBottom - pill.minY) + effCorner),
                                     radius: effCorner)
            region.append(roundedPath(firstVis.insetBy(dx: -bGap, dy: -bGap), radius: tabRadius + bGap))
            region.windingRule = .evenOdd
            groupColor.set()
            region.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Name capsule (tabbar background) at the top, spanning the width, with a
        // 1pt group-color margin. The name is left-aligned.
        let capsuleMargin = Self.groupNameCapsuleMargin
        let font = Self.groupNameFont
        let textHeight = ceil(font.ascender - font.descender)
        let capsuleHeight = textHeight + Self.groupNameCapsuleVPad * 2
        let capsule = NSRect(x: pill.minX + capsuleMargin,
                             y: pill.minY + capsuleMargin,
                             width: pill.width - capsuleMargin * 2,
                             height: capsuleHeight)
        let capsuleRadius = pillCornerRadius(for: capsule)
        bgColor.set()
        roundedPath(capsule, radius: capsuleRadius).fill()

        if !name.isEmpty {
            let para = NSMutableParagraphStyle()
            para.alignment = .left
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                         .foregroundColor: textCol,
                                                         .paragraphStyle: para]
            let textInset: CGFloat = 8
            let textRect = NSRect(x: capsule.minX + textInset,
                                  y: capsule.midY - textHeight / 2.0,
                                  width: max(0, capsule.width - textInset * 2),
                                  height: textHeight)
            PSMTabSearchHighlight.highlighting(NSAttributedString(string: name, attributes: attrs),
                                           query: tabBar?.searchHighlightQuery).draw(in: textRect)
        }

        // Enclosing pill outline (1pt), inset a half point so the stroke is crisp.
        groupColor.set()
        let outline = roundedPath(pill.insetBy(dx: 0.5, dy: 0.5), radius: effCorner)
        outline.lineWidth = 1
        outline.stroke()
    }

    var dividerColor: NSColor {
        if #available(macOS 27, *) {
            return NSColor(displayP3Red: 204.0 / 255.0, green: 204.0 / 255.0, blue: 204.0 / 255.0, alpha: 1.0)
        }
        return NSColor(displayP3Red: 205.0 / 255.0, green: 205.0 / 255.0, blue: 205.0 / 255.0, alpha: 1.0)
    }

    func drawDivider(betweenCell leftCell: PSMTabBarCell, andCell rightCell: PSMTabBarCell) {
        if orientation != .horizontalOrientation {
            return
        }
        if leftCell.isHighlighted || rightCell.isHighlighted || leftCell.state == .on || rightCell.state == .on {
            return
        }
        if leftCell.isTabGroupChip || rightCell.isTabGroupChip {
            return
        }
        // Draw a divider only between two cells with the same group membership:
        // both ungrouped, or both members of the same group (an interior divider
        // marks the tab boundary inside the run, well within the enclosing
        // outline). At a group edge the identifiers differ and a divider there
        // would collide with that outline, so skip it.
        if leftCell.tabGroupIdentifier != rightCell.tabGroupIdentifier {
            return
        }
        guard let cells = tabBar?.cells() as? [PSMTabBarCell], cells.count >= 3 else {
            return
        }
        dividerColor.set()
        let rect: NSRect
        if #available(macOS 27, *) {
            // Centered in the bar, 16pt tall in a standard one.
            rect = NSRect(x: leftCell.frame.maxX,
                          y: leftCell.frame.minY + 6,
                          width: 1.0,
                          height: leftCell.frame.height - 11)
        } else {
            rect = NSRect(x: leftCell.frame.maxX,
                          y: leftCell.frame.minY + 5,
                          width: 1.0,
                          height: leftCell.frame.height - 10)
        }
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
        if let anyTabHasColorWhileDrawing {
            return anyTabHasColorWhileDrawing
        }
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
        
        let rect = backgroundRect(for: cellFrame)
        let path = pillPath(for: rect)
        // On macOS 27 an unselected tab that isn't under the mouse is just the
        // bar, so leave the bar (and its rim) showing.
        let drawsFill: Bool
        if #available(macOS 27, *) {
            drawsFill = selected || isHighlighted
        } else {
            drawsFill = true
        }
        if drawsFill {
            path.fill()
        }
        if selected {
            drawCellOutline(path: path, rect: rect)
        }

        if let tabColor {
            let color = cellBackgroundColor(forTabColor: tabColor, selected: true)
            color.set()
            if selected {
                // Tint the outline if this cell is selected.
                NSGraphicsContext.current?.saveGraphicsState()
                path.addClip()
                rect.fill(using: .color)

                // Additive white pushes the outline past reference white, which
                // reads as an HDR glow on an extended-range display. Gated
                // because forcing the display into EDR can hang some systems
                // (the same risk as the Metal HDR cursor). Off leaves the
                // outline tinted with the tab color, just not brighter than white.
                if iTermAdvancedSettingsModel.allowHDR() {
                    NSColor(white: 1.0, alpha: tabColor.perceivedBrightness).set()
                    rect.fill(using: .plusLighter)
                }
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            
            // Tint the inside.
            if selected {
                pillPath(for: rect, inset: 1.0).fill()
            } else {
                let path2 = pillPath(for: rect)
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

        // The measured edge brightens or darkens whatever is under it, so it
        // goes over the tab color's tint rather than under it.
        if selected, usesSelectedTabEdgeImage(rect: rect) {
            drawSelectedTabEdgeImage(rect: rect)
        }
    }
    
    func drawCellOutline(path: NSBezierPath, rect: NSRect) {
        if #available(macOS 27, *) {
            if !usesSelectedTabEdgeImage(rect: rect) {
                drawModernEdge(modernEdge, rect: rect)
            }
            return
        }
        Self.outlineColor.set()
        path.stroke()
    }

    /// Which part of TahoeSelectedTabEdges this style's selected tab uses, or
    /// nil to draw its edge in code from modernEdge.
    var selectedTabEdgeImageStrip: PSMTahoeSelectedTabEdgeStrip? {
        return windowIsMainAndAppIsActive ? .lightActive : .lightInactive
    }

    // On macOS 27 a selected tab of the standard height draws its edge from
    // an image measured from the system's own tab bar (see
    // drawSelectedTabEdgeImage). Other shapes draw it in code.
    private func usesSelectedTabEdgeImage(rect: NSRect) -> Bool {
        guard #available(macOS 27, *),
              selectedTabEdgeImageStrip != nil,
              Self.selectedTabEdgeImage != nil,
              abs(rect.height - PSMTahoeSelectedTabEdgeStrip.pillHeight) < 0.01,
              pillCornerRadius(for: rect) >= rect.height / 2 - 0.001 else {
            return false
        }
        return true
    }

    private static let selectedTabEdgeImage = Bundle(for: PSMTahoeTabStyle.self).image(forResource: "TahoeSelectedTabEdges")

    /// Draws the selected tab's edge over its fill from TahoeSelectedTabEdges.
    /// The image holds, for each state, how much macOS 27 brightens (white
    /// pixels) or darkens (black pixels) each pixel of the tab relative to its
    /// fill, measured from Terminal's tab bar. It is a left end, a 1pt middle
    /// that stretches, and a right end, with a 1pt margin all around.
    private func drawSelectedTabEdgeImage(rect: NSRect) {
        guard let image = Self.selectedTabEdgeImage, let strip = selectedTabEdgeImageStrip else {
            return
        }
        let frame = rect.insetBy(dx: -1, dy: -1)
        let height = frame.height
        let imageWidth = image.size.width
        let endWidth = min((imageWidth - 1) / 2, frame.width / 2)
        // Image coordinates start at the bottom.
        let sourceY = image.size.height - height * CGFloat(strip.rawValue + 1)
        var pieces = [(NSRect(x: 0, y: sourceY, width: endWidth, height: height),
                       NSRect(x: frame.minX, y: frame.minY, width: endWidth, height: height)),
                      (NSRect(x: imageWidth - endWidth, y: sourceY, width: endWidth, height: height),
                       NSRect(x: frame.maxX - endWidth, y: frame.minY, width: endWidth, height: height))]
        if frame.width > endWidth * 2 {
            pieces.append((NSRect(x: (imageWidth - 1) / 2, y: sourceY, width: 1, height: height),
                           NSRect(x: frame.minX + endWidth, y: frame.minY,
                                  width: frame.width - endWidth * 2, height: height)))
        }
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.none.rawValue]
        // Adding white leaves black pixels alone, and multiplying by black
        // leaves white pixels alone.
        for operation in [NSCompositingOperation.plusLighter, .multiply] {
            for (source, destination) in pieces {
                image.draw(in: destination, from: source, operation: operation,
                           fraction: 1, respectFlipped: true, hints: hints)
            }
        }
    }

    /// The shape of a pill drawn in `rect`, shrunk by `inset` on every side.
    /// Pills are stadiums, or rounded rectangles when rich tab content makes
    /// them tall. On macOS 27 a stadium's ends have the shape of the system's
    /// own window tab bar (see PSMTahoeStadiumEnd) rather than semicircles.
    func pillPath(for rect: NSRect, inset: CGFloat = 0) -> NSBezierPath {
        return roundedPath(rect.insetBy(dx: inset, dy: inset),
                           radius: max(0, pillCornerRadius(for: rect) - inset))
    }

    /// A rounded rectangle, except that on macOS 27 one round enough to be a
    /// stadium gets the system's stadium ends, so shapes drawn around or
    /// inside a tab follow its curve.
    func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        guard #available(macOS 27, *),
              rect.width > 0,
              rect.height > 0,
              radius >= rect.height / 2 - 0.001 else {
            return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        }
        return PSMTahoeStadiumEnd.selectedTab.path(in: rect)
    }

    /// How far a pill's rounded end reaches in from its side.
    func pillEndLength(for rect: NSRect, inset: CGFloat = 0) -> CGFloat {
        let shrunk = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, pillCornerRadius(for: rect) - inset)
        if #available(macOS 27, *), radius >= shrunk.height / 2 - 0.001 {
            return min(shrunk.height / 2 * PSMTahoeStadiumEnd.selectedTab.length, shrunk.width / 2)
        }
        return radius
    }

    // How far along a straight edge its color eases in from where a rounded
    // end meets it.
    private static let straightEdgeRampLength = CGFloat(2.25)

    /// How macOS 27 draws the edge of the selected tab, measured from the
    /// system's own window tab bars. The edge is lit from above and below, so
    /// its color depends on which way each part of it faces. On the rounded
    /// ends that direction varies with height alone, so vertical gradients
    /// reproduce it.
    struct ModernEdge {
        /// Values along the top half of the edge, keyed by how much that part
        /// faces up: 1 is the straight top edge and 0 is the vertical end of a
        /// rounded cap. The bottom half mirrors these except at the straight
        /// bottom edge, which has its own value.
        struct Profile {
            var points: [(facing: CGFloat, value: CGFloat)]
            var bottom: CGFloat
            /// Values along the straight top and bottom edges between the
            /// rounded ends, when they differ from where the ends meet them.
            var straightTop: CGFloat?
            var straightBottom: CGFloat?
        }

        /// The outermost 0.5pt as gray levels (0-255) drawn opaque, or nil
        /// for no outline.
        var outer: Profile?
        /// The next 0.5pt in, as opacities (0-1) of white over the fill.
        var innerHighlight: Profile?
        /// Opacities of a white glow inside the tab, keyed by distance from
        /// the top edge as a fraction of the tab's height. The bottom mirrors
        /// it.
        var glow: [(location: CGFloat, alpha: CGFloat)]?
    }

    var modernEdge: ModernEdge {
        // A faint shadow, darkest partway around each rounded end, that
        // nearly vanishes along the top, bottom, and vertical ends.
        if windowIsMainAndAppIsActive {
            return ModernEdge(outer: .init(points: [(1, 236), (0.91, 228), (0.74, 227), (0.57, 224),
                                                    (0.39, 222), (0.22, 220), (0, 247)],
                                           bottom: 240))
        }
        return ModernEdge(outer: .init(points: [(1, 228), (0.83, 223), (0.57, 222), (0.39, 221),
                                                (0.22, 220), (0.1, 232), (0, 243)],
                                       bottom: 230))
    }

    private func drawModernEdge(_ edge: ModernEdge, rect: NSRect) {
        if let glow = edge.glow, let first = glow.first, let last = glow.last {
            let white = { (alpha: CGFloat) in NSColor(white: 1, alpha: alpha) }
            // Hold the first value out to the edge, and mirror for the bottom.
            let top = [(location: CGFloat(0), alpha: first.alpha)] + glow
            let bottom = top.reversed().map { (location: 1 - $0.location, alpha: $0.alpha) }
            let stops = top + (last.location < 0.5 ? [(location: CGFloat(0.5), alpha: last.alpha)] : []) + bottom
            if let gradient = NSGradient(colors: stops.map { white($0.alpha) },
                                         atLocations: stops.map(\.location),
                                         colorSpace: .genericGray) {
                NSGraphicsContext.saveGraphicsState()
                pillPath(for: rect).addClip()
                // The tab bar is flipped, so 90 degrees runs from top to bottom.
                gradient.draw(in: rect, angle: 90)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if let inner = edge.innerHighlight {
            drawEdgeRing(rect: rect, inset: 0.5, profile: inner) { NSColor(white: 1, alpha: $0) }
        }
        if let outer = edge.outer {
            drawEdgeRing(rect: rect, inset: 0, profile: outer) {
                NSColor(displayP3Red: $0 / 255.0, green: $0 / 255.0, blue: $0 / 255.0, alpha: 1)
            }
        }
    }

    /// Fills the 0.5pt ring starting `inset` points inside `rect` with a
    /// vertical gradient following `profile`.
    private func drawEdgeRing(rect: NSRect,
                              inset: CGFloat,
                              profile: ModernEdge.Profile,
                              color: (CGFloat) -> NSColor) {
        let width = CGFloat(0.5)
        let outerRect = rect.insetBy(dx: inset, dy: inset)
        let ring = pillPath(for: rect, inset: inset)
        ring.append(pillPath(for: rect, inset: inset + width))
        ring.windingRule = .evenOdd

        // On a rounded end, the part of the edge whose facing is f sits at
        // (1 - f) / 2 of the way down from the top.
        let top = profile.points.map { (location: (1 - $0.facing) / 2, value: $0.value) }
        var bottom = top.reversed().map { (location: 1 - $0.location, value: $0.value) }
        if bottom.last?.location == 1 {
            bottom[bottom.count - 1].value = profile.bottom
        }
        let stops = top + bottom.filter { $0.location > 0.5 }
        guard let gradient = NSGradient(colors: stops.map { color($0.value) },
                                        atLocations: stops.map(\.location),
                                        colorSpace: .displayP3) else {
            return
        }
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }
        ring.addClip()
        // The straight edges between the rounded ends can have their own
        // values. Where they do, the gradient covers only the ends.
        let endLength = pillEndLength(for: rect, inset: inset)
        let straightTop = NSRect(x: outerRect.minX + endLength,
                                 y: outerRect.minY,
                                 width: max(0, outerRect.width - endLength * 2),
                                 height: outerRect.height / 2)
        let straightBottom = straightTop.offsetBy(dx: 0, dy: outerRect.height / 2)
        if profile.straightTop != nil || profile.straightBottom != nil {
            let ends = NSBezierPath(rect: NSRect(x: outerRect.minX, y: outerRect.minY,
                                                 width: endLength, height: outerRect.height))
            ends.append(NSBezierPath(rect: NSRect(x: outerRect.maxX - endLength, y: outerRect.minY,
                                                  width: endLength, height: outerRect.height)))
            NSGraphicsContext.saveGraphicsState()
            ends.addClip()
            // The tab bar is flipped, so 90 degrees runs from top to bottom.
            gradient.draw(in: outerRect, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
            // Ease from where the ends meet the straight edges to the straight
            // edges' own values over a short distance, as the system does.
            func fill(_ band: NSRect, from endValue: CGFloat, to value: CGFloat) {
                let ramp = min(Self.straightEdgeRampLength, band.width / 2)
                guard band.width > 0, ramp > 0,
                      let gradient = NSGradient(colors: [color(endValue), color(value), color(value), color(endValue)],
                                                atLocations: [0, ramp / band.width, 1 - ramp / band.width, 1],
                                                colorSpace: .displayP3) else {
                    color(value).set()
                    band.fill(using: .sourceOver)
                    return
                }
                gradient.draw(in: band, angle: 0)
            }
            let topEnd = profile.points.first?.value ?? 0
            fill(straightTop, from: topEnd, to: profile.straightTop ?? topEnd)
            fill(straightBottom, from: profile.bottom, to: profile.straightBottom ?? profile.bottom)
        } else {
            gradient.draw(in: outerRect, angle: 90)
        }
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
        
        PSMTabSearchHighlight.highlighting(attributedString, query: tabBar?.searchHighlightQuery).draw(in: labelRect)
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
        if #available(macOS 27, *) {
            // Measured from macOS 27 system window tabs: only the selected
            // title is dark in an active window.
            let value: CGFloat = switch (mainAndActive, selected) {
            case (true, true): 75
            case (true, false): 181
            case (false, true): 182
            case (false, false): 171
            }
            return NSColor(displayP3Red: value / 255.0, green: value / 255.0, blue: value / 255.0, alpha: 1)
        }
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
            if #available(macOS 27, *) {
                // Measured from macOS 27 system tab bars: nearly white when
                // active and a touch darker when inactive. Hovering over the
                // selected tab doesn't change it.
                let level: CGFloat = windowIsMainAndAppIsActive ? 254 : 246
                return NSColor(displayP3Red: level / 255.0, green: level / 255.0, blue: level / 255.0, alpha: 1.0)
            }
            return NSColor(white: 0.97, alpha: 1.0)
        } else {
            if #available(macOS 27, *), highlightAmount > 0 {
                return NSColor(displayP3Red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 220.0 / 255.0, alpha: 1.0)
            }
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
        let rich = drawnRichLines(cell: cell) != nil

        // left margin
        resultWidth = rich ? Self.richHorizontalInset : kSPMTabBarCellInternalXMargin
        
        // close button? A rich tab draws it in its graphic's place, which it
        // has only when there's a graphic or close button.
        if rich {
            let graphicWidth = cell.cachedTitle?.inputs.graphic == nil ? 0 : kPSMTabBarIconWidth
            let closeButtonWidth = cell.hasCloseButton ? (_closeButton?.size.width ?? 0) : 0
            let slotWidth = max(closeButtonWidth, graphicWidth)
            if slotWidth > 0 {
                resultWidth += slotWidth + 4
            }
        } else {
            resultWidth += (_closeButton?.size.width ?? 0) + kPSMTabBarCellPadding
        }
        
        // icon?
        if cell.hasIcon {
            resultWidth += kPSMTabBarIconWidth + kPSMTabBarCellIconPadding
        }
        
        return resultWidth
    }
    
    private func widthOfRightMatterInCell(_ cell: PSMTabBarCell) -> CGFloat {
        var resultWidth: CGFloat = 0
        let rich = drawnRichLines(cell: cell) != nil

        // object counter? A classic tab without one keeps room to balance the
        // close button, since it centers its title. A rich tab doesn't, and
        // takes only the room drawInterior gives its counter: a gap and the
        // text, when there's text to show.
        if rich {
            if cell.count > 0 {
                let width = Self.objectCountSize(attributedObjectCountValue(forTabCell: cell), fontSize: fontSize).width
                if width > 0 {
                    resultWidth += 4 + width
                }
            }
        } else if cell.count > 0 {
            resultWidth += objectCounterRect(forTabCell: cell).size.width + kPSMTabBarCellPadding
        } else if !rich {
            resultWidth += (_closeButton?.size.width ?? 0) + kPSMTabBarCellPadding
        }
        
        // indicator?
        if !cell.indicator.isHidden {
            resultWidth += kPSMTabBarCellPadding + kPSMTabBarIndicatorWidth
        }
        
        // right margin
        resultWidth += rich ? Self.richHorizontalInset : kSPMTabBarCellInternalXMargin
        
        return resultWidth
    }
    
    private func widthOfAttributedStringInCell(_ cell: PSMTabBarCell) -> CGFloat {
        guard let cachedTitle = cell.cachedTitle else { return 0 }
        return ceil(cachedTitle.size.width)
    }
    
    @objc var fontSize: CGFloat {
        if let tabBar,
           let override = tabBar.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
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
        var priority: Int
        var gravity: Gravity
        // Layout asks for this repeatedly and an image's size is slow to get, so get it once.
        let sizingMode: SizingMode
        var draw: (ResolvedLayout) -> ()

        init(name: String,
             image: NSImage,
             priority: Int,
             gravity: Gravity,
             preferredWidth: CGFloat? = nil,
             draw: @escaping (ResolvedLayout) -> ()) {
            self.name = name
            self.priority = priority
            self.gravity = gravity
            sizingMode = .fixed(preferredWidth ?? image.size.width)
            self.draw = draw
        }

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
        // Rich content is a block of left-aligned lines, so it starts at the
        // tab's leading edge, with the icon, counter, and activity indicator
        // at its trailing edge. A classic horizontal tab centers its title
        // and the icons beside it.
        let richLines = drawnRichLines(cell: cell)
        let contentGravity: Gravity = (richLines == nil && orientation == .horizontalOrientation) ? .center : .left
        
        let orientationShift = if orientation == .verticalOrientation {
            1.0
        } else {
            0.0
        }

        // Close button or pin indicator. A rich tab puts its close button in
        // its graphic's place, below.
        if richLines == nil, cell.hasCloseButton, !cell.isPinned, let image = _closeButton {
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
        } else if cell.isPinned, let pinImage = _pinImage, showsPinIndicator(cell: cell) {
            objects.append(FixedSpacerLO(name: "Leading Spacer",
                                         width: richLines == nil ? edgePadding : Self.richHorizontalInset,
                                         priority: Priority.required.rawValue,
                                         gravity: .left))

            let tintColor: NSColor
            let colorKey: UnsafeRawPointer
            if tabColorBrightness(cell) < 0.5 {
                colorKey = PSMTabStyleLightColorKey
                tintColor = NSColor.white
            } else {
                colorKey = PSMTabStyleDarkColorKey
                tintColor = NSColor.black
            }
            let tintedPin = pinImage.it_cachingImage(withTintColor: tintColor, key: colorKey)
            let pinAlpha: CGFloat = windowIsMainAndAppIsActive ? 0.6 : 0.3

            objects.append(GroupLO(name: "Pin Indicator", priority: Priority.required.rawValue, gravity: .left, members: [
                ImageLO(name: "Pin Icon", image: pinImage, priority: Priority.required.rawValue, gravity: .left) { resolved in
                    var pinRect = resolved.frame
                    pinRect.size = pinImage.size
                    // A rich tab puts it on its first line, like its other accessories,
                    // a point lower so the glyph looks centered beside the title.
                    if let minY = self.richAccessoryMinY(cell: cell, height: pinRect.height) {
                        pinRect.origin.y = minY + 1
                    } else {
                        // In a vertical bar the pin is followed by the graphic, so it
                        // is centered like the graphic. A horizontal pinned tab shows
                        // it alone, beside the title's first character.
                        let pinNudge = orientation == .verticalOrientation ? 0.0 : 2.0
                        pinRect.origin.y = cell.frame.minY + floor((cell.frame.height - pinRect.height) / 2.0) + orientationShift + pinNudge
                    }
                    tintedPin.draw(in: pinRect,
                                   from: NSZeroRect,
                                   operation: .sourceOver,
                                   fraction: pinAlpha,
                                   respectFlipped: true,
                                   hints: nil)
                },
                FixedSpacerLO(name: "Post-pin Spacer", width: 4.0, priority: Priority.required.rawValue, gravity: .left)
            ]))
        } else {
            objects.append(FixedSpacerLO(name: "Leading Spacer",
                                         width: richLines == nil ? edgePadding : Self.richHorizontalInset,
                                         priority: Priority.required.rawValue,
                                         gravity: .left))
        }
        
        // Graphic
        if richLines != nil {
            // Rich content starts at the tab's leading edge. Setting aside
            // room for a close button before the graphic would leave the
            // graphic floating away from the edge, so the close button takes
            // the graphic's place when it shows, as in the Minimal style.
            let graphic = cell.cachedTitle?.inputs.graphic
            // A pinned tab has no close button.
            let closeButtonImage = (cell.hasCloseButton && !cell.isPinned) ? _closeButton : nil
            if let slotImage = graphic ?? closeButtonImage {
                let width = max(graphic == nil ? 0 : kPSMTabBarIconWidth, closeButtonImage?.size.width ?? 0)
                let closeButton = tintedCloseButtonImage(cell: cell)
                let closeButtonAlpha = closeButtonImage == nil ? 0 : self.closeButtonAlpha(cell: cell, highlightAmount: highlightAmount)
                // Without a graphic, the slot holds only the close button, which
                // goes first when the tab is too narrow, as it does classically.
                let slotPriority = graphic == nil ? Priority.closeButton : Priority.graphic
                objects.append(GroupLO(name: Name.graphic.rawValue, priority: slotPriority.rawValue, gravity: .left, members: [
                    ImageLO(name: "Graphic or Close Button", image: slotImage, priority: Priority.required.rawValue, gravity: .left, preferredWidth: width) { resolved in
                        if let graphic, closeButtonAlpha < 1 {
                            let rect = NSRect(x: resolved.frame.minX,
                                              y: self.richAccessoryMinY(cell: cell, height: kPSMTabBarIconWidth) ?? cell.frame.minY,
                                              width: kPSMTabBarIconWidth,
                                              height: kPSMTabBarIconWidth)
                            graphic.draw(in: rect,
                                         from: .zero,
                                         operation: .sourceOver,
                                         fraction: 1 - closeButtonAlpha,
                                         respectFlipped: true,
                                         hints: nil)
                        }
                        if closeButtonAlpha > 0, let closeButton {
                            // Where clicks on it land.
                            closeButton.draw(at: self.closeButtonRect(forTabCell: cell).origin,
                                             from: NSZeroRect,
                                             operation: .sourceOver,
                                             fraction: closeButtonAlpha)
                        }
                    },
                    FixedSpacerLO(name: Name.preLabelSpace.rawValue, width: 4.0, priority: Priority.required.rawValue, gravity: .left)
                ]))
            }
        } else if let image = cell.cachedTitle?.inputs.graphic {
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

            objects.append(GroupLO(name: Name.graphic.rawValue, priority: Priority.graphic.rawValue, gravity: contentGravity, members: [
                ImageLO(name: "Graphic", image: image, priority: Priority.required.rawValue, gravity: .left, preferredWidth: kPSMTabBarIconWidth, draw: drawGraphic),
                FixedSpacerLO(name: Name.preLabelSpace.rawValue, width: 2.0, priority: Priority.required.rawValue, gravity: .left)
            ]))
        }
        
        
        // Label and subtitle
        // A pinned tab in a horizontal bar is compact: it skips its title if
        // a graphic icon is present, shows only the title's first character
        // otherwise, and never shows its subtitle. In a vertical bar it is as
        // wide as any other tab, so it shows all of them.
        let compactPinned = isCompactPinned(cell)
        let skipLabel = compactPinned && cell.cachedTitle?.inputs.graphic != nil
        let subtitleWidth = subtitleWidth(cell: cell, orientation: orientation)
        let labelWidth = max(widthOfAttributedStringInCell(cell), subtitleWidth)
        let supportsMultiLineLabels = self.supportsMultiLineLabels
        // Amount to shift text down from vertically centered so that it matches the OS's rendering
        let textShift = self.textShift
        if let richLines {
            // Rich content replaces the title and subtitle.
            let baseFont = NSFont.systemFont(ofSize: fontSize)
            let textColor = textColor(for: cell)
            objects.append(TextLO(name: Name.label.rawValue,
                                  priority: Priority.required.rawValue,
                                  minWidth: 8,
                                  attributedStringWidth: PSMTabRichContentRenderer.preferredWidth(lines: richLines, baseFont: baseFont),
                                  gravity: contentGravity) { resolved in
                // richContentRect shifts down like the classic label, to match
                // the OS's text rendering.
                PSMTabRichContentRenderer.draw(lines: richLines,
                                               in: self.richContentRect(cell: cell,
                                                                        x: resolved.frame.minX,
                                                                        width: resolved.frame.width),
                                               baseFont: baseFont,
                                               textColor: textColor,
                                               secondaryColor: textColor.withAlphaComponent(textColor.alphaComponent * 0.7),
                                               alignment: .left,
                                               colorAppearance: self.richLineColorAppearance(for: cell),
                                               highlight: self.tabBar?.searchHighlightQuery)
            })
        } else if !skipLabel {
            objects.append(TextLO(name: Name.label.rawValue,
                                  priority: Priority.required.rawValue,
                                  minWidth: 8,
                                  attributedStringWidth: labelWidth,
                                  gravity: contentGravity) { resolved in
                let labelOffset: CGFloat
                let mainLabelHeight: CGFloat
                if let cachedTitle = cell.cachedTitle,
                   !cachedTitle.isEmpty {
                    let drawString: NSAttributedString
                    if compactPinned {
                        // For pinned tabs, show only the first character.
                        let title = cachedTitle.inputs.title
                        let firstChar = title.isEmpty ? "" : String(title.prefix(1))
                        let fullString = cachedTitle.attributedStringForcingLeftAlignment(
                            true,
                            truncatedForWidth: resolved.frame.size.width)
                        let attrs = fullString.length > 0 ? fullString.attributes(at: 0, effectiveRange: nil) : [:]
                        drawString = NSAttributedString(string: firstChar, attributes: attrs)
                    } else {
                        drawString = cachedTitle.attributedStringForcingLeftAlignment(
                            orientation == .verticalOrientation,
                            truncatedForWidth: resolved.frame.size.width)
                    }
                    var rect = resolved.frame
                    let boundingSize = cachedTitle.boundingRect(with: NSSize(width: resolved.frame.width, height: cell.frame.height)).size
                    mainLabelHeight = boundingSize.height
                    labelOffset = PSMTahoeTabStyle.willDrawSubtitle(cell.cachedSubtitle) ? PSMTahoeTabStyle.verticalOffsetForTitleWhenSubtitlePresent : 0
                    rect.origin.y = cell.frame.origin.y + floor((cell.frame.size.height - boundingSize.height) / 2.0) + labelOffset + textShift
                    rect.size.height = boundingSize.height
                    PSMTabSearchHighlight.highlighting(drawString, query: self.tabBar?.searchHighlightQuery).draw(in: rect)
                } else {
                    labelOffset = 0
                    mainLabelHeight = 0
                }

                // Draw subtitle (never for compact pinned tabs).
                if supportsMultiLineLabels && !compactPinned {
                    self.drawSubtitle(cell: cell,
                                      orientation: orientation,
                                      xOrigin: resolved.frame.minX,
                                      maxWidth: resolved.frame.width,
                                      labelOffset: labelOffset,
                                      mainLabelHeight: mainLabelHeight)
                }
            })
        }

        // Icon
        if cell.hasIcon, let icon = icon(cell: cell) {
            let iconGravity: Gravity = richLines != nil ? .right : (orientation == .horizontalOrientation ? .center : .left)
            objects.append(GroupLO(name: Name.icon.rawValue, priority: Priority.icon.rawValue, gravity: iconGravity, members: [
                FixedSpacerLO(name: "Pre-Icon Space", width: kPSMTabBarCellIconPadding, priority: Priority.required.rawValue, gravity: .left),
                ImageLO(name: "Icon", image: icon, priority: Priority.required.rawValue, gravity: .left) { resolved in
                    var rect = resolved.frame
                    rect.size.height = kPSMTabBarIconWidth
                    // Vertically center the icon in the cell, then shift down to
                    // match the OS text rendering offset applied to all labels.
                    rect.origin.y = self.richAccessoryMinY(cell: cell, height: kPSMTabBarIconWidth) ??
                        cell.frame.origin.y + floor((cell.frame.size.height - kPSMTabBarIconWidth) / 2) + textShift
                    icon.draw(in: rect,
                              from: NSZeroRect,
                              operation: .sourceOver,
                              fraction: 1.0,
                              respectFlipped: true,
                              hints: nil)
                },
                // A rich tab's icon sits right at its trailing margin, or 4pt
                // before the counter (Pre-Counter Space).
                FixedSpacerLO(name: "Post-Icon Space", width: richLines == nil ? 1.0 : 0, priority: Priority.required.rawValue, gravity: .left),
            ]))
        }
        
        // Counter
        let counterString = attributedObjectCountValue(forTabCell: cell)
        if cell.count > 0 && !counterString.string.isEmpty {
            let counterStringSize = Self.objectCountSize(counterString, fontSize: fontSize)
            let fontSize = self.fontSize
            let gravity: Gravity = (richLines == nil && orientation == .horizontalOrientation) ? .center : .right
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
                        rect.origin.y = self.richAccessoryMinY(cell: cell, height: counterStringSize.height) ??
                            myRect.origin.y + floor((myRect.size.height - counterStringSize.height) / 2.0) + textShift
                        rect.size.height = counterStringSize.height
                        counterString.draw(in: rect)
                    }
                }
            ]))
        }

        if !cell.indicator.isHidden {
            // A rich tab keeps the counter or icon off the indicator.
            objects.append(FixedSpacerLO(name: "Indicator Space",
                                         width: kPSMTabBarIndicatorWidth + (richLines == nil ? 0 : kPSMTabBarCellPadding),
                                         priority: Priority.required.rawValue,
                                         gravity: .right))
        }
        objects.append(FixedSpacerLO(name: "Trailing Spacer",
                                     width: richLines == nil ? edgePadding + 8.0 : Self.richHorizontalInset,
                                     priority: Priority.required.rawValue,
                                     gravity: .right))

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

// The message is an autoclosure so that drawing a tab doesn't pay to describe it.
private func DLog(_ message: @autoclosure () -> String) {
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
        if #available(macOS 27, *) {
            return NSColor(displayP3Red: 64.0 / 255.0, green: 64.0 / 255.0, blue: 64.0 / 255.0, alpha: 1.0)
        }
        return NSColor(displayP3Red: 0.17,
                       green:        0.18,
                       blue:         0.19,
                       alpha:        1.0)
    }

    override func accessoryStrokeColor() -> NSColor {
        return NSColor.darkGray
    }

    override func accessoryTextColor() -> NSColor {
        return NSColor(srgbRed: 0.958, green: 0.958, blue: 0.958, alpha: 1)
    }

    override func backgroundColorSelected(_ selected: Bool, highlightAmount: CGFloat) -> NSColor {
        if selected {
            if #available(macOS 27, *) {
                // Measured from macOS 27 system tab bars, where the selected
                // tab is darker than the bar behind it and darker still when
                // the window is inactive. Hovering over it doesn't change it.
                let level: CGFloat = windowIsMainAndAppIsActive ? 50 : 45
                return NSColor(displayP3Red: level / 255.0, green: level / 255.0, blue: level / 255.0, alpha: 1.0)
            }
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
            if #available(macOS 27, *), highlightAmount > 0 {
                return NSColor(displayP3Red: 75.0 / 255.0, green: 75.0 / 255.0, blue: 75.0 / 255.0, alpha: 1.0)
            }
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
        if #available(macOS 27, *) {
            // Measured from macOS 27 system window tabs: only the selected
            // title is bright in an active window.
            let value: CGFloat = switch (mainAndActive, selected) {
            case (true, true): 235
            case (true, false): 105
            case (false, true): 98
            case (false, false): 113
            }
            return NSColor(displayP3Red: value / 255.0, green: value / 255.0, blue: value / 255.0, alpha: 1)
        }
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
    
    override func drawCellOutline(path: NSBezierPath, rect: NSRect) {
        if #available(macOS 27, *) {
            // These cap images are opaque and would hide the darker fill, so
            // macOS 27 uses the base class's edge instead: the measured image
            // for a standard-height tab, or modernEdge in code otherwise.
            super.drawCellOutline(path: path, rect: rect)
            return
        }
        // Cap images must scale to the pill height so chrome matches the cell
        // when Default tab bar height changes (left/right tabs). A pill whose
        // corners are capped (see maximumCornerRadius) is a rounded rectangle:
        // the images scale to the height of a pill with that radius, and
        // their middles stretch to fill the rest.
        let left = Self.leftTabCap
        let scaledHeight = min(rect.height, pillCornerRadius(for: rect) * 2)
        let scale = left.size.height > 0 ? scaledHeight / left.size.height : 1.0
        // Clamp so left and right caps never overlap on a narrow tall pill.
        let capWidth = min(left.size.width * scale, rect.width / 2.0)

        // The three images (leftCap | mid | rightCap) tile to fill the pill. Their
        // inner seams fall at rect.minX + capWidth and rect.maxX - capWidth, which
        // are fractional (capWidth scales with height, and rect.minX moves with
        // layout/scroll). A seam on a fractional device pixel makes both abutting
        // image edges antialias against transparency, leaving a faint ~0.5pt
        // vertical line inside the pill. Snap the seams to the backing-store pixel
        // grid so the tiles meet on a whole pixel. The outer rounded cap edges are
        // left as-is; their curves antialiasing over the bar background is correct.
        let backing = tabBar?.window?.backingScaleFactor ?? 2.0
        let snap: (CGFloat) -> CGFloat = { backing > 0 ? ($0 * backing).rounded() / backing : $0 }
        let leftSeam = snap(rect.minX + capWidth)
        let rightSeam = max(leftSeam, snap(rect.maxX - capWidth))

        Self.draw(left,
                  in: NSRect(x: rect.minX, y: rect.minY,
                             width: leftSeam - rect.minX, height: rect.height),
                  scaledHeight: scaledHeight)

        Self.draw(Self.rightTabCap,
                  in: NSRect(x: rightSeam, y: rect.minY,
                             width: rect.maxX - rightSeam, height: rect.height),
                  scaledHeight: scaledHeight)

        Self.draw(Self.tabMid,
                  in: NSRect(x: leftSeam, y: rect.minY,
                             width: max(0, rightSeam - leftSeam), height: rect.height),
                  scaledHeight: scaledHeight)
    }

    override var selectedTabEdgeImageStrip: PSMTahoeSelectedTabEdgeStrip? {
        return windowIsMainAndAppIsActive ? .darkActive : .darkInactive
    }

    override var modernEdge: ModernEdge {
        if windowIsMainAndAppIsActive {
            // Glass: a bright line along the top and bottom. Around each
            // rounded end it becomes a dark line, with a highlight just inside
            // it that fades toward the vertical end. A glow fades in from both
            // edges.
            return ModernEdge(outer: .init(points: [(1, 76), (0.96, 85), (0.93, 62), (0.8, 60), (0.6, 58),
                                                    (0.4, 57), (0.2, 56), (0, 56)],
                                           bottom: 76,
                                           straightTop: 113,
                                           straightBottom: 112),
                              innerHighlight: .init(points: [(1, 0.16), (0.96, 0.25), (0.9, 0.12), (0.85, 0.13), (0.77, 0.13), (0.68, 0.12),
                                                             (0.6, 0.09), (0.51, 0.075), (0.43, 0.065), (0.3, 0.05),
                                                             (0.17, 0.025), (0, 0.01)],
                                                    bottom: 0.16,
                                                    straightTop: 0.124,
                                                    straightBottom: 0.114),
                              glow: [(0.04, 0.059), (0.06, 0.044), (0.08, 0.034), (0.1, 0.025), (0.125, 0.02),
                                     (0.15, 0.015), (0.19, 0.01), (0.23, 0.005), (0.29, 0)])
        }
        // An inactive window's tab has no outline at all.
        return ModernEdge()
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
        if #available(macOS 27, *) {
            return NSColor(displayP3Red: 87.0 / 255.0, green: 87.0 / 255.0, blue: 87.0 / 255.0, alpha: 1.0)
        }
        return NSColor(displayP3Red: 38.0 / 255.0, green: 38.0 / 255.0, blue: 38.0 / 255.0, alpha: 1.0)
    }

    override func useLightControls() -> Bool {
        return true
    }

    override var trackRimColor: NSColor? {
        return NSColor(displayP3Red: 79.0 / 255.0, green: 79.0 / 255.0, blue: 79.0 / 255.0, alpha: 1.0)
    }

    override var trackRimEndColor: NSColor? {
        return NSColor(displayP3Red: 75.0 / 255.0, green: 75.0 / 255.0, blue: 75.0 / 255.0, alpha: 1.0)
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
            if #available(macOS 27, *) {
                // macOS 27 draws the selected tab darker than the bar behind
                // it. This bar is nearly black already, so the tab is black
                // and lightens a little on hover.
                if highlightAmount > 0 {
                    return NSColor(displayP3Red: 10.0 / 255.0,
                                   green:        12.0 / 255.0,
                                   blue:         13.0 / 255.0,
                                   alpha:        1.0)
                }
                return NSColor.black
            }
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

    // A dark edge would vanish against the black tab, so this edge is light
    // all the way around, keeping the brighter top and bottom of the glass.
    // High contrast wasn't measured, so it keeps the outline drawn in code.
    override var selectedTabEdgeImageStrip: PSMTahoeSelectedTabEdgeStrip? {
        return nil
    }

    override var modernEdge: ModernEdge {
        if windowIsMainAndAppIsActive {
            return ModernEdge(outer: .init(points: [(1, 180), (0.87, 140), (0.71, 125), (0.5, 110), (0, 90)],
                                           bottom: 175),
                              innerHighlight: .init(points: [(1, 0.3), (0.87, 0.22), (0.71, 0.16), (0.5, 0.09), (0, 0)],
                                                    bottom: 0.27),
                              glow: [(0.04, 0.09), (0.29, 0)])
        }
        return ModernEdge(outer: .init(points: [(1, 120), (0.87, 105), (0.71, 100), (0.5, 90), (0, 75)],
                                       bottom: 120))
    }

    override func textColor(for cell: PSMTabBarCell) -> NSColor {
        if anyTabHasColor() {
            return super.textColor(for: cell)
        } else {
            return NSColor.white
        }
    }
    override var fontSize: CGFloat {
        if let tabBar,
           let override = tabBar.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
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

    // High contrast wasn't measured, so it keeps the outline drawn in code.
    override var selectedTabEdgeImageStrip: PSMTahoeSelectedTabEdgeStrip? {
        return nil
    }

    override var modernEdge: ModernEdge {
        if windowIsMainAndAppIsActive {
            return ModernEdge(outer: .init(points: [(1, 150), (0.87, 155), (0.71, 150), (0.5, 140), (0, 110)],
                                           bottom: 145))
        }
        return ModernEdge(outer: .init(points: [(1, 140), (0.87, 148), (0.71, 150), (0.5, 142), (0, 120)],
                                       bottom: 140))
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
        if let tabBar,
           let override = tabBar.delegate?.tabView?(tabBar, valueOfOption: PSMTabBarControlOptionKey.fontSizeOverride) as? NSNumber {
            return CGFloat(override.doubleValue)
        }
        return 13.0
    }
}

/// The parts of TahoeSelectedTabEdges, top to bottom, one per look of a
/// selected tab.
@available(macOS 26, *)
enum PSMTahoeSelectedTabEdgeStrip: Int {
    case darkActive
    case darkInactive
    case lightActive
    case lightInactive

    /// The height of the tab each part was measured from.
    static let pillHeight = CGFloat(24)
}

/// The shape of one rounded end of a macOS 27 stadium (the tab bar's container
/// or a selected tab), fitted to the system's own window tab bar. Neither is a
/// semicircle: each runs close to the straight edge for a long way before
/// meeting it.
@available(macOS 26, *)
struct PSMTahoeStadiumEnd {
    /// Each knot is (height, inset): at `height` (0 at the end's middle, 1 at
    /// the straight top or bottom edge) the edge is `inset` in from the end's
    /// outermost point. Both are in units of half the stadium's height.
    let knots: [(height: CGFloat, inset: CGFloat)]
    private let tangents: [CGFloat]

    static let selectedTab = PSMTahoeStadiumEnd(knots: [
        (0, 0.0000), (0.2, 0.0223), (0.35, 0.0690), (0.5, 0.1371), (0.62, 0.2211),
        (0.72, 0.3093), (0.8, 0.4101), (0.87, 0.5188), (0.895, 0.5754), (0.92, 0.6337),
        (0.94, 0.7163), (0.96, 0.7862), (0.98, 0.9853), (1.0, 1.2876)
    ])

    static let bar = PSMTahoeStadiumEnd(knots: [
        (0, 0.0000), (0.2, 0.0252), (0.35, 0.0683), (0.5, 0.1390), (0.62, 0.2254),
        (0.72, 0.3060), (0.8, 0.4100), (0.87, 0.5169), (0.92, 0.6381), (0.96, 0.8000),
        (0.985, 0.9124), (0.992, 0.9138), (0.997, 0.9626), (1.0, 1.2600)
    ])

    init(knots: [(height: CGFloat, inset: CGFloat)]) {
        self.knots = knots
        // Tangents for a monotone cubic through the knots (Fritsch-Carlson),
        // so the end never bulges past them.
        let count = knots.count
        let slopes = (0..<(count - 1)).map { i in
            (knots[i + 1].inset - knots[i].inset) / (knots[i + 1].height - knots[i].height)
        }
        var tangents = [CGFloat](repeating: 0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]
        for i in 1..<(count - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
        }
        for i in 0..<(count - 1) where slopes[i] != 0 {
            let a = tangents[i] / slopes[i]
            let b = tangents[i + 1] / slopes[i]
            let sum = a * a + b * b
            if sum > 9 {
                let scale = 3 / sum.squareRoot()
                tangents[i] = scale * a * slopes[i]
                tangents[i + 1] = scale * b * slopes[i]
            }
        }
        self.tangents = tangents
    }

    /// How far the end reaches in from its outermost point, in units of half
    /// the stadium's height.
    var length: CGFloat { knots.last!.inset }

    /// The end's inset at `height`, interpolated between the knots.
    func inset(at height: CGFloat) -> CGFloat {
        let h = min(max(height, 0), 1)
        var i = 0
        while i < knots.count - 2 && h > knots[i + 1].height {
            i += 1
        }
        let span = knots[i + 1].height - knots[i].height
        let u = (h - knots[i].height) / span
        let u2 = u * u
        let u3 = u2 * u
        return (2 * u3 - 3 * u2 + 1) * knots[i].inset
            + (u3 - 2 * u2 + u) * span * tangents[i]
            + (-2 * u3 + 3 * u2) * knots[i + 1].inset
            + (u3 - u2) * span * tangents[i + 1]
    }

    /// A stadium with these ends filling `rect`. A rect too narrow for both
    /// full ends gets proportionally smaller ones.
    func path(in rect: NSRect) -> NSBezierPath {
        let halfHeight = rect.height / 2
        let scale = min(halfHeight, rect.width / 2 / length)
        let endLength = length * scale
        let steps = 96
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + endLength, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - endLength, y: rect.minY))
        // Down the right end, from the top edge to the bottom edge.
        for i in 0...steps {
            let y = -1 + 2 * CGFloat(i) / CGFloat(steps)
            path.line(to: NSPoint(x: rect.maxX - inset(at: abs(y)) * scale,
                                  y: rect.midY + y * halfHeight))
        }
        path.line(to: NSPoint(x: rect.minX + endLength, y: rect.maxY))
        // Up the left end.
        for i in 0...steps {
            let y = 1 - 2 * CGFloat(i) / CGFloat(steps)
            path.line(to: NSPoint(x: rect.minX + inset(at: abs(y)) * scale,
                                  y: rect.midY + y * halfHeight))
        }
        path.close()
        return path
    }
}

#endif
