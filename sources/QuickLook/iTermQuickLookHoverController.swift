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

protocol iTermQuickLookHoverControllerDelegate: AnyObject {
    // Finds the link under `point`. The completion may be called synchronously or later. `url` is nil
    // when there is no link; `linkRects` are the regions the link occupies.
    func hoverControllerResolveLink(at point: NSPoint,
                                    completion: @escaping (_ url: URL?, _ linkRects: [NSRect]) -> Void)
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
}

@objc(iTermQuickLookHoverController)
class iTermQuickLookHoverController: NSObject {
    weak var delegate: iTermQuickLookHoverControllerDelegate?

    private let scheduler: iTermQuickLookScheduling
    private var mode = iTermQuickLookHoverMode.off
    private var delay: TimeInterval = 0
    private var autoCloseDelay: TimeInterval = 0
    private var allowlist = iTermQuickLookDomainAllowlist(string: "")
    // How long the pointer must rest before the link under it is resolved to show the cue. nil
    // turns the cue off. Only used in Hover mode, and only when shorter than the hover delay.
    var cueSettleDelay: TimeInterval?

    // Timer for resolving the link the pointer is resting on. Replaced on every qualifying move.
    private var pendingOpen: iTermQuickLookCancellable?
    // Timer for resolving the link under the pointer to show the cue before the preview opens.
    private var pendingCue: iTermQuickLookCancellable?
    // The link the cue is shown for. Reused when the hover delay elapses on it, so the link is
    // resolved once per link the pointer settles on.
    private var cue: (url: URL, linkRects: [NSRect])?
    // Bumped whenever a pending open is cancelled or superseded so that a resolution that completes
    // afterwards (the delegate may answer asynchronously) is recognized as stale and dropped.
    private var generation = 0

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
    }

    // MARK: - Inputs

    @objc func pointerMoved(to point: NSPoint, commandDown: Bool, optionDown: Bool, windowActive: Bool) {
        cancelPendingOpen()
        if let cue, !cue.linkRects.contains(where: { $0.contains(point) }) {
            clearCue()
        }
        if isOpen {
            if isInsideLinkOrPreview(point) {
                cancelAutoClose()
                return
            }
            startAutoCloseIfNeeded()
        }
        guard hoverAllowed(commandDown: commandDown, optionDown: optionDown, windowActive: windowActive) else {
            clearCue()
            return
        }
        if cue == nil, let settle = cueSettleDelay, mode == .hover, settle < delay {
            pendingCue = scheduler.schedule(after: settle) { [weak self] in
                self?.resolveCue(at: point)
            }
        }
        pendingOpen = scheduler.schedule(after: delay) { [weak self] in
            self?.resolve(at: point)
        }
    }

    @objc func modifiersChanged(commandDown: Bool, optionDown: Bool) {
        if mode == .commandHover && !(commandDown && !optionDown) {
            cancelPendingOpen()
        }
    }

    @objc func mouseDown() {
        cancelPendingOpen()
        clearCue()
    }

    @objc func keyDown() {
        cancelPendingOpen()
        clearCue()
    }

    @objc func scrolled() {
        cancelPendingOpen()
        clearCue()
    }

    // The app or window lost focus.
    @objc func deactivated() {
        cancelPendingOpen()
        clearCue()
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
        generation += 1
    }

    private func clearCue() {
        guard cue != nil else {
            return
        }
        cue = nil
        delegate?.hoverControllerClearCue()
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

    private func resolve(at point: NSPoint) {
        pendingOpen = nil
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

    private func resolveCue(at point: NSPoint) {
        pendingCue = nil
        guard let delegate else {
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
