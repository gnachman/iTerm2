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

// A cell of the terminal's content, numbered so that it keeps its number while lines scroll off
// the top. Compared to tell whether the text under a still pointer moved. The main and alternate
// screens number their lines alike, so the screen is part of the cell.
struct iTermQuickLookHoverCell: Equatable {
    let line: Int64
    let column: Int32
    let alternateScreen: Bool
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
    // The content cell at `point`. Cheap: asked on each move that starts a pending open and again
    // when the content moves under the pointer.
    func hoverControllerCell(at point: NSPoint) -> iTermQuickLookHoverCell
    // Where the open preview's link is now, after the content moved, or nil if unknown. Empty once
    // the link has left the buffer.
    func hoverControllerPreviewLinkRects() -> [NSRect]?
    // The pointer rested on a web link for the hover delay, but the allowlist kept it from
    // previewing.
    func hoverControllerDeclinedLink(url: URL)
    // Any resolution still in flight is stale: its answer will be dropped, so the delegate should
    // stop it and must not keep anything from it.
    func hoverControllerCancelResolution()
}

extension iTermQuickLookHoverControllerDelegate {
    func hoverControllerPreviewLinkRects() -> [NSRect]? {
        return nil
    }

    func hoverControllerDeclinedLink(url: URL) {
    }

    func hoverControllerCancelResolution() {
    }
}

@objc(iTermQuickLookHoverController)
class iTermQuickLookHoverController: NSObject {
    weak var delegate: iTermQuickLookHoverControllerDelegate?

    private let scheduler: iTermQuickLookScheduling
    private var mode = iTermQuickLookHoverMode.off
    private var delay: TimeInterval = 0
    private var autoCloseDelay: TimeInterval = 0
    private var allowlist = iTermQuickLookDomainAllowlist(entries: [], allowsAllDomains: false)
    // How long the pointer must rest before the link under it is resolved to show the cue, for links
    // the delegate can't look up immediately. nil turns the cue off. Only used in Hover mode, and
    // the settle timer only when shorter than the hover delay.
    var cueSettleDelay: TimeInterval?

    // Timer for resolving the link the pointer is resting on. Replaced on every qualifying move.
    private var pendingOpen: iTermQuickLookCancellable?
    // Timer for resolving the link under the pointer to show the cue before the preview opens.
    private var pendingCue: iTermQuickLookCancellable?
    // The link the cue is shown for. Reused when the hover delay elapses on it, so the link is
    // resolved once per link the pointer settles on. `immediate` is true when the immediate lookup
    // (an OSC 8 hyperlink) found it, so a content shift can cheaply check it is still there.
    private var cue: (url: URL, linkRects: [NSRect], immediate: Bool)?
    // The regions of the last link the immediate lookup found that won't get a cue. Moves inside them
    // look nothing up again. Forgotten when the pointer leaves them and whenever what they cover
    // might have changed (content, scrolling, settings, input).
    private var rejectedLinkRects = [NSRect]()
    // True when the rejected link is a web link the allowlist refused. Resting on it still runs the
    // open timer, so the delegate hears that it was declined.
    private var rejectedLinkIsDeclined = false
    // Bumped whenever a pending open is cancelled or superseded so that a resolution that completes
    // afterwards (the delegate may answer asynchronously) is recognized as stale and dropped.
    private var generation = 0
    // Where the pending open and pending cue resolve the link. Follows the pointer when the content
    // moves under it without a pointer event.
    private var pendingPoint: NSPoint?
    // The point of the last move that started a hover and the content cell under it. Like
    // pendingPoint, the point follows a still pointer as the content moves. They outlive the
    // resolution (which may end with a declined open and the cue still showing) so that a shift
    // that leaves the pointer on the same cell changes nothing and repeats nothing.
    private var restingPoint: NSPoint?
    private var restingCell: iTermQuickLookHoverCell?
    // The inputs of the last pointer move, to replay it when the text under the pointer changes.
    private var commandDown = false
    private var optionDown = false
    private var windowActive = false

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

    func configure(mode: iTermQuickLookHoverMode,
                         delay: TimeInterval,
                         autoCloseDelay: TimeInterval,
                         allowlist: iTermQuickLookDomainAllowlist) {
        self.mode = mode
        self.delay = delay
        self.autoCloseDelay = autoCloseDelay
        self.allowlist = allowlist
        cancelPendingOpen()
        clearCue()
        forgetRejectedLink()
    }

    // MARK: - Inputs

    private func forgetRejectedLink() {
        rejectedLinkRects = []
        rejectedLinkIsDeclined = false
    }

    @objc func pointerMoved(to point: NSPoint, commandDown: Bool, optionDown: Bool, windowActive: Bool) {
        self.commandDown = commandDown
        self.optionDown = optionDown
        self.windowActive = windowActive
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
        // new to look up. The cue of the open preview doesn't count: off its link, the pointer may be
        // on another one, and the cheap lookup must answer before any full resolution.
        if cue == nil || cueBelongsToOpenPreview, let settle = cueSettleDelay, mode == .hover {
            if rejectedLinkRects.contains(where: { $0.contains(point) }) {
                guard rejectedLinkIsDeclined else {
                    return
                }
                schedulePendingOpen(at: point)
                return
            }
            forgetRejectedLink()
            switch delegate?.hoverControllerLookUpLinkImmediately(at: point) ?? .unknown {
            case let .link(url, rects):
                guard rects.contains(where: { $0.contains(point) }) else {
                    return
                }
                guard allowlist.allows(url) else {
                    rejectedLinkRects = rects
                    rejectedLinkIsDeclined = iTermQuickLookDomainAllowlist.isWebURL(url)
                    if rejectedLinkIsDeclined {
                        schedulePendingOpen(at: point)
                    }
                    return
                }
                // The open timer reuses this, so the link isn't resolved again.
                showCueIfWanted(url: url, linkRects: rects, immediate: true)
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
        schedulePendingOpen(at: point)
    }

    // Resolves the link under `point` once the pointer has rested there for the hover delay.
    private func schedulePendingOpen(at point: NSPoint) {
        pendingPoint = point
        restingPoint = point
        restingCell = delegate?.hoverControllerCell(at: point)
        pendingOpen = scheduler.schedule(after: delay) { [weak self] in
            self?.resolve()
        }
    }

    @objc func modifiersChanged(commandDown: Bool, optionDown: Bool) {
        self.commandDown = commandDown
        self.optionDown = optionDown
        if mode == .commandHover && !(commandDown && !optionDown) {
            cancelPendingOpen()
        }
    }

    @objc func mouseDown() {
        cancelPendingOpen()
        clearPendingCue()
        forgetRejectedLink()
    }

    @objc func keyDown() {
        cancelPendingOpen()
        clearPendingCue()
        forgetRejectedLink()
    }

    @objc func scrolled() {
        cancelPendingOpen()
        clearPendingCue()
        forgetRejectedLink()
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
        forgetRejectedLink()
    }

    // What the view shows changed (new output, lines scrolled off the top, a resize), so a rejected
    // link may no longer be where it was.
    @objc func contentChanged() {
        forgetRejectedLink()
    }

    // The content may have moved under the pointer without a pointer event (lines dropped off the
    // top of a full scrollback, the screen scrolled, a resize). This happens on every line of
    // streaming output. While the pointer is still on the same content cell (scrolled back, so the
    // text under it did not move) the pending hover stays, and a cue whose open was declined stays
    // without being shown or tried again. Otherwise the pending open and cue are dropped, along
    // with any resolution in flight, and the pointer counts as having just moved to where it is
    // now. The cue of an open preview stays.
    @objc func contentShifted() {
        forgetRejectedLink()
        if isOpen, let rects = delegate?.hoverControllerPreviewLinkRects() {
            // The open preview's link moved with the content. Auto-close tests the pointer against
            // where it is now.
            if cueBelongsToOpenPreview, let cue {
                self.cue = (cue.url, rects, cue.immediate)
            }
            linkRects = rects
        }
        let hasPendingCue = cue != nil && !cueBelongsToOpenPreview
        // pendingPoint outlives the timers while their resolution is in flight.
        guard pendingPoint != nil || hasPendingCue else {
            return
        }
        guard let point = delegate?.hoverControllerPointerLocation() else {
            cancelPendingOpen()
            clearPendingCue()
            return
        }
        if let restingCell, let restingPoint,
           delegate?.hoverControllerCell(at: point) == restingCell,
           !hasPendingCue || pendingCueIsStillThere(at: point) {
            // The view moved under the still pointer by whole lines, and the link with it.
            let dy = point.y - restingPoint.y
            if dy != 0, hasPendingCue, let cue {
                self.cue = (cue.url, cue.linkRects.map { $0.offsetBy(dx: 0, dy: dy) }, cue.immediate)
            }
            self.restingPoint = point
            if pendingPoint != nil {
                pendingPoint = point
            }
            return
        }
        cancelPendingOpen()
        clearPendingCue()
        pointerMoved(to: point, commandDown: commandDown, optionDown: optionDown, windowActive: windowActive)
    }

    // The same cell may hold other text than before (a program redrew the screen in place). For a
    // cue the immediate lookup found, look again (cheap: no full resolution); other cues are kept.
    private func pendingCueIsStillThere(at point: NSPoint) -> Bool {
        guard let cue, cue.immediate else {
            return true
        }
        guard case let .link(url, _) = delegate?.hoverControllerLookUpLinkImmediately(at: point) else {
            return false
        }
        return url == cue.url
    }

    // The app or window lost focus.
    @objc func deactivated() {
        cancelPendingOpen()
        clearCue()
        forgetRejectedLink()
        if isOpen && !clickedInPreview {
            closeHoverPreview()
        }
    }

    // The pointer entered the open preview. It may have come from somewhere this view gets no
    // events, so the auto-close started when it left must be stopped here.
    func pointerEnteredPreview() {
        guard isOpen else {
            return
        }
        cancelAutoClose()
    }

    // The pointer left the open preview, possibly for somewhere this view gets no events (another
    // pane, another window, the desktop), so start auto-close now. `point` is where the pointer
    // is, or nil when it isn't over this view.
    func pointerLeftPreview(at point: NSPoint?) {
        guard isOpen else {
            return
        }
        if let point, isInsideLinkOrPreview(point) {
            return
        }
        startAutoCloseIfNeeded()
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
        restingPoint = nil
        restingCell = nil
        generation += 1
        delegate?.hoverControllerCancelResolution()
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

    private func showCueIfWanted(url: URL, linkRects rects: [NSRect], immediate: Bool) {
        guard mode == .hover, cueSettleDelay != nil, cue?.url != url || cue?.linkRects != rects else {
            return
        }
        cue = (url, rects, immediate)
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

    // Closes only the preview. A pending open and a cue belong to the link the pointer is on now,
    // which may be another link the user is waiting on, so they stay.
    private func autoCloseFired() {
        autoClose = nil
        if cueBelongsToOpenPreview {
            clearCue()
        }
        resetToIdle()
        delegate?.hoverControllerClosePreview()
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
        if let cue, cue.linkRects.contains(where: { $0.contains(point) }) {
            resolutionFinished()
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
            let (current, currentRects) = self.shiftedSinceResolving(point: point, rects: rects)
            self.resolutionFinished()
            self.resolved(url: url, linkRects: currentRects, at: current)
        }
    }

    // Nothing is pending any more. The resting cell stays so a content shift can tell whether the
    // pointer is still on the text it rested on.
    private func resolutionFinished() {
        pendingPoint = nil
    }

    // A resolution that survived content shifts (the pointer stayed on the same cell) answers in
    // the coordinates it was asked in. Moves its answer by however far the content has moved since.
    private func shiftedSinceResolving(point: NSPoint, rects: [NSRect]) -> (NSPoint, [NSRect]) {
        guard let restingPoint, restingPoint.y != point.y else {
            return (point, rects)
        }
        let dy = restingPoint.y - point.y
        return (NSPoint(x: point.x, y: restingPoint.y), rects.map { $0.offsetBy(dx: 0, dy: dy) })
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
            let (current, currentRects) = self.shiftedSinceResolving(point: point, rects: rects)
            guard let url, self.allowlist.allows(url), currentRects.contains(where: { $0.contains(current) }) else {
                return
            }
            self.showCueIfWanted(url: url, linkRects: currentRects, immediate: false)
        }
    }

    private func resolved(url: URL?, linkRects rects: [NSRect], at point: NSPoint) {
        guard let url, rects.contains(where: { $0.contains(point) }) else {
            return
        }
        guard allowlist.allows(url) else {
            if iTermQuickLookDomainAllowlist.isWebURL(url) {
                delegate?.hoverControllerDeclinedLink(url: url)
            }
            return
        }
        showCueIfWanted(url: url, linkRects: rects, immediate: false)
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
