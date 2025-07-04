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
    func stopBackgroundScript(for extensionId: String)
    
    /// Stop all running background scripts
    func stopAllBackgroundScripts()
    
    /// Check if background script is active for the given extension ID
    /// - Parameter extensionId: The extension ID to check
    /// - Returns: True if background script is active
    func isBackgroundScriptActive(for extensionId: String) -> Bool
    
    /// Get list of extension IDs with active background scripts
    var activeBackgroundScriptExtensionIds: Set<String> { get }
    
    /// Evaluate JavaScript in a specific extension's background script context
    /// - Parameters:
    ///   - javascript: The JavaScript code to evaluate
    ///   - extensionId: The extension ID to evaluate in
    /// - Returns: The result of the JavaScript evaluation
    func evaluateJavaScript(_ javascript: String, in extensionId: String) async throws -> Any?
}

/// Implementation of background service that runs extension background scripts in hidden WKWebViews
@MainActor
public class BrowserExtensionBackgroundService: BrowserExtensionBackgroundServiceProtocol {
    
    /// Map of extension ID to background WKWebView
    private var backgroundWebViews: [String: WKWebView] = [:]
    
    /// Hidden container view for WKWebViews (must be in view hierarchy)
    private let hiddenContainer: NSView
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Whether to use ephemeral data store (for incognito mode)
    private let useEphemeralDataStore: Bool
    
    /// Initialize background service
    /// - Parameters:
    ///   - hiddenContainer: Hidden container view for WKWebViews
    ///   - logger: Logger for debugging and error reporting
    ///   - useEphemeralDataStore: Whether to use ephemeral data store
    public init(hiddenContainer: NSView, logger: BrowserExtensionLogger, useEphemeralDataStore: Bool = false) {
        self.hiddenContainer = hiddenContainer
        self.logger = logger
        self.useEphemeralDataStore = useEphemeralDataStore
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
        
        // Set up data store (ephemeral or persistent)
        if useEphemeralDataStore {
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            logger.debug("Using ephemeral data store for extension: \(extensionId)")
        } else {
            configuration.websiteDataStore = WKWebsiteDataStore.default()
            logger.debug("Using persistent data store for extension: \(extensionId)")
        }
        
        // DOM nuke script will be injected as part of the HTML to ensure proper execution order
        
        // Create hidden WKWebView
        let webView = WKWebView(frame: CGRect.zero, configuration: configuration)
        webView.isHidden = true
        
        // Add to hidden container (required for full functionality)
        hiddenContainer.addSubview(webView)
        
        // Store reference
        backgroundWebViews[extensionId] = webView
        
        // Create a simple HTML page and inject the script directly
        // TODO: Re-enable DOM nuke script after fixing execution issues
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Background Script</title>
        </head>
        <body>
            <script>
            \(backgroundResource.jsContent)
            </script>
        </body>
        </html>
        """
        
        // Load the HTML
        _ = webView.loadHTMLString(html, baseURL: browserExtension.baseURL)
        
        // Ensure the HTML has loaded and scripts can execute
        // This forces the WebView to process the HTML and be ready for script execution
        _ = try? await webView.evaluateJavaScript("1 + 1")
        
        logger.info("Background script loaded for: \(extensionId)")
    }
    
    public func stopBackgroundScript(for extensionId: String) {
        guard let webView = backgroundWebViews[extensionId] else {
            logger.debug("No background script running for extension: \(extensionId)")
            return
        }
        
        logger.info("Stopping background script for extension: \(extensionId)")
        
        // Remove from container
        webView.removeFromSuperview()
        
        // Remove reference
        backgroundWebViews.removeValue(forKey: extensionId)
        
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
    
    public func isBackgroundScriptActive(for extensionId: String) -> Bool {
        return backgroundWebViews[extensionId] != nil
    }
    
    public var activeBackgroundScriptExtensionIds: Set<String> {
        return Set(backgroundWebViews.keys)
    }
    
    public func evaluateJavaScript(_ javascript: String, in extensionId: String) async throws -> Any? {
        guard let webView = backgroundWebViews[extensionId] else {
            throw NSError(domain: "BrowserExtensionBackgroundService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No background script running for extension: \(extensionId)"
            ])
        }
        
        return try await webView.evaluateJavaScript(javascript)
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
                'Worker', 'SharedWorker',
                
                // Gamepad
                'Gamepad', 'GamepadButton', 'GamepadEvent',
                
                // WebGL
                'WebGLRenderingContext', 'WebGL2RenderingContext',
                
                // XHR (legacy - encourage fetch)
                'XMLHttpRequest', 'XMLHttpRequestEventTarget', 'XMLHttpRequestUpload'
            ];
            
            // Remove each DOM global
            DOM_GLOBALS.forEach(name => {
                if (name in global) {
                    try {
                        const descriptor = Object.getOwnPropertyDescriptor(global, name);
                        
                        // Only override if it's configurable
                        if (!descriptor || descriptor.configurable) {
                            Object.defineProperty(global, name, {
                                get() { 
                                    // Return undefined instead of null to match natural behavior
                                    return undefined;
                                },
                                set() {
                                    // Silently ignore attempts to set
                                },
                                enumerable: false,
                                configurable: true
                            });
                        }
                    } catch (e) {
                        // Some properties might throw when accessed
                        try {
                            global[name] = undefined;
                        } catch (e2) {
                            // If we can't remove it, leave it alone
                        }
                    }
                }
            });
            
            // Also remove any DOM properties from window/global that might not be in our list
            try {
                if (global.window && global.window !== global) {
                    Object.defineProperty(global, 'window', {
                        get() { return undefined; },
                        set() {},
                        enumerable: false,
                        configurable: true
                    });
                }
            } catch (e) {}
            
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
            
        })();
        """
    }
}