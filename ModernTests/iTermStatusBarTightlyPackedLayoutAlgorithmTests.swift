//
//  iTermStatusBarTightlyPackedLayoutAlgorithmTests.swift
//  ModernTests
//
//  Characterization tests for iTermStatusBarTightlyPackedLayoutAlgorithm, the
//  status bar layout used when the layout setting is “tightly packed”. The
//  base layout algorithm gives each visible component its minimum width and
//  then, in rounds, asks its subclass how much the components that can still
//  grow should grow. This subclass divides the available width among them in
//  proportion to their spring constants, rounding each share down, never
//  taking a component past its maximum width, and taking back any part of
//  the share that would put the component more than a whole point past its
//  preferred width (plus the icon width when it has an icon).
//
//  Everything goes through the Objective-C runtime: the algorithm is made by
//  iTermStatusBarLayoutAlgorithm's factory, as the status bar view controller
//  makes it, and the growth method is sent by its selector, as the base
//  class sends it.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// The factory and the growth method, sent by name through AnyObject.
@objc private protocol TightlyPackedLayoutSelectors {
    @objc(layoutAlgorithmWithContainerViews:mandatoryView:statusBarWidth:setting:removeEmptyComponents:)
    func makeLayoutAlgorithmBySelector(containerViews: [iTermStatusBarContainerView],
                                       mandatoryView: iTermStatusBarContainerView?,
                                       statusBarWidth: CGFloat,
                                       setting: UInt,
                                       removeEmptyComponents: Bool) -> NSObject?

    @objc(totalGrowthAfterUpdatingDesiredWidthsForAvailableWidth:sumOfSpringConstants:views:)
    func totalGrowthBySelector(availableWidth: CGFloat,
                               sumOfSpringConstants: Double,
                               views: [iTermStatusBarContainerView]) -> Double
}

// A status bar component whose sizes and spring constant the test chooses.
private final class TightlyPackedTestComponent: iTermStatusBarBaseComponent {
    var springConstant: CGFloat = 1
    var minimumWidth: CGFloat = 10
    var maximumWidth: CGFloat = 1000
    var preferredWidth: CGFloat = 100
    var canStretch = true
    var icon: NSImage?
    private let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))

    override func statusBarComponentSpringConstant() -> CGFloat { springConstant }
    override func statusBarComponentMinimumWidth() -> CGFloat { minimumWidth }
    override func statusBarComponentMaximumWidth() -> CGFloat { maximumWidth }
    override func statusBarComponentPreferredWidth() -> CGFloat { preferredWidth }
    override func statusBarComponentCanStretch() -> Bool { canStretch }
    override func statusBarComponentIcon() -> NSImage? { icon }
    override func statusBarComponentView() -> NSView { view }
}

final class iTermStatusBarTightlyPackedLayoutAlgorithmTests: XCTestCase {
    private let unitClassName = "iTermStatusBarTightlyPackedLayoutAlgorithm"
    // iTermStatusBarLayoutAlgorithmSettingTightlyPacked.
    private let tightlyPackedSetting: UInt = 1

    private func makeContainer(spring: CGFloat = 1,
                               minimum: CGFloat = 10,
                               maximum: CGFloat = 1000,
                               preferred: CGFloat = 100,
                               icon: NSImage? = nil,
                               desiredWidth: CGFloat = 10) throws -> iTermStatusBarContainerView {
        let component = TightlyPackedTestComponent(configuration: [:], scope: nil)
        component.springConstant = spring
        component.minimumWidth = minimum
        component.maximumWidth = maximum
        component.preferredWidth = preferred
        component.icon = icon
        let container = try XCTUnwrap(iTermStatusBarContainerView(component: component))
        container.desiredWidth = desiredWidth
        return container
    }

    private func makeAlgorithm(_ views: [iTermStatusBarContainerView],
                               statusBarWidth: CGFloat = 500) throws -> NSObject {
        let factory = iTermStatusBarLayoutAlgorithm.self as AnyObject
        let made = factory.makeLayoutAlgorithmBySelector?(containerViews: views,
                                                          mandatoryView: nil,
                                                          statusBarWidth: statusBarWidth,
                                                          setting: tightlyPackedSetting,
                                                          removeEmptyComponents: false)
        return try XCTUnwrap(made ?? nil)
    }

    private func growth(_ algorithm: NSObject,
                        available: CGFloat,
                        sum: Double,
                        views: [iTermStatusBarContainerView]) throws -> Double {
        return try XCTUnwrap((algorithm as AnyObject).totalGrowthBySelector?(availableWidth: available,
                                                                             sumOfSpringConstants: sum,
                                                                             views: views))
    }

    // MARK: - The runtime interface

    func testFactoryMakesThisClassForTheTightlyPackedSetting() throws {
        let algorithm = try makeAlgorithm([])
        XCTAssertEqual(NSStringFromClass(type(of: algorithm)), unitClassName)
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        let superclass: AnyClass = try XCTUnwrap(class_getSuperclass(cls))
        XCTAssertEqual(NSStringFromClass(superclass), "iTermStatusBarBaseLayoutAlgorithm")
    }

    func testGrowthSelectorAndEncoding() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        let selector = NSSelectorFromString("totalGrowthAfterUpdatingDesiredWidthsForAvailableWidth:sumOfSpringConstants:views:")
        let method = try XCTUnwrap(class_getInstanceMethod(cls, selector))
        XCTAssertEqual(String(cString: try XCTUnwrap(method_getTypeEncoding(method))), "d40@0:8d16d24@32")
        // The class has its own implementation, not only the base class's.
        let superclass: AnyClass = try XCTUnwrap(class_getSuperclass(cls))
        XCTAssertNotEqual(method_getImplementation(method),
                          class_getMethodImplementation(superclass, selector))
    }

    // MARK: - Dividing the width

    // Shares follow the spring constants. The first view grows by a quarter
    // of 100 and stays under its preferred width. The second's share of 75
    // would take it 35 past its preferred width of 50, so 35 is taken back.
    func testWidthIsDividedInProportionToSpringConstantsUpToThePreferredWidth() throws {
        let a = try makeContainer(spring: 1, preferred: 100, desiredWidth: 10)
        let b = try makeContainer(spring: 3, preferred: 50, desiredWidth: 10)
        let algorithm = try makeAlgorithm([a, b])
        let total = try growth(algorithm, available: 100, sum: 4, views: [a, b])
        XCTAssertEqual(a.desiredWidth, 35)
        XCTAssertEqual(b.desiredWidth, 50)
        XCTAssertEqual(total, 65)
    }

    // Each share is rounded down: a third of 10 is 3.
    func testSharesAreRoundedDown() throws {
        let views = try (0..<3).map { _ in try makeContainer(desiredWidth: 10) }
        let algorithm = try makeAlgorithm(views)
        let total = try growth(algorithm, available: 10, sum: 3, views: views)
        XCTAssertEqual(views.map(\.desiredWidth), [13, 13, 13])
        XCTAssertEqual(total, 9)
    }

    // The amount past the preferred width that is taken back is rounded
    // down too, so a view may end up less than a point past it.
    func testOverageIsRoundedDown() throws {
        let view = try makeContainer(preferred: 47.5, desiredWidth: 10)
        let algorithm = try makeAlgorithm([view])
        let total = try growth(algorithm, available: 40, sum: 1, views: [view])
        // A share of 40 proposes 50, which is 2.5 past 47.5; 2 is taken back.
        XCTAssertEqual(view.desiredWidth, 48)
        XCTAssertEqual(total, 38)
    }

    // A share that would take a view past its maximum width is cut to reach
    // the maximum exactly.
    func testShareIsLimitedByTheMaximumWidth() throws {
        let view = try makeContainer(maximum: 30, preferred: 100, desiredWidth: 10)
        let algorithm = try makeAlgorithm([view])
        let total = try growth(algorithm, available: 60, sum: 1, views: [view])
        XCTAssertEqual(view.desiredWidth, 30)
        XCTAssertEqual(total, 20)
    }

    // The maximum width is the base algorithm's, which is never below the
    // minimum width: with a minimum of 40 and a maximum of 30, it is 40.
    func testMaximumWidthComesFromTheBaseAlgorithm() throws {
        let view = try makeContainer(minimum: 40, maximum: 30, preferred: 100, desiredWidth: 10)
        let algorithm = try makeAlgorithm([view])
        let total = try growth(algorithm, available: 60, sum: 1, views: [view])
        XCTAssertEqual(view.desiredWidth, 40)
        XCTAssertEqual(total, 30)
    }

    // A view already past its maximum width shrinks to it, and the growth
    // is negative.
    func testAViewPastItsMaximumShrinks() throws {
        let view = try makeContainer(maximum: 40, preferred: 100, desiredWidth: 50)
        let algorithm = try makeAlgorithm([view])
        let total = try growth(algorithm, available: 5, sum: 1, views: [view])
        XCTAssertEqual(view.desiredWidth, 40)
        XCTAssertEqual(total, -10)
    }

    // A view with an icon may grow to its preferred width plus the icon's
    // width.
    func testAnIconAddsItsWidthToThePreferredWidth() throws {
        let iconWidth = iTermStatusBarViewControllerIconWidth
        let icon = NSImage(size: NSSize(width: 12, height: 12))
        let withIcon = try makeContainer(preferred: 40, icon: icon, desiredWidth: 10)
        let withoutIcon = try makeContainer(preferred: 40, desiredWidth: 10)
        let algorithm = try makeAlgorithm([withIcon, withoutIcon])
        let total = try growth(algorithm, available: 200, sum: 2, views: [withIcon, withoutIcon])
        XCTAssertEqual(withIcon.desiredWidth, 40 + iconWidth)
        XCTAssertEqual(withoutIcon.desiredWidth, 40)
        XCTAssertEqual(total, 60 + iconWidth)
    }

    // The sum of spring constants is the caller's, not recomputed: with a
    // sum of 4 a lone view of spring constant 1 gets a quarter.
    func testTheGivenSumOfSpringConstantsIsUsed() throws {
        let view = try makeContainer(spring: 1, preferred: 1000, desiredWidth: 10)
        let algorithm = try makeAlgorithm([view])
        let total = try growth(algorithm, available: 100, sum: 4, views: [view])
        XCTAssertEqual(view.desiredWidth, 35)
        XCTAssertEqual(total, 25)
    }

    func testNoViewsMeansNoGrowth() throws {
        let algorithm = try makeAlgorithm([])
        XCTAssertEqual(try growth(algorithm, available: 100, sum: 1, views: []), 0)
    }

    // No available width and a sum of zero make each share 0 * infinity,
    // which is NaN: the view's width and the growth become NaN.
    func testZeroOverZeroGivesNaN() throws {
        let view = try makeContainer(desiredWidth: 10)
        let algorithm = try makeAlgorithm([view])
        let total = try growth(algorithm, available: 0, sum: 0, views: [view])
        XCTAssertTrue(view.desiredWidth.isNaN)
        XCTAssertTrue(total.isNaN)
    }

    // MARK: - Through the base algorithm

    // The base algorithm reaches the growth method when it lays out the
    // visible views: a stretchable view starts at its minimum width of 20 and
    // grows to its preferred width of 200.
    func testVisibleContainerViewsGrowsAViewToItsPreferredWidth() throws {
        let view = try makeContainer(minimum: 20, preferred: 200, desiredWidth: 0)
        let algorithm = try XCTUnwrap(try makeAlgorithm([view], statusBarWidth: 500) as? iTermStatusBarLayoutAlgorithm)
        let visible = algorithm.visibleContainerViews()
        XCTAssertEqual(visible.count, 1)
        XCTAssertTrue(visible.first === view)
        XCTAssertEqual(view.desiredWidth, 200)
    }
}
