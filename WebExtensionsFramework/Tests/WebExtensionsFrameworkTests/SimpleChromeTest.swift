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
        
        let injector = BrowserExtensionJavaScriptAPIInjector(
            browserExtension: mockBrowserExtension,
            logger: mockLogger
        )
        
        let webView = AsyncWKWebView()
        injector.injectRuntimeAPIs(into: webView)
        
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        let jsBody = """
            return {
                chromeExists: typeof chrome !== 'undefined',
                chromeType: typeof chrome,
                chromeString: String(chrome),
                windowProps: Object.getOwnPropertyNames(window).filter(n => n.includes('chrome'))
            };
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: .page) as? [String: Any]
        
        print("Chrome test result: \(result ?? [:])")
        
        XCTAssertEqual(result?["chromeExists"] as? Bool, true, "chrome object should exist")
    }
}