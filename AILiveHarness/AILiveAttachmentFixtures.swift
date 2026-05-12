//
//  AILiveAttachmentFixtures.swift
//  iTerm2 AI live harness
//
//  Per-MIME fixture set used by the 96-cell attachment matrix
//  (AILiveAttachmentMatrix). Each fixture pairs a MIME type with bytes
//  representative of that type plus a `probe` substring the model should
//  echo back when asked "what is in this file?". Probes are designed to
//  be unambiguous, so a non-empty matching response is strong evidence
//  the vendor actually parsed the attachment (vs hallucinating).
//
//  Programmatic fixtures (image PNG/WEBP/HEIC/TIFF, PDF, ZIP, plain text,
//  SVG, etc.) are generated in-test for determinism. The four content-rich
//  binaries (DOCX, XLSX, MP3, MP4) load from
//  ModernTests/Resources/AttachmentFixtures/, which means the project root
//  must be discoverable at runtime (run_ai_live.sh writes PROJECT_ROOT into
//  the temp config file).
//

import Foundation
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
@testable import iTerm2SharedARC

struct AILiveAttachmentFixture {
    let mime: String
    let filename: String
    let bytes: Data
    /// A short prompt phrase asking the model to surface content from the
    /// attachment. Concatenated with the file body in the user message.
    let prompt: String
    /// Substrings the model's response must contain (case-insensitive). The
    /// match policy is OR — any one substring matching counts as success.
    /// Multiple alternatives accommodate model wording variation.
    let acceptanceProbes: [String]
}

enum AILiveAttachmentKind: String, CaseIterable {
    case textPlain        // text/plain
    case textMarkdown     // text/markdown
    case applicationJSON  // application/json
    case applicationXML   // application/xml
    case imageSVG         // image/svg+xml
    case yamlAsUnknown    // unknown extension, content is text; exercises
                          // the ?? "text/plain" fallback in fileTypeIsSupported
    case imagePNG         // image/png
    case imageWEBP        // image/webp
    case imageHEIC        // image/heic
    case imageTIFF        // image/tiff
    case applicationPDF   // application/pdf
    case audioMPEG        // audio/mpeg
    case videoMP4         // video/mp4
    case applicationDOCX  // application/vnd.openxmlformats-officedocument.wordprocessingml.document
    case applicationZIP   // application/zip
    case applicationOctet // application/octet-stream
}

enum AILiveAttachmentFixtures {
    /// Phrase rendered into image/PDF fixtures and used as the acceptance
    /// probe. Deliberately unguessable so vendors that lossyString-mangle
    /// the bytes can't hallucinate a probe-matching response. (When the
    /// probe was "42", DeepSeek was matching every garbled-binary cell
    /// by guessing the canonical test answer. When the probe was
    /// "pinecone42", Gemini's OCR returned "pinecone" alone, failing
    /// strict equality but clearly demonstrating vision worked — the
    /// model can't hallucinate "pinecone" from binary noise.)
    static let visualProbe = "pinecone"

    /// String literal embedded inside text/markdown/json/xml/yaml/zip
    /// fixtures and used as the acceptance probe.
    static let textProbe = "pinecone-42"

    static func make(_ kind: AILiveAttachmentKind) throws -> AILiveAttachmentFixture {
        switch kind {
        case .textPlain:
            // Some vendors (notably Anthropic) inline textual attachments
            // as plain text blocks with no "this is a file" wrapper, which
            // makes prompts that say "this file" confuse the model into
            // refusing for lack of an attachment. Prompts in this fixture
            // set deliberately avoid that phrasing.
            let body = "The magic phrase is \(textProbe)."
            return AILiveAttachmentFixture(
                mime: "text/plain",
                filename: "magic.txt",
                bytes: Data(body.utf8),
                prompt: "Quote the magic phrase exactly as written.",
                acceptanceProbes: [textProbe])

        case .textMarkdown:
            let body = "# Magic\n\nThe phrase is **\(textProbe)**.\n"
            return AILiveAttachmentFixture(
                mime: "text/markdown",
                filename: "magic.md",
                bytes: Data(body.utf8),
                prompt: "Quote the bolded phrase.",
                acceptanceProbes: [textProbe])

        case .applicationJSON:
            let body = "{\"magic\":\"\(textProbe)\"}"
            return AILiveAttachmentFixture(
                mime: "application/json",
                filename: "magic.json",
                bytes: Data(body.utf8),
                prompt: "Quote the value of the \"magic\" field shown.",
                acceptanceProbes: [textProbe])

        case .applicationXML:
            let body = "<?xml version=\"1.0\"?><root><magic>\(textProbe)</magic></root>"
            return AILiveAttachmentFixture(
                mime: "application/xml",
                filename: "magic.xml",
                bytes: Data(body.utf8),
                prompt: "Quote the text inside the <magic> element shown.",
                acceptanceProbes: [textProbe])

        case .imageSVG:
            let body = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 20\">" +
                       "<text x=\"0\" y=\"15\">\(textProbe)</text></svg>"
            return AILiveAttachmentFixture(
                mime: "image/svg+xml",
                filename: "magic.svg",
                bytes: Data(body.utf8),
                prompt: "Quote the text inside the <text> element shown.",
                acceptanceProbes: [textProbe])

        case .yamlAsUnknown:
            let body = "magic: \(textProbe)\n"
            return AILiveAttachmentFixture(
                mime: "text/plain",
                filename: "magic.yaml",
                bytes: Data(body.utf8),
                prompt: "Quote the value of the 'magic' key shown.",
                acceptanceProbes: [textProbe])

        case .imagePNG:
            return AILiveAttachmentFixture(
                mime: "image/png",
                filename: "magic.png",
                bytes: try renderDigitsImage(format: .png),
                prompt: "What word do you see in this image? Reply with just the word.",
                acceptanceProbes: [visualProbe])

        case .imageWEBP:
            // ImageIO on macOS 12-15 ships a WebP decoder but no encoder,
            // so we can't generate a WebP at runtime via
            // CGImageDestination. The on-disk fixture was generated once
            // with cwebp from a "42" PNG; lossless-ARGB, 572 bytes.
            return AILiveAttachmentFixture(
                mime: "image/webp",
                filename: "magic.webp",
                bytes: try loadDiskFixture("magic.webp"),
                prompt: "What word do you see in this image? Reply with just the word.",
                acceptanceProbes: [visualProbe])

        case .imageHEIC:
            return AILiveAttachmentFixture(
                mime: "image/heic",
                filename: "magic.heic",
                bytes: try renderDigitsImage(format: .heic),
                prompt: "What word do you see in this image? Reply with just the word.",
                acceptanceProbes: [visualProbe])

        case .imageTIFF:
            return AILiveAttachmentFixture(
                mime: "image/tiff",
                filename: "magic.tiff",
                bytes: try renderDigitsImage(format: .tiff),
                prompt: "What word do you see in this image? Reply with just the word.",
                acceptanceProbes: [visualProbe])

        case .applicationPDF:
            return AILiveAttachmentFixture(
                mime: "application/pdf",
                filename: "magic.pdf",
                bytes: try renderProbePDF(),
                prompt: "What word is written in this PDF? Reply with just the word.",
                acceptanceProbes: [visualProbe])

        case .audioMPEG:
            return AILiveAttachmentFixture(
                mime: "audio/mpeg",
                filename: "sample.mp3",
                bytes: try loadDiskFixture("sample.mp3"),
                prompt: "Briefly describe this audio clip in one sentence.",
                // Three seconds of synth music; the model should mention at
                // least one of these words. Soft probe — recorded audio is
                // not as deterministic as text/image content.
                acceptanceProbes: ["audio", "sound", "music", "synth", "tone", "note", "instrument", "second"])

        case .videoMP4:
            return AILiveAttachmentFixture(
                mime: "video/mp4",
                filename: "sample.mp4",
                bytes: try loadDiskFixture("sample.mp4"),
                prompt: "Briefly describe what is happening in this video in one sentence.",
                // Scrolling in a web browser; the model should mention browsing,
                // scrolling, or a web page. Soft probe.
                acceptanceProbes: ["browser", "scroll", "page", "web", "website", "site", "document"])

        case .applicationDOCX:
            return AILiveAttachmentFixture(
                mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                filename: "sample.docx",
                bytes: try loadDiskFixture("sample.docx"),
                prompt: "Quote the first two words of the title of this document.",
                acceptanceProbes: ["lorem ipsum", "Lorem ipsum", "Lorem Ipsum", "lorem", "Lorem"])

        case .applicationZIP:
            // The payload is padded with repetitive content so the zip
            // command's default DEFLATE compression kicks in and the probe
            // no longer appears verbatim in the resulting bytes. Without
            // padding, a small payload gets stored uncompressed and any
            // textual probe leaks through the lossyString fallback,
            // making "garbled" cells unreliably match probes.
            let padding = String(repeating: "padding line for deflate compression. ", count: 256)
            let payload = padding + "\nThe magic phrase is \(textProbe).\n" + padding
            return AILiveAttachmentFixture(
                mime: "application/zip",
                filename: "magic.zip",
                bytes: try zipSingleFile(name: "magic.txt", content: Data(payload.utf8)),
                prompt: "What magic phrase is inside the file in this archive? Quote it verbatim.",
                acceptanceProbes: [textProbe])

        case .applicationOctet:
            // Random bytes; no semantic probe possible. This fixture is only
            // useful for rejection tests, so acceptanceProbes is empty.
            return AILiveAttachmentFixture(
                mime: "application/octet-stream",
                filename: "magic.bin",
                bytes: Data((0..<256).map { UInt8($0) }),
                prompt: "What is in this file?",
                acceptanceProbes: [])
        }
    }

    // MARK: - Loaders

    private static func loadDiskFixture(_ basename: String) throws -> Data {
        guard let root = projectRoot() else {
            throw AILiveAttachmentFixtureError.projectRootMissing
        }
        let path = (root as NSString)
            .appendingPathComponent("ModernTests")
            + "/Resources/AttachmentFixtures/\(basename)"
        guard FileManager.default.fileExists(atPath: path) else {
            throw AILiveAttachmentFixtureError.fixtureFileMissing(path)
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func projectRoot() -> String? {
        // See AILiveHarness.configPath() for why /tmp.
        let configPath = "/tmp/iterm2-ai-live.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return nil
        }
        let root = json["PROJECT_ROOT"] ?? ""
        return root.isEmpty ? nil : root
    }

    // MARK: - Image rendering

    private enum ImageFormat {
        // WebP is intentionally absent: ImageIO on macOS 12-15 lacks a
        // WebP encoder, so the WebP fixture is loaded from disk instead
        // of generated at runtime.
        case png, heic, tiff
        var utType: CFString {
            switch self {
            case .png:  return UTType.png.identifier as CFString
            case .heic: return UTType.heic.identifier as CFString
            case .tiff: return UTType.tiff.identifier as CFString
            }
        }
    }

    private static func renderDigitsImage(format: ImageFormat) throws -> Data {
        // Render the visual probe ("42") into a small 1x-DPI bitmap. NSImage
        // would inflate to retina scale here; constructing the
        // NSBitmapImageRep directly pins the pixel dimensions, which keeps
        // the eventual bytes small. Critical for formats that fall through
        // to lossyString on some vendors (Anthropic's TIFF path turns the
        // file into a one-char-per-byte text block; a 600KB TIFF blows the
        // 200K-token prompt budget).
        // Canvas wide enough that the multi-character visualProbe fits at
        // a font size big enough for vision models to OCR reliably.
        let pixelWidth = 400
        let pixelHeight = 120
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0) else {
            throw AILiveAttachmentFixtureError.imageRenderFailed
        }
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 48),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let s = NSAttributedString(string: visualProbe, attributes: attrs)
        let stringSize = s.size()
        s.draw(at: CGPoint(x: (CGFloat(pixelWidth) - stringSize.width) / 2,
                           y: (CGFloat(pixelHeight) - stringSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        // TIFF: encode via NSBitmapImageRep with LZW compression so the
        // bytes don't dwarf the request. CGImageDestination's default TIFF
        // is uncompressed.
        if case .tiff = format {
            guard let data = rep.representation(
                    using: .tiff,
                    properties: [.compressionMethod: NSNumber(value: NSBitmapImageRep.TIFFCompression.lzw.rawValue)]) else {
                throw AILiveAttachmentFixtureError.imageEncodeFailed(format: "tiff")
            }
            return data
        }

        guard let cg = rep.cgImage else {
            throw AILiveAttachmentFixtureError.imageRenderFailed
        }
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                buffer as CFMutableData,
                format.utType,
                1, nil) else {
            throw AILiveAttachmentFixtureError.imageEncodeFailed(format: format.utType as String)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AILiveAttachmentFixtureError.imageEncodeFailed(format: format.utType as String)
        }
        return buffer as Data
    }

    // MARK: - PDF rendering

    private static func renderProbePDF() throws -> Data {
        // Canvas wide enough that the rendered string is not clipped at
        // font size 28 ("The number is 42." takes ~210pt at this size).
        let pixelWidth = 612    // US Letter width @ 72dpi for natural PDF dims
        let pixelHeight = 200
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0) else {
            throw AILiveAttachmentFixtureError.pdfRenderFailed
        }
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 28),
            .foregroundColor: NSColor.black,
        ]
        let s = NSAttributedString(string: "The word is \(visualProbe).", attributes: attrs)
        s.draw(at: CGPoint(x: 40, y: CGFloat(pixelHeight) / 2 - 14))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage,
              let nsImage = NSImage(cgImage: cg, size: NSSize(width: pixelWidth, height: pixelHeight)) as NSImage? else {
            throw AILiveAttachmentFixtureError.pdfRenderFailed
        }
        guard let page = PDFPage(image: nsImage) else {
            throw AILiveAttachmentFixtureError.pdfRenderFailed
        }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        guard let data = doc.dataRepresentation() else {
            throw AILiveAttachmentFixtureError.pdfRenderFailed
        }
        return data
    }

    // MARK: - ZIP packaging

    private static func zipSingleFile(name: String, content: Data) throws -> Data {
        // Stage <tmp>/zip-staging-<uuid>/<name>, zip from there to
        // <tmp>/<uuid>.zip, read back. Uses iTermCommandRunner.zip which is
        // already in the test bundle.
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }
        let payloadURL = stagingDir.appendingPathComponent(name)
        try content.write(to: payloadURL)

        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }
        let zipURL = outDir.appendingPathComponent("payload.zip")

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        iTermCommandRunner.zip([URL(fileURLWithPath: name, relativeTo: stagingDir)],
                               arguments: [],
                               toZip: zipURL,
                               relativeTo: stagingDir,
                               callbackQueue: .main) { ok in
            success = ok
            semaphore.signal()
        }
        // iTermCommandRunner.zip dispatches the callback to .main; running
        // the main run loop here is fine because this helper is only called
        // from XCTest threads, which the harness already drives by spinning
        // the run loop via wait(for:timeout:). Wait without blocking main
        // by yielding to the run loop.
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        guard success else {
            throw AILiveAttachmentFixtureError.zipFailed
        }
        return try Data(contentsOf: zipURL)
    }
}

enum AILiveAttachmentFixtureError: Error, CustomStringConvertible {
    case projectRootMissing
    case fixtureFileMissing(String)
    case imageRenderFailed
    case imageEncodeFailed(format: String)
    case pdfRenderFailed
    case zipFailed

    var description: String {
        switch self {
        case .projectRootMissing:
            return "PROJECT_ROOT not set in iterm2-ai-live.json (live harness invoked outside run_ai_live.sh?)"
        case .fixtureFileMissing(let path):
            return "fixture file missing on disk: \(path)"
        case .imageRenderFailed:
            return "failed to render NSImage for fixture"
        case .imageEncodeFailed(let format):
            return "failed to encode CGImage as \(format)"
        case .pdfRenderFailed:
            return "failed to build PDF fixture"
        case .zipFailed:
            return "iTermCommandRunner.zip returned ok=false"
        }
    }
}
