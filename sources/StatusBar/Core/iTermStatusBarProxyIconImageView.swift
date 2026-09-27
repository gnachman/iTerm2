//
//  iTermStatusBarProxyIconImageView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman.
//

import AppKit

// A status bar icon image view that doubles as a proxy icon: dragging it starts a file drag of
// `url` (like the proxy icon in a window title bar), while a plain click invokes `onClick`. The
// displayed image is whatever the container sets (a monochrome template glyph), so it stays
// visually consistent with other status bar icons; only the drag image is the real Finder icon.
@objc(iTermStatusBarProxyIconImageView)
class iTermStatusBarProxyIconImageView: NSImageView, NSDraggingSource {
    // The file to drag. When nil, dragging is disabled but clicking still works.
    @objc var url: URL?

    // Invoked on a click that did not turn into a drag.
    @objc var onClick: (() -> Void)?

    private var isMouseDown = false
    private var didDrag = false
    private var mouseDownPoint = NSPoint.zero

    private static let dragThreshold: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        didDrag = false
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMouseDown, !didDrag, let url else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        guard distance >= Self.dragThreshold else {
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
