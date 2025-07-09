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
        let baseURL = URL(fileURLWithPath: "/tmp/test-extension")
        mockLogger = createTestLogger()
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseURL: baseURL,
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
        try await activeManager.registerWebView(webView, role: .userFacing)
        
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
        try await webView.evaluateJavaScript(jsBody)
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
                    123, // Invalid - should be an object
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
        
        // Should receive an error about invalid message type
        XCTAssertNotNil(result?["error"])
        XCTAssertTrue((result?["error"] as? String)?.contains("Message must be a JSON object") ?? false)
    }
    
    // MARK: - Direct Handler Tests
    
    func testSendMessageHandlerParsingSingleArgument() async throws {
        let handler = SendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, browserExtension: mockBrowserExtension)
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil
        )
        
        // Test single argument: just message
        let request = SendMessageRequestImpl(
            requestId: "test-1",
            args: [AnyJSONCodable(["greeting": "hello"])]
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown noMessageReceiver error")
        } catch let error as BrowserExtensionError {
            XCTAssertEqual(error, .noMessageReceiver)
        }
    }
    
    func testSendMessageHandlerParsingTwoArgumentsExtensionIdAndMessage() async throws {
        let handler = SendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, browserExtension: mockBrowserExtension)
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil
        )
        
        // Test two arguments: extensionId and message
        let request = SendMessageRequestImpl(
            requestId: "test-2",
            args: [
                AnyJSONCodable("other-extension-id"),
                AnyJSONCodable(["greeting": "hello"])
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
        let handler = SendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, browserExtension: mockBrowserExtension)
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil
        )
        
        // Test two arguments: message and options
        let request = SendMessageRequestImpl(
            requestId: "test-3",
            args: [
                AnyJSONCodable(["greeting": "hello"]),
                AnyJSONCodable(["includeTlsChannelId": true])
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
        let handler = SendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, browserExtension: mockBrowserExtension)
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil
        )
        
        // Test three arguments: extensionId, message, and options
        let request = SendMessageRequestImpl(
            requestId: "test-4",
            args: [
                AnyJSONCodable("other-extension-id"),
                AnyJSONCodable(["greeting": "hello"]),
                AnyJSONCodable(["includeTlsChannelId": true])
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
        let handler = SendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, browserExtension: mockBrowserExtension)
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil
        )
        
        // Test no arguments
        let request = SendMessageRequestImpl(
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
        let handler = SendMessageHandler()
        let network = BrowserExtensionNetwork()
        network.add(webView: webView, browserExtension: mockBrowserExtension)
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        let context = BrowserExtensionContext(
            logger: mockLogger,
            router: router,
            webView: webView,
            browserExtension: mockBrowserExtension,
            tab: nil,
            frameId: nil
        )
        
        // Test invalid message type (not an object)
        let request = SendMessageRequestImpl(
            requestId: "test-6",
            args: [AnyJSONCodable("not an object")]
        )
        
        do {
            _ = try await handler.handle(request: request, context: context)
            XCTFail("Should have thrown internalError")
        } catch let error as BrowserExtensionError {
            if case .internalError(let message) = error {
                XCTAssertTrue(message.contains("Message must be a JSON object"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}

// MARK: - Console Log Handler

fileprivate class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("JS Console: \(message.body)")
    }
}
