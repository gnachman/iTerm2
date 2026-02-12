//
//  iTermBrowserPageSaverTestHelper.swift
//  iTerm2XCTests
//
//  Created by Claude on 6/24/25.
//

import Foundation
import WebKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
class iTermBrowserPageSaverTestHelper {
    private let tempDirectory: URL
    private let serverPort: Int
    private var webView: iTermBrowserWebView!
    private var httpServer: iTermTestHTTPServer!
    private var navigationDelegate: WKNavigationDelegate?
    private let loggingHandler = iTermBrowserPageSaverTestHelperLoggingHandler()

    init() throws {
        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iterm-page-saver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Find available port for HTTP server
        serverPort = try iTermTestHTTPServer.findAvailablePort()
        
        setupTestResources()
        setupHTTPServer()
        setupWebView()
    }
    
    deinit {
        httpServer?.stop()
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Test Resource Creation
    
    private func setupTestResources() {
        createTestHTML()
        createTestCSS()
        createTestImage()
        createTestJS()
    }
    
    private func createTestHTML() {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Test Page</title>
            <link rel="stylesheet" href="/test.css">
        </head>
        <body>
            <h1 id="title">Test Page Title</h1>
            <p>This is a test paragraph with <strong>bold text</strong>.</p>
            <img src="/test-image.png" alt="Test Image" id="test-image">
            <div class="background-test">Background image test</div>
            <script src="/test.js"></script>
        </body>
        </html>
        """
        
        let htmlFile = tempDirectory.appendingPathComponent("index.html")
        try! html.write(to: htmlFile, atomically: true, encoding: .utf8)
    }
    
    private func createTestCSS() {
        let css = """
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f0f0f0;
        }
        
        h1 {
            color: #333;
            border-bottom: 2px solid #007acc;
        }
        
        .background-test {
            width: 200px;
            height: 100px;
            background-image: url('/test-bg.png');
            background-repeat: no-repeat;
            background-size: cover;
        }
        
        @import url('/imported.css');
        """
        
        let cssFile = tempDirectory.appendingPathComponent("test.css")
        try! css.write(to: cssFile, atomically: true, encoding: .utf8)
        
        // Create imported CSS file
        let importedCSS = """
        .imported-style {
            color: red;
            font-weight: bold;
        }
        """
        
        let importedCSSFile = tempDirectory.appendingPathComponent("imported.css")
        try! importedCSS.write(to: importedCSSFile, atomically: true, encoding: .utf8)
    }
    
    private func createTestImage() {
        // Create a simple PNG image (1x1 pixel red image)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
        image.unlockFocus()
        
        let imageData = image.tiffRepresentation!
        let bitmap = NSBitmapImageRep(data: imageData)!
        let pngData = bitmap.representation(using: .png, properties: [:])!
        
        let imageFile = tempDirectory.appendingPathComponent("test-image.png")
        try! pngData.write(to: imageFile)
        
        // Create background image
        let bgImageFile = tempDirectory.appendingPathComponent("test-bg.png")
        try! pngData.write(to: bgImageFile)
    }
    
    private func createTestJS() {
        let js = """
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Test JavaScript loaded');
            document.getElementById('title').style.color = 'blue';
        });
        """
        
        let jsFile = tempDirectory.appendingPathComponent("test.js")
        try! js.write(to: jsFile, atomically: true, encoding: .utf8)
    }
    
    // MARK: - HTTP Server Setup
    
    private func setupHTTPServer() {
        httpServer = iTermTestHTTPServer(port: serverPort, documentRoot: tempDirectory)
        httpServer.start()
    }
    
    // MARK: - WebView Setup
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()

        let logErrors = iTermBrowserTemplateLoader.loadTemplate(named: "log-errors",
                                                                        type: "js",
                                                                        substitutions: [:])

        let js = iTermBrowserTemplateLoader.loadTemplate(named: "console-log",
                                                         type: "js",
                                                         substitutions: ["LOG_ERRORS": logErrors])
        configuration.userContentController.addUserScript(WKUserScript(
            source: "(function() {" + js + "})();",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page))
        configuration.userContentController.addUserScript(WKUserScript(
            source: iTermBrowserTemplateLoader.load(template: "graph-discovery.js", substitutions: [:]),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page))

        configuration.userContentController.add(loggingHandler, name: "iTerm2ConsoleLog")

        let pointerController = PointerController()
        webView = iTermBrowserWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                                       configuration: configuration,
                                       pointerController: pointerController)
    }
    
    // MARK: - Test Methods
    
    @MainActor
    func loadTestPage() async throws {
        let url = URL(string: "http://localhost:\(serverPort)/")!
        let request = URLRequest(url: url)

        return try await withCheckedThrowingContinuation { continuation in
            @MainActor
            class NavigationDelegate: NSObject, WKNavigationDelegate {
                let continuation: CheckedContinuation<Void, Error>
                weak var helper: iTermBrowserPageSaverTestHelper?

                init(continuation: CheckedContinuation<Void, Error>, helper: iTermBrowserPageSaverTestHelper) {
                    self.continuation = continuation
                    self.helper = helper
                    super.init()
                }

                func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                    helper?.navigationDelegate = nil // Clean up reference
                    continuation.resume()
                }

                func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
                    helper?.navigationDelegate = nil // Clean up reference
                    continuation.resume(throwing: error)
                }

                func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
                    helper?.navigationDelegate = nil // Clean up reference
                    continuation.resume(throwing: error)
                }
            }

            let delegate = NavigationDelegate(continuation: continuation, helper: self)
            self.navigationDelegate = delegate // Keep strong reference
            webView.navigationDelegate = delegate
            webView.load(request)
        }
    }
    
    func savePageAndVerify() async throws -> (originalHTML: String, savedHTML: String, savedFolder: URL) {
        // Get original HTML
        let originalHTML = try await getPageHTML()
        
        // Create save directory
        let saveFolder = tempDirectory.appendingPathComponent("saved-page-\(UUID().uuidString)")
        
        // Save the page
        let baseURL = webView.url!
        let pageSaver = iTermBrowserPageSaver(webView: webView, baseURL: baseURL)
        try await pageSaver.savePageWithResources(to: SSHLocation(path: saveFolder.path,
                                                                  endpoint: LocalhostEndpoint.instance))

        // Read saved HTML
        let savedHTMLFile = saveFolder.appendingPathComponent("index.html")
        let savedHTML = try String(contentsOf: savedHTMLFile, encoding: .utf8)
        
        return (originalHTML, savedHTML, saveFolder)
    }
    
    func verifyPageIntegrity(originalHTML: String, savedHTML: String, savedFolder: URL) throws {
        // Verify DOCTYPE is preserved
        XCTAssertTrue(savedHTML.hasPrefix("<!DOCTYPE html>"), "Saved HTML should include DOCTYPE declaration")
        
        // Verify basic structure
        XCTAssertTrue(savedHTML.contains("<title>Test Page</title>"), "Title should be preserved")
        XCTAssertTrue(savedHTML.contains("Test Page Title"), "Content should be preserved")
        
        // Verify CSS was inlined
        XCTAssertTrue(savedHTML.contains("<style>"), "CSS should be inlined as style tags")
        XCTAssertFalse(savedHTML.contains("<link rel=\"stylesheet\""), "CSS links should be replaced with style tags")
        
        // Verify CSS content is present
        XCTAssertTrue(savedHTML.contains("font-family: Arial"), "CSS content should be preserved")
        XCTAssertTrue(savedHTML.contains("border-bottom: 2px solid"), "CSS styles should be preserved")
        
        // Verify images are referenced locally
        XCTAssertTrue(savedHTML.contains("src=\"resources/"), "Images should reference local resources folder")
        
        // Verify resources folder exists
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesFolder.path), "Resources folder should exist")
        
        // Verify specific resource files exist
        let resourceFiles = try FileManager.default.contentsOfDirectory(atPath: resourcesFolder.path)
        XCTAssertTrue(resourceFiles.contains { $0.hasSuffix(".png") }, "Image files should be saved")
        XCTAssertTrue(resourceFiles.contains { $0.hasSuffix(".js") }, "JavaScript files should be saved")
        
        // Verify CSS background images are rewritten
        XCTAssertTrue(savedHTML.contains("url('resources/"), "CSS background images should reference local files")
    }
    
    @MainActor
    private func getPageHTML() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let html = result as? String {
                    continuation.resume(returning: html)
                } else {
                    continuation.resume(throwing: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get HTML"]))
                }
            }
        }
    }
    
    // MARK: - Page Integrity Testing Methods
    
    @MainActor
    func getOriginalPageHTML() async throws -> String {
        return try await getPageHTML()
    }
    
    @MainActor
    func getImageSrc() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.getElementById('test-image').src") { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let src = result as? String {
                    continuation.resume(returning: src)
                } else {
                    continuation.resume(throwing: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get image src"]))
                }
            }
        }
    }
    
    @MainActor
    func pageHasDataSavedAttributes() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let script = """
            (function() {
                const elementsWithDataSaved = document.querySelectorAll('[data-saved-src], [data-saved-href], [data-saved-css-content]');
                return elementsWithDataSaved.length > 0;
            })();
            """
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let hasAttributes = result as? Bool {
                    continuation.resume(returning: hasAttributes)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    @MainActor
    func getPageTitle() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.title") { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let title = result as? String {
                    continuation.resume(returning: title)
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    @MainActor
    func getCSSLinkCount() async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            let script = """
            document.querySelectorAll('link[rel="stylesheet"]').length
            """
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let count = result as? Int {
                    continuation.resume(returning: count)
                } else {
                    continuation.resume(returning: 0)
                }
            }
        }
    }
    
    @MainActor
    func isImageVisible() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let script = """
            (function() {
                const img = document.getElementById('test-image');
                if (!img) return false;
                
                // Check if image has valid src and is not broken
                return img.src && img.src.length > 0 && !img.src.includes('resources/');
            })();
            """
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let isVisible = result as? Bool {
                    continuation.resume(returning: isVisible)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    @MainActor
    private func loadPageWithRequest(_ request: URLRequest) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            @MainActor
            class NavigationDelegate: NSObject, WKNavigationDelegate {
                let continuation: CheckedContinuation<Void, Error>
                weak var helper: iTermBrowserPageSaverTestHelper?
                
                init(continuation: CheckedContinuation<Void, Error>, helper: iTermBrowserPageSaverTestHelper) {
                    self.continuation = continuation
                    self.helper = helper
                    super.init()
                }
                
                func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                    helper?.navigationDelegate = nil
                    continuation.resume()
                }
                
                func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
                    helper?.navigationDelegate = nil
                    continuation.resume(throwing: error)
                }
                
                func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
                    helper?.navigationDelegate = nil
                    continuation.resume(throwing: error)
                }
            }
            
            let delegate = NavigationDelegate(continuation: continuation, helper: self)
            self.navigationDelegate = delegate
            webView.navigationDelegate = delegate
            webView.load(request)
        }
    }
    
    // MARK: - Additional Test Page Creation Methods
    
    @MainActor
    func createAndLoadMinimalPage() async throws {
        let minimalHTML = """
        <!DOCTYPE html>
        <html><head><title>Minimal</title></head><body><h1>Minimal Page</h1></body></html>
        """
        let minimalFile = tempDirectory.appendingPathComponent("minimal.html")
        try minimalHTML.write(to: minimalFile, atomically: true, encoding: .utf8)
        
        let url = URL(string: "http://localhost:\(serverPort)/minimal.html")!
        let request = URLRequest(url: url)
        try await loadPageWithRequest(request)
    }
    
    @MainActor
    func createAndLoadTextOnlyPage() async throws {
        let textOnlyHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Text Only Page</title></head>
        <body>
            <h1>Text Only Page</h1>
            <p>This page has no external resources.</p>
            <div>Just plain text content.</div>
        </body>
        </html>
        """
        let textOnlyFile = tempDirectory.appendingPathComponent("textonly.html")
        try textOnlyHTML.write(to: textOnlyFile, atomically: true, encoding: .utf8)
        
        let url = URL(string: "http://localhost:\(serverPort)/textonly.html")!
        let request = URLRequest(url: url)
        try await loadPageWithRequest(request)
    }
    
    @MainActor
    func createAndLoadPageWithBrokenLinks() async throws {
        let brokenHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Page with Broken Links</title>
            <link rel="stylesheet" href="/nonexistent.css">
        </head>
        <body>
            <h1>Page with Broken Links</h1>
            <img src="/missing-image.png" alt="Missing">
            <script src="/missing-script.js"></script>
        </body>
        </html>
        """
        let brokenFile = tempDirectory.appendingPathComponent("broken.html")
        try brokenHTML.write(to: brokenFile, atomically: true, encoding: .utf8)
        
        let url = URL(string: "http://localhost:\(serverPort)/broken.html")!
        let request = URLRequest(url: url)
        try await loadPageWithRequest(request)
    }
    
    @MainActor
    func createAndLoadComplexPage() async throws {
        createComplexTestPage()
        let url = URL(string: "http://localhost:\(serverPort)/complex.html")!
        let request = URLRequest(url: url)
        try await loadPageWithRequest(request)
    }
    
    @MainActor
    func createAndLoadPageWithComplexCSS() async throws {
        createPageWithComplexCSS()
        let url = URL(string: "http://localhost:\(serverPort)/complex-css.html")!
        let request = URLRequest(url: url)
        try await loadPageWithRequest(request)
    }
    
    @MainActor
    func createAndLoadPageWithNestedCSS() async throws {
        createPageWithNestedCSS()
        let url = URL(string: "http://localhost:\(serverPort)/nested-css.html")!
        let request = URLRequest(url: url)
        try await loadPageWithRequest(request)
    }
    
    // MARK: - Server Control
    
    func stopServer() {
        httpServer?.stop()
    }
    
    func startServer() {
        httpServer = iTermTestHTTPServer(port: serverPort, documentRoot: tempDirectory)
        httpServer.start()
    }
    
    // MARK: - Complex Test Scenarios
    
    func createComplexTestPage() {
        let complexHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Complex Test Page</title>
            <link rel="stylesheet" href="/complex.css">
            <style>
                .inline-style {
                    background-image: url('/inline-bg.png');
                }
            </style>
        </head>
        <body>
            <iframe src="/iframe.html"></iframe>
            <video src="/test-video.mp4" controls></video>
            <audio src="/test-audio.mp3" controls></audio>
            <object data="/test-object.pdf"></object>
        </body>
        </html>
        """
        
        let complexFile = tempDirectory.appendingPathComponent("complex.html")
        try! complexHTML.write(to: complexFile, atomically: true, encoding: .utf8)
        
        // Create iframe content
        let iframeHTML = """
        <!DOCTYPE html>
        <html><body><h1>Iframe Content</h1></body></html>
        """
        let iframeFile = tempDirectory.appendingPathComponent("iframe.html")
        try! iframeHTML.write(to: iframeFile, atomically: true, encoding: .utf8)
        
        // Create complex CSS with multiple URL references
        let complexCSS = """
        @font-face {
            font-family: 'TestFont';
            src: url('/fonts/test-font.woff2') format('woff2');
        }
        
        .complex {
            background: url('/bg1.png'), url('/bg2.png');
            font-family: 'TestFont', sans-serif;
        }
        """
        let complexCSSFile = tempDirectory.appendingPathComponent("complex.css")
        try! complexCSS.write(to: complexCSSFile, atomically: true, encoding: .utf8)
    }
    
    func createPageWithComplexCSS() {
        let pageHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Complex CSS Test</title>
            <link rel="stylesheet" href="/complex-styles.css">
        </head>
        <body>
            <h1 class="title">Complex CSS Test</h1>
            <div class="multiple-bg">Multiple backgrounds</div>
            <div class="font-test">Custom font test</div>
        </body>
        </html>
        """
        
        let pageFile = tempDirectory.appendingPathComponent("complex-css.html")
        try! pageHTML.write(to: pageFile, atomically: true, encoding: .utf8)
        
        let complexCSS = """
        @font-face {
            font-family: 'TestFont';
            src: url('/fonts/test-font.woff2') format('woff2'),
                 url('/fonts/test-font.woff') format('woff');
        }
        
        .title {
            color: #333;
            font-family: 'TestFont', Arial, sans-serif;
        }
        
        .multiple-bg {
            background: url('/bg1.png') no-repeat left,
                       url('/bg2.png') no-repeat right,
                       linear-gradient(to right, #fff, #eee);
            padding: 20px;
        }
        
        .font-test {
            font-family: 'TestFont', sans-serif;
            background-image: url('/pattern.png');
        }
        """
        
        let cssFile = tempDirectory.appendingPathComponent("complex-styles.css")
        try! complexCSS.write(to: cssFile, atomically: true, encoding: .utf8)
        
        // Create some dummy resource files
        createDummyImageFile(name: "bg1.png")
        createDummyImageFile(name: "bg2.png")
        createDummyImageFile(name: "pattern.png")
    }
    
    func createPageWithNestedCSS() {
        let pageHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Nested CSS Test</title>
            <link rel="stylesheet" href="/main.css">
        </head>
        <body>
            <h1>Nested CSS Test</h1>
            <div class="imported-style">Imported styles</div>
            <div class="nested-import">Deeply nested</div>
        </body>
        </html>
        """
        
        let pageFile = tempDirectory.appendingPathComponent("nested-css.html")
        try! pageHTML.write(to: pageFile, atomically: true, encoding: .utf8)
        
        let mainCSS = """
        @import url('/secondary.css');
        
        body {
            font-family: Arial, sans-serif;
            background: url('/main-bg.png');
        }
        
        h1 {
            color: #333;
        }
        """
        
        let mainCSSFile = tempDirectory.appendingPathComponent("main.css")
        try! mainCSS.write(to: mainCSSFile, atomically: true, encoding: .utf8)
        
        let secondaryCSS = """
        @import url('/tertiary.css');
        
        .imported-style {
            color: red;
            background-image: url('/secondary-bg.png');
        }
        """
        
        let secondaryCSSFile = tempDirectory.appendingPathComponent("secondary.css")
        try! secondaryCSS.write(to: secondaryCSSFile, atomically: true, encoding: .utf8)
        
        let tertiaryCSS = """
        .nested-import {
            font-weight: bold;
            background: url('/tertiary-bg.png');
        }
        """
        
        let tertiaryCSSFile = tempDirectory.appendingPathComponent("tertiary.css")
        try! tertiaryCSS.write(to: tertiaryCSSFile, atomically: true, encoding: .utf8)
        
        // Create dummy background images
        createDummyImageFile(name: "main-bg.png")
        createDummyImageFile(name: "secondary-bg.png")
        createDummyImageFile(name: "tertiary-bg.png")
    }
    
    private func createDummyImageFile(name: String) {
        // Create a simple 1x1 pixel image
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
        image.unlockFocus()
        
        let imageData = image.tiffRepresentation!
        let bitmap = NSBitmapImageRep(data: imageData)!
        let pngData = bitmap.representation(using: .png, properties: [:])!
        
        let imageFile = tempDirectory.appendingPathComponent(name)
        try! pngData.write(to: imageFile)
    }
    
    // Expose webView for tests
    var testWebView: iTermBrowserWebView { return webView }
}

// MARK: - Simple HTTP Server for Testing

@available(macOS 11.0, *)
private class iTermTestHTTPServer {
    private let port: Int
    private let documentRoot: URL
    private var server: Process?
    
    init(port: Int, documentRoot: URL) {
        self.port = port
        self.documentRoot = documentRoot
    }
    
    func start() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-m", "http.server", "--bind", "127.0.0.1", String(port)]
        task.currentDirectoryURL = documentRoot

        try! task.run()
        server = task

        // Give the server a moment to start (longer for CI environments)
        Thread.sleep(forTimeInterval: 1.0)
    }
    
    func stop() {
        server?.terminate()
        server?.waitUntilExit()
    }
    
    static func findAvailablePort() throws -> Int {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard result == 0 else {
            throw NSError(domain: "SocketError", code: Int(errno), userInfo: nil)
        }
        
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socket, $0, &addrLen)
            }
        }
        
        guard getResult == 0 else {
            throw NSError(domain: "SocketError", code: Int(errno), userInfo: nil)
        }
        
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

class iTermBrowserPageSaverTestHelperLoggingHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle console.{log,debug,error} messages separately since they come as String
        if let obj = message.body as? [String: String], let logMessage = obj["msg"], let level = obj["level"] {
            switch level {
            case "debug":
                NSFuckingLog("Javascript Console: " + logMessage)
            default:
                NSFuckingLog("%@", "Javascript Console: \(logMessage)")
            }
        }
    }
}
