//
//  PSMTabGroupRichContentTests.swift
//  ModernTests
//
//  With rich tab content on, a collapsed tab group's chip shows its members'
//  combined lines below the group's name, so it's sized like a tab.
//

import XCTest
@testable import iTerm2SharedARC

private final class Group: NSObject, PSMTabGroup {
    let name: String
    let color = NSColor(srgbRed: 0.2, green: 0.9, blue: 0.2, alpha: 1)
    init(name: String) {
        self.name = name
    }
}

private final class RichDataSource: NSObject, PSMTabGroupDataSource {
    var showsRichContent = true
    var lines = [PSMTabRichLine(text: "~/project")]
    var name = "G"

    func tabGroup(withIdentifier identifier: String) -> PSMTabGroup? {
        return Group(name: name)
    }

    func tabGroupsShowRichContent() -> Bool {
        return showsRichContent
    }

    // How many times the members' lines were asked for.
    var richLinesRequests = 0
    // The sizing lines; by default, lines like `lines` with no text.
    var sizingLines: [PSMTabRichLine]?

    func tabGroupRichLines(withIdentifier identifier: String) -> [PSMTabRichLine]? {
        richLinesRequests += 1
        return showsRichContent ? lines : nil
    }

    func tabGroupRichLinesForSizing() -> [PSMTabRichLine]? {
        guard showsRichContent else {
            return nil
        }
        return sizingLines ?? lines.map { PSMTabRichLine(text: "", scale: $0.scale) }
    }
}

private extension PSMTabRichLine {
    convenience init(text: String, scale: CGFloat = 1) {
        self.init(text: text,
                  scale: scale,
                  bold: false,
                  italic: false,
                  color: nil,
                  secondary: false,
                  lineBreakMode: .byTruncatingTail,
                  collapsesWhenEmpty: false)
    }
}

final class PSMTabGroupRichContentTests: XCTestCase {
    private var bar: PSMTabBarControl!
    private var dataSource: RichDataSource!

    override func setUp() {
        super.setUp()
        bar = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 60))
        dataSource = RichDataSource()
        bar.tabGroupDataSource = dataSource
    }

    override func tearDown() {
        bar = nil
        dataSource = nil
        super.tearDown()
    }

    private func makeChip() -> PSMTabBarCell {
        let chip = PSMTabBarCell(controlView: bar)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        return chip
    }

    private var verticalCellHeight: CGFloat {
        typealias Fn = @convention(c) (AnyObject, Selector) -> CGFloat
        let selector = NSSelectorFromString("verticalCellHeight")
        return unsafeBitCast(bar.method(for: selector), to: Fn.self)(bar, selector)
    }

    func testLinesComeFromTheDataSourceOnlyWhenShown() {
        XCTAssertEqual(bar.richLines(forTabGroupIdentifier: "A")?.map(\.text), ["~/project"])
        XCTAssertNil(bar.richLines(forTabGroupIdentifier: ""))
        dataSource.showsRichContent = false
        XCTAssertNil(bar.richLines(forTabGroupIdentifier: "A"))
    }

    // On a vertical bar a collapsed chip takes a whole row, like the tabs it
    // stands for. An expanded group's header holds only the name and stays
    // short.
    func testCollapsedChipIsARowTallOnAVerticalBar() {
        bar.style = PSMYosemiteTabStyle()
        bar.orientation = .verticalOrientation
        // A row tall enough for the name and lines, as rich content makes it.
        bar.height = 57
        let chip = makeChip()
        dataSource.showsRichContent = false
        let header = bar.height(ofTabGroupChipCell: chip, collapsed: true)
        XCTAssertEqual(bar.height(ofTabGroupChipCell: chip, collapsed: false), header)

        dataSource.showsRichContent = true
        XCTAssertEqual(bar.height(ofTabGroupChipCell: chip, collapsed: true), verticalCellHeight)
        XCTAssertEqual(bar.height(ofTabGroupChipCell: chip, collapsed: false), header)
    }

    // Minimal draws a collapsed group as a short capsule with no lines, so
    // it stays as short as an expanded group's header.
    func testMinimalCollapsedChipIsAsShortAsAHeader() {
        bar.style = PSMMinimalTabStyle()
        bar.orientation = .verticalOrientation
        bar.height = 57
        let chip = makeChip()
        let header = bar.height(ofTabGroupChipCell: chip, collapsed: false)
        XCTAssertLessThan(header, verticalCellHeight, "precondition: the header is shorter than a row")
        XCTAssertEqual(bar.height(ofTabGroupChipCell: chip, collapsed: true), header)
    }

    // A chip's height depends only on the layout, so it comes from lines
    // that describe the layout, without combining the members' content.
    func testCollapsedChipHeightComesFromTheSizingLines() {
        let style = PSMYosemiteTabStyle()
        bar.style = style
        bar.orientation = .verticalOrientation
        bar.height = 24
        let chip = makeChip()
        let sizing = (0..<4).map { _ in PSMTabRichLine(text: "") }
        dataSource.sizingLines = sizing
        dataSource.richLinesRequests = 0
        let header = bar.height(ofTabGroupChipCell: chip, collapsed: false)
        let expected = max(verticalCellHeight,
                           ceil(style.tabGroupCollapsedChipHeight(for: sizing, headerHeight: header)))
        XCTAssertEqual(bar.height(ofTabGroupChipCell: chip, collapsed: true), expected)
        XCTAssertEqual(dataSource.richLinesRequests, 0)
    }

    private func addCollapsedGroupAndTabs(_ tabs: Int) {
        let chip = makeChip()
        bar.cells().add(chip)
        let member = PSMTabBarCell(controlView: bar)!
        member.tabGroupIdentifier = "A"
        member.isCollapsedHidden = true
        bar.cells().add(member)
        for _ in 0..<tabs {
            bar.cells().add(PSMTabBarCell(controlView: bar)!)
        }
    }

    private func withScrollableTabBar(_ scrollable: Bool, _ body: () throws -> Void) rethrows {
        let saved = iTermPreferences.bool(forKey: kPreferenceKeyScrollableSideTabBar)
        iTermPreferences.setBool(scrollable, forKey: kPreferenceKeyScrollableSideTabBar)
        defer { iTermPreferences.setBool(saved, forKey: kPreferenceKeyScrollableSideTabBar) }
        try body()
    }

    // When tabs share one width, a collapsed chip with lines stands in for
    // tabs, so it shares that width too rather than reserving its own and
    // squeezing the tabs.
    func testUniformCollapsedChipIsLaidOutLikeATab() {
        withScrollableTabBar(false) {
            bar.style = PSMYosemiteTabStyle()
            bar.style.tabBar = bar
            bar.frame = NSRect(x: 0, y: 0, width: 400, height: 24)
            bar.sizeCellsToFit = false
            bar.stretchCellsToFit = false
            bar.cellMinWidth = 60
            bar.cellOptimumWidth = 175
            addCollapsedGroupAndTabs(3)
            let widths = (bar.cellWidths(forHorizontalArrangementWithOverflow: false) ?? []).map(\.doubleValue)
            XCTAssertEqual(widths.count, 5)
            XCTAssertEqual(widths[1], 0, "the hidden member")
            XCTAssertEqual(widths[0], widths[2], accuracy: 0.5)
            XCTAssertLessThan(widths[0], 175, "the bar is too narrow for tabs at their optimum width")
        }
    }

    // Minimal draws a collapsed group as a capsule without lines, so it
    // keeps its own width rather than taking a tab's.
    func testMinimalCollapsedChipKeepsItsWidth() {
        withScrollableTabBar(false) {
            bar.style = PSMMinimalTabStyle()
            bar.style.tabBar = bar
            bar.frame = NSRect(x: 0, y: 0, width: 600, height: 24)
            bar.sizeCellsToFit = false
            bar.stretchCellsToFit = false
            bar.cellMinWidth = 60
            bar.cellOptimumWidth = 175
            addCollapsedGroupAndTabs(3)
            let widths = (bar.cellWidths(forHorizontalArrangementWithOverflow: false) ?? []).map(\.doubleValue)
            XCTAssertEqual(widths.count, 5)
            XCTAssertLessThan(widths[0], widths[2], "narrower than a tab")
        }
    }

    func testScrollableCollapsedChipIsTabWidth() throws {
        try withScrollableTabBar(true) {
            bar.style = PSMYosemiteTabStyle()
            bar.sizeCellsToFit = false
            bar.scrollableTabWidth = 120
            addCollapsedGroupAndTabs(1)
            typealias Fn = @convention(c) (AnyObject, Selector) -> NSArray
            let selector = NSSelectorFromString("naturalHorizontalCellWidths")
            let widths = try XCTUnwrap(unsafeBitCast(bar.method(for: selector), to: Fn.self)(bar, selector) as? [NSNumber])
            XCTAssertEqual(widths.map(\.doubleValue), [120, 0, 120])
        }
    }

    // Without lines, a collapsed chip keeps its own, name-based width.
    func testUniformCollapsedChipWithoutLinesKeepsItsWidth() {
        withScrollableTabBar(false) {
            dataSource.showsRichContent = false
            bar.style = PSMYosemiteTabStyle()
            bar.style.tabBar = bar
            bar.frame = NSRect(x: 0, y: 0, width: 600, height: 24)
            bar.sizeCellsToFit = false
            addCollapsedGroupAndTabs(2)
            let widths = (bar.cellWidths(forHorizontalArrangementWithOverflow: false) ?? []).map(\.doubleValue)
            XCTAssertEqual(widths[0], bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: true, memberCount: 1, nested: false),
                           accuracy: 0.5)
            XCTAssertNotEqual(widths[0], widths[2], accuracy: 0.5)
        }
    }

    // A vertical chip that doesn't change collapse state must not move during
    // another group's slide, even if its members have no frames because they
    // are in the overflow menu.
    func testStaticChipKeepsItsHeightDuringAnotherGroupsSlide() {
        bar.style = PSMYosemiteTabStyle()
        bar.orientation = .verticalOrientation
        bar.height = 57
        let chip = makeChip()
        let header = bar.height(ofTabGroupChipCell: chip, collapsed: false)
        XCTAssertLessThan(header, verticalCellHeight, "precondition")
        let reference = PSMTabBarCell(controlView: bar)!
        reference.frame = NSRect(x: 0, y: 0, width: 150, height: verticalCellHeight - 1)
        chip.frame = NSRect(x: 0, y: 60, width: 150, height: header - 1)
        let overflowed = PSMTabBarCell(controlView: bar)!
        overflowed.tabGroupIdentifier = "A"
        bar.cells().setArray([reference, chip, overflowed])
        bar.perform(NSSelectorFromString("startVerticalCollapseAnimation"))
        let start = (bar.value(forKey: "_collapseStartWidths") as? [NSNumber])?.map(\.doubleValue)
        let target = (bar.value(forKey: "_collapseTargetWidths") as? [NSNumber])?.map(\.doubleValue)
        bar.perform(NSSelectorFromString("cancelCollapseAnimation"))
        XCTAssertEqual(start?[1], target?[1])
        XCTAssertEqual(target?[1], header)
    }

    // When tabs fit their content, so does the chip, up to the widest a tab
    // may be.
    func testUnevenHorizontalChipFitsItsLines() {
        let style = PSMYosemiteTabStyle()
        bar.style = style
        bar.sizeCellsToFit = true
        bar.cellMaxWidth = 300
        dataSource.lines = [PSMTabRichLine(text: "a fairly long directory name")]
        let fitted = bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: true, memberCount: 2, nested: false)
        XCTAssertEqual(fitted, style.tabGroupCollapsedChipWidth(for: dataSource.lines), accuracy: 0.5)
        XCTAssertLessThan(fitted, 300)

        dataSource.lines = [PSMTabRichLine(text: String(repeating: "x", count: 200))]
        XCTAssertEqual(bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: true, memberCount: 2, nested: false), 300)
    }

    func testExpandedChipIgnoresLines() {
        bar.style = PSMYosemiteTabStyle()
        bar.sizeCellsToFit = false
        bar.cellOptimumWidth = 175
        XCTAssertLessThan(bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: false, memberCount: 2, nested: false), 175)
    }

    // MARK: - Drawing

    private func render(size: NSSize, draw: @escaping () -> Void) throws -> NSBitmapImageRep {
        let image = NSImage(size: size, flipped: true) { _ in
            draw()
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: Int(size.width),
                                                 pixelsHigh: Int(size.height),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Whether anything other than the group's color is drawn in rect.
    private func hasNonGroupPixels(_ rep: NSBitmapImageRep, in rect: NSRect) -> Bool {
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if !(c.greenComponent > c.redComponent + 0.3) {
                    return true
                }
            }
        }
        return false
    }

    private func renderYosemiteChip(orientation: PSMTabBarOrientation) throws -> NSBitmapImageRep {
        let style = PSMYosemiteTabStyle()
        bar.style = style
        bar.orientation = orientation
        bar.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        let chip = makeChip()
        chip.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        typealias Draw = @convention(c) (AnyObject, Selector, AnyObject, Int, NSString, AnyObject, Bool) -> Void
        let selector = NSSelectorFromString("drawSquaredCollapsedTabGroupChip:memberCount:groupID:inBar:isDropTarget:")
        return try render(size: NSSize(width: 200, height: 80)) { [bar] in
            unsafeBitCast(style.method(for: selector), to: Draw.self)(style, selector, chip, 2, "A", bar!, false)
        }
    }

    // The name moves to the top and the lines fill the space below it.
    func testSquaredChipDrawsLinesBelowTheName() throws {
        for orientation in [PSMTabBarOrientation.horizontalOrientation, .verticalOrientation] {
            let lower = NSRect(x: 8, y: 50, width: 150, height: 25)
            dataSource.showsRichContent = false
            XCTAssertFalse(hasNonGroupPixels(try renderYosemiteChip(orientation: orientation), in: lower),
                           "precondition: just a centered name")
            dataSource.showsRichContent = true
            dataSource.lines = [PSMTabRichLine(text: ""), PSMTabRichLine(text: "WWWWWWWW")]
            let rep = try renderYosemiteChip(orientation: orientation)
            XCTAssertTrue(hasNonGroupPixels(rep, in: lower), "\(orientation)")
            XCTAssertTrue(hasNonGroupPixels(rep, in: NSRect(x: 8, y: 0, width: 40, height: 22)),
                          "the name is at the top: \(orientation)")
        }
    }

    // A chip is only as tall as a tab, whose height leaves room for the title
    // and subtitle lines the chip doesn't show. If the name took more than
    // that, the last line wouldn't fit and would silently not be drawn.
    func testHorizontalChipFitsItsLinesWithoutASubtitleLine() throws {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.titleID, size: .regular),
                                              TabContentSlot(identifier: TabContentSlot.directoryID, size: .small),
                                              TabContentSlot(identifier: TabContentSlot.jobID, size: .small)])
        let height = TabContentSettings.requiredHeight(layout: layout, baseFontSize: 11)
        let rep = try renderSquaredChip(style: PSMYosemiteTabStyle(), orientation: .horizontalOrientation, height: height)
        XCTAssertTrue(hasNonGroupPixels(rep, in: NSRect(x: 8, y: height - 12, width: 150, height: 10)),
                      "the last line is drawn")
    }

    // On a vertical bar the name keeps its header-sized band, so the chip
    // grows when a tab's height doesn't leave room for the name and lines.
    func testVerticalChipGrowsToFitItsLines() throws {
        // Minimal draws a collapsed group without lines, so use a style
        // that draws them.
        let style = PSMYosemiteTabStyle()
        bar.orientation = .verticalOrientation
        // A row too short for the name and the lines.
        bar.height = 24
        bar.style = style
        dataSource.lines = [PSMTabRichLine(text: "", scale: TabContentLineSize.small.scale),
                            PSMTabRichLine(text: "WWWWWWWW", scale: TabContentLineSize.small.scale)]
        let height = bar.height(ofTabGroupChipCell: makeChip(), collapsed: true)
        XCTAssertGreaterThan(height, verticalCellHeight, "grew past a row")
        let rep = try renderSquaredChip(style: style, orientation: .verticalOrientation, height: height)
        XCTAssertTrue(hasNonGroupPixels(rep, in: NSRect(x: 8, y: height - 12, width: 150, height: 10)),
                      "the last line is drawn")
    }

    private func renderSquaredChip(style: PSMTabStyle,
                                   orientation: PSMTabBarOrientation,
                                   height: CGFloat) throws -> NSBitmapImageRep {
        dataSource.lines = [PSMTabRichLine(text: "", scale: TabContentLineSize.small.scale),
                            PSMTabRichLine(text: "WWWWWWWW", scale: TabContentLineSize.small.scale)]
        bar.style = style
        bar.orientation = orientation
        bar.frame = NSRect(x: 0, y: 0, width: 200, height: ceil(height))
        let chip = makeChip()
        chip.frame = NSRect(x: 0, y: 0, width: 200, height: height)
        typealias Draw = @convention(c) (AnyObject, Selector, AnyObject, Int, NSString, AnyObject, Bool) -> Void
        let selector = NSSelectorFromString("drawSquaredCollapsedTabGroupChip:memberCount:groupID:inBar:isDropTarget:")
        let object = style as AnyObject
        return try render(size: NSSize(width: 200, height: ceil(height))) { [bar] in
            unsafeBitCast(object.method(for: selector), to: Draw.self)(object, selector, chip, 2, "A", bar!, false)
        }
    }

    // Mid-slide on a vertical bar, the expanded run's chip slot is between
    // header and collapsed heights. The name stays in a header-sized band at
    // the top rather than riding the middle of the slot.
    func testRunKeepsTheNameAtTheTopMidSlide() throws {
        let style = PSMYosemiteTabStyle()
        bar.style = style
        bar.orientation = .verticalOrientation
        bar.height = 57
        bar.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let chip = makeChip()
        chip.frame = NSRect(x: 0, y: 0, width: 200, height: 45)
        let first = PSMTabBarCell(controlView: bar)!
        first.tabGroupIdentifier = "A"
        first.frame = NSRect(x: 0, y: 45, width: 200, height: 57)
        let header = bar.height(ofTabGroupChipCell: chip, collapsed: false)
        XCTAssertLessThan(header + 8, 45, "precondition: the slot is well past the header")
        typealias Draw = @convention(c) (AnyObject, Selector, Bool, AnyObject, NSRect, AnyObject, NSString, AnyObject) -> Void
        let selector = NSSelectorFromString("drawSquaredTabGroupRunHorizontal:chip:tabsRect:firstTab:groupID:inBar:")
        let rep = try render(size: NSSize(width: 200, height: 120)) { [bar] in
            unsafeBitCast(style.method(for: selector), to: Draw.self)(style, selector, false, chip,
                                                                       first.frame, first, "A", bar!)
        }
        XCTAssertTrue(hasNonGroupPixels(rep, in: NSRect(x: 8, y: 2, width: 40, height: header - 4)))
        XCTAssertFalse(hasNonGroupPixels(rep, in: NSRect(x: 8, y: header + 2, width: 40, height: 45 - header - 4)))
    }

    func testNameBandGivesWayToLines() {
        let lines = [PSMTabRichLine(text: "a"), PSMTabRichLine(text: "b")]
        let font = NSFont.systemFont(ofSize: 11)
        let content = PSMTabRichContentRenderer.contentHeight(lines: lines, baseFont: font)
        func band(_ available: CGFloat) -> CGFloat {
            return PSMTabRichContentRenderer.nameBandHeight(preferred: 24, minimum: 14, available: available,
                                                            lines: lines, baseFont: font, bottomPadding: 4)
        }
        XCTAssertEqual(band(100), 24, "room to spare")
        XCTAssertEqual(band(content + 4 + 18), 18, "shrinks so the lines fit")
        XCTAssertEqual(band(content), 14, "never below the name's own height")
    }

    // A chip sharing the tabs' width never goes below what its name needs.
    // When that's more than the tabs' share, the tabs give up the difference
    // rather than the last one falling into the overflow menu.
    func testSharingChipWiderThanATabDoesNotPushATabIntoOverflow() {
        withScrollableTabBar(false) {
            // Chip widths are cached by name; use one no other test sized.
            dataSource.name = "A long group name \(UUID().uuidString.prefix(4))"
            bar.style = PSMYosemiteTabStyle()
            bar.style.tabBar = bar
            bar.sizeCellsToFit = false
            bar.stretchCellsToFit = false
            bar.cellMinWidth = 40
            // So tabs fill the bar rather than stopping at their optimum.
            bar.cellOptimumWidth = 1000
            let own = bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: true, memberCount: 1, nested: false)
            // Room for six tabs and the chip only if the tabs are narrower than it.
            bar.frame = NSRect(x: 0, y: 0, width: own + 6 * (own - 40), height: 24)
            addCollapsedGroupAndTabs(6)
            let widths = (bar.cellWidths(forHorizontalArrangementWithOverflow: false) ?? []).map(\.doubleValue)
            XCTAssertEqual(widths.count, 8, "every cell fits")
            XCTAssertEqual(widths[0], own, accuracy: 0.5)
            XCTAssertLessThan(widths[2], own)
        }
    }

    // Paths that size a chip outside the full layout (seeding new chip cells,
    // a drag) must give a sharing chip the tabs' width too, or it shrinks to
    // its name until the next layout.
    func testSettledWidthOfASharingChip() {
        withScrollableTabBar(false) {
            bar.style = PSMYosemiteTabStyle()
            bar.sizeCellsToFit = false
            addCollapsedGroupAndTabs(1)
            let tab = bar.cells()[2] as! PSMTabBarCell
            tab.frame = NSRect(x: 0, y: 0, width: 150, height: 24)
            let own = bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: true, memberCount: 1, nested: false)
            XCTAssertEqual(bar.settledWidthOfCollapsedTabGroupChip(withWidth: own, cells: bar.cells() as! [PSMTabBarCell]),
                           max(own, 150))
            dataSource.showsRichContent = false
            XCTAssertEqual(bar.settledWidthOfCollapsedTabGroupChip(withWidth: own, cells: bar.cells() as! [PSMTabBarCell]),
                           own)
        }
        withScrollableTabBar(true) {
            // With no laid-out tab and no layout yet, the scrolling width.
            dataSource.showsRichContent = true
            (bar.cells()[2] as! PSMTabBarCell).frame = .zero
            bar.scrollableTabWidth = 120
            XCTAssertEqual(bar.settledWidthOfCollapsedTabGroupChip(withWidth: 30, cells: bar.cells() as! [PSMTabBarCell]),
                           120)
        }
    }

    // Scrolled partly off the top of a vertical bar, the chip's name and
    // lines scroll with it rather than piling up at the top.
    func testScrolledChipKeepsItsGeometry() throws {
        dataSource.lines = [PSMTabRichLine(text: "", scale: TabContentLineSize.small.scale),
                            PSMTabRichLine(text: "WWWWWWWW", scale: TabContentLineSize.small.scale)]
        let style = PSMYosemiteTabStyle()
        bar.style = style
        bar.orientation = .verticalOrientation
        bar.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        func draw(atY y: CGFloat) throws -> NSBitmapImageRep {
            let chip = makeChip()
            chip.frame = NSRect(x: 0, y: y, width: 200, height: 80)
            typealias Draw = @convention(c) (AnyObject, Selector, AnyObject, Int, NSString, AnyObject, Bool) -> Void
            let selector = NSSelectorFromString("drawSquaredCollapsedTabGroupChip:memberCount:groupID:inBar:isDropTarget:")
            return try render(size: NSSize(width: 200, height: 80)) { [bar] in
                unsafeBitCast(style.method(for: selector), to: Draw.self)(style, selector, chip, 2, "A", bar!, false)
            }
        }
        let whole = try draw(atY: 0)
        let scrolled = try draw(atY: -30)
        var mismatches = 0
        for y in 3..<48 {
            for x in 3..<150 {
                let a = whole.colorAt(x: x, y: y + 30)!.usingColorSpace(.sRGB)!
                let b = scrolled.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if abs(a.redComponent - b.redComponent) > 0.1 || abs(a.greenComponent - b.greenComponent) > 0.1 {
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    private func commit(_ widths: [CGFloat]) {
        let nsWidths = widths.map { NSNumber(value: Double($0)) } as NSArray
        bar.perform(NSSelectorFromString("finishUpdateWithRegularWidths:widthsWithOverflow:"),
                    with: nsWidths,
                    with: nsWidths)
    }

    // With no laid-out tab to copy (a bar of collapsed groups), a sharing
    // chip's settled width comes from the layout last committed, not from
    // whatever width query ran last.
    func testSettledWidthWithNoVisibleTabsUsesTheCommittedLayout() {
        withScrollableTabBar(false) {
            bar.style = PSMYosemiteTabStyle()
            bar.style.tabBar = bar
            bar.frame = NSRect(x: 0, y: 0, width: 600, height: 24)
            bar.sizeCellsToFit = false
            addCollapsedGroupAndTabs(0)
            addCollapsedGroupAndTabs(0)
            let own = bar.widthOfTabGroupChipCell(forIdentifier: "A", collapsed: true, memberCount: 1, nested: false)
            func settled() -> CGFloat {
                return bar.settledWidthOfCollapsedTabGroupChip(withWidth: own, cells: bar.cells() as! [PSMTabBarCell])
            }
            commit([175, 0, 175, 0])
            XCTAssertEqual(settled(), 175)
            // A query for another layout doesn't change it.
            bar.cellOptimumWidth = 250
            _ = bar.cellWidths(forHorizontalArrangementWithOverflow: true)
            XCTAssertEqual(settled(), 175)
            // When every chip keeps its own, wider width, so does this one.
            commit([own, 0, own + 20, 0])
            XCTAssertEqual(settled(), own)
        }
    }

    // A scrollable bar whose tabs all fit lays them out like a fixed bar, so
    // a sharing chip takes the tabs' laid-out width, not the scrolling width.
    func testSettledWidthOnAScrollableBarThatFitsUsesTheTabs() {
        withScrollableTabBar(true) {
            bar.style = PSMYosemiteTabStyle()
            bar.sizeCellsToFit = false
            bar.scrollableTabWidth = 120
            addCollapsedGroupAndTabs(1)
            (bar.cells()[2] as! PSMTabBarCell).frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            XCTAssertEqual(bar.settledWidthOfCollapsedTabGroupChip(withWidth: 30, cells: bar.cells() as! [PSMTabBarCell]),
                           300)
        }
    }
}
