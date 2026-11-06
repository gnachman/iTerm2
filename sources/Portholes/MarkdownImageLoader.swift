//
//  MarkdownImageLoader.swift
//  iTerm2SharedARC
//
//  Loads images referenced by Markdown shown in a porthole. It never touches the
//  network: remote images are turned into links before they get here. Files are
//  read only when the user clicks an image's placeholder, and not at all when
//  shell integration says the text came from another machine.
//

import AppKit
import Foundation

final class MarkdownImageLoader {
    private static let maximumFileSize = 32 * 1024 * 1024

    private let baseDirectory: URL?
    private let allowsLocalFiles: Bool
    private var cache = [String: NSImage?]()

    init(baseDirectory: URL?, allowsLocalFiles: Bool) {
        self.baseDirectory = baseDirectory
        self.allowsLocalFiles = allowsLocalFiles
    }

    func image(for source: String) -> NSImage? {
        if let cached = cache[source] {
            return cached
        }
        let image = load(source)
        cache[source] = image
        return image
    }

    /// True when the image's bytes are in the Markdown itself (a data: URL), so
    /// showing it doesn't read anything from this Mac.
    static func isEmbedded(_ source: String) -> Bool {
        return source.lowercased().hasPrefix("data:")
    }

    private func load(_ source: String) -> NSImage? {
        if Self.isEmbedded(source) {
            return dataURLImage(source)
        }
        guard allowsLocalFiles, let url = fileURL(for: source) else {
            DLog("Not loading Markdown image \(source): allowsLocalFiles=\(allowsLocalFiles) baseDirectory=\(String(describing: baseDirectory))")
            return nil
        }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size <= Self.maximumFileSize else {
            DLog("Not loading Markdown image \(url.path): not a regular file of acceptable size")
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func fileURL(for source: String) -> URL? {
        if source.lowercased().hasPrefix("file:") {
            guard let url = URL(string: source), url.isFileURL else {
                return nil
            }
            if let host = url.host, !host.isEmpty, host != "localhost" {
                return nil
            }
            return url.standardizedFileURL
        }
        let path = (source.removingPercentEncoding ?? source) as NSString
        let expanded = path.expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        guard let baseDirectory else {
            return nil
        }
        return URL(fileURLWithPath: expanded, relativeTo: baseDirectory).standardizedFileURL
    }

    private func dataURLImage(_ source: String) -> NSImage? {
        guard let comma = source.firstIndex(of: ",") else {
            return nil
        }
        let header = source[..<comma].lowercased()
        let payload = String(source[source.index(after: comma)...])
        guard header.hasSuffix(";base64"), payload.count <= Self.maximumFileSize * 4 / 3 + 4 else {
            return nil
        }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return NSImage(data: data)
    }
}

/// The value of the link on an image placeholder. Clicking it shows the image.
final class MarkdownImageReference: NSObject {
    let source: String
    let alt: String

    init(source: String, alt: String) {
        self.source = source
        self.alt = alt
    }
}

/// Draws an image at its natural size, scaled down to fit the width left on the line.
final class MarkdownImageAttachmentCell: NSTextAttachmentCell {
    private let picture: NSImage

    init(image: NSImage) {
        picture = image
        super.init(imageCell: image)
    }

    required init(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        return picture.size
    }

    override func cellFrame(for textContainer: NSTextContainer,
                            proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint,
                            characterIndex charIndex: Int) -> NSRect {
        let natural = picture.size
        guard natural.width > 0, natural.height > 0 else {
            return .zero
        }
        let available = max(1, lineFrag.width - position.x - textContainer.lineFragmentPadding * 2)
        let scale = min(1, available / natural.width)
        return NSRect(x: 0, y: 0, width: floor(natural.width * scale), height: floor(natural.height * scale))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        picture.draw(in: cellFrame,
                     from: .zero,
                     operation: .sourceOver,
                     fraction: 1,
                     respectFlipped: true,
                     hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}
