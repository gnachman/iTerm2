import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class BrowserExtensionJavaScriptAPIInjectorTests: XCTestCase {
    
    var mockBrowserExtension: BrowserExtension!
    var mockLogger: BrowserExtensionLogger!
    var injector: BrowserExtensionJavaScriptAPIInjector!

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
    }
    
    override func tearDown() async throws {
        injector = nil
        mockLogger = nil
        mockBrowserExtension = nil
        try await super.tearDown()
    }
    
    func testRuntimeIdEndToEnd() async throws {
        let freshWebView = try await makeWebViewForTesting() { freshWebView in
            let network = BrowserExtensionNetwork()
            network.add(webView: freshWebView, browserExtension: mockBrowserExtension)
            let router = BrowserExtensionRouter(network: network, logger: mockLogger)
            let context = BrowserExtensionContext(
                logger: mockLogger,
                router: router,
                webView: freshWebView,
                browserExtension: mockBrowserExtension,
                tab: nil,
                frameId: nil
            )
            let dispatcher = BrowserExtensionDispatcher(context: context)
            injector.injectRuntimeAPIs(into: freshWebView,
                                       dispatcher: dispatcher,
                                       router: router,
                                       network: network)
        }

        let jsBody = "return chrome.runtime.id;"

        let expectedId = mockBrowserExtension.id.uuidString
        let actual = try await freshWebView.callAsyncJavaScript(jsBody, contentWorld: WKContentWorld.page) as? String
        XCTAssertEqual(actual, expectedId)
    }
    
    func testRuntimeGetPlatformInfoEndToEnd() async throws {
        let freshWebView = try await makeWebViewForTesting() { freshWebView in
            let network = BrowserExtensionNetwork()
            network.add(webView: freshWebView, browserExtension: mockBrowserExtension)
            let router = BrowserExtensionRouter(network: network, logger: mockLogger)
            let context = BrowserExtensionContext(
                logger: mockLogger,
                router: router,
                webView: freshWebView,
                browserExtension: mockBrowserExtension,
                tab: nil,
                frameId: nil
            )
            let dispatcher = BrowserExtensionDispatcher(context: context)
            injector.injectRuntimeAPIs(into: freshWebView,
                                       dispatcher: dispatcher,
                                       router: router,
                                       network: network)
        }

        let jsBody = "return await new Promise(resolve => chrome.runtime.getPlatformInfo(resolve));"

        let actual = try await freshWebView.callAsyncJavaScript(jsBody, contentWorld: WKContentWorld.page) as? [String: String]
        
        XCTAssertEqual(actual?["os"], "mac")
        XCTAssertNotNil(actual?["arch"])
        XCTAssertTrue(actual?["arch"] == "x86-64" || actual?["arch"] == "arm64")
        let arch = actual?["arch"]
        let naclArch = actual?["nacl_arch"]
        XCTAssertEqual(arch, naclArch) // nacl_arch should match arch
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

