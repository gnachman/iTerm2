//
//  PSMTabRichContentDrawingTests.swift
//  ModernTests
//
//  Draws tab cells that have rich content lines in each tab style, in the
//  configurations that change how a cell is laid out.
//

import XCTest
@testable import iTerm2SharedARC

private final class FakeRichTab: NSObject, PSMTabBarControlRepresentedObjectIdentifierProtocol {
    var lines: [PSMTabRichLine]
    var graphic: NSImage?
    private(set) var richLineRequests = 0
    private(set) var graphicRequests = 0

    init(lines: [PSMTabRichLine], graphic: NSImage?) {
        self.lines = lines
        self.graphic = graphic
    }

    func psmTabRichLines() -> [PSMTabRichLine]? {
        richLineRequests += 1
        return lines
    }

    func psmTabGraphic() -> NSImage? {
        graphicRequests += 1
        return graphic
    }
}

final class PSMTabRichContentDrawingTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var items = [NSTabViewItem]()

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 60),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isReleasedWhenClosed = false
        control = RichTabContentTabBar(frame: NSRect(x: 0, y: 0, width: 600, height: 60))
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

    private func richLine(_ text: String) -> PSMTabRichLine {
        return PSMTabRichLine(text: text,
                              scale: 1,
                              bold: false,
                              italic: false,
                              color: nil,
                              secondary: false,
                              lineBreakMode: .byTruncatingTail,
                              collapsesWhenEmpty: true)
    }

    private func draw(style: PSMTabStyle, graphic: NSImage?) {
        control.style = style
        let tab = FakeRichTab(lines: [richLine("title"), richLine("/some/path")], graphic: graphic)
        let item = NSTabViewItem(identifier: tab)
        item.label = "title"
        items.append(item)
        let cell = PSMTabBarCell(controlView: control)!
        cell.representedObject = item
        cell.stringValue = "title"
        cell.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        control.cells().setArray([cell])
        // The control only draws cells for its tab view's items, so draw the
        // cell directly, the way the control would.
        let image = NSImage(size: control.bounds.size)
        image.lockFocusFlipped(true)
        cell.draw(withFrame: cell.frame, in: control)
        image.unlockFocus()
        XCTAssertGreaterThan(tab.richLineRequests, 0, "precondition: the cell was drawn with rich content")
        if graphic != nil {
            XCTAssertGreaterThan(tab.graphicRequests, 0, "precondition: the style asked for the graphic")
        }
    }

    private func graphic() -> NSImage {
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
    }

    // A horizontal Tahoe tab lays out its graphic centered. The rich label
    // after it must not break the layout's left-to-right gravity order.
    func testTahoeHorizontalWithGraphic() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        draw(style: PSMTahoeTabStyle(), graphic: graphic())
    }

    func testTahoeHorizontalWithoutGraphic() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        draw(style: PSMTahoeTabStyle(), graphic: nil)
    }

    func testYosemiteWithGraphic() {
        draw(style: PSMYosemiteTabStyle(), graphic: graphic())
    }

    // The rich lines replace the classic title, which isn't drawn, so how
    // long that title is must not change how much room the lines get. A
    // suppressed close button reserves space on a horizontal tab.
    func testYosemiteRichWidthIgnoresHiddenTitle() {
        let style = PSMYosemiteTabStyle()
        control.style = style
        style.orientation = .horizontalOrientation
        func rect(title: String) -> NSRect {
            let item = NSTabViewItem(identifier: FakeRichTab(lines: [richLine("x")], graphic: nil))
            items.append(item)
            let cell = PSMTabBarCell(controlView: control)!
            cell.representedObject = item
            cell.stringValue = title
            cell.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
            return style.richContentRect(for: cell, labelPosition: 20, hasIcon: false, iconRect: .zero, reservedSpace: 22)
        }
        let short = rect(title: "a")
        let long = rect(title: String(repeating: "a very long hidden title ", count: 10))
        XCTAssertEqual(short, long)
        XCTAssertEqual(short.minX, 42, "starts after the reserved close button space")
    }

    // A tab sized to fit its content fits its rich lines, not the classic
    // title they replace.
    private func desiredWidth(style: PSMTabStyle, title: String, line: String) -> Float {
        control.style = style
        let item = NSTabViewItem(identifier: FakeRichTab(lines: [richLine(line)], graphic: nil))
        items.append(item)
        let cell = PSMTabBarCell(controlView: control)!
        cell.representedObject = item
        cell.stringValue = title
        cell.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        return style.desiredWidth(ofTabCell: cell)
    }

    func testYosemiteDesiredWidthFollowsRichLines() {
        let longLine = String(repeating: "/a/long/directory", count: 4)
        XCTAssertGreaterThan(desiredWidth(style: PSMYosemiteTabStyle(), title: "a", line: longLine),
                             desiredWidth(style: PSMYosemiteTabStyle(), title: "a", line: "a") + 50)
    }

    func testTahoeDesiredWidthFollowsRichLines() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let longLine = String(repeating: "/a/long/directory", count: 4)
        XCTAssertGreaterThan(desiredWidth(style: PSMTahoeTabStyle(), title: "a", line: longLine),
                             desiredWidth(style: PSMTahoeTabStyle(), title: "a", line: "a") + 50)
    }

    // A horizontal Tahoe bar clips its tabs to a rounded container. A bar
    // made taller for rich content must get a taller container, or its tabs
    // are cut off at the classic height.
    private func withRichContent(_ enabled: Bool, _ body: () throws -> Void) throws {
        let bar = try XCTUnwrap(control as? RichTabContentTabBar)
        bar.richContent = enabled
        defer { bar.richContent = false }
        try body()
    }

    func testTahoeContainerFillsATallerBar() throws {
        try withRichContent(true) {
            try checkTahoeContainer(expectedMaxY: 61)
        }
    }

    // Without rich content, a bar made tall another way, such as a larger
    // default tab bar height, keeps the standard container it always had.
    func testTahoeContainerStaysStandardWithoutRichContent() throws {
        try withRichContent(false) {
            try checkTahoeContainer(expectedMaxY: 32)
        }
    }

    private func checkTahoeContainer(expectedMaxY: CGFloat) throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        control.style = style
        control.orientation = .horizontalOrientation
        control.insets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        control.frame = NSRect(x: 0, y: 0, width: 600, height: 65)
        // Drawing is what attaches the style to the bar.
        let image = NSImage(size: control.bounds.size)
        image.lockFocusFlipped(true)
        control.draw(control.bounds)
        image.unlockFocus()
        let clip = try XCTUnwrap(style.accessoryClipPath(forTabBar: control)).bounds
        XCTAssertEqual(clip.minY, 4, accuracy: 0.01)
        XCTAssertEqual(clip.maxY, expectedMaxY, accuracy: 0.01)
    }

    // Bars with larger insets, as in traditional full screen, keep the
    // standard container.
    func testTahoeStandardContainerUnchanged() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        control.style = style
        control.orientation = .horizontalOrientation
        control.insets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        control.frame = NSRect(x: 0, y: 0, width: 600, height: 36)
        let image = NSImage(size: control.bounds.size)
        image.lockFocusFlipped(true)
        control.draw(control.bounds)
        image.unlockFocus()
        let clip = try XCTUnwrap(style.accessoryClipPath(forTabBar: control)).bounds
        XCTAssertEqual(clip.minY, 4, accuracy: 0.01)
        XCTAssertEqual(clip.height, 28, accuracy: 0.01)
    }

    // A group's header row in a vertical bar holds only the group's name, so
    // it keeps the normal row height when rich content makes tab rows taller.
    // Otherwise the space below the name fills with a thick band of color.
    func testTahoeVerticalGroupHeaderKeepsNormalHeight() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        control.style = style
        control.orientation = .verticalOrientation
        style.orientation = .verticalOrientation
        control.frame = NSRect(x: 0, y: 0, width: 200, height: 600)
        control.height = 80
        let chip = PSMTabBarCell(controlView: control)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        typealias F = @convention(c) (AnyObject, Selector) -> CGFloat
        let selector = NSSelectorFromString("verticalCellHeight")
        let rowHeight = unsafeBitCast(control.method(for: selector), to: F.self)(control, selector)
        XCTAssertGreaterThan(rowHeight, style.tabBarHeight, "precondition: tall rows")
        XCTAssertEqual(control.height(ofTabGroupChipCell: chip), style.tabBarHeight)
    }

    // The style must keep the header's shorter height when it lays out the
    // cell, or the header's frame overlaps the tab below it.
    func testTahoeVerticalCellRectKeepsAShorterHeaderHeight() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeTabStyle()
        control.style = style
        control.orientation = .verticalOrientation
        style.orientation = .verticalOrientation
        let generic = NSRect(x: 0, y: 0, width: 200, height: 80)
        let header = style.adjustedCellRect(NSRect(x: 0, y: 100, width: 200, height: 26), generic: generic)
        XCTAssertEqual(header.height, 25)
        let tab = style.adjustedCellRect(NSRect(x: 0, y: 126, width: 200, height: 80), generic: generic)
        XCTAssertEqual(tab.height, 79)
    }

    // The Minimal style reports no tab bar height of its own (0). Its header
    // is its normal row height, and stays that when rows are taller.
    func testMinimalVerticalGroupHeaderHeight() throws {
        // Not visible to Swift.
        let styleClass = try XCTUnwrap(NSClassFromString("PSMMinimalTabStyle") as? NSObject.Type)
        let style = try XCTUnwrap(styleClass.init() as? PSMTabStyle)
        control.style = style
        control.orientation = .verticalOrientation
        control.frame = NSRect(x: 0, y: 0, width: 200, height: 600)
        let chip = PSMTabBarCell(controlView: control)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        let normal = CGFloat(iTermAdvancedSettingsModel.compactMinimalTabBarHeight())
        control.height = normal
        XCTAssertEqual(control.height(ofTabGroupChipCell: chip), normal)
        control.height = normal + 40
        XCTAssertEqual(control.height(ofTabGroupChipCell: chip), normal)
    }
}
