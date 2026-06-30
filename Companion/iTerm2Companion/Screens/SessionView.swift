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
    @State private var selecting = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveVideoLayer(holder: holder)
                .ignoresSafeArea(edges: .bottom)
            if model.sessionSelectionSupported {
                selectionGestureOverlay
            }
            VStack {
                HStack {
                    liveBadge
                    Spacer()
                    if model.sessionSelectionSupported {
                        selectionControls
                    }
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

    /// A transparent layer that turns a drag into begin/move/end selection
    /// gestures. A drag starting on a selection handle adjusts that endpoint
    /// (anchoring at the opposite one); a drag elsewhere starts a fresh selection.
    /// Mapping uses the stream geometry. Handles are drawn but do not intercept
    /// touches, so the one gesture below hit-tests them itself.
    private var selectionGestureOverlay: some View {
        GeometryReader { geo in
            let handles = model.selectionHandlePoints(viewSize: geo.size)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !selecting {
                                    selecting = true
                                    beginSelectionDrag(at: value.startLocation, handles: handles, viewSize: geo.size)
                                }
                                model.sendSelectionGesture(phase: .move, mode: .character,
                                                           viewPoint: value.location, viewSize: geo.size)
                            }
                            .onEnded { value in
                                model.sendSelectionGesture(phase: .end, mode: .character,
                                                           viewPoint: value.location, viewSize: geo.size)
                                selecting = false
                            }
                    )
                if let handles {
                    selectionHandle.position(handles.start)
                    selectionHandle.position(handles.end)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// A handle dot. Non-interactive: the overlay's single gesture hit-tests it.
    private var selectionHandle: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(.blue, lineWidth: 2))
            .frame(width: 16, height: 16)
            .shadow(radius: 2)
            .allowsHitTesting(false)
    }

    /// Decide what a drag beginning at `location` does, and send the opening
    /// gesture. Grabbing a handle anchors the selection at the opposite endpoint.
    private func beginSelectionDrag(at location: CGPoint,
                                    handles: (start: CGPoint, end: CGPoint)?,
                                    viewSize: CGSize) {
        let hitRadius: CGFloat = 32
        if let handles, let endpoints = model.activeSelectionEndpoints {
            if location.distance(to: handles.start) <= hitRadius {
                model.sendSelectionGesture(phase: .begin, mode: .character, point: endpoints.end)
                return
            }
            if location.distance(to: handles.end) <= hitRadius {
                model.sendSelectionGesture(phase: .begin, mode: .character, point: endpoints.start)
                return
            }
        }
        model.sendSelectionGesture(phase: .begin, mode: .character, viewPoint: location, viewSize: viewSize)
    }

    private var selectionControls: some View {
        HStack(spacing: 8) {
            Button { model.clearActiveSelection() } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Clear selection")
            Button { model.copyActiveSelection() } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel("Copy selection")
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
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

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

/// Holds the AVSampleBufferDisplayLayer-backed view across SwiftUI updates.
private final class LiveVideoHolder {
    let view = CompanionVideoView(frame: .zero)
}

private struct LiveVideoLayer: UIViewRepresentable {
    let holder: LiveVideoHolder
    func makeUIView(context: Context) -> CompanionVideoView { holder.view }
    func updateUIView(_ uiView: CompanionVideoView, context: Context) {}
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
