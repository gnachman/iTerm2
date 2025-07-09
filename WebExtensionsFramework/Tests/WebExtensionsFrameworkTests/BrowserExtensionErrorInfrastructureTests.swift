import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class BrowserExtensionErrorInfrastructureTests: XCTestCase {
    
    var mockBrowserExtension: BrowserExtension!
    var mockLogger: BrowserExtensionLogger!
    var activeManager: BrowserExtensionActiveManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock dependencies
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0",
            description: "Test extension for error infrastructure"
        )
        let baseURL = URL(fileURLWithPath: "/tmp/test-extension")
        mockLogger = createTestLogger()
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseURL: baseURL,
            logger: mockLogger
        )
        
        // Create activeManager
        activeManager = createTestActiveManager(logger: mockLogger)
    }
    
    override func tearDown() async throws {
        await activeManager.deactivateAll()
        activeManager = nil
        mockLogger = nil
        mockBrowserExtension = nil
        try await super.tearDown()
    }
    
    // Test that the error infrastructure functions exist
    func testErrorInfrastructureExists() async throws {
        let webView = AsyncWKWebView()
        
        // Activate extension
        await activeManager.activate(mockBrowserExtension)

        // Register webview (this adds the user scripts)
        try await activeManager.registerWebView(
            webView,
            userContentManager: BrowserExtensionUserContentManager(
                webView: webView,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world
        let activeExtension = activeManager.activeExtension(for: mockBrowserExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        let jsBody = """
            return {
                chromeExists: typeof chrome !== 'undefined',
                chromeRuntimeExists: typeof chrome !== 'undefined' && typeof chrome.runtime !== 'undefined',
                extensionIdExists: typeof chrome !== 'undefined' && typeof chrome.runtime !== 'undefined' && typeof chrome.runtime.id !== 'undefined',
                hasInjectLastError: typeof __ext_injectLastError === 'function',
                hasInvokeCallback: typeof __EXT_invokeCallback__ === 'function'
            };
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: contentWorld)
        
        guard let dictResult = result as? [String: Any] else {
            XCTFail("Result is not a dictionary: \(result ?? "nil")")
            return
        }
        
        // WebKit converts JavaScript booleans to numbers (1/0), so we need to check for both
        func boolValue(for key: String) -> Bool? {
            if let boolVal = dictResult[key] as? Bool {
                return boolVal
            } else if let intVal = dictResult[key] as? Int {
                return intVal != 0
            }
            return nil
        }
        
        XCTAssertEqual(boolValue(for: "chromeExists"), true)
        XCTAssertEqual(boolValue(for: "chromeRuntimeExists"), true)
        XCTAssertEqual(boolValue(for: "extensionIdExists"), true)
        XCTAssertEqual(boolValue(for: "hasInjectLastError"), true)
        XCTAssertEqual(boolValue(for: "hasInvokeCallback"), true)
    }
    
    // Test that the lastError injection function works correctly
    func testLastErrorInjectionMechanism() async throws {
        let webView = AsyncWKWebView()
        
        // Activate extension
        await activeManager.activate(mockBrowserExtension)

        // Register webview (this adds the user scripts)
        try await activeManager.registerWebView(
            webView,
            userContentManager: BrowserExtensionUserContentManager(
                webView: webView,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world
        let activeExtension = activeManager.activeExtension(for: mockBrowserExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        let jsBody = """
            // Test the lastError injection mechanism directly
            let testError = { message: "Test error message" };
            let callbackCalled = false;
            let lastErrorSeen = null;
            
            function testCallback(response) {
                callbackCalled = true;
                lastErrorSeen = chrome.runtime.lastError;
            }
            
            __ext_injectLastError(testError, testCallback, null);
            
            return {
                callbackCalled: callbackCalled,
                lastErrorMessage: lastErrorSeen?.message,
                lastErrorNowUndefined: chrome.runtime.lastError === undefined
            };
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: contentWorld) as? [String: Any]
        let callbackCalled = result?["callbackCalled"] as? Bool
        XCTAssertEqual(callbackCalled, true)
        let lastErrorMessage = result?["lastErrorMessage"] as? String
        XCTAssertEqual(lastErrorMessage, "Test error message")
        let lastErrorNowUndefined = result?["lastErrorNowUndefined"] as? Bool
        XCTAssertEqual(lastErrorNowUndefined, true)
    }
    
    // Test that unchecked lastError generates warning
    func testUncheckedLastErrorWarning() async throws {
        let webView = AsyncWKWebView()
        
        // Activate extension
        await activeManager.activate(mockBrowserExtension)

        // Register webview (this adds the user scripts)
        try await activeManager.registerWebView(
            webView,
            userContentManager: BrowserExtensionUserContentManager(
                webView: webView,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world
        let activeExtension = activeManager.activeExtension(for: mockBrowserExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        var consoleMessages: [String] = []
        webView.configuration.userContentController.add(
            TestConsoleHandler { message in
                consoleMessages.append(message)
            },
            contentWorld: contentWorld,
            name: "testConsole"
        )
        
        let jsBody = """
            // Override console.warn to capture warnings
            window.console.warn = (...args) => {
                window.webkit.messageHandlers.testConsole.postMessage(args.join(' '));
            };
            
            // Test unchecked lastError
            let testError = { message: "Unchecked error" };
            
            function testCallback(response) {
                // Intentionally don't check chrome.runtime.lastError
            }
            
            __ext_injectLastError(testError, testCallback, null);
            
            return true;
            """
        
        _ = try await webView.callAsyncJavaScript(jsBody, contentWorld: contentWorld)
        
        // Verify warning was logged
        XCTAssertTrue(consoleMessages.contains { $0.contains("Unchecked") && $0.contains("lastError") })
    }
    
    // Test that BrowserExtensionError can be encoded to JSON
    func testErrorSerialization() throws {
        let error = BrowserExtensionError.noMessageReceiver
        let errorInfo = BrowserExtensionErrorInfo(from: error)
        
        let jsonData = try JSONEncoder().encode(errorInfo)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString?.contains("Could not establish connection") ?? false)
    }
    
    // MARK: - Helper Methods
    
    private func makeWebViewForTesting(injection: (AsyncWKWebView) -> ()) async throws -> AsyncWKWebView {
        let webView = AsyncWKWebView()
        injection(webView)
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        return webView
    }
}

// MARK: - Test Helpers

private class TestConsoleHandler: NSObject, WKScriptMessageHandler {
    let handler: (String) -> Void
    
    init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let messageString = message.body as? String {
            handler(messageString)
        }
    }
}
