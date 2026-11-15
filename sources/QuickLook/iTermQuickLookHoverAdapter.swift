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
    // Returns NO if the host declined to open a preview.
    @objc var openPreview: ((_ url: URL, _ point: NSPoint) -> Bool)?
    @objc var closePreview: (() -> Void)?
    // The open preview's frame, or NSZeroRect when there is none.
    @objc var previewFrame: (() -> NSRect)?
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
        super.init()
        controller.delegate = self
        reloadPreferences()
    }

    @objc static var preferenceKeys: Set<String> {
        return [kPreferenceKeyQuickLookHoverMode,
                kPreferenceKeyQuickLookHoverDelay,
                kPreferenceKeyQuickLookHoverAutoCloseDelay,
                kPreferenceKeyQuickLookHoverDomainAllowlist]
    }

    @objc static var currentMode: iTermQuickLookHoverMode {
        return iTermQuickLookHoverMode(rawValue: Int(iTermPreferences.int(forKey: kPreferenceKeyQuickLookHoverMode))) ?? .off
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

    func hoverControllerOpenPreview(url: URL, linkRects: [NSRect], at point: NSPoint) -> Bool {
        return host.openPreview?(url, point) ?? false
    }

    func hoverControllerClosePreview() {
        host.closePreview?()
    }

    func hoverControllerPreviewFrame() -> NSRect? {
        guard let frame = host.previewFrame?(), !frame.isEmpty else {
            return nil
        }
        return frame
    }
}

// Calls a handler once, on the first mouse-down inside a view. It watches events without consuming
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    @objc func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        handler = nil
    }

    private func handle(_ event: NSEvent) {
        guard let view, let window = view.window, event.window === window else {
            return
        }
        guard view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else {
            return
        }
        let handler = self.handler
        stop()
        handler?()
    }
}
