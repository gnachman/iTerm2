//
//  iTermStatusBarProxyIconImageView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman.
//

import AppKit

// A status bar icon image view that doubles as a proxy icon: dragging it starts a file drag of
// the URL from `urlProvider` (like the proxy icon in a window title bar), while a plain click
// invokes `onClick`. The displayed image is whatever the container sets (a monochrome template
// glyph), so it stays visually consistent with other status bar icons; only the drag image is
// the real Finder icon.
@objc(iTermStatusBarProxyIconImageView)
class iTermStatusBarProxyIconImageView: NSImageView, NSDraggingSource {
    // Returns the file to drag. It is asked when a drag begins rather than cached, so a
    // directory deleted after it became current is not offered. When it is nil or returns nil,
    // dragging is disabled but clicking still works.
    @objc var urlProvider: (() -> URL?)?

    // Invoked on a click that did not turn into a drag.
    @objc var onClick: (() -> Void)?

    private var isMouseDown = false
    private var didDrag = false
    private var mouseDownPoint = NSPoint.zero

    private static let dragThreshold: CGFloat = 4

    // Whether the mouse has moved far enough from where it went down to count as a drag rather
    // than a click.
    static func movementIsDrag(from start: NSPoint, to end: NSPoint) -> Bool {
        return hypot(end.x - start.x, end.y - start.y) >= dragThreshold
    }

    // The URL a proxy icon should vend for `path`, or nil if it must not be draggable. A proxy
    // icon drag hands a real file to another app, so it only makes sense for a local directory
    // that exists right now.
    @objc(directoryURLForPath:isLocal:)
    static func directoryURL(forPath path: String?, isLocal: Bool) -> URL? {
        guard let path, !path.isEmpty, isLocal else {
            return nil
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // The URL to vend for a drag starting now. Asks `urlProvider` afresh on every call.
    func urlForDrag() -> URL? {
        return urlProvider?()
    }

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        didDrag = false
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMouseDown, !didDrag else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard Self.movementIsDrag(from: mouseDownPoint, to: point) else {
            return
        }
        // Check now rather than when the path last changed: the directory may have been
        // deleted since.
        guard let url = urlForDrag() else {
            return
        }
        didDrag = true
        isMouseDown = false

        let pbItem = NSPasteboardItem()
        pbItem.setString(url.absoluteString, forType: .fileURL)

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: 16, height: 16)
        icon.size = size
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        dragItem.setDraggingFrame(NSRect(origin: origin, size: size), contents: icon)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = isMouseDown && !didDrag
        isMouseDown = false
        didDrag = false
        if wasClick {
            onClick?()
        }
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .link, .generic]
    }
}
