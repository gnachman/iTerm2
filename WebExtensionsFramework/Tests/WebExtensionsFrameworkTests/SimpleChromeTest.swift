import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class SimpleChromeTest: XCTestCase {
    
    func testChromeObjectExists() async throws {
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0",
            description: "Test extension"
        )
        let baseURL = URL(fileURLWithPath: "/tmp/test-extension")
        let mockLogger = createTestLogger()
        let mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseURL: baseURL,
            logger: mockLogger
        )
        
        let activeManager = createTestActiveManager(logger: mockLogger)
        let webView = AsyncWKWebView()
        
        // Activate extension
        await activeManager.activate(mockBrowserExtension)
        
        // Register webview (this adds the user scripts)
        try await activeManager.registerWebView(
            webView,
            userContentManager: BrowserExtensionUserContentManager(
                userContentController: webView.be_configuration.be_userContentController,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world for the extension
        let activeExtension = activeManager.activeExtension(for: mockBrowserExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        let jsBody = """
            return {
                chromeExists: typeof chrome !== 'undefined',
                chromeType: typeof chrome,
                chromeString: String(chrome),
                windowProps: Object.getOwnPropertyNames(window).filter(n => n.includes('chrome'))
            };
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: contentWorld) as? [String: Any]
        
        print("Chrome test result: \(result ?? [:])")
        
        XCTAssertEqual(result?["chromeExists"] as? Bool, true, "chrome object should exist")
        
        // Cleanup
        activeManager.unregisterWebView(webView)
    }
}
