import XCTest
import WebKit
import BrowserExtensionShared
@testable import WebExtensionsFramework

@MainActor
class SendMessageHandlerTests: XCTestCase {
    
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
            description: "Test extension for sendMessage"
        )
        mockLogger = createTestLogger()
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/tmp"),
            extensionLocation: "test-extension",
            logger: mockLogger
        )
        
        // Create activeManager
        activeManager = createTestActiveManager(logger: mockLogger)
        
        // Create and configure webView
        webView = AsyncWKWebView()
        webView.configuration.userContentController.add(ConsoleLogHandler(),
                                                       name: "consoleLog")
        
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
        let jsBody = """
            console.log = (...args) => {
                window.webkit.messageHandlers.consoleLog
                    .postMessage(args.join(' '))
            };
            true;
            """
        _ = try await webView.evaluateJavaScript(jsBody)
    }
    
    override func tearDown() async throws {
        activeManager.unregisterWebView(webView)
        await activeManager.deactivateAll()
        webView = nil
        activeManager = nil
        mockLogger = nil
        mockBrowserExtension = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Properties
    
    private var extensionContentWorld: WKContentWorld {
        activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld
    }
    
    // MARK: - Single Argument Tests
    
    func testSendMessageSingleArgument() async throws {
        // Test sendMessage(message) - should not throw immediately
        let jsBody = """
            try {
                chrome.runtime.sendMessage({type: "greeting", data: "hello"});
                return {success: true};
            } catch (e) {
                return {error: e.message || String(e)};
            }
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // Should not throw synchronously
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertNil(result?["error"])
    }
    
    func testSendMessageSingleArgumentWithCallback() async throws {
        // Test sendMessage(message, callback)
        let jsBody = """
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    {type: "greeting", data: "hello"},
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({error: chrome.runtime.lastError.message});
                        } else {
                            resolve({response: response, error: null});
                        }
                    }
                );
            });
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // We expect a "no message receiver" error
        XCTAssertEqual(result?["error"] as? String, "Could not establish connection. Receiving end does not exist.")
    }
    
    // MARK: - Two Arguments Tests
    
    func testSendMessageTwoArgumentsMessageAndOptions() async throws {
        // Test sendMessage(message, options) - should not throw immediately
        let jsBody = """
            try {
                chrome.runtime.sendMessage(
                    {type: "greeting"},
                    {includeTlsChannelId: true}
                );
                return {success: true};
            } catch (e) {
                return {error: e.message || String(e)};
            }
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // Should not throw synchronously
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertNil(result?["error"])
    }
    
    func testSendMessageTwoArgumentsExtensionIdAndMessage() async throws {
        // Test sendMessage(extensionId, message) - should not throw immediately
        let jsBody = """
            try {
                chrome.runtime.sendMessage(
                    "other-extension-id",
                    {type: "greeting"}
                );
                return {success: true};
            } catch (e) {
                return {error: e.message || String(e)};
            }
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // Should not throw synchronously
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertNil(result?["error"])
    }
    
    func testSendMessageTwoArgumentsMessageAndCallback() async throws {
        // Test sendMessage(message, callback) - callback should be detected and removed by JS
        let jsBody = """
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    {type: "greeting"},
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({error: chrome.runtime.lastError.message});
                        } else {
                            resolve({response: response, error: null});
                        }
                    }
                );
            });
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        XCTAssertEqual(result?["error"] as? String, "Could not establish connection. Receiving end does not exist.")
    }
    
    // MARK: - Three Arguments Tests
    
    func testSendMessageThreeArgumentsWithExtensionId() async throws {
        // Test sendMessage(extensionId, message, options) - should not throw immediately
        let jsBody = """
            try {
                chrome.runtime.sendMessage(
                    "other-extension-id",
                    {type: "greeting"},
                    {includeTlsChannelId: false}
                );
                return {success: true};
            } catch (e) {
                return {error: e.message || String(e)};
            }
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // Should not throw synchronously
        XCTAssertEqual(result?["success"] as? Bool, true)
        XCTAssertNil(result?["error"])
    }
    
    func testSendMessageThreeArgumentsWithCallback() async throws {
        // Test sendMessage(message, options, callback)
        let jsBody = """
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    {type: "greeting"},
                    {includeTlsChannelId: true},
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({error: chrome.runtime.lastError.message});
                        } else {
                            resolve({response: response, error: null});
                        }
                    }
                );
            });
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        XCTAssertEqual(result?["error"] as? String, "Could not establish connection. Receiving end does not exist.")
    }
    
    // MARK: - Error Cases
    
    func testSendMessageNoArguments() async throws {
        // Test sendMessage() with no arguments
        let jsBody = """
            try {
                chrome.runtime.sendMessage();
                return {error: null};
            } catch (e) {
                return {error: e.message || String(e)};
            }
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // Should receive an error about missing arguments
        XCTAssertNotNil(result?["error"])
    }
    
    func testSendMessageInvalidMessageType() async throws {
        // Test sendMessage with non-object message
        let jsBody = """
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    123, // This will be stringified and sent, but no listener exists
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({error: chrome.runtime.lastError.message});
                        } else {
                            resolve({response: response, error: null});
                        }
                    }
                );
            });
            """
        
        let result = try await webView.callAsyncJavaScript(jsBody, contentWorld: extensionContentWorld) as? [String: Any]
        
        // Should receive an error about no message receiver (since the string is passed through)
        XCTAssertNotNil(result?["error"])
        XCTAssertTrue((result?["error"] as? String)?.contains("Could not establish connection") ?? false)
    }
    
    // MARK: - Direct Handler Tests
    
    func testSendMessageHandlerParsingSingleArgument() async throws {
        let handler = RuntimeSendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, world: .page, browserExtension: mockBrowserExtension, trusted: true, role: .backgroundScript(mockBrowserExtension.id), setAccessLevelToken: "")
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test single argument: just message
        let request = RuntimeSendMessageRequestImpl(
            requestId: "test-1",
            args: [AnyJSONCodable("{\"greeting\":\"hello\"}")]
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testSendMessageHandlerParsingTwoArgumentsExtensionIdAndMessage() async throws {
        let handler = RuntimeSendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, world: .page, browserExtension: mockBrowserExtension, trusted: true, role: .backgroundScript(mockBrowserExtension.id), setAccessLevelToken: "")
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test two arguments: extensionId and message
        let request = RuntimeSendMessageRequestImpl(
            requestId: "test-2",
            args: [
                AnyJSONCodable("\"other-extension-id\""),
                AnyJSONCodable("{\"greeting\":\"hello\"}")
            ]
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testSendMessageHandlerParsingTwoArgumentsMessageAndOptions() async throws {
        let handler = RuntimeSendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, world: .page, browserExtension: mockBrowserExtension, trusted: true, role: .backgroundScript(mockBrowserExtension.id), setAccessLevelToken: "")
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test two arguments: message and options
        let request = RuntimeSendMessageRequestImpl(
            requestId: "test-3",
            args: [
                AnyJSONCodable("{\"greeting\":\"hello\"}"),
                AnyJSONCodable("{\"includeTlsChannelId\":true}")
            ]
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testSendMessageHandlerParsingThreeArguments() async throws {
        let handler = RuntimeSendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, world: .page, browserExtension: mockBrowserExtension, trusted: true, role: .backgroundScript(mockBrowserExtension.id), setAccessLevelToken: "")
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test three arguments: extensionId, message, and options
        let request = RuntimeSendMessageRequestImpl(
            requestId: "test-4",
            args: [
                AnyJSONCodable("\"other-extension-id\""),
                AnyJSONCodable("{\"greeting\":\"hello\"}"),
                AnyJSONCodable("{\"includeTlsChannelId\":true}")
            ]
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testSendMessageHandlerNoArguments() async throws {
        let handler = RuntimeSendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, world: .page, browserExtension: mockBrowserExtension, trusted: true, role: .backgroundScript(mockBrowserExtension.id), setAccessLevelToken: "")
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test no arguments
        let request = RuntimeSendMessageRequestImpl(
            requestId: "test-5",
            args: []
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown internalError")
        } catch let error as BrowserExtensionError {
            if case .internalError(let message) = error {
                XCTAssertTrue(message.contains("at least one argument"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testSendMessageHandlerInvalidMessageType() async throws {
        let handler = RuntimeSendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, world: .page, browserExtension: mockBrowserExtension, trusted: true, role: .backgroundScript(mockBrowserExtension.id), setAccessLevelToken: "")
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil,
            contextType: .trusted,
            role: .backgroundScript(mockBrowserExtension.id)
        )
        
        // Test with string (not a JSON-encoded string) - the handler now accepts any string
        let request = RuntimeSendMessageRequestImpl(
            requestId: "test-6",
            args: [AnyJSONCodable("\"not an object\"")]  // JSON-encoded string
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            // Since the handler passes strings through, we expect noMessageReceiver
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    // MARK: - MV3 Messaging Restriction Tests
    
    func testBackgroundServiceWorkerCannotSendMessageToContentScript() async throws {
        let backgroundMessageSent = "BackgroundMessageSent"
        let backgroundReceivedError = "BackgroundReceivedError"
        let contentReady = "ContentReady"
        
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    
                    (async function() {
                        console.log('Content script setting up message listener');
                        // Set up message listener in content script
                        chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                            console.log('Content script received message:', message);
                            console.log('Message sender:', sender);
                            
                            // This should never be reached in MV3 when sent from background service worker
                            assertTrue(false, 'Content script should not receive messages from background service worker in MV3');
                            return true;
                        });
                        
                        console.log('Content script listener ready');
                        globalThis.contentListenerReady = true;
                        \(testRunner.javascriptResolvingPromise(name: contentReady))
                    })();
                """
            ],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: backgroundMessageSent))
                    \(testRunner.javascriptCreatingPromise(name: backgroundReceivedError))
                    
                    (async function() {
                        console.log('Background service worker started');
                        
                        console.log('Background service worker attempting to send message to content script');
                        chrome.runtime.sendMessage({
                            type: 'background_to_content',
                            message: 'This should not be allowed in MV3'
                        }, (response) => {
                            console.log('Background service worker callback called');
                            // In MV3, background service workers cannot send messages to content scripts
                            // The framework filters out content script receivers, so we get "no message receiver" error
                            assertTrue(chrome.runtime.lastError !== undefined, 'Background service worker should get error when trying to send to content script');
                            assertTrue(chrome.runtime.lastError.message.includes('Could not establish connection') || 
                                      chrome.runtime.lastError.message.includes('Receiving end does not exist'), 
                                      'Error message should indicate no eligible receivers');
                            globalThis.backgroundError = chrome.runtime.lastError.message;
                            \(testRunner.javascriptResolvingPromise(name: backgroundReceivedError))
                            \(testRunner.expectReach("background received no receiver error"))
                        });
                        \(testRunner.javascriptResolvingPromise(name: backgroundMessageSent))
                        \(testRunner.expectReach("background attempted to send message"))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        
        // Create an untrusted webview for content script
        let (contentWebView, _) = try await testRunner.createUntrustedWebView(for: .contentScript)
        try await contentWebView.loadHTMLStringAsync("<html><body>Test Page</body></html>", baseURL: nil)
        
        // Wait for content script to be ready
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentReady)
        
        // Wait for background script to attempt message sending
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundMessageSent)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundReceivedError)
        
        testRunner.verifyAssertions()
    }
    
    // MARK: - Helper Setup for TestRunner
    
    private var testRunner: ExtensionTestingInfrastructure.TestRunner!
    
    override func setUpWithError() throws {
        testRunner = ExtensionTestingInfrastructure.TestRunner(verbose: false)
    }
    
    override func tearDownWithError() throws {
        testRunner = nil
    }
}

// MARK: - Console Log Handler

fileprivate class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("JS Console: \(message.body)")
    }
}
