//
//  OnMessageTests.swift
//  WebExtensionsFramework
//
//  Created by Assistant on 7/7/25.
//

import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class OnMessageTests: XCTestCase {
    
    var mockLogger: BrowserExtensionLogger!
    var mockBrowserExtension: BrowserExtension!
    var activeManager: BrowserExtensionActiveManager!
    var senderWebView: AsyncWKWebView!
    var receiverWebView: AsyncWKWebView!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockLogger = createTestLogger(verbose: true)
        
        // Create mock browser extension
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Test Extension",
            version: "1.0.0"
        )
        let baseURL = URL(fileURLWithPath: "/tmp/test-extension")
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseURL: baseURL,
            logger: mockLogger
        )
        
        // Create webviews
        senderWebView = AsyncWKWebView()
        receiverWebView = AsyncWKWebView()
        
        // Add console log handlers for debugging
        senderWebView.configuration.userContentController.add(ConsoleLogHandler(), name: "consoleLog")
        receiverWebView.configuration.userContentController.add(ConsoleLogHandler(), name: "consoleLog")
        
        // Create activeManager
        activeManager = createTestActiveManager(logger: mockLogger)
        
        // Activate the extension (this will set up the infrastructure properly)
        await activeManager.activate(mockBrowserExtension)

        // Register both webviews with the activeManager (this will inject APIs automatically)
        try await activeManager.registerWebView(
            senderWebView,
            userContentManager: BrowserExtensionUserContentManager(
                webView: senderWebView,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)
        try await activeManager.registerWebView(
            receiverWebView,
            userContentManager: BrowserExtensionUserContentManager(
                webView: receiverWebView,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)

        // Load HTML into both webviews (this will trigger the injected scripts)
        let html = "<html><body>Test</body></html>"
        try await senderWebView.loadHTMLStringAsync(html, baseURL: nil)
        try await receiverWebView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Set up console.log override for debugging
        let consoleScript = """
            console.log = (...args) => {
                window.webkit.messageHandlers.consoleLog.postMessage(args.join(' '));
            };
            true;
        """
        try await senderWebView.evaluateJavaScript(consoleScript)
        try await receiverWebView.evaluateJavaScript(consoleScript)
    }
    
    override func tearDown() async throws {
        activeManager.unregisterWebView(senderWebView)
        activeManager.unregisterWebView(receiverWebView)
        await activeManager.deactivateAll()
        senderWebView = nil
        receiverWebView = nil
        mockBrowserExtension = nil
        activeManager = nil
        mockLogger = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic onMessage functionality
    
    func testOnMessageAddListener() async throws {
        // Test that we can add a listener
        let result = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                // Simple listener that doesn't respond
            });
            return { success: true };
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertEqual(result?["success"] as? Bool, true)
    }
    
    func testOnMessageRemoveListener() async throws {
        // Test that we can add and remove a listener
        let result = try await receiverWebView.callAsyncJavaScript("""
            function testListener(message, sender, sendResponse) {
                // Simple listener
            }
            
            chrome.runtime.onMessage.addListener(testListener);
            let hasBeforeRemove = chrome.runtime.onMessage.hasListener(testListener);
            
            chrome.runtime.onMessage.removeListener(testListener);
            let hasAfterRemove = chrome.runtime.onMessage.hasListener(testListener);
            
            return { 
                hasBeforeRemove: hasBeforeRemove, 
                hasAfterRemove: hasAfterRemove 
            };
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertEqual(result?["hasBeforeRemove"] as? Bool, true)
        XCTAssertEqual(result?["hasAfterRemove"] as? Bool, false)
    }
    
    func testOnMessageHasListener() async throws {
        // Test hasListener function
        let result = try await receiverWebView.callAsyncJavaScript("""
            function testListener(message, sender, sendResponse) {
                // Simple listener
            }
            
            function otherListener(message, sender, sendResponse) {
                // Another listener
            }
            
            let hasBeforeAdd = chrome.runtime.onMessage.hasListener(testListener);
            chrome.runtime.onMessage.addListener(testListener);
            let hasAfterAdd = chrome.runtime.onMessage.hasListener(testListener);
            let hasOther = chrome.runtime.onMessage.hasListener(otherListener);
            
            return { 
                hasBeforeAdd: hasBeforeAdd,
                hasAfterAdd: hasAfterAdd,
                hasOther: hasOther
            };
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertEqual(result?["hasBeforeAdd"] as? Bool, false)
        XCTAssertEqual(result?["hasAfterAdd"] as? Bool, true)
        XCTAssertEqual(result?["hasOther"] as? Bool, false)
    }
    
    // MARK: - Message sending and receiving
    
    func testSimpleMessageExchange() async throws {
        // Get the content world for the extension
        let extensionContentWorld = activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld
        
        // Set up listener in receiver
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "greeting") {
                    sendResponse({ reply: "hello back!" });
                }
            });
        """, contentWorld: extensionContentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "greeting", data: "hello" },
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({ error: chrome.runtime.lastError.message });
                        } else {
                            resolve({ response: response });
                        }
                    }
                );
            });
        """, contentWorld: extensionContentWorld) as? [String: Any]
        
        XCTAssertNil(result?["error"])
        let response = result?["response"] as? [String: Any]
        XCTAssertEqual(response?["reply"] as? String, "hello back!")
    }
    
    func testAsynchronousResponse() async throws {
        // Set up listener that responds asynchronously
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "async") {
                    setTimeout(() => {
                        sendResponse({ async: true, received: message.data });
                    }, 50);
                    return true; // Keep the message channel open
                }
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "async", data: "test data" },
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({ error: chrome.runtime.lastError.message });
                        } else {
                            resolve({ response: response });
                        }
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertNil(result?["error"])
        let response = result?["response"] as? [String: Any]
        XCTAssertEqual(response?["async"] as? Bool, true)
        XCTAssertEqual(response?["received"] as? String, "test data")
    }
    
    func testMultipleListeners() async throws {
        // Set up multiple listeners in receiver
        _ = try await receiverWebView.callAsyncJavaScript("""
            let responses = [];
            
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "broadcast") {
                    responses.push("listener1");
                }
            });
            
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "broadcast") {
                    responses.push("listener2");
                    sendResponse({ from: "listener2", responses: responses });
                }
            });
            
            window.getResponses = function() { return responses; };
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "broadcast", data: "test" },
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({ error: chrome.runtime.lastError.message });
                        } else {
                            resolve({ response: response });
                        }
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertNil(result?["error"])
        let response = result?["response"] as? [String: Any]
        XCTAssertEqual(response?["from"] as? String, "listener2")
        let responses = response?["responses"] as? [String]
        XCTAssertEqual(responses?.count, 2)
        XCTAssertTrue(responses?.contains("listener1") == true)
        XCTAssertTrue(responses?.contains("listener2") == true)
    }
    
    func testListenerExceptionHandling() async throws {
        // Set up listeners, one that throws and one that works
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "exception_test") {
                    throw new Error("Test exception");
                }
            });
            
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "exception_test") {
                    sendResponse({ success: true });
                }
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "exception_test" },
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({ error: chrome.runtime.lastError.message });
                        } else {
                            resolve({ response: response });
                        }
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertNil(result?["error"])
        let response = result?["response"] as? [String: Any]
        XCTAssertEqual(response?["success"] as? Bool, true)
    }
    
    func testNoResponseFromListener() async throws {
        // Set up listener that doesn't respond
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "no_response") {
                    // Don't call sendResponse or return true
                }
            });
            true;
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender - should complete without throwing error
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "no_response" },
                    (response) => {
                        // Just resolve with success if no error occurred
                        resolve({ success: !chrome.runtime.lastError });
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        // The main goal is that this doesn't crash
        XCTAssertNotNil(result)
    }
    
    func testSendMessageWithNoListeners() async throws {
        // Don't set up any listeners - this should return undefined, not an error
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "test" },
                    (response) => {
                        resolve({ 
                            hasError: !!chrome.runtime.lastError,
                            errorMessage: chrome.runtime.lastError?.message,
                            responseType: typeof response,
                            response: response
                        });
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        // According to Chrome behavior, when there are no listeners:
        // 1. Set lastError to "Could not establish connection. Receiving end does not exist."
        // 2. Call callback with undefined
        XCTAssertEqual(result?["hasError"] as? Bool, true)
        XCTAssertEqual(result?["errorMessage"] as? String, "Could not establish connection. Receiving end does not exist.")
        XCTAssertEqual(result?["responseType"] as? String, "undefined")
    }
    
    func testListenerSendsNullResponse() async throws {
        // Set up listener that explicitly sends null
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "null_response") {
                    sendResponse(null); // Explicitly send null
                }
            });
            true;
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "null_response" },
                    (response) => {
                        resolve({ 
                            hasError: !!chrome.runtime.lastError,
                            responseType: typeof response,
                            response: response,
                            isNull: response === null
                        });
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        // When a listener explicitly sends null, the callback should receive null, not undefined
        XCTAssertEqual(result?["hasError"] as? Bool, false)
        XCTAssertEqual(result?["responseType"] as? String, "object") // null is typeof "object" in JS
        XCTAssertEqual(result?["isNull"] as? Bool, true)
    }
    
    func testSendMessageWithUndefinedAndRespondWithUndefined() async throws {
        // Set up listener that explicitly responds with undefined
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "undefined_test") {
                    // Test that we can receive undefined in the message
                    sendResponse({ 
                        receivedUndefined: message.data === undefined,
                        respondingWith: undefined
                    });
                }
            });
            true;
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message with undefined value from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "undefined_test", data: undefined },
                    (response) => {
                        resolve({ 
                            hasError: !!chrome.runtime.lastError,
                            responseType: typeof response,
                            response: response,
                            receivedUndefined: response?.receivedUndefined,
                            respondingWithType: typeof response?.respondingWith,
                            respondingWithIsUndefined: response?.respondingWith === undefined
                        });
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        // Verify the listener received undefined in the message
        XCTAssertEqual(result?["hasError"] as? Bool, false)
        XCTAssertEqual(result?["responseType"] as? String, "object") // response is an object containing the reply
        XCTAssertEqual(result?["receivedUndefined"] as? Bool, true) // listener received undefined in message.data
        XCTAssertEqual(result?["respondingWithType"] as? String, "undefined") // undefined response field
        XCTAssertEqual(result?["respondingWithIsUndefined"] as? Bool, true) // explicit undefined check
    }
    
    func testListenerRespondsWithExplicitUndefined() async throws {
        // Set up listener that calls sendResponse(undefined) explicitly
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "explicit_undefined") {
                    sendResponse(undefined); // Explicitly send undefined
                }
            });
            true;
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "explicit_undefined" },
                    (response) => {
                        resolve({ 
                            hasError: !!chrome.runtime.lastError,
                            responseType: typeof response,
                            response: response,
                            isUndefined: response === undefined
                        });
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        // When a listener explicitly calls sendResponse(undefined), the callback should receive undefined
        XCTAssertEqual(result?["hasError"] as? Bool, false)
        XCTAssertEqual(result?["responseType"] as? String, "undefined")
        XCTAssertEqual(result?["isUndefined"] as? Bool, true)
    }
    
    // MARK: - Edge cases and error handling
    
    func testSendResponseCalledMultipleTimes() async throws {
        // Set up listener that tries to call sendResponse multiple times
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "multiple_response") {
                    sendResponse({ attempt: 1 });
                    sendResponse({ attempt: 2 }); // Should be ignored
                }
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                chrome.runtime.sendMessage(
                    { type: "multiple_response" },
                    (response) => {
                        if (chrome.runtime.lastError) {
                            resolve({ error: chrome.runtime.lastError.message });
                        } else {
                            resolve({ response: response });
                        }
                    }
                );
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertNil(result?["error"])
        let response = result?["response"] as? [String: Any]
        XCTAssertEqual(response?["attempt"] as? Int, 1) // Only first response should be received
    }
    
    func testComplexMessageData() async throws {
        // Set up listener that echoes complex data
        _ = try await receiverWebView.callAsyncJavaScript("""
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                if (message.type === "complex") {
                    sendResponse({ 
                        echo: message,
                        timestamp: 1234567890, // Use fixed timestamp to avoid Date object issues
                        sender: {
                            id: sender.id,
                            url: sender.url
                        }
                    });
                }
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld)
        
        // Send complex message from sender
        let result = try await senderWebView.callAsyncJavaScript("""
            return await new Promise((resolve) => {
                const complexMessage = {
                    type: "complex",
                    data: {
                        array: [1, 2, 3],
                        nested: {
                            deep: {
                                value: "test",
                                number: 42,
                                boolean: true
                            }
                        }
                    }
                };
                
                chrome.runtime.sendMessage(complexMessage, (response) => {
                    if (chrome.runtime.lastError) {
                        resolve({ error: chrome.runtime.lastError.message });
                    } else {
                        resolve({ response: response });
                    }
                });
            });
        """, contentWorld: activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld) as? [String: Any]
        
        XCTAssertNil(result?["error"])
        let response = result?["response"] as? [String: Any]
        XCTAssertNotNil(response?["echo"])
        XCTAssertNotNil(response?["timestamp"])
        XCTAssertNotNil(response?["sender"])
        
        let echo = response?["echo"] as? [String: Any]
        XCTAssertEqual(echo?["type"] as? String, "complex")
        
        let sender = response?["sender"] as? [String: Any]
        XCTAssertEqual(sender?["id"] as? String, mockBrowserExtension.id.uuidString)
    }
}

// Console log handler for debugging
fileprivate class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("JS Console: \(message.body)")
    }
}
