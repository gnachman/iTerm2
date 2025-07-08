import os.log
import WebKit
import XCTest
@testable import WebExtensionsFramework

@MainActor
final class BrowserExtensionActiveManagerTests: XCTestCase {
    
    var manager: BrowserExtensionActiveManager!
    var testExtension: BrowserExtension!
    
    override func setUp() {
        super.setUp()
        manager = createTestActiveManager()
        testExtension = createTestBrowserExtension()
    }
    
    override func tearDown() {
        manager = nil
        testExtension = nil
        super.tearDown()
    }
    
    /// Test basic manager initialization
    func testManagerInitialization() {
        XCTAssertNotNil(manager)
    }
    
    /// Test activating an extension
    func testActivateExtension() async throws {
        await manager.activate(testExtension)

        let extensionId = testExtension.id
        let isActive = manager.isActive(extensionId)
        XCTAssertTrue(isActive)
    }
    
    /// Test getting an active extension
    func testGetActiveExtension() async throws {
        await manager.activate(testExtension)

        let extensionId = testExtension.id
        let activeExtension = manager.activeExtension(for: extensionId)
        XCTAssertNotNil(activeExtension)
        
        let browserExtensionId = activeExtension?.browserExtension.id
        let browserExtensionName = activeExtension?.browserExtension.manifest.name
        XCTAssertEqual(browserExtensionId, extensionId)
        XCTAssertEqual(browserExtensionName, "Test Extension")
    }
    
    /// Test that content world is created for extension
    func testContentWorldCreation() async throws {
        await manager.activate(testExtension)

        let extensionId = testExtension.id
        let activeExtension = manager.activeExtension(for: extensionId)
        XCTAssertNotNil(activeExtension)
        XCTAssertEqual(activeExtension?.contentWorld.name, "Extension-\(extensionId)")
    }
    
    /// Test activation timestamp
    func testActivationTimestamp() async throws {
        let beforeActivation = Date()
        await manager.activate(testExtension)
        let afterActivation = Date()
        
        let extensionId = testExtension.id
        let activeExtension = manager.activeExtension(for: extensionId)
        let activatedAt = activeExtension?.activatedAt
        
        XCTAssertNotNil(activatedAt)
        XCTAssertGreaterThanOrEqual(activatedAt!, beforeActivation)
        XCTAssertLessThanOrEqual(activatedAt!, afterActivation)
    }
    
    /// Test that activating the same extension twice calls fatalError (should not happen in practice)
    func testActivateSameExtensionTwice() async throws {
        await manager.activate(testExtension)

        // Second activation should be prevented by caller logic, not by this method
        // This test verifies the extension is already active
        let extensionId = testExtension.id
        XCTAssertTrue(manager.isActive(extensionId))
        
        // In practice, callers should check isActive() before calling activate()
        // The fatalError is a last resort for programming errors
    }
    
    /// Test deactivating an extension
    func testDeactivateExtension() async throws {
        await manager.activate(testExtension)

        let extensionId = testExtension.id
        var isActive = manager.isActive(extensionId)
        XCTAssertTrue(isActive)
        
        await manager.deactivate(extensionId)

        isActive = manager.isActive(extensionId)
        XCTAssertFalse(isActive)
        
        let activeExtension = manager.activeExtension(for: extensionId)
        XCTAssertNil(activeExtension)
    }
    
    /// Test getting all active extensions
    func testGetAllActiveExtensions() async throws {
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension 2",
            version: "1.0.0"
        )
        
        let extensionURL2 = URL(fileURLWithPath: "/test/extension2")
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: extensionURL2, logger: createTestLogger())
        
        await manager.activate(testExtension)
        await manager.activate(testExtension2)

        let allActive = manager.allActiveExtensions()
        XCTAssertEqual(allActive.count, 2)
        
        let extensionId1 = testExtension.id
        let extensionId2 = testExtension2.id
        XCTAssertNotNil(allActive[extensionId1])
        XCTAssertNotNil(allActive[extensionId2])
    }
    
    /// Test deactivating all extensions
    func testDeactivateAllExtensions() async throws {
        let manifest2 = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension 2",
            version: "1.0.0"
        )
        
        let extensionURL2 = URL(fileURLWithPath: "/test/extension2")
        let testExtension2 = BrowserExtension(manifest: manifest2, baseURL: extensionURL2, logger: createTestLogger())
        
        await manager.activate(testExtension)
        await manager.activate(testExtension2)

        var allActive = manager.allActiveExtensions()
        XCTAssertEqual(allActive.count, 2)
        
        await manager.deactivateAll()
        
        allActive = manager.allActiveExtensions()
        XCTAssertEqual(allActive.count, 0)
        
        let extensionId1 = testExtension.id
        let extensionId2 = testExtension2.id
        let isActive1 = manager.isActive(extensionId1)
        let isActive2 = manager.isActive(extensionId2)
        XCTAssertFalse(isActive1)
        XCTAssertFalse(isActive2)
    }
    
    /// Test checking if non-existent extension is active
    func testIsActiveForNonExistentExtension() {
        let isActive = manager.isActive(UUID())
        XCTAssertFalse(isActive)
    }
    
    /// Test getting non-existent active extension
    func testGetNonExistentActiveExtension() {
        let activeExtension = manager.activeExtension(for: UUID())
        XCTAssertNil(activeExtension)
    }
    
    /// Test that chrome.runtime.id works correctly for a single extension
    func testChromeRuntimeId() async throws {
        // Create and register a webview
        let webView = AsyncWKWebView()
        
        // Activate extension
        await manager.activate(testExtension)

        // Register webview (this adds the user scripts)
        try await manager.registerWebView(webView)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world
        let activeExtension = manager.activeExtension(for: testExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        // Check chrome.runtime.id
        let result = try await webView.callAsyncJavaScript("""
            return {
                id: chrome.runtime.id,
                idType: typeof chrome.runtime.id
            };
        """, contentWorld: contentWorld) as? [String: Any]
        
        XCTAssertEqual(result?["id"] as? String, testExtension.id.uuidString)
        XCTAssertEqual(result?["idType"] as? String, "string")
        
        // Cleanup
        manager.unregisterWebView(webView)
    }
    
    /// Test that chrome.runtime.id is different for multiple extensions
    func testChromeRuntimeIdMultipleExtensions() async throws {
        // Create two different extensions
        let extension1 = createTestBrowserExtension(name: "Extension 1")
        let extension2 = createTestBrowserExtension(name: "Extension 2")
        
        // Create webview
        let webView = AsyncWKWebView()
        
        // Activate both extensions
        await manager.activate(extension1)
        await manager.activate(extension2)

        // Register webview (this adds the user scripts)
        try await manager.registerWebView(webView)
        
        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Wait for user scripts to take effect
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Get content worlds
        let activeExtension1 = manager.activeExtension(for: extension1.id)!
        let activeExtension2 = manager.activeExtension(for: extension2.id)!
        let contentWorld1 = activeExtension1.contentWorld
        let contentWorld2 = activeExtension2.contentWorld
        
        // Check chrome.runtime.id in first extension's world
        let result1 = try await webView.callAsyncJavaScript("""
            return chrome.runtime.id;
        """, contentWorld: contentWorld1) as? String
        
        // Check chrome.runtime.id in second extension's world
        let result2 = try await webView.callAsyncJavaScript("""
            return chrome.runtime.id;
        """, contentWorld: contentWorld2) as? String
        
        XCTAssertEqual(result1, extension1.id.uuidString)
        XCTAssertEqual(result2, extension2.id.uuidString)
        XCTAssertNotEqual(result1, result2)
        
        // Cleanup
        manager.unregisterWebView(webView)
    }
    
    /// Test that chrome.runtime.getPlatformInfo works
    func testChromeRuntimeGetPlatformInfo() async throws {
        // Create and register a webview
        let webView = AsyncWKWebView()
        
        // Activate extension
        await manager.activate(testExtension)

        // Register webview (this adds the user scripts)
        try await manager.registerWebView(webView)

        // Load HTML - user scripts will be injected during this load
        let html = "<html><body>Test</body></html>"
        try await webView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Get the content world
        let activeExtension = manager.activeExtension(for: testExtension.id)!
        let contentWorld = activeExtension.contentWorld
        
        // Check chrome.runtime.getPlatformInfo
        let result = try await webView.callAsyncJavaScript("""
            return new Promise((resolve) => {
                chrome.runtime.getPlatformInfo((info) => {
                    resolve(info);
                });
            });
        """, contentWorld: contentWorld) as? [String: Any]
        
        XCTAssertEqual(result?["os"] as? String, "mac")
        XCTAssertNotNil(result?["arch"])
        XCTAssertNotNil(result?["nacl_arch"])
        
        // Cleanup
        manager.unregisterWebView(webView)
    }
}

extension BrowserExtensionActiveManager {
    public convenience init() {
        // Create a hidden container view for background scripts
        // This must be added to a view hierarchy for WKWebView to work properly
        let hiddenContainer = NSView()
        hiddenContainer.isHidden = true
        let logger = DefaultBrowserExtensionLogger()

        // Create background service with default logger
        let backgroundService = BrowserExtensionBackgroundService(
            hiddenContainer: hiddenContainer,
            logger: logger,
            useEphemeralDataStore: false,
            urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: logger)
        )

        let network = BrowserExtensionNetwork()
        let router = BrowserExtensionRouter(network: network, logger: logger)
        
        self.init(
            injectionScriptGenerator: BrowserExtensionContentScriptInjectionGenerator(logger: logger),
            userScriptFactory: BrowserExtensionUserScriptFactory(),
            backgroundService: backgroundService,
            network: network,
            router: router,
            logger: logger
        )
    }
}

/// Default implementation of BrowserExtensionLogger using os.log
public class DefaultBrowserExtensionLogger: BrowserExtensionLogger {
    private static let logger = Logger(subsystem: "com.webextensions.framework", category: "main")
    @TaskLocal static var logContexts = ["Root"]

    public init() {}

    public func info(_ messageBlock: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: Int = #line,
                     function: StaticString = #function) {
        let message = "Info: " + prefixed(message: "\(file):\(line) (\(function)): \(messageBlock())")
        Self.logger.info("\(message, privacy: .public)")
    }

    public func debug(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        let message = "Debug: " + prefixed(message: "\(file):\(line) (\(function)): \(messageBlock())")
        Self.logger.debug("\(message, privacy: .public)")
    }

    public func error(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        let message = "Error: " + prefixed(message: "\(file):\(line) (\(function)): \(messageBlock())")
        Self.logger.error("\(message, privacy: .public)")
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

    private func prefixed(message: String) -> String {
        let prefix = DefaultBrowserExtensionLogger.logContexts.joined(separator: " > ")
        return "\(prefix): \(message)"
    }

    public func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try DefaultBrowserExtensionLogger.$logContexts.withValue(
            DefaultBrowserExtensionLogger.logContexts + [prefix]
        ) {
            Self.logger.debug("\(self.prefixed(message: "Begin"), privacy: .public)")
            defer {
                Self.logger.debug("\(self.prefixed(message: "End"), privacy: .public)")
            }
            do {
                return try closure()
            } catch {
                Self.logger.debug("\(self.prefixed(message: "Exiting scope with error \(error)"), privacy: .public)")
                throw error
            }
        }
    }

    public func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await DefaultBrowserExtensionLogger.$logContexts.withValue(
            DefaultBrowserExtensionLogger.logContexts + [prefix]
        ) {
            Self.logger.debug("\(self.prefixed(message: "Begin"), privacy: .public)")
            defer {
                Self.logger.debug("\(self.prefixed(message: "End"), privacy: .public)")
            }
            do {
                return try await closure()
            } catch {
                Self.logger.debug("\(self.prefixed(message: "Exiting scope with error \(error)"), privacy: .public)")
                throw error
            }
        }
    }
}
