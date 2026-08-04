//
//  KittyDnDPasteboardDropData.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Snapshots a drag pasteboard into the KittyDnDDropData the controller needs.
//  It reads eagerly at construction because a drag pasteboard is only valid
//  during performDragOperation, whereas the program pulls the data later over
//  the pty. Files are offered as text/uri-list (the controller turns the file
//  URLs into a uri-list, materializing them remotely for Tier 2); text and
//  images are offered with their bytes inline.
//

import AppKit
import UniformTypeIdentifiers

@available(macOS 11.0, *)
@MainActor
final class KittyDnDPasteboardDropData: KittyDnDDropData {
    let mimeTypes: [String]
    let fileURLs: [URL]
    private let dataByIndex: [Int: Data]

    /// Designated initializer taking already-resolved components (testable).
    init(fileURLs: [URL], text: String?, png: Data?) {
        var mimes: [String] = []
        var data: [Int: Data] = [:]
        var index = 0
        func add(_ mime: String, _ payload: Data?) {
            index += 1
            mimes.append(mime)
            if let payload {
                data[index] = payload
            }
        }
        // Files first: the controller builds the uri-list from fileURLs, so no
        // inline data for this entry.
        if !fileURLs.isEmpty {
            add("text/uri-list", nil)
        }
        if let text {
            add("text/plain", Data(text.utf8))
        }
        if let png {
            add("image/png", png)
        }
        self.mimeTypes = mimes
        self.fileURLs = fileURLs
        self.dataByIndex = data
    }

    convenience init(pasteboard: NSPasteboard) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let text = pasteboard.string(forType: .string)
        var png: Data?
        if let existing = pasteboard.data(forType: .png) {
            png = existing
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff) {
            png = rep.representation(using: .png, properties: [:])
        }
        self.init(fileURLs: urls, text: text, png: png)
    }

    func data(forMimeIndex index: Int) -> Data? {
        return dataByIndex[index]
    }
}
