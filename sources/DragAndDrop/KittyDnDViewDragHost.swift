//
//  KittyDnDViewDragHost.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  The real drag host: starts a native NSDraggingSession on the terminal view
//  when a program offers data to be dragged out, and relays the drag's outcome
//  back to the controller as t=e events.
//
//  Because the offer requires a round trip (gesture -> t=o -> the program's offer
//  + t=P) before the OS drag can start, the drag begins from the stored gesture
//  event rather than the current one; AppKit allows beginning a drag from a past
//  event (as FileAttachmentSubpartView does from a timer).
//

import AppKit

@available(macOS 11.0, *)
@MainActor
final class KittyDnDViewDragHost: NSObject, KittyDnDDragHost, NSDraggingSource {
    private weak var dataSource: KittyDnDBridgeDataSource?
    weak var controller: KittyDnDController?

    /// The mouse event that started the gesture, captured when the terminal told
    /// the program about it. Used to begin the drag once the program says go.
    var pendingEvent: NSEvent?

    private var currentOperations = 1

    init(dataSource: KittyDnDBridgeDataSource) {
        self.dataSource = dataSource
    }

    func beginDrag(_ offer: KittyDnDDragOffer) -> Bool {
        guard let view = dataSource?.kittyDnDView, let event = pendingEvent else {
            return false
        }
        let items = draggingItems(for: offer, in: view, event: event)
        guard !items.isEmpty else {
            return false
        }
        currentOperations = offer.operations
        view.beginDraggingSession(with: items, event: event, source: self)
        return true
    }

    func cancelDrag() {
        // A running NSDraggingSession cannot be programmatically canceled cleanly;
        // this is best effort. The session's end callback still fires.
        pendingEvent = nil
    }

    // MARK: - Building the drag items

    private func draggingItems(for offer: KittyDnDDragOffer,
                               in view: NSView,
                               event: NSEvent) -> [NSDraggingItem] {
        let image = dragImage(for: offer)
        let size = image?.size ?? NSSize(width: 32, height: 32)
        let origin = view.convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: origin.x - size.width / 2,
                           y: origin.y - size.height / 2,
                           width: size.width, height: size.height)

        // Prefer real file URLs (from text/uri-list) so a drop onto Finder works.
        if let urls = fileURLs(from: offer), !urls.isEmpty {
            return urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let contents = image ?? NSWorkspace.shared.icon(forFile: url.path)
                item.setDraggingFrame(frame.offsetBy(dx: CGFloat(index) * 6, dy: 0),
                                      contents: contents)
                return item
            }
        }

        // Otherwise a plain-text drag.
        if let index = offer.mimeTypes.firstIndex(of: "text/plain"),
           let data = offer.data[index],
           let text = String(data: data, encoding: .utf8) {
            let pbItem = NSPasteboardItem()
            pbItem.setString(text, forType: .string)
            let item = NSDraggingItem(pasteboardWriter: pbItem)
            item.setDraggingFrame(frame, contents: image ?? textImage(text, size: size))
            return [item]
        }

        return []
    }

    private func fileURLs(from offer: KittyDnDDragOffer) -> [URL]? {
        guard let index = offer.mimeTypes.firstIndex(of: "text/uri-list"),
              let data = offer.data[index],
              let list = String(data: data, encoding: .utf8) else {
            return nil
        }
        return list
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map(String.init)
            .compactMap { URL(string: $0) }
            .filter { $0.isFileURL }
    }

    private func dragImage(for offer: KittyDnDDragOffer) -> NSImage? {
        // Only PNG thumbnails are supported for now (format 100).
        guard let image = offer.image, image.format == 100 else {
            return nil
        }
        return NSImage(data: image.data)
    }

    private func textImage(_ text: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let snippet = String(text.prefix(40))
        (snippet as NSString).draw(at: NSPoint(x: 2, y: 2),
                                   withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        image.unlockFocus()
        return image
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        var mask: NSDragOperation = []
        if currentOperations & 1 != 0 {
            mask.insert(.copy)
        }
        if currentOperations & 2 != 0 {
            mask.insert(.move)
        }
        return mask.isEmpty ? .copy : mask
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        if operation.isEmpty {
            controller?.dragFinished(canceled: true)
        } else {
            controller?.dragDropped()
            controller?.dragFinished(canceled: false)
        }
        pendingEvent = nil
    }
}
