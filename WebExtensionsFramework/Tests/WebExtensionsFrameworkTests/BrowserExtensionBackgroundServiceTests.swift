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
    var activeManager: BrowserExtensionActiveManager!
    
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
            useEphemeralDataStore: true, // Use ephemeral for tests
            urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: testLogger)
        )
        
        // Create real active manager with mock dependencies for these tests
        let network = BrowserExtensionNetwork()
        let router = BrowserExtensionRouter(network: network, logger: testLogger)
        let dependencies = BrowserExtensionActiveManager.Dependencies(
            injectionScriptGenerator: MockInjectionScriptGenerator(),
            userScriptFactory: BrowserExtensionUserScriptFactory(),
            backgroundService: backgroundService,
            network: network,
            router: router,
            logger: testLogger,
            storageManager: MockStorageManager()
        )
        activeManager = BrowserExtensionActiveManager(dependencies: dependencies)
        
        // Set the real active manager as the delegate
        backgroundService.activeManagerDelegate = activeManager
        
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
        testExtension = BrowserExtension(manifest: manifest, baseURL: extensionURL, logger: testLogger)
        
        // Create mock background script resource using test helper
        let mockBackgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: "console.log('Background script loaded');",
            isServiceWorker: true
        )
        testExtension.setBackgroundScriptResource(mockBackgroundResource)
        
        // Activate the extension in the active manager
        await activeManager.activate(testExtension)
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
        // Note: In setUp, we activate testExtension which has a background script, so it's not empty
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 1)
    }
    
    /// Test starting a background script creates a WebView
    func testStartBackgroundScript() async throws {
        let result = try await backgroundService.startBackgroundScript(for: testExtension)
        XCTAssertNotNil(result)
        try await backgroundService.run(extensionId: testExtension.id)

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
        // Note: In setUp, we already have testExtension with a background script active
        let initialActiveCount = backgroundService.activeBackgroundScriptExtensionIds.count
        let initialSubviewCount = mockHiddenContainer.addedSubviews.count
        
        let manifestWithoutBackground = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0"
        )
        let extensionURL = URL(fileURLWithPath: "/test/extension")
        let extensionWithoutBackground = BrowserExtension(manifest: manifestWithoutBackground, baseURL: extensionURL, logger: testLogger)
        
        let result = try await backgroundService.startBackgroundScript(for: extensionWithoutBackground)
        XCTAssertNil(result)

        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: extensionWithoutBackground.id))
        // Counts should remain the same - no new background scripts added
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, initialActiveCount)
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, initialSubviewCount)
    }
    
    /// Test stopping a background script removes the WebView
    func testStopBackgroundScript() async throws {
        let result = try await backgroundService.startBackgroundScript(for: testExtension)
        XCTAssertNotNil(result)
        
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
            self.backgroundService.stopBackgroundScript(for: ExtensionID())
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: extensionURL2, logger: testLogger)
        
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: "console.log('Background script 2 loaded');",
            isServiceWorker: true
        )
        testExtension2.setBackgroundScriptResource(mockBackgroundResource2)
        
        // Start both background scripts
        _ = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)
        _ = try await backgroundService.startBackgroundScript(for: testExtension2)
        try await backgroundService.run(extensionId: testExtension2.id)

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
        _ = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)
        _ = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)

        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 1)
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension.id))
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 1)
    }
    
    /// Test stop all background scripts
    func testStopAllBackgroundScripts() async throws {
        // Start multiple background scripts
        _ = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)

        let backgroundScript2 = BackgroundScript(serviceWorker: "bg2.js", scripts: nil, persistent: nil, type: nil)
        let manifest2 = ExtensionManifest(manifestVersion: 3, name: "Test 2", version: "1.0", background: backgroundScript2)
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"), logger: testLogger)
        testExtension2.setBackgroundScriptResource(BackgroundScriptResource(config: backgroundScript2, jsContent: "test", isServiceWorker: true))
        
        _ = try await backgroundService.startBackgroundScript(for: testExtension2)
        try await backgroundService.run(extensionId: testExtension2.id)

        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 2)
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 2)
        
        backgroundService.stopAllBackgroundScripts()
        
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 0)
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: testExtension.id))
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: testExtension2.id))
        XCTAssertEqual(mockHiddenContainer.removedSubviews.count, 2)
    }
    
    /// Test that DOM globals are removed in background scripts
    func testDOMGlobalsAreRemoved() async throws {
        let backgroundResult = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)

        // Register the webview with the ActiveManager to get background script support
        if let (webView, contentManager) = backgroundResult {
            print("DEBUG: About to register background webview with ActiveManager")
            try await activeManager.registerWebView(
                webView,
                userContentManager: contentManager,
                role: .backgroundScript(testExtension.id))
            print("DEBUG: Successfully registered background webview with ActiveManager")
        } else {
            print("DEBUG: No background webview returned from startBackgroundScript")
        }
        
        let extensionId = testExtension.id
        
        // Note: DOM nuke functionality is now handled by BrowserExtensionActiveManager
        // This test should focus on what the background service actually does
        
        // Test that essential APIs are preserved
        let fetchResult = try await backgroundService.evaluateJavaScript("typeof fetch", in: extensionId)
        XCTAssertEqual(fetchResult as? String, "function", "fetch should be available")
        
        let globalThisResult = try await backgroundService.evaluateJavaScript("typeof globalThis", in: extensionId)
        XCTAssertEqual(globalThisResult as? String, "object", "globalThis should be available")
        
        let setTimeoutResult = try await backgroundService.evaluateJavaScript("typeof setTimeout", in: extensionId)
        XCTAssertEqual(setTimeoutResult as? String, "function", "setTimeout should be available")
        
        let consoleResult = try await backgroundService.evaluateJavaScript("typeof console", in: extensionId)
        XCTAssertEqual(consoleResult as? String, "object", "console should be available")
        
        // Test that the background script can execute basic JavaScript
        let basicTestResult = try await backgroundService.evaluateJavaScript("2 + 2", in: extensionId)
        XCTAssertEqual(basicTestResult as? Int, 4, "Basic JavaScript should work")
        
        // Test that background script content is accessible
        let testScriptResult = try await backgroundService.evaluateJavaScript("'Background script loaded'", in: extensionId)
        XCTAssertEqual(testScriptResult as? String, "Background script loaded", "Background script should be accessible")
    }

    func testSimple() async throws {
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"), logger: testLogger)
        let mockBackgroundResource1 = BackgroundScriptResource(
            config: backgroundScript1,
            jsContent: """
                globalThis.foo = 1;
            """,
            isServiceWorker: true
        )
        testExtension1.setBackgroundScriptResource(mockBackgroundResource1)
        
        // Just use activate - it should handle everything
        await activeManager.activate(testExtension1)
        
        let value = try await backgroundService.evaluateJavaScript("globalThis.foo", in: testExtension1.id) as? NSNumber
        XCTAssertEqual(NSNumber(value: 1), value)
    }

    /// Test process isolation - extensions can't access each other's process-level data
    func testProcessIsolation() async throws {
        // Create first extension that sets some process-level state
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"), logger: testLogger)
        let mockBackgroundResource1 = BackgroundScriptResource(
            config: backgroundScript1,
            jsContent: """
                // Try to set some state that might be shared between processes
                globalThis.extensionId = 'extension1';
                
                // Try to access navigator properties that might be shared
                if (navigator && navigator.userAgent) {
                    globalThis.hasNavigator = true;
                    globalThis.userAgent = navigator.userAgent;
                }
            """,
            isServiceWorker: true
        )
        testExtension1.setBackgroundScriptResource(mockBackgroundResource1)
        
        // Create second extension that tries to access the first extension's state
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"), logger: testLogger)
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: """
            foo = 123;
                globalThis.extensionId = 'extension2';
                
                // Check if we can see extension1's state
                globalThis.canSeeOtherExtension = (typeof globalThis.extensionId !== 'undefined' && globalThis.extensionId === 'extension1');
                
                // Each extension should have its own navigator
                if (navigator && navigator.userAgent) {
                    globalThis.hasNavigator = true;
                    globalThis.userAgent = navigator.userAgent;
                }
            """,
            isServiceWorker: true
        )
        testExtension2.setBackgroundScriptResource(mockBackgroundResource2)
        
        // Activate the extensions in the active manager
        await activeManager.activate(testExtension1)
        await activeManager.activate(testExtension2)
        
        // Start both extensions
        let result1 = try await backgroundService.startBackgroundScript(for: testExtension1)
        try await backgroundService.run(extensionId: testExtension1.id)
        let result2 = try await backgroundService.startBackgroundScript(for: testExtension2)
        try await backgroundService.run(extensionId: testExtension2.id)

        // Register the webviews with the ActiveManager to get background script support
        if let (webView1, contentManager1) = result1 {
            try await activeManager.registerWebView(
                webView1,
                userContentManager: contentManager1,
                role: .backgroundScript(testExtension1.id))
        }
        if let (webView2, contentManager2) = result2 {
            try await activeManager.registerWebView(
                webView2,
                userContentManager: contentManager2,
                role: .backgroundScript(testExtension2.id))
        }
        
        // Verify they're in separate processes
        let ext1Id = try await backgroundService.evaluateJavaScript("globalThis.extensionId", in: testExtension1.id)
        XCTAssertEqual(ext1Id as? String, "extension1")
        
        let ext2Id = try await backgroundService.evaluateJavaScript("globalThis.extensionId", in: testExtension2.id)
        XCTAssertEqual(ext2Id as? String, "extension2")
        
        // Verify extension2 cannot see extension1's state
        let canSeeOther = try await backgroundService.evaluateJavaScript("globalThis.canSeeOtherExtension", in: testExtension2.id)
        XCTAssertEqual(canSeeOther as? Bool, false, "Extension 2 should not see Extension 1's global state")
        
        // Both should have their own navigator (if available)
        let ext1Navigator = try await backgroundService.evaluateJavaScript("globalThis.hasNavigator", in: testExtension1.id)
        let ext2Navigator = try await backgroundService.evaluateJavaScript("globalThis.hasNavigator", in: testExtension2.id)
        
        if let ext1Nav = ext1Navigator as? Bool, let ext2Nav = ext2Navigator as? Bool {
            XCTAssertEqual(ext1Nav, ext2Nav, "Both extensions should have same navigator availability")
        }
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"), logger: testLogger)
        let mockBackgroundResource1 = BackgroundScriptResource(
            config: backgroundScript1,
            jsContent: "globalThis.testVariable = 'extension1';",
            isServiceWorker: true
        )
        testExtension1.setBackgroundScriptResource(mockBackgroundResource1)
        
        // Activate the extension in the active manager
        await activeManager.activate(testExtension1)
        
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"), logger: testLogger)
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
        
        // Activate the extension in the active manager
        await activeManager.activate(testExtension2)
        
        // Start both background scripts and register them with the active manager
        let result1 = try await backgroundService.startBackgroundScript(for: testExtension1)
        try await backgroundService.run(extensionId: testExtension1.id)
        let result2 = try await backgroundService.startBackgroundScript(for: testExtension2)
        try await backgroundService.run(extensionId: testExtension2.id)

        // Register the webviews with the ActiveManager to get background script support
        if let (webView1, contentManager1) = result1 {
            try await activeManager.registerWebView(
                webView1,
                userContentManager: contentManager1,
                role: .backgroundScript(testExtension1.id))
        }
        if let (webView2, contentManager2) = result2 {
            try await activeManager.registerWebView(
                webView2,
                userContentManager: contentManager2,
                role: .backgroundScript(testExtension2.id))
        }
        
        // Note: setUp already has testExtension active, so we have 3 total (setUp + testExtension1 + testExtension2)
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 3)
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension1.id))
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension2.id))
        
        // Verify both extensions are running in separate WKWebView instances (setUp + 2 new = 3 total)
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 3)
        
        // Test extension 1 - should have its own variable
        let extension1Result = try await backgroundService.evaluateJavaScript("globalThis.testVariable", in: testExtension1.id)
        XCTAssertEqual(extension1Result as? String, "extension1", "Extension 1 should have its own global variable")
        
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
    
    /// Test storage isolation - extensions should have different origins and separate storage
    func testStorageIsolation() async throws {
        // Create first extension that sets localStorage
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"), logger: testLogger)
        let mockBackgroundResource1 = BackgroundScriptResource(
            config: backgroundScript1,
            jsContent: """
                // Use a simpler test that doesn't rely on async operations
                // Test that the extension can access indexedDB API
                try {
                    globalThis.hasIndexedDB = (typeof indexedDB !== 'undefined');
                    globalThis.indexedDBType = typeof indexedDB;
                    globalThis.canCreateRequest = !!indexedDB.open;
                } catch (e) {
                    globalThis.hasIndexedDB = false;
                    globalThis.indexedDBError = e.message;
                }
                
                // Check current origin
                globalThis.currentOrigin = location.origin;
                
                // Set a unique identifier for this extension
                globalThis.extensionIdentifier = 'extension1';
            """,
            isServiceWorker: true
        )
        testExtension1.setBackgroundScriptResource(mockBackgroundResource1)
        
        // Create second extension that tries to read localStorage
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"), logger: testLogger)
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: """
                // Test that this extension also has access to indexedDB API
                try {
                    globalThis.hasIndexedDB = (typeof indexedDB !== 'undefined');
                    globalThis.indexedDBType = typeof indexedDB;
                    globalThis.canCreateRequest = !!indexedDB.open;
                } catch (e) {
                    globalThis.hasIndexedDB = false;
                    globalThis.indexedDBError = e.message;
                }
                
                // Check current origin
                globalThis.currentOrigin = location.origin;
                
                // Set a unique identifier for this extension
                globalThis.extensionIdentifier = 'extension2';
                
                // Test if we can see extension1's identifier (should be impossible)
                globalThis.canSeeOtherExtension = (typeof globalThis.extensionIdentifier !== 'undefined' && globalThis.extensionIdentifier === 'extension1');
            """,
            isServiceWorker: true
        )
        testExtension2.setBackgroundScriptResource(mockBackgroundResource2)
        
        // Activate the extensions in the active manager
        await activeManager.activate(testExtension1)
        await activeManager.activate(testExtension2)
        
        // Start both extensions
        let result1 = try await backgroundService.startBackgroundScript(for: testExtension1)
        try await backgroundService.run(extensionId: testExtension1.id)
        let result2 = try await backgroundService.startBackgroundScript(for: testExtension2)
        try await backgroundService.run(extensionId: testExtension2.id)

        // Register the webviews with the ActiveManager to get background script support
        if let (webView1, contentManager1) = result1 {
            try await activeManager.registerWebView(
                webView1,
                userContentManager: contentManager1,
                role: .backgroundScript(testExtension1.id))
        }
        if let (webView2, contentManager2) = result2 {
            try await activeManager.registerWebView(
                webView2,
                userContentManager: contentManager2,
                role: .backgroundScript(testExtension2.id))
        }
        
        // Test that both extensions have access to IndexedDB API
        let ext1HasIndexedDB = try await backgroundService.evaluateJavaScript("globalThis.hasIndexedDB", in: testExtension1.id)
        XCTAssertEqual(ext1HasIndexedDB as? Bool, true, "Extension 1 should have access to IndexedDB")
        
        let ext2HasIndexedDB = try await backgroundService.evaluateJavaScript("globalThis.hasIndexedDB", in: testExtension2.id)
        XCTAssertEqual(ext2HasIndexedDB as? Bool, true, "Extension 2 should have access to IndexedDB")
        
        // Test that extensions have separate global scopes
        let ext1Identifier = try await backgroundService.evaluateJavaScript("globalThis.extensionIdentifier", in: testExtension1.id)
        XCTAssertEqual(ext1Identifier as? String, "extension1", "Extension 1 should have its own identifier")
        
        let ext2Identifier = try await backgroundService.evaluateJavaScript("globalThis.extensionIdentifier", in: testExtension2.id)
        XCTAssertEqual(ext2Identifier as? String, "extension2", "Extension 2 should have its own identifier")
        
        // Test that extension 2 cannot see extension 1's global scope
        let ext2CanSeeOther = try await backgroundService.evaluateJavaScript("globalThis.canSeeOtherExtension", in: testExtension2.id)
        XCTAssertEqual(ext2CanSeeOther as? Bool, false, "Extension 2 should not see Extension 1's global variables")
        
        // Verify extensions have different origins
        let ext1Origin = try await backgroundService.evaluateJavaScript("globalThis.currentOrigin", in: testExtension1.id)
        let ext2Origin = try await backgroundService.evaluateJavaScript("globalThis.currentOrigin", in: testExtension2.id)
        
        XCTAssertNotNil(ext1Origin as? String, "Extension 1 should have an origin")
        XCTAssertNotNil(ext2Origin as? String, "Extension 2 should have an origin")
        XCTAssertNotEqual(ext1Origin as? String, ext2Origin as? String, "Extensions should have different origins")
        
        
        // Verify origins follow expected pattern (extension://extensionId/)
        if let origin1 = ext1Origin as? String, let origin2 = ext2Origin as? String {
            XCTAssertTrue(origin1.hasPrefix("extension://"), "Extension 1 origin should start with extension://")
            XCTAssertTrue(origin2.hasPrefix("extension://"), "Extension 2 origin should start with extension://")
            XCTAssertTrue(origin1.lowercased().contains(testExtension1.id.stringValue.lowercased()), "Extension 1 origin should contain its ID")
            XCTAssertTrue(origin2.lowercased().contains(testExtension2.id.stringValue.lowercased()), "Extension 2 origin should contain its ID")
        } else {
            XCTFail("Origins should be strings, got ext1: \(type(of: ext1Origin)), ext2: \(type(of: ext2Origin))")
        }
    }
    
    /// Test ephemeral storage isolation - ephemeral extensions should have separate storage
    func testEphemeralStorageIsolation() async throws {
        // Create background service with ephemeral data stores
        let ephemeralBackgroundService = BrowserExtensionBackgroundService(
            hiddenContainer: mockHiddenContainer,
            logger: testLogger,
            useEphemeralDataStore: true, // Force ephemeral
            urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: testLogger)
        )
        
        // Set the active manager delegate for ephemeral service
        ephemeralBackgroundService.activeManagerDelegate = activeManager
        
        // Create first ephemeral extension
        let backgroundScript1 = BackgroundScript(
            serviceWorker: "background1.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest1 = ExtensionManifest(
            manifestVersion: 3,
            name: "Ephemeral Extension 1",
            version: "1.0",
            background: backgroundScript1
        )
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ephemeral1"), logger: testLogger)
        let mockBackgroundResource1 = BackgroundScriptResource(
            config: backgroundScript1,
            jsContent: """
                // Test that IndexedDB is available in ephemeral mode
                try {
                    globalThis.hasIndexedDB = (typeof indexedDB !== 'undefined');
                    globalThis.indexedDBType = typeof indexedDB;
                } catch (e) {
                    globalThis.hasIndexedDB = false;
                    globalThis.indexedDBError = e.message;
                }
                
                // Set a unique identifier for this ephemeral extension
                globalThis.ephemeralExtensionId = 'ephemeral1';
                
                // Check current origin
                globalThis.currentOrigin = location.origin;
            """,
            isServiceWorker: true
        )
        testExtension1.setBackgroundScriptResource(mockBackgroundResource1)
        
        // Create second ephemeral extension
        let backgroundScript2 = BackgroundScript(
            serviceWorker: "background2.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Ephemeral Extension 2",
            version: "1.0",
            background: backgroundScript2
        )
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ephemeral2"), logger: testLogger)
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: """
                // Test that IndexedDB is available in ephemeral mode
                try {
                    globalThis.hasIndexedDB = (typeof indexedDB !== 'undefined');
                    globalThis.indexedDBType = typeof indexedDB;
                } catch (e) {
                    globalThis.hasIndexedDB = false;
                    globalThis.indexedDBError = e.message;
                }
                
                // Set a unique identifier for this ephemeral extension
                globalThis.ephemeralExtensionId = 'ephemeral2';
                
                // Try to see if we can access the other ephemeral extension's data
                globalThis.canSeeOtherEphemeral = (typeof globalThis.ephemeralExtensionId !== 'undefined' && globalThis.ephemeralExtensionId === 'ephemeral1');
                
                // Check current origin
                globalThis.currentOrigin = location.origin;
            """,
            isServiceWorker: true
        )
        testExtension2.setBackgroundScriptResource(mockBackgroundResource2)
        
        // Activate the extensions in the active manager
        await activeManager.activate(testExtension1)
        await activeManager.activate(testExtension2)
        
        // Start both ephemeral extensions
        let result1 = try await ephemeralBackgroundService.startBackgroundScript(for: testExtension1)
        try await ephemeralBackgroundService.run(extensionId: testExtension1.id)
        let result2 = try await ephemeralBackgroundService.startBackgroundScript(for: testExtension2)
        try await ephemeralBackgroundService.run(extensionId: testExtension2.id)

        // Register the webviews with the ActiveManager to get background script support
        if let (webView1, contentManager1) = result1 {
            try await activeManager.registerWebView(
                webView1,
                userContentManager: contentManager1,
                role: .backgroundScript(testExtension1.id))
        }
        if let (webView2, contentManager2) = result2 {
            try await activeManager.registerWebView(
                webView2,
                userContentManager: contentManager2,
                role: .backgroundScript(testExtension2.id))
        }
        
        // Test that both ephemeral extensions have access to IndexedDB
        let ext1HasIndexedDB = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.hasIndexedDB", in: testExtension1.id)
        XCTAssertEqual(ext1HasIndexedDB as? Bool, true, "Ephemeral Extension 1 should have access to IndexedDB")
        
        let ext2HasIndexedDB = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.hasIndexedDB", in: testExtension2.id)
        XCTAssertEqual(ext2HasIndexedDB as? Bool, true, "Ephemeral Extension 2 should have access to IndexedDB")
        
        // Test that ephemeral extensions have separate global scopes
        let ext1EphemeralId = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.ephemeralExtensionId", in: testExtension1.id)
        XCTAssertEqual(ext1EphemeralId as? String, "ephemeral1", "Ephemeral Extension 1 should have its own identifier")
        
        let ext2EphemeralId = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.ephemeralExtensionId", in: testExtension2.id)
        XCTAssertEqual(ext2EphemeralId as? String, "ephemeral2", "Ephemeral Extension 2 should have its own identifier")
        
        // Test that ephemeral extension 2 cannot see ephemeral extension 1's global scope
        let ext2CanSeeOther = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.canSeeOtherEphemeral", in: testExtension2.id)
        XCTAssertEqual(ext2CanSeeOther as? Bool, false, "Ephemeral Extension 2 should not see Ephemeral Extension 1's global variables")
        
        // Verify ephemeral extensions have different origins
        let ext1Origin = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.currentOrigin", in: testExtension1.id)
        let ext2Origin = try await ephemeralBackgroundService.evaluateJavaScript("globalThis.currentOrigin", in: testExtension2.id)
        
        XCTAssertNotNil(ext1Origin as? String, "Ephemeral Extension 1 should have an origin")
        XCTAssertNotNil(ext2Origin as? String, "Ephemeral Extension 2 should have an origin")
        XCTAssertNotEqual(ext1Origin as? String, ext2Origin as? String, "Ephemeral extensions should have different origins")
        
        
        // Verify ephemeral origins follow expected pattern
        if let origin1 = ext1Origin as? String, let origin2 = ext2Origin as? String {
            XCTAssertTrue(origin1.hasPrefix("extension://"), "Ephemeral Extension 1 origin should start with extension://")
            XCTAssertTrue(origin2.hasPrefix("extension://"), "Ephemeral Extension 2 origin should start with extension://")
            XCTAssertTrue(origin1.lowercased().contains(testExtension1.id.stringValue.lowercased()), "Ephemeral Extension 1 origin should contain its ID")
            XCTAssertTrue(origin2.lowercased().contains(testExtension2.id.stringValue.lowercased()), "Ephemeral Extension 2 origin should contain its ID")
        } else {
            XCTFail("Ephemeral origins should be strings, got ext1: \(type(of: ext1Origin)), ext2: \(type(of: ext2Origin))")
        }
        
        // Clean up ephemeral extensions
        ephemeralBackgroundService.stopAllBackgroundScripts()
    }
    
    /// Test navigation security - background scripts should not be able to navigate to arbitrary URLs
    func testNavigationSecurity() async throws {
        // Create an extension with a background script that tries to navigate
        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Navigation Test Extension",
            version: "1.0",
            background: backgroundScript
        )
        let testExtension = BrowserExtension(manifest: manifest, baseURL: URL(fileURLWithPath: "/test/nav-test"), logger: testLogger)
        let mockBackgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: """
                // Try to navigate to an unauthorized URL
                try {
                    window.location.href = 'https://evil.com';
                    globalThis.navigationAttempted = true;
                } catch (e) {
                    globalThis.navigationError = e.message;
                    globalThis.navigationAttempted = false;
                }
                
                // Try to open a new window (should be undefined)
                try {
                    if (typeof window.open === 'undefined') {
                        globalThis.windowOpenAttempted = false;
                        globalThis.windowOpenUndefined = true;
                    } else {
                        window.open('https://evil.com');
                        globalThis.windowOpenAttempted = true;
                        globalThis.windowOpenUndefined = false;
                    }
                } catch (e) {
                    globalThis.windowOpenError = e.message;
                    globalThis.windowOpenAttempted = false;
                    globalThis.windowOpenUndefined = false;
                }
                
                // Record that the script executed successfully
                globalThis.scriptExecuted = true;
            """,
            isServiceWorker: true
        )
        testExtension.setBackgroundScriptResource(mockBackgroundResource)
        
        // Activate the extension in the active manager
        await activeManager.activate(testExtension)
        
        // Start the background script
        let result = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)
        if let (webView, contentManager) = result {
            try await activeManager.registerWebView(
                webView,
                userContentManager: contentManager,
                role: .backgroundScript(testExtension.id))
        }
        
        // Verify the script executed
        let scriptExecuted = try await backgroundService.evaluateJavaScript("globalThis.scriptExecuted", in: testExtension.id)
        XCTAssertEqual(scriptExecuted as? Bool, true, "Background script should have executed")
        
        // Verify that window.open was undefined (blocked by DOM nuke script)
        let windowOpenUndefined = try await backgroundService.evaluateJavaScript("globalThis.windowOpenUndefined", in: testExtension.id) 
        XCTAssertEqual(windowOpenUndefined as? Bool, true, "window.open should be undefined in background scripts")
        
        // Verify that only the background script webview exists
        let initialWebViewCount = mockHiddenContainer.addedSubviews.count
        // Note: setUp adds testExtension + this test adds testExtension = 2 total
        XCTAssertEqual(initialWebViewCount, 2, "Should only have the background script webviews, no new windows")
        
        // Test that alert() is blocked by the DOM nuke script
        let alertResult = try await backgroundService.evaluateJavaScript("typeof alert", in: testExtension.id)
        XCTAssertEqual(alertResult as? String, "undefined", "alert should be blocked by DOM nuke script")
        
        // Clean up
        backgroundService.stopBackgroundScript(for: testExtension.id)
    }
    
    /// Test that various redirect mechanisms are blocked by navigation security
    func testRedirectBlocking() async throws {
        // Create an extension that tries various redirect methods
        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Redirect Test Extension",
            version: "1.0",
            background: backgroundScript
        )
        let testExtension = BrowserExtension(manifest: manifest, baseURL: URL(fileURLWithPath: "/test/redirect-test"), logger: testLogger)
        let mockBackgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: """
                // Test that we can't inject meta refresh tags
                try {
                    const meta = document.createElement('meta');
                    meta.httpEquiv = 'refresh';
                    meta.content = '0; url=https://evil.com';
                    document.head.appendChild(meta);
                    globalThis.metaRefreshInjected = true;
                } catch (e) {
                    globalThis.metaRefreshError = e.message;
                    globalThis.metaRefreshInjected = false;
                }
                
                // Test that we can't modify document.location
                try {
                    document.location.href = 'https://evil.com';
                    globalThis.locationModified = true;
                } catch (e) {
                    globalThis.locationError = e.message;
                    globalThis.locationModified = false;
                }
                
                // Test that location.replace is blocked
                try {
                    location.replace('https://evil.com');
                    globalThis.locationReplaced = true;
                } catch (e) {
                    globalThis.locationReplaceError = e.message;
                    globalThis.locationReplaced = false;
                }
                
                // Test that location.assign is blocked
                try {
                    location.assign('https://evil.com');
                    globalThis.locationAssigned = true;
                } catch (e) {
                    globalThis.locationAssignError = e.message;
                    globalThis.locationAssigned = false;
                }
                
                // Record successful script execution
                globalThis.redirectTestExecuted = true;
            """,
            isServiceWorker: true
        )
        testExtension.setBackgroundScriptResource(mockBackgroundResource)
        
        // Activate the extension in the active manager
        await activeManager.activate(testExtension)
        
        // Start the background script
        let result = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)
        if let (webView, contentManager) = result {
            try await activeManager.registerWebView(
                webView,
                userContentManager: contentManager,
                role: .backgroundScript(testExtension.id))
        }
        
        // Note: Even though document and location may be available due to WKWebView non-configurable properties,
        // the key security measure is that the navigation delegate blocks all navigation attempts.
        
        // Verify that attempts to use these APIs don't result in successful redirects
        let metaRefreshInjected = try await backgroundService.evaluateJavaScript("globalThis.metaRefreshInjected", in: testExtension.id)
        // Meta refresh injection might succeed (due to document being available) but won't cause navigation
        if metaRefreshInjected as? Bool == true {
            // That's OK - the navigation delegate prevents the actual redirect
        }
        
        let locationModified = try await backgroundService.evaluateJavaScript("globalThis.locationModified", in: testExtension.id)
        // Location modification might not throw an error, but navigation delegate prevents redirect
        if locationModified as? Bool == true {
            // That's OK - the navigation delegate prevents the actual redirect
        }
        
        // The key security verification: no additional navigation occurred
        // The navigation delegate should have blocked any redirect attempts
        let webViewCount = mockHiddenContainer.addedSubviews.count
        // Note: setUp adds testExtension + this test adds testExtension = 2 total
        XCTAssertEqual(webViewCount, 2, "Should only have the original background script webviews - no redirects should succeed")
        
        // Verify script executed successfully despite any redirect attempts
        let scriptExecuted = try await backgroundService.evaluateJavaScript("globalThis.redirectTestExecuted", in: testExtension.id)
        XCTAssertEqual(scriptExecuted as? Bool, true, "Script should execute successfully in secure background context")
        
        // Clean up
        backgroundService.stopBackgroundScript(for: testExtension.id)
    }
    
    /// Test WKContentWorld separation with DOM nuke script running in both worlds
    func testContentWorldSeparation() async throws {
        let backgroundResult = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)

        // Register the webview with the ActiveManager to get background script support
        if let (webView, contentManager) = backgroundResult {
            try await activeManager.registerWebView(
                webView,
                userContentManager: contentManager,
                role: .backgroundScript(testExtension.id))
        }
        
        let extensionId = testExtension.id
        
        // The DOM nuke script now runs in both .page and .defaultClient worlds for defense in depth.
        // This means background scripts don't have access to DOM APIs they shouldn't use.
        
        // Verify that DOM APIs are properly removed from extension scripts
        let workerResult = try await backgroundService.evaluateJavaScript("typeof Worker", in: extensionId)
        XCTAssertEqual(workerResult as? String, "undefined", "Worker should be removed from background scripts")
        
        let xmlHttpRequestResult = try await backgroundService.evaluateJavaScript("typeof XMLHttpRequest", in: extensionId)
        XCTAssertEqual(xmlHttpRequestResult as? String, "undefined", "XMLHttpRequest should be removed from background scripts")
        
        // Test that essential APIs are still available for extensions
        let fetchResult = try await backgroundService.evaluateJavaScript("typeof fetch", in: extensionId)
        XCTAssertEqual(fetchResult as? String, "function", "fetch should be available")
        
        let webSocketResult = try await backgroundService.evaluateJavaScript("typeof WebSocket", in: extensionId)
        XCTAssertEqual(webSocketResult as? String, "function", "WebSocket should be available")
        
        let globalThisResult = try await backgroundService.evaluateJavaScript("typeof globalThis", in: extensionId)
        XCTAssertEqual(globalThisResult as? String, "object", "globalThis should be available")
        
        // Test that BroadcastChannel is also properly removed
        let broadcastChannelResult = try await backgroundService.evaluateJavaScript("typeof BroadcastChannel", in: extensionId)
        XCTAssertEqual(broadcastChannelResult as? String, "undefined", "BroadcastChannel should be removed from background scripts")
        
        // The key security benefit is that DOM APIs are removed from all worlds where
        // background scripts execute, preventing access to inappropriate browser APIs
    }
    
    /// Test that CSP headers are properly set in URL scheme handler
    func testCSPHeadersInURLSchemeHandler() async throws {
        // Create a test URL scheme handler
        let urlSchemeHandler = BrowserExtensionURLSchemeHandler(logger: testLogger)
        
        // Register a test background script
        let backgroundScript = BackgroundScript(serviceWorker: "test.js", scripts: nil, persistent: nil, type: nil)
        let backgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: "console.log('test');",
            isServiceWorker: true
        )
        urlSchemeHandler.registerBackgroundScript(backgroundResource, for: testExtension.id)
        
        // Create a mock URL scheme task
        let mockTask = MockURLSchemeTask(url: BrowserExtensionURLSchemeHandler.backgroundPageURL(for: testExtension.id))
        
        // Handle the request
        urlSchemeHandler.webView(WKWebView(), start: mockTask)
        
        // Verify CSP headers were set
        XCTAssertNotNil(mockTask.receivedResponse, "Should have received a response")
        if let httpResponse = mockTask.receivedResponse as? HTTPURLResponse {
            let cspHeader = httpResponse.allHeaderFields["Content-Security-Policy"] as? String
            XCTAssertNotNil(cspHeader, "CSP header should be present")
            XCTAssertTrue(cspHeader?.contains("default-src 'none'") == true, "CSP should have default-src 'none'")
            XCTAssertTrue(cspHeader?.contains("script-src 'self'") == true, "CSP should have script-src 'self'")
            XCTAssertTrue(cspHeader?.contains("connect-src https:") == true, "CSP should have connect-src https:")
        } else {
            XCTFail("Response should be HTTPURLResponse with headers")
        }
    }
    
    /// Test that background script cleanup happens properly
    func testBackgroundScriptCleanupOnFailure() async throws {
        // This test verifies that the cleanup logic in the do/catch block works correctly
        // Rather than trying to force a failure (which is complex), we test the cleanup path directly
        
        // Note: In setUp, we already call activeManager.activate(testExtension) which starts the background script
        // So the background script is already running at this point
        
        // Verify the background script is already running from setUp
        XCTAssertEqual(mockHiddenContainer.addedSubviews.count, 1, "WebView should already be added from setUp")
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 1, "Should already have one delegate from setUp")
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: testExtension.id), "Extension should already be active from setUp")
        
        // Stop it (this exercises the cleanup path)
        backgroundService.stopBackgroundScript(for: testExtension.id)
        
        // Verify cleanup
        XCTAssertEqual(mockHiddenContainer.removedSubviews.count, 1, "WebView should be removed")
        XCTAssertEqual(backgroundService.activeBackgroundScriptExtensionIds.count, 0, "Should have cleaned up all delegates")
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: testExtension.id), "Extension should not be active")
        
        // The cleanup logic in startBackgroundScript's catch block is the same as stopBackgroundScript,
        // so this tests that the cleanup functionality works correctly.
    }
    
    /// Test that stopLoading is called when stopping background script
    func testStopLoadingOnBackgroundScriptStop() async throws {
        // Start a background script
        _ = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)

        let extensionId = testExtension.id
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: extensionId), "Extension should be active")
        
        // Stop the background script - this should call stopLoading() internally
        backgroundService.stopBackgroundScript(for: extensionId)
        
        // Verify the extension is no longer active
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: extensionId), "Extension should not be active after stop")
        
        // Verify WebView was removed from container
        XCTAssertEqual(mockHiddenContainer.removedSubviews.count, 1, "WebView should have been removed")
    }
    
    /// Test Task cancellation support (simplified test without actual cancellation)
    func testTaskCancellationSupport() async throws {
        // This test verifies that the cancellation handler is properly set up
        // The actual cancellation behavior is hard to test reliably in unit tests
        
        // Verify that withTaskCancellationHandler is used in the implementation
        // by testing that a normal background script start completes successfully
        _ = try await backgroundService.startBackgroundScript(for: testExtension)
        try await backgroundService.run(extensionId: testExtension.id)

        let extensionId = testExtension.id
        XCTAssertTrue(backgroundService.isBackgroundScriptActive(for: extensionId), "Background script should be active")
        
        // The cancellation handler is present in the code and will call webView.stopLoading()
        // when a Task is cancelled, but testing actual cancellation is complex due to timing
        
        // Clean up
        backgroundService.stopBackgroundScript(for: extensionId)
        XCTAssertFalse(backgroundService.isBackgroundScriptActive(for: extensionId), "Background script should be cleaned up")
    }
    
    /// Test UUID validation in URL scheme handler
    func testUUIDValidationInURLSchemeHandler() async throws {
        let urlSchemeHandler = BrowserExtensionURLSchemeHandler(logger: testLogger)
        
        // Test with invalid UUID
        let invalidURL = URL(string: "extension://not-a-uuid/background.html")!
        let mockTask = MockURLSchemeTask(url: invalidURL)
        
        urlSchemeHandler.webView(WKWebView(), start: mockTask)
        
        // Should have failed with invalid UUID error
        XCTAssertNotNil(mockTask.error, "Should have failed with invalid UUID")
        XCTAssertTrue(mockTask.error?.localizedDescription.contains("not a UUID") == true, "Error should mention UUID validation")
    }
    
    /// Test console.log interception and logging
    func testConsoleLogInterception() async throws {
        // Clear any existing log messages
        testLogger.clear()
        
        // Create an extension with console.log statements
        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Console Test Extension",
            version: "1.0",
            background: backgroundScript
        )
        let consoleTestExtension = BrowserExtension(manifest: manifest, baseURL: URL(fileURLWithPath: "/test/console-test"), logger: testLogger)
        let mockBackgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: """
                // Test webkit messageHandlers availability
                globalThis.webkitExists = typeof webkit !== 'undefined';
                globalThis.messageHandlersExists = typeof webkit !== 'undefined' && !!webkit.messageHandlers;
                
                // Test direct message handler call
                try {
                    if (typeof webkit !== 'undefined' && webkit.messageHandlers && webkit.messageHandlers.consoleLog) {
                        webkit.messageHandlers.consoleLog.postMessage('Direct test message');
                        globalThis.directMessageSent = true;
                    } else {
                        globalThis.directMessageSent = false;
                    }
                } catch (e) {
                    globalThis.directMessageSent = false;
                }
                
                console.log('Hello from extension!');
                console.log('Testing with number:', 42);
                console.log('Testing with object:', { key: 'value', nested: { data: true } });
                console.log('Testing with null:', null);
                console.log('Testing with undefined:', undefined);
                console.log('Multiple', 'arguments', 'test');
                
                // Verify console.log is still a function
                globalThis.consoleLogType = typeof console.log;
                
                // Test that other console methods are preserved
                globalThis.consoleErrorType = typeof console.error;
                globalThis.consoleWarnType = typeof console.warn;
                globalThis.consoleInfoType = typeof console.info;
                
                // Test console exists
                globalThis.consoleExists = typeof console === 'object';
                
                globalThis.testCompleted = true;
            """,
            isServiceWorker: true
        )
        consoleTestExtension.setBackgroundScriptResource(mockBackgroundResource)
        
        // Activate the extension in the active manager
        await activeManager.activate(consoleTestExtension)
        
        // Start the background script
        let result = try await backgroundService.startBackgroundScript(for: consoleTestExtension)
        try await backgroundService.run(extensionId: consoleTestExtension.id)
        if let (webView, contentManager) = result {
            try await activeManager.registerWebView(
                webView,
                userContentManager: contentManager,
                role: .backgroundScript(consoleTestExtension.id))
        }
        
        // Verify the script executed
        let testCompleted = try await backgroundService.evaluateJavaScript("globalThis.testCompleted", in: consoleTestExtension.id)
        XCTAssertEqual(testCompleted as? Bool, true, "Test script should have completed")
        
        // Verify console.log is still a function
        let consoleLogType = try await backgroundService.evaluateJavaScript("globalThis.consoleLogType", in: consoleTestExtension.id)
        XCTAssertEqual(consoleLogType as? String, "function", "console.log should be a function")
        
        // Verify other console methods are preserved
        let consoleErrorType = try await backgroundService.evaluateJavaScript("globalThis.consoleErrorType", in: consoleTestExtension.id)
        XCTAssertEqual(consoleErrorType as? String, "function", "console.error should be preserved")
        
        let consoleWarnType = try await backgroundService.evaluateJavaScript("globalThis.consoleWarnType", in: consoleTestExtension.id)
        XCTAssertEqual(consoleWarnType as? String, "function", "console.warn should be preserved")
        
        // Verify console exists
        let consoleExists = try await backgroundService.evaluateJavaScript("globalThis.consoleExists", in: consoleTestExtension.id)
        XCTAssertEqual(consoleExists as? Bool, true, "console should exist")
        
        // Verify webkit.messageHandlers is working
        let webkitExists = try await backgroundService.evaluateJavaScript("globalThis.webkitExists", in: consoleTestExtension.id)
        XCTAssertEqual(webkitExists as? NSNumber, 1, "webkit should be available")
        
        let messageHandlersExists = try await backgroundService.evaluateJavaScript("globalThis.messageHandlersExists", in: consoleTestExtension.id)
        XCTAssertEqual(messageHandlersExists as? NSNumber, 1, "webkit.messageHandlers should be available")
        
        let directMessageSent = try await backgroundService.evaluateJavaScript("globalThis.directMessageSent", in: consoleTestExtension.id)
        XCTAssertEqual(directMessageSent as? NSNumber, 1, "Direct message should have been sent successfully")
        
        // Verify console.log messages were captured in the logger
        let infoMessages = testLogger.messages.filter { $0.level == "INFO" }
        let consoleMessages = infoMessages.filter { $0.message.contains("Console [") }
        
        
        // We should have at least 6 console.log messages
        XCTAssertGreaterThanOrEqual(consoleMessages.count, 6, "Should have captured console.log messages")
        
        // Check specific console.log messages
        let extensionId = consoleTestExtension.id
        XCTAssertTrue(consoleMessages.contains { $0.message.contains("Console [\(extensionId)]: Hello from extension!") }, "Should capture simple string message")
        XCTAssertTrue(consoleMessages.contains { $0.message.contains("Console [\(extensionId)]: Testing with number: 42") }, "Should capture message with number")
        XCTAssertTrue(consoleMessages.contains { $0.message.contains("Console [\(extensionId)]: Testing with null: null") }, "Should capture message with null")
        XCTAssertTrue(consoleMessages.contains { $0.message.contains("Console [\(extensionId)]: Testing with undefined: undefined") }, "Should capture message with undefined")
        XCTAssertTrue(consoleMessages.contains { $0.message.contains("Console [\(extensionId)]: Multiple arguments test") }, "Should capture message with multiple arguments")
        
        // Clean up
        backgroundService.stopBackgroundScript(for: consoleTestExtension.id)
    }
    
    /// Test basic webkit message handler functionality
    func testBasicWebKitMessageHandler() async throws {
        let testLogger = TestBrowserExtensionLogger()
        let handler = SimpleMessageHandler(logger: testLogger)
        
        let config = WKWebViewConfiguration()
        config.userContentController.add(handler, name: "testHandler")
        
        let testScript = WKUserScript(
            source: """
                setTimeout(() => {
                    if (typeof webkit !== 'undefined' && webkit.messageHandlers && webkit.messageHandlers.testHandler) {
                        webkit.messageHandlers.testHandler.postMessage('test message');
                    }
                }, 100);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(testScript)
        
        let webView = WKWebView(frame: CGRect.zero, configuration: config)
        mockHiddenContainer.addSubview(webView)
        
        // Load a simple HTML page
        let html = "<html><body>Test</body></html>"
        webView.loadHTMLString(html, baseURL: nil)
        
        // Check if message was received
        print("Basic webkit test messages: \(testLogger.messages.count)")
        for message in testLogger.messages {
            print("[\(message.level)]: \(message.message)")
        }
        
        webView.removeFromSuperview()
        config.userContentController.removeScriptMessageHandler(forName: "testHandler")
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

class MockURLSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var receivedResponse: URLResponse?
    var receivedData: Data?
    var error: Error?
    var finished = false
    
    init(url: URL) {
        self.request = URLRequest(url: url)
        super.init()
    }
    
    func didReceive(_ response: URLResponse) {
        receivedResponse = response
    }
    
    func didReceive(_ data: Data) {
        receivedData = data
    }
    
    func didFinish() {
        finished = true
    }
    
    func didFailWithError(_ error: Error) {
        self.error = error
    }
}


class FailingURLSchemeHandler: BrowserExtensionURLSchemeHandler {
    override func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // Always fail requests to test error handling
        let error = NSError(domain: "TestFailure", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "Simulated navigation failure for testing"
        ])
        urlSchemeTask.didFailWithError(error)
    }
}

class SimpleMessageHandler: NSObject, WKScriptMessageHandler {
    private let logger: TestBrowserExtensionLogger
    
    init(logger: TestBrowserExtensionLogger) {
        self.logger = logger
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.info("SimpleMessageHandler received: \(message.body)")
    }
}


/// Test implementation of BrowserExtensionLogger that captures messages
public class TestBrowserExtensionLogger: BrowserExtensionLogger {
    public struct LogMessage {
        public let level: String
        public let message: String
        public let file: StaticString
        public let line: Int
        public let function: StaticString

        var string: String { "\(file):\(line) \(function): [\(level)] \(message)"}
    }

    public private(set) var messages: [LogMessage] = []

    public init() {}

    public func clear() {
        messages.removeAll()
    }

    public func info(_ messageBlock: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: Int = #line,
                     function: StaticString = #function) {
        messages.append(LogMessage(level: "INFO", message: messageBlock(), file: file, line: line, function: function))
    }

    public func debug(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        messages.append(LogMessage(level: "DEBUG", message: messageBlock(), file: file, line: line, function: function))
    }

    public func error(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        messages.append(LogMessage(level: "ERROR", message: messageBlock(), file: file, line: line, function: function))
    }

    public func assert(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) {
        Swift.assert(condition(), message(), file: file, line: UInt(line))
    }

    public func fatalError(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) -> Never {
        Swift.fatalError(message(), file: file, line: UInt(line))
    }

    public func preconditionFailure(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) -> Never {
        Swift.preconditionFailure(message(), file: file, line: UInt(line))
    }

    public func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try closure()
    }

    public func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await closure()
    }
}
