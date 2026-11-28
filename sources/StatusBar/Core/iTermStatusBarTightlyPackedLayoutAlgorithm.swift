//
//  iTermStatusBarTightlyPackedLayoutAlgorithm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

import Foundation

// The status bar layout for the “tightly packed” setting. The base algorithm
// gives each component its minimum width and then repeatedly asks for the
// growth of the components that can still grow; this one divides the
// available width among them in proportion to their spring constants.
@objc(iTermStatusBarTightlyPackedLayoutAlgorithm)
class iTermStatusBarTightlyPackedLayoutAlgorithm: iTermStatusBarBaseLayoutAlgorithm {
    // The base class declares and implements this method (returning 0) only
    // in its .m file, so Swift cannot see it, and this method replaces it by
    // selector without `override`. Each view grows by its share of
    // availableWidth, rounded down, but not past its maximum width. If that
    // would take it past its preferred width (plus the icon width when it has
    // an icon), the overage rounded down to whole points is taken back, so a
    // view can end up less than a point past it. Returns the total growth.
    @objc(totalGrowthAfterUpdatingDesiredWidthsForAvailableWidth:sumOfSpringConstants:views:)
    func totalGrowthAfterUpdatingDesiredWidths(forAvailableWidth availableWidth: CGFloat,
                                               sumOfSpringConstants: Double,
                                               views: [iTermStatusBarContainerView]) -> Double {
        var growth = 0.0
        for view in views {
            let component = view.component
            let weight = component.statusBarComponentSpringConstant() / sumOfSpringConstants
            var delta = floor(availableWidth * weight)
            let maxWidth = maximumWidth(for: component)
            if view.desiredWidth + delta > maxWidth {
                delta = maxWidth - view.desiredWidth
            }
            let iconWidth = component.statusBarComponentIcon() == nil ? 0 : iTermStatusBarViewControllerIconWidth
            let maximum = component.statusBarComponentPreferredWidth() + iconWidth
            let proposed = view.desiredWidth + delta
            let overage = floor(max(0, proposed - maximum))
            delta -= overage
            view.desiredWidth += delta
            growth += delta
            DLog("  grow \(component) by \(delta) to \(view.desiredWidth). Its preferred width is \(component.statusBarComponentPreferredWidth())")
        }
        return growth
    }
}
