//
//  PSMTabRichAccessoryPlacementTests.swift
//  ModernTests
//
//  A tab with rich content lines is taller than a classic tab. Its tab
//  icon, status dot (or other attention icon), and activity indicator line up
//  with its first line instead of floating halfway down the tab. Without rich
//  content they stay vertically centered, as they always were.
//

import XCTest
@testable import iTerm2SharedARC

private final class FakeAccessoryTab: NSObject, PSMTabBarControlRepresentedObjectIdentifierProtocol {
    var lines: [PSMTabRichLine]?
    var graphic: NSImage?
    var statusIcon: NSImage?

    init(lines: [PSMTabRichLine]?, graphic: NSImage?, statusIcon: NSImage?) {
        self.lines = lines
        self.graphic = graphic
        self.statusIcon = statusIcon
    }

    func psmTabRichLines() -> [PSMTabRichLine]? {
        return lines
    }

    func psmTabGraphic() -> NSImage? {
        return graphic
    }

    func icon() -> NSImage? {
        return statusIcon
    }

    func setIcon(_ icon: NSImage?) {
        statusIcon = icon
    }
}

final class PSMTabRichAccessoryPlacementTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var items = [NSTabViewItem]()
    private let cellFrame = NSRect(x: 0, y: 0, width: 300, height: 60)

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isReleasedWhenClosed = false
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        window.contentView?.addSubview(control)
    }

    override func tearDown() {
        control.removeFromSuperview()
        window.close()
        control = nil
        window = nil
        items = []
        super.tearDown()
    }

    enum CloseButton {
        case none
        // Shown only while the mouse is over the tab. It isn't in these tests.
        case onHover
        case always
    }

    private func line(_ text: String, scale: CGFloat = 1) -> PSMTabRichLine {
        return PSMTabRichLine(text: text,
                              scale: scale,
                              bold: false,
                              italic: false,
                              color: nil,
                              secondary: false,
                              lineBreakMode: .byTruncatingTail,
                              collapsesWhenEmpty: true)
    }

    private var richLines: [PSMTabRichLine] {
        return [line("title"), line("/some/path", scale: 0.85), line("claude Working", scale: 0.85)]
    }

    private var baseFont: NSFont {
        return NSFont.systemFont(ofSize: 11)
    }

    // The first line's vertical center in the whole cell, which is where the
    // accessories belong.
    private var titleLineMidY: CGFloat {
        return PSMTabRichContentRenderer.firstLineMidY(lines: richLines, in: cellFrame, baseFont: baseFont)
    }

    // Tahoe centers the lines in its background, which is inset from the
    // cell, and draws text lower than centered to match the system's
    // rendering, by 1pt in a horizontal bar and 2pt in a vertical one. It
    // lines its accessories up with that text.
    private func tahoeTitleLineMidY(_ orientation: PSMTabBarOrientation) -> CGFloat {
        guard #available(macOS 26, *) else {
            return titleLineMidY
        }
        let shift: CGFloat = orientation == .verticalOrientation ? 2 : 1
        let background = PSMTahoeTabStyle().backgroundRect(for: cellFrame)
        let rect = NSRect(x: background.minX,
                          y: background.minY + shift,
                          width: background.width,
                          height: background.height - shift)
        return PSMTabRichContentRenderer.firstLineMidY(lines: richLines, in: rect, baseFont: baseFont)
    }

    private func solidImage(_ color: NSColor) -> NSImage {
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private func makeCell(style: PSMTabStyle,
                          orientation: PSMTabBarOrientation,
                          rich: Bool,
                          graphic: NSImage? = nil,
                          statusIcon: NSImage? = nil,
                          closeButton: CloseButton = .none,
                          count: Int32 = 0) -> PSMTabBarCell {
        control.style = style
        control.orientation = orientation
        style.orientation = orientation
        let tab = FakeAccessoryTab(lines: rich ? richLines : nil, graphic: graphic, statusIcon: statusIcon)
        let item = NSTabViewItem(identifier: tab)
        item.label = "title"
        items.append(item)
        let cell = PSMTabBarCell(controlView: control)!
        cell.representedObject = item
        cell.stringValue = "title"
        // A cell showing its activity indicator reports having no icon.
        cell.indicator.isHidden = true
        // Yosemite fades the graphic out where a visible close button goes.
        cell.hasCloseButton = closeButton != .none
        cell.isCloseButtonSuppressed = closeButton == .onHover
        cell.count = count
        cell.hasIcon = statusIcon != nil
        cell.frame = cellFrame
        control.cells().setArray([cell])
        return cell
    }

    // MARK: - The renderer

    func testFirstLineMidYIsTheMiddleOfTheFirstLine() {
        let rects = PSMTabRichContentRenderer.layout(lines: richLines, in: cellFrame, baseFont: baseFont)
        XCTAssertEqual(titleLineMidY, rects[0].midY)
        XCTAssertLessThan(titleLineMidY, cellFrame.midY - 5, "precondition: the first line is well above the middle")
    }

    // When the first line is empty and collapses, the next line moves up to
    // the same top. The accessories stay close to its middle, and don't move,
    // so an indicator view positioned earlier doesn't go stale.
    func testFirstLineMidYStaysNearTheTopLineWhenTheFirstCollapses() {
        var lines = richLines
        lines[0] = line("")
        let midY = PSMTabRichContentRenderer.firstLineMidY(lines: lines, in: cellFrame, baseFont: baseFont)
        XCTAssertEqual(midY, titleLineMidY, "doesn't depend on what the lines say")
        let rects = PSMTabRichContentRenderer.layout(lines: lines, in: cellFrame, baseFont: baseFont)
        XCTAssertEqual(rects[0], .zero, "precondition: the first line collapsed")
        XCTAssertEqual(midY, rects[1].midY, accuracy: 1.5, "near the line that moved up")
    }

    // A first line that wraps puts the accessories on its first row.
    func testFirstLineMidYUsesTheFirstRowOfAWrappingLine() {
        let wrapping = PSMTabRichLine(text: "a long title",
                                      scale: 1,
                                      bold: false,
                                      italic: false,
                                      color: nil,
                                      secondary: false,
                                      lineBreakMode: .byTruncatingTail,
                                      collapsesWhenEmpty: false,
                                      maximumLines: 3)
        let lines = [wrapping, line("/some/path", scale: 0.85)]
        let rects = PSMTabRichContentRenderer.layout(lines: lines, in: cellFrame, baseFont: baseFont)
        let rowHeight = rects[0].height / 3
        XCTAssertEqual(PSMTabRichContentRenderer.firstLineMidY(lines: lines, in: cellFrame, baseFont: baseFont),
                       rects[0].minY + rowHeight / 2)
    }

    func testFirstLineMidYWithNoLinesIsTheMiddle() {
        XCTAssertEqual(PSMTabRichContentRenderer.firstLineMidY(lines: [], in: cellFrame, baseFont: baseFont),
                       cellFrame.midY)
    }

    // MARK: - Rects the styles report

    private func assertOnTitleLine(_ rect: NSRect, expected: CGFloat? = nil, _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.midY, expected ?? titleLineMidY, accuracy: 1, message, file: file, line: line)
    }

    private func assertCentered(_ rect: NSRect, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.midY, cellFrame.midY, accuracy: 1.5, message, file: file, line: line)
    }

    func testYosemiteIconAndIndicatorRectsFollowTheTitleLine() {
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMYosemiteTabStyle()
            let cell = makeCell(style: style, orientation: orientation, rich: true, statusIcon: solidImage(.blue))
            assertOnTitleLine(style.iconRect(forTabCell: cell), "icon, orientation \(orientation.rawValue)")
            assertOnTitleLine(style.indicatorRect(forTabCell: cell), "indicator, orientation \(orientation.rawValue)")
        }
    }

    func testYosemiteIconAndIndicatorRectsStayCenteredWithoutRichContent() {
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMYosemiteTabStyle()
            let cell = makeCell(style: style, orientation: orientation, rich: false, statusIcon: solidImage(.blue))
            assertCentered(style.iconRect(forTabCell: cell), "icon, orientation \(orientation.rawValue)")
            assertCentered(style.indicatorRect(forTabCell: cell), "indicator, orientation \(orientation.rawValue)")
        }
    }

    // Tahoe draws text a point or two lower than centered to match the
    // system's rendering, and its accessories move with the text.
    func testTahoeIndicatorRectFollowsTheTitleLine() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMTahoeTabStyle()
            let cell = makeCell(style: style, orientation: orientation, rich: true)
            assertOnTitleLine(style.indicatorRect(forTabCell: cell), expected: tahoeTitleLineMidY(orientation),
                              "orientation \(orientation.rawValue)")
        }
    }

    // A pinned tab doesn't draw its rich content, so its accessories stay
    // centered.
    func testYosemitePinnedTabsKeepAccessoriesCentered() {
        let yosemite = PSMYosemiteTabStyle()
        let yosemiteCell = makeCell(style: yosemite, orientation: .verticalOrientation, rich: true, statusIcon: solidImage(.blue))
        yosemiteCell.isPinned = true
        assertCentered(yosemite.iconRect(forTabCell: yosemiteCell), "Yosemite icon")
        assertCentered(yosemite.indicatorRect(forTabCell: yosemiteCell), "Yosemite indicator")
    }

    func testTahoePinnedTabsKeepAccessoriesCentered() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let tahoe = PSMTahoeTabStyle()
        let tahoeCell = makeCell(style: tahoe, orientation: .verticalOrientation, rich: true)
        tahoeCell.isPinned = true
        assertCentered(tahoe.indicatorRect(forTabCell: tahoeCell), "Tahoe indicator")
    }

    func testTahoeIndicatorRectStaysCenteredWithoutRichContent() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMTahoeTabStyle()
            let cell = makeCell(style: style, orientation: orientation, rich: false)
            assertCentered(style.indicatorRect(forTabCell: cell), "orientation \(orientation.rawValue)")
        }
    }

    // The activity indicator is a view, so redrawing the cell doesn't move
    // it. When a tab gains rich content (as when the setting is turned on),
    // the tab bar must move it to the title line without waiting for its next
    // full layout.
    func testIndicatorMovesWhenTheTabGainsRichContent() throws {
        let style = PSMYosemiteTabStyle()
        let cell = makeCell(style: style, orientation: .verticalOrientation, rich: false)
        let indicator = try XCTUnwrap(cell.indicator)
        indicator.isHidden = false
        indicator.frame = style.indicatorRect(forTabCell: cell)
        control.addSubview(indicator)
        assertCentered(indicator.frame, "precondition: laid out without rich content")

        let tab = try XCTUnwrap((cell.representedObject as? NSTabViewItem)?.identifier as? FakeAccessoryTab)
        tab.lines = richLines
        control.richContentDidChangeForTab(withIdentifier: tab)

        assertOnTitleLine(indicator.frame, "indicator view")
    }

    // A rich Tahoe tab's close button is on its first line, so when the tab
    // gains rich content the area that highlights the button on hover must
    // move there too.
    func testCloseButtonHoverAreaMovesWhenTheTabGainsRichContent() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        let cell = makeCell(style: style, orientation: .horizontalOrientation, rich: false, closeButton: .onHover)
        let classicRect = style.closeButtonRect(forTabCell: cell)
        cell.setCloseButtonTrackingRect(classicRect, userData: nil, assumeInside: false, view: control)

        let tab = try XCTUnwrap((cell.representedObject as? NSTabViewItem)?.identifier as? FakeAccessoryTab)
        tab.lines = richLines
        control.richContentDidChangeForTab(withIdentifier: tab)

        let richRect = style.closeButtonRect(forTabCell: cell)
        XCTAssertNotEqual(richRect, classicRect, "precondition: the button moved")
        let rects = control.trackingAreas.filter { ($0.owner as AnyObject?) === cell }.map(\.rect)
        XCTAssertEqual(rects, [richRect])
    }

    // Moving the close button's hover area doesn't generate mouse entered or
    // exited events, so the highlight follows where the mouse is.
    func testMovingTheCloseButtonHoverAreaUpdatesTheHighlight() {
        let cell = makeCell(style: PSMYosemiteTabStyle(), orientation: .horizontalOrientation, rich: false, closeButton: .onHover)
        let old = NSRect(x: 6, y: 20, width: 16, height: 16)
        let new = NSRect(x: 6, y: 8, width: 16, height: 16)
        cell.setCloseButtonTrackingRect(old, userData: nil, assumeInside: false, view: control)

        cell.closeButtonOver = true
        cell.moveCloseButtonTrackingRect(to: new, in: control, mouseLocation: NSPoint(x: 10, y: 30))
        XCTAssertFalse(cell.closeButtonOver, "the mouse was over the old place, not the new one")

        cell.moveCloseButtonTrackingRect(to: old, in: control, mouseLocation: NSPoint(x: 10, y: 30))
        XCTAssertTrue(cell.closeButtonOver, "the button moved under the mouse")
    }

    // A cell without a hover area, such as a background tab that can't be
    // closed, doesn't get one.
    func testMovingDoesNotAddAHoverArea() {
        let cell = makeCell(style: PSMYosemiteTabStyle(), orientation: .horizontalOrientation, rich: false, closeButton: .onHover)
        cell.moveCloseButtonTrackingRect(to: NSRect(x: 6, y: 8, width: 16, height: 16), in: control, mouseLocation: .zero)
        XCTAssertTrue(control.trackingAreas.filter { ($0.owner as AnyObject?) === cell }.isEmpty)
        XCTAssertFalse(cell.closeButtonOver)
    }

    // MARK: - Where the styles draw

    // Draws the cell into a flipped 1x bitmap whose pixels match the cell's
    // coordinates, and returns the bounds of the pixels that are nearly pure
    // color, or nil if there are none.
    private func drawnBounds(of cell: PSMTabBarCell,
                             inColumns columns: ClosedRange<Int>? = nil,
                             matching isColor: (NSColor) -> Bool) -> NSRect? {
        let rep = render(cell)
        var bounds: NSRect?
        for y in 0..<rep.pixelsHigh {
            for x in columns ?? 0...(rep.pixelsWide - 1) {
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), isColor(color) {
                    let pixel = NSRect(x: x, y: y, width: 1, height: 1)
                    bounds = bounds.map { $0.union(pixel) } ?? pixel
                }
            }
        }
        return bounds
    }

    // The bounds of the pixels that differ between two renders.
    private func differingBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> NSRect? {
        var bounds: NSRect?
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide where a.colorAt(x: x, y: y) != b.colorAt(x: x, y: y) {
                let pixel = NSRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    private func render(_ cell: PSMTabBarCell) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(cellFrame.width),
                                   pixelsHigh: Int(cellFrame.height),
                                   bitsPerSample: 8,
                                   samplesPerPixel: 4,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let bitmapContext = NSGraphicsContext(bitmapImageRep: rep)!
        let cg = bitmapContext.cgContext
        cg.translateBy(x: 0, y: cellFrame.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        cell.draw(withFrame: cell.frame, in: control)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func drawnMidY(of cell: PSMTabBarCell, matching isColor: (NSColor) -> Bool) -> CGFloat? {
        return drawnBounds(of: cell, matching: isColor)?.midY
    }

    private func isRed(_ color: NSColor) -> Bool {
        return color.redComponent > 0.9 && color.greenComponent < 0.15 && color.blueComponent < 0.15 && color.alphaComponent > 0.9
    }

    private func isBlue(_ color: NSColor) -> Bool {
        return color.blueComponent > 0.9 && color.redComponent < 0.15 && color.greenComponent < 0.15 && color.alphaComponent > 0.9
    }

    private func checkDrawing(style: () -> PSMTabStyle,
                              titleLineMidY: (PSMTabBarOrientation) -> CGFloat,
                              tolerance: CGFloat) throws {
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let rich = makeCell(style: style(),
                                orientation: orientation,
                                rich: true,
                                graphic: solidImage(.red),
                                statusIcon: solidImage(.blue))
            let graphicY = try XCTUnwrap(drawnMidY(of: rich, matching: isRed), "graphic, orientation \(orientation.rawValue)")
            let iconY = try XCTUnwrap(drawnMidY(of: rich, matching: isBlue), "icon, orientation \(orientation.rawValue)")
            XCTAssertEqual(graphicY, titleLineMidY(orientation), accuracy: tolerance, "graphic, orientation \(orientation.rawValue)")
            XCTAssertEqual(iconY, titleLineMidY(orientation), accuracy: tolerance, "icon, orientation \(orientation.rawValue)")

            let classic = makeCell(style: style(),
                                   orientation: orientation,
                                   rich: false,
                                   graphic: solidImage(.red),
                                   statusIcon: solidImage(.blue))
            let classicGraphicY = try XCTUnwrap(drawnMidY(of: classic, matching: isRed))
            let classicIconY = try XCTUnwrap(drawnMidY(of: classic, matching: isBlue))
            XCTAssertEqual(classicGraphicY, cellFrame.midY, accuracy: 2.5, "classic graphic, orientation \(orientation.rawValue)")
            XCTAssertEqual(classicIconY, cellFrame.midY, accuracy: 2.5, "classic icon, orientation \(orientation.rawValue)")
        }
    }

    // Rich content is a left-aligned block of lines, so a Tahoe tab starts it
    // at its leading edge rather than centering it, and puts the attention
    // icon at its trailing edge.
    func testTahoeRichContentIsLeftAlignedWithTheIconOnTheRight() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let cell = makeCell(style: PSMTahoeTabStyle(),
                                orientation: orientation,
                                rich: true,
                                graphic: solidImage(.red),
                                statusIcon: solidImage(.blue))
            let graphic = try XCTUnwrap(drawnBounds(of: cell, matching: isRed), "graphic, orientation \(orientation.rawValue)")
            let icon = try XCTUnwrap(drawnBounds(of: cell, matching: isBlue), "icon, orientation \(orientation.rawValue)")
            XCTAssertLessThan(graphic.minX, cellFrame.minX + 30, "graphic, orientation \(orientation.rawValue)")
            XCTAssertGreaterThan(icon.maxX, cellFrame.maxX - 40, "icon, orientation \(orientation.rawValue)")
        }
    }

    // A Tahoe rich tab doesn't set aside room for a close button before its
    // icon, which would leave the icon floating away from the tab's edge.
    // The close button takes the icon's place instead, as in the Minimal
    // style.
    func testTahoeRichIconSitsAtTheLeadingEdge() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let cell = makeCell(style: PSMTahoeTabStyle(),
                                orientation: orientation,
                                rich: true,
                                graphic: solidImage(.red),
                                closeButton: .onHover)
            let graphic = try XCTUnwrap(drawnBounds(of: cell, matching: isRed), "orientation \(orientation.rawValue)")
            XCTAssertLessThan(graphic.minX, cellFrame.minX + 12, "orientation \(orientation.rawValue)")
        }
    }

    func testTahoeRichCloseButtonReplacesTheIcon() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMTahoeTabStyle()
            let cell = makeCell(style: style,
                                orientation: orientation,
                                rich: true,
                                graphic: solidImage(.red),
                                closeButton: .always)
            // The test window isn't key, so the button shows at half strength
            // and the graphic fades to half; it's never drawn at full strength.
            XCTAssertNil(drawnBounds(of: cell, matching: isRed), "orientation \(orientation.rawValue)")
            // The rect clicks and hovering use, which the button is drawn at,
            // is in the icon's place on the first line.
            let closeRect = style.closeButtonRect(forTabCell: cell)
            XCTAssertLessThan(closeRect.minX, cellFrame.minX + 12, "orientation \(orientation.rawValue)")
            assertOnTitleLine(closeRect, expected: tahoeTitleLineMidY(orientation), "orientation \(orientation.rawValue)")
        }
    }

    // The shortcut (the object counter) lines up with the title, like the
    // status dot beside it.
    func testTahoeRichShortcutIsOnTheTitleLine() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let cell = makeCell(style: PSMTahoeTabStyle(),
                            orientation: .horizontalOrientation,
                            rich: true,
                            count: 4)
        // The shortcut is drawn only with a modifier, so the difference
        // between the two is the shortcut.
        let without = render(cell)
        cell.modifierString = "⌘"
        let shortcut = try XCTUnwrap(differingBounds(without, render(cell)))
        XCTAssertGreaterThan(shortcut.minX, cellFrame.midX, "precondition: at the trailing edge")
        XCTAssertEqual(shortcut.midY, tahoeTitleLineMidY(.horizontalOrientation), accuracy: 2)
    }

    // A rich Tahoe tab has the same margin on both sides, clear of its
    // rounded corners.
    func testTahoeRichTabHasEqualSideMargins() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMTahoeTabStyle()
            let cell = makeCell(style: style,
                                orientation: orientation,
                                rich: true,
                                graphic: solidImage(.red),
                                statusIcon: solidImage(.blue),
                                closeButton: .onHover)
            let graphic = try XCTUnwrap(drawnBounds(of: cell, matching: isRed))
            let icon = try XCTUnwrap(drawnBounds(of: cell, matching: isBlue))
            let leading = graphic.minX - cellFrame.minX
            let trailing = cellFrame.maxX - icon.maxX
            XCTAssertEqual(leading, 10, accuracy: 0.5, "orientation \(orientation.rawValue)")
            XCTAssertEqual(trailing, leading, accuracy: 0.5, "orientation \(orientation.rawValue)")
            XCTAssertEqual(style.closeButtonRect(forTabCell: cell).minX, graphic.minX, accuracy: 0.5,
                           "the close button replaces the graphic, orientation \(orientation.rawValue)")
            XCTAssertEqual(cellFrame.maxX - style.indicatorRect(forTabCell: cell).maxX, trailing, accuracy: 0.5,
                           "the activity indicator, orientation \(orientation.rawValue)")
        }
    }

    // A tab sized to fit its content is only as wide as its lines plus the
    // margins, when there's no graphic or close button to make room for.
    func testTahoeRichFittedWidthHasNoRoomForAMissingSlot() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        let cell = makeCell(style: style, orientation: .horizontalOrientation, rich: true)
        let lines = PSMTabRichContentRenderer.preferredWidth(lines: richLines,
                                                             baseFont: NSFont.systemFont(ofSize: style.fontSize))
        XCTAssertEqual(CGFloat(style.desiredWidth(ofTabCell: cell)), ceil(lines + 20))
    }

    // The shortcut takes only the width of its text plus a gap. A tab with a
    // count but no shortcut to show (no modifier) leaves no room for one.
    func testTahoeRichFittedWidthFitsTheShortcut() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        let lines = PSMTabRichContentRenderer.preferredWidth(lines: richLines,
                                                             baseFont: NSFont.systemFont(ofSize: style.fontSize))
        let cell = makeCell(style: style, orientation: .horizontalOrientation, rich: true, count: 4)
        XCTAssertEqual(CGFloat(style.desiredWidth(ofTabCell: cell)), ceil(lines + 20), "no shortcut shown")
        cell.modifierString = "⌘"
        let shortcut = style.attributedObjectCountValue(forTabCell: cell).size().width
        XCTAssertGreaterThan(shortcut, 0, "precondition")
        XCTAssertEqual(CGFloat(style.desiredWidth(ofTabCell: cell)), ceil(lines + 20 + 4 + shortcut))
    }

    // A Tahoe tab draws its rounded background inset from the cell, so it
    // asks for that much more height, and centers the lines in the
    // background rather than the cell. The lines get room above and below.
    func testTahoeRichLinesHaveRoomInsideTheBackground() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let style = PSMTahoeTabStyle()
            style.orientation = orientation
            XCTAssertGreaterThan(style.richContentChromeHeight, 0)
            let layout = TabContentLayout.defaultLayout
            let height = TabContentSettings.requiredHeight(layout: layout, baseFontSize: style.fontSize) + style.richContentChromeHeight
            let cell = makeCell(style: style, orientation: orientation, rich: true)
            cell.frame = NSRect(x: 0, y: 0, width: 300, height: height)
            let lines = layout.slots.map {
                PSMTabRichLine(text: "x", scale: $0.size.scale, bold: false, italic: false, color: nil,
                               secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: false)
            }
            let rects = PSMTabRichContentRenderer.layout(lines: lines,
                                                         in: style.richContentRect(cell: cell, x: 0, width: 300),
                                                         baseFont: NSFont.systemFont(ofSize: style.fontSize))
            let background = style.backgroundRect(for: cell.frame)
            let top = try XCTUnwrap(rects.first).minY - background.minY
            let bottom = background.maxY - (try XCTUnwrap(rects.last).maxY)
            XCTAssertGreaterThanOrEqual(top, 5, "orientation \(orientation.rawValue)")
            XCTAssertGreaterThanOrEqual(bottom, 5, "orientation \(orientation.rawValue)")
        }
    }

    // The minimum tab height includes the style's chrome, at the style's font
    // size.
    func testMinimumTabHeightForAStyleIncludesItsChrome() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let enabled = TabContentConfiguration(enabled: true,
                                              layout: .defaultLayout,
                                              lineLimit: nil,
                                              overrides: nil,
                                              subtitleFormat: "")
        let tahoe = PSMTahoeTabStyle()
        // The cell is 1pt shorter than its row, its background is inset 3pt
        // more, and the lines get 2pt more above and below.
        XCTAssertEqual(tahoe.richContentChromeHeight, 8)
        XCTAssertEqual(enabled.minimumTabHeight(style: tahoe),
                       enabled.minimumTabHeight(fontSize: tahoe.fontSize) + tahoe.richContentChromeHeight)
        let yosemite = PSMYosemiteTabStyle()
        XCTAssertEqual(enabled.minimumTabHeight(style: yosemite),
                       enabled.minimumTabHeight(fontSize: (yosemite as PSMTabStyle).fontSize ?? 0),
                       "a style without chrome to account for")
        XCTAssertEqual(TabContentConfiguration.disabled.minimumTabHeight(style: tahoe), 0)
    }

    // Without rich content a horizontal Tahoe tab still centers its title and
    // the icons beside it.
    func testTahoeClassicHorizontalTabStaysCentered() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let cell = makeCell(style: PSMTahoeTabStyle(),
                            orientation: .horizontalOrientation,
                            rich: false,
                            graphic: solidImage(.red),
                            statusIcon: solidImage(.blue))
        let graphic = try XCTUnwrap(drawnBounds(of: cell, matching: isRed))
        let icon = try XCTUnwrap(drawnBounds(of: cell, matching: isBlue))
        XCTAssertGreaterThan(graphic.minX, cellFrame.minX + 60)
        XCTAssertLessThan(icon.maxX, cellFrame.maxX - 60)
    }

    func testYosemiteDrawsTheGraphicAndIconOnTheTitleLine() throws {
        try checkDrawing(style: { PSMYosemiteTabStyle() }, titleLineMidY: { _ in titleLineMidY }, tolerance: 1)
    }

    func testTahoeDrawsTheGraphicAndIconOnTheTitleLine() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        try checkDrawing(style: { PSMTahoeTabStyle() }, titleLineMidY: tahoeTitleLineMidY, tolerance: 1)
    }

    // A classic Yosemite tab with no subtitle draws the same during a tab bar
    // search: there is no subtitle to highlight. Its drawing passed the
    // missing subtitle's nil string to PSMTabSearchHighlight, whose string
    // parameter is non-optional Swift; unit psm-nullability-guards stops
    // there, as -willDrawSubtitle: already did. Under the nullability
    // sanitizer this test failed before.
    func testYosemiteTabWithoutASubtitleDrawsTheSameDuringASearch() {
        let cell = makeCell(style: PSMYosemiteTabStyle(), orientation: .horizontalOrientation, rich: false)
        XCTAssertNil(cell.cachedSubtitle, "precondition: no subtitle")
        let before = render(cell)
        control.searchHighlightQuery = "zzz"
        let searching = render(cell)
        XCTAssertNil(differingBounds(before, searching))
    }

    // A style that is not attached to a tab bar has no delegate to ask for a
    // font size override, so it uses its default.
    func testYosemiteFontSizeWithoutATabBarIsTheDefault() {
        XCTAssertEqual((PSMYosemiteTabStyle() as PSMTabStyle).fontSize, 11)
    }
}
