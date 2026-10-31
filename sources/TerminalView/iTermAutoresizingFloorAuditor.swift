//
//  iTermAutoresizingFloorAuditor.swift
//  iTerm2SharedARC
//
//  Terminal windows are laid out by hand, but anything that engages AppKit's
//  layout engine in a window (a constraint, NSGlassEffectView, some controls)
//  makes AppKit translate every view's autoresizing mask into required
//  constraints. On an axis where a view's size is flexible, its margins that
//  are not flexible are captured as constants, and since a size cannot go
//  below zero they become a minimum size for the superview. Through a chain of
//  flexible ancestors that reaches the window, and the user can no longer make
//  the window smaller. A hidden view with a stale frame is the usual cause.
//  Issue 13118.
//
//  This checks for such a floor from the frames and masks alone, so it works
//  whether or not the engine is engaged. Development builds run it after each
//  layout of a terminal window.
//

import AppKit

@objc(iTermAutoresizingFloorAuditor)
final class AutoresizingFloorAuditor: NSObject {
    // Called with a description of each new violation. Tests set this, which
    // also forgets what was reported before.
    @objc static var violationHandler: ((String) -> Void)? {
        didSet {
            activeViolations.removeAllObjects()
        }
    }

    // For each root view, the violations found by the last check, identified
    // by axis and culprit views rather than by sizes and frames, which change
    // as the window resizes. A violation is reported when it first appears and
    // again only if it goes away and comes back. Weak keys let a closed
    // window's entry go away with it.
    private static let activeViolations = NSMapTable<NSView, NSMutableSet>.weakToStrongObjects()

    private struct Contribution {
        var view: NSView
        var margins: CGFloat
    }

    private struct Violation {
        var description: String
        var key: String
    }

    // Describes each axis on which the views under `root` impose a minimum
    // size of more than `threshold` points on it, naming the views whose
    // fixed margins add up to it.
    @objc(violationsInView:threshold:)
    static func violations(in root: NSView, threshold: CGFloat) -> [String] {
        return findViolations(in: root, threshold: threshold).map { $0.description }
    }

    private static func findViolations(in root: NSView, threshold: CGFloat) -> [Violation] {
        var result = [Violation]()
        for horizontal in [true, false] {
            var contributions = [Contribution]()
            let floor = self.floor(of: root, horizontal: horizontal, contributions: &contributions)
            guard floor > threshold else {
                continue
            }
            let culprits = contributions.filter { $0.margins > 0.5 }
            let axis = horizontal ? "Width" : "Height"
            let descriptions = culprits.map {
                "\(type(of: $0.view)) margins=\($0.margins) frame=\(NSStringFromRect($0.view.frame)) hidden=\($0.view.isHiddenOrHasHiddenAncestor)"
            }
            let identities = culprits.map { "\(ObjectIdentifier($0.view).hashValue)" }
            result.append(Violation(description: "\(axis) floor of \(floor) on \(type(of: root)) from: \(descriptions.joined(separator: "; "))",
                                    key: ([axis] + identities).joined(separator: ",")))
        }
        return result
    }

    // Development builds call this after laying out a terminal window's root
    // view.
    @objc(checkRootView:)
    static func check(rootView: NSView) {
        let violations = findViolations(in: rootView, threshold: 1)
        let previous = activeViolations.object(forKey: rootView) ?? NSMutableSet()
        let current = NSMutableSet()
        for violation in violations {
            current.add(violation.key)
            if !previous.contains(violation.key) {
                DLog("\(violation.description)")
                violationHandler?(violation.description)
            }
        }
        if current.count == 0 {
            activeViolations.removeObject(forKey: rootView)
        } else {
            activeViolations.setObject(current, forKey: rootView)
        }
    }

    // Only subviews whose size is flexible on the axis can pass a floor up, so
    // the walk stays on those.
    private static func floor(of view: NSView, horizontal: Bool, contributions: inout [Contribution]) -> CGFloat {
        var result: CGFloat = 0
        let bounds = view.bounds
        for subview in view.subviews where subview.translatesAutoresizingMaskIntoConstraints {
            let mask = subview.autoresizingMask
            let frame = subview.frame
            let margins: CGFloat
            if horizontal {
                guard mask.contains(.width) else {
                    continue
                }
                margins = (mask.contains(.minXMargin) ? 0 : frame.minX - bounds.minX) +
                    (mask.contains(.maxXMargin) ? 0 : bounds.maxX - frame.maxX)
            } else {
                guard mask.contains(.height) else {
                    continue
                }
                margins = (mask.contains(.minYMargin) ? 0 : frame.minY - bounds.minY) +
                    (mask.contains(.maxYMargin) ? 0 : bounds.maxY - frame.maxY)
            }
            var inner = [Contribution]()
            let total = margins + floor(of: subview, horizontal: horizontal, contributions: &inner)
            if total > result {
                result = total
                contributions = [Contribution(view: subview, margins: margins)] + inner
            }
        }
        return result
    }
}
