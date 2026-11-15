//
//  iTermQuickLookHoverAdapter.swift
//  iTerm2SharedARC
//
//  Connects the Quick Look hover state machine to a host view written in Objective-C. The host
//  supplies blocks in place of the Swift-only controller delegate, and the adapter configures the
//  controller from user preferences.
//

import AppKit

// The host's side of the connection, as blocks. Points and rects are in the host's coordinates.
@objc(iTermQuickLookHoverHostCallbacks)
final class iTermQuickLookHoverHostCallbacks: NSObject {
    // Finds the web link under a point. Calls the completion with nil when there is none, and with
    // NSRect values covering the link otherwise.
    @objc var resolveLink: ((_ point: NSPoint, _ completion: @escaping (URL?, [NSValue]) -> Void) -> Void)?
    // Looks up the link under a point synchronously and cheaply. Returns nil when only resolveLink
    // can tell, and a link with a nil URL when nothing there would preview (with the rects of a link
    // that won't preview, if that is what is there).
    @objc var lookUpLinkImmediately: ((_ point: NSPoint) -> iTermQuickLookHoverImmediateLink?)?
    // Returns NO if the host declined to open a preview.
    @objc var openPreview: ((_ url: URL, _ point: NSPoint) -> Bool)?
    @objc var closePreview: (() -> Void)?
    // The open preview's frame, or NSZeroRect when there is none.
    @objc var previewFrame: (() -> NSRect)?
    // Shows that the link at `url`, last returned by resolveLink, will preview.
    @objc var showCue: ((_ url: URL) -> Void)?
    @objc var clearCue: (() -> Void)?
    // Where the pointer is now, as an NSPoint value, or nil when it is not over the view.
    @objc var pointerLocation: (() -> NSValue?)?
    // The content cell at a point. Required: without it every content shift would look like the
    // text under the pointer changed.
    @objc let absoluteCell: (_ point: NSPoint) -> iTermQuickLookHoverHostCell

    @objc(initWithAbsoluteCell:)
    init(absoluteCell: @escaping (_ point: NSPoint) -> iTermQuickLookHoverHostCell) {
        self.absoluteCell = absoluteCell
        super.init()
    }
}

// The answer to iTermQuickLookHoverHostCallbacks.absoluteCell.
@objc(iTermQuickLookHoverHostCell)
final class iTermQuickLookHoverHostCell: NSObject {
    // Numbered so that it keeps its number while lines scroll off the top (the line includes the
    // lines dropped so far).
    @objc let coord: VT100GridAbsCoord
    // The main and alternate screens number their lines alike.
    @objc let alternateScreen: Bool

    @objc(initWithCoord:alternateScreen:)
    init(coord: VT100GridAbsCoord, alternateScreen: Bool) {
        self.coord = coord
        self.alternateScreen = alternateScreen
        super.init()
    }
}

// The answer to iTermQuickLookHoverHostCallbacks.lookUpLinkImmediately.
@objc(iTermQuickLookHoverImmediateLink)
final class iTermQuickLookHoverImmediateLink: NSObject {
    // nil when nothing at the point would preview. Rects may then cover a link that won't preview.
    @objc let url: URL?
    // The regions the link occupies, as NSRect values.
    @objc let rects: [NSValue]

    @objc(initWithURL:rects:)
    init(url: URL?, rects: [NSValue]) {
        self.url = url
        self.rects = rects
        super.init()
    }
}

@objc(iTermQuickLookHoverAdapter)
final class iTermQuickLookHoverAdapter: NSObject, iTermQuickLookHoverControllerDelegate {
    @objc let controller: iTermQuickLookHoverController
    @objc private(set) var mode = iTermQuickLookHoverMode.off
    private let host: iTermQuickLookHoverHostCallbacks
    private var clickWatcher: iTermQuickLookClickWatcher?

    @objc(initWithHost:)
    init(host: iTermQuickLookHoverHostCallbacks) {
        self.host = host
        controller = iTermQuickLookHoverController(scheduler: iTermQuickLookTimerScheduler())
        controller.cueSettleDelay = Self.cueSettleDelay
        super.init()
        controller.delegate = self
        reloadPreferences()
    }

    // Long enough that sweeping the pointer across text doesn't flash cues, short enough that the
    // cue shows well before a preview opens at the default delay.
    private static let cueSettleDelay: TimeInterval = 0.1

    @objc static var preferenceKeys: Set<String> {
        return [kPreferenceKeyQuickLookHoverMode,
                kPreferenceKeyQuickLookHoverDelay,
                kPreferenceKeyQuickLookHoverAutoCloseDelay,
                kPreferenceKeyQuickLookHoverDomainAllowlist]
    }

    @objc static var currentMode: iTermQuickLookHoverMode {
        return iTermQuickLookHoverMode(rawValue: Int(iTermPreferences.int(forKey: kPreferenceKeyQuickLookHoverMode))) ?? .off
    }

    // Hover previews only OSC 8 hyperlinks unless the user also wants plain-text URLs found by URL
    // detection, which often grab neighboring text (such as escape sequences in a command line).
    // Force press and the context menu are not gated by this.
    @objc(shouldHoverPreviewURLThatIsOSC8:includesPlainTextURLs:)
    static func shouldHoverPreview(isOSC8: Bool, includesPlainTextURLs: Bool) -> Bool {
        return isOSC8 || includesPlainTextURLs
    }

    @objc static var includesPlainTextURLs: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyQuickLookHoverIncludesPlainTextURLs)
    }

    @objc func reloadPreferences() {
        mode = Self.currentMode
        controller.configure(mode: mode,
                             delay: iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverDelay),
                             autoCloseDelay: iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay),
                             allowlistString: iTermPreferences.string(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist) ?? "")
    }

    // Reports the first mouse-down inside `view` to the controller as a click in the preview. Used
    // for previews that don't report clicks themselves. Replaces any earlier watch.
    @objc(watchForClicksInView:)
    func watchForClicks(in view: NSView) {
        clickWatcher?.stop()
        clickWatcher = iTermQuickLookClickWatcher(view: view) { [weak self] in
            self?.controller.previewClicked()
        }
    }

    @objc func stopWatchingForClicks() {
        clickWatcher?.stop()
        clickWatcher = nil
    }

    // MARK: - iTermQuickLookHoverControllerDelegate

    func hoverControllerResolveLink(at point: NSPoint,
                                    completion: @escaping (URL?, [NSRect]) -> Void) {
        guard let resolveLink = host.resolveLink else {
            completion(nil, [])
            return
        }
        resolveLink(point) { url, rects in
            completion(url, rects.map { $0.rectValue })
        }
    }

    func hoverControllerLookUpLinkImmediately(at point: NSPoint) -> iTermQuickLookHoverImmediateLookup {
        guard let link = host.lookUpLinkImmediately?(point) else {
            return .unknown
        }
        let rects = link.rects.map { $0.rectValue }
        guard let url = link.url else {
            return .noLink(rects)
        }
        return .link(url, rects)
    }

    func hoverControllerOpenPreview(url: URL, linkRects: [NSRect], at point: NSPoint) -> Bool {
        return host.openPreview?(url, point) ?? false
    }

    func hoverControllerClosePreview() {
        host.closePreview?()
    }

    func hoverControllerShowCue(url: URL, linkRects: [NSRect]) {
        host.showCue?(url)
    }

    func hoverControllerClearCue() {
        host.clearCue?()
    }

    func hoverControllerPointerLocation() -> NSPoint? {
        return host.pointerLocation?()?.pointValue
    }

    func hoverControllerCell(at point: NSPoint) -> iTermQuickLookHoverCell {
        let cell = host.absoluteCell(point)
        return iTermQuickLookHoverCell(line: cell.coord.y,
                                       column: cell.coord.x,
                                       alternateScreen: cell.alternateScreen)
    }

    func hoverControllerPreviewFrame() -> NSRect? {
        guard let frame = host.previewFrame?(), !frame.isEmpty else {
            return nil
        }
        return frame
    }
}

// Calls a handler once, on the first mouse-down inside a view or the first key-down while the view's
// window is key, so keyboard-only use counts as interacting. It watches events without consuming
// them.
@objc(iTermQuickLookClickWatcher)
final class iTermQuickLookClickWatcher: NSObject {
    private var monitor: Any?
    private weak var view: NSView?
    private var handler: (() -> Void)?

    @objc(initWithView:handler:)
    init(view: NSView, handler: @escaping () -> Void) {
        self.view = view
        self.handler = handler
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    // A watcher that is dropped without stop() must not leave its event monitor installed.
    deinit {
        stop()
    }

    @objc func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        handler = nil
    }

    private func handle(_ event: NSEvent) {
        guard let view, Self.isInteraction(type: event.type,
                                           window: event.window,
                                           locationInWindow: event.locationInWindow,
                                           in: view) else {
            return
        }
        let handler = self.handler
        stop()
        handler?()
    }

    // A key-down counts anywhere in the view's window while that window is key; a mouse-down only
    // inside the view.
    static func isInteraction(type: NSEvent.EventType,
                              window eventWindow: NSWindow?,
                              locationInWindow: NSPoint,
                              in view: NSView) -> Bool {
        guard let window = view.window, eventWindow === window else {
            return false
        }
        if type == .keyDown {
            return window.isKeyWindow
        }
        return view.bounds.contains(view.convert(locationInWindow, from: nil))
    }
}
