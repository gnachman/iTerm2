//
//  PSMTahoeTallTabShapeTests.swift
//  ModernTests
//
//  Rich tab content makes tabs taller. With it on, the Tahoe styles give
//  tall tabs rounded rectangles rather than very round stadiums, and every
//  part of a tab must agree on that shape. With it off, tabs keep their
//  classic stadium shape however tall the tab bar is.
//

import XCTest
@testable import iTerm2SharedARC

// A tab bar whose window does or doesn't show rich tab content. In the app,
// PseudoTerminal answers through the tab bar's delegate.
final class RichTabContentTabBar: PSMTabBarControl {
    var richContent = false

    override var showsRichTabContent: Bool {
        return richContent
    }
}

final class PSMTahoeTallTabShapeTests: XCTestCase {
    // A style's tab bar is weak.
    private var bars = [PSMTabBarControl]()

    // A tab bar whose window does or doesn't show rich content, as the
    // style's tab bar.
    @available(macOS 26, *)
    @discardableResult
    private func attach(_ style: PSMTahoeTabStyle, richContent: Bool) -> PSMTabBarControl {
        let bar = RichTabContentTabBar(frame: NSRect(origin: .zero, size: size))
        bar.richContent = richContent
        style.tabBar = bar
        bars.append(bar)
        return bar
    }

    private let size = NSSize(width: 200, height: 60)

    // Draws into a transparent bitmap at 1x and returns it.
    private func render(_ body: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width),
                                   pixelsHigh: Int(size.height),
                                   bitsPerSample: 8,
                                   samplesPerPixel: 4,
                                   hasAlpha: true,
                                   isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Alpha of the pixel whose lower left corner is (x, y), in drawing
    // coordinates (origin at the bottom left).
    private func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        return rep.colorAt(x: x, y: Int(size.height) - 1 - y)?.alphaComponent ?? 0
    }

    // A 50pt pill at (0, 2). Near its corner, (2, 12) is inside a rounded
    // rectangle with a 14pt radius but outside a stadium, whose radius is 25.
    private let pill = NSRect(x: 0, y: 2, width: 200, height: 50)
    private let cornerX = 2
    private let cornerY = 12

    // The dark style draws a selected tab's chrome with images of a pill's
    // ends. They must take the tab's rounded rectangle shape, not stretch
    // into a stadium over it.
    func testDarkSelectedChromeFollowsTheRoundedRectangle() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe styles need macOS 26")
        }
        let style = PSMTahoeDarkTabStyle()
        attach(style, richContent: true)
        let rep = render {
            style.drawCellOutline(path: NSBezierPath(rect: pill), rect: pill)
        }
        XCTAssertGreaterThan(alpha(rep, x: cornerX, y: cornerY), 0.5)
        XCTAssertEqual(alpha(rep, x: 0, y: 2), 0, "the corner itself stays rounded")
        XCTAssertGreaterThan(alpha(rep, x: 0, y: 27), 0.5, "the straight left edge")
    }

    func testTallTabsAreRoundedRectanglesWithRichContent() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe styles need macOS 26")
        }
        let style = PSMTahoeTabStyle()
        attach(style, richContent: true)
        let rep = render {
            style.drawCellBackgroundSelected(true,
                                             inRect: NSRect(x: 0, y: 0, width: 200, height: 53),
                                             withTabColor: nil,
                                             highlightAmount: 0,
                                             horizontal: false,
                                             isHighlighted: false)
        }
        XCTAssertGreaterThan(alpha(rep, x: cornerX, y: cornerY), 0.5)
    }

    // A tall tab bar without rich content, as from a large default tab bar
    // height, keeps the stadium shape it always had.
    func testTallTabsStayStadiumsWithoutRichContent() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe styles need macOS 26")
        }
        let style = PSMTahoeTabStyle()
        attach(style, richContent: false)
        let rep = render {
            style.drawCellBackgroundSelected(true,
                                             inRect: NSRect(x: 0, y: 0, width: 200, height: 53),
                                             withTabColor: nil,
                                             highlightAmount: 0,
                                             horizontal: false,
                                             isHighlighted: false)
        }
        XCTAssertEqual(alpha(rep, x: cornerX, y: cornerY), 0)
        let dark = PSMTahoeDarkTabStyle()
        attach(dark, richContent: false)
        let darkRep = render {
            dark.drawCellOutline(path: NSBezierPath(rect: pill), rect: pill)
        }
        XCTAssertEqual(alpha(darkRep, x: cornerX, y: cornerY), 0)
    }
    // The selected tab's side shadows run the full height of a tall tab
    // rather than stopping where a standard tab would end.
    func testDropShadowCoversATallTab() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe styles need macOS 26")
        }
        let style = PSMTahoeTabStyle()
        let bar = attach(style, richContent: true)
        let cell = try XCTUnwrap(PSMTabBarCell(controlView: bar))
        cell.frame = NSRect(x: 60, y: 4, width: 80, height: 50)
        let rep = render {
            style.drawDropShadow(cell: cell)
        }
        // Just outside each edge of the tab: near both ends, past where a
        // standard tab would end, and in the stretched middle.
        for y in [10, 29, 48] {
            XCTAssertGreaterThan(alpha(rep, x: 58, y: y), 0, "left, y=\(y)")
            XCTAssertGreaterThan(alpha(rep, x: 141, y: y), 0, "right, y=\(y)")
        }
    }
}
