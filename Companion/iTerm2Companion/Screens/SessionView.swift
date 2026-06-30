//
//  SessionView.swift
//  iTerm2 Companion
//
//  A read-only view of one terminal session's contents, reached by tapping an
//  @-mention in a chat. The Mac renders slices of the session's scrollback to
//  bitmaps on demand; this view sizes a scrollable canvas from the session's
//  geometry (line count and cell size) and fetches each slice lazily as it
//  scrolls into view.
//
//  Scrolling and zooming are a real UIScrollView (via SessionContentZoomView)
//  because UIKit's built-in zooming anchors at the pinch centroid, which
//  SwiftUI gestures don't give you. Tile visibility (and therefore lazy
//  fetching) is computed from the scroll view's visible rect.
//

import SwiftUI
import CoreImage
import CompanionProtocol

struct SessionView: View {
    @Environment(AppModel.self) private var model
    let guid: String
    let title: String
    /// When false, the "chat about this session" toolbar button is hidden. The
    /// mention picker shows this view only to preview a session, where starting
    /// a chat would push onto the stack behind the picker sheet.
    var allowsChat: Bool = true

    /// Lines per fetched tile: large enough to amortize round trips, small
    /// enough that each tile's PNG stays a lightweight frame.
    private static let linesPerTile = 50

    @State private var info: CompanionSessionScreenInfo?
    /// Fetched tile bitmaps, keyed by the tile's first line.
    @State private var tiles: [Int: UIImage] = [:]
    /// Tiles whose fetch failed; they show a tap-to-retry affordance.
    @State private var failedTiles: Set<Int> = []
    /// Tiles with a fetch in flight, so scroll events don't duplicate them.
    @State private var inFlightTiles: Set<Int> = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if model.macSupportsStreaming {
                // Live follow-mode video of the visible screen. Scrollback
                // browsing stays on the tile path (a later milestone).
                LiveSessionView(guid: guid)
            } else {
                tileContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsChat {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.openOrCreateChat(forSessionGuid: guid)
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                    .accessibilityLabel("Chat about this session")
                }
            }
            if !model.macSupportsStreaming {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(info == nil && loadError == nil)
                }
            }
        }
        .task(id: guid) {
            if !model.macSupportsStreaming {
                await load()
            }
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        Group {
            if let info {
                SessionContentZoomView(info: info,
                                       linesPerTile: Self.linesPerTile,
                                       tiles: tiles,
                                       failedTiles: failedTiles,
                                       requestTile: { firstLine in
                                           // May be invoked mid render pass
                                           // (updateUIView); defer the state
                                           // mutations a tick.
                                           Task { @MainActor in
                                               loadTile(firstLine: firstLine)
                                           }
                                       },
                                       retryTile: { firstLine in
                                           failedTiles.remove(firstLine)
                                           loadTile(firstLine: firstLine)
                                       })
                .ignoresSafeArea(edges: .bottom)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Can’t Show Session", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { reload() }
                }
            } else {
                ProgressView("Loading session…")
            }
        }
    }

    private func load() async {
        do {
            let info = try await model.sessionScreenInfo(guid: guid)
            companionLog("Session \(guid): \(info.lineCount) lines, \(info.columns) columns")
            self.info = info
            loadError = nil
        } catch {
            companionLog("Session info failed: \(String(describing: error))")
            loadError = model.userMessage(for: error)
        }
    }

    /// Content is a snapshot; refresh refetches the geometry and drops every
    /// cached tile so the next render shows current contents.
    private func reload() {
        info = nil
        tiles = [:]
        failedTiles = []
        inFlightTiles = []
        loadError = nil
        Task { await load() }
    }

    private func loadTile(firstLine: Int) {
        guard let info,
              tiles[firstLine] == nil,
              !failedTiles.contains(firstLine),
              !inFlightTiles.contains(firstLine) else {
            return
        }
        let lineCount = min(Self.linesPerTile, info.lineCount - firstLine)
        guard lineCount > 0 else { return }
        inFlightTiles.insert(firstLine)
        Task {
            defer { inFlightTiles.remove(firstLine) }
            do {
                let content = try await model.sessionContent(guid: guid,
                                                             firstLine: firstLine,
                                                             lineCount: lineCount)
                guard let image = UIImage(data: content.pngData) else {
                    companionLog("Tile at line \(firstLine): undecodable image")
                    failedTiles.insert(firstLine)
                    return
                }
                tiles[firstLine] = image
            } catch {
                companionLog("Tile at line \(firstLine) failed: \(String(describing: error))")
                failedTiles.insert(firstLine)
            }
        }
    }
}

/// A UIScrollView that scrolls and pinch-zooms the session canvas with
/// UIKit's native behavior (centroid-anchored zoom, bounce, double-tap), and
/// materializes tile subviews only around the visible rect so fetching stays
/// lazy.
private struct SessionContentZoomView: UIViewRepresentable {
    let info: CompanionSessionScreenInfo
    let linesPerTile: Int
    let tiles: [Int: UIImage]
    let failedTiles: Set<Int>
    let requestTile: (Int) -> Void
    let retryTile: (Int) -> Void

    /// Zoom stops when one Mac pixel covers this many iPhone pixels. 1 means
    /// the bitmaps' native resolution is the ceiling; higher values allow
    /// upscaling past it. Tune to taste.
    static let maxiPhonePixelsPerMacPixel: CGFloat = 4

    func makeUIView(context: Context) -> LayoutObservingScrollView {
        let scrollView = LayoutObservingScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4  // placeholder; sized from content geometry on layout
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .systemBackground

        let contentView = UIView()
        scrollView.addSubview(contentView)

        context.coordinator.scrollView = scrollView
        context.coordinator.contentView = contentView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.viewportDidLayout()
        }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(tap)

        return scrollView
    }

    func updateUIView(_ scrollView: LayoutObservingScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refreshTiles()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: SessionContentZoomView
        weak var scrollView: UIScrollView?
        weak var contentView: UIView?

        private var tileViews: [Int: TileView] = [:]
        private var requested: Set<Int> = []
        private var layoutWidth: CGFloat = 0
        private var didScrollToBottom = false

        init(parent: SessionContentZoomView) {
            self.parent = parent
        }

        // MARK: Geometry

        private var pointsPerLine: CGFloat {
            guard parent.info.width > 0 else { return 1 }
            return parent.info.lineHeight * layoutWidth / parent.info.width
        }

        private func tileFrame(firstLine: Int) -> CGRect {
            let lineCount = min(parent.linesPerTile, parent.info.lineCount - firstLine)
            return CGRect(x: 0,
                          y: CGFloat(firstLine) * pointsPerLine,
                          width: layoutWidth,
                          height: CGFloat(lineCount) * pointsPerLine)
        }

        /// Called from layoutSubviews: adopt the viewport width (initially,
        /// and again on rotation) and size the canvas from it.
        func viewportDidLayout() {
            guard let scrollView, let contentView else { return }
            let width = scrollView.bounds.width
            guard width > 0, width != layoutWidth else { return }
            layoutWidth = width
            scrollView.zoomScale = 1
            // Allow zooming until one Mac pixel covers N iPhone pixels. At
            // zoom z the canvas spans width * z * displayScale iPhone pixels
            // across info.width * info.scale Mac pixels; solve for z.
            let macPixelWidth = CGFloat(parent.info.width * parent.info.scale)
            let displayScale = max(1, scrollView.traitCollection.displayScale)
            scrollView.maximumZoomScale = max(
                1, SessionContentZoomView.maxiPhonePixelsPerMacPixel * macPixelWidth / (width * displayScale))
            let height = CGFloat(parent.info.lineCount) * pointsPerLine
            contentView.frame = CGRect(x: 0, y: 0, width: width, height: height)
            scrollView.contentSize = contentView.frame.size
            for (firstLine, view) in tileViews {
                view.frame = tileFrame(firstLine: firstLine)
            }
            if !didScrollToBottom {
                didScrollToBottom = true
                let bottom = max(-scrollView.adjustedContentInset.top,
                                 height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                scrollView.contentOffset = CGPoint(x: 0, y: bottom)
            }
            refreshTiles()
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            refreshTiles()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            refreshTiles()
        }

        // MARK: Tiles

        /// Materialize tile views around the visible rect (one viewport of
        /// lookahead each way), drop ones that scrolled far away, and apply
        /// the latest fetched images / failure states.
        func refreshTiles() {
            guard let scrollView, let contentView, layoutWidth > 0 else { return }
            let visible = scrollView.convert(scrollView.bounds, to: contentView)
            let keepRect = visible.insetBy(dx: 0, dy: -visible.height)

            let tileHeight = CGFloat(parent.linesPerTile) * pointsPerLine
            guard tileHeight > 0 else { return }
            let tileCount = max(1, (parent.info.lineCount + parent.linesPerTile - 1) / parent.linesPerTile)
            let firstIndex = max(0, Int(floor(keepRect.minY / tileHeight)))
            let lastIndex = min(tileCount - 1, Int(floor(keepRect.maxY / tileHeight)))
            guard firstIndex <= lastIndex else { return }

            for index in firstIndex...lastIndex {
                let firstLine = index * parent.linesPerTile
                let view: TileView
                if let existing = tileViews[firstLine] {
                    view = existing
                } else {
                    view = TileView()
                    view.frame = tileFrame(firstLine: firstLine)
                    contentView.addSubview(view)
                    tileViews[firstLine] = view
                }
                if let image = parent.tiles[firstLine] {
                    view.show(image: image)
                } else if parent.failedTiles.contains(firstLine) {
                    view.showFailure()
                    requested.remove(firstLine)
                } else {
                    view.showLoading()
                    if !requested.contains(firstLine) {
                        requested.insert(firstLine)
                        parent.requestTile(firstLine)
                    }
                }
            }

            // Drop views far outside the keep rect; their images stay cached
            // in the SwiftUI layer, so scrolling back is instant.
            let discardRect = visible.insetBy(dx: 0, dy: -3 * visible.height)
            for (firstLine, view) in tileViews where !view.frame.intersects(discardRect) {
                view.removeFromSuperview()
                tileViews[firstLine] = nil
            }
        }

        // MARK: Gestures

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let contentView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                // Zoom to 2x around the tapped point, like Photos.
                let point = gesture.location(in: contentView)
                let scale: CGFloat = 2
                let size = CGSize(width: scrollView.bounds.width / scale,
                                  height: scrollView.bounds.height / scale)
                let origin = CGPoint(x: point.x - size.width / 2,
                                     y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let contentView else { return }
            let point = gesture.location(in: contentView)
            for (firstLine, view) in tileViews where view.frame.contains(point) {
                if parent.failedTiles.contains(firstLine) {
                    parent.retryTile(firstLine)
                }
                return
            }
        }
    }
}

/// UIScrollView that reports layout passes, so the coordinator can size the
/// canvas once the viewport width is known (and re-size it on rotation).
private final class LayoutObservingScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// One slice of the canvas: the fetched bitmap when available, otherwise a
/// spinner, or a tap-to-retry hint after a failed fetch.
private final class TileView: UIView {
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        addSubview(spinner)
        retryLabel.text = "Couldn’t load this part. Tap to retry."
        retryLabel.font = .preferredFont(forTextStyle: .footnote)
        retryLabel.textColor = .secondaryLabel
        retryLabel.textAlignment = .center
        retryLabel.isHidden = true
        addSubview(retryLabel)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        retryLabel.frame = bounds.insetBy(dx: 12, dy: 0)
    }

    func show(image: UIImage) {
        imageView.image = image
        imageView.isHidden = false
        retryLabel.isHidden = true
        spinner.stopAnimating()
    }

    func showLoading() {
        guard imageView.image == nil else { return }
        imageView.isHidden = true
        retryLabel.isHidden = true
        if !spinner.isAnimating {
            spinner.startAnimating()
        }
    }

    func showFailure() {
        imageView.isHidden = true
        retryLabel.isHidden = false
        spinner.stopAnimating()
    }
}

// MARK: - Live streaming

/// Live follow-mode video of a session's visible screen, played through an
/// AVSampleBufferDisplayLayer. Starts the stream on appear, stops it on
/// disappear or backgrounding, and re-subscribes (with a fresh keyframe) on
/// resume. Scrollback browsing is not available here (a later milestone).
private struct LiveSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let guid: String

    @State private var holder = LiveVideoHolder()
    @State private var resolution: String?
    @State private var endedReason: CompanionStreamEndReason?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Zoomable/scrollable canvas hosting the live video, with long-press
            // selection (Safari model). History tiles and draggable handles are
            // added in later M5 steps.
            // Passing the selection range (read here) makes SwiftUI re-run
            // updateUIView when it changes, so the canvas repositions its handles.
            LiveCanvas(holder: holder, model: model, selectionRange: model.activeSelectionRange)
                .ignoresSafeArea(edges: .bottom)
            VStack {
                HStack {
                    liveBadge
                    Spacer()
                }
                Spacer()
            }
            .padding()
            if let endedReason {
                ContentUnavailableView {
                    Label("Stream Ended", systemImage: "stop.circle")
                } description: {
                    Text(endedMessage(endedReason))
                }
            }
        }
        // A left-edge drag would otherwise trigger the swipe-back gesture instead
        // of starting a selection there. Disable swipe-back while selection is
        // available; the back button still works.
        .background {
            if model.sessionSelectionSupported {
                SwipeBackDisabler()
            }
        }
        .task(id: guid) { start() }
        .onDisappear { model.stopWatchingSessionLive() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                companionLog("CDIAG SessionView scenePhase active -> resumeLiveStream")
                model.resumeLiveStream()
            case .background:
                companionLog("CDIAG SessionView scenePhase background -> pauseLiveStream")
                model.pauseLiveStream()
            default: break
            }
        }
    }

    @ViewBuilder private var liveBadge: some View {
        if endedReason == nil {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(resolution.map { "LIVE  \($0)" } ?? "LIVE")
                    .font(.caption2.monospaced())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
        }
    }

    private func start() {
        endedReason = nil
        holder.view.onNeedsKeyframe = { [weak model] in model?.requestActiveStreamKeyframe() }
        model.watchSessionLive(
            guid: guid,
            onConfig: { config in
                resolution = "\(config.pixelWidth)×\(config.pixelHeight)"
                if let parameterSets = try? CompanionHEVCFraming.decodeParameterSets(config.codecExtradata) {
                    holder.view.configure(parameterSets: parameterSets)
                }
            },
            onMedia: { [weak model] frame in
                holder.view.enqueue(accessUnit: frame.payload, ptsMilliseconds: frame.ptsMilliseconds)
                model?.sendActiveStreamAck(lastPTSMilliseconds: frame.ptsMilliseconds, queueDepth: 0)
            },
            onEnded: { reason in
                // Only a terminal host-side end reaches here; a transient
                // disconnect restarts silently. Surface only the cases worth
                // telling the user about.
                switch reason {
                case .sessionClosed, .error, .dataLimitReached:
                    endedReason = reason
                case .stoppedByClient, .superseded:
                    break
                }
            })
    }

    private func endedMessage(_ reason: CompanionStreamEndReason) -> String {
        switch reason {
        case .sessionClosed: return "The session is no longer available."
        case .stoppedByClient, .superseded: return "The live view stopped."
        case .error: return "The live view ended unexpectedly."
        case .dataLimitReached: return "Live view paused to stay within data limits."
        }
    }
}

/// Holds the AVSampleBufferDisplayLayer-backed view across SwiftUI updates.
private final class LiveVideoHolder {
    let view = CompanionVideoView(frame: .zero)
}

/// A draggable selection-endpoint dot. The view is larger than the dot so the
/// touch target is comfortable; the dot is drawn centered.
private final class SelectionHandleView: UIView {
    private let dotDiameter: CGFloat = 18

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { it_fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let dot = CGRect(x: bounds.midX - dotDiameter / 2, y: bounds.midY - dotDiameter / 2,
                         width: dotDiameter, height: dotDiameter)
        UIColor.white.setFill()
        ctx.fillEllipse(in: dot)
        UIColor.systemBlue.setStroke()
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: dot.insetBy(dx: 1, dy: 1))
    }
}

private final class LoupeUIView: UIView {
    var pixelBufferProvider: (() -> CVPixelBuffer?)?
    var imagePoint: CGPoint = .zero   // center, image px, top-left origin
    var cropSide: CGFloat = 80        // image px shown across the loupe
    var cellHeight: CGFloat = 0       // image px, for sizing the handle caret
    private let ciContext = CIContext(options: nil)
    private var displayLink: CADisplayLink?

    // The loupe must re-sample the latest decoded frame every refresh, not only
    // when the finger moves: after the finger stops, new frames keep arriving (the
    // selection catches up) and the loupe would otherwise keep showing the stale
    // frame it last sampled on a gesture event. A display link drives the redraw
    // while the loupe is on screen.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(redrawFromDisplayLink))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @objc private func redrawFromDisplayLink() {
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    override func draw(_ rect: CGRect) {
        guard let pixelBuffer = pixelBufferProvider?(), cropSide > 0 else { return }
        // CIImage uses a bottom-left origin; clamp to the edges so a crop near the
        // border extends rather than going transparent.
        let base = CIImage(cvPixelBuffer: pixelBuffer)
        let imageHeight = base.extent.height
        let ciImage = base.clampedToExtent()
        let half = cropSide / 2
        let ciRect = CGRect(x: imagePoint.x - half,
                            y: imageHeight - (imagePoint.y + half),
                            width: cropSide, height: cropSide)
        if let cropped = ciContext.createCGImage(ciImage, from: ciRect) {
            UIImage(cgImage: cropped).draw(in: bounds)  // scales the crop to fill the circle
        }
        drawHandleMarker()
    }

    /// The dragged endpoint tracks the finger, which is the loupe center, so draw
    /// the handle there: a vertical caret one (magnified) cell tall with a knob,
    /// matching the on-screen selection handle, so it appears inside the magnifier.
    private func drawHandleMarker() {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // One image cell maps to this many points in the loupe.
        let caretHeight = cellHeight > 0 ? bounds.height * cellHeight / cropSide : bounds.height / 4
        let caretWidth: CGFloat = 2
        let caretRect = CGRect(x: center.x - caretWidth / 2, y: center.y - caretHeight / 2,
                               width: caretWidth, height: caretHeight)
        UIColor.systemBlue.setFill()
        ctx.fill(caretRect)
        let knobRadius: CGFloat = 5
        let knobRect = CGRect(x: center.x - knobRadius, y: caretRect.minY - knobRadius,
                              width: knobRadius * 2, height: knobRadius * 2)
        ctx.fillEllipse(in: knobRect)
        UIColor.white.setStroke()
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: knobRect)
    }
}

/// The live view as a zoomable/scrollable canvas (Safari model): two-finger pinch
/// zooms, one-finger drag scrolls (when zoomed in), and a long-press begins a
/// selection that the same press-and-drag extends, with the magnifier and the
/// system edit menu. This first step hosts only the live video; history tiles and
/// re-draggable handles come in later M5 steps.
private struct LiveCanvas: UIViewRepresentable {
    let holder: LiveVideoHolder
    let model: AppModel
    /// Drives handle repositioning: a change re-runs updateUIView.
    let selectionRange: CompanionSelectionRange?

    func makeCoordinator() -> Coordinator { Coordinator(holder: holder, model: model) }
    func makeUIView(context: Context) -> UIView { context.coordinator.makeContainer() }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.repositionHandles()
    }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.tearDown() }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIEditMenuInteractionDelegate {
        let holder: LiveVideoHolder
        var model: AppModel
        private let container = UIView()
        private let scrollView = LayoutObservingScrollView()
        private let contentView = UIView()
        private let loupe = LoupeUIView()
        private let startHandle = SelectionHandleView()
        private let endHandle = SelectionHandleView()
        private var editMenu: UIEditMenuInteraction!
        private var selecting = false
        private var draggingStart = false
        private var draggingEnd = false
        private var lastLayoutSize: CGSize = .zero
        private var menuAnchor: CGPoint = .zero
        private let loupeDiameter: CGFloat = 120

        init(holder: LiveVideoHolder, model: AppModel) {
            self.holder = holder
            self.model = model
            super.init()
        }

        func tearDown() {
            editMenu?.dismissMenu()
        }

        func makeContainer() -> UIView {
            container.backgroundColor = .black
            scrollView.frame = container.bounds
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 6
            scrollView.delegate = self
            scrollView.backgroundColor = .black
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.bouncesZoom = true
            container.addSubview(scrollView)

            holder.view.frame = contentView.bounds
            holder.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(holder.view)
            scrollView.addSubview(contentView)

            // Hold-still ~0.3s to begin a selection; the same press-and-drag then
            // extends it. A drag that moves before recognition scrolls instead
            // (default allowableMovement), matching Safari.
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.3
            contentView.addGestureRecognizer(longPress)

            // Tap clears the selection / dismisses the menu.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            contentView.addGestureRecognizer(tap)

            loupe.isUserInteractionEnabled = false
            loupe.backgroundColor = .black
            loupe.layer.masksToBounds = true
            loupe.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
            loupe.layer.borderWidth = 3
            loupe.pixelBufferProvider = { [weak self] in self?.holder.view.latestPixelBuffer() }

            editMenu = UIEditMenuInteraction(delegate: self)
            container.addInteraction(editMenu)

            // Draggable selection handles overlay the container (so they stay a
            // fixed size regardless of zoom) and reposition as the canvas scrolls.
            for (handle, isStart) in [(startHandle, true), (endHandle, false)] {
                handle.isHidden = true
                let pan = UIPanGestureRecognizer(target: self, action: isStart ? #selector(handleStartPan(_:)) : #selector(handleEndPan(_:)))
                handle.addGestureRecognizer(pan)
                container.addSubview(handle)
            }

            scrollView.onLayout = { [weak self] in self?.layout() }
            return container
        }

        private func layout() {
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0, size != lastLayoutSize else { return }
            lastLayoutSize = size
            contentView.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            let imageWidth = model.activeStreamImageSize.width
            if imageWidth > 0 {
                let displayScale = max(1, scrollView.traitCollection.displayScale)
                scrollView.maximumZoomScale = max(1, 4 * imageWidth / (size.width * displayScale))
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { repositionHandles() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { repositionHandles() }

        // MARK: Handles

        /// Place the handle dots at the selection endpoints, converting from the
        /// content's coordinate space (where the endpoints are computed) to the
        /// container, so zoom and scroll are applied. A handle being dragged keeps
        /// the finger position until the round-tripped selection catches up.
        func repositionHandles() {
            // Hide handles during a fresh long-press drag (the magnifier leads
            // there); they appear once the selection settles.
            guard !selecting else {
                startHandle.isHidden = true
                endHandle.isHidden = true
                return
            }
            guard model.activeSelectionRange != nil,
                  let points = model.selectionHandlePoints(viewSize: contentView.bounds.size) else {
                startHandle.isHidden = true
                endHandle.isHidden = true
                return
            }
            if !draggingStart {
                startHandle.center = container.convert(points.start, from: contentView)
                startHandle.isHidden = false
            }
            if !draggingEnd {
                endHandle.center = container.convert(points.end, from: contentView)
                endHandle.isHidden = false
            }
        }

        @objc private func handleStartPan(_ gesture: UIPanGestureRecognizer) { handleHandlePan(gesture, isStart: true) }
        @objc private func handleEndPan(_ gesture: UIPanGestureRecognizer) { handleHandlePan(gesture, isStart: false) }

        /// Drag an endpoint, anchoring the selection at the opposite one.
        private func handleHandlePan(_ gesture: UIPanGestureRecognizer, isStart: Bool) {
            let point = gesture.location(in: contentView)
            let viewSize = contentView.bounds.size
            switch gesture.state {
            case .began:
                guard let endpoints = model.activeSelectionEndpoints else { return }
                if isStart { draggingStart = true } else { draggingEnd = true }
                scrollView.isScrollEnabled = false
                editMenu.dismissMenu()
                model.sendSelectionGesture(phase: .begin, mode: .character, point: isStart ? endpoints.end : endpoints.start)
                model.sendSelectionGesture(phase: .move, mode: .character, viewPoint: point, viewSize: viewSize)
                moveHandle(isStart: isStart, toContentPoint: point)
                showLoupe(at: point)
            case .changed:
                model.sendSelectionGesture(phase: .move, mode: .character, viewPoint: point, viewSize: viewSize)
                moveHandle(isStart: isStart, toContentPoint: point)
                showLoupe(at: point)
            case .ended, .cancelled, .failed:
                draggingStart = false
                draggingEnd = false
                scrollView.isScrollEnabled = true
                model.sendSelectionGesture(phase: .end, mode: .character, viewPoint: point, viewSize: viewSize)
                loupe.removeFromSuperview()
                repositionHandles()
                menuAnchor = clampToContent(container.convert(point, from: contentView))
                editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: menuAnchor))
            default:
                break
            }
        }

        private func moveHandle(isStart: Bool, toContentPoint point: CGPoint) {
            (isStart ? startHandle : endHandle).center = container.convert(point, from: contentView)
        }

        // MARK: Selection

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: contentView)
            let viewSize = contentView.bounds.size
            switch gesture.state {
            case .began:
                guard model.isInsideContent(viewPoint: point, viewSize: viewSize) else { return }
                selecting = true
                scrollView.isScrollEnabled = false
                editMenu.dismissMenu()
                startHandle.isHidden = true
                endHandle.isHidden = true
                model.sendSelectionGesture(phase: .begin, mode: .character, viewPoint: point, viewSize: viewSize)
                showLoupe(at: point)
            case .changed:
                guard selecting else { return }
                model.sendSelectionGesture(phase: .move, mode: .character, viewPoint: point, viewSize: viewSize)
                showLoupe(at: point)
            case .ended, .cancelled, .failed:
                guard selecting else { return }
                selecting = false
                scrollView.isScrollEnabled = true
                model.sendSelectionGesture(phase: .end, mode: .character, viewPoint: point, viewSize: viewSize)
                loupe.removeFromSuperview()
                menuAnchor = clampToContent(container.convert(point, from: contentView))
                editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: menuAnchor))
            default:
                break
            }
        }

        @objc private func handleTap() {
            editMenu.dismissMenu()
            model.clearActiveSelection()
        }

        private func showLoupe(at contentPoint: CGPoint) {
            let viewSize = contentView.bounds.size
            guard let imagePoint = model.selectionImagePoint(viewPoint: contentPoint, viewSize: viewSize) else { return }
            loupe.imagePoint = imagePoint
            loupe.cellHeight = model.activeStreamCellHeight
            loupe.cropSide = max(40, model.activeStreamCellHeight * 4)
            let finger = container.convert(contentPoint, from: contentView)
            let radius = loupeDiameter / 2
            let x = min(max(finger.x, radius), max(radius, container.bounds.width - radius))
            let above = finger.y - 24 - radius
            let y = above - radius >= 0 ? above : finger.y + 24 + radius
            loupe.frame = CGRect(x: x - radius, y: y - radius, width: loupeDiameter, height: loupeDiameter)
            loupe.layer.cornerRadius = radius
            if loupe.superview == nil { container.addSubview(loupe) }
            loupe.setNeedsDisplay()
        }

        private func clampToContent(_ point: CGPoint) -> CGPoint {
            let rect = model.contentRect(in: container.bounds.size)
            let inset = min(8, rect.width / 2, rect.height / 2)
            return CGPoint(x: min(max(point.x, rect.minX + inset), rect.maxX - inset),
                           y: min(max(point.y, rect.minY + inset), rect.maxY - inset))
        }

        // nonisolated to match the non-main-actor delegate requirement; UIKit calls
        // it on the main thread, so the body assumes isolation and the deferred
        // action handlers hop back to the main actor.
        nonisolated func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                             menuFor configuration: UIEditMenuConfiguration,
                                             suggestedActions: [UIMenuElement]) -> UIMenu? {
            MainActor.assumeIsolated {
                var children: [UIMenuElement] = [
                    UIAction(title: "Copy") { [weak self] _ in Task { @MainActor in self?.model.copyActiveSelection() } },
                    UIAction(title: "Select All") { [weak self] _ in Task { @MainActor in self?.model.selectAllActiveStream() } },
                ]
                if UIPasteboard.general.hasStrings {
                    children.append(UIAction(title: "Paste") { [weak self] _ in Task { @MainActor in self?.model.pasteIntoActiveSession() } })
                }
                return UIMenu(children: children)
            }
        }
    }
}

/// Disables the navigation controller's interactive swipe-back while present, so
/// a left-edge drag starts a selection instead of popping the view. Restores the
/// previous state on disappear (e.g. the back button is still used).
private struct SwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var previouslyEnabled: Bool?
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let recognizer = navigationController?.interactivePopGestureRecognizer else { return }
            previouslyEnabled = recognizer.isEnabled
            recognizer.isEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let previouslyEnabled {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = previouslyEnabled
            }
        }
    }
}
