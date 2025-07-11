//
//  BackgroundToContentMessagingTests.swift
//  WebExtensionsFramework
//
//  Created by Assistant on 7/8/25.
//

import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class BackgroundToContentMessagingTests: XCTestCase {
    
    var testRunner: ExtensionTestingInfrastructure.TestRunner!
    
    override func setUp() async throws {
        testRunner = ExtensionTestingInfrastructure.TestRunner(verbose: false)
    }
    
    override func tearDown() async throws {
        testRunner = nil
    }
    
    // MARK: - Integration Tests
    
    func testBackgroundScriptSendsMessageToContentScript() async throws {
        let backgroundMessageSent = "BackgroundMessageSent"
        let contentMessageReceived = "ContentMessageReceived"
        let backgroundReceivedResponse = "BackgroundReceivedResponse"
        let contentReady = "ContentReady"
        
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentMessageReceived))
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    
                    (async function() {
                        console.log('Content script setting up message listener');
                        
                        // Set up message listener in content script
                        chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                            console.log('Content script received message:', message);
                            console.log('Message sender:', sender);
                            
                            if (message.type === 'background_to_content') {
                                assertTrue(message.message === 'Hello from background script!', 'Message content should match expected');
                                assertTrue(typeof message.timestamp === 'number', 'Timestamp should be a number');
                                
                                // Store the received message for testing
                                globalThis.receivedMessage = message;
                                
                                // Send response back to background script
                                sendResponse({
                                    success: true,
                                    reply: 'Hello back from content script!',
                                    originalMessage: message.message
                                });
                                
                                \(testRunner.javascriptResolvingPromise(name: contentMessageReceived))
                                \(testRunner.expectReach("content received message"))
                                return true; // Keep message channel open
                            }
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
                    \(testRunner.javascriptCreatingPromise(name: backgroundReceivedResponse))
                    
                    (async function() {
                        console.log('Background script started');
                        
                        // Wait a bit for content script to be ready
                        await new Promise(resolve => setTimeout(resolve, 1000));
                        
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
                                assertTrue(response !== undefined, 'Response should not be undefined');
                                assertEqual(response.success, true, 'Response success should be true');
                                assertEqual(response.reply, 'Hello back from content script!', 'Response reply should match expected');
                                assertEqual(response.originalMessage, 'Hello from background script!', 'Original message should be echoed back');
                                globalThis.backgroundResponse = response;
                            }
                            \(testRunner.javascriptResolvingPromise(name: backgroundReceivedResponse))
                            \(testRunner.expectReach("background received response"))
                        });
                        \(testRunner.javascriptResolvingPromise(name: backgroundMessageSent))
                        \(testRunner.expectReach("background sent message"))
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
        
        // Wait for message processing
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundMessageSent)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentMessageReceived)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundReceivedResponse)
        
        testRunner.verifyAssertions()
    }

    func testBackgroundScriptSendsMessageWithNoContentListener() async throws {
        let callbackCalled = "CallbackCalled"
        
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: callbackCalled))
                    
                    (async function() {
                        console.log('Background script started');
                        
                        // Send message to content script (no listener)
                        console.log('Background script sending message with no listener');
                        chrome.runtime.sendMessage({
                            type: 'no_listener_test',
                            message: 'This should fail'
                        }, (response) => {
                            console.log('Background script callback called');
                            assertTrue(chrome.runtime.lastError !== undefined, 'There should be an error when no listener exists');
                            assertEqual(chrome.runtime.lastError.message, 'Could not establish connection. Receiving end does not exist.', 'Error message should match expected');
                            globalThis.backgroundError = chrome.runtime.lastError.message;
                            globalThis.backgroundErrorOccurred = true;
                            \(testRunner.javascriptResolvingPromise(name: callbackCalled))
                            \(testRunner.expectReach("callback with error"))
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        
        // Wait for callback to be called
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: callbackCalled)
        
        testRunner.verifyAssertions()
    }
}