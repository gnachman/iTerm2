// BrowserExtensionBackgroundService.swift
// Background script service for running extension background scripts in hidden WKWebViews

import Foundation
import WebKit
import AppKit

/// Protocol for managing background script execution in extensions
@MainActor
public protocol BrowserExtensionBackgroundServiceProtocol {
    /// Start a background script for the given extension
    /// - Parameter browserExtension: The extension to start background script for
    /// - Throws: Error if background script cannot be started
    func startBackgroundScript(for browserExtension: BrowserExtension) async throws
    
    /// Stop background script for the given extension ID
    /// - Parameter extensionId: The extension ID to stop background script for
    func stopBackgroundScript(for extensionId: UUID)
    
    /// Stop all running background scripts
    func stopAllBackgroundScripts()
    
    /// Check if background script is active for the given extension ID
    /// - Parameter extensionId: The extension ID to check
    /// - Returns: True if background script is active
    func isBackgroundScriptActive(for extensionId: UUID) -> Bool
    
    /// Get list of extension IDs with active background scripts
    var activeBackgroundScriptExtensionIds: Set<UUID> { get }
    
    /// Evaluate JavaScript in a specific extension's background script context
    /// - Parameters:
    ///   - javascript: The JavaScript code to evaluate
    ///   - extensionId: The extension ID to evaluate in
    /// - Returns: The result of the JavaScript evaluation
    func evaluateJavaScript(_ javascript: String, in extensionId: UUID) async throws -> Any?
}

/// Implementation of background service that runs extension background scripts in hidden WKWebViews
@MainActor
public class BrowserExtensionBackgroundService: BrowserExtensionBackgroundServiceProtocol {
    
    /// Map of extension ID to background WKWebView
    private var backgroundWebViews: [UUID: WKWebView] = [:]
    
    /// Map of extension ID to navigation delegate (must keep strong reference)
    private var navigationDelegates: [UUID: BackgroundScriptNavigationDelegate] = [:]
    
    /// Map of extension ID to UI delegate (must keep strong reference)
    private var uiDelegates: [UUID: BackgroundScriptUIDelegate] = [:]
    
    /// Hidden container view for WKWebViews (must be in view hierarchy)
    private let hiddenContainer: NSView
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Whether to use ephemeral data store (for incognito mode)
    private let useEphemeralDataStore: Bool
    
    /// URL scheme handler for isolated extension origins
    private let urlSchemeHandler: BrowserExtensionURLSchemeHandler
    
    /// Initialize background service
    /// - Parameters:
    ///   - hiddenContainer: Hidden container view for WKWebViews
    ///   - logger: Logger for debugging and error reporting
    ///   - useEphemeralDataStore: Whether to use ephemeral data store
    ///   - urlSchemeHandler: URL scheme handler for isolated origins
    public init(hiddenContainer: NSView, logger: BrowserExtensionLogger, useEphemeralDataStore: Bool, urlSchemeHandler: BrowserExtensionURLSchemeHandler) {
        self.hiddenContainer = hiddenContainer
        self.logger = logger
        self.useEphemeralDataStore = useEphemeralDataStore
        self.urlSchemeHandler = urlSchemeHandler
    }
    
    public func startBackgroundScript(for browserExtension: BrowserExtension) async throws {
        let extensionId = browserExtension.id
        
        // Check if already running
        if backgroundWebViews[extensionId] != nil {
            logger.debug("Background script already running for extension: \(extensionId)")
            return
        }
        
        // Check if extension has background script
        guard let backgroundResource = browserExtension.backgroundScriptResource else {
            logger.debug("No background script for extension: \(extensionId)")
            return
        }
        
        logger.info("Starting background script for extension: \(extensionId)")
        
        // Create WKWebView configuration
        let configuration = WKWebViewConfiguration()
        
        // Each extension gets its own process pool for true isolation
        // This prevents cookie/cache/memory sharing between extensions
        configuration.processPool = WKProcessPool()
        
        // Disable JavaScript from opening windows automatically
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Register custom URL scheme handler for isolated origins
        configuration.setURLSchemeHandler(urlSchemeHandler, forURLScheme: BrowserExtensionURLSchemeHandler.scheme)
        
        // Set up data store (each extension gets its own isolated data store)
        if useEphemeralDataStore {
            // Each extension gets its own ephemeral data store for complete isolation
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            logger.debug("Using ephemeral data store for extension: \(extensionId)")
        } else {
            // Create a persistent data store with extension-specific identifier
            // This ensures each extension has completely separate storage
            if #available(macOS 14.0, *) {
                configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: extensionId)
                logger.debug("Using persistent data store with ID \(extensionId) for extension: \(extensionId)")
            } else {
                fatalError("Background script storage isolation requires macOS 14.0 or later")
            }
        }
        
        // Inject DOM nuke script in the page world to shadow DOM globals
        // Extension scripts will run in .defaultClient world for complete isolation
        let domNukeScript = generateDOMNukeScript()
        let nukeUserScript = WKUserScript(
            source: domNukeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        configuration.userContentController.addUserScript(nukeUserScript)
        
        // Inject extension background script in .defaultClient world for isolation
        if let backgroundResource = browserExtension.backgroundScriptResource {
            let backgroundUserScript = WKUserScript(
                source: backgroundResource.jsContent,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .defaultClient
            )
            configuration.userContentController.addUserScript(backgroundUserScript)
        }
        
        // Create hidden WKWebView
        let webView = WKWebView(frame: CGRect.zero, configuration: configuration)
        webView.isHidden = true
        
        // Add to hidden container (required for full functionality)
        hiddenContainer.addSubview(webView)
        
        // Store reference
        backgroundWebViews[extensionId] = webView
        
        // Register the background script with the URL scheme handler
        urlSchemeHandler.registerBackgroundScript(backgroundResource, for: extensionId)
        
        // Load the background page from custom scheme for isolated origin
        let backgroundURL = BrowserExtensionURLSchemeHandler.backgroundPageURL(for: extensionId)
        
        // Create security delegates that will persist for the lifetime of the WebView
        let navigationDelegate = BackgroundScriptNavigationDelegate(
            allowedURL: backgroundURL,
            logger: logger,
            extensionId: extensionId
        )
        let uiDelegate = BackgroundScriptUIDelegate(
            logger: logger,
            extensionId: extensionId
        )
        
        // Store strong references to delegates
        navigationDelegates[extensionId] = navigationDelegate
        uiDelegates[extensionId] = uiDelegate
        
        // Assign delegates to WebView
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate
        
        do {
            // Load the background page
            let request = URLRequest(url: backgroundURL)
            _ = webView.load(request)
            
            // Wait for navigation to complete with cancellation support
            try await withTaskCancellationHandler {
                try await navigationDelegate.waitForLoad()
            } onCancel: {
                // Cancel the navigation if the Task is cancelled
                Task { @MainActor in
                    webView.stopLoading()
                }
            }
        } catch {
            // Clean up if loading fails to prevent resource leaks
            stopBackgroundScript(for: extensionId)
            throw error
        }
        
        logger.info("Background script loaded for: \(extensionId)")
    }
    
    public func stopBackgroundScript(for extensionId: UUID) {
        guard let webView = backgroundWebViews[extensionId] else {
            logger.debug("No background script running for extension: \(extensionId)")
            return
        }
        
        logger.info("Stopping background script for extension: \(extensionId)")
        
        // Cancel any in-flight navigation to prevent 404 errors
        webView.stopLoading()
        
        // Clear delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        
        // Remove from container
        webView.removeFromSuperview()
        
        // Unregister from URL scheme handler
        urlSchemeHandler.unregisterBackgroundScript(for: extensionId)
        
        // Remove all references
        backgroundWebViews.removeValue(forKey: extensionId)
        navigationDelegates.removeValue(forKey: extensionId)
        uiDelegates.removeValue(forKey: extensionId)
        
        logger.debug("Background script stopped for extension: \(extensionId)")
    }
    
    public func stopAllBackgroundScripts() {
        logger.info("Stopping all background scripts")
        
        let extensionIds = Array(backgroundWebViews.keys)
        for extensionId in extensionIds {
            stopBackgroundScript(for: extensionId)
        }
        
        logger.debug("All background scripts stopped")
    }
    
    public func isBackgroundScriptActive(for extensionId: UUID) -> Bool {
        return backgroundWebViews[extensionId] != nil
    }
    
    public var activeBackgroundScriptExtensionIds: Set<UUID> {
        return Set(backgroundWebViews.keys)
    }
    
    public func evaluateJavaScript(_ javascript: String, in extensionId: UUID) async throws -> Any? {
        guard let webView = backgroundWebViews[extensionId] else {
            throw NSError(domain: "BrowserExtensionBackgroundService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No background script running for extension: \(extensionId)"
            ])
        }
        
        // Evaluate in .defaultClient world to match where extension scripts execute
        // (DOM nuke script runs in .page world, so they're isolated)
        return try await webView.evaluateJavaScript(javascript, in: nil, contentWorld: .defaultClient)
    }
    
    /// Generate DOM nuke script to remove DOM globals from background script context
    private func generateDOMNukeScript() -> String {
        return """
        (() => {
            'use strict';
            
            // Get the proper global object reference
            const global = (function() {
                if (typeof globalThis !== 'undefined') return globalThis;
                if (typeof window !== 'undefined') return window;
                if (typeof global !== 'undefined') return global;
                if (typeof self !== 'undefined') return self;
                throw new Error('Unable to locate global object');
            })();
            
            // List of DOM-related globals to remove
            const DOM_GLOBALS = [
                // Core DOM objects (but not 'window' itself as we need it for the global reference)
                'document', 'Document',
                'HTMLDocument', 'XMLDocument',
                
                // Element constructors
                'HTMLElement', 'Element', 'Node', 'Text', 'Comment',
                'DocumentFragment', 'DocumentType', 'ProcessingInstruction',
                'CharacterData', 'Attr', 'CDATASection',
                
                // HTML Element constructors
                'HTMLDivElement', 'HTMLSpanElement', 'HTMLButtonElement',
                'HTMLInputElement', 'HTMLFormElement', 'HTMLAnchorElement',
                'HTMLImageElement', 'HTMLCanvasElement', 'HTMLVideoElement',
                'HTMLAudioElement', 'HTMLScriptElement', 'HTMLStyleElement',
                'HTMLLinkElement', 'HTMLMetaElement', 'HTMLHeadElement',
                'HTMLBodyElement', 'HTMLHtmlElement', 'HTMLTableElement',
                'HTMLTableRowElement', 'HTMLTableCellElement', 'HTMLParagraphElement',
                'HTMLBRElement', 'HTMLHRElement', 'HTMLLIElement', 'HTMLUListElement',
                'HTMLOListElement', 'HTMLPreElement', 'HTMLTextAreaElement',
                'HTMLSelectElement', 'HTMLOptionElement', 'HTMLOptGroupElement',
                'HTMLFieldSetElement', 'HTMLLegendElement', 'HTMLLabelElement',
                
                // SVG Elements
                'SVGElement', 'SVGGraphicsElement', 'SVGSVGElement',
                
                // Events (constructors only, not the base Event)
                'UIEvent', 'MouseEvent', 'KeyboardEvent', 'TouchEvent',
                'WheelEvent', 'InputEvent', 'FocusEvent', 'CompositionEvent',
                'CustomEvent', 'AnimationEvent', 'TransitionEvent',
                
                // UI/Browser APIs
                'alert', 'confirm', 'prompt',
                'open', 'print', 'stop',
                'focus', 'blur', 'close',
                
                // Selection and Range
                'Selection', 'Range', 'getSelection',
                
                // Parser
                'DOMParser', 'XMLSerializer',
                
                // Observers
                'MutationObserver', 'IntersectionObserver', 'ResizeObserver',
                
                // Storage (legacy - encourage chrome.storage)
                'localStorage', 'sessionStorage', 'Storage',
                
                // Other DOM APIs
                'history', 'History',
                'location', 'Location',
                'navigator', 'Navigator',
                'screen', 'Screen',
                
                // Forms
                'FormData',
                
                // Media
                'MediaQueryList', 'matchMedia',
                
                // CSSOM
                'CSSStyleDeclaration', 'CSSRule', 'CSSStyleSheet',
                'getComputedStyle',
                
                // Performance (DOM-related parts)
                'PerformanceNavigation', 'PerformanceTiming',
                
                // Frames
                'frames', 'frameElement', 'parent', 'top',
                
                // Scrolling
                'scrollTo', 'scrollBy', 'scroll',
                'scrollX', 'scrollY', 'pageXOffset', 'pageYOffset',
                
                // Dimensions
                'innerWidth', 'innerHeight', 'outerWidth', 'outerHeight',
                'screenX', 'screenY', 'screenLeft', 'screenTop',
                
                // Device
                'devicePixelRatio',
                
                // Base64
                'atob', 'btoa',
                
                // Timers (keep setTimeout/setInterval as they're needed)
                'requestAnimationFrame', 'cancelAnimationFrame',
                
                // Workers (DOM-related)
                'Worker', 'SharedWorker', 'DedicatedWorkerGlobalScope', 'importScripts',
                
                // Broadcast APIs
                'BroadcastChannel', 'MessageChannel', 'MessagePort',
                
                // Server-Sent Events
                'EventSource',
                
                // Gamepad
                'Gamepad', 'GamepadButton', 'GamepadEvent',
                
                // WebGL
                'WebGLRenderingContext', 'WebGL2RenderingContext',
                
                // XHR (legacy - encourage fetch)
                'XMLHttpRequest', 'XMLHttpRequestEventTarget', 'XMLHttpRequestUpload'
            ];
            
            // Shadow each DOM global by defining an own property
            // This works for both own properties and inherited properties from prototype chain
            DOM_GLOBALS.forEach(name => {
                if (name in global) {
                    try {
                        // Shadow the property with undefined, making it truly inaccessible
                        Object.defineProperty(global, name, {
                            value: undefined,
                            writable: false,
                            configurable: true,
                            enumerable: false
                        });
                    } catch (e) {
                        // If we can't define the property, try setting it directly
                        try {
                            global[name] = undefined;
                        } catch (e2) {
                            // If we can't override it, leave it alone
                        }
                    }
                }
            });
            
            // Special handling for window since window === globalThis in WKWebView
            // We want to shadow window but NOT globalThis itself, as extension scripts need globalThis
            try {
                Object.defineProperty(global, 'window', {
                    value: undefined,
                    writable: false,
                    configurable: true,
                    enumerable: false
                });
            } catch (e) {}
            
            // Don't shadow globalThis itself - extensions need access to it for their own globals
            
            // Set up service worker-like environment
            // Keep 'self' pointing to global for compatibility
            if (!global.self) {
                global.self = global;
            }
            
            // Add minimal registration object for service worker compatibility
            if (!global.registration) {
                global.registration = {
                    scope: '/',
                    active: null,
                    installing: null,
                    waiting: null,
                    updateViaCache: 'none'
                };
            }
            
            // Ensure critical APIs remain available:
            // - globalThis, self
            // - console, Math, JSON, Object, Array, String, Number, Boolean, Symbol, BigInt
            // - Promise, Error, TypeError, ReferenceError, etc.
            // - fetch, Request, Response, Headers, URL, URLSearchParams
            // - crypto, TextEncoder, TextDecoder
            // - setTimeout, setInterval, clearTimeout, clearInterval
            // - queueMicrotask, structuredClone
            // - AbortController, AbortSignal
            // - Event, EventTarget (base classes needed for chrome.runtime events)
            // - WebSocket
            // - indexedDB
            // - caches (Cache API)
            
            // Set debug marker
            global.__domNukeExecuted = true;
            
        })();
        """
    }
}

/// Navigation delegate that uses async/await for page load completion
/// and provides security by blocking all navigation except the initial background page
private class BackgroundScriptNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private let allowedURL: URL
    private let logger: BrowserExtensionLogger
    private let extensionId: UUID
    
    init(allowedURL: URL, logger: BrowserExtensionLogger, extensionId: UUID) {
        self.allowedURL = allowedURL
        self.logger = logger
        self.extensionId = extensionId
        super.init()
    }
    
    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            // WK callbacks always come on main thread, so no locking needed
            self.continuation = continuation
        }
    }
    
    // Only allow the initial background page URL
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            logger.error("Navigation blocked - no URL for extension: \(extensionId)")
            decisionHandler(.cancel)
            return
        }
        
        // Block redirects explicitly
        if navigationAction.navigationType == .other && url != allowedURL {
            logger.error("Navigation blocked - redirect to unauthorized URL: \(url) (extension: \(extensionId))")
            decisionHandler(.cancel)
            return
        }
        
        if url == allowedURL {
            logger.debug("Navigation allowed for background page: \(url) (extension: \(extensionId))")
            decisionHandler(.allow)
        } else {
            logger.error("Navigation blocked to unauthorized URL: \(url) (extension: \(extensionId))")
            decisionHandler(.cancel)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// UI delegate that blocks all UI interactions from background scripts
private class BackgroundScriptUIDelegate: NSObject, WKUIDelegate {
    private let logger: BrowserExtensionLogger
    private let extensionId: UUID
    
    init(logger: BrowserExtensionLogger, extensionId: UUID) {
        self.logger = logger
        self.extensionId = extensionId
        super.init()
    }
    
    // Block all attempts to create new windows/tabs
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        logger.error("Blocked attempt to create new window from background script (extension: \(extensionId))")
        return nil
    }
    
    // Block all JavaScript alerts
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        logger.error("Blocked JavaScript alert from background script: '\(message)' (extension: \(extensionId))")
        completionHandler()
    }
    
    // Block all JavaScript confirms
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        logger.error("Blocked JavaScript confirm from background script: '\(message)' (extension: \(extensionId))")
        completionHandler(false)
    }
    
    // Block all JavaScript prompts
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        logger.error("Blocked JavaScript prompt from background script: '\(prompt)' (extension: \(extensionId))")
        completionHandler(nil)
    }
    
    // Block file open panels
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        logger.error("Blocked file open panel from background script (extension: \(extensionId))")
        completionHandler(nil)
    }
    
    // Note: Context menu blocking would require newer WKUIDelegate methods
    // The main security threats (window.open, navigation, dialogs, file access) are covered above
}
