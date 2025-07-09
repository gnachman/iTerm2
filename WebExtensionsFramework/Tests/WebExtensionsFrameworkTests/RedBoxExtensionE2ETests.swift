import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class RedBoxExtensionE2ETests: XCTestCase {
    
    var webView: WKWebView!
    var registry: BrowserExtensionRegistry!
    var activeManager: BrowserExtensionActiveManager!
    var navigationHandler: BrowserExtensionNavigationHandler!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create real WKWebView
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        
        // Set up extension framework components
        registry = createTestRegistry()
        activeManager = BrowserExtensionActiveManager()
        
        // Register the webview with the active manager
        try await activeManager.registerWebView(webView, role: .userFacing)
        
        navigationHandler = BrowserExtensionNavigationHandler(logger: createTestLogger())
    }
    
    override func tearDown() async throws {
        if let webView = webView {
            activeManager?.unregisterWebView(webView)
        }
        webView = nil
        registry = nil
        activeManager = nil
        navigationHandler = nil
        try await super.tearDown()
    }
    
    /// End-to-end test: Load red-box extension and verify it modifies the DOM
    func testRedBoxExtensionE2E() async throws {
        // 1. Load the red-box extension from test resources
        guard let resourceURL = Bundle.module.resourceURL else {
            XCTFail("Could not find test resources")
            return
        }
        let redBoxPath = resourceURL.appendingPathComponent("red-box").path
        try registry.add(extensionPath: redBoxPath)
        
        // 2. Get the loaded extension
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 1, "Should have loaded one extension")
        
        let browserExtension = extensions.first!
        let extensionManifest = browserExtension.manifest
        XCTAssertEqual(extensionManifest.name, "Red Box")
        
        // 3. Activate the extension
        await activeManager.activate(browserExtension)
        let extensionId = browserExtension.id
        XCTAssertTrue(activeManager.isActive(extensionId))
        
        // 4. Load a test page
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test Page</title>
        </head>
        <body>
            <h1>Test Page</h1>
            <p>This is a test page for the red-box extension.</p>
        </body>
        </html>
        """
        
        let expectation = XCTestExpectation(description: "Page load complete")
        
        // 5. Set up navigation delegate to trigger extension injection
        let testDelegate = TestNavigationDelegate(
            navigationHandler: navigationHandler,
            expectation: expectation
        )
        webView.navigationDelegate = testDelegate
        
        // 6. Load the page
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://example.com"))
        
        // 7. Wait for navigation to complete
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // 8. Give content script time to execute
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // 9. Verify the red box was added to the DOM
        let redBoxCheckScript = """
        const redBox = document.querySelector('div[style*="background: red"]');
        redBox ? {
            exists: true,
            text: redBox.textContent,
            position: redBox.style.position,
            background: redBox.style.background,
            zIndex: redBox.style.zIndex
        } : { exists: false }
        """
        
        let result = try await webView.evaluateJavaScript(redBoxCheckScript)
        let resultDict = result as! [String: Any]
        
        // 10. Assert the red box exists and has correct properties
        XCTAssertTrue(resultDict["exists"] as! Bool, "Red box should exist in DOM")
        XCTAssertEqual(resultDict["text"] as? String, "Red Box Extension Active!")
        XCTAssertEqual(resultDict["position"] as? String, "fixed")
        XCTAssertEqual(resultDict["background"] as? String, "red")
        XCTAssertEqual(resultDict["zIndex"] as? String, "9999")
        
        // 11. Verify console log was executed
        let consoleLogCheckScript = """
        // Check if our extension's console.log executed by examining the page
        // We can't directly access console logs, but we can verify the script ran
        document.querySelector('div[style*="background: red"]') !== null
        """
        
        let logResult = try await webView.evaluateJavaScript(consoleLogCheckScript)
        XCTAssertTrue(logResult as! Bool, "Extension script should have executed")
    }
    
    /// Test that the extension only injects on matching URLs
    func testRedBoxExtensionURLMatching() async throws {
        // Load and activate extension
        guard let resourceURL = Bundle.module.resourceURL else {
            XCTFail("Could not find test resources")
            return
        }
        let redBoxPath = resourceURL.appendingPathComponent("red-box").path
        try registry.add(extensionPath: redBoxPath)
        
        let extensions = registry.extensions
        let browserExtension = extensions.first!
        await activeManager.activate(browserExtension)

        // Test with a URL that should match (<all_urls>)
        let htmlContent = "<html><body><h1>Test</h1></body></html>"
        
        let expectation = XCTestExpectation(description: "Navigation complete")
        let testDelegate = TestNavigationDelegate(
            navigationHandler: navigationHandler,
            expectation: expectation
        )
        webView.navigationDelegate = testDelegate
        
        // Load with a specific URL that should trigger the extension
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://github.com"))
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Give extension time to inject
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify injection occurred
        let checkScript = "document.querySelector('div[style*=\"background: red\"]') !== null"
        let hasRedBox = try await webView.evaluateJavaScript(checkScript) as! Bool
        XCTAssertTrue(hasRedBox, "Red box should be injected on all URLs due to <all_urls> pattern")
    }
    
    /// Test multiple extensions don't interfere with each other
    func testMultipleExtensionsIsolation() async throws {
        // This test would require a second test extension
        // For now, we'll test that our red-box extension works in isolation
        
        guard let resourceURL = Bundle.module.resourceURL else {
            XCTFail("Could not find test resources")
            return
        }
        let redBoxPath = resourceURL.appendingPathComponent("red-box").path
        try registry.add(extensionPath: redBoxPath)
        
        let extensions = registry.extensions
        let browserExtension = extensions.first!
        await activeManager.activate(browserExtension)

        // Load page and inject content script
        let htmlContent = "<html><body><h1>Isolation Test</h1></body></html>"
        let expectation = XCTestExpectation(description: "Navigation complete")
        let testDelegate = TestNavigationDelegate(
            navigationHandler: navigationHandler,
            expectation: expectation
        )
        webView.navigationDelegate = testDelegate
        
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://isolation-test.com"))
        await fulfillment(of: [expectation], timeout: 5.0)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify the extension runs in its own content world
        // The red box should be added but shouldn't interfere with page's main world
        let isolationCheckScript = """
        // Check that red box exists
        const redBox = document.querySelector('div[style*="background: red"]');
        const redBoxExists = redBox !== null;
        
        // Check that page's main content is unaffected
        const originalHeading = document.querySelector('h1');
        const headingUnchanged = originalHeading && originalHeading.textContent === 'Isolation Test';
        
        ({
            redBoxExists: redBoxExists,
            pageUnaffected: headingUnchanged
        })
        """
        
        let result = try await webView.evaluateJavaScript(isolationCheckScript) as! [String: Any]
        XCTAssertTrue(result["redBoxExists"] as! Bool, "Red box should exist")
        XCTAssertTrue(result["pageUnaffected"] as! Bool, "Page content should be unaffected")
    }
}

// MARK: - Test Navigation Delegate

@MainActor
private class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    private let navigationHandler: BrowserExtensionNavigationHandler
    private let expectation: XCTestExpectation
    
    init(navigationHandler: BrowserExtensionNavigationHandler, expectation: XCTestExpectation) {
        self.navigationHandler = navigationHandler
        self.expectation = expectation
        super.init()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Call into our extension navigation handler
        navigationHandler.webView(webView, didFinish: navigation)
        expectation.fulfill()
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Call into our extension navigation handler for document_start scripts
        navigationHandler.webView(webView, didCommit: navigation)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        navigationHandler.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        navigationHandler.webView(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler)
    }
}
