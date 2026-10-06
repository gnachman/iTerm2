//
//  iTermFloatingPaneView.swift
//  iTerm2SharedARC
//
//  A floating pane: a session that sits above a tab's tiled layout. This wrapper holds the float's
//  outline and shadow and, inside it, a split view with exactly one child, the session's view.
//
//  The one-child split view keeps PTYTab's many casts of a session view's superview to
//  NSSplitView valid, so swaps (Instant Replay, Filter) work inside a float unchanged. The float's
//  frame and z-order belong to this wrapper. Records about a float must be keyed on the wrapper,
//  never on the session view, which can be swapped out.
//

import AppKit

@objc(iTermFloatingPaneView)
final class iTermFloatingPaneView: NSView {
    /// Width of the outline drawn around the float. The split view is inset by this much.
    @objc static let outlineWidth: CGFloat = 1

    /// The float's root: a split view with one child, the session's view.
    @objc let splitView: PTYSplitView

    @objc var isActive = false {
        didSet {
            updateOutlineColor()
        }
    }

    @objc init(frame: NSRect, splitView: PTYSplitView) {
        self.splitView = splitView
        super.init(frame: frame)
        wantsLayer = true
        autoresizesSubviews = true
        layer?.masksToBounds = false
        layer?.borderWidth = Self.outlineWidth
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        updateOutlineColor()
        updateShadowPath()

        splitView.autoresizingMask = [.width, .height]
        splitView.frame = Self.splitViewFrame(forBounds: bounds)
        addSubview(splitView)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    /// The session view currently showing in the float. During Instant Replay or Filter this is the
    /// synthetic session's view.
    @objc var sessionView: SessionView? {
        return splitView.subviews.first as? SessionView
    }

    @objc static func splitViewFrame(forBounds bounds: NSRect) -> NSRect {
        return bounds.insetBy(dx: outlineWidth, dy: outlineWidth)
    }

    /// The wrapper's frame for a given split view frame, both in the container's coordinates.
    @objc static func frame(forSplitViewFrame frame: NSRect) -> NSRect {
        return frame.insetBy(dx: -outlineWidth, dy: -outlineWidth)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateShadowPath()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOutlineColor()
    }

    private func updateShadowPath() {
        layer?.shadowPath = CGPath(rect: bounds, transform: nil)
    }

    private func updateOutlineColor() {
        let color = isActive ? NSColor.controlAccentColor : NSColor.separatorColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = color.cgColor
        }
    }
}
