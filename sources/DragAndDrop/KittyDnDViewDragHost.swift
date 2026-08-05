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
        return Self.parseFileURLs(uriList: list)
    }

    /// Parse a text/uri-list into file URLs: split on CR/LF, drop blank and
    /// comment (`#`) lines, keep only file URLs.
    nonisolated static func parseFileURLs(uriList: String) -> [URL] {
        // Split on newlines; $0.isNewline matches CR, LF, and the CRLF grapheme
        // (Swift treats "\r\n" as a single Character).
        return uriList
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { URL(string: $0) }
            .filter { $0.isFileURL }
    }

    private func dragImage(for offer: KittyDnDDragOffer) -> NSImage? {
        guard let image = offer.image else {
            return nil
        }
        switch image.format {
        case 100:
            // PNG.
            return NSImage(data: image.data)
        case 24, 32:
            // Raw RGB / RGBA. The controller has already validated that the byte
            // count matches width*height*bytesPerPixel.
            return Self.image(fromRaw: image)
        default:
            // Format 0 (text) or unknown: no thumbnail.
            return nil
        }
    }

    /// Build an NSImage from raw RGB (format 24) or RGBA (format 32) pixel data.
    private static func image(fromRaw image: KittyDnDDragImage) -> NSImage? {
        let samplesPerPixel = image.format == 32 ? 4 : 3
        // Bound the dimensions so the size arithmetic below cannot overflow, then
        // require the data length to match exactly (the controller already
        // validates the primary image; this keeps the renderer self-consistent).
        guard image.width > 0, image.height > 0,
              image.width <= 1 << 16, image.height <= 1 << 16,
              image.data.count == image.width * image.height * samplesPerPixel else {
            return nil
        }
        // Kitty's RGBA (format 32) is non-premultiplied; say so or semi-transparent
        // pixels render with wrong colors.
        let bitmapFormat: NSBitmapImageRep.Format = samplesPerPixel == 4 ? .alphaNonpremultiplied : []
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: image.width,
            pixelsHigh: image.height,
            bitsPerSample: 8,
            samplesPerPixel: samplesPerPixel,
            hasAlpha: samplesPerPixel == 4,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: bitmapFormat,
            bytesPerRow: image.width * samplesPerPixel,
            bitsPerPixel: samplesPerPixel * 8),
              let dest = rep.bitmapData else {
            return nil
        }
        image.data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                dest.update(from: base.assumingMemoryBound(to: UInt8.self), count: raw.count)
            }
        }
        let result = NSImage(size: NSSize(width: image.width, height: image.height))
        result.addRepresentation(rep)
        return result
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
