//
//  BackgroundToContentMessagingTests.swift
//  WebExtensionsFramework
//
//  Created by Assistant on 7/8/25.
//

import XCTest
import WebKit
import AppKit
@testable import WebExtensionsFramework

@MainActor
class BackgroundToContentMessagingTests: XCTestCase {
    
    var mockLogger: BrowserExtensionLogger!
    var mockBrowserExtension: BrowserExtension!
    var activeManager: BrowserExtensionActiveManager!
    var contentWebView: AsyncWKWebView!
    var hiddenContainer: NSView!
    var backgroundService: BrowserExtensionBackgroundServiceProtocol!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockLogger = createTestLogger(verbose: true)
        
        // Create background script content
        let backgroundScriptContent = """
            console.log('Background script started');
            
            // Function to send message to content script
            function sendMessageToContentScript() {
                console.log('Background script sending message to content script');
                chrome.runtime.sendMessage({
                    type: 'background_to_content',
                    message: 'Hello from background script!',
                    timestamp: Date.now()
                }, (response) => {
                    console.log('Background script received response:', response);
                    if (chrome.runtime.lastError) {
                        console.log('Background script error:', chrome.runtime.lastError.message);
                        globalThis.backgroundError = chrome.runtime.lastError.message;
                    } else {
                        globalThis.backgroundResponse = response;
                    }
                    globalThis.backgroundMessageSent = true;
                });
            }
            
            // Make the function available globally for testing
            globalThis.sendMessageToContentScript = sendMessageToContentScript;
            globalThis.backgroundScriptReady = true;
        """
        
        // Create background script resource
        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )
        
        let backgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: backgroundScriptContent,
            isServiceWorker: true
        )
        
        // Create mock browser extension with background script
        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "Background to Content Test Extension",
            version: "1.0.0",
            background: backgroundScript
        )
        let baseURL = URL(fileURLWithPath: "/tmp/test-extension")
        mockBrowserExtension = BrowserExtension(
            manifest: manifest,
            baseURL: baseURL,
            logger: mockLogger
        )
        
        // Set the background script resource
        mockBrowserExtension.setBackgroundScriptResource(backgroundResource)
        
        // Create webview for content script
        contentWebView = AsyncWKWebView()
        
        // Add console log handler for debugging
        contentWebView.configuration.userContentController.add(ConsoleLogHandler(), name: "consoleLog")
        
        // Create hidden container for background service
        hiddenContainer = NSView()
        
        // Create activeManager with real background service
        backgroundService = BrowserExtensionBackgroundService(
            hiddenContainer: hiddenContainer,
            logger: mockLogger,
            useEphemeralDataStore: true,
            urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: mockLogger)
        )
        let network = BrowserExtensionNetwork()
        let router = BrowserExtensionRouter(network: network, logger: mockLogger)
        activeManager = BrowserExtensionActiveManager(
            injectionScriptGenerator: BrowserExtensionContentScriptInjectionGenerator(logger: mockLogger),
            userScriptFactory: BrowserExtensionUserScriptFactory(),
            backgroundService: backgroundService,
            network: network,
            router: router,
            logger: mockLogger
        )
        
        // Activate the extension (this will start the background script)
        await activeManager.activate(mockBrowserExtension)
        
        // Register content webview
        try await activeManager.registerWebView(
            contentWebView,
            userContentManager: BrowserExtensionUserContentManager(
                userContentController: contentWebView.be_configuration.be_userContentController,
                userScriptFactory: BrowserExtensionUserScriptFactory()),
            role: .userFacing)

        // Load HTML into content webview
        let html = "<html><body>Test</body></html>"
        try await contentWebView.loadHTMLStringAsync(html, baseURL: nil)
        
        // Set up console.log override for debugging
        let consoleScript = """
            console.log = (...args) => {
                window.webkit.messageHandlers.consoleLog.postMessage(args.join(' '));
            };
            true;
        """
        try await contentWebView.evaluateJavaScript(consoleScript)
    }
    
    override func tearDown() async throws {
        activeManager.unregisterWebView(contentWebView)
        await activeManager.deactivateAll()
        contentWebView = nil
        mockBrowserExtension = nil
        activeManager = nil
        backgroundService = nil
        hiddenContainer = nil
        mockLogger = nil
        try await super.tearDown()
    }
    
    // MARK: - Integration Tests
    
    func testBackgroundScriptSendsMessageToContentScript() async throws {
        // Set up content script listener
        let extensionContentWorld = activeManager.activeExtension(for: mockBrowserExtension.id)!.contentWorld
        
        _ = try await contentWebView.callAsyncJavaScript("""
            console.log('Content script setting up message listener');
            
            // Set up message listener in content script
            chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                console.log('Content script received message:', message);
                console.log('Message sender:', sender);
                
                if (message.type === 'background_to_content') {
                    // Store the received message for testing
                    globalThis.receivedMessage = message;
                    
                    // Send response back to background script
                    sendResponse({
                        success: true,
                        reply: 'Hello back from content script!',
                        originalMessage: message.message
                    });
                    
                    globalThis.contentResponseSent = true;
                    return true; // Keep message channel open
                }
            });
            
            globalThis.contentListenerReady = true;
        """, contentWorld: extensionContentWorld)
        
        // Wait for background script to initialize
        var backgroundReady = false
        for _ in 0..<50 { // Wait up to 5 seconds
            let ready = try await backgroundService.evaluateJavaScript("globalThis.backgroundScriptReady", in: mockBrowserExtension.id)
            if ready as? Bool == true {
                backgroundReady = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        XCTAssertTrue(backgroundReady, "Background script should be ready")
        
        // Verify content script listener is ready
        print("DEBUG: Checking if content script listener is ready")
        let contentReady = try await contentWebView.callAsyncJavaScript("""
            return globalThis.contentListenerReady === true;
        """, contentWorld: extensionContentWorld) as? Bool
        print("DEBUG: Content script listener ready: \(contentReady ?? false)")
        XCTAssertTrue(contentReady == true, "Content script listener should be ready")
        
        // Trigger message from background to content
        print("DEBUG: Triggering message from background to content")
        try await backgroundService.evaluateJavaScript("sendMessageToContentScript()", in: mockBrowserExtension.id)
        print("DEBUG: Message trigger completed")
        
        // Wait for message to be processed
        print("DEBUG: Waiting for message to be processed")
        var messageProcessed = false
        for _ in 0..<50 { // Wait up to 5 seconds
            let sent = try await backgroundService.evaluateJavaScript("globalThis.backgroundMessageSent", in: mockBrowserExtension.id)
            if sent as? Bool == true {
                messageProcessed = true
                print("DEBUG: Background message was sent")
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        XCTAssertTrue(messageProcessed, "Background script should have sent message")
        
        // Verify content script received the message
        print("DEBUG: Checking if content script received the message")
        let receivedMessage = try await contentWebView.callAsyncJavaScript("""
            return globalThis.receivedMessage;
        """, contentWorld: extensionContentWorld) as? [String: Any]
        
        print("DEBUG: Content script received message: \(receivedMessage ?? [:])")
        XCTAssertNotNil(receivedMessage, "Content script should have received message")
        XCTAssertEqual(receivedMessage?["type"] as? String, "background_to_content")
        XCTAssertEqual(receivedMessage?["message"] as? String, "Hello from background script!")
        
        // Verify content script sent response
        let responseSent = try await contentWebView.callAsyncJavaScript("""
            return globalThis.contentResponseSent === true;
        """, contentWorld: extensionContentWorld) as? Bool
        XCTAssertTrue(responseSent == true, "Content script should have sent response")
        
        // Verify background script received response
        print("DEBUG: Checking if background script received response")
        let backgroundResponse = try await backgroundService.evaluateJavaScript("globalThis.backgroundResponse", in: mockBrowserExtension.id) as? [String: Any]
        
        print("DEBUG: Background script response: \(backgroundResponse ?? [:])")
        XCTAssertNotNil(backgroundResponse, "Background script should have received response")
        if let response = backgroundResponse {
            XCTAssertEqual(response["success"] as? Bool, true)
            XCTAssertEqual(response["reply"] as? String, "Hello back from content script!")
            XCTAssertEqual(response["originalMessage"] as? String, "Hello from background script!")
        }
        
        // Verify no errors occurred
        let backgroundError = try await backgroundService.evaluateJavaScript("globalThis.backgroundError", in: mockBrowserExtension.id)
        print("DEBUG: Background script error: \(backgroundError ?? "nil")")
        XCTAssertNil(backgroundError, "Background script should not have errors")
    }

    private static func makeNoListenerExtension(logger: BrowserExtensionLogger) -> BrowserExtension {
        // Create a separate extension for the no-listener test
        let backgroundScriptContent = """
            console.log('Background script started');
            
            // Function to send message to content script (no listener)
            function sendMessageWithNoListener() {
                console.log('Background script sending message with no listener');
                chrome.runtime.sendMessage({
                    type: 'no_listener_test',
                    message: 'This should fail'
                }, (response) => {
                    console.log('Background script callback called');
                    if (chrome.runtime.lastError) {
                        console.log('Background script error:', chrome.runtime.lastError.message);
                        globalThis.backgroundError = chrome.runtime.lastError.message;
                        globalThis.backgroundErrorOccurred = true;
                    } else {
                        globalThis.backgroundResponse = response;
                        globalThis.backgroundErrorOccurred = false;
                    }
                    globalThis.backgroundCallbackCalled = true;
                });
            }
            
            globalThis.sendMessageWithNoListener = sendMessageWithNoListener;
            globalThis.backgroundScriptReady = true;
        """

        let backgroundScript = BackgroundScript(
            serviceWorker: "background.js",
            scripts: nil,
            persistent: nil,
            type: nil
        )

        let backgroundResource = BackgroundScriptResource(
            config: backgroundScript,
            jsContent: backgroundScriptContent,
            isServiceWorker: true
        )

        let manifest = ExtensionManifest(
            manifestVersion: 3,
            name: "No Listener Test Extension",
            version: "1.0.0",
            background: backgroundScript
        )

        let noListenerExtension = BrowserExtension(
            manifest: manifest,
            baseURL: URL(fileURLWithPath: "/tmp/no-listener-extension"),
            logger: logger
        )

        noListenerExtension.setBackgroundScriptResource(backgroundResource)
        return noListenerExtension
    }

    func testBackgroundScriptSendsMessageWithNoContentListener() async throws {
        print("qqq starting")
        let noListenerExtension = Self.makeNoListenerExtension(logger: mockLogger)
        print("qqq will call activate")
        // Activate the extension
        await activeManager.activate(noListenerExtension)
        
        // Wait for background script to initialize
        print("qqq: Waiting for no-listener background script to initialize")
        var backgroundReady = false
        for _ in 0..<50 {
            let ready = try await backgroundService.evaluateJavaScript("globalThis.backgroundScriptReady", in: noListenerExtension.id)
            if ready as? Bool == true {
                backgroundReady = true
                print("qqq: No-listener background script is ready")
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(backgroundReady, "Background script should be ready")
        
        // Trigger message from background (should fail)
        print("qqq: Triggering message from background with no listener")
        _ = try await backgroundService.evaluateJavaScript("sendMessageWithNoListener()", in: noListenerExtension.id)
        print("qqq: No-listener message trigger completed")

        // Wait for callback to be called
        print("qqq: Waiting for callback to be called")
        var callbackCalled = false
        for _ in 0..<50 {
            let called = try await backgroundService.evaluateJavaScript("globalThis.backgroundCallbackCalled", in: noListenerExtension.id)
            if called as? Bool == true {
                callbackCalled = true
                print("qqq: Background callback was called")
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(callbackCalled, "Background script callback should be called")
        
        // Verify error occurred
        let errorOccurred = try await backgroundService.evaluateJavaScript("globalThis.backgroundErrorOccurred", in: noListenerExtension.id)
        XCTAssertEqual(errorOccurred as? Bool, true, "Background script should have error when no listener")
        
        // Verify error message
        let errorMessage = try await backgroundService.evaluateJavaScript("globalThis.backgroundError", in: noListenerExtension.id)
        XCTAssertEqual(errorMessage as? String, "Could not establish connection. Receiving end does not exist.")
        
        // Clean up
        print("About to call deactivate")
        await activeManager.deactivate(noListenerExtension.id)
        print("Finished")
    }
}

// Console log handler for debugging
fileprivate class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("JS Console: \(message.body)")
    }
}
