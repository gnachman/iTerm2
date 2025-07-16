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
    
    func testBackgroundScriptCannotSendMessageToContentScriptInMV3() async throws {
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
                            
                            // In MV3, this listener should never be called from background scripts
                            assertTrue(false, 'Content script should not receive messages from background service workers in MV3');
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
                    \(testRunner.javascriptCreatingPromise(name: backgroundReceivedResponse))
                    
                    (async function() {
                        console.log('Background script started');
                        
                        // Wait a bit for content script to be ready
                        await new Promise(resolve => setTimeout(resolve, 1000));
                        
                        console.log('Background script attempting to send message to content script (should fail in MV3)');
                        chrome.runtime.sendMessage({
                            type: 'background_to_content',
                            message: 'This should not reach content scripts in MV3'
                        }, (response) => {
                            console.log('Background script callback called');
                            // In MV3, background scripts cannot send to content scripts
                            assertTrue(chrome.runtime.lastError !== undefined, 'Background script should get error when trying to send to content script');
                            assertTrue(chrome.runtime.lastError.message.includes('Could not establish connection') || 
                                      chrome.runtime.lastError.message.includes('Receiving end does not exist'), 
                                      'Error message should indicate no eligible receivers');
                            globalThis.backgroundError = chrome.runtime.lastError.message;
                            \(testRunner.javascriptResolvingPromise(name: backgroundReceivedResponse))
                            \(testRunner.expectReach("background received MV3 restriction error"))
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
        
        // Wait for message processing (content script should not receive anything in MV3)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundMessageSent)
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
    
    func testBackgroundScriptCannotSendNullMessageToContentScriptInMV3() async throws {
        let backgroundMessageSent = "BackgroundNullMessageSent"
        let contentMessageReceived = "ContentNullMessageReceived"
        let backgroundReceivedResponse = "BackgroundReceivedNullResponse"
        let contentReady = "ContentNullReady"
        
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentMessageReceived))
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    
                    (async function() {
                        console.log('Content script setting up message listener for null message');
                        // Set up message listener in content script
                        chrome.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                            console.log('Content script received message:', message);
                            console.log('Message sender:', sender);
                            
                            // In MV3, this listener should never be called from background scripts
                            assertTrue(false, 'Content script should not receive messages from background service workers in MV3');
                            return true;
                        });
                        
                        console.log('Content script listener ready for null message');
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
                        console.log('Background script started - sending null message');
                        
                        // Wait a bit for content script to be ready
                        await new Promise(resolve => setTimeout(resolve, 1000));
                        
                        console.log('Background script attempting to send null message to content script (should fail in MV3)');
                        chrome.runtime.sendMessage(null, (response) => {
                            console.log('Background script callback called');
                            // In MV3, background scripts cannot send to content scripts
                            assertTrue(chrome.runtime.lastError !== undefined, 'Background script should get error when trying to send to content script');
                            assertTrue(chrome.runtime.lastError.message.includes('Could not establish connection') || 
                                      chrome.runtime.lastError.message.includes('Receiving end does not exist'), 
                                      'Error message should indicate no eligible receivers');
                            globalThis.backgroundError = chrome.runtime.lastError.message;
                            \(testRunner.javascriptResolvingPromise(name: backgroundReceivedResponse))
                            \(testRunner.expectReach("background received MV3 restriction error for null message"))
                        });
                        \(testRunner.javascriptResolvingPromise(name: backgroundMessageSent))
                        \(testRunner.expectReach("background sent null message"))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        
        // Create an untrusted webview for content script
        let (contentWebView, _) = try await testRunner.createUntrustedWebView(for: .contentScript)
        try await contentWebView.loadHTMLStringAsync("<html><body>Test Page for Null Message</body></html>", baseURL: nil)
        
        // Wait for content script to be ready
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentReady)
        
        // Wait for message processing (content script should not receive anything in MV3)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundMessageSent)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundReceivedResponse)
        
        testRunner.verifyAssertions()
    }
}
