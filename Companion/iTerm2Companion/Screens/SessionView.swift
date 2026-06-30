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

    /// The displayed bitmap (persists across refetches), for the magnifier to sample.
    var currentImage: UIImage? { imageView.image }

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
            // Respect the bottom safe area so the canvas sits above the tab bar
            // (the black background still fills under it); a content inset adds a
            // margin so the last line stays legible. The top stays under the nav bar.
            LiveCanvas(holder: holder, model: model,
                       layout: model.liveCanvasLayout,
                       selectionRange: model.activeSelectionRange)
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
    /// The image to magnify (the live frame over the live band, or a history tile
    /// over scrollback). Sampled every refresh so live content keeps updating.
    var imageProvider: (() -> CIImage?)?
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
        guard let base = imageProvider?(), cropSide > 0 else { return }
        // CIImage uses a bottom-left origin; clamp to the edges so a crop near the
        // border extends rather than going transparent.
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
    /// Drives a relayout (history extent / geometry) when it changes.
    let layout: CompanionLiveCanvasLayout?
    /// Drives handle repositioning: a change re-runs updateUIView.
    let selectionRange: CompanionSelectionRange?

    func makeCoordinator() -> Coordinator { Coordinator(holder: holder, model: model) }
    func makeUIView(context: Context) -> UIView { context.coordinator.makeContainer() }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.layout = layout
        context.coordinator.applyLayout()
        context.coordinator.repositionHandles()
        context.coordinator.updateSelectionTiles()
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
        private var menuAnchor: CGPoint = .zero
        private let loupeDiameter: CGFloat = 120
        /// Empty space kept below the content so the last line clears the tab bar.
        static let bottomMargin: CGFloat = 16

        // History canvas layout (set from updateUIView).
        var layout: CompanionLiveCanvasLayout?
        /// The live video band within the (tall) content view, in content coords.
        private var videoRect: CGRect = .zero
        private var pointsPerLine: CGFloat = 0
        /// Number of scrollback lines above the live video (the history region).
        private var historyLines = 0
        /// Guards redundant relayout: the (viewport size, layout) it was built for.
        private var appliedKey: String = ""
        /// The history origin the tiles are currently keyed against; a change means
        /// scrollback was trimmed or cleared.
        private var laidOutFirstAbsLine: Int64?
        private var laidOutTotalLines = 0
        private var didScrollToBottom = false
        // History tiles, keyed by tile index (0 = oldest), like the static path.
        private var tileViews: [Int: TileView] = [:]
        private var requestedTiles: Set<Int> = []
        /// Line count the cached image for each tile actually covers, so a tile that
        /// has grown is sized to its image (not stretched) until it is refetched.
        private var tileFetchedLines: [Int: Int] = [:]
        /// Per-tile request token: a completion applies only if its token is still
        /// current, so a re-request (after a grow or selection change) supersedes an
        /// in-flight fetch instead of an out-of-order reply winning.
        private var tileToken: [Int: Int] = [:]
        private var tileTokenCounter = 0
        /// Tile indices that currently overlap the selection, and the endpoints they
        /// were computed for, so a selection change invalidates only the tiles whose
        /// highlight changed.
        private var selectedTileIndices: Set<Int> = []
        private var lastSelectionEndpoints: (start: CompanionSelectionPoint, end: CompanionSelectionPoint)?
        private let linesPerTile = 50
        private var growthTimer: Timer?

        init(holder: LiveVideoHolder, model: AppModel) {
            self.holder = holder
            self.model = model
            super.init()
        }

        func tearDown() {
            editMenu?.dismissMenu()
            growthTimer?.invalidate()
            growthTimer = nil
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
            // Empty space below the content so the bottom line clears the tab bar.
            scrollView.contentInset.bottom = Self.bottomMargin
            scrollView.verticalScrollIndicatorInsets.bottom = Self.bottomMargin
            container.addSubview(scrollView)

            // The video is positioned explicitly (a band at the document bottom) by
            // applyLayout; until then it fills the container so the first frames show.
            holder.view.frame = container.bounds
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

            scrollView.onLayout = { [weak self] in self?.applyLayout() }

            // Grow the document as the live top advances (4 Hz; cheap no-op when the
            // extent is unchanged or the user is interacting).
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.growthTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            growthTimer = timer
            return container
        }

        /// Lay out the scrollable document: history fills the top, the live video is
        /// a band at the bottom (the last `rows` lines). The document grows as the
        /// live top advances (new output scrolls into history); if the view was
        /// pinned to the bottom it stays there (following), otherwise the offset is
        /// preserved (browsing) since the content above is unchanged.
        func applyLayout() {
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            // No geometry yet: fall back to the video filling the viewport.
            guard let layout, layout.imageSize.width > 0, layout.rows > 0, layout.totalLines > 0 else {
                contentView.frame = CGRect(origin: .zero, size: size)
                scrollView.contentSize = size
                holder.view.frame = contentView.bounds
                videoRect = contentView.bounds
                return
            }
            // Relayout only at zoom 1: at other scales the scroll view manages
            // contentSize for zooming and our changes would fight it. Resumes when
            // the user returns to 1.
            guard scrollView.zoomScale <= 1.001 else { return }

            // Freshest extent: grow with the live top as output scrolls off; the
            // extent (firstAbsLine/totalLines, updated by streamExtent on trim or
            // clear) is the floor, so a clear shrinks the document once the next
            // frame lands. Live top can move down on clear, so do not pin it up.
            let derivedTotal = model.activeStreamLiveTop > layout.firstAbsLine
                ? Int(model.activeStreamLiveTop - layout.firstAbsLine) + layout.rows
                : layout.totalLines
            let totalLines = max(layout.totalLines, derivedTotal)

            let key = "\(Int(size.width))x\(Int(size.height))|\(layout)|\(totalLines)"
            guard key != appliedKey else { return }
            let wasAtBottom = isPinnedToBottom
            appliedKey = key

            // The history origin advanced (scrollback trimmed) or the document
            // shrank (cleared): tiles are keyed relative to the origin and stale
            // ones must not linger, so drop every tile view; they refetch (hitting
            // the cache for survivors). The model cache was already pruned.
            let shrank = totalLines < laidOutTotalLines
            if let prev = laidOutFirstAbsLine, prev != layout.firstAbsLine || shrank {
                for view in tileViews.values { view.removeFromSuperview() }
                tileViews.removeAll()
                requestedTiles.removeAll()
                tileFetchedLines.removeAll()
                tileToken.removeAll()
                // Tile indices are relative to the origin; force selection tiles to
                // be recomputed against the new origin.
                selectedTileIndices.removeAll()
                lastSelectionEndpoints = nil
            }
            laidOutFirstAbsLine = layout.firstAbsLine
            laidOutTotalLines = totalLines

            let videoHeight = size.width * layout.imageSize.height / layout.imageSize.width
            pointsPerLine = videoHeight / CGFloat(layout.rows)
            historyLines = max(0, totalLines - layout.rows)
            let documentHeight = CGFloat(totalLines) * pointsPerLine

            contentView.frame = CGRect(x: 0, y: 0, width: size.width, height: documentHeight)
            scrollView.contentSize = contentView.frame.size
            videoRect = CGRect(x: 0, y: documentHeight - videoHeight, width: size.width, height: videoHeight)
            holder.view.frame = videoRect

            let displayScale = max(1, scrollView.traitCollection.displayScale)
            scrollView.maximumZoomScale = max(1, 4 * layout.imageSize.width / (size.width * displayScale))

            for (index, view) in tileViews { view.frame = tileFrame(index: index) }
            if !didScrollToBottom || wasAtBottom {
                didScrollToBottom = true
                scrollToBottom()
            }
            refreshTiles()
        }

        private var isPinnedToBottom: Bool {
            let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            return scrollView.contentOffset.y >= maxY - 1
        }

        private func scrollToBottom() {
            let maxY = max(-scrollView.adjustedContentInset.top,
                           scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            scrollView.contentOffset = CGPoint(x: 0, y: maxY)
        }

        /// Periodically grow the document as the live top advances, but never while
        /// the user is interacting (it would jolt) or zoomed in.
        private func growthTick() {
            guard !scrollView.isDragging, !scrollView.isDecelerating, !scrollView.isZooming,
                  !selecting, !draggingStart, !draggingEnd, scrollView.zoomScale <= 1.001 else { return }
            applyLayout()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { repositionHandles(); refreshTiles() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { repositionHandles(); refreshTiles() }

        // MARK: History tiles

        private func expectedLines(index: Int) -> Int {
            min(linesPerTile, historyLines - index * linesPerTile)
        }

        private func tileFrame(index: Int) -> CGRect {
            // Height tracks the image's actual line count (or the expected count
            // while loading), so a tile that has since grown is never stretched.
            let lines = tileFetchedLines[index] ?? expectedLines(index: index)
            return CGRect(x: 0, y: CGFloat(index * linesPerTile) * pointsPerLine,
                          width: contentView.bounds.width, height: CGFloat(max(0, lines)) * pointsPerLine)
        }

        /// Materialize tile views around the visible history (one viewport of
        /// lookahead each way), fetch their bitmaps, refetch any whose line count
        /// grew, and drop far-away ones.
        private func refreshTiles() {
            guard let layout, historyLines > 0, pointsPerLine > 0, contentView.bounds.width > 0 else { return }
            let tileHeight = CGFloat(linesPerTile) * pointsPerLine
            guard tileHeight > 0 else { return }
            let visible = scrollView.convert(scrollView.bounds, to: contentView)
            let keep = visible.insetBy(dx: 0, dy: -visible.height)
            let tileCount = (historyLines + linesPerTile - 1) / linesPerTile
            let first = max(0, Int(floor(keep.minY / tileHeight)))
            let last = min(tileCount - 1, Int(floor(keep.maxY / tileHeight)))
            guard first <= last else { return }

            for index in first...last {
                let expected = expectedLines(index: index)
                guard expected > 0 else { continue }
                let view: TileView
                if let existing = tileViews[index] {
                    view = existing
                } else {
                    view = TileView()
                    contentView.insertSubview(view, belowSubview: holder.view)
                    tileViews[index] = view
                }
                view.frame = tileFrame(index: index)
                let absLine = layout.firstAbsLine + Int64(index * linesPerTile)
                if tileFetchedLines[index] == expected, let image = model.cachedHistoryTile(firstAbsLine: absLine) {
                    view.show(image: image)
                } else if !requestedTiles.contains(index) {
                    // Missing, or grew since last fetch: (re)render for the current
                    // count. Keep the old (correctly-sized) image visible meanwhile
                    // (showLoading is a no-op once a tile already has an image).
                    view.showLoading()
                    requestedTiles.insert(index)
                    let token = nextTileToken(index)
                    model.invalidateHistoryTile(firstAbsLine: absLine)
                    model.requestHistoryTile(firstAbsLine: absLine, lineCount: expected) { [weak self] image in
                        // Ignore a superseded reply (a newer request for this tile ran).
                        guard let self, self.tileToken[index] == token else { return }
                        self.requestedTiles.remove(index)
                        guard let view = self.tileViews[index] else { return }
                        if let image {
                            self.tileFetchedLines[index] = expected
                            view.frame = self.tileFrame(index: index)
                            view.show(image: image)
                        } else {
                            view.showFailure()
                        }
                        // It may have grown again while rendering; catch up.
                        if self.expectedLines(index: index) != expected { self.refreshTiles() }
                    }
                }
            }

            let discard = visible.insetBy(dx: 0, dy: -3 * visible.height)
            for (index, view) in tileViews where !view.frame.intersects(discard) {
                view.removeFromSuperview()
                tileViews[index] = nil
                requestedTiles.remove(index)
                // Keep tileFetchedLines so a re-shown tile uses the cache; a cache
                // miss (e.g. generation change) still triggers a refetch.
            }
        }

        // MARK: Selection-driven tile invalidation

        /// The history tiles are rendered with the current selection by the mac, so
        /// when the selection changes, invalidate the tiles whose highlight changed:
        /// tiles that entered or left the selection, and the tiles holding either
        /// endpoint (their selected edge moves). Visible ones refetch immediately;
        /// off-screen ones refetch lazily when scrolled into view.
        func updateSelectionTiles() {
            guard let layout else { return }
            let endpoints = model.activeSelectionEndpoints
            // No change since last call -> nothing to invalidate. updateUIView fires
            // for many reasons (including each tile load); without this guard the
            // endpoint tile is re-invalidated and refetched every time, looping.
            if endpoints?.start == lastSelectionEndpoints?.start,
               endpoints?.end == lastSelectionEndpoints?.end {
                return
            }
            let newTiles = endpoints.map { historyTileIndices(start: $0.start.absLine, end: $0.end.absLine) } ?? []
            var affected = newTiles.symmetricDifference(selectedTileIndices)
            // Endpoint tiles (their selected edge moved): old and new positions.
            for absLine in [endpoints?.start.absLine, endpoints?.end.absLine,
                            lastSelectionEndpoints?.start.absLine, lastSelectionEndpoints?.end.absLine] {
                if let absLine, let index = historyTileIndex(forAbs: absLine) { affected.insert(index) }
            }
            selectedTileIndices = newTiles
            lastSelectionEndpoints = endpoints
            for index in affected {
                model.invalidateHistoryTile(firstAbsLine: layout.firstAbsLine + Int64(index * linesPerTile))
                tileFetchedLines[index] = nil
                requestedTiles.remove(index)
                _ = nextTileToken(index)   // supersede any in-flight fetch
            }
            if !affected.isEmpty {
                companionLog("historyTile invalidate selection affected=\(affected.sorted()) new=\(newTiles.sorted()) hist=\(historyLines)")
                refreshTiles()
            }
        }

        /// A fresh request token for a tile, marking any in-flight fetch superseded.
        private func nextTileToken(_ index: Int) -> Int {
            tileTokenCounter += 1
            tileToken[index] = tileTokenCounter
            return tileTokenCounter
        }

        /// Tile index for an absolute line, or nil if it is not in the history region.
        private func historyTileIndex(forAbs absLine: Int64) -> Int? {
            guard let layout, absLine >= layout.firstAbsLine else { return nil }
            let rel = Int(absLine - layout.firstAbsLine)
            guard rel < historyLines else { return nil }
            return rel / linesPerTile
        }

        /// History tile indices a selection spanning [start, end] touches.
        private func historyTileIndices(start: Int64, end: Int64) -> Set<Int> {
            guard let layout, historyLines > 0 else { return [] }
            let lo = max(0, Int(min(start, end) - layout.firstAbsLine))
            let hi = min(historyLines - 1, Int(max(start, end) - layout.firstAbsLine))
            guard lo <= hi else { return [] }
            return Set((lo / linesPerTile)...(hi / linesPerTile))
        }

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
            guard model.activeSelectionRange != nil, let endpoints = model.activeSelectionEndpoints,
                  pointsPerLine > 0, cellWidthPoints > 0 else {
                startHandle.isHidden = true
                endHandle.isHidden = true
                return
            }
            // Endpoints are absolute (col, line); place the start handle at the
            // top-left of its cell and the end handle at the bottom-right of its
            // cell, then convert to the container (applying zoom/scroll).
            if !draggingStart {
                let p = contentPoint(absLine: endpoints.start.absLine, column: endpoints.start.column, rightEdge: false, bottomEdge: false)
                startHandle.center = container.convert(p, from: contentView)
                startHandle.isHidden = false
            }
            if !draggingEnd {
                let p = contentPoint(absLine: endpoints.end.absLine, column: endpoints.end.column, rightEdge: true, bottomEdge: true)
                endHandle.center = container.convert(p, from: contentView)
                endHandle.isHidden = false
            }
        }

        // MARK: Whole-document coordinate mapping

        /// Width of one cell in content points (the video fills the width at zoom 1).
        private var cellWidthPoints: CGFloat {
            guard let layout, layout.columns > 0, contentView.bounds.width > 0 else { return 0 }
            return contentView.bounds.width / CGFloat(layout.columns)
        }

        /// A point anywhere in the document to an absolute terminal point, clamped to
        /// the available lines/columns. Works for both history and the live band.
        private func selectionPoint(atContent p: CGPoint) -> CompanionSelectionPoint? {
            guard let layout, pointsPerLine > 0, cellWidthPoints > 0 else { return nil }
            let col = min(max(Int((p.x / cellWidthPoints).rounded(.down)), 0), layout.columns - 1)
            let line = Int((p.y / pointsPerLine).rounded(.down))
            let lastLine = max(0, historyLines + layout.rows - 1)
            let clampedLine = min(max(line, 0), lastLine)
            return CompanionSelectionPoint(absLine: layout.firstAbsLine + Int64(clampedLine), column: col)
        }

        /// The content-space point of a cell corner, for placing handles / highlights.
        private func contentPoint(absLine: Int64, column: Int, rightEdge: Bool, bottomEdge: Bool) -> CGPoint {
            let line = CGFloat(absLine - (layout?.firstAbsLine ?? 0))
            return CGPoint(x: (CGFloat(column) + (rightEdge ? 1 : 0)) * cellWidthPoints,
                           y: (line + (bottomEdge ? 1 : 0)) * pointsPerLine)
        }

        private func videoLocal(_ contentPoint: CGPoint) -> CGPoint {
            CGPoint(x: contentPoint.x - videoRect.minX, y: contentPoint.y - videoRect.minY)
        }

        @objc private func handleStartPan(_ gesture: UIPanGestureRecognizer) { handleHandlePan(gesture, isStart: true) }
        @objc private func handleEndPan(_ gesture: UIPanGestureRecognizer) { handleHandlePan(gesture, isStart: false) }

        /// Drag an endpoint, anchoring the selection at the opposite one.
        private func handleHandlePan(_ gesture: UIPanGestureRecognizer, isStart: Bool) {
            let point = gesture.location(in: contentView)
            guard let sel = selectionPoint(atContent: point) else { return }
            switch gesture.state {
            case .began:
                guard let endpoints = model.activeSelectionEndpoints else { return }
                if isStart { draggingStart = true } else { draggingEnd = true }
                scrollView.isScrollEnabled = false
                editMenu.dismissMenu()
                model.sendSelectionGesture(phase: .begin, mode: .character, point: isStart ? endpoints.end : endpoints.start)
                model.sendSelectionGesture(phase: .move, mode: .character, point: sel)
                moveHandle(isStart: isStart, toContentPoint: point)
                showLoupe(at: point)
            case .changed:
                model.sendSelectionGesture(phase: .move, mode: .character, point: sel)
                moveHandle(isStart: isStart, toContentPoint: point)
                showLoupe(at: point)
            case .ended, .cancelled, .failed:
                draggingStart = false
                draggingEnd = false
                scrollView.isScrollEnabled = true
                model.sendSelectionGesture(phase: .end, mode: .character, point: sel)
                loupe.removeFromSuperview()
                repositionHandles()
                menuAnchor = clampToContainer(container.convert(point, from: contentView))
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
            guard let sel = selectionPoint(atContent: point) else { return }
            switch gesture.state {
            case .began:
                selecting = true
                scrollView.isScrollEnabled = false
                editMenu.dismissMenu()
                startHandle.isHidden = true
                endHandle.isHidden = true
                model.sendSelectionGesture(phase: .begin, mode: .character, point: sel)
                showLoupe(at: point)
            case .changed:
                guard selecting else { return }
                model.sendSelectionGesture(phase: .move, mode: .character, point: sel)
                showLoupe(at: point)
            case .ended, .cancelled, .failed:
                guard selecting else { return }
                selecting = false
                scrollView.isScrollEnabled = true
                model.sendSelectionGesture(phase: .end, mode: .character, point: sel)
                loupe.removeFromSuperview()
                menuAnchor = clampToContainer(container.convert(point, from: contentView))
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
            // Magnify the live frame over the live band, or the history tile under
            // the finger over scrollback. Hide if there is nothing to sample yet.
            guard let sample = loupeSample(atContent: contentPoint) else { loupe.removeFromSuperview(); return }
            loupe.imageProvider = sample.provider
            loupe.imagePoint = sample.imagePoint
            loupe.cellHeight = sample.cellHeight
            loupe.cropSide = max(8, sample.cellHeight * 4)
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

        /// The image + center the magnifier should show for a content point, in that
        /// image's pixel space. Over the live band it samples the decoded frame; over
        /// history it samples the tile view's current bitmap (which persists across
        /// refetches, so the magnifier does not flicker while the endpoint tile is
        /// being re-rendered). `cellHeight`/crop are in the sampled image's pixels.
        private func loupeSample(atContent p: CGPoint)
            -> (provider: () -> CIImage?, imagePoint: CGPoint, cellHeight: CGFloat)? {
            if videoRect.contains(p) {
                guard let imagePoint = model.selectionImagePoint(viewPoint: videoLocal(p), viewSize: videoRect.size) else {
                    return nil
                }
                let provider: () -> CIImage? = { [weak self] in
                    self?.holder.view.latestPixelBuffer().map { CIImage(cvPixelBuffer: $0) }
                }
                return (provider, imagePoint, model.activeStreamCellHeight)
            }
            // History: locate the tile under the point and the pixel within its image.
            guard pointsPerLine > 0, contentView.bounds.width > 0, historyLines > 0 else { return nil }
            let index = Int(p.y / pointsPerLine) / linesPerTile
            let lines = min(linesPerTile, historyLines - index * linesPerTile)
            guard lines > 0, let cg = tileViews[index]?.currentImage?.cgImage else { return nil }
            let tileTop = CGFloat(index * linesPerTile) * pointsPerLine
            let tileHeight = CGFloat(lines) * pointsPerLine
            let fx = min(max(p.x / contentView.bounds.width, 0), 1)
            let fy = min(max((p.y - tileTop) / tileHeight, 0), 1)
            let imagePoint = CGPoint(x: fx * CGFloat(cg.width), y: fy * CGFloat(cg.height))
            let cellHeight = CGFloat(cg.height) / CGFloat(lines)
            return ({ CIImage(cgImage: cg) }, imagePoint, cellHeight)
        }

        private func clampToContainer(_ point: CGPoint) -> CGPoint {
            let bounds = container.bounds.insetBy(dx: 8, dy: 8)
            guard bounds.width > 0, bounds.height > 0 else { return point }
            return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                           y: min(max(point.y, bounds.minY), bounds.maxY))
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
