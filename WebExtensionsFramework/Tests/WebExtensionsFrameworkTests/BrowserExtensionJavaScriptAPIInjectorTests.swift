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
            injector.injectRuntimeIdAPI(into: freshWebView)
        }

        let jsBody = "return await new Promise(resolve => chrome.runtime.getId(resolve));"

        let expectedId = mockBrowserExtension.id.uuidString
        let actual = try await freshWebView.callAsyncJavaScript(jsBody, contentWorld: .page) as? String
        XCTAssertEqual(actual, expectedId)
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

fileprivate enum NavigationError: Error {
    case loadFailed
}

fileprivate class AsyncWKWebView: WKWebView, WKNavigationDelegate {
    private var continuations = [ObjectIdentifier: CheckedContinuation<Void, Error>]()

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        navigationDelegate = self
    }

    func loadHTMLStringAsync(_ string: String, baseURL: URL?) async throws {
        guard let nav = loadHTMLString(string, baseURL: baseURL) else {
            throw NavigationError.loadFailed
        }
        try await waitFor(nav)
    }

    private func waitFor(_ navigation: WKNavigation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let key = ObjectIdentifier(navigation)
            continuations[key] = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume()
        continuations.removeValue(forKey: key)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume(throwing: error)
        continuations.removeValue(forKey: key)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let navigation = navigation else { return }
        let key = ObjectIdentifier(navigation)
        guard let cont = continuations[key] else { return }
        cont.resume(throwing: error)
        continuations.removeValue(forKey: key)
    }
}
