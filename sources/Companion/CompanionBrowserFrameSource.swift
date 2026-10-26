//
//  CompanionBrowserFrameSource.swift
//  iTerm2
//
//  The live frame source for a web browser session: streams snapshots of the
//  session's web view. WKWebView renders out of process, so a snapshot arrives
//  asynchronously; tick() keeps one snapshot in flight at a time (capped at
//  snapshotsPerSecond) and renderCurrentScreen() returns the newest one. A
//  browser has no cell grid, scrollback, or alternate screen, so the stream
//  config carries no cell geometry and zero rows/lines, which makes the phone
//  show the video without history tiles or text selection.
//
//  WebKit draws a text field's insertion point only while the web view's window
//  is key, which it usually is not while someone uses the phone. So this asks
//  the page where the insertion point is (companion-browser-editing.js) and
//  draws a blinking one into the frames itself whenever WebKit does not.
//
//  Must be used on the main thread.
//

import AppKit
import WebKit

final class CompanionBrowserFrameSource: CompanionLiveFrameSource {
    /// Web view snapshots are much more expensive than rendering a terminal grid,
    /// so they are taken less often than the stream's frame-rate cap.
    private static let snapshotsPerSecond = 10.0
    /// How often to check whether the page's focused element is a text editor,
    /// and, while one is, where its insertion point is.
    private static let editingChecksPerSecond = 4.0
    private static let caretChecksPerSecond = 10.0
    /// How long the drawn insertion point stays on, then off, while blinking.
    /// It stays on for the first period after it moves.
    private static let caretBlinkPeriod: TimeInterval = 0.5
    private static let editingScript = iTermBrowserTemplateLoader.loadTemplate(named: "companion-browser-editing",
                                                                               type: "js")

    private let session: PTYSession
    private var latestImage: CGImage?
    private var latestScale: Double?
    private var snapshotInFlight = false
    private var lastSnapshotStartedAt: TimeInterval = 0
    private var loggedFailure = false
    private(set) var contentLastChangedAt: TimeInterval = 0
    /// Whether the page's focused element is a text editor, from the most recent
    /// check.
    private var focusedElementIsEditor = false
    private var editingCheckInFlight = false
    private var lastEditingCheckStartedAt: TimeInterval = 0
    /// Where to draw the insertion point, from the most recent check.
    private var caret: CompanionBrowserCaret?
    private var caretMovedAt: TimeInterval = 0
    /// Whether the insertion point is in the on phase of its blink.
    private var caretBlinkOn = false
    /// The last frame with the insertion point drawn in, to avoid redrawing it
    /// for every render of the same snapshot.
    private var composited: (image: CGImage, caret: CompanionBrowserCaret, result: CGImage)?

    init(session: PTYSession) {
        self.session = session
    }

    private var webView: WKWebView? {
        MainActor.assumeIsolated {
            session.view?.browserViewController?.webView
        }
    }

    var columns: Int { 0 }
    var rows: Int { 0 }
    var scale: Double {
        if let latestScale {
            return latestScale
        }
        return MainActor.assumeIsolated {
            Double(webView?.window?.backingScaleFactor ?? 2.0)
        }
    }
    var cellGeometry: CompanionCellGeometry? { nil }
    var liveTop: Int64 { 0 }
    // The phone resizes in terms of cells, which a browser does not have.
    var canResize: Bool { false }
    var isBrowser: Bool { true }

    /// Whether a text field on the page has keyboard focus. The browser's editing
    /// detector only reports editing while the web view's window is key, which it
    /// usually is not while someone uses the phone, so this also asks the page
    /// which element has focus (see tick()). The detector still covers editors
    /// inside cross-origin frames when the window is key.
    var isEditingText: Bool {
        MainActor.assumeIsolated {
            focusedElementIsEditor || (session.view?.browserViewController?.webView.isEditingText ?? false)
        }
    }

    /// Check the focused element on the next tick rather than waiting for the
    /// next periodic check, because the user just did something (such as a tap)
    /// that may have moved focus.
    func checkEditingSoon() {
        lastEditingCheckStartedAt = 0
    }

    /// The web view point (origin at the top left) shown at `imagePoint` in the
    /// most recent frame, or nil before the first frame.
    func webViewPoint(imagePoint: CGPoint) -> CGPoint? {
        guard let latestScale, latestScale > 0 else {
            return nil
        }
        return CGPoint(x: imagePoint.x / latestScale, y: imagePoint.y / latestScale)
    }

    /// The scale of the most recent frame in encoded pixels per web view point.
    var frameScale: Double? {
        latestScale
    }

    var browserWebView: iTermBrowserWebView? {
        MainActor.assumeIsolated {
            session.view?.browserViewController?.webView
        }
    }

    var browserViewController: iTermBrowserViewController? {
        MainActor.assumeIsolated {
            session.view?.browserViewController
        }
    }

    /// What the phone's browser controls show, or nil if the web view is gone.
    var navigationState: CompanionBrowserNavigationState? {
        MainActor.assumeIsolated {
            guard let webView = session.view?.browserViewController?.webView else {
                return nil
            }
            return CompanionBrowserNavigationState(url: webView.url?.absoluteString ?? "",
                                                   title: webView.title ?? "",
                                                   canGoBack: webView.canGoBack,
                                                   canGoForward: webView.canGoForward,
                                                   isLoading: webView.isLoading)
        }
    }

    func tick() {
        MainActor.assumeIsolated {
            startSnapshotIfNeeded()
            startEditingCheckIfNeeded()
            updateCaretBlink()
        }
    }

    private func updateCaretBlink() {
        let on: Bool
        if caret == nil {
            on = false
        } else {
            let periods = Int((CACurrentMediaTime() - caretMovedAt) / Self.caretBlinkPeriod)
            on = periods % 2 == 0
        }
        if on != caretBlinkOn {
            caretBlinkOn = on
            contentLastChangedAt = CACurrentMediaTime()
        }
    }

    private func setCaret(_ newValue: CompanionBrowserCaret?) {
        guard newValue != caret else {
            return
        }
        caret = newValue
        caretMovedAt = CACurrentMediaTime()
        caretBlinkOn = newValue != nil
        contentLastChangedAt = CACurrentMediaTime()
    }

    @MainActor
    private func startEditingCheckIfNeeded() {
        guard !editingCheckInFlight, let webView = session.view?.browserViewController?.webView else {
            return
        }
        let now = CACurrentMediaTime()
        // Check more often while editing so the drawn insertion point keeps up.
        let rate = focusedElementIsEditor ? Self.caretChecksPerSecond : Self.editingChecksPerSecond
        guard now - lastEditingCheckStartedAt >= 1.0 / rate else {
            return
        }
        lastEditingCheckStartedAt = now
        editingCheckInFlight = true
        // An isolated world, so the page's own scripts cannot interfere.
        webView.safelyCallAsyncJavaScript(Self.editingScript, contentWorld: .defaultClient) { [weak self] result, error in
            guard let self else {
                return
            }
            editingCheckInFlight = false
            if let error {
                DLog("Companion browser editing check failed: \(error)")
                focusedElementIsEditor = false
                setCaret(nil)
                return
            }
            let dictionary = result as? [String: Any]
            focusedElementIsEditor = (dictionary?["editing"] as? Bool) ?? false
            setCaret(CompanionBrowserCaret(checkResult: dictionary))
        }
    }

    @MainActor
    private func startSnapshotIfNeeded() {
        guard !snapshotInFlight, let webView, webView.bounds.width > 0, webView.bounds.height > 0 else {
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastSnapshotStartedAt >= 1.0 / Self.snapshotsPerSecond else {
            return
        }
        lastSnapshotStartedAt = now
        snapshotInFlight = true
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        // Waiting for a screen update would stall for a web view that is not on
        // screen; the current contents are good enough for a live feed.
        configuration.afterScreenUpdates = false
        let pointWidth = webView.bounds.width
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self else {
                return
            }
            snapshotInFlight = false
            guard let image, let cgImage = Self.cgImage(from: image) else {
                if !loggedFailure {
                    loggedFailure = true
                    RLog("Companion browser stream: snapshot failed for \(session.guid): \(String(describing: error))")
                }
                return
            }
            latestImage = cgImage
            latestScale = Double(cgImage.width) / Double(pointWidth)
            // The streamer drops frames whose pixels did not change, so reporting
            // every snapshot as a change costs nothing on a static page.
            contentLastChangedAt = CACurrentMediaTime()
        }
    }

    func renderCurrentScreen() -> CGImage? {
        guard let latestImage else {
            return nil
        }
        guard caretBlinkOn, let caret else {
            return latestImage
        }
        if let composited, composited.image === latestImage, composited.caret == caret {
            return composited.result
        }
        guard let result = caret.draw(on: latestImage, pixelsPerPoint: latestScale ?? 2) else {
            return latestImage
        }
        composited = (latestImage, caret, result)
        return result
    }

    /// The snapshot's backing image, at full (backing-scale) resolution.
    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// An insertion point to draw into a browser frame, in fractions of the frame
/// so it does not depend on the frame's resolution.
struct CompanionBrowserCaret: Equatable {
    var x: Double
    var y: Double
    var height: Double
    var color: CGColor

    init(x: Double, y: Double, height: Double, color: CGColor) {
        self.x = x
        self.y = y
        self.height = height
        self.color = color
    }

    /// The insertion point from companion-browser-editing.js's result, or nil if
    /// there is none to draw (including when the page made it transparent, which
    /// editors that draw their own do).
    init?(checkResult: [String: Any]?) {
        guard let caret = checkResult?["caret"] as? [String: Any],
              let x = (caret["x"] as? NSNumber)?.doubleValue,
              let y = (caret["y"] as? NSNumber)?.doubleValue,
              let height = (caret["height"] as? NSNumber)?.doubleValue,
              height > 0,
              let color = Self.color(css: caret["color"] as? String),
              color.alpha > 0 else {
            return nil
        }
        self.init(x: x, y: y, height: height, color: color)
    }

    /// Parses a computed CSS color, which is rgb() or rgba() for sRGB colors.
    /// Other color spaces fall back to black.
    static func color(css: String?) -> CGColor? {
        guard let css else {
            return nil
        }
        let trimmed = css.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("rgb"),
              let open = trimmed.firstIndex(of: "("),
              let close = trimmed.lastIndex(of: ")"),
              open < close else {
            return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
        let components = trimmed[trimmed.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0) }
        guard components.count >= 3 else {
            return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
        let alpha = components.count >= 4 ? components[3] : 1
        return CGColor(srgbRed: components[0] / 255, green: components[1] / 255, blue: components[2] / 255,
                       alpha: alpha)
    }

    /// A copy of `image` with the insertion point drawn in, one point wide.
    func draw(on image: CGImage, pixelsPerPoint: Double) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        let caretWidth = max(1, pixelsPerPoint.rounded())
        let caretHeight = (self.height * Double(height)).rounded()
        let top = (y * Double(height)).rounded()
        // Core Graphics puts the origin at the bottom left.
        let rect = CGRect(x: (x * Double(width)).rounded(),
                          y: Double(height) - top - caretHeight,
                          width: caretWidth,
                          height: caretHeight)
        context.setFillColor(color)
        context.fill(rect.intersection(bounds))
        return context.makeImage()
    }
}
