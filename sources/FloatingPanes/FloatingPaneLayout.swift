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

    /// The largest grid the float can have in its tab, as (columns, rows) in an NSSize.
    @objc(maximumGridOfFloatingPane:session:)
    static func maximumGrid(_ pane: iTermFloatingPaneView, session: PTYSession) -> NSSize {
        guard let metrics = metrics(for: session), let container = containerSize(of: pane) else {
            return NSSize(width: CGFloat(session.columns), height: CGFloat(session.rows))
        }
        let grid = FloatingPaneGeometry.maximumGrid(container: container, metrics: metrics)
        return NSSize(width: CGFloat(grid.columns), height: CGFloat(grid.rows))
    }

    /// Sets the float's grid, clamped to what fits in its tab, keeping its top left where there is
    /// room. A program's resize request (CSI 8 t, DECCOLM, the API) goes here: for a float, the pane
    /// is the window.
    @objc(setGridOfFloatingPane:session:columns:rows:)
    static func setGrid(_ pane: iTermFloatingPaneView, session: PTYSession, columns: Int, rows: Int) {
        resize(pane,
               session: session,
               columns: columns - Int(session.columns),
               rows: rows - Int(session.rows))
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

    // MARK: - Persistence

    /// The float's outline frame in visual coordinates (top left origin, y down) of its container.
    @objc(visualOutlineFrameOfFloatingPane:)
    static func visualOutlineFrame(of pane: iTermFloatingPaneView) -> NSRect {
        guard let container = pane.superview else {
            return pane.outlineFrame
        }
        return FloatingPaneGeometry.toVisual(pane.outlineFrame,
                                             containerHeight: container.bounds.height,
                                             containerIsFlipped: container.isFlipped)
    }

    /// While maximized, the visual frame the float returns to. NSZeroRect otherwise.
    @objc(visualFrameBeforeMaximizingOfFloatingPane:)
    static func visualFrameBeforeMaximizing(of pane: iTermFloatingPaneView) -> NSRect {
        guard let saved = pane.outlineFrameBeforeMaximizing, let container = pane.superview else {
            return .zero
        }
        return FloatingPaneGeometry.toVisual(saved,
                                             containerHeight: container.bounds.height,
                                             containerIsFlipped: container.isFlipped)
    }

    /// The grid the float wants if it was shrunk to fit its tab, as {"columns", "rows"}.
    @objc(desiredGridDictionaryOfFloatingPane:)
    static func desiredGridDictionary(of pane: iTermFloatingPaneView) -> [String: Int]? {
        guard let grid = pane.desiredGrid else {
            return nil
        }
        return ["columns": grid.columns, "rows": grid.rows]
    }

    /// Records a placement from a saved arrangement. It is applied the first time the float's
    /// container has a size, by relayout.
    @objc(setRestoredPlacementOfFloatingPane:visualFrame:containerSize:desiredGrid:visualFrameBeforeMaximizing:)
    static func setRestoredPlacement(of pane: iTermFloatingPaneView,
                                     visualFrame: NSRect,
                                     containerSize: NSSize,
                                     desiredGrid: [String: Any]?,
                                     visualFrameBeforeMaximizing: NSRect) {
        pane.pendingRestore = iTermFloatingPaneView.PendingRestore(
            frame: visualFrame,
            containerSize: containerSize,
            frameBeforeMaximizing: visualFrameBeforeMaximizing.isEmpty ? nil : visualFrameBeforeMaximizing)
        if let columns = (desiredGrid?["columns"] as? NSNumber)?.intValue,
           let rows = (desiredGrid?["rows"] as? NSNumber)?.intValue {
            pane.desiredGrid = FloatingPaneGrid(columns: columns, rows: rows)
        }
    }

    /// Applies a saved placement: the origin scaled by the ratio of the new container to the saved
    /// one, the size from the session's saved grid at the current font, then clamped.
    private static func applyPendingRestore(_ pending: iTermFloatingPaneView.PendingRestore,
                                            to pane: iTermFloatingPaneView,
                                            session: PTYSession,
                                            metrics: FloatingPaneMetrics,
                                            container: CGSize) {
        func scaled(_ rect: CGRect) -> CGPoint {
            let sx = pending.containerSize.width > 0 ? container.width / pending.containerSize.width : 1
            let sy = pending.containerSize.height > 0 ? container.height / pending.containerSize.height : 1
            return CGPoint(x: (rect.minX * sx).rounded(), y: (rect.minY * sy).rounded())
        }
        let saved = FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows))
        let wanted = pane.desiredGrid ?? saved
        if let beforeMaximizing = pending.frameBeforeMaximizing {
            // Restore the frame to return to, then fill the tab.
            let grid = metrics.grid(fitting: beforeMaximizing.size).clamped(
                min: .minimum,
                max: FloatingPaneGeometry.maximumGrid(container: container, metrics: metrics))
            let frame = FloatingPaneGeometry.clamp(CGRect(origin: scaled(beforeMaximizing),
                                                          size: metrics.frameSize(for: grid)),
                                                   in: container)
            fit(pane, session: session, toOutlineFrame: CGRect(origin: .zero, size: container))
            if let superview = pane.superview {
                pane.outlineFrameBeforeMaximizing = FloatingPaneGeometry.fromVisual(
                    frame,
                    containerHeight: container.height,
                    containerIsFlipped: superview.isFlipped)
            }
            return
        }
        let grid = wanted.clamped(min: .minimum,
                                  max: FloatingPaneGeometry.maximumGrid(container: container, metrics: metrics))
        let frame = FloatingPaneGeometry.clamp(CGRect(origin: scaled(pending.frame), size: metrics.frameSize(for: grid)),
                                               in: container)
        apply(FloatingPanePlacement(frame: frame, grid: grid), to: pane, session: session)
        pane.desiredGrid = FloatingPaneGeometry.desiredGrid(wanted: wanted, actual: grid)
    }

    // MARK: - Appearance

    /// A float whose session is translucent gets a blur underlay so it stays legible.
    @objc(updateUnderlayOfFloatingPane:session:)
    static func updateUnderlay(_ pane: iTermFloatingPaneView, session: PTYSession) {
        let translucent = (session.textview?.transparencyAlpha ?? 1) < 1
        pane.setBlurUnderlay(enabled: translucent, dark: isDark(session.processedBackgroundColor))
    }

    private static func isDark(_ color: NSColor?) -> Bool {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            return true
        }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance < 0.5
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

    /// Like fit(_:session:toOutlineFrame:), with the frame in visual coordinates (top left origin,
    /// y down) of the container, as the API reports frames.
    @objc(fitFloatingPane:session:toVisualOutlineFrame:)
    static func fit(_ pane: iTermFloatingPaneView, session: PTYSession, toVisualOutlineFrame visualFrame: NSRect) {
        guard let container = pane.superview else {
            return
        }
        fit(pane,
            session: session,
            toOutlineFrame: FloatingPaneGeometry.fromVisual(visualFrame,
                                                            containerHeight: container.bounds.height,
                                                            containerIsFlipped: container.isFlipped))
    }

    /// Makes a float fill its tab, remembering where it was.
    @objc(maximizeFloatingPane:session:)
    static func maximize(_ pane: iTermFloatingPaneView, session: PTYSession) {
        guard !pane.isMaximized, let bounds = pane.superview?.bounds else {
            return
        }
        let saved = pane.outlineFrame
        fit(pane, session: session, toOutlineFrame: bounds)
        pane.outlineFrameBeforeMaximizing = saved
    }

    /// Returns a maximized float to where it was.
    @objc(unmaximizeFloatingPane:session:)
    static func unmaximize(_ pane: iTermFloatingPaneView, session: PTYSession) {
        guard let saved = pane.outlineFrameBeforeMaximizing else {
            return
        }
        pane.outlineFrameBeforeMaximizing = nil
        fit(pane, session: session, toOutlineFrame: saved)
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
        if let pending = pane.pendingRestore {
            pane.pendingRestore = nil
            applyPendingRestore(pending, to: pane, session: session, metrics: metrics, container: container)
            return
        }
        if pane.isMaximized {
            // A maximized float keeps filling its tab.
            let saved = pane.outlineFrameBeforeMaximizing
            fit(pane, session: session, toOutlineFrame: CGRect(origin: .zero, size: container))
            pane.outlineFrameBeforeMaximizing = saved
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
