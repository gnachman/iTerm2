//
//  iTermFloatingPaneView.swift
//  iTerm2SharedARC
//
//  A floating pane: a session that sits above a tab's tiled layout. This wrapper holds the float's
//  outline, shadow and resize band and, inside them, a split view with exactly one child, the
//  session's view.
//
//  The one-child split view keeps PTYTab's many casts of a session view's superview to
//  NSSplitView valid, so swaps (Instant Replay, Filter) work inside a float unchanged. The float's
//  frame and z-order belong to this wrapper. Records about a float must be keyed on the wrapper,
//  never on the session view, which can be swapped out.
//
//  Layout, from the outside in: an invisible resize band, the one-point outline, the split view.
//  The band lies outside the outline so it never covers the terminal, its scroller or a browser.
//  The "outline frame" is what the user sees as the float and what geometry works with; the
//  wrapper's frame is the outline frame grown by the band.
//
//  Moving and resizing are plain mouse event handlers with explicit state, not a modal tracking
//  loop, so tests can drive them with synthesized events.
//

import AppKit

@objc(iTermFloatingPaneViewDelegate)
protocol FloatingPaneViewDelegate: AnyObject {
    /// The session showing in the float, whose grid the float's frame follows.
    func floatingPaneSession(_ pane: iTermFloatingPaneView) -> PTYSession?

    /// Whether the user may move or resize floats now (Lock Layout says no).
    func floatingPaneCanMoveOrResize(_ pane: iTermFloatingPaneView) -> Bool

    /// Whether the user may change the float's size or take it out of the float (by docking or
    /// dragging it out) now. Instant replay, filtering and zoom say no.
    func floatingPaneCanResize(_ pane: iTermFloatingPaneView) -> Bool

    /// A move or resize began or ended.
    func floatingPane(_ pane: iTermFloatingPaneView, dragDidChangeToActive active: Bool)

    /// A live move left the tab, so it becomes an ordinary pane drag (to dock the float, make a
    /// tab or a window of it). `grabPoint` is where the move's mouse-down was, in window
    /// coordinates; the float is back where it was then.
    func floatingPaneWantsPaneDrag(_ pane: iTermFloatingPaneView, grabPointInWindow grabPoint: NSPoint)

    /// The user showed or hid a borderless float's title bar.
    func floatingPaneTitleBarVisibilityDidChange(_ pane: iTermFloatingPaneView)
}

@objc(iTermFloatingPaneView)
final class iTermFloatingPaneView: NSView {
    /// Width of the outline drawn around the float.
    @objc static let outlineWidth: CGFloat = 1

    /// Width of the invisible band around the outline that resizes the float.
    @objc static let resizeBandWidth: CGFloat = 6

    /// How far each arm of a corner's L-shaped part of the band reaches along the edges. Corners
    /// get a bigger target than edges because they are harder to hit.
    static let cornerLength: CGFloat = resizeBandWidth * 4

    /// The float's root: a split view with one child, the session's view.
    @objc let splitView: PTYSplitView

    @objc weak var delegate: FloatingPaneViewDelegate?

    /// The grid this float wanted when it last had to shrink to fit its tab, so it can grow back
    /// when there is room. Nil when it has the grid it wants.
    var desiredGrid: FloatingPaneGrid?

    /// Where the float was, in visual coordinates, before its tab got too small and clamping moved
    /// it, per axis, so it goes back when there is room. Nil on an axis it hasn't been moved along.
    var desiredX: CGFloat?
    var desiredY: CGFloat?

    /// While the float is maximized, the outline frame to return to.
    var outlineFrameBeforeMaximizing: NSRect?

    /// A placement read from a saved arrangement, applied once the float's tab has its real size:
    /// the saved visual frame, the container size it was saved with, (if it was maximized) the
    /// visual frame to return to, and the saved grid.
    struct PendingRestore {
        var frame: CGRect
        var containerSize: CGSize
        var frameBeforeMaximizing: CGRect?
        /// The saved grid. A session made from the arrangement is first sized before it has its
        /// title bar, so its own grid can be a row off.
        var grid: FloatingPaneGrid?
    }
    var pendingRestore: PendingRestore?

    /// tmux hides floats while a pane is zoomed, except ones made to show over zoom. Such a float
    /// still exists; this is not the hide toggle.
    @objc var isHiddenByTmux = false

    /// When this float was hidden (by the toggle or by tmux), seconds since the reference date, or
    /// 0 while it shows. Activity after this decorates the hidden-floats indicator.
    @objc var hiddenSince: TimeInterval = 0

    @objc var isMaximized: Bool {
        return outlineFrameBeforeMaximizing != nil
    }

    @objc var isActive = false {
        didSet {
            outlineView.isActive = isActive
        }
    }

    /// The outline's color while the float is active: the session's border around the active pane,
    /// or nil where its profile doesn't ask for one, so active and inactive floats look alike.
    @objc var activeOutlineColor: NSColor? {
        didSet {
            outlineView.activeColor = activeOutlineColor
        }
    }

    /// A tmux float with pane-border-lines none. tmux reserves no border around it, so there is no
    /// room for a title bar: it is hidden until the user shows it with the toggle, and then it sits
    /// above the content, outside the cells tmux gave the float, covering whatever is there.
    @objc var isBorderless = false {
        didSet {
            guard isBorderless != oldValue else {
                return
            }
            if !isBorderless {
                showsBorderlessTitleBar = false
            }
            updateTrackingAreas()
            updateTitleBarToggle()
        }
    }

    /// Whether the user showed a borderless float's title bar.
    @objc private(set) var showsBorderlessTitleBar = false

    /// Whether the float's session should show its title bar.
    @objc var showsTitleBar: Bool {
        return !isBorderless || showsBorderlessTitleBar
    }

    private let outlineView = FloatingPaneOutlineView()
    private var sizeReadout: NSTextField?
    private var titleBarToggle: NSButton?
    private var hoverTrackingArea: NSTrackingArea?
    private var mouseIsInside = false

    /// Shown under a translucent float's session so it blurs what is beneath it in the window
    /// rather than showing the tiled panes' glyphs through it.
    private var blurUnderlay: NSVisualEffectView?

    // MARK: - Drag state

    private enum DragState {
        case idle
        case moving(startPointInWindow: NSPoint, start: FloatingPanePlacement, hasBegun: Bool)
        case resizing(edges: FloatingPaneEdges, startPointInWindow: NSPoint, start: FloatingPanePlacement)
    }

    private var dragState = DragState.idle

    /// True while a move or resize is under way.
    @objc var isDragging: Bool {
        switch dragState {
        case .idle:
            return false
        case let .moving(_, _, hasBegun):
            return hasBegun
        case .resizing:
            return true
        }
    }

    // MARK: - Init

    /// `outlineFrame` is the float as the user sees it, in the superview's coordinates.
    @objc init(outlineFrame: NSRect, splitView: PTYSplitView) {
        self.splitView = splitView
        super.init(frame: Self.frame(forOutlineFrame: outlineFrame))
        autoresizesSubviews = true

        outlineView.frame = bounds.insetBy(dx: Self.resizeBandWidth, dy: Self.resizeBandWidth)
        outlineView.autoresizingMask = [.width, .height]
        addSubview(outlineView)

        splitView.autoresizingMask = [.width, .height]
        splitView.frame = Self.splitViewFrame(forBounds: bounds)
        addSubview(splitView)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    // MARK: - Frames

    /// The session view currently showing in the float. During Instant Replay or Filter this is the
    /// synthetic session's view.
    @objc var sessionView: SessionView? {
        return splitView.subviews.first as? SessionView
    }

    static func frame(forOutlineFrame outlineFrame: NSRect) -> NSRect {
        return outlineFrame.insetBy(dx: -resizeBandWidth, dy: -resizeBandWidth)
    }

    static func splitViewFrame(forBounds bounds: NSRect) -> NSRect {
        let inset = resizeBandWidth + outlineWidth
        return bounds.insetBy(dx: inset, dy: inset)
    }

    /// The split view's frame for an outline frame, both in the wrapper's superview's coordinates.
    @objc static func splitViewSize(forOutlineSize size: NSSize) -> NSSize {
        return NSSize(width: size.width - 2 * outlineWidth, height: size.height - 2 * outlineWidth)
    }

    /// The float as the user sees it (the outline's outer edge), in the superview's coordinates.
    @objc var outlineFrame: NSRect {
        get {
            return frame.insetBy(dx: Self.resizeBandWidth, dy: Self.resizeBandWidth)
        }
        set {
            frame = Self.frame(forOutlineFrame: newValue)
        }
    }

    // MARK: - Blur underlay

    /// Installs or removes the blur underlay. `dark` forces a dark material for a dark
    /// background; otherwise the system appearance would tint it and wash out a dark terminal.
    @objc(setBlurUnderlayEnabled:dark:)
    func setBlurUnderlay(enabled: Bool, dark: Bool) {
        guard enabled else {
            blurUnderlay?.removeFromSuperview()
            blurUnderlay = nil
            return
        }
        let underlay: NSVisualEffectView
        if let existing = blurUnderlay {
            underlay = existing
        } else {
            underlay = NSVisualEffectView(frame: splitView.frame)
            // Within-window blending blurs the tiled panes, lower floats and any shared background
            // image beneath the float. Behind-window blending would show the desktop instead.
            underlay.blendingMode = .withinWindow
            // Some materials, such as .sheet, are opaque within a window. This one is translucent.
            underlay.material = .hudWindow
            // Always active, so floats do not go flat when the window loses key.
            underlay.state = .active
            underlay.autoresizingMask = [.width, .height]
            addSubview(underlay, positioned: .below, relativeTo: splitView)
            blurUnderlay = underlay
        }
        underlay.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    @objc var hasBlurUnderlay: Bool {
        return blurUnderlay != nil
    }

    // MARK: - Hit testing and cursors

    static func cursor(for edges: FloatingPaneEdges) -> NSCursor {
        if #available(macOS 15, *), let position = frameResizePosition(for: edges) {
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if edges == .left || edges == .right {
            return .resizeLeftRight
        }
        if edges == .top || edges == .bottom {
            return .resizeUpDown
        }
        // Before macOS 15 the diagonal cursors are private, as the window uses them.
        let diagonal = (edges == [.top, .left] || edges == [.bottom, .right])
            ? "_windowResizeNorthWestSouthEastCursor"
            : "_windowResizeNorthEastSouthWestCursor"
        let selector = NSSelectorFromString(diagonal)
        if NSCursor.responds(to: selector),
           let cursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .crosshair
    }

    @available(macOS 15, *)
    private static func frameResizePosition(for edges: FloatingPaneEdges) -> NSCursor.FrameResizePosition? {
        switch edges {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        case [.top, .left]: return .topLeft
        case [.top, .right]: return .topRight
        case [.bottom, .left]: return .bottomLeft
        case [.bottom, .right]: return .bottomRight
        default: return nil
        }
    }

    /// The edges of the float that are flush with its tab's edges. There the band outside the
    /// outline is outside the tab, so it lies just inside the outline instead.
    private var flushEdges: FloatingPaneEdges {
        guard let container = superview else {
            return []
        }
        let outline = outlineFrame
        let bounds = container.bounds
        let tolerance: CGFloat = 0.5
        var result: FloatingPaneEdges = []
        if outline.minX <= bounds.minX + tolerance {
            result.insert(.left)
        }
        if outline.maxX >= bounds.maxX - tolerance {
            result.insert(.right)
        }
        let lowY: FloatingPaneEdges = container.isFlipped ? .top : .bottom
        let highY: FloatingPaneEdges = container.isFlipped ? .bottom : .top
        if outline.minY <= bounds.minY + tolerance {
            result.insert(lowY)
        }
        if outline.maxY >= bounds.maxY - tolerance {
            result.insert(highY)
        }
        return result
    }

    /// How far in from a flush edge the band starts. The window's own resize area takes the first
    /// few points inside its edge, and a tab's edges are often the window's.
    static let flushBandInset: CGFloat = 6

    /// How much of the top of the title bar resizes the top edge of a float flush with the tab's
    /// top. The rest of the title bar moves the float.
    static let flushTopGrabDepth: CGFloat = 2

    /// The rectangle whose border, `resizeBandWidth` deep, is the resize band, in this view's
    /// coordinates: the wrapper's bounds, pulled in on each flush edge past the outline and the
    /// window's own resize area.
    private var bandBounds: NSRect {
        var b = bounds
        let pullIn = Self.resizeBandWidth + Self.flushBandInset
        let flush = flushEdges
        let lowY: FloatingPaneEdges = isFlipped ? .top : .bottom
        let highY: FloatingPaneEdges = isFlipped ? .bottom : .top
        if flush.contains(.left) {
            b.origin.x += pullIn
            b.size.width -= pullIn
        }
        if flush.contains(.right) {
            b.size.width -= pullIn
        }
        if flush.contains(lowY) {
            b.origin.y += pullIn
            b.size.height -= pullIn
        }
        if flush.contains(highY) {
            // The tab's top is usually below the window's title bar or tab bar, out of the window's
            // own resize area, so the band starts right inside the outline. The title bar takes
            // all but its top few points.
            b.size.height -= Self.resizeBandWidth
        }
        return b
    }

    /// The title bar, in this view's coordinates, if it shows, less its top `flushTopGrabDepth`
    /// points. It is the grab handle, so the band that lies inside the outline on a flush edge stays
    /// out of it, except for that sliver along the top.
    private var titleBarRect: NSRect? {
        guard let sessionView, sessionView.showTitle(), let title = sessionView.title, !title.isHidden else {
            return nil
        }
        var rect = title.convert(title.bounds, to: self)
        rect.size.height = max(0, rect.height - Self.flushTopGrabDepth)
        if isFlipped {
            rect.origin.y += Self.flushTopGrabDepth
        }
        return rect
    }

    /// `rect` with any part over the title bar removed. The title bar spans the float's width at its
    /// top, so this cuts the rect off where the title bar begins.
    private func excludingTitleBar(_ rect: NSRect) -> NSRect {
        guard let title = titleBarRect, rect.intersects(title) else {
            return rect
        }
        var result = rect
        if isFlipped {
            let top = max(rect.minY, title.maxY)
            result.size.height = max(0, rect.maxY - top)
            result.origin.y = top
        } else {
            result.size.height = max(0, min(rect.maxY, title.minY) - rect.minY)
        }
        return result
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let b = bandBounds
        let band = Self.resizeBandWidth
        let corner = Self.cornerLength
        let lowY: FloatingPaneEdges = isFlipped ? .top : .bottom
        let highY: FloatingPaneEdges = isFlipped ? .bottom : .top
        // Later rects win where they overlap, so corners go last.
        let rects: [(NSRect, FloatingPaneEdges)] = [
            (NSRect(x: b.minX, y: b.minY, width: band, height: b.height), .left),
            (NSRect(x: b.maxX - band, y: b.minY, width: band, height: b.height), .right),
            (NSRect(x: b.minX, y: b.minY, width: b.width, height: band), lowY),
            (NSRect(x: b.minX, y: b.maxY - band, width: b.width, height: band), highY),
            (NSRect(x: b.minX, y: b.minY, width: corner, height: band), [.left, lowY]),
            (NSRect(x: b.minX, y: b.minY, width: band, height: corner), [.left, lowY]),
            (NSRect(x: b.maxX - corner, y: b.minY, width: corner, height: band), [.right, lowY]),
            (NSRect(x: b.maxX - band, y: b.minY, width: band, height: corner), [.right, lowY]),
            (NSRect(x: b.minX, y: b.maxY - band, width: corner, height: band), [.left, highY]),
            (NSRect(x: b.minX, y: b.maxY - corner, width: band, height: corner), [.left, highY]),
            (NSRect(x: b.maxX - corner, y: b.maxY - band, width: corner, height: band), [.right, highY]),
            (NSRect(x: b.maxX - band, y: b.maxY - corner, width: band, height: corner), [.right, highY]),
        ]
        for (rect, edges) in rects {
            let clipped = excludingTitleBar(rect)
            if !clipped.isEmpty {
                addCursorRect(clipped, cursor: Self.cursor(for: edges))
            }
        }
    }

    /// The edges a mouse-down at `point` (in this view's coordinates) resizes, or none if it is not
    /// in the band. The band is L-shaped near each corner, `cornerLength` long, and there both edges
    /// move, matching the cursor rects.
    func edges(at point: NSPoint) -> FloatingPaneEdges {
        let b = bandBounds
        let band = Self.resizeBandWidth
        guard b.contains(point),
              !b.insetBy(dx: band, dy: band).contains(point),
              !(titleBarRect?.contains(point) ?? false) else {
            return []
        }
        let corner = Self.cornerLength
        let lowY: FloatingPaneEdges = isFlipped ? .top : .bottom
        let highY: FloatingPaneEdges = isFlipped ? .bottom : .top
        let inLeftBand = point.x < b.minX + band
        let inRightBand = point.x >= b.maxX - band
        let inLowBand = point.y < b.minY + band
        let inHighBand = point.y >= b.maxY - band
        let nearLeft = point.x < b.minX + corner
        let nearRight = point.x >= b.maxX - corner
        let nearLow = point.y < b.minY + corner
        let nearHigh = point.y >= b.maxY - corner
        var result: FloatingPaneEdges = []
        if inLeftBand || (nearLeft && (inLowBand || inHighBand)) {
            result.insert(.left)
        }
        if inRightBand || (nearRight && (inLowBand || inHighBand)) {
            result.insert(.right)
        }
        if inLowBand || (nearLow && (inLeftBand || inRightBand)) {
            result.insert(lowY)
        }
        if inHighBand || (nearHigh && (inLeftBand || inRightBand)) {
            result.insert(highY)
        }
        return result
    }

    /// Whether a window point is in the resize band, for views beneath that must not treat it as
    /// theirs.
    @objc(resizeBandContainsWindowPoint:)
    func resizeBandContains(windowPoint: NSPoint) -> Bool {
        return !edges(at: convert(windowPoint, from: nil)).isEmpty
    }

    /// While picking a pane to swap this float with, it is translucent and clicks go through it to
    /// the panes and floats it covers, except on its title bar, where a click cancels.
    @objc var isSourceOfSwapPicking = false {
        didSet {
            alphaValue = isSourceOfSwapPicking ? 0.35 : 1
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isSourceOfSwapPicking {
            guard let title = sessionView?.title,
                  title.bounds.contains(title.convert(point, from: superview)) else {
                return nil
            }
            return super.hitTest(point)
        }
        // On a flush edge the band lies over the float's own content, which would otherwise get the
        // click. `point` is in the superview's coordinates.
        if !isHidden, !flushEdges.isEmpty, !edges(at: convert(point, from: superview)).isEmpty {
            return self
        }
        return super.hitTest(point)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Which edges are flush can change, and with them where the band is.
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        window?.invalidateCursorRects(for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Resizing (mouse events in the band)

    override func mouseDown(with event: NSEvent) {
        let edges = self.edges(at: convert(event.locationInWindow, from: nil))
        guard !edges.isEmpty else {
            super.mouseDown(with: event)
            return
        }
        beginResize(edges: edges, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        switch dragState {
        case .idle:
            super.mouseDragged(with: event)
        case .moving:
            continueMove(event: event)
        case .resizing:
            continueResize(event: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .idle = dragState {
            super.mouseUp(with: event)
            return
        }
        endDrag()
    }

    private func currentPlacement() -> (FloatingPanePlacement, PTYSession)? {
        guard let session = delegate?.floatingPaneSession(self),
              let placement = FloatingPaneLayout.placement(of: self, session: session) else {
            return nil
        }
        return (placement, session)
    }

    private func beginResize(edges: FloatingPaneEdges, event: NSEvent) {
        guard delegate?.floatingPaneCanResize(self) ?? false,
              let (placement, session) = currentPlacement() else {
            return
        }
        DLog("Begin resize of \(edges.rawValue) for \(session)")
        dragState = .resizing(edges: edges, startPointInWindow: event.locationInWindow, start: placement)
        delegate?.floatingPane(self, dragDidChangeToActive: true)
        showSizeReadout(placement.grid)
    }

    private func visualDelta(from start: NSPoint, to end: NSPoint) -> CGSize {
        // Window coordinates have y up; visual coordinates have y down.
        return CGSize(width: end.x - start.x, height: start.y - end.y)
    }

    private func continueResize(event: NSEvent) {
        guard case let .resizing(edges, startPoint, start) = dragState,
              let session = delegate?.floatingPaneSession(self),
              let metrics = FloatingPaneLayout.metrics(for: session),
              let container = superview?.bounds.size else {
            return
        }
        let result = FloatingPaneGeometry.resize(start,
                                                 edges: edges,
                                                 by: visualDelta(from: startPoint, to: event.locationInWindow),
                                                 in: container,
                                                 metrics: metrics)
        FloatingPaneLayout.apply(result, to: self, session: session)
        desiredGrid = nil
        showSizeReadout(result.grid)
    }

    // MARK: - Moving (mouse events forwarded from the title bar)

    /// Whether a drag that can't move the float may start a pane drag instead, which docks the float
    /// or takes it to another tab or window. Not when the float can't leave its place, as in tmux
    /// 3.7, which has no commands to move a float; then dragging does nothing.
    @objc var allowsPaneDrag: Bool {
        return delegate?.floatingPaneCanResize(self) ?? false
    }

    /// The title bar's mouse-down. Returns whether a move may follow.
    @objc(titleBarMouseDown:)
    func titleBarMouseDown(_ event: NSEvent) -> Bool {
        guard delegate?.floatingPaneCanMoveOrResize(self) ?? false,
              let (placement, _) = currentPlacement() else {
            return false
        }
        dragState = .moving(startPointInWindow: event.locationInWindow, start: placement, hasBegun: false)
        return true
    }

    /// The title bar's mouse-dragged. Returns whether it was handled as a move.
    @objc(titleBarMouseDragged:)
    func titleBarMouseDragged(_ event: NSEvent) -> Bool {
        guard case .moving = dragState else {
            return false
        }
        continueMove(event: event)
        return true
    }

    /// The title bar's mouse-up. Returns whether it ended a move that actually moved.
    @objc(titleBarMouseUp:)
    func titleBarMouseUp(_ event: NSEvent) -> Bool {
        guard case let .moving(_, _, hasBegun) = dragState else {
            return false
        }
        endDrag()
        return hasBegun
    }

    private func continueMove(event: NSEvent) {
        guard case let .moving(startPoint, start, hasBegun) = dragState,
              let session = delegate?.floatingPaneSession(self),
              let container = superview?.bounds.size else {
            return
        }
        if !hasBegun {
            dragState = .moving(startPointInWindow: startPoint, start: start, hasBegun: true)
            delegate?.floatingPane(self, dragDidChangeToActive: true)
        }
        let leftTheTab = superview.map {
            !$0.bounds.contains($0.convert(event.locationInWindow, from: nil))
        } ?? false
        if (leftTheTab || event.modifierFlags.contains(.control)) && delegate?.floatingPaneCanResize(self) ?? false {
            // Leaving the tab, or pressing Control during the move (to dock the float into its own
            // tab), escalates to the pane drag, which shows split halves and can dock the float or
            // move it to another tab or window.
            DLog("Live move escalates to a pane drag")
            FloatingPaneLayout.apply(start, to: self, session: session)
            endDrag()
            delegate?.floatingPaneWantsPaneDrag(self, grabPointInWindow: startPoint)
            return
        }
        let frame = FloatingPaneGeometry.move(start.frame,
                                              by: visualDelta(from: startPoint, to: event.locationInWindow),
                                              in: container)
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: frame, grid: start.grid), to: self, session: session)
        // The legacy renderer draws a slice of a shared background image chosen by position. Redraw so
        // the slice moves with the float instead of snapping back later.
        session.textview?.requestDelegateRedraw()
    }

    private func endDrag() {
        let wasActive = isDragging
        dragState = .idle
        hideSizeReadout()
        // Rendering switches back from the drag's mode afterward. Draw a fresh frame, or one made
        // while the readout was showing can stay on screen until the content changes.
        delegate?.floatingPaneSession(self)?.textview?.requestDelegateRedraw()
        window?.invalidateCursorRects(for: self)
        if wasActive {
            delegate?.floatingPane(self, dragDidChangeToActive: false)
        }
    }

    // MARK: - Borderless title bar toggle

    /// Shows or hides a borderless float's title bar.
    @objc(toggleBorderlessTitleBar:)
    func toggleBorderlessTitleBar(_ sender: Any?) {
        guard isBorderless else {
            return
        }
        showsBorderlessTitleBar.toggle()
        DLog("Borderless float title bar shown=\(showsBorderlessTitleBar)")
        delegate?.floatingPaneTitleBarVisibilityDidChange(self)
        updateTitleBarToggle()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }
        guard isBorderless else {
            mouseIsInside = false
            return
        }
        // The toggle appears only while the mouse is over the float, so it doesn't permanently
        // cover the float's top row.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === hoverTrackingArea, hoverTrackingArea != nil else {
            super.mouseEntered(with: event)
            return
        }
        mouseIsInside = true
        updateTitleBarToggle()
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hoverTrackingArea, hoverTrackingArea != nil else {
            super.mouseExited(with: event)
            return
        }
        mouseIsInside = false
        updateTitleBarToggle()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateTitleBarToggle()
    }

    /// The float's content (its scroll view) in this view's coordinates.
    private var contentRect: NSRect? {
        guard let scrollview = sessionView?.scrollview else {
            return nil
        }
        return scrollview.convert(scrollview.bounds, to: self)
    }

    /// Whether a title bar above the content would be inside the tab. A borderless float in the top
    /// row has none, and its title bar can't be shown.
    private var hasRoomForTitleBarAbove: Bool {
        guard let container = superview, let scrollview = sessionView?.scrollview else {
            return false
        }
        let rect = scrollview.convert(scrollview.bounds, to: container)
        let top = container.isFlipped ? rect.minY : container.bounds.height - rect.maxY
        let titleHeight = showsBorderlessTitleBar ? 0 : CGFloat(SessionView.titleHeight())
        return top >= titleHeight
    }

    /// Whether the toggle is showing, for tests.
    @objc var titleBarToggleIsVisible: Bool {
        return titleBarToggle.map { !$0.isHidden } ?? false
    }

    /// Shows, hides and positions the toggle. It sits at the top center of the content: under the
    /// title bar when the title bar shows, over the first row when it doesn't.
    @objc func updateTitleBarToggle() {
        guard isBorderless,
              mouseIsInside,
              hasRoomForTitleBarAbove,
              let content = contentRect else {
            titleBarToggle?.isHidden = true
            return
        }
        let toggle = titleBarToggle ?? makeTitleBarToggle()
        let description: String
        let symbol: SFSymbol
        if showsBorderlessTitleBar {
            symbol = .chevronCompactUp
            description = String(localized: "FloatingPane.HideTitleBar",
                                 defaultValue: "Hide Title Bar",
                                 comment: "Tooltip and accessibility description for a button on a floating pane with no border that hides the pane’s title bar")
        } else {
            symbol = .chevronCompactDown
            description = String(localized: "FloatingPane.ShowTitleBar",
                                 defaultValue: "Show Title Bar",
                                 comment: "Tooltip and accessibility description for a button on a floating pane with no border that shows the pane’s title bar above it")
        }
        toggle.image = NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: description)
        toggle.toolTip = description
        // A terminal's colors are arbitrary, so the toggle brings its own background.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            toggle.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        }
        let size = NSSize(width: 28, height: 12)
        let y = isFlipped ? content.minY : content.maxY - size.height
        toggle.frame = NSRect(x: content.midX - size.width / 2, y: y, width: size.width, height: size.height).integral
        toggle.isHidden = false
    }

    private func makeTitleBarToggle() -> NSButton {
        let toggle = NSButton(frame: .zero)
        toggle.isBordered = false
        toggle.imagePosition = .imageOnly
        toggle.contentTintColor = .secondaryLabelColor
        toggle.wantsLayer = true
        toggle.layer?.cornerRadius = 4
        toggle.target = self
        toggle.action = #selector(toggleBorderlessTitleBar(_:))
        addSubview(toggle, positioned: .above, relativeTo: nil)
        titleBarToggle = toggle
        return toggle
    }

    // MARK: - Size readout

    private func showSizeReadout(_ grid: FloatingPaneGrid) {
        let readout: NSTextField
        if let existing = sizeReadout {
            readout = existing
        } else {
            readout = NSTextField(labelWithString: "")
            readout.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            readout.textColor = .labelColor
            readout.drawsBackground = true
            readout.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85)
            readout.alignment = .center
            addSubview(readout)
            sizeReadout = readout
        }
        // Localization unneeded: numbers and a multiplication sign only.
        readout.stringValue = "\(grid.columns)×\(grid.rows)"
        readout.sizeToFit()
        var frame = readout.frame
        frame.size.width += 12
        frame.size.height += 4
        frame.origin = NSPoint(x: (bounds.width - frame.width) / 2, y: (bounds.height - frame.height) / 2)
        readout.frame = frame.integral
    }

    private func hideSizeReadout() {
        sizeReadout?.removeFromSuperview()
        sizeReadout = nil
    }

    /// The text of the size readout while resizing, for tests.
    @objc var sizeReadoutText: String? {
        return sizeReadout?.stringValue
    }
}

/// The float's one-point outline and its shadow. It is not hit-testable.
private final class FloatingPaneOutlineView: NSView {
    var isActive = false {
        didSet {
            updateColors()
        }
    }

    var activeColor: NSColor? {
        didSet {
            updateColors()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = iTermFloatingPaneView.outlineWidth
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        updateColors()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // An explicit shadow path keeps the shadow cheap during live moves.
        layer?.shadowPath = CGPath(rect: bounds, transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let color = (isActive ? activeColor : nil) ?? NSColor.separatorColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = color.cgColor
        }
    }
}
