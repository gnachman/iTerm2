//
//  iTermQuickLookClickWatcher.swift
//  iTerm2SharedARC
//

import AppKit

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
