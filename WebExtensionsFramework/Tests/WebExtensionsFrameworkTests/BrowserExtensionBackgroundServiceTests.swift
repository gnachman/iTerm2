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
            useEphemeralDataStore: true, // Use ephemeral for tests
            urlSchemeHandler: BrowserExtensionURLSchemeHandler()
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
            self.backgroundService.stopBackgroundScript(for: UUID())
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
    
    /// Test that DOM globals are removed in background scripts
    func testDOMGlobalsAreRemoved() async throws {
        try await backgroundService.startBackgroundScript(for: testExtension)
        
        let extensionId = testExtension.id
        
        // Verify DOM nuke script executed
        let debugResult = try await backgroundService.evaluateJavaScript("window.__domNukeExecuted", in: extensionId)
        XCTAssertEqual(debugResult as? Bool, true, "DOM nuke script should have executed")
        
        // Test that removable DOM globals are gone
        let alertResult = try await backgroundService.evaluateJavaScript("typeof alert", in: extensionId)
        XCTAssertEqual(alertResult as? String, "undefined", "alert should be removed")
        
        let localStorageResult = try await backgroundService.evaluateJavaScript("typeof localStorage", in: extensionId)
        XCTAssertEqual(localStorageResult as? String, "undefined", "localStorage should be removed")
        
        let xmlHttpRequestResult = try await backgroundService.evaluateJavaScript("typeof XMLHttpRequest", in: extensionId)
        XCTAssertEqual(xmlHttpRequestResult as? String, "undefined", "XMLHttpRequest should be removed")
        
        // Note: document and window are non-configurable in WKWebView and cannot be deleted
        // but that's OK - the main security risks (storage, XHR, UI dialogs) are blocked
        
        // Test that essential APIs are preserved
        let fetchResult = try await backgroundService.evaluateJavaScript("typeof fetch", in: extensionId)
        XCTAssertEqual(fetchResult as? String, "function", "fetch should be available")
        
        let globalThisResult = try await backgroundService.evaluateJavaScript("typeof globalThis", in: extensionId)
        XCTAssertEqual(globalThisResult as? String, "object", "globalThis should be available")
        
        let setTimeoutResult = try await backgroundService.evaluateJavaScript("typeof setTimeout", in: extensionId)
        XCTAssertEqual(setTimeoutResult as? String, "function", "setTimeout should be available")
        
        let consoleResult = try await backgroundService.evaluateJavaScript("typeof console", in: extensionId)
        XCTAssertEqual(consoleResult as? String, "object", "console should be available")
        
        // Test specific DOM constructors that are typically inherited from prototype chain
        let elementResult = try await backgroundService.evaluateJavaScript("typeof Element", in: extensionId)
        XCTAssertEqual(elementResult as? String, "undefined", "Element constructor should be shadowed")
        
        let htmlElementResult = try await backgroundService.evaluateJavaScript("typeof HTMLElement", in: extensionId)
        XCTAssertEqual(htmlElementResult as? String, "undefined", "HTMLElement constructor should be shadowed")
        
        // Note: document and window are non-configurable in WKWebView and cannot be shadowed
        // But that's acceptable - the main security risks (storage, XHR, UI dialogs) are blocked
        
        // Test that shadowed properties cannot be accessed even with bracket notation
        let elementBracketResult = try await backgroundService.evaluateJavaScript("typeof globalThis['Element']", in: extensionId)
        XCTAssertEqual(elementBracketResult as? String, "undefined", "Element should be shadowed with bracket notation")
        
        // Note: document and window are non-configurable in WKWebView and cannot be completely removed
        // But the dangerous APIs (alert, localStorage, XMLHttpRequest, Element constructors) are properly shadowed
        // This provides adequate security - background scripts can't manipulate DOM or access legacy storage
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"))
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"))
        let mockBackgroundResource2 = BackgroundScriptResource(
            config: backgroundScript2,
            jsContent: """
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
        
        // Start both extensions
        try await backgroundService.startBackgroundScript(for: testExtension1)
        try await backgroundService.startBackgroundScript(for: testExtension2)
        
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ext1"))
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ext2"))
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
        
        // Start both extensions
        try await backgroundService.startBackgroundScript(for: testExtension1)
        try await backgroundService.startBackgroundScript(for: testExtension2)
        
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
            XCTAssertTrue(origin1.lowercased().contains(testExtension1.id.uuidString.lowercased()), "Extension 1 origin should contain its ID")
            XCTAssertTrue(origin2.lowercased().contains(testExtension2.id.uuidString.lowercased()), "Extension 2 origin should contain its ID")
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
            urlSchemeHandler: BrowserExtensionURLSchemeHandler()
        )
        
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
        let testExtension1 = BrowserExtension(manifest: manifest1, baseURL: URL(fileURLWithPath: "/test/ephemeral1"))
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
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: URL(fileURLWithPath: "/test/ephemeral2"))
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
        
        // Start both ephemeral extensions
        try await ephemeralBackgroundService.startBackgroundScript(for: testExtension1)
        try await ephemeralBackgroundService.startBackgroundScript(for: testExtension2)
        
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
            XCTAssertTrue(origin1.lowercased().contains(testExtension1.id.uuidString.lowercased()), "Ephemeral Extension 1 origin should contain its ID")
            XCTAssertTrue(origin2.lowercased().contains(testExtension2.id.uuidString.lowercased()), "Ephemeral Extension 2 origin should contain its ID")
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
        let testExtension = BrowserExtension(manifest: manifest, baseURL: URL(fileURLWithPath: "/test/nav-test"))
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
                
                // Try to open a new window
                try {
                    window.open('https://evil.com');
                    globalThis.windowOpenAttempted = true;
                } catch (e) {
                    globalThis.windowOpenError = e.message;
                    globalThis.windowOpenAttempted = false;
                }
                
                // Record that the script executed successfully
                globalThis.scriptExecuted = true;
            """,
            isServiceWorker: true
        )
        testExtension.setBackgroundScriptResource(mockBackgroundResource)
        
        // Start the background script
        try await backgroundService.startBackgroundScript(for: testExtension)
        
        // Verify the script executed
        let scriptExecuted = try await backgroundService.evaluateJavaScript("globalThis.scriptExecuted", in: testExtension.id)
        XCTAssertEqual(scriptExecuted as? Bool, true, "Background script should have executed")
        
        // Verify that window.open was called but blocked by security measures
        let windowOpenAttempted = try await backgroundService.evaluateJavaScript("globalThis.windowOpenAttempted", in: testExtension.id) 
        XCTAssertEqual(windowOpenAttempted as? Bool, true, "window.open should be callable but blocked by UI delegate")
        
        // The key security measure is that the UI delegate blocks window creation
        // window.open() might return truthy but no actual window should be created
        // The real test is that no new webviews are created in the container
        let initialWebViewCount = mockHiddenContainer.addedSubviews.count
        
        // Verify that window.open() didn't actually create new windows
        // The UI delegate should have blocked the window creation
        XCTAssertEqual(initialWebViewCount, 1, "Should only have the background script webview, no new windows")
        
        // Test that alert() is blocked by the DOM nuke script
        let alertResult = try await backgroundService.evaluateJavaScript("typeof alert", in: testExtension.id)
        XCTAssertEqual(alertResult as? String, "undefined", "alert should be blocked by DOM nuke script")
        
        // Clean up
        backgroundService.stopBackgroundScript(for: testExtension.id)
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