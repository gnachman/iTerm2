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
import UniformTypeIdentifiers

@objc(iTermKittyDnDViewDragHost)
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

    func beginDrag(_ offer: KittyDnDDragOffer) -> KittyDnDDragStartResult {
        guard let view = dataSource?.kittyDnDView else {
            DLog("KittyDnD beginDrag: no view; failed")
            return .failed
        }
        guard let event = pendingEvent else {
            // No stored gesture: the drag request came without (or after) one.
            DLog("KittyDnD beginDrag: no pending gesture event; gestureGone")
            return .gestureGone
        }
        // Refuse a stale gesture: a real drag-out holds THE SAME mouse button down
        // through the t=o / t=P round trip. Checking that specific button (not just
        // any button being pressed, which a later unrelated click would satisfy)
        // stops a program starting a phantom drag from a long-dead event.
        guard Self.gestureIsLive(event) else {
            DLog("KittyDnD beginDrag: gesture no longer live (button released); gestureGone. pressedButtons=\(NSEvent.pressedMouseButtons) buttonNumber=\(event.buttonNumber)")
            pendingEvent = nil
            return .gestureGone
        }
        let items = draggingItems(for: offer, in: view, event: event)
        guard !items.isEmpty else {
            DLog("KittyDnD beginDrag: no dragging items built from offer mimeTypes=\(offer.mimeTypes); failed")
            return .failed
        }
        DLog("KittyDnD beginDrag: starting NSDraggingSession with \(items.count) item(s), window=\(view.window?.windowNumber ?? 0)")
        currentOperations = offer.operations
        view.beginDraggingSession(with: items, event: event, source: self)
        return .started
    }

    func cancelDrag() {
        // A running NSDraggingSession cannot be programmatically canceled cleanly;
        // this is best effort. The session's end callback still fires.
        pendingEvent = nil
    }

    func clearPendingGesture() {
        pendingEvent = nil
    }

    var hasLiveGesture: Bool {
        guard let event = pendingEvent else { return false }
        return Self.gestureIsLive(event)
    }

    /// Whether the specific mouse button that started `event` is still pressed.
    private static func gestureIsLive(_ event: NSEvent) -> Bool {
        return (NSEvent.pressedMouseButtons & (1 << event.buttonNumber)) != 0
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

        // Real file URLs (from text/uri-list) so a drop onto Finder works. When the
        // offer includes files, the drag is FILE-ONLY: we deliberately do not also
        // add the non-file MIME pasteboard item below. Finder (and other strict
        // destinations) reject a drag that MIXES file and non-file items, accepting
        // only all-file drags; in-app destinations that tolerate a mixed pasteboard
        // do not, which is why such a drag dropped into another terminal but was
        // refused by Finder. A file drag's payload is the file itself, so dropping
        // the extra text/MIME flavor here is the right trade.
        if let urls = fileURLs(from: offer), !urls.isEmpty {
            return urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let contents = image ?? NSWorkspace.shared.icon(forFile: url.path)
                item.setDraggingFrame(frame.offsetBy(dx: CGFloat(index) * 6, dy: 0),
                                      contents: contents)
                return item
            }
        }

        // A non-file offer: a single pasteboard item carrying every offered MIME
        // type's data, so a destination can pick its preferred flavor (image/png,
        // application/json, text/plain, custom types, ...).
        var items: [NSDraggingItem] = []
        if let pbItem = Self.pasteboardItem(from: offer) {
            let item = NSDraggingItem(pasteboardWriter: pbItem)
            let contents = image ?? dragThumbnail(for: offer, size: size)
            item.setDraggingFrame(frame, contents: contents)
            items.append(item)
        }

        return items
    }

    /// A single pasteboard item carrying every offered non-file MIME's data, typed
    /// by its UTType (or the raw MIME string as a custom type for unknown MIMEs).
    private static func pasteboardItem(from offer: KittyDnDDragOffer) -> NSPasteboardItem? {
        let pbItem = NSPasteboardItem()
        var added = false
        for (index, mime) in offer.mimeTypes.enumerated() where mime != "text/uri-list" {
            guard let data = offer.data[index] else { continue }
            if mime == "text/plain", let text = String(data: data, encoding: .utf8) {
                pbItem.setString(text, forType: .string)
            } else {
                pbItem.setData(data, forType: pasteboardType(forMIME: mime))
            }
            added = true
        }
        return added ? pbItem : nil
    }

    private static func pasteboardType(forMIME mime: String) -> NSPasteboard.PasteboardType {
        if let type = UTType(mimeType: mime) {
            return NSPasteboard.PasteboardType(type.identifier)
        }
        // Unknown MIME: use the MIME string itself as a custom pasteboard type.
        return NSPasteboard.PasteboardType(mime)
    }

    /// A thumbnail for a non-file drag: the first offered image, else a text
    /// snippet, else a blank square.
    private func dragThumbnail(for offer: KittyDnDDragOffer, size: NSSize) -> NSImage {
        for (index, mime) in offer.mimeTypes.enumerated()
        where mime.hasPrefix("image/") {
            guard let data = offer.data[index] else { continue }
            // Cap the DECODED pixel count before handing the payload to AppKit: a
            // small compressed file declaring huge dimensions would otherwise force
            // a multi-GB bitmap allocation when the drag image is rendered. This is
            // the same guard the controller applies to pre-sent t=p thumbnails; a
            // MIME image used only as a thumbnail bypasses that path.
            if let pixels = KittyDnDController.imagePixelCount(data),
               pixels > KittyDnDController.maxImagePixels {
                continue
            }
            if let image = NSImage(data: data) {
                return image
            }
        }
        if let index = offer.mimeTypes.firstIndex(of: "text/plain"),
           let data = offer.data[index],
           let text = String(data: data, encoding: .utf8) {
            return textImage(text, size: size)
        }
        return NSImage(size: size)
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
                         willBeginAt screenPoint: NSPoint) {
        // The OS drag now owns event tracking; the mouse handler must synthesize
        // the button-release report that the swallowed mouseUp would have sent.
        dataSource?.kittyDnDDragDidBegin()
    }

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
