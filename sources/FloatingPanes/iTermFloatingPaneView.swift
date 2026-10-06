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

    /// A move or resize began or ended.
    func floatingPane(_ pane: iTermFloatingPaneView, dragDidChangeToActive active: Bool)
}

@objc(iTermFloatingPaneView)
final class iTermFloatingPaneView: NSView {
    /// Width of the outline drawn around the float.
    @objc static let outlineWidth: CGFloat = 1

    /// Width of the invisible band around the outline that resizes the float.
    @objc static let resizeBandWidth: CGFloat = 4

    /// The float's root: a split view with one child, the session's view.
    @objc let splitView: PTYSplitView

    @objc weak var delegate: FloatingPaneViewDelegate?

    /// The grid this float wanted when it last had to shrink to fit its tab, so it can grow back
    /// when there is room. Nil when it has the grid it wants.
    var desiredGrid: FloatingPaneGrid?

    /// While the float is maximized, the outline frame to return to.
    var outlineFrameBeforeMaximizing: NSRect?

    @objc var isMaximized: Bool {
        return outlineFrameBeforeMaximizing != nil
    }

    @objc var isActive = false {
        didSet {
            outlineView.isActive = isActive
        }
    }

    private let outlineView = FloatingPaneOutlineView()
    private var sizeReadout: NSTextField?

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

    private static func cursor(for edges: FloatingPaneEdges) -> NSCursor {
        if edges == .left || edges == .right {
            return .resizeLeftRight
        }
        if edges == .top || edges == .bottom {
            return .resizeUpDown
        }
        return .crosshair
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let b = bounds
        let band = Self.resizeBandWidth
        let corner = band * 3
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
            addCursorRect(rect, cursor: Self.cursor(for: edges))
        }
    }

    /// The edges a mouse-down at `point` (in this view's coordinates) resizes, or none if it is not
    /// in the band. The band is L-shaped near each corner, three bands long, and there both edges
    /// move, matching the cursor rects.
    func edges(at point: NSPoint) -> FloatingPaneEdges {
        let b = bounds
        let band = Self.resizeBandWidth
        guard b.contains(point), !b.insetBy(dx: band, dy: band).contains(point) else {
            return []
        }
        let corner = band * 3
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
        guard delegate?.floatingPaneCanMoveOrResize(self) ?? false,
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
        window?.invalidateCursorRects(for: self)
        if wasActive {
            delegate?.floatingPane(self, dragDidChangeToActive: false)
        }
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
        let color = isActive ? NSColor.controlAccentColor : NSColor.separatorColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = color.cgColor
        }
    }
}
