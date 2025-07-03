import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class ContentWorldIsolationIntegrationTests: XCTestCase {
    
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
        registry = BrowserExtensionRegistry()
        activeManager = BrowserExtensionActiveManager()
        
        // Register the webview with the active manager
        try activeManager.registerWebView(webView)
        
        navigationHandler = BrowserExtensionNavigationHandler()
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
    
    /// Integration test: Verify that multiple extensions run in isolated content worlds
    func testMultipleExtensionsContentWorldIsolation() async throws {
        // 1. Load both test extensions
        guard let resourceURL = Bundle.module.resourceURL else {
            XCTFail("Could not find test resources")
            return
        }
        
        let redBoxPath = resourceURL.appendingPathComponent("red-box").path
        let blueCirclePath = resourceURL.appendingPathComponent("blue-circle").path
        
        try registry.add(extensionPath: redBoxPath)
        try registry.add(extensionPath: blueCirclePath)
        
        // 2. Verify both extensions loaded
        let extensions = registry.extensions
        XCTAssertEqual(extensions.count, 2, "Should have loaded two extensions")
        
        var redBoxExtension: BrowserExtension?
        var blueCircleExtension: BrowserExtension?
        
        for ext in extensions {
            let name = ext.manifest.name
            if name == "Red Box" {
                redBoxExtension = ext
            } else if name == "Blue Circle" {
                blueCircleExtension = ext
            }
        }
        
        XCTAssertNotNil(redBoxExtension, "Red Box extension should be loaded")
        XCTAssertNotNil(blueCircleExtension, "Blue Circle extension should be loaded")
        
        // 3. Activate both extensions
        try activeManager.activate(redBoxExtension!)
        try activeManager.activate(blueCircleExtension!)
        
        let redBoxId = redBoxExtension!.id
        let blueCircleId = blueCircleExtension!.id
        
        XCTAssertTrue(activeManager.isActive(redBoxId))
        XCTAssertTrue(activeManager.isActive(blueCircleId))
        
        // 4. Verify they have different content worlds
        let redBoxActiveExtension = activeManager.activeExtension(for: redBoxId)!
        let blueCircleActiveExtension = activeManager.activeExtension(for: blueCircleId)!
        
        XCTAssertEqual(redBoxActiveExtension.contentWorld.name, "Extension-\(redBoxId)")
        XCTAssertEqual(blueCircleActiveExtension.contentWorld.name, "Extension-\(blueCircleId)")
        XCTAssertNotEqual(redBoxActiveExtension.contentWorld.name, blueCircleActiveExtension.contentWorld.name)
        
        // 5. Load a test page
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Content World Isolation Test</title>
        </head>
        <body>
            <h1>Content World Isolation Test</h1>
            <p>Testing that extensions run in separate isolated content worlds.</p>
        </body>
        </html>
        """
        
        let expectation = XCTestExpectation(description: "Page load complete")
        let testDelegate = TestNavigationDelegate(
            navigationHandler: navigationHandler,
            expectation: expectation
        )
        webView.navigationDelegate = testDelegate
        
        // 6. Load the page
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://isolation-test.com"))
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // 7. Give content scripts time to execute
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // 8. Verify both extensions modified the DOM in the main world
        let domCheckScript = """
        ({
            redBoxExists: document.querySelector('div[style*="background: red"]') !== null,
            blueCircleExists: document.querySelector('#blue-circle-extension') !== null,
            redBoxText: document.querySelector('div[style*="background: red"]')?.textContent || null,
            blueCircleText: document.querySelector('#blue-circle-extension')?.textContent || null
        })
        """
        
        let domResult = try await webView.evaluateJavaScript(domCheckScript) as! [String: Any]
        XCTAssertTrue(domResult["redBoxExists"] as! Bool, "Red box should exist")
        XCTAssertTrue(domResult["blueCircleExists"] as! Bool, "Blue circle should exist")
        XCTAssertEqual(domResult["redBoxText"] as? String, "Red Box Extension Active!")
        XCTAssertEqual(domResult["blueCircleText"] as? String, "🔵")
        
        // 9. Test isolation: Check that extension variables are NOT accessible in main world
        let mainWorldIsolationScript = """
        ({
            redBoxVariableExists: typeof window.redBoxExtensionActive !== 'undefined',
            blueCircleVariableExists: typeof window.blueCircleExtensionActive !== 'undefined',
            extensionTypeExists: typeof window.extensionType !== 'undefined'
        })
        """
        
        let mainWorldResult = try await webView.evaluateJavaScript(mainWorldIsolationScript) as! [String: Any]
        XCTAssertFalse(mainWorldResult["redBoxVariableExists"] as! Bool, "Red box extension variables should NOT be accessible in main world")
        XCTAssertFalse(mainWorldResult["blueCircleVariableExists"] as! Bool, "Blue circle extension variables should NOT be accessible in main world")
        XCTAssertFalse(mainWorldResult["extensionTypeExists"] as! Bool, "Extension type variable should NOT be accessible in main world")
        
        // 10. Test that each extension can access its own variables in its content world
        let redBoxWorldScript = """
        ({
            hasOwnVariable: typeof window.redBoxExtensionActive !== 'undefined' && window.redBoxExtensionActive === true,
            extensionType: window.extensionType || null,
            cannotAccessBlueCircle: typeof window.blueCircleExtensionActive === 'undefined'
        })
        """
        
        let redBoxWorldResult = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(redBoxWorldScript, in: nil, in: redBoxActiveExtension.contentWorld) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as! [String: Any])
                case .failure(_):
                    continuation.resume(returning: [:])
                }
            }
        }
        XCTAssertTrue(redBoxWorldResult["hasOwnVariable"] as! Bool, "Red box extension should access its own variables")
        XCTAssertEqual(redBoxWorldResult["extensionType"] as? String, "red-box")
        XCTAssertTrue(redBoxWorldResult["cannotAccessBlueCircle"] as! Bool, "Red box extension should NOT access blue circle variables")
        
        let blueCircleWorldScript = """
        ({
            hasOwnVariable: typeof window.blueCircleExtensionActive !== 'undefined' && window.blueCircleExtensionActive === true,
            extensionType: window.extensionType || null,
            cannotAccessRedBox: typeof window.redBoxExtensionActive === 'undefined'
        })
        """
        
        let blueCircleWorldResult = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(blueCircleWorldScript, in: nil, in: blueCircleActiveExtension.contentWorld) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as! [String: Any])
                case .failure(_):
                    continuation.resume(returning: [:])
                }
            }
        }
        XCTAssertTrue(blueCircleWorldResult["hasOwnVariable"] as! Bool, "Blue circle extension should access its own variables")
        XCTAssertEqual(blueCircleWorldResult["extensionType"] as? String, "blue-circle")
        XCTAssertTrue(blueCircleWorldResult["cannotAccessRedBox"] as! Bool, "Blue circle extension should NOT access red box variables")
    }
    
    /// Test that deactivating one extension doesn't affect another extension's content world
    func testExtensionDeactivationIsolation() async throws {
        // Load and activate both extensions
        guard let resourceURL = Bundle.module.resourceURL else {
            XCTFail("Could not find test resources")
            return
        }
        
        let redBoxPath = resourceURL.appendingPathComponent("red-box").path
        let blueCirclePath = resourceURL.appendingPathComponent("blue-circle").path
        
        try registry.add(extensionPath: redBoxPath)
        try registry.add(extensionPath: blueCirclePath)
        
        let extensions = registry.extensions
        var redBoxExtension: BrowserExtension?
        var blueCircleExtension: BrowserExtension?
        
        for ext in extensions {
            let name = ext.manifest.name
            if name == "Red Box" {
                redBoxExtension = ext
            } else if name == "Blue Circle" {
                blueCircleExtension = ext
            }
        }
        
        try activeManager.activate(redBoxExtension!)
        try activeManager.activate(blueCircleExtension!)
        
        let redBoxId = redBoxExtension!.id
        let blueCircleId = blueCircleExtension!.id
        
        // Load page and let both extensions inject
        let htmlContent = "<html><body><h1>Deactivation Test</h1></body></html>"
        let expectation = XCTestExpectation(description: "Navigation complete")
        let testDelegate = TestNavigationDelegate(
            navigationHandler: navigationHandler,
            expectation: expectation
        )
        webView.navigationDelegate = testDelegate
        
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://deactivation-test.com"))
        await fulfillment(of: [expectation], timeout: 5.0)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify both are active initially
        let initialCheck = try await webView.evaluateJavaScript("""
        ({
            redBox: document.querySelector('div[style*="background: red"]') !== null,
            blueCircle: document.querySelector('#blue-circle-extension') !== null
        })
        """) as! [String: Any]
        
        XCTAssertTrue(initialCheck["redBox"] as! Bool)
        XCTAssertTrue(initialCheck["blueCircle"] as! Bool)
        
        // Deactivate red box extension
        activeManager.deactivate(redBoxId)
        XCTAssertFalse(activeManager.isActive(redBoxId))
        XCTAssertTrue(activeManager.isActive(blueCircleId))
        
        // Reload page to see effect of deactivation
        let reloadExpectation = XCTestExpectation(description: "Page reload complete")
        let reloadDelegate = TestNavigationDelegate(
            navigationHandler: navigationHandler,
            expectation: reloadExpectation
        )
        webView.navigationDelegate = reloadDelegate
        
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://deactivation-test.com"))
        await fulfillment(of: [reloadExpectation], timeout: 5.0)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify only blue circle extension is still active
        let afterDeactivationCheck = try await webView.evaluateJavaScript("""
        ({
            redBox: document.querySelector('div[style*="background: red"]') !== null,
            blueCircle: document.querySelector('#blue-circle-extension') !== null
        })
        """) as! [String: Any]
        
        XCTAssertFalse(afterDeactivationCheck["redBox"] as! Bool, "Red box should no longer appear after deactivation")
        XCTAssertTrue(afterDeactivationCheck["blueCircle"] as! Bool, "Blue circle should still appear")
        
        // Verify blue circle extension can still access its content world
        let blueCircleActiveExtension = activeManager.activeExtension(for: blueCircleId)!
        let blueCircleStillWorking = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("""
            typeof window.blueCircleExtensionActive !== 'undefined' && window.blueCircleExtensionActive === true
            """, in: nil, in: blueCircleActiveExtension.contentWorld) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as! Bool)
                case .failure(_):
                    continuation.resume(returning: false)
                }
            }
        }
        
        XCTAssertTrue(blueCircleStillWorking, "Blue circle extension should still work in its content world")
    }
}

// MARK: - Test Navigation Delegate (reuse from E2E tests)

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
        navigationHandler.webView(webView, didFinish: navigation)
        expectation.fulfill()
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        navigationHandler.webView(webView, didCommit: navigation)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        navigationHandler.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        navigationHandler.webView(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler)
    }
}