import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class BrowserExtensionJavaScriptAPIInjectorTests: XCTestCase {
    
    var mockBrowserExtension: BrowserExtension!
    var mockLogger: BrowserExtensionLogger!
    var injector: BrowserExtensionJavaScriptAPIInjector!
    var webView: WKWebView!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock dependencies
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0",
            description: "Test extension for API injection"
        )
        let baseURL = URL(fileURLWithPath: "/tmp/test-extension")
        mockLogger = createTestLogger()
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseURL: baseURL,
            logger: mockLogger
        )
        
        // Create injector
        injector = BrowserExtensionJavaScriptAPIInjector(
            browserExtension: mockBrowserExtension,
            logger: mockLogger
        )
        
        // Create webview
        webView = WKWebView()
    }
    
    override func tearDown() async throws {
        webView = nil
        injector = nil
        mockLogger = nil
        mockBrowserExtension = nil
        try await super.tearDown()
    }
    
    func testRuntimeIdEndToEnd() async throws {
        let freshWebView = try await makeWebViewForTesting() { freshWebView in
            injector.injectRuntimeAPIs(into: freshWebView)
        }

        let jsBody = "return chrome.runtime.id;"

        let expectedId = mockBrowserExtension.id.uuidString
        let actual = try await freshWebView.callAsyncJavaScript(jsBody, contentWorld: .page) as? String
        XCTAssertEqual(actual, expectedId)
    }
    
    func testRuntimeGetPlatformInfoEndToEnd() async throws {
        let freshWebView = try await makeWebViewForTesting() { freshWebView in
            injector.injectRuntimeAPIs(into: freshWebView)
        }

        let jsBody = "return await new Promise(resolve => chrome.runtime.getPlatformInfo(resolve));"

        let actual = try await freshWebView.callAsyncJavaScript(jsBody, contentWorld: .page) as? [String: String]
        
        XCTAssertEqual(actual?["os"], "mac")
        XCTAssertNotNil(actual?["arch"])
        XCTAssertTrue(actual?["arch"] == "x86-64" || actual?["arch"] == "arm64")
        XCTAssertEqual(actual?["arch"], actual?["nacl_arch"]) // nacl_arch should match arch
    }
    
    // MARK: - Helper Methods
    
    private func makeWebViewForTesting(injection: (AsyncWKWebView) -> ()) async throws -> AsyncWKWebView {
        let freshWebView = AsyncWKWebView()
        freshWebView.configuration.userContentController.add(ConsoleLogHandler(),
                                                             name: "consoleLog")
        injection(freshWebView)
        let html = "<html><body>Test</body></html>"
        try await freshWebView.loadHTMLStringAsync(html, baseURL: nil)
        let jsBody = """
            console.log = (...args) => {
                window.webkit.messageHandlers.consoleLog
                    .postMessage(args.join(' '))
            };
            true;
            """
        try await freshWebView.evaluateJavaScript(jsBody)
        return freshWebView
    }
}

// MARK: - Console Log Handler

fileprivate class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("JS: \(message.body)")
    }
}

