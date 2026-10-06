//
//  FloatingPaneLayout.swift
//  iTerm2SharedARC
//
//  Connects FloatingPaneGeometry to real floats: measures a float's session, and applies a
//  placement to its view and grid. A float's grid is canonical; its frame follows from it.
//

import AppKit

@objc(iTermFloatingPaneLayout)
final class FloatingPaneLayout: NSObject {
    // MARK: - Measuring

    /// The cell size and the chrome around the grid of a float's session, as it is now.
    static func metrics(for session: PTYSession) -> FloatingPaneMetrics? {
        guard let view = session.view, let textview = session.textview else {
            return nil
        }
        let cell = CGSize(width: max(1, textview.charWidth), height: max(1, textview.lineHeight))
        let compact = view.compactFrame()
        let outline = iTermFloatingPaneView.outlineWidth * 2
        let chrome = CGSize(width: compact.width - CGFloat(session.columns) * cell.width + outline,
                            height: compact.height - CGFloat(session.rows) * cell.height + outline)
        return FloatingPaneMetrics(cellSize: cell, chrome: chrome)
    }

    private static func containerSize(of pane: iTermFloatingPaneView) -> CGSize? {
        return pane.superview?.bounds.size
    }

    /// The float's current placement in visual coordinates.
    static func placement(of pane: iTermFloatingPaneView, session: PTYSession) -> FloatingPanePlacement? {
        guard let container = pane.superview else {
            return nil
        }
        let frame = FloatingPaneGeometry.toVisual(pane.outlineFrame,
                                                  containerHeight: container.bounds.height,
                                                  containerIsFlipped: container.isFlipped)
        return FloatingPanePlacement(frame: frame,
                                     grid: FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows)))
    }

    // MARK: - Applying

    /// Sets the float's frame and grid.
    static func apply(_ placement: FloatingPanePlacement,
                      to pane: iTermFloatingPaneView,
                      session: PTYSession) {
        guard let container = pane.superview else {
            return
        }
        let frame = FloatingPaneGeometry.fromVisual(placement.frame,
                                                    containerHeight: container.bounds.height,
                                                    containerIsFlipped: container.isFlipped)
        DLog("Apply \(placement) to \(session) giving frame \(NSStringFromRect(frame))")
        if pane.outlineFrame != frame {
            pane.outlineFrame = frame
            pane.splitView.adjustSubviews()
        }
        let grid = VT100GridSizeMake(Int32(placement.grid.columns), Int32(placement.grid.rows))
        if session.columns != grid.width || session.rows != grid.height {
            session.setSize(grid)
        }
    }

    /// The smallest a float may be: the minimum grid at its own font, plus its chrome.
    @objc(minimumSizeOfFloatingPaneWithSession:)
    static func minimumSize(session: PTYSession) -> NSSize {
        return metrics(for: session)?.minimumFrameSize ?? .zero
    }

    /// Keeps the float's grid and recomputes its frame from its current metrics, after something
    /// changed them: a font, margin, scroller, title bar or status bar change.
    @objc(refitFloatingPane:session:)
    static func refit(_ pane: iTermFloatingPaneView, session: PTYSession) {
        guard let container = containerSize(of: pane) else {
            return
        }
        relayout(pane, session: session, oldContainerSize: container)
    }

    // MARK: - Operations

    /// Sizes and positions a float that was just added: 80% of the tab, centered.
    @objc(placeNewFloatingPane:session:)
    static func placeNew(_ pane: iTermFloatingPaneView, session: PTYSession) {
        guard let metrics = metrics(for: session), let container = containerSize(of: pane) else {
            return
        }
        apply(FloatingPaneGeometry.initialPlacement(container: container, metrics: metrics),
              to: pane,
              session: session)
        pane.desiredGrid = nil
    }

    /// Gives a float the largest grid whose frame fits in `outlineFrame` (in the container's
    /// coordinates), keeping its top left.
    @objc(fitFloatingPane:session:toOutlineFrame:)
    static func fit(_ pane: iTermFloatingPaneView, session: PTYSession, toOutlineFrame outlineFrame: NSRect) {
        guard let metrics = metrics(for: session), let superview = pane.superview else {
            return
        }
        let container = superview.bounds.size
        let visual = FloatingPaneGeometry.toVisual(outlineFrame,
                                                   containerHeight: container.height,
                                                   containerIsFlipped: superview.isFlipped)
        let grid = metrics.grid(fitting: visual.size).clamped(
            min: .minimum,
            max: FloatingPaneGeometry.maximumGrid(container: container, metrics: metrics))
        let frame = CGRect(origin: visual.origin, size: metrics.frameSize(for: grid))
        apply(FloatingPanePlacement(frame: FloatingPaneGeometry.clamp(frame, in: container), grid: grid),
              to: pane,
              session: session)
        pane.desiredGrid = nil
    }

    /// Moves a float by whole cells, as the keyboard move commands do.
    @objc(moveFloatingPane:session:columns:rows:)
    static func move(_ pane: iTermFloatingPaneView, session: PTYSession, columns: Int, rows: Int) {
        guard let metrics = metrics(for: session),
              let container = containerSize(of: pane),
              let start = placement(of: pane, session: session) else {
            return
        }
        let delta = CGSize(width: CGFloat(columns) * metrics.cellSize.width,
                           height: CGFloat(rows) * metrics.cellSize.height)
        let frame = FloatingPaneGeometry.move(start.frame, by: delta, in: container)
        apply(FloatingPanePlacement(frame: frame, grid: start.grid), to: pane, session: session)
    }

    /// Grows or shrinks a float by whole cells, as the keyboard resize commands do.
    @objc(resizeFloatingPane:session:columns:rows:)
    static func resize(_ pane: iTermFloatingPaneView, session: PTYSession, columns: Int, rows: Int) {
        guard let metrics = metrics(for: session),
              let container = containerSize(of: pane),
              let start = placement(of: pane, session: session) else {
            return
        }
        apply(FloatingPaneGeometry.resize(start, byColumns: columns, rows: rows, in: container, metrics: metrics),
              to: pane,
              session: session)
        pane.desiredGrid = nil
    }

    /// Re-places a float after its container changed size, or after something changed its metrics
    /// (font, margins, title bar). Keeps the grid, shrinking it only if the tab is too small and
    /// remembering what it wanted.
    @objc(relayoutFloatingPane:session:oldContainerSize:)
    static func relayout(_ pane: iTermFloatingPaneView, session: PTYSession, oldContainerSize: NSSize) {
        guard let metrics = metrics(for: session),
              let container = containerSize(of: pane),
              let start = placement(of: pane, session: session) else {
            return
        }
        guard container.width > 0, container.height > 0 else {
            return
        }
        // The visual frame was computed against the new height; recompute against the old one so a
        // float touching the bottom edge is recognized.
        let oldFrame: CGRect
        if let superview = pane.superview, !superview.isFlipped {
            let outline = pane.outlineFrame
            oldFrame = CGRect(x: outline.minX,
                              y: oldContainerSize.height - outline.maxY,
                              width: outline.width,
                              height: outline.height)
        } else {
            oldFrame = start.frame
        }
        let wanted = pane.desiredGrid ?? start.grid
        let result = FloatingPaneGeometry.placement(after: FloatingPanePlacement(frame: oldFrame, grid: start.grid),
                                                    desiredGrid: pane.desiredGrid,
                                                    oldContainer: oldContainerSize,
                                                    newContainer: container,
                                                    metrics: metrics)
        apply(result, to: pane, session: session)
        pane.desiredGrid = FloatingPaneGeometry.desiredGrid(wanted: wanted, actual: result.grid)
    }
}
