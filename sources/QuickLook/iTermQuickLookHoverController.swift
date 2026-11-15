//
//  iTermQuickLookHoverController.swift
//  iTerm2SharedARC
//
//  Decides when hovering a web link should open a Quick Look popover and when it should close.
//  It is a pure state machine: the text view feeds it pointer, modifier and click events, timers
//  go through an injected scheduler, and open/close requests go out through a delegate. It only
//  observes input and never consumes an event. All points and rects are in the text view’s
//  coordinate system.
//

import AppKit

protocol iTermQuickLookCancellable {
    func cancel()
}

protocol iTermQuickLookScheduling {
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> iTermQuickLookCancellable
}

// Production scheduler. Timers run on the main run loop in the common modes so they still fire
// while the user is tracking the mouse.
final class iTermQuickLookTimerScheduler: iTermQuickLookScheduling {
    private final class TimerHandle: iTermQuickLookCancellable {
        private let timer: Timer

        init(timer: Timer) {
            self.timer = timer
        }

        func cancel() {
            timer.invalidate()
        }
    }

    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> iTermQuickLookCancellable {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            block()
        }
        RunLoop.main.add(timer, forMode: .common)
        return TimerHandle(timer: timer)
    }
}

// What the host can tell synchronously, on a pointer move, about the link under a point.
enum iTermQuickLookHoverImmediateLookup: Equatable {
    // A link that hover may preview, and the regions it occupies.
    case link(URL, [NSRect])
    // Nothing there would preview, so there is no need to resolve it later. The regions are those of
    // a link that won't preview, or empty when there is no link.
    case noLink([NSRect])
    // Only the full (asynchronous) resolution can tell.
    case unknown
}

protocol iTermQuickLookHoverControllerDelegate: AnyObject {
    // Finds the link under `point`. The completion may be called synchronously or later. `url` is nil
    // when there is no link; `linkRects` are the regions the link occupies.
    func hoverControllerResolveLink(at point: NSPoint,
                                    completion: @escaping (_ url: URL?, _ linkRects: [NSRect]) -> Void)
    // A cheap synchronous look at the link under `point`, done on pointer moves so the cue can show
    // as soon as the pointer enters a link.
    func hoverControllerLookUpLinkImmediately(at point: NSPoint) -> iTermQuickLookHoverImmediateLookup
    // Shows a preview for `url`, replacing any preview this controller opened earlier. Returns false
    // if the host declined (for example because the user opened a preview some other way); the
    // controller's earlier preview, if any, is then left as it was.
    func hoverControllerOpenPreview(url: URL, linkRects: [NSRect], at point: NSPoint) -> Bool
    func hoverControllerClosePreview()
    // The open preview’s frame, or nil when there is none.
    func hoverControllerPreviewFrame() -> NSRect?
    // Shows that the link under the pointer will preview (an underline and the URL), as Cmd-hover
    // does. Only in Hover mode, and only for links that pass the same gates as opening.
    func hoverControllerShowCue(url: URL, linkRects: [NSRect])
    // Removes the cue shown by hoverControllerShowCue.
    func hoverControllerClearCue()
    // Where the pointer is now, or nil when it is not over the view. Asked after the content moved
    // without a pointer event, when the point of the last move may no longer be where the pointer is.
    func hoverControllerPointerLocation() -> NSPoint?
}

@objc(iTermQuickLookHoverController)
class iTermQuickLookHoverController: NSObject {
    weak var delegate: iTermQuickLookHoverControllerDelegate?

    private let scheduler: iTermQuickLookScheduling
    private var mode = iTermQuickLookHoverMode.off
    private var delay: TimeInterval = 0
    private var autoCloseDelay: TimeInterval = 0
    private var allowlist = iTermQuickLookDomainAllowlist(string: "")
    // How long the pointer must rest before the link under it is resolved to show the cue, for links
    // the delegate can't look up immediately. nil turns the cue off. Only used in Hover mode, and
    // the settle timer only when shorter than the hover delay.
    var cueSettleDelay: TimeInterval?

    // Timer for resolving the link the pointer is resting on. Replaced on every qualifying move.
    private var pendingOpen: iTermQuickLookCancellable?
    // Timer for resolving the link under the pointer to show the cue before the preview opens.
    private var pendingCue: iTermQuickLookCancellable?
    // The link the cue is shown for. Reused when the hover delay elapses on it, so the link is
    // resolved once per link the pointer settles on.
    private var cue: (url: URL, linkRects: [NSRect])?
    // The regions of the last link the immediate lookup found that won't get a cue. Moves inside them
    // look nothing up again. Forgotten when the pointer leaves them and whenever what they cover
    // might have changed (content, scrolling, settings, input).
    private var rejectedLinkRects = [NSRect]()
    // Bumped whenever a pending open is cancelled or superseded so that a resolution that completes
    // afterwards (the delegate may answer asynchronously) is recognized as stale and dropped.
    private var generation = 0
    // Where the pending open and pending cue resolve the link. Follows the pointer when the content
    // moves under it without a pointer event.
    private var pendingPoint: NSPoint?
    // Bumped on each content shift, so only the latest shift's check of the pending cue counts.
    private var shiftGeneration = 0
    // True while a content shift's check of the pending cue is outstanding. A pending open that
    // fires meanwhile waits for it, since the cue it would reuse may be stale.
    private var checkingShiftedCue = false
    private var openWaitsForShiftCheck = false

    private var openURL: URL?
    private var linkRects = [NSRect]()
    private var autoClose: iTermQuickLookCancellable?
    private var clickedInPreview = false
    // True while the delegate is opening a preview. Opening may close the preview it replaces, and
    // a delegate that reports that close through previewClosed() must not reset the new preview.
    private var openingPreview = false

    private var isOpen: Bool {
        return openURL != nil
    }

    init(scheduler: iTermQuickLookScheduling) {
        self.scheduler = scheduler
        super.init()
    }

    @objc func configure(mode: iTermQuickLookHoverMode,
                         delay: TimeInterval,
                         autoCloseDelay: TimeInterval,
                         allowlistString: String) {
        self.mode = mode
        self.delay = delay
        self.autoCloseDelay = autoCloseDelay
        self.allowlist = iTermQuickLookDomainAllowlist(string: allowlistString)
        cancelPendingOpen()
        clearCue()
        rejectedLinkRects = []
    }

    // MARK: - Inputs

    @objc func pointerMoved(to point: NSPoint, commandDown: Bool, optionDown: Bool, windowActive: Bool) {
        cancelPendingOpen()
        if let cue, !cue.linkRects.contains(where: { $0.contains(point) }) {
            clearPendingCue()
        }
        if isOpen {
            if isInsideLinkOrPreview(point) {
                cancelAutoClose()
                return
            }
            startAutoCloseIfNeeded()
        }
        guard hoverAllowed(commandDown: commandDown, optionDown: optionDown, windowActive: windowActive) else {
            clearPendingCue()
            return
        }
        // While the pointer stays inside the cue's link, or a link already rejected, there is nothing
        // new to look up.
        if cue == nil, let settle = cueSettleDelay, mode == .hover {
            if rejectedLinkRects.contains(where: { $0.contains(point) }) {
                return
            }
            rejectedLinkRects = []
            switch delegate?.hoverControllerLookUpLinkImmediately(at: point) ?? .unknown {
            case let .link(url, rects):
                guard rects.contains(where: { $0.contains(point) }) else {
                    return
                }
                guard allowlist.allows(url) else {
                    rejectedLinkRects = rects
                    return
                }
                // The open timer reuses this, so the link isn't resolved again.
                showCueIfWanted(url: url, linkRects: rects)
            case let .noLink(rects):
                if rects.contains(where: { $0.contains(point) }) {
                    rejectedLinkRects = rects
                }
                return
            case .unknown:
                if settle < delay {
                    pendingPoint = point
                    pendingCue = scheduler.schedule(after: settle) { [weak self] in
                        self?.resolveCue()
                    }
                }
            }
        }
        pendingPoint = point
        pendingOpen = scheduler.schedule(after: delay) { [weak self] in
            self?.resolve()
        }
    }

    @objc func modifiersChanged(commandDown: Bool, optionDown: Bool) {
        if mode == .commandHover && !(commandDown && !optionDown) {
            cancelPendingOpen()
        }
    }

    @objc func mouseDown() {
        cancelPendingOpen()
        clearPendingCue()
        rejectedLinkRects = []
    }

    @objc func keyDown() {
        cancelPendingOpen()
        clearPendingCue()
        rejectedLinkRects = []
    }

    @objc func scrolled() {
        cancelPendingOpen()
        clearPendingCue()
        rejectedLinkRects = []
    }

    // The view lost keyboard focus, for example to another split pane. A pending cue would linger
    // unseen and come back on the next underline update, so drop it; the cue of an open preview
    // stays.
    @objc func focusLost() {
        guard !openingPreview else {
            return
        }
        cancelPendingOpen()
        clearPendingCue()
        rejectedLinkRects = []
    }

    // What the view shows changed (new output, lines scrolled off the top, a resize), so a rejected
    // link may no longer be where it was.
    @objc func contentChanged() {
        rejectedLinkRects = []
    }

    // The content may have moved under the pointer without a pointer event (lines dropped off the
    // top of a full scrollback, the screen scrolled, a resize). This happens on every line of
    // streaming output, often while the link under the pointer stays put (scrolled back), so the
    // pending cue and open are kept while the pointer is still on the cued link, with the link's
    // new regions, and dropped otherwise. The cue of an open preview stays.
    @objc func contentShifted() {
        rejectedLinkRects = []
        let pendingCueURL = cueBelongsToOpenPreview ? nil : cue?.url
        guard pendingOpen != nil || pendingCue != nil || pendingCueURL != nil else {
            return
        }
        guard let point = delegate?.hoverControllerPointerLocation() else {
            cancelPendingOpen()
            clearPendingCue()
            return
        }
        pendingPoint = point
        guard let pendingCueURL else {
            // Nothing is cued yet, so the timers resolve whatever is under the pointer when they fire.
            return
        }
        shiftGeneration += 1
        checkingShiftedCue = true
        let expectedGeneration = generation
        let expectedShiftGeneration = shiftGeneration
        let completion: (URL?, [NSRect]) -> Void = { [weak self] url, rects in
            guard let self,
                  self.generation == expectedGeneration,
                  self.shiftGeneration == expectedShiftGeneration else {
                return
            }
            self.shiftedCueChecked(expectedURL: pendingCueURL, url: url, linkRects: rects, at: point)
        }
        switch delegate?.hoverControllerLookUpLinkImmediately(at: point) ?? .unknown {
        case let .link(url, rects):
            completion(url, rects)
        case .noLink:
            completion(nil, [])
        case .unknown:
            delegate?.hoverControllerResolveLink(at: point, completion: completion)
        }
    }

    private func shiftedCueChecked(expectedURL: URL, url: URL?, linkRects rects: [NSRect], at point: NSPoint) {
        checkingShiftedCue = false
        guard url == expectedURL, rects.contains(where: { $0.contains(point) }) else {
            cancelPendingOpen()
            clearPendingCue()
            return
        }
        // Re-shows the cue only if the link's regions changed.
        showCueIfWanted(url: expectedURL, linkRects: rects)
        if openWaitsForShiftCheck {
            openWaitsForShiftCheck = false
            resolve()
        }
    }

    // The app or window lost focus.
    @objc func deactivated() {
        cancelPendingOpen()
        clearCue()
        rejectedLinkRects = []
        if isOpen && !clickedInPreview {
            closeHoverPreview()
        }
    }

    @objc func previewClicked() {
        guard isOpen else {
            return
        }
        clickedInPreview = true
        cancelAutoClose()
    }

    // The user (or something other than this controller) closed the preview.
    @objc func previewClosed() {
        guard !openingPreview else {
            return
        }
        cancelPendingOpen()
        clearCue()
        resetToIdle()
    }

    // MARK: - Private

    private func hoverAllowed(commandDown: Bool, optionDown: Bool, windowActive: Bool) -> Bool {
        guard windowActive else {
            return false
        }
        switch mode {
        case .off:
            return false
        case .hover:
            return true
        case .commandHover:
            return commandDown && !optionDown
        @unknown default:
            return false
        }
    }

    private func isInsideLinkOrPreview(_ point: NSPoint) -> Bool {
        if linkRects.contains(where: { $0.contains(point) }) {
            return true
        }
        return delegate?.hoverControllerPreviewFrame()?.contains(point) ?? false
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingCue?.cancel()
        pendingCue = nil
        pendingPoint = nil
        checkingShiftedCue = false
        openWaitsForShiftCheck = false
        generation += 1
    }

    private func clearCue() {
        guard cue != nil else {
            return
        }
        cue = nil
        delegate?.hoverControllerClearCue()
    }

    // The cue stays on the link of the preview it opened until that preview closes or is replaced,
    // so the preview is visibly tied to its link.
    private var cueBelongsToOpenPreview: Bool {
        return isOpen && cue?.url == openURL
    }

    // Clears the cue unless it marks the open preview's link.
    private func clearPendingCue() {
        guard !cueBelongsToOpenPreview else {
            return
        }
        clearCue()
    }

    private func showCueIfWanted(url: URL, linkRects rects: [NSRect]) {
        guard mode == .hover, cueSettleDelay != nil, cue?.url != url || cue?.linkRects != rects else {
            return
        }
        cue = (url, rects)
        delegate?.hoverControllerShowCue(url: url, linkRects: rects)
    }

    private func cancelAutoClose() {
        autoClose?.cancel()
        autoClose = nil
    }

    private func startAutoCloseIfNeeded() {
        guard autoClose == nil, !clickedInPreview, autoCloseDelay > 0 else {
            return
        }
        autoClose = scheduler.schedule(after: autoCloseDelay) { [weak self] in
            self?.autoCloseFired()
        }
    }

    private func autoCloseFired() {
        autoClose = nil
        cancelPendingOpen()
        closeHoverPreview()
    }

    private func closeHoverPreview() {
        clearCue()
        resetToIdle()
        delegate?.hoverControllerClosePreview()
    }

    private func resetToIdle() {
        cancelAutoClose()
        openURL = nil
        linkRects = []
        clickedInPreview = false
    }

    private func resolve() {
        pendingOpen = nil
        guard let point = pendingPoint else {
            return
        }
        if checkingShiftedCue {
            openWaitsForShiftCheck = true
            return
        }
        if let cue, cue.linkRects.contains(where: { $0.contains(point) }) {
            resolved(url: cue.url, linkRects: cue.linkRects, at: point)
            return
        }
        guard let delegate else {
            return
        }
        let expectedGeneration = generation
        delegate.hoverControllerResolveLink(at: point) { [weak self] url, rects in
            guard let self, self.generation == expectedGeneration else {
                return
            }
            self.resolved(url: url, linkRects: rects, at: point)
        }
    }

    private func resolveCue() {
        pendingCue = nil
        guard let point = pendingPoint, let delegate else {
            return
        }
        let expectedGeneration = generation
        delegate.hoverControllerResolveLink(at: point) { [weak self] url, rects in
            guard let self, self.generation == expectedGeneration else {
                return
            }
            guard let url, self.allowlist.allows(url), rects.contains(where: { $0.contains(point) }) else {
                return
            }
            self.showCueIfWanted(url: url, linkRects: rects)
        }
    }

    private func resolved(url: URL?, linkRects rects: [NSRect], at point: NSPoint) {
        guard let url, allowlist.allows(url), rects.contains(where: { $0.contains(point) }) else {
            return
        }
        showCueIfWanted(url: url, linkRects: rects)
        if url == openURL {
            // The pointer rests on another occurrence of the open link. Track that occurrence so the
            // preview does not auto-close while the pointer stays on it.
            linkRects = rects
            cancelAutoClose()
            return
        }
        openingPreview = true
        let opened = delegate?.hoverControllerOpenPreview(url: url, linkRects: rects, at: point) ?? false
        openingPreview = false
        guard opened else {
            return
        }
        cancelAutoClose()
        openURL = url
        linkRects = rects
        clickedInPreview = false
    }
}
