//
//  PSMTabGroupAttentionImageTests.swift
//  iTerm2XCTests
//
//  A collapsed tab group's chip draws an attention icon supplied by the tab
//  group data source. These tests cover how the control asks for it.
//

import XCTest
@testable import iTerm2SharedARC

private final class Group: NSObject, PSMTabGroup {
    let name: String
    let color: NSColor
    init(name: String, color: NSColor = .systemBlue) {
        self.name = name
        self.color = color
    }
}

private final class GreenGroupDataSource: NSObject, PSMTabGroupDataSource {
    let image: NSImage
    init(image: NSImage) { self.image = image }
    func tabGroup(withIdentifier identifier: String) -> PSMTabGroup? {
        return Group(name: "G", color: NSColor(srgbRed: 0.2, green: 0.9, blue: 0.2, alpha: 1))
    }
    func tabGroupAttentionImage(withIdentifier identifier: String) -> NSImage? { image }
}

// A data source that predates the attention icon: it does not implement the
// optional method.
private final class PlainDataSource: NSObject, PSMTabGroupDataSource {
    func tabGroup(withIdentifier identifier: String) -> PSMTabGroup? {
        return Group(name: "Group")
    }
}

private final class AttentionDataSource: NSObject, PSMTabGroupDataSource {
    var images: [String: NSImage] = [:]
    var names: [String: String] = [:]
    private(set) var requests: [String] = []

    func tabGroup(withIdentifier identifier: String) -> PSMTabGroup? {
        return Group(name: names[identifier] ?? "Group")
    }

    func tabGroupAttentionImage(withIdentifier identifier: String) -> NSImage? {
        requests.append(identifier)
        return images[identifier]
    }
}

final class PSMTabGroupAttentionImageTests: XCTestCase {
    private var control: PSMTabBarControl!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    func testDataSourceWithoutOptionalMethodGivesNoImage() {
        let dataSource = PlainDataSource()
        control.tabGroupDataSource = dataSource
        XCTAssertNil(control.attentionImage(forTabGroupIdentifier: "A"))
    }

    func testImageComesFromDataSourceForThatGroup() {
        let dataSource = AttentionDataSource()
        let image = NSImage(size: NSSize(width: 16, height: 16))
        dataSource.images["A"] = image
        control.tabGroupDataSource = dataSource
        XCTAssertTrue(control.attentionImage(forTabGroupIdentifier: "A") === image)
        XCTAssertNil(control.attentionImage(forTabGroupIdentifier: "B"))
        XCTAssertEqual(dataSource.requests, ["A", "B"])
    }

    func testEmptyIdentifierDoesNotAskDataSource() {
        let dataSource = AttentionDataSource()
        control.tabGroupDataSource = dataSource
        XCTAssertNil(control.attentionImage(forTabGroupIdentifier: ""))
        XCTAssertTrue(dataSource.requests.isEmpty)
    }

    // The chip reserves room for the icon whether or not there is one, so a
    // collapsed group doesn't change width (and shift every tab after it)
    // when one of its members starts or stops needing attention. Sizing must
    // therefore never ask for the icon. Chip widths are cached process-wide by
    // name, so use a name no other test has sized, or the cache would answer
    // without reaching the code under test.
    func testSizingCollapsedChipDoesNotAskForAttention() {
        let dataSource = AttentionDataSource()
        let identifier = "attention-sizing-\(UUID().uuidString)"
        dataSource.names[identifier] = identifier
        dataSource.images[identifier] = NSImage(size: NSSize(width: 16, height: 16))
        control.tabGroupDataSource = dataSource
        let width = control.widthOfTabGroupChipCell(forIdentifier: identifier, collapsed: true, memberCount: 3, nested: false)
        XCTAssertGreaterThan(width, 0)
        XCTAssertTrue(dataSource.requests.isEmpty, "sizing a chip must not depend on its attention icon")
    }

    // A hidden member's icon changing must redraw its group's chip, which
    // can be far from where the member's own (zero-width) cell is.
    func testAttentionChangeRedrawsTheGroupsChip() {
        let chip = PSMTabBarCell(controlView: control)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        chip.frame = NSRect(x: 300, y: 0, width: 80, height: 24)
        control.cells().setArray([chip])
        // AppKit only tracks invalidation for a view in a window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 24),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(control)
        defer {
            control.removeFromSuperview()
            window.close()
        }
        control.displayIfNeeded()
        XCTAssertFalse(control.needsDisplay, "precondition: nothing pending")

        control.tabGroupAttentionDidChange(forIdentifier: "B")
        XCTAssertFalse(control.needsDisplay, "another group's change must not redraw this chip")

        control.tabGroupAttentionDidChange(forIdentifier: "A")
        XCTAssertTrue(control.needsDisplay)
    }

    // A collapsed group's members are squashed to nothing along the bar: zero
    // width in a horizontal bar, zero height in a vertical one. Either way
    // they must not draw, or a member's icon lands on top of the chip.
    func testCollapsedMemberIsHiddenAlongEitherAxis() {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isCollapsedHidden = true
        cell.frame = NSRect(x: 0, y: 0, width: 0, height: 24)
        XCTAssertTrue(cell.isHiddenByCollapse)
        cell.frame = NSRect(x: 0, y: 0, width: 200, height: 0)
        XCTAssertTrue(cell.isHiddenByCollapse, "vertical bar")
        // Mid-animation a member is partly visible and must draw.
        cell.frame = NSRect(x: 0, y: 0, width: 50, height: 24)
        XCTAssertFalse(cell.isHiddenByCollapse)
        cell.isCollapsedHidden = false
        cell.frame = NSRect(x: 0, y: 0, width: 0, height: 24)
        XCTAssertFalse(cell.isHiddenByCollapse)
    }

    // During a vertical collapse slide, members whose slots have shrunk to
    // nothing (those of already-collapsed groups, and a collapsing group at
    // the end) get an empty frame, as in the settled layout. A full-width,
    // zero-height frame made them look sized, which hid their group's chip.
    func testVerticalCollapseFrameEmptiesFinishedMembers() {
        let collapsed = PSMTabBarCell(controlView: control)!
        collapsed.isCollapsedHidden = true
        let visible = PSMTabBarCell(controlView: control)!
        control.cells().setArray([collapsed, visible])
        control.setValue([0, 30], forKey: "_collapseStartWidths")
        control.setValue([0, 30], forKey: "_collapseTargetWidths")
        control.setValue(0.5, forKey: "_collapseAnimT")
        control.setValue(1, forKey: "_collapseVerticalGap")
        control.setValue(0, forKey: "_collapseVerticalCellX")
        control.setValue(150, forKey: "_collapseVerticalCellWidth")
        control.perform(NSSelectorFromString("layoutVerticalCollapseFrame"))
        XCTAssertEqual(collapsed.frame.size, .zero)
        XCTAssertEqual(visible.frame.size, NSSize(width: 150, height: 29))
    }

    // When a vertical bar runs out of room, cells are removed from the end
    // until a full row is free for the overflow button. A group header can
    // be shorter than a row, so removing just one may not be enough.
    func testOverflowReclaimsAFullRow() {
        // Rows of 80 and a 24pt header at 160; the next tab didn't fit in 200.
        let origins = NSMutableArray(array: [0, 80, 160])
        PSMTabBarControl.reclaimRowForOverflowButton(inOrigins: origins, end: 184, available: 200, rowHeight: 80)
        XCTAssertEqual(origins as! [Int], [0], "header and the tab before it")

        // A full tab is enough on its own.
        let tabs = NSMutableArray(array: [0, 80])
        PSMTabBarControl.reclaimRowForOverflowButton(inOrigins: tabs, end: 160, available: 200, rowHeight: 80)
        XCTAssertEqual(tabs as! [Int], [0])
    }

    // Some icons aren't centered in their canvas. The chip centers what is
    // actually drawn on its disc.
    func testChipCentersAnOffCenterIconOnItsDisc() throws {
        // A red 8pt dot whose center is (11, 10) in a 16pt canvas.
        let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.red.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 6, width: 8, height: 8)).fill()
            return true
        }
        let bar = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let style = PSMYosemiteTabStyle()
        bar.style = style
        let dataSource = GreenGroupDataSource(image: icon)
        bar.tabGroupDataSource = dataSource
        let chip = PSMTabBarCell(controlView: bar)!
        chip.isTabGroupChip = true
        chip.tabGroupIdentifier = "A"
        chip.frame = NSRect(x: 0, y: 4, width: 120, height: 32)
        typealias Draw = @convention(c) (AnyObject, Selector, AnyObject, Int, NSString, AnyObject, Bool) -> Void
        let selector = NSSelectorFromString("drawSquaredCollapsedTabGroupChip:memberCount:groupID:inBar:isDropTarget:")
        let image = NSImage(size: NSSize(width: 200, height: 40), flipped: true) { _ in
            unsafeBitCast(style.method(for: selector), to: Draw.self)(style, selector, chip, 2, "A", bar, false)
            return true
        }
        // Render at 2x so a 1pt outline is measurable.
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 80,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 200, height: 40)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 200, height: 40))
        NSGraphicsContext.restoreGraphicsState()

        // The icon's pixels, and the disc's pixels around it (neither green nor red).
        var red = (x: 0.0, y: 0.0, n: 0.0)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if c.redComponent > 0.8 && c.greenComponent < 0.3 {
                    red = (red.x + Double(x), red.y + Double(y), red.n + 1)
                }
            }
        }
        XCTAssertGreaterThan(red.n, 0, "precondition: the icon was drawn")
        let cx = Int(red.x / red.n), cy = Int(red.y / red.n)
        var disc = (x: 0.0, y: 0.0, n: 0.0)
        for y in max(0, cy - 30)..<min(rep.pixelsHigh, cy + 30) {
            for x in max(0, cx - 30)..<min(rep.pixelsWide, cx + 30) {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let green = c.greenComponent > c.redComponent + 0.3
                if !green && c.alphaComponent > 0.5 {
                    disc = (disc.x + Double(x), disc.y + Double(y), disc.n + 1)
                }
            }
        }
        XCTAssertEqual(disc.x / disc.n, red.x / red.n, accuracy: 1.0, "horizontally centered")
        XCTAssertEqual(disc.y / disc.n, red.y / red.n, accuracy: 1.0, "vertically centered")

        // The contrast edge is a thin outline hugging the icon, not a disc:
        // nothing but the chip color more than about 1pt outside the icon.
        let scale = Double(rep.pixelsWide) / 200
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                // Include the icon's antialiased edge (red blended toward the
                // outline) so these are its true bounds.
                if c.redComponent > 0.4 && c.greenComponent < 0.4 && c.redComponent > c.blueComponent + 0.3 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        // 1pt of outline plus a pixel of antialiasing.
        let slack = Int(ceil(1.0 * scale)) + 1
        for y in max(0, minY - 6 * Int(scale))..<min(rep.pixelsHigh, maxY + 6 * Int(scale)) {
            for x in max(0, minX - 6 * Int(scale))..<min(rep.pixelsWide, maxX + 6 * Int(scale)) {
                let outside = x < minX - slack || x > maxX + slack || y < minY - slack || y > maxY + slack
                guard outside else { continue }
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                XCTAssertTrue(c.greenComponent > c.redComponent + 0.3,
                              "pixel (\(x), \(y)) beyond the outline isn't the chip color")
                if !(c.greenComponent > c.redComponent + 0.3) { return }
            }
        }
    }
}
