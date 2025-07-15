import XCTest
import Foundation
import WebKit
@testable import WebExtensionsFramework
import BrowserExtensionShared

/// Test infrastructure for creating and testing web extensions programmatically
@MainActor
class ExtensionTestingInfrastructure {
    
    /// Context types for testing different execution environments
    enum TestContextType {
        case contentScript
        case backgroundScript
        case untrustedWebPage
    }
    
    /// A test extension configuration
    struct TestExtension {
        let id: ExtensionID
        let manifest: [String: Any]
        let contentScripts: [String: String] // filename -> script content
        let backgroundScripts: [String: String] // filename -> script content
        let webPages: [String: String] // filename -> HTML content
        
        init(id: ExtensionID = ExtensionID(), 
             permissions: [String] = [],
             contentScripts: [String: String] = [:],
             backgroundScripts: [String: String] = [:],
             webPages: [String: String] = [:]) {
            self.id = id
            self.contentScripts = contentScripts
            self.backgroundScripts = backgroundScripts
            self.webPages = webPages
            
            var manifest: [String: Any] = [
                "manifest_version": 3,
                "name": "Test Extension",
                "version": "1.0.0"
            ]
            
            if !permissions.isEmpty {
                manifest["permissions"] = permissions
            }
            
            if !contentScripts.isEmpty {
                let contentScriptConfigs = contentScripts.keys.map { filename in
                    [
                        "matches": ["<all_urls>"],
                        "js": [filename]
                    ]
                }
                manifest["content_scripts"] = contentScriptConfigs
            }
            
            if !backgroundScripts.isEmpty {
                manifest["background"] = [
                    "service_worker": Array(backgroundScripts.keys).first!
                ]
            }
            
            self.manifest = manifest
        }
    }
    
    /// JavaScript assertion that can be passed to Swift for XCTest verification
    struct JavaScriptAssertion {
        let description: String
        let passed: Bool
        let actualValue: String?
        let expectedValue: String?
        
        init(description: String, passed: Bool, actualValue: String? = nil, expectedValue: String? = nil) {
            self.description = description
            self.passed = passed
            self.actualValue = actualValue
            self.expectedValue = expectedValue
        }
    }
    struct JavaScriptReached {
        let name: String
    }

    /// Test runner for executing extension tests
    @MainActor
    class TestRunner {
        private let storageProvider: MockBrowserExtensionStorageProvider
        private let storageManager: BrowserExtensionStorageManager
        private var activeManager: BrowserExtensionActiveManager
        private let logger: BrowserExtensionLogger
        private var webViews: [TestContextType: AsyncWKWebView] = [:]
        private var extensions: [ExtensionID: TestExtension] = [:]
        private var activatedExtensions: [ExtensionID: BrowserExtension] = [:]
        private var assertions: [JavaScriptAssertion] = []
        private var expectedReached: [String] = []
        private var reached: [JavaScriptReached] = []
        private var backgroundService: BrowserExtensionBackgroundService
        private var dependencies: BrowserExtensionActiveManager.Dependencies

        init(verbose: Bool) {
            self.logger = createTestLogger(verbose: verbose)
            self.storageProvider = MockBrowserExtensionStorageProvider()
            self.storageManager = BrowserExtensionStorageManager(logger: logger)
            self.storageManager.storageProvider = storageProvider
            
            // Create active manager with all dependencies like other tests
            let network = BrowserExtensionNetwork()
            let router = BrowserExtensionRouter(network: network, logger: logger)
            
            // Connect router to storage manager for onChanged events
            self.storageManager.router = router

            backgroundService = BrowserExtensionBackgroundService(
                hiddenContainer: NSView(),
                logger: logger,
                useEphemeralDataStore: true,
                urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: logger)
            )
            dependencies = BrowserExtensionActiveManager.Dependencies(
                injectionScriptGenerator: BrowserExtensionContentScriptInjectionGenerator(logger: logger),
                userScriptFactory: BrowserExtensionUserScriptFactory(),
                backgroundService: backgroundService,
                network: network,
                router: router,
                logger: logger,
                storageManager: storageManager
            )
            self.activeManager = BrowserExtensionActiveManager(dependencies: dependencies)
            addDebugStuff()
        }

        private func addDebugStuff() {
            activeManager.debug = true
            let commonDebugScripts: [BrowserExtensionUserContentManager.UserScript] = [.init(code: assertionHandler,
                                                                                             injectionTime: .atDocumentStart,
                                                                                             forMainFrameOnly: false,
                                                                                             worlds: [],
                                                                                             identifier: "assertionFunctionsForTests")]
            activeManager.debugScripts = commonDebugScripts + [.init(code: Self.javascriptResolvingPromise(name: "Complete"),
                                                                     injectionTime: .atDocumentEnd,
                                                                     forMainFrameOnly: false,
                                                                     worlds: [],
                                                                     identifier: "resolveContentScriptComplete")]
            activeManager.debugHandlers = [.init(scriptMessageHandler: BrowserExtensionConsoleLogHandler(extensionId: ExtensionID(), logger: logger),
                                                 name: "consoleLog"),
                                           .init(scriptMessageHandler: AssertionMessageHandler(testRunner: self),
                                                 name: "assertions"),]
            backgroundService.debugScripts = commonDebugScripts
            backgroundService.debugHandlers = activeManager.debugHandlers
            let createBackgroundPromise = Self.javascriptCreatingPromise(name: "Complete")
            backgroundService.debugScripts.append(.init(code: createBackgroundPromise,
                                                        injectionTime: .atDocumentStart,
                                                        forMainFrameOnly: false,
                                                        worlds: [.page],
                                                        identifier: "createBackgroundPromise"))
            backgroundService.debugScripts.append(.init(code: Self.javascriptResolvingPromise(name: "Complete"),
                                                        injectionTime: .atDocumentEnd,
                                                        forMainFrameOnly: false,
                                                        worlds: [.page],
                                                        identifier: "resolveBackgroundPromise"))
        }

        static func javascriptCreatingPromise(name: String) -> String {
            """
            // replace the let/const declarations with window properties
            window.__resolve\(name) = undefined;
            window.__promiseFor\(name) = new Promise((resolve, reject) => {
                window.__resolve\(name) = resolve;
            });
            true;
            """
        }
        func javascriptCreatingPromise(name: String) -> String {
            Self.javascriptCreatingPromise(name: name)
        }

        static func javascriptBlockingOnPromise(name: String) -> String {
            """
            console.debug('Blocking on \(name)');
            await window.__promiseFor\(name);
            """
        }
        func javascriptBlockingOnPromise(name: String) -> String {
            Self.javascriptBlockingOnPromise(name: name)
        }

        static func javascriptResolvingPromise(name: String) -> String {
            """
            console.debug('Resolve \(name)');
            window.__resolve\(name)({});
            """
        }
        func javascriptResolvingPromise(name: String) -> String {
            Self.javascriptResolvingPromise(name: name)
        }

        /// Register a test extension for use in tests
        func registerExtension(_ testExtension: TestExtension) {
            extensions[testExtension.id] = testExtension
        }

        private let assertionHandler = """
                window.assert = function(condition, description, actualValue, expectedValue) {
                    const assertion = {
                        description: description || 'Assertion',
                        passed: !!condition,
                        actualValue: actualValue !== undefined ? String(actualValue) : null,
                        expectedValue: expectedValue !== undefined ? String(expectedValue) : null
                    };
                    if (!condition) {
                        console.error("Assertion failed: ", assertion);
                    }
                    window.webkit.messageHandlers.assertions.postMessage(assertion);
                    return !!condition;
                };
                
                window.assertEqual = function(actual, expected, description) {
                    return window.assert(actual === expected, description || 'Values should be equal', actual, expected);
                };
                
                window.assertTrue = function(condition, description) {
                    return window.assert(condition, description || 'Condition should be true', condition, true);
                };
                
                window.assertFalse = function(condition, description) {
                    return window.assert(!condition, description || 'Condition should be false', condition, false);
                };
                
                window.assertNotNull = function(value, description) {
                    return window.assert(value != null, description || 'Value should not be null', value, 'not null');
                };
            
                window.assertReached = function(name) {
                    console.debug('assertReached called with ', name);
                    window.webkit.messageHandlers.assertions.postMessage({reached: name});
                }
            """
        private var assertionScript: WKUserScript {
            WKUserScript(
                source: assertionHandler,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        }

        /// Create a web view for the specified context type
        func createUntrustedWebView(for contextType: TestContextType) async throws -> (AsyncWKWebView, BrowserExtensionUserContentManager) {
            // Create a basic configuration
            let configuration = WKWebViewConfiguration()
            let userContentController = WKUserContentController()
            
            userContentController.addUserScript(assertionScript)
            
            // Set up message handler for assertions
            userContentController.add(AssertionMessageHandler(testRunner: self), name: "assertions")
            
            configuration.userContentController = userContentController
            
            let webView = AsyncWKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
            webViews[contextType] = webView

            let userContentManager = BrowserExtensionUserContentManager(
                userContentController: webView.configuration.userContentController,
                userScriptFactory: BrowserExtensionUserScriptFactory())
            try await activeManager.registerWebView(webView, userContentManager: userContentManager, role: .userFacing)
            return (webView, userContentManager)
        }

        func unblockBackgroundScript(extensionId: ExtensionID, blockName: String) async {
            let iife = """
            (async () => {
                console.debug('Waiting for \(blockName) to complete in background script');
                __resolve\(blockName)({});
                console.debug('\(blockName) complete in background script');
            })();
            true;
            """
            _ = try! await activeManager.backgroundScriptWebView(in: extensionId)!.be_evaluateJavaScript(iife, in: nil, in: .page)
        }

        func waitForBackgroundScriptCompletion(_ extensionId: ExtensionID, name: String = "Complete") async {
            let js = """
            console.debug('Waiting for background script \(name)');
            await __promiseFor\(name);
            console.debug('Finished waiting for background script \(name)');
            true;
            """
            do {
                guard let webView = activeManager.backgroundScriptWebView(in: extensionId) else {
                    throw BrowserExtensionError.internalError("No background script webview found")
                }
                _ = try await webView.be_callAsyncJavaScript(
                    js,
                    arguments: [:],
                    in: nil,
                    in: .page)
            } catch {
                XCTFail("\(error)")
            }
            logger.debug("Swift done waiting on \(name)")
        }

        func unblockContentScript(_ id: ExtensionID, webView: BrowserExtensionWKWebView, name: String) async {
            let iife = """
            (async () => {
                console.debug('Waiting for \(name) to complete in content script');
                __resolve\(name)({});
                console.debug('\(name) content in background script');
            })();
            true;
            """
            _ = try! await webView.be_evaluateJavaScript(
                iife,
                in: nil,
                in: activeManager.contentWorld(for: id.stringValue)!)
        }

        func waitForContentScriptCompletion(_ id: ExtensionID, webView: BrowserExtensionWKWebView, name: String="Complete") async {
            let js = """
            console.debug('Waiting for \(name) completion');
            await __promiseFor\(name);
            console.debug('\(name) complete');
            """
            _ = try! await webView.be_callAsyncJavaScript(js, arguments: [:], in: nil, in: activeManager.contentWorld(for: id.stringValue)!)
        }

        private var currentPageView: AsyncWKWebView?

        // Returns the user-facing webview
        @discardableResult
        func run(_ testExtension: TestExtension) async throws -> AsyncWKWebView {
            clearAssertions()
            registerExtension(testExtension)
            let extensionId = testExtension.id

            // Create or reuse a real BrowserExtension from the test data
            let browserExtension: BrowserExtension
            var filesystem = [String: String]()
            let manifest = try createManifest(from: testExtension, filesystem: &filesystem)
            browserExtension = BrowserExtension(
                id: extensionId,
                manifest: manifest,
                baseURL: URL(string: "chrome-extension://\(extensionId.stringValue)/")!,
                logger: logger
            )
            browserExtension.mockFilesystem = filesystem
            try! browserExtension.loadContentScripts()
            try! browserExtension.loadBackgroundScript()
            assert(activatedExtensions[extensionId] == nil)
            activatedExtensions[extensionId] = browserExtension

            let completionPromise = Self.javascriptCreatingPromise(name: "Complete")
            activeManager.debugScripts += [.init(code: completionPromise,
                                                 injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: false,
                                                 worlds: [WKContentWorld.world(name: BrowserExtensionActiveManager.worldName(for: extensionId))],
                                                 identifier: "content script promise")]
            await activeManager.activate(browserExtension)
            let pageView = AsyncWKWebView()
            currentPageView = pageView  // ensure it does not get released
            let userContentManager = BrowserExtensionUserContentManager(
                userContentController: pageView.configuration.userContentController,
                userScriptFactory: BrowserExtensionUserScriptFactory())
            try await activeManager.registerWebView(
                pageView,
                userContentManager: userContentManager,
                role: .userFacing
            )
            // Load HTML to trigger document start and API injection
            _ = try await pageView.loadHTMLStringAsync("<html><body></body></html>", baseURL: nil)
            _ = try await pageView.evaluateJavaScript("true;")
            return pageView
        }

        func forgetActiveExtension() {
            backgroundService = BrowserExtensionBackgroundService(
                hiddenContainer: NSView(),
                logger: logger,
                useEphemeralDataStore: true,
                urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: logger)
            )
            dependencies.backgroundService = backgroundService
            dependencies.network = BrowserExtensionNetwork()
            dependencies.router = BrowserExtensionRouter(network: dependencies.network, logger: logger)
            self.activeManager = BrowserExtensionActiveManager(dependencies: dependencies)
            activatedExtensions.removeAll()
            addDebugStuff()
        }

        /// Create an ExtensionManifest from test extension data
        private func createManifest(from testExtension: TestExtension,
                                    filesystem: inout [String: String]) throws -> ExtensionManifest {
            var manifestDict = testExtension.manifest
            
            // Add content scripts if any
            if !testExtension.contentScripts.isEmpty {
                let contentScripts = testExtension.contentScripts.keys.map { filename in
                    [
                        "matches": ["<all_urls>"],
                        "js": [filename]
                    ]
                }
                manifestDict["content_scripts"] = contentScripts
                for (key, value) in testExtension.contentScripts {
                    filesystem[key] = value
                }
            }
            
            // Add background scripts if any
            if !testExtension.backgroundScripts.isEmpty {
                let firstScript = testExtension.backgroundScripts.keys.first!
                manifestDict["background"] = [
                    "service_worker": firstScript
                ]
                for (key, value) in testExtension.backgroundScripts {
                    filesystem[key] = value
                }
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: manifestDict)
            return try JSONDecoder().decode(ExtensionManifest.self, from: jsonData)
        }
        
        /// Load a web page into a web view
        func loadWebPage(extensionId: ExtensionID, pageName: String, into webView: AsyncWKWebView) async throws {
            guard let testExtension = extensions[extensionId],
                  let htmlContent = testExtension.webPages[pageName] else {
                throw TestError.webPageNotFound(pageName)
            }
            
            try await webView.loadHTMLStringAsync(htmlContent, baseURL: nil)
        }
        
        /// Execute JavaScript in a web view and return the result
        func executeJavaScript(_ script: String,
                               contextType: TestContextType,
                               extensionId: ExtensionID,
                               contentWebView: BrowserExtensionWKWebView?) async throws -> Any? {
            switch contextType {
            case .backgroundScript:
                let webView = activeManager.backgroundScriptWebView(in: extensionId)!
                return try await webView.be_evaluateJavaScript(script, in: nil, in: .page)
            case .contentScript:
                return try await contentWebView!.be_evaluateJavaScript(
                    script,
                    in: nil,
                    in: activeManager.contentWorld(for: extensionId.stringValue)!)
            case .untrustedWebPage:
                return try await contentWebView!.be_evaluateJavaScript(
                    script,
                    in: nil,
                    in: .page)
            }
        }

        func callAsyncJavaScript(_ script: String,
                               contextType: TestContextType,
                               extensionId: ExtensionID,
                               contentWebView: BrowserExtensionWKWebView?) async throws -> Any? {
            switch contextType {
            case .backgroundScript:
                let webView = activeManager.backgroundScriptWebView(in: extensionId)!
                return try await webView.be_callAsyncJavaScript(
                    script,
                    arguments: [:],
                    in: nil,
                    in: .page)
            case .contentScript:
                return try await contentWebView!.be_callAsyncJavaScript(
                    script,
                    arguments: [:],
                    in: nil,
                    in: activeManager.contentWorld(for: extensionId.stringValue)!)
            case .untrustedWebPage:
                return try await contentWebView!.be_callAsyncJavaScript(
                    script,
                    arguments: [:],
                    in: nil,
                    in: .page)
            }
        }

        /// Wait for all pending assertions to complete
        func waitForAssertions(timeout: TimeInterval = 5.0) async throws {
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < timeout {
                if assertions.isEmpty {
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        /// Verify all captured assertions using XCTest
        func verifyAssertions(file: StaticString = #file, line: UInt = #line) {
            XCTAssertFalse(assertions.isEmpty, "No assertions were reached")
            for assertion in assertions {
                XCTAssertTrue(assertion.passed, 
                             "JavaScript assertion failed: \(assertion.description)." +
                             (assertion.actualValue != nil ? " (actual: \(assertion.actualValue!)" : "(actual: nil") +
                             (assertion.expectedValue != nil ? ", expected: \(assertion.expectedValue!))" : ", expected: nil)"),
                             file: file, line: line)
            }
            for expectedReach in expectedReached {
                XCTAssertTrue(reached.contains { $0.name == expectedReach }, "Failed to reach \(expectedReach)")
            }
            assertions.removeAll()
            expectedReached.removeAll()
        }
        
        /// Clear all captured assertions
        func clearAssertions() {
            assertions.removeAll()
        }
        
        /// Internal method to add assertions from JavaScript
        fileprivate func addAssertion(_ assertion: JavaScriptAssertion) {
            assertions.append(assertion)
        }

        fileprivate func didReach(_ name: String) {
            reached.append(.init(name: name))
        }

        func expectReach(_ name: String) -> String {
            expectedReached.append(name)
            return "assertReached('\(name)'); console.log('Did reach \(name)');"
        }

        // MARK: - Extension Lifecycle Control
        
        /// Disable an extension (makes storage APIs non-functional)
        func disableExtension(_ extensionId: ExtensionID) async {
            await activeManager.deactivate(extensionId)
        }
        
        /// Re-enable a previously disabled extension
        func enableExtension(_ extensionId: ExtensionID) async throws {
            guard let testExtension = extensions[extensionId] else {
                throw TestError.extensionNotFound(extensionId)
            }

            var filesystem = [String: String]()
            let manifest = try createManifest(from: testExtension, filesystem: &filesystem)
            let browserExtension = BrowserExtension(
                manifest: manifest,
                baseURL: URL(string: "chrome-extension://\(extensionId.stringValue)/")!,
                logger: logger
            )
            
            await activeManager.activate(browserExtension)
        }
        
        /// Unload an extension completely (removes it from the system)
        func unloadExtension(_ extensionId: ExtensionID) async {
            await activeManager.deactivate(extensionId)
            extensions.removeValue(forKey: extensionId)
        }
        
        /// Reload an extension (simulates extension reload in browser)
        func reloadExtension(_ extensionId: ExtensionID) async throws {
            // Deactivate first
            await activeManager.deactivate(extensionId)
            
            // Clear any cached state
            storageProvider.clearStorageData(for: extensionId)
            
            // Re-enable
            try await enableExtension(extensionId)
        }
        
        /// Create a fresh test runner (simulates extension reload with fresh state)
        static func createFreshRunner() -> TestRunner {
            return TestRunner(verbose: false)
        }
        
        // MARK: - Advanced Testing Features
        
        /// Create a real iframe context for testing cross-origin scenarios
        func createIframeContext(origin: String, parentWebView: AsyncWKWebView) async throws -> WKFrameInfo? {
            return try await parentWebView.createIframeAsync(origin: origin)
        }
        
        /// Simulate extension shutdown
        func simulateShutdown(_ extensionId: ExtensionID) async {
            // Mark extension as shutting down - future API calls should fail fast
            await activeManager.deactivate(extensionId)
            
            // Clear webviews to simulate context destruction
            webViews.removeAll()
        }
        
        /// Corrupt storage data for testing error handling
        func corruptStorageData(for extensionId: ExtensionID) {
            storageProvider.corruptData(for: extensionId)
        }
        
        /// Check if an extension is currently active
        func isExtensionActive(_ extensionId: ExtensionID) -> Bool {
            return activeManager.activeExtension(for: extensionId) != nil
        }
        
        
    }
    
    /// Message handler for JavaScript assertions
    private class AssertionMessageHandler: NSObject, WKScriptMessageHandler {
        weak var testRunner: TestRunner?
        
        init(testRunner: TestRunner) {
            self.testRunner = testRunner
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any],
               let reached = body["reached"] as? String {
                testRunner?.didReach(reached)
                return
            }
            guard let body = message.body as? [String: Any],
                  let description = body["description"] as? String,
                  let passed = body["passed"] as? Bool else {
                return
            }
            
            let actualValue = body["actualValue"] as? String
            let expectedValue = body["expectedValue"] as? String
            
            let assertion = JavaScriptAssertion(
                description: description,
                passed: passed,
                actualValue: actualValue,
                expectedValue: expectedValue
            )
            
            testRunner?.addAssertion(assertion)
        }
    }
    
    
    /// Test-specific errors
    enum TestError: Error, LocalizedError {
        case extensionNotFound(ExtensionID)
        case webPageNotFound(String)
        case scriptExecutionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .extensionNotFound(let id):
                return "Extension not found: \(id)"
            case .webPageNotFound(let name):
                return "Web page not found: \(name)"
            case .scriptExecutionFailed(let error):
                return "Script execution failed: \(error)"
            }
        }
    }
}

/// Mock browser extension for testing
struct MockBrowserExtension {
    let id: ExtensionID
    let permissions: [BrowserExtensionAPIPermission]
    let manifest: [String: Any]
    
    func hasPermission(_ permission: BrowserExtensionAPIPermission) -> Bool {
        return permissions.contains(permission)
    }
}
