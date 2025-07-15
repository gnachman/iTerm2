import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
final class StorageIntegrationTests: XCTestCase {
    
    var webView: AsyncWKWebView!
    var registry: BrowserExtensionRegistry!
    var activeManager: BrowserExtensionActiveManager!
    var backgroundService: BrowserExtensionBackgroundService!
    var storageProvider: MockBrowserExtensionStorageProvider!
    var storageManager: BrowserExtensionStorageManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create storage infrastructure
        let logger = createTestLogger(verbose: false)
        storageProvider = MockBrowserExtensionStorageProvider()
        storageManager = BrowserExtensionStorageManager(logger: logger)
        storageManager.storageProvider = storageProvider
        
        // Create background service
        let hiddenContainer = NSView()
        backgroundService = BrowserExtensionBackgroundService(
            hiddenContainer: hiddenContainer,
            logger: logger,
            useEphemeralDataStore: true,
            urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: logger)
        )
        
        // Create dependencies with our storage manager
        let network = BrowserExtensionNetwork()
        let router = BrowserExtensionRouter(network: network, logger: logger)
        let dependencies = BrowserExtensionActiveManager.Dependencies(
            injectionScriptGenerator: BrowserExtensionContentScriptInjectionGenerator(logger: logger),
            userScriptFactory: BrowserExtensionUserScriptFactory(),
            backgroundService: backgroundService,
            network: network,
            router: router,
            logger: logger,
            storageManager: storageManager
        )
        
        // Get base directory for extensions
        guard let resourceURL = Bundle.module.resourceURL else {
            fatalError("Could not find test resources")
        }
        
        registry = createTestRegistry(baseDirectory: resourceURL, logger: logger)
        activeManager = BrowserExtensionActiveManager(dependencies: dependencies)
        
        // Create AsyncWKWebView
        let config = WKWebViewConfiguration()
        webView = AsyncWKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
    }
    
    override func tearDown() async throws {
        if let webView = webView {
            activeManager?.unregisterWebView(webView)
        }
        await activeManager?.deactivateAll()
        webView = nil
        registry = nil
        activeManager = nil
        backgroundService = nil
        storageProvider = nil
        storageManager = nil
        try await super.tearDown()
    }
    
    func testStorageAPIIntegration() async throws {
        // Get the storage-demo extension from bundle resources
        guard let resourceURL = Bundle.module.resourceURL else {
            XCTFail("Could not find test resources")
            return
        }
        
        let storageDemoPath = resourceURL.appendingPathComponent("storage-demo").path
        try registry.add(extensionLocation: URL(fileURLWithPath: storageDemoPath).lastPathComponent)
        
        // Get the extension from the registry
        let browserExtension = registry.extensions.first!
        
        // Activate the extension
        await activeManager.activate(browserExtension)
        
        // Register the webview (this will start background and content scripts)
        try await activeManager.registerWebView(
            webView,
            userContentManager: BrowserExtensionUserContentManager(
                userContentController: webView.be_configuration.be_userContentController,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)
        
        // Load a test page in the webview
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Storage Test</title></head>
        <body>
            <h1>Storage Integration Test</h1>
            <div id="status">Ready for testing</div>
            <div id="data">No data</div>
        </body>
        </html>
        """
        
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Test 1: Execute JavaScript in background script to verify it can write to storage
        // This will be queued after the background script loads
        _ = try await backgroundService.evaluateJavaScript("""
            chrome.storage.local.set({
                'integration_test': {
                    message: 'Hello from integration test!',
                    timestamp: Date.now(),
                    source: 'background'
                }
            });
        """, in: browserExtension.id)
        
        // Test 2: Verify background script data was stored by polling the storage provider
        var integrationTestFound = false
        for _ in 0..<50 { // Wait up to 5 seconds
            let storedData = try! await storageProvider.get(keys: nil, area: .local, extensionId: browserExtension.id)
            if storedData["integration_test"] != nil {
                integrationTestFound = true
                break
            }
            // Brief pause to allow async operations to complete
            await Task.yield()
        }
        
        XCTAssertTrue(integrationTestFound, "Background script should have written test data")
        
        // Verify both pieces of data are present
        let finalStoredData = try! await storageProvider.get(keys: nil, area: .local, extensionId: browserExtension.id)
        XCTAssertNotNil(finalStoredData["integration_test"], "Background script should have written test data")
        XCTAssertNotNil(finalStoredData["background_data"], "Background script should have written initial data")
    }
}