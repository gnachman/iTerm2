import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class BrowserExtensionErrorHandlingTests: XCTestCase {
    
    var mockBrowserExtension: BrowserExtension!
    var mockLogger: BrowserExtensionLogger!
    var activeManager: BrowserExtensionActiveManager!
    var webView: AsyncWKWebView!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock dependencies
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0",
            description: "Test extension for error handling"
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
        if let webView {
            activeManager.unregisterWebView(webView)
        }
        await activeManager.deactivateAll()
        webView = nil
        activeManager = nil
        mockLogger = nil
        mockBrowserExtension = nil
        try await super.tearDown()
    }
    
    // MARK: - JavaScript-side errors (TypeError, DataCloneError)
    // TODO: These tests require implementing proper argument validation and structured cloning
    // in the generated JavaScript code. For now, focusing on native error handling.
    
    func testSendMessageThrowsTypeErrorForMissingArguments() async throws {
        // SKIP: Requires JavaScript argument validation
        throw XCTSkip("JavaScript argument validation not yet implemented")
    }
    
    func testSendMessageThrowsTypeErrorForNonFunctionCallback() async throws {
        // SKIP: Requires JavaScript argument validation
        throw XCTSkip("JavaScript argument validation not yet implemented")
    }
    
    func testSendMessageThrowsDataCloneErrorForFunction() async throws {
        // SKIP: Requires structured cloning validation
        throw XCTSkip("Structured cloning validation not yet implemented")
    }
    
    func testSendMessageThrowsDataCloneErrorForDOMNode() async throws {
        // SKIP: Requires structured cloning validation
        throw XCTSkip("Structured cloning validation not yet implemented")
    }
    
    // MARK: - Runtime errors (handled by native code)
    
    func testSendMessageWithNoListenerSetsLastError() async throws {
        // Create and setup webview
        webView = AsyncWKWebView()
        
        // Activate extension
        await activeManager.activate(mockBrowserExtension)

        // Register webview (this adds the user scripts)
        try await activeManager.registerWebView(webView, role: .userFacing)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world
        let activeExtension = activeManager.activeExtension(for: mockBrowserExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        // Simple test to check if sendMessage calls the callback at all
        let jsBody = """
            let callbackCalled = false;
            let result = null;
            let lastError = null;
            
            chrome.runtime.sendMessage({test: "data"}, function(response) {
                callbackCalled = true;
                result = response;
                lastError = chrome.runtime.lastError;
            });
            
            // Wait a bit for the callback
            await new Promise(resolve => setTimeout(resolve, 1000));
            
            return {
                callbackCalled: callbackCalled,
                hasLastError: lastError != null,
                lastErrorMessage: lastError?.message,
                response: result
            };
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: contentWorld) as? [String: Any]
        mockLogger.debug("SendMessage test result: \(result ?? [:])")
        
        let callbackCalled = result?["callbackCalled"] as? Bool
        XCTAssertEqual(callbackCalled, true, "Callback should be called")
        let hasLastError = result?["hasLastError"] as? Bool
        XCTAssertEqual(hasLastError, true, "Should have lastError")
        let lastErrorMessage = result?["lastErrorMessage"] as? String
        XCTAssertEqual(lastErrorMessage, 
                      "Could not establish connection. Receiving end does not exist.")
        // response should be null when there's an error
        XCTAssertTrue(result?["response"] is NSNull || result?["response"] == nil)
    }
    
    func testUncheckedLastErrorWarning() async throws {
        // This test would check console warnings for unchecked lastError
        // We'll need to capture console output to verify this
        webView = AsyncWKWebView()
        
        // Activate extension
        await activeManager.activate(mockBrowserExtension)

        // Register webview (this adds the user scripts)
        try await activeManager.registerWebView(webView, role: .userFacing)
        
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
            
            // Call sendMessage but don't check lastError
            chrome.runtime.sendMessage({test: "data"}, function(response) {
                // Intentionally not checking chrome.runtime.lastError
            });
            
            // Wait a bit for async warning
            await new Promise(resolve => setTimeout(resolve, 100));
            return true;
            """
        
        _ = try await webView.callAsyncJavaScript(jsBody, contentWorld: contentWorld)
        
        // Verify warning was logged
        XCTAssertTrue(consoleMessages.contains { $0.contains("Unchecked") && $0.contains("lastError") })
    }
    
    // MARK: - Promise vs Callback behavior
    
    func testSendMessageReturnsPromiseWithoutCallback() async throws {
        // SKIP: Promise-based APIs will be provided by webextension-polyfill
        throw XCTSkip("Promise-based APIs will be handled by webextension-polyfill")
    }
    
    func testSendMessagePromiseRejectsOnError() async throws {
        // SKIP: Promise-based APIs will be provided by webextension-polyfill
        throw XCTSkip("Promise-based APIs will be handled by webextension-polyfill")
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
