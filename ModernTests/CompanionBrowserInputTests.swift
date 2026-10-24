//
//  CompanionBrowserInputTests.swift
//  iTerm2 ModernTests
//
//  The key mapping for phone input to a web page, and end-to-end delivery of
//  clicks, keys, and scrolls into a real WKWebView, both in a window that is not
//  key and with no window at all (a browser in a background tab).
//

import XCTest
import WebKit
import Carbon.HIToolbox
@testable import iTerm2SharedARC

final class CompanionBrowserInputTests: XCTestCase {
    private typealias Stroke = CompanionBrowserInput.Stroke

    // MARK: - Key mapping

    func testLettersAndShiftedSymbolsAreKeyPresses() {
        XCTAssertEqual(CompanionBrowserInput.strokes(for: CompanionKeyEvent(key: .text("aB!"))), [
            .key(characters: "a", charactersIgnoringModifiers: "a",
                 keyCode: UInt16(kVK_ANSI_A), modifiers: []),
            .key(characters: "B", charactersIgnoringModifiers: "B",
                 keyCode: UInt16(kVK_ANSI_B), modifiers: .shift),
            .key(characters: "!", charactersIgnoringModifiers: "!",
                 keyCode: UInt16(kVK_ANSI_1), modifiers: .shift),
        ])
    }

    func testNewlineIsReturn() {
        for text in ["\n", "\r"] {
            XCTAssertEqual(CompanionBrowserInput.strokes(for: CompanionKeyEvent(key: .text(text))), [
                .key(characters: "\r", charactersIgnoringModifiers: "\r",
                     keyCode: UInt16(kVK_Return), modifiers: []),
            ])
        }
    }

    func testCharactersWithoutAKeyAreInsertedAsText() {
        XCTAssertEqual(CompanionBrowserInput.strokes(for: CompanionKeyEvent(key: .text("é😀a"))), [
            .text("é😀"),
            .key(characters: "a", charactersIgnoringModifiers: "a",
                 keyCode: UInt16(kVK_ANSI_A), modifiers: []),
        ])
    }

    func testControlLetterProducesControlCharacter() {
        let event = CompanionKeyEvent(key: .text("c"), modifiers: CompanionKeyModifiers(control: true))
        XCTAssertEqual(CompanionBrowserInput.strokes(for: event), [
            .key(characters: "\u{3}", charactersIgnoringModifiers: "c",
                 keyCode: UInt16(kVK_ANSI_C), modifiers: .control),
        ])
    }

    func testSpecialKeys() {
        XCTAssertEqual(CompanionBrowserInput.strokes(for: CompanionKeyEvent(key: .special(.backspace))), [
            .key(characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
                 keyCode: UInt16(kVK_Delete), modifiers: []),
        ])
        let left = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        let shiftLeft = CompanionKeyEvent(key: .special(.left), modifiers: CompanionKeyModifiers(shift: true))
        XCTAssertEqual(CompanionBrowserInput.strokes(for: shiftLeft), [
            .key(characters: left, charactersIgnoringModifiers: left,
                 keyCode: UInt16(kVK_LeftArrow), modifiers: [.shift, .numericPad, .function]),
        ])
    }

    // MARK: - Delivery into a real web view

    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        var expectation: XCTestExpectation?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            expectation?.fulfill()
        }
    }

    private let html = """
    <html><body style='margin:0'>
    <form onsubmit='window.submitted = (window.submitted || 0) + 1; return false;'>
    <input id=field style='position:absolute; left:20px; top:20px; width:200px; height:30px'>
    </form>
    <a href='#' onclick='window.clicked = (window.clicked || 0) + 1; return false;'
       style='position:absolute; left:20px; top:80px'>link</a>
    <textarea id=area style='position:absolute; left:20px; top:120px; width:200px; height:30px'></textarea>
    <div id=editor contenteditable style='position:absolute; left:20px; top:180px; width:200px; height:30px'>x</div>
    <div style='height:5000px'></div>
    </body></html>
    """

    @MainActor
    private func evaluate(_ webView: WKWebView, _ script: String) async -> String {
        let result = try? await webView.evaluateJavaScript(script)
        return result.map { "\($0)" } ?? ""
    }

    /// Wait (without a fixed delay) until `script` evaluates to `expected`.
    @MainActor
    private func waitFor(_ webView: WKWebView,
                         _ script: String,
                         toBe expected: String,
                         file: StaticString = #filePath,
                         line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(15)
        var last = ""
        while Date() < deadline {
            last = await evaluate(webView, script)
            if last == expected {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("\(script) is \(last), expected \(expected)", file: file, line: line)
    }

    @MainActor
    private func editingCheck(_ webView: WKWebView) async -> [String: Any]? {
        let script = iTermBrowserTemplateLoader.loadTemplate(named: "companion-browser-editing", type: "js")
        return (try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient)) as? [String: Any]
    }

    /// Wait until iTerm2 Buddy's editing check satisfies `condition`, and return
    /// the insertion point it reported.
    @discardableResult
    @MainActor
    private func waitForCheck(_ webView: WKWebView,
                              _ description: String,
                              file: StaticString = #filePath,
                              line: UInt = #line,
                              _ condition: ([String: Any]?) -> Bool) async throws -> CompanionBrowserCaret? {
        let deadline = Date().addingTimeInterval(15)
        var last: [String: Any]?
        while Date() < deadline {
            last = await editingCheck(webView)
            if condition(last) {
                return CompanionBrowserCaret(checkResult: last)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("editing check \(String(describing: last)) is not \(description)", file: file, line: line)
        return nil
    }

    /// Wait until iTerm2 Buddy's focused-editor check reports `expected`.
    @MainActor
    private func waitForEditing(_ webView: WKWebView,
                                toBe expected: Bool,
                                file: StaticString = #filePath,
                                line: UInt = #line) async throws {
        try await waitForCheck(webView, "editing=\(expected)", file: file, line: line) {
            ($0?["editing"] as? Bool) == expected
        }
    }

    /// Wait for an insertion point to draw whose left edge is in `xRange` and
    /// that is vertically within `yRange`, both in web view points.
    @discardableResult
    @MainActor
    private func waitForCaret(_ webView: WKWebView,
                              x xRange: ClosedRange<Double>,
                              y yRange: ClosedRange<Double>,
                              file: StaticString = #filePath,
                              line: UInt = #line) async throws -> CompanionBrowserCaret? {
        let size = webView.bounds.size
        return try await waitForCheck(webView, "a caret in x \(xRange) y \(yRange)", file: file, line: line) {
            guard let caret = CompanionBrowserCaret(checkResult: $0) else {
                return false
            }
            let top = caret.y * size.height
            return xRange.contains(caret.x * size.width)
                && top >= yRange.lowerBound
                && top + caret.height * size.height <= yRange.upperBound
        }
    }

    @MainActor
    private func exercise(inWindow: Bool) async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var window: NSWindow?
        if inWindow {
            window = NSWindow(contentRect: webView.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
            window?.isReleasedWhenClosed = false
            window?.contentView?.addSubview(webView)
            window?.orderBack(nil)
        }
        defer {
            window?.close()
        }
        let waiter = NavigationWaiter()
        waiter.expectation = expectation(description: "page loaded")
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
        await fulfillment(of: [waiter.expectation!], timeout: 15)

        try await waitForEditing(webView, toBe: false)
        CompanionBrowserInput.click(webView, at: CGPoint(x: 100, y: 35))
        try await waitFor(webView, "document.activeElement.id", toBe: "field")
        // The window is not key (or there is none), so the page does not have
        // focus, but the focused field still counts as editing.
        try await waitForEditing(webView, toBe: true)
        // The empty field's insertion point is at its left edge, inside its box.
        let emptyCaret = try await waitForCaret(webView, x: 20...32, y: 20...52)
        // WebKit does not draw one in a window that is not key, so the check
        // reports one to draw.
        XCTAssertEqual(emptyCaret?.color, CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

        CompanionBrowserInput.send(CompanionKeyEvent(key: .text("Hé")), to: webView)
        CompanionBrowserInput.send(CompanionKeyEvent(key: .special(.backspace)), to: webView)
        CompanionBrowserInput.send(CompanionKeyEvent(key: .text("i!")), to: webView)
        try await waitFor(webView, "document.getElementById('field').value", toBe: "Hi!")
        // Typing moves it right.
        try await waitForCaret(webView, x: 30...60, y: 20...52)
        // A range selection has no insertion point.
        _ = await evaluate(webView, "document.getElementById('field').select(), 1")
        try await waitForCheck(webView, "editing without a caret") {
            ($0?["editing"] as? Bool) == true && CompanionBrowserCaret(checkResult: $0) == nil
        }

        CompanionBrowserInput.send(CompanionKeyEvent(key: .text("\n")), to: webView)
        try await waitFor(webView, "window.submitted", toBe: "1")

        CompanionBrowserInput.click(webView, at: CGPoint(x: 30, y: 88))
        try await waitFor(webView, "window.clicked", toBe: "1")
        try await waitForEditing(webView, toBe: false)

        CompanionBrowserInput.click(webView, at: CGPoint(x: 100, y: 135))
        try await waitFor(webView, "document.activeElement.id", toBe: "area")
        try await waitForEditing(webView, toBe: true)
        try await waitForCaret(webView, x: 20...32, y: 120...154)

        // A contenteditable element measures the selection instead.
        CompanionBrowserInput.click(webView, at: CGPoint(x: 150, y: 190))
        try await waitFor(webView, "document.activeElement.id", toBe: "editor")
        try await waitForCaret(webView, x: 24...40, y: 178...212)

        // Content moving up by 200 points scrolls the page down by 200.
        CompanionBrowserInput.scroll(webView, at: CGPoint(x: 200, y: 150), deltaX: 0, deltaY: -200)
        try await waitFor(webView, "window.scrollY", toBe: "200")
    }

    /// The insertion point is reported in fractions of what is on screen, so it
    /// lines up with the frames when the page is zoomed.
    @MainActor
    func testCaretFollowsPageZoom() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let waiter = NavigationWaiter()
        waiter.expectation = expectation(description: "page loaded")
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
        await fulfillment(of: [waiter.expectation!], timeout: 15)
        webView.pageZoom = 2
        _ = await evaluate(webView, "document.getElementById('field').focus(), 1")
        // Everything is twice as far from the top left as at 100%.
        try await waitForCaret(webView, x: 40...64, y: 40...104)
    }

    func testInputReachesPageInWindowThatIsNotKey() async throws {
        try await exercise(inWindow: true)
    }

    func testInputReachesPageWithNoWindow() async throws {
        try await exercise(inWindow: false)
    }

    // MARK: Drawn insertion point

    func testCaretColorParsing() {
        XCTAssertEqual(CompanionBrowserCaret.color(css: "rgb(255, 0, 51)"),
                       CGColor(srgbRed: 1, green: 0, blue: 0.2, alpha: 1))
        XCTAssertEqual(CompanionBrowserCaret.color(css: "rgba(0, 0, 255, 0.5)"),
                       CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.5))
        // Other color spaces fall back to black.
        XCTAssertEqual(CompanionBrowserCaret.color(css: "color(display-p3 1 0 0)"),
                       CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    }

    func testTransparentCaretIsNotDrawn() {
        let result: [String: Any] = ["editing": true,
                                     "caret": ["x": 0.1, "y": 0.1, "height": 0.1, "color": "rgba(0, 0, 0, 0)"]]
        XCTAssertNil(CompanionBrowserCaret(checkResult: result))
    }

    func testCaretIsDrawnIntoFrame() throws {
        let width = 100
        let height = 50
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let blank = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        blank.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        blank.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(blank.makeImage())

        let caret = CompanionBrowserCaret(x: 0.5, y: 0.2, height: 0.4,
                                          color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let drawn = try XCTUnwrap(caret.draw(on: image, pixelsPerPoint: 2))
        XCTAssertEqual(drawn.width, width)
        XCTAssertEqual(drawn.height, height)

        // Read the pixels back top-down as RGBA.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let reader = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: colorSpace,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        reader.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        func pixel(x: Int, y: Int) -> [UInt8] {
            // The bitmap's first row is the top of the image.
            let offset = (y * width + x) * 4
            return Array(pixels[offset..<offset + 3])
        }
        // Two pixels wide, from 20% to 60% of the height.
        XCTAssertEqual(pixel(x: 50, y: 10), [255, 0, 0])
        XCTAssertEqual(pixel(x: 51, y: 29), [255, 0, 0])
        XCTAssertEqual(pixel(x: 52, y: 20), [255, 255, 255])
        XCTAssertEqual(pixel(x: 50, y: 9), [255, 255, 255])
        XCTAssertEqual(pixel(x: 50, y: 30), [255, 255, 255])
    }

    // MARK: Address field

    func testTypedURLIsOpened() {
        XCTAssertEqual(urlStringForTypedText("  iterm2.com/features "), "https://iterm2.com/features")
        XCTAssertEqual(urlStringForTypedText("http://example.com/a?b=c"), "http://example.com/a?b=c")
    }

    func testTypedTextIsSearchedFor() {
        XCTAssertEqual(urlStringForTypedText("terminal emulator"), webSearchURLString(for: "terminal emulator"))
        // A lone word could be an intranet host, but the URL bar searches for it.
        XCTAssertEqual(urlStringForTypedText("weather"), webSearchURLString(for: "weather"))
    }

    func testBlankTypedTextLoadsNothing() {
        XCTAssertNil(urlStringForTypedText("   "))
    }
}
