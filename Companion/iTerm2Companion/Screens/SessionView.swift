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
    /// The chat the user tapped an @-mention in to reach this view, if any. The
    /// compose overlay sends into it (rather than a session-bound chat) and a
    /// reply notification pops back to it. Nil when reached from the session
    /// list or a workgroup.
    var originatingChatID: String? = nil
    /// When false, the "chat about this session" toolbar button is hidden. The
    /// mention picker shows this view only to preview a session, where starting
    /// a chat would push onto the stack behind the picker sheet.
    var allowsChat: Bool = true

    /// Whether the compose overlay (text field + dictation + send) is up.
    @State private var showComposer = false
    /// The chat this visit's compose overlay sends into. Resolved on the first
    /// send (the originating chat, or the session's recent/new session-bound
    /// chat) and reused for the rest of the visit.
    @State private var composeChatID: String?
    /// Set once the @-mention's originating chat is found deleted, so later sends
    /// stop preferring the (dead) originatingChatID and fall through to creating a
    /// fresh session-bound chat - otherwise recovery is impossible for this visit.
    @State private var originatingChatIsDead = false
    /// Identifies THIS session view's watch, so a different session view leaving
    /// (or a stale send) can't tear down or steal this view's reply watch.
    @State private var watchToken = UUID()
    /// A send failure for THIS view's compose overlay (scoped locally so it can't
    /// surface on a different SessionView via shared state).
    @State private var sendError: String?
    /// Whether the compose overlay's draft is empty; a scrim tap only dismisses
    /// (discarding the draft) when it is.
    @State private var composeIsEmpty = true
    /// Text to seed the overlay with, used to restore a draft whose send failed.
    @State private var composeInitialText = ""
    /// Bumped on the failed-send restore path to re-seed composeInitialText into
    /// the composer. Edge-triggered so the restore works even when SwiftUI reuses
    /// the same composer instance (e.g. a restore that lands inside the exit
    /// animation window, where showComposer false->true just reverses the
    /// transition) - no view-identity churn needed.
    @State private var composerSeedGeneration = 0
    /// A send held while the auto-provide consent modal is up; its buttons resume it.
    @State private var pendingConsentText: String?
    /// Drives the auto-provide consent modal (include terminal state + screen with AI).
    @State private var showAutoProvideConsentAlert = false
    /// The view's current width, tracked so the principal nav-bar title can be
    /// rebuilt on rotation. The system caches the title view's width at first layout
    /// and does not re-measure it when the bar widens/narrows on rotation, so a title
    /// laid out in portrait stays narrow in landscape (and vice versa). Keying the
    /// title on this width forces a fresh measurement whenever it changes.
    @State private var barWidth: CGFloat = 0

    private static let messageAgentLabel = "Message the agent"

    /// The originating @-mention chat this overlay targets, or nil once it's dead
    /// (recovery: sends create a fresh session-bound chat) or for a plain session
    /// view. Sends and the label/disable logic all key off this.
    private var effectiveOriginatingChatID: String? {
        originatingChatIsDead ? nil : originatingChatID
    }

    /// Whether the RESOLVED send target is a chat the Mac deleted, independent of
    /// openChatID (a tab round-trip repoints it). Reactive dead-detection flips
    /// effectiveOriginatingChatID to nil, so this only stays true in the brief
    /// window before recovery kicks in (or for an already-resolved, since-deleted
    /// composeChatID).
    private var composerTargetIsDeleted: Bool {
        guard let target = composeChatID ?? effectiveOriginatingChatID else { return false }
        return !model.chatExists(target)
    }

    /// Whether the originating @-mention chat is present in the chat list, for
    /// reactive dead-detection.
    private var originatingChatPresent: Bool {
        guard let originatingChatID else { return true }
        return model.chatExists(originatingChatID)
    }

    /// Whether the resolved send chat is present in the chat list, for reactive
    /// dead-detection (a session-list send resolves composeChatID, which has no
    /// @-mention recovery path of its own).
    private var composeChatPresent: Bool {
        guard let composeChatID else { return true }
        return model.chatExists(composeChatID)
    }

    /// Run `recover` when a tracked target chat (`id`) has left an AUTHORITATIVE
    /// list. Shared guard for the two reactive dead-detection handlers: only when
    /// the id was actually set, it is now absent, AND `chats` is non-empty (an empty
    /// list is "not synced yet", not "deleted", so it must not trigger recovery).
    private func recoverIfChatDeleted(id: String?, present: Bool, recover: () -> Void) {
        if id != nil, !present, !model.chats.isEmpty { recover() }
    }

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
        .background {
            // Track the view width without disturbing layout, so the principal title
            // can be rebuilt when the bar widens/narrows on rotation.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { barWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in barWidth = width }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // The live path fills behind the (translucent) nav bar with black, so the
        // default label-colored title and buttons render dark-on-dark and are
        // invisible in light mode (only a colored emoji in the title showed through,
        // which read as "the title is truncated to the emoji"). Force the bar's
        // content light there. The tile path keeps the system background, so leave its
        // bar automatic.
        .toolbarColorScheme(model.macSupportsStreaming ? .dark : nil, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if showComposer {
                composeOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showComposer)
        .alert("Couldn’t Send Message",
               isPresented: Binding(get: { sendError != nil },
                                    set: { if !$0 { sendError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sendError ?? "")
        }
        .alert("Share This Session with the AI?", isPresented: $showAutoProvideConsentAlert) {
            Button("Allow") {
                if let text = pendingConsentText { performSend(text, grantAutoProvideConsent: true) }
                pendingConsentText = nil
            }
            Button("Not Now", role: .cancel) {
                model.declineAutoProvideConsent(sessionGuid: guid)
                if let text = pendingConsentText { performSend(text, grantAutoProvideConsent: false) }
                pendingConsentText = nil
            }
        } message: {
            Text("Include this session’s terminal state and current screen with your messages so the AI can see what’s happening. You can change this later in the chat’s permissions.")
        }
        .onAppear {
            // This view is alive; un-mark its token as departed (onDisappear fires
            // on a tab switch/cover while the view stays in the stack, and the
            // token outlives that).
            model.watchViewDidAppear(guid: guid, token: watchToken)
            companionLog("SessionView appeared for \(guid): macSupportsStreaming=\(model.macSupportsStreaming) -> using \(model.macSupportsStreaming ? "LIVE (has resize button)" : "TILE (no resize button)") path; macRevision=\(model.macRevision) sessionResizeSupported=\(model.sessionResizeSupported)")
        }
        .onDisappear {
            // onDisappear fires on a tab switch/cover too, not just a pop, so this
            // only ends the watch when the session is genuinely gone from the nav
            // stack - otherwise switching to the Chats tab to wait for the reply
            // would kill the very notification the user is waiting for.
            model.sessionViewDidDisappear(guid: guid, token: watchToken)
        }
        .onChange(of: originatingChatPresent) { _, present in
            // The @-mention's originating chat left an AUTHORITATIVE list (deleted
            // on the Mac): switch to session-bound recovery so the composer stays
            // usable (the next send creates a fresh chat) instead of silently
            // targeting a dead chat and only revealing it on Send.
            recoverIfChatDeleted(id: originatingChatID, present: present) {
                originatingChatIsDead = true
            }
        }
        .onChange(of: composeChatPresent) { _, present in
            // The resolved send chat was deleted on the Mac: drop it so the composer
            // re-enables and the next send re-resolves (creates a fresh chat),
            // instead of the whole bar dead-ending disabled with no way to recover.
            recoverIfChatDeleted(id: composeChatID, present: present) { composeChatID = nil }
        }
        .toolbar {
            // A principal title claims the space BETWEEN the leading and trailing
            // groups (not the system title's symmetric reservation), so it uses the
            // full width. maxWidth:.infinity is what makes it expand rather than size
            // to its (truncated) intrinsic width. Colored explicitly since a principal
            // item does not pick up the bar's title color: white over the black live
            // canvas, primary over the tile path's system background.
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(model.macSupportsStreaming ? Color.white : Color.primary)
                    // The system caches the title view's width; re-key on the current
                    // width so a rotation re-measures it instead of keeping the old
                    // orientation's (too-narrow-in-landscape) width.
                    .id(barWidth)
            }
            if allowsChat {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Only reset emptiness when actually opening; the overlay's
                        // scrim doesn't cover the nav bar, so re-tapping while a
                        // draft is up must not mark it empty (a scrim tap would
                        // then discard it).
                        if !showComposer {
                            composeIsEmpty = true
                            composeInitialText = ""
                            showComposer = true
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Self.messageAgentLabel)
                }
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

    // MARK: Compose overlay

    /// A dim scrim plus a bottom-docked message bar. The bar rides above the
    /// keyboard (default safe-area avoidance); tapping the scrim or the close
    /// button dismisses it. Sending routes to the originating chat, if any, or a
    /// session-bound chat, and starts watching that chat for the agent's reply.
    private var composeOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                // A scrim tap is an easy accidental target while typing; only
                // dismiss (destroying the draft) when the field is empty. Use the
                // close button to abandon a non-empty draft deliberately.
                .onTapGesture { if composeIsEmpty { dismissComposer() } }
            VStack(spacing: 0) {
                HStack {
                    Text(effectiveOriginatingChatID != nil ? "Message this chat" : Self.messageAgentLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        dismissComposer()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                AgentComposerBar(placeholder: Self.messageAgentLabel,
                                 showsMentionButton: false,
                                 autoFocus: true,
                                 // Disable only if the RESOLVED target chat is
                                 // deleted (independent of openChatID, which a tab
                                 // round-trip can repoint). A dead originating chat
                                 // switches effectiveOriginatingChatID to nil
                                 // (recovery), so this stays enabled and the next
                                 // send creates a fresh session-bound chat.
                                 isDisabled: composerTargetIsDeleted,
                                 onEmptyChanged: { composeIsEmpty = $0 },
                                 initialText: composeInitialText,
                                 seedGeneration: composerSeedGeneration) { text in
                    sendComposed(text)
                }
            }
            .background(.regularMaterial)
        }
        .transition(.opacity)
    }

    private func sendComposed(_ text: String) {
        // Single point that rejects empty input, BEFORE any watch claim, since a
        // claim not followed by a real send would cancel a concurrent view's watch.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dismissComposer()
            return
        }
        dismissComposer()
        // Before the first consented send, ask whether to include the session's
        // terminal state + visible screen with AI messages. If needed, block on the
        // modal (its buttons call performSend); otherwise send straight through.
        Task {
            if await model.shouldPromptAutoProvideConsent(sessionGuid: guid) {
                pendingConsentText = text
                showAutoProvideConsentAlert = true
            } else {
                performSend(text, grantAutoProvideConsent: false)
            }
        }
    }

    private func performSend(_ text: String, grantAutoProvideConsent: Bool) {
        // Claim the watch slot right before the send Task so the view's onDisappear
        // clears it if the view leaves, and keep the prior claim to restore on failure.
        let claim = model.claimSessionWatch(token: watchToken)
        Task {
            let outcome = await model.sendFromSessionView(text: text,
                                                          sessionGuid: guid,
                                                          resolvedChatID: composeChatID,
                                                          originatingChatID: effectiveOriginatingChatID,
                                                          grantAutoProvideConsent: grantAutoProvideConsent,
                                                          watchToken: watchToken,
                                                          claimSequence: claim.sequence)
            switch outcome {
            case .sent(let chatID):
                // Only advance on a successful resolution; a failed/empty send
                // must not clobber an already-resolved id.
                composeChatID = chatID
            case .failed(let message):
                restoreFailedDraft(text, error: message, claim: claim)
            case .chatDeleted(let message):
                // Drop BOTH the dead resolved id and (if the dead target was the
                // @-mention's originating chat) the preference for originatingChatID,
                // so the NEXT send re-resolves and creates a fresh session-bound
                // chat instead of re-targeting the deleted chat every time.
                composeChatID = nil
                originatingChatIsDead = true
                restoreFailedDraft(text, error: message, claim: claim)
            }
        }
    }

    /// Restore a failed send's draft: show the error, undo the watch claim, and
    /// re-seed the (optimistically cleared) text so the user can retry.
    private func restoreFailedDraft(_ text: String, error: String,
                                    claim: AppModel.SessionWatchClaim) {
        sendError = error
        model.restoreSessionWatchClaim(claim)
        // The bar cleared the draft optimistically and the overlay was dismissed;
        // restore the text. Any optimistic echo (the @-mention case, where the
        // originating chat is open below) was rolled back on the failed publish, so
        // the restored draft is the sole representation of the failed send.
        composeInitialText = text
        composeIsEmpty = false
        // Request a re-seed (edge-triggered) so the draft is restored even if the
        // composer instance is reused mid-exit-animation.
        composerSeedGeneration += 1
        showComposer = true
    }

    private func dismissComposer() {
        showComposer = false
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

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        // A safe-area change (rotation, bar show/hide) must re-flow the content insets;
        // schedule a layout pass so the coordinator's applyLayout re-reads them.
        setNeedsLayout()
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
    /// The live canvas area in points, used to compute a legible grid size for the
    /// resize button. Captured from a background GeometryReader so reading it does
    /// not disturb the canvas layout.
    @State private var viewportSize: CGSize = .zero
    /// Diagnostics: log only the first media frame received per view, so a working
    /// (or stalled) stream is visible in the log without spamming per frame.
    @State private var didLogFirstMedia = false

    /// The one-time discoverability tip: shown until the user first opens the on-screen
    /// keyboard (persisted in AppModel), and only when the mac accepts input and the
    /// stream is live. Reactive via AppModel observation - no timer, no manual state.
    private var showKeyboardTip: Bool {
        model.keyInputSupported && !model.didRevealSessionKeyboard && endedReason == nil
    }

    var body: some View {
        ZStack {
            // Overlays pinned within the safe area, so the nav bar and tab bar never
            // hide them even though the canvas below fills edge to edge.
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
                // The canvas fills black regardless of the device appearance, so
                // the default label-colored title/icon/description render dark-on-
                // black and are nearly invisible in light mode. Force dark scheme
                // here (mirroring the nav bar's .toolbarColorScheme) so they stay
                // light on the black background.
                .environment(\.colorScheme, .dark)
            }
            if showKeyboardTip {
                VStack {
                    Spacer()
                    Label("Tap on terminal contents to open keyboard", systemImage: "keyboard")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Fill the screen edge to edge, behind the translucent nav bar and tab bar,
            // so the video can scroll into those regions. The canvas is kept full-bleed
            // here - a background stack that ignores the safe area - rather than by
            // putting .ignoresSafeArea() on the representable directly, which does not
            // reliably expand a UIViewRepresentable. Because this fills the whole screen,
            // the scroll view's own safeAreaInsets are the real bar insets, which
            // applyLayout turns into content insets: at rest the terminal sits within the
            // safe area and only reaches behind the bars (and only then wheels) when
            // pushed there. See LiveCanvas.Coordinator.applyLayout.
            //
            // Passing the selection range (read here) makes SwiftUI re-run updateUIView
            // when it changes, so the canvas repositions its handles.
            ZStack {
                Color.black
                LiveCanvas(holder: holder, model: model, guid: guid,
                           isLive: endedReason == nil,
                           layout: model.liveCanvasLayout,
                           selectionRange: model.activeSelectionRange)
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.25), value: showKeyboardTip)
        // A left-edge drag would otherwise trigger the swipe-back gesture instead
        // of starting a selection there. Disable swipe-back while selection is
        // available; the back button still works.
        .background {
            if model.sessionSelectionSupported {
                SwipeBackDisabler()
            }
        }
        // Track the canvas size (and re-track on rotation) without perturbing the
        // layout, so the resize button knows the viewport it should fit the grid to.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewportSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in viewportSize = size }
            }
        }
        .toolbar {
            // Only offer the resize control when the mac is new enough to honor it;
            // an older mac would silently ignore the resizeSession message.
            if model.sessionResizeSupported {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.resizeActiveSessionForLegibility(viewSize: viewportSize)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("Resize for This Screen")
                    // Disabled when the mac reports the session's window cannot be
                    // resized (full screen, maximized, edge-attached, or width-locked).
                    .disabled(endedReason != nil || viewportSize == .zero || !model.activeStreamCanResize)
                }
            }
        }
        .task(id: guid) { start() }
        .onAppear {
            companionLog("LiveSessionView appeared for \(guid): macSupportsStreaming=\(model.macSupportsStreaming) macRevision=\(model.macRevision) sessionResizeSupported=\(model.sessionResizeSupported) (need >= \(CompanionProtocolVersion.sessionResizeRevision)) -> resize button \(model.sessionResizeSupported ? "SHOWN" : "HIDDEN"); activeStreamCanResize=\(model.activeStreamCanResize) viewportSize=\(Int(viewportSize.width))x\(Int(viewportSize.height))")
        }
        .onChange(of: model.sessionResizeSupported) { _, supported in
            companionLog("LiveSessionView: sessionResizeSupported changed to \(supported) (macRevision=\(model.macRevision)) -> resize button \(supported ? "SHOWN" : "HIDDEN")")
        }
        .onChange(of: model.activeStreamCanResize) { _, canResize in
            companionLog("LiveSessionView: activeStreamCanResize changed to \(canResize) -> resize button \(canResize ? "enabled" : "disabled")")
        }
        .onDisappear { model.stopWatchingSessionLive() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                companionLog("SessionView scenePhase active -> resumeLiveStream")
                model.resumeLiveStream()
            case .background:
                companionLog("SessionView scenePhase background -> pauseLiveStream")
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
                    companionLog("LiveSessionView onConfig: stream=\(config.streamID) gen=\(config.generationId) \(config.pixelWidth)x\(config.pixelHeight) grid=\(config.columns)x\(config.rows) -> configuring decoder")
                    holder.view.configure(parameterSets: parameterSets)
                } else {
                    companionLog("LiveSessionView onConfig: stream=\(config.streamID) \(config.pixelWidth)x\(config.pixelHeight) but FAILED to decode parameter sets from \(config.codecExtradata.count)-byte extradata")
                }
            },
            onMedia: { [weak model] frame in
                if !didLogFirstMedia {
                    didLogFirstMedia = true
                    companionLog("LiveSessionView onMedia: first frame received (\(frame.payload.count) bytes, pts=\(frame.ptsMilliseconds)) -> decoding")
                }
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
    /// The session the on-screen keyboard types into.
    let guid: String
    /// Whether the session is still live. When it has ended, a tap must not raise the
    /// keyboard (typed keys would be silently dropped on the mac).
    let isLive: Bool
    /// Drives a relayout (history extent / geometry) when it changes.
    let layout: CompanionLiveCanvasLayout?
    /// Drives handle repositioning: a change re-runs updateUIView.
    let selectionRange: CompanionSelectionRange?

    func makeCoordinator() -> Coordinator { Coordinator(holder: holder, model: model, guid: guid) }
    func makeUIView(context: Context) -> UIView { context.coordinator.makeContainer() }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.setLive(isLive)
        // guid can change in place when SwiftUI reuses this representable for a
        // different session (the same reason .task(id: guid) restarts the stream);
        // the keyboard send closure reads it at call time, so refreshing it here keeps
        // keystrokes routed to the visible session, and clears leftover modifier state.
        context.coordinator.setGuid(guid)
        context.coordinator.installTileSlotCallback()
        context.coordinator.layout = layout
        context.coordinator.applyWheelMode()
        context.coordinator.applyLayout()
        context.coordinator.repositionHandles()
        context.coordinator.updateSelectionTiles()
    }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.tearDown() }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        let holder: LiveVideoHolder
        var model: AppModel
        /// The session the on-screen keyboard types into. A `var` (not `let`) because a
        /// reused coordinator can be handed a new guid via updateUIView; the keyboard
        /// send closure reads it at call time.
        var guid: String
        /// Whether the session is still live (refreshed from updateUIView). A tap only
        /// raises the keyboard while live, so keys can't be typed into an ended session.
        var isLive = true
        /// The canvas root, a UIKeyInput first responder so a tap raises the keyboard.
        private let container = CompanionKeyboardInputView()
        /// Drives the on-screen keyboard: routes typed + accessory keys to the session.
        private let keyboardController = SessionKeyboardController()
        private let scrollView = LayoutObservingScrollView()
        private let contentView = UIView()
        private let loupe = LoupeUIView()
        private let startHandle = SelectionHandleView()
        private let endHandle = SelectionHandleView()
        private var editMenu: UIEditMenuInteraction!
        private var selecting = false
        private var draggingStart = false
        private var draggingEnd = false
        /// The last live point sent during the current drag, used to finalize with a
        /// valid .end even if the ending touch cannot be mapped (degenerate geometry),
        /// so the host never keeps a selection live indefinitely.
        private var lastDragLivePoint: CompanionSelectionPoint?
        private var menuAnchor: CGPoint = .zero
        private let loupeDiameter: CGFloat = 120
        /// Extra breathing room added below the safe-area bottom inset, so the last
        /// line sits a little above the tab bar rather than flush against it.
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
        /// The generation the tiles were rendered against; a change (e.g. column
        /// reflow) re-renders every tile, so cached ones must be dropped.
        private var laidOutGeneration: UInt32?
        private var didScrollToBottom = false
        // History tiles, keyed by tile index (0 = oldest), like the static path.
        private var tileViews: [Int: TileView] = [:]
        private var requestedTiles: Set<Int> = []
        /// Tiles whose last fetch returned a host-reported failure. The idle 4 Hz
        /// re-drive skips these (retrying them every pass would strobe spinner/retry-label
        /// and spam the relay); an explicit scroll/zoom/grow still retries them.
        private var failedTiles: Set<Int> = []
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
        /// Last visible tile range logged, so refreshTiles logs only on change.
        private var lastLoggedVisibleRange: (Int, Int)?
        private let linesPerTile = 50
        private var growthTimer: Timer?
        /// Set while a throttled-tile re-drive is already scheduled, so a viewport full
        /// of throttled tiles coalesces into a single follow-up refreshTiles.
        private var tileRefreshScheduled = false

        // Scroll-to-wheel (alt screen + mouse reporting). A single-finger pan tracked
        // alongside the scroll view: normal panning of a zoomed band scrolls, and only
        // motion pushing PAST the top/bottom edge is converted to wheel notches and
        // sent to the terminal. At zoom 1 the band already fits, so every drag wheels.
        private var wheelPan: UIPanGestureRecognizer?
        private var lastWheelTranslationY: CGFloat = 0
        /// Past-edge motion not yet turned into whole notches (points). Positive =
        /// reveal older (up), negative = reveal newer (down).
        private var wheelAccumulator: CGFloat = 0
        /// True when the mac reports the session is on the alt screen with mouse-wheel
        /// reporting on: scroll gestures become wheel input instead of scrollback.
        private var wheelScrollMode: Bool {
            layout?.altScreen == true && layout?.scrollWheelReporting == true
        }

        init(holder: LiveVideoHolder, model: AppModel, guid: String) {
            self.holder = holder
            self.model = model
            self.guid = guid
            super.init()
        }

        /// Adopt a new session guid when SwiftUI reuses this coordinator in place. Any
        /// armed/locked keyboard modifier or open tray belongs to the previous session,
        /// so clear it - otherwise the next keystroke into the new session could carry a
        /// modifier the user never armed for it.
        func setGuid(_ newGuid: String) {
            guard newGuid != guid else {
                return
            }
            guid = newGuid
            keyboardController.reset()
        }

        /// Track whether the session is still live. When it ends (or the canvas is
        /// reused for an already-ended session), dismiss the on-screen keyboard: keys
        /// typed into a dead session are silently dropped on the mac, so leaving the
        /// keyboard up would make typing vanish with no feedback.
        func setLive(_ live: Bool) {
            isLive = live
            if !live {
                container.resignFirstResponder()
            }
        }

        func tearDown() {
            container.resignFirstResponder()
            editMenu?.dismissMenu()
            growthTimer?.invalidate()
            growthTimer = nil
            // Only clear the shared slot-available callback if we still own it; a
            // sibling coordinator (e.g. the session-mention preview) may have claimed it.
            if model.historyTileSlotOwner == ObjectIdentifier(self) {
                model.onHistoryTileSlotAvailable = nil
                model.historyTileSlotOwner = nil
            }
        }

        /// Claim the shared slot-available callback for this coordinator. Called from
        /// updateUIView so a reused coordinator reappearing (a TabView switch back) that
        /// a sibling had overwritten reinstalls its own; makeContainer runs only once and
        /// so cannot.
        func installTileSlotCallback() {
            model.historyTileSlotOwner = ObjectIdentifier(self)
            model.onHistoryTileSlotAvailable = { [weak self] in self?.scheduleTileRefresh() }
        }

        func makeContainer() -> UIView {
            container.backgroundColor = .black
            // On-screen keyboard: route typed characters and accessory-bar keys to
            // this session, and let the accessory dismiss the keyboard. Installing the
            // accessory is harmless when the mac is too old; handleTap gates whether a
            // tap actually raises the keyboard on model.keyInputSupported.
            keyboardController.send = { [weak self] event in
                guard let self else { return }
                self.model.sendKey(event, toSessionGuid: self.guid)
            }
            keyboardController.dismiss = { [weak self] in
                self?.container.resignFirstResponder()
            }
            container.installAccessory(controller: keyboardController)
            scrollView.frame = container.bounds
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 6
            scrollView.delegate = self
            scrollView.backgroundColor = .black
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            // We manage content insets ourselves in applyLayout (from the safe area),
            // so keep UIKit's automatic adjustment off. With .never, adjustedContentInset
            // equals our contentInset exactly, which the scroll limits, the initial
            // bottom-pin, and the wheel-mode edge detection all rely on.
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.bouncesZoom = true
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

            // Single-finger pan for scroll-to-wheel, enabled only in wheel mode. It
            // recognizes simultaneously with the scroll view's own pan (so a zoomed
            // band still scrolls) and reads the raw finger translation, which keeps
            // growing past the hard edge. maximumNumberOfTouches = 1 leaves two-finger
            // pinch zoom to the scroll view.
            let wheelPan = UIPanGestureRecognizer(target: self, action: #selector(handleWheelPan(_:)))
            wheelPan.delegate = self
            wheelPan.maximumNumberOfTouches = 1
            wheelPan.isEnabled = false
            scrollView.addGestureRecognizer(wheelPan)
            self.wheelPan = wheelPan

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

        /// Content insets that hold the content within the safe area at rest while the
        /// scroll view itself fills the screen edge to edge: the safe area on every side
        /// (the nav bar on top, the tab bar plus a small margin on the bottom, and the
        /// dynamic island / home indicator on the sides in landscape). Because the scroll
        /// view uses .never adjustment, these ARE the adjustedContentInset, so the scroll
        /// limits, the initial pin, and the wheel-mode edge detection all account for
        /// them: the content only reaches behind the bars/island - and only then wheels -
        /// once it is scrolled past the inset. The horizontal insets are what let you
        /// scroll the edge columns out from under the island (at zoom 1 the video already
        /// fills the full width, so without them those columns can never be cleared).
        private func desiredContentInsets() -> UIEdgeInsets {
            let safe = scrollView.safeAreaInsets
            return UIEdgeInsets(top: safe.top, left: safe.left,
                                bottom: safe.bottom + Self.bottomMargin, right: safe.right)
        }

        /// Apply new content insets only when they change, so a no-op layout pass does
        /// not perturb the scroll offset.
        private func applyContentInsets(_ insets: UIEdgeInsets) {
            guard scrollView.contentInset != insets else { return }
            scrollView.contentInset = insets
            scrollView.verticalScrollIndicatorInsets.bottom = insets.bottom
        }

        /// Lay out the scrollable document: history fills the top, the live video is
        /// a band at the bottom (the last `rows` lines). The document grows as the
        /// live top advances (new output scrolls into history); if the view was
        /// pinned to the bottom it stays there (following), otherwise the offset is
        /// preserved (browsing) since the content above is unchanged.
        func applyLayout() {
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let desiredInset = desiredContentInsets()
            // No geometry yet: fall back to the video filling the viewport.
            guard let layout, layout.imageSize.width > 0, layout.rows > 0, layout.totalLines > 0 else {
                applyContentInsets(desiredInset)
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
            // Alt screen: hide scrollback and show only the mutable section. Clamping
            // totalLines to rows makes historyLines 0, the document exactly the video
            // band, and requests no history tiles. The shrink detection below tears
            // down any cached tiles from the primary buffer; on exit the extent grows
            // back and scrollback reappears.
            let totalLines = layout.altScreen ? layout.rows : max(layout.totalLines, derivedTotal)

            let key = "\(Int(size.width))x\(Int(size.height))|\(layout)|\(totalLines)|\(Int(desiredInset.top)),\(Int(desiredInset.bottom)),\(Int(desiredInset.left)),\(Int(desiredInset.right))"
            guard key != appliedKey else { return }
            // Measure the pinned state against the OLD inset before switching to the new
            // one, so a safe-area change (rotation) re-pins to the bottom correctly.
            let wasAtBottom = isPinnedToBottom
            appliedKey = key
            applyContentInsets(desiredInset)

            // Drop every tile view when the content they show is no longer valid:
            // the history origin advanced (scrollback trimmed), the document shrank
            // (cleared), or the generation changed (a mid-stream geometry change such
            // as column reflow re-rendered every tile at new line boundaries). They
            // refetch (hitting the cache for survivors); the model cache was pruned.
            let shrank = totalLines < laidOutTotalLines
            let generationChanged = laidOutGeneration != nil && laidOutGeneration != layout.generationId
            if let prev = laidOutFirstAbsLine, prev != layout.firstAbsLine || shrank || generationChanged {
                for view in tileViews.values { view.removeFromSuperview() }
                tileViews.removeAll()
                requestedTiles.removeAll()
                failedTiles.removeAll()
                tileFetchedLines.removeAll()
                tileToken.removeAll()
                // Tile indices are relative to the origin; force selection tiles to
                // be recomputed against the new origin.
                selectedTileIndices.removeAll()
                lastSelectionEndpoints = nil
            }
            laidOutFirstAbsLine = layout.firstAbsLine
            laidOutTotalLines = totalLines
            laidOutGeneration = layout.generationId

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
            if !didScrollToBottom {
                // First layout: pin to the bottom and place the left edge just clear of
                // the left safe-area inset (the dynamic island in landscape), so the
                // start of each line is readable without scrolling.
                didScrollToBottom = true
                scrollToBottom(resetHorizontal: true)
            } else if wasAtBottom {
                // Following live output: keep any horizontal scroll the user set (e.g.
                // to read the right columns) and only re-pin the vertical position.
                scrollToBottom(resetHorizontal: false)
            }
            companionLog("canvas layout size=\(Int(size.width))x\(Int(size.height)) inset=\(Int(desiredInset.top))/\(Int(desiredInset.bottom))/\(Int(desiredInset.left))/\(Int(desiredInset.right)) firstAbs=\(layout.firstAbsLine) total=\(totalLines) hist=\(historyLines) ppl=\(String(format: "%.2f", pointsPerLine)) videoTop=\(Int(videoRect.minY)) docH=\(Int(documentHeight)) offset=\(Int(scrollView.contentOffset.x)),\(Int(scrollView.contentOffset.y)) wasAtBottom=\(wasAtBottom)")
            refreshTiles()
        }

        private var isPinnedToBottom: Bool {
            let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            return scrollView.contentOffset.y >= maxY - 1
        }

        /// Pin the vertical offset to the bottom (last line just above the tab-bar inset).
        /// When `resetHorizontal` is true, also move the left edge just clear of the left
        /// safe-area inset; otherwise keep the current horizontal scroll.
        private func scrollToBottom(resetHorizontal: Bool = true) {
            let maxY = max(-scrollView.adjustedContentInset.top,
                           scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            let x = resetHorizontal ? -scrollView.adjustedContentInset.left : scrollView.contentOffset.x
            scrollView.contentOffset = CGPoint(x: x, y: maxY)
        }

        /// Periodically grow the document as the live top advances, but never while
        /// the user is interacting (it would jolt) or zoomed in.
        private func growthTick() {
            // Never mutate the canvas mid-interaction.
            guard !scrollView.isDragging, !scrollView.isDecelerating, !scrollView.isZooming,
                  !selecting, !draggingStart, !draggingEnd else { return }
            // Recover tiles a flush (reconnect / resume) left as spinners, paced at 4 Hz.
            // This runs regardless of zoom (the layout-grow path below early-returns while
            // zoomed) so a zoomed-in scrollback view still recovers, and it self-heals the
            // race where the flush re-drive runs before the neutralized .throttled
            // completions clear requestedTiles. skipFailed so it does not retry
            // host-reported failures every pass (which would strobe / spam the relay).
            if model.hasActiveStream { refreshTiles(skipFailed: true) }
            // Grow the document as the live top advances (zoom 1 only; the scroll view
            // owns contentSize while zoomed and our changes would fight it).
            guard scrollView.zoomScale <= 1.001 else { return }
            applyLayout()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { repositionHandles(); refreshTiles() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { repositionHandles(); refreshTiles() }
        // A fling can settle with no further scroll event, so re-drive tiles once it
        // ends to pick up any that were throttle-dropped mid-fling.
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { refreshTiles() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { refreshTiles() }
        }

        // MARK: Scroll-to-wheel (alt screen + mouse reporting)

        /// Enable the wheel pan and disable rubber-band bounce while in wheel mode, so
        /// the top/bottom edge is a crisp hard stop the past-edge translation maps to
        /// wheel notches; restore normal scrolling otherwise.
        func applyWheelMode() {
            let on = wheelScrollMode
            wheelPan?.isEnabled = on
            scrollView.bounces = !on
        }

        /// Let the wheel pan run alongside the scroll view's own pan (so a zoomed band
        /// still scrolls while we observe the finger) and its pinch (kept for zoom).
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return g === wheelPan || other === wheelPan
        }

        @objc private func handleWheelPan(_ g: UIPanGestureRecognizer) {
            // A hold-then-drag selects; never wheel while selecting or dragging handles.
            guard wheelScrollMode, !selecting, !draggingStart, !draggingEnd else { return }
            switch g.state {
            case .began:
                lastWheelTranslationY = 0
                wheelAccumulator = 0
            case .changed:
                let translationY = g.translation(in: scrollView).y
                let delta = translationY - lastWheelTranslationY
                lastWheelTranslationY = translationY
                accrueWheel(delta: delta)
            case .ended, .cancelled, .failed:
                lastWheelTranslationY = 0
                wheelAccumulator = 0
            default:
                break
            }
        }

        /// Convert past-edge finger motion into wheel notches. In-range panning (when
        /// zoomed and not at an edge) is left to the scroll view and accrues nothing.
        private func accrueWheel(delta: CGFloat) {
            guard delta != 0 else { return }
            let offsetY = scrollView.contentOffset.y
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height
                                 + scrollView.adjustedContentInset.bottom)
            let atTop = offsetY <= minY + 0.5
            let atBottom = offsetY >= maxY - 0.5
            // Finger moving down (delta > 0) at the top reveals older content (up);
            // finger moving up (delta < 0) at the bottom reveals newer content (down).
            // At zoom 1 the band fits, so both edges are true and either direction wheels.
            if delta > 0 && atTop {
                wheelAccumulator += delta
            } else if delta < 0 && atBottom {
                wheelAccumulator += delta
            } else {
                return
            }
            // One notch per line of past-edge travel (fall back to a fixed step before
            // any layout has set pointsPerLine).
            let step = pointsPerLine > 0.5 ? pointsPerLine : 24
            let notches = Int(wheelAccumulator / step)
            guard notches != 0 else { return }
            wheelAccumulator -= CGFloat(notches) * step
            model.sendScrollWheel(up: notches > 0, lines: abs(notches))
        }

        /// Coalesce a follow-up refreshTiles after throttle-dropped tiles, so the drops
        /// are re-requested once the in-flight window drains, without scheduling one per
        /// dropped tile.
        private func scheduleTileRefresh() {
            guard !tileRefreshScheduled else { return }
            tileRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tileRefreshScheduled = false
                self.refreshTiles()
            }
        }

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
        /// - Parameter skipFailed: when true, tiles whose last fetch failed are left
        ///   alone (used by the idle auto re-drive so it does not retry host failures at
        ///   4 Hz). Explicit re-drives (scroll/zoom/grow/selection) leave it false so a
        ///   failed tile back in view still retries.
        private func refreshTiles(skipFailed: Bool = false) {
            guard let layout, historyLines > 0, pointsPerLine > 0, contentView.bounds.width > 0 else { return }
            let tileHeight = CGFloat(linesPerTile) * pointsPerLine
            guard tileHeight > 0 else { return }
            let visible = scrollView.convert(scrollView.bounds, to: contentView)
            let keep = visible.insetBy(dx: 0, dy: -visible.height)
            let tileCount = (historyLines + linesPerTile - 1) / linesPerTile
            let first = max(0, Int(floor(keep.minY / tileHeight)))
            let last = min(tileCount - 1, Int(floor(keep.maxY / tileHeight)))
            guard first <= last else { return }

            // Log only when the visible tile range changes, so scrolling does not spam.
            if lastLoggedVisibleRange?.0 != first || lastLoggedVisibleRange?.1 != last {
                lastLoggedVisibleRange = (first, last)
                companionLog("canvas visible tiles \(first)...\(last) of \(tileCount) offsetY=\(Int(scrollView.contentOffset.y)) zoom=\(String(format: "%.2f", scrollView.zoomScale))")
            }

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
                } else if !requestedTiles.contains(index), !(skipFailed && failedTiles.contains(index)) {
                    // Missing, or grew since last fetch: (re)render for the current
                    // count. Keep the old (correctly-sized) image visible meanwhile
                    // (showLoading is a no-op once a tile already has an image).
                    view.showLoading()
                    requestedTiles.insert(index)
                    let token = nextTileToken(index)
                    model.invalidateHistoryTile(firstAbsLine: absLine)
                    model.requestHistoryTile(firstAbsLine: absLine, lineCount: expected) { [weak self] outcome in
                        // Ignore a superseded reply (a newer request for this tile ran).
                        guard let self, self.tileToken[index] == token else { return }
                        self.requestedTiles.remove(index)
                        guard let view = self.tileViews[index] else { return }
                        switch outcome {
                        case .image(let image):
                            self.failedTiles.remove(index)
                            self.tileFetchedLines[index] = expected
                            view.frame = self.tileFrame(index: index)
                            view.show(image: image)
                            // A rendered tile may have grown (live tail) since we asked;
                            // catch up. Gated to .image so a saturated .throttled does not
                            // trigger a re-request loop, and a .failed is not silently
                            // re-requested without an explicit retry decision.
                            if self.expectedLines(index: index) != expected { self.refreshTiles() }
                        case .throttled:
                            // Transient: keep any currently-shown image (do not flash a
                            // failure). Do NOT self-schedule a refresh here: while the
                            // throttle is saturated that would busy-loop (re-request ->
                            // reject -> reschedule). The model's onHistoryTileSlotAvailable
                            // re-drives us when a slot actually frees; a settled fling is
                            // also covered by scrollViewDidEndDecelerating.
                            break
                        case .failed:
                            if self.expectedLines(index: index) != expected {
                                // Grew while in flight: this failure is for a stale line
                                // count. Retry at the new size instead of leaving a stuck
                                // X the idle pass would skip (do not mark it failed).
                                self.refreshTiles()
                            } else {
                                self.failedTiles.insert(index)
                                view.showFailure()
                            }
                        }
                    }
                }
            }

            let discard = visible.insetBy(dx: 0, dy: -3 * visible.height)
            var discardedAbsLines: Set<Int64> = []
            for (index, view) in tileViews where !view.frame.intersects(discard) {
                view.removeFromSuperview()
                tileViews[index] = nil
                requestedTiles.remove(index)
                // A re-shown tile should retry from scratch, not stay suppressed.
                failedTiles.remove(index)
                // Collect for a single pending-queue prune below (a fling discards many
                // tiles per pass; scanning the queue once beats once per tile). `layout`
                // is the non-optional local unwrapped at the top of refreshTiles.
                discardedAbsLines.insert(layout.firstAbsLine + Int64(index * linesPerTile))
                // Keep tileFetchedLines so a re-shown tile uses the cache; a cache
                // miss (e.g. generation change) still triggers a refetch.
            }
            // Drop still-queued requests for the flung-past tiles so they do not spend
            // in-flight slots and relay budget (an already-issued fetch warms the cache).
            model.cancelPendingHistoryTiles(firstAbsLines: discardedAbsLines)
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

        /// Content points per encoded pixel (the video fills the width at zoom 1).
        private var pointsPerPixel: CGFloat {
            guard let layout, layout.imageSize.width > 0, contentView.bounds.width > 0 else { return 0 }
            return contentView.bounds.width / layout.imageSize.width
        }

        /// Width of one cell in content points. The rendered frame includes the side
        /// margins, so derive this from the reported cell width rather than dividing
        /// the full image width by the columns (which would smear the margins across
        /// every cell). Falls back to the margin-free estimate for an old host.
        private var cellWidthPoints: CGFloat {
            guard let layout, layout.columns > 0, contentView.bounds.width > 0 else { return 0 }
            if let geometry = layout.cellGeometry, geometry.cellWidth > 0 {
                return CGFloat(geometry.cellWidth) * pointsPerPixel
            }
            return contentView.bounds.width / CGFloat(layout.columns)
        }

        /// Left side margin in content points (0 for an old host, or if the mapping
        /// falls back to the margin-free estimate above).
        private var leftMarginPoints: CGFloat {
            guard let layout, let geometry = layout.cellGeometry, geometry.cellWidth > 0 else { return 0 }
            return CGFloat(geometry.leftMargin) * pointsPerPixel
        }

        /// A point anywhere in the document to an absolute terminal point, clamped to
        /// the available lines/columns. Works for both history and the live band.
        private func selectionPoint(atContent p: CGPoint) -> CompanionSelectionPoint? {
            guard let layout, pointsPerLine > 0, cellWidthPoints > 0 else { return nil }
            let col = min(max(Int(((p.x - leftMarginPoints) / cellWidthPoints).rounded(.down)), 0), layout.columns - 1)
            let line = Int((p.y / pointsPerLine).rounded(.down))
            let lastLine = max(0, historyLines + layout.rows - 1)
            let clampedLine = min(max(line, 0), lastLine)
            return CompanionSelectionPoint(absLine: layout.firstAbsLine + Int64(clampedLine), column: col)
        }

        /// The content-space point of a cell corner, for placing handles / highlights.
        private func contentPoint(absLine: Int64, column: Int, rightEdge: Bool, bottomEdge: Bool) -> CGPoint {
            let line = CGFloat(absLine - (layout?.firstAbsLine ?? 0))
            return CGPoint(x: leftMarginPoints + (CGFloat(column) + (rightEdge ? 1 : 0)) * cellWidthPoints,
                           y: (line + (bottomEdge ? 1 : 0)) * pointsPerLine)
        }

        private func videoLocal(_ contentPoint: CGPoint) -> CGPoint {
            CGPoint(x: contentPoint.x - videoRect.minX, y: contentPoint.y - videoRect.minY)
        }

        @objc private func handleStartPan(_ gesture: UIPanGestureRecognizer) { handleHandlePan(gesture, isStart: true) }
        @objc private func handleEndPan(_ gesture: UIPanGestureRecognizer) { handleHandlePan(gesture, isStart: false) }

        /// Drag an endpoint, anchoring the selection at the opposite one. Raw
        /// inclusive coordinates go to the host, which resolves exclusivity by
        /// document order (so backward and crossing drags stay correct).
        private func handleHandlePan(_ gesture: UIPanGestureRecognizer, isStart: Bool) {
            let point = gesture.location(in: contentView)
            switch gesture.state {
            case .began:
                guard let endpoints = model.activeSelectionEndpoints else { return }
                if isStart { draggingStart = true } else { draggingEnd = true }
                scrollView.isScrollEnabled = false
                editMenu.dismissMenu()
                // Reconstruct the EXACT current selection from the known endpoints so
                // grabbing a handle never shifts it: the fixed handle is the anchor,
                // this handle is the live endpoint. Using the endpoints (not a
                // touch-mapped cell) avoids any grab-time bias.
                let live = isStart ? endpoints.start : endpoints.end
                model.sendSelectionGesture(phase: .begin, mode: .character,
                                           point: isStart ? endpoints.end : endpoints.start)
                model.sendSelectionGesture(phase: .move, mode: .character, point: live)
                lastDragLivePoint = live
                moveHandle(isStart: isStart, toContentPoint: point)
                showLoupe(at: point)
            case .changed:
                guard let live = handleSelectionPoint(atContent: point, isStart: isStart) else { return }
                lastDragLivePoint = live
                model.sendSelectionGesture(phase: .move, mode: .character, point: live)
                moveHandle(isStart: isStart, toContentPoint: point)
                showLoupe(at: point)
            case .ended, .cancelled, .failed:
                // Only finalize a drag that actually began: if .began bailed (no
                // active selection), this handle never sent begin/move, so a stray
                // .end would create a spurious one-cell selection on the host.
                guard isStart ? draggingStart : draggingEnd else { return }
                draggingStart = false
                draggingEnd = false
                scrollView.isScrollEnabled = true
                // Always finalize: fall back to the last live point if this touch
                // cannot be mapped, so the host runs endLive and does not leave the
                // selection live.
                if let live = handleSelectionPoint(atContent: point, isStart: isStart) ?? lastDragLivePoint {
                    model.sendSelectionGesture(phase: .end, mode: .character, point: live)
                }
                lastDragLivePoint = nil
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

        /// Map a handle-drag touch to an inclusive cell. A handle sits on a cell/line
        /// BOUNDARY (the start handle at the top-left of its cell, the end handle at
        /// the bottom-right), so snap the touch to the nearest boundary and take the
        /// cell on the selection's side of it. Plain floor() mapping put the end
        /// handle one cell/line too far, growing the selection by one on a grab.
        private func handleSelectionPoint(atContent p: CGPoint, isStart: Bool) -> CompanionSelectionPoint? {
            guard let layout, pointsPerLine > 0, cellWidthPoints > 0 else { return nil }
            let colBoundary = Int(((p.x - leftMarginPoints) / cellWidthPoints).rounded())
            let lineBoundary = Int((p.y / pointsPerLine).rounded())
            let col = isStart ? colBoundary : colBoundary - 1
            let line = isStart ? lineBoundary : lineBoundary - 1
            let clampedCol = min(max(col, 0), layout.columns - 1)
            let lastLine = max(0, historyLines + layout.rows - 1)
            let clampedLine = min(max(line, 0), lastLine)
            return CompanionSelectionPoint(absLine: layout.firstAbsLine + Int64(clampedLine), column: clampedCol)
        }

        // MARK: Selection

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: contentView)
            switch gesture.state {
            case .began:
                guard let sel = selectionPoint(atContent: point) else { return }
                selecting = true
                scrollView.isScrollEnabled = false
                editMenu.dismissMenu()
                startHandle.isHidden = true
                endHandle.isHidden = true
                // Fresh drag: the first cell is the anchor; the host resolves
                // exclusivity by document order as the drag extends in either
                // direction.
                lastDragLivePoint = sel
                model.sendSelectionGesture(phase: .begin, mode: .character, point: sel)
                showLoupe(at: point)
            case .changed:
                guard selecting else { return }
                if let sel = selectionPoint(atContent: point) {
                    lastDragLivePoint = sel
                    model.sendSelectionGesture(phase: .move, mode: .character, point: sel)
                }
                showLoupe(at: point)
            case .ended, .cancelled, .failed:
                guard selecting else { return }
                selecting = false
                scrollView.isScrollEnabled = true
                // Always finalize with a valid point so the host runs endLive.
                if let sel = selectionPoint(atContent: point) ?? lastDragLivePoint {
                    model.sendSelectionGesture(phase: .end, mode: .character, point: sel)
                }
                lastDragLivePoint = nil
                loupe.removeFromSuperview()
                menuAnchor = clampToContainer(container.convert(point, from: contentView))
                editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: menuAnchor))
            default:
                break
            }
        }

        @objc private func handleTap() {
            editMenu.dismissMenu()
            // A tap with a selection up only clears it (a single tap should not both
            // dismiss the selection and pop the keyboard).
            if model.activeSelectionRange != nil {
                model.clearActiveSelection()
                return
            }
            // Otherwise the tap means "type here": raise the on-screen keyboard, but
            // only when the session is still live (an ended session drops every key on
            // the mac) and the mac can accept injected input (an older mac never
            // advertises support, so its keys would be dead). Only mark the tip
            // dismissed if the keyboard actually came up.
            //
            // isLive is the value from the last updateUIView. In the brief window
            // between the session ending on the mac and SwiftUI re-running updateUIView
            // (which calls setLive(false) -> resignFirstResponder), a tap could still
            // read isLive == true and raise the keyboard; the very next updateUIView
            // brings it back down. Self-correcting, so we don't re-read a per-guid ended
            // source of truth here.
            if isLive && model.keyInputSupported && container.becomeFirstResponder() {
                model.markSessionKeyboardRevealed()
            }
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
