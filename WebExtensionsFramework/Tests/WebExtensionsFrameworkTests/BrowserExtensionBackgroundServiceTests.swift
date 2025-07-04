import XCTest
import WebKit
import AppKit
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionBackgroundServiceTests: XCTestCase {
    
    var backgroundService: BrowserExtensionBackgroundServiceProtocol!
    var testExtension: BrowserExtension!
    var mockHiddenContainer: MockNSView!
    var testLogger: TestBrowserExtensionLogger!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock hidden container
        mockHiddenContainer = MockNSView()
        
        // Create test logger
        testLogger = TestBrowserExtensionLogger()
        
        // Create background service with mock container, logger, and ephemeral flag
        backgroundService = BrowserExtensionBackgroundService(
            hiddenContainer: mockHiddenContainer,
            logger: testLogger,
            useEphemeralDataStore: true // Use ephemeral for tests
        )
        
        // Create test extension with background script
        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0",
            description: "Test extension with background script",
            contentScripts: nil,
            background: backgroundScript
        )
        
        let extensionURL = URL(fileURLWithPath: "/test/extension")
        testExtension = BrowserExtension(manifest: manifest, baseURL: extensionURL)
        
        // Create mock background script resource using test helper
        let mockBackgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: "console.log('Background script loaded');",
            isServiceWorker: true
        )
        testExtension.setBackgroundScriptResource(mockBackgroundResource)
    }
    
    override func tearDown() async throws {
        backgroundService = nil
        testExtension = nil
        mockHiddenContainer = nil
        testLogger = nil
        try await super.tearDown()
    }
    
    /// Test background service initialization
    func testBackgroundServiceInitialization() {
        XCTAssertNotNil(backgroundService)
        XCTAssertTrue(backgroundService.activeBackgroundScriptExtensionIds.isEmpty)
    }
    
    /// Test starting a background script creates a WebView
    func testStartBackgroundScript() async throws {
        try await backgroundService.startBackgroundScript(for: testExtension)
        
        let extensionId = testExtension.id
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: extensionId))
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 1)
        XCTAssertTrue(backgroundService.activeBackgroundScriptExtensionIds.contains(extensionId))
        
        // Verify WebView was added to hidden container
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 1)
        XCTAssertTrue(mockHiddenContainer.addedSubviews[0] is WKWebView)
    }
    
    /// Test starting background script for extension without background script does nothing
    func testStartBackgroundScriptWithoutBackgroundScript() async throws {
        let manifestWithoutBackground = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0"
        )
        let extensionURL = URL(fileURLWithPath: "/test/extension")
        let extensionWithoutBackground = BrowserExtension(manifest: manifestWithoutBackground, baseURL: extensionURL)
        
        try await backgroundService.startBackgroundScript(for: extensionWithoutBackground)
        
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: extensionWithoutBackground.id))
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 0)
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 0)
    }
    
    /// Test stopping a background script removes the WebView
    func testStopBackgroundScript() async throws {
        try await backgroundService.startBackgroundScript(for: testExtension)
        
        let extensionId = testExtension.id
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: extensionId))
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 1)
        
        backgroundService.stopBackgroundScript(for: extensionId)
        
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: extensionId))
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 0)
        
        // Verify WebView was removed from hidden container
        XCTAssertEqual(mockHiddenContainer.removedSubviews.count, 1)
    }
    
    /// Test stopping non-existent background script doesn't crash
    func testStopNonExistentBackgroundScript() {
        XCTAssertNoThrow {
            self.backgroundService.stopBackgroundScript(for: "non-existent-extension")
        }
    }
    
    /// Test multiple background scripts can run simultaneously
    func testMultipleBackgroundScripts() async throws {
        // Create second test extension
        let backgroundScript2 = BackgroundScript(
            serviceWorker: "background2.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension 2",
            version: "1.0",
            description: "Second test extension",
            contentScripts: nil,
            background: backgroundScript2
        )
        
        let extensionURL2 = URL(fileURLWithPath: "/test/extension2")
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: extensionURL2)
        
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: "console.log('Background script 2 loaded');",
            isServiceWorker: true
        )
        testExtension2.setBackgroundScriptResource(mockBackgroundResource2)
        
        // Start both background scripts
        try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.startBackgroundScript(for: testExtension2)
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 2)
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension.id))
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension2.id))
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 2)
        
        // Stop first extension
        backgroundService.stopBackgroundScript(for: testExtension.id)
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 1)
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: testExtension.id))
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension2.id))
        XCTAssertEqual(mockHiddenContainer.removedSubviews.count, 1)
    }
    
    /// Test starting same background script twice doesn't create duplicates
    func testStartSameBackgroundScriptTwice() async throws {
        try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.startBackgroundScript(for: testExtension)
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 1)
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension.id))
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 1)
    }
    
    /// Test stop all background scripts
    func testStopAllBackgroundScripts() async throws {
        // Start multiple background scripts
        try await backgroundService.startBackgroundScript(for: testExtension)
        
        let backgroundScript2 = BackgroundScript(serviceWorker: "bg2.js", scripts: nil, persistent: nil, type: nil)
        let manifest2 = ExtensionManifest(manifestVersion: 3, name: "Test 2", version: "1.0", background: backgroundScript2)
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"))
        testExtension2.setBackgroundScriptResource(BackgroundScriptResource(config: backgroundScript2, jsContent: "test", isServiceWorker: true))
        
        try await backgroundService.startBackgroundScript(for: testExtension2)
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 2)
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 2)
        
        backgroundService.stopAllBackgroundScripts()
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 0)
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: testExtension.id))
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: testExtension2.id))
        XCTAssertEqual(mockHiddenContainer.removedSubviews.count, 2)
    }
    
    /// Test background script isolation - global variables should not leak between extensions
    func testBackgroundScriptIsolation() async throws {
        // Create first extension with script that sets a global variable
        let backgroundScript1 = BackgroundScript(
            serviceWorker: "background1.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest1 = ExtensionManifest(
            manifestVersion: 3,
            name: "Extension 1",
            version: "1.0",
            background: backgroundScript1
        )
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"))
        let mockBackgroundResource1 = BackgroundScriptResource(
            config: backgroundScript1,
            jsContent: "globalThis.testVariable = 'extension1';",
            isServiceWorker: true
        )
        testExtension1.setBackgroundScriptResource(mockBackgroundResource1)
        
        // Create second extension with script that tries to read the global variable
        let backgroundScript2 = BackgroundScript(
            serviceWorker: "background2.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Extension 2", 
            version: "1.0",
            background: backgroundScript2
        )
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"))
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: """
                // Try to access the global variable from extension1
                globalThis.otherExtensionVariable = globalThis.testVariable;
                globalThis.isolationTest = (globalThis.testVariable === undefined ? true : false);
                globalThis.testVariable2 = 'extension2';
            """,
            isServiceWorker: true
        )
        testExtension2.setBackgroundScriptResource(mockBackgroundResource2)
        
        // Start both background scripts
        try await backgroundService.startBackgroundScript(for: testExtension1)
        try await backgroundService.startBackgroundScript(for: testExtension2)
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 2)
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension1.id))
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension2.id))
        
        // Verify both extensions are running in separate WKWebView instances
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 2)
        
        // Test extension 1 - should have its own variable
        let extension1Result = try await backgroundService.evaluateJavaScript("globalThis.testVariable", in: testExtension1.id)
        XCTAssertEqual(extension1Result as? String, "extension1", "Extension 1 should have its own global variable")
        
        // Small wait to ensure scripts have executed (necessary for reliable test execution)
        _ = try? await backgroundService.evaluateJavaScript("1", in: testExtension2.id)
        
        // Test extension 2 - verify it has its own variable
        let extension2VarResult = try await backgroundService.evaluateJavaScript("globalThis.testVariable2", in: testExtension2.id)
        XCTAssertEqual(extension2VarResult as? String, "extension2", "Extension 2 should have its own global variable")
        
        // Test extension 2 - should NOT see extension 1's variable  
        let extension2IsolationResult = try await backgroundService.evaluateJavaScript("globalThis.isolationTest", in: testExtension2.id)
        // JavaScript boolean true becomes NSNumber(1) in Swift
        if let numberResult = extension2IsolationResult as? NSNumber {
            XCTAssertTrue(numberResult.boolValue, "Extension 2 should not be able to access Extension 1's global variables")
        } else {
            XCTFail("Expected isolation test to return a boolean value, got: \(String(describing: extension2IsolationResult))")
        }
    }
}

// MARK: - Mock Objects

class MockNSView: NSView {
    var addedSubviews: [NSView] = []
    var removedSubviews: [NSView] = []
    
    override func addSubview(_ view: NSView) {
        addedSubviews.append(view)
        super.addSubview(view)
    }
    
    override func willRemoveSubview(_ subview: NSView) {
        removedSubviews.append(subview)
        super.willRemoveSubview(subview)
    }
}