import Foundation
import WebKit
import AppKit

/// Factory for creating configured WKWebViews for extension contexts
@MainActor
public class BrowserExtensionWebViewFactory {
    
    public enum WebViewType {
        case backgroundScript  // Service worker context - no DOM, no window interactions
        case popup            // Extension popup UI - interactive, can open windows
        case test             // Clean test environment
    }
    
    /// Configuration for creating extension WebViews
    public struct Configuration {
        public let extensionId: String
        public let logger: BrowserExtensionLogger
        public let urlSchemeHandler: BrowserExtensionURLSchemeHandler
        public let hiddenContainer: NSView
        public let useEphemeralDataStore: Bool
        
        public init(
            extensionId: String,
            logger: BrowserExtensionLogger,
            urlSchemeHandler: BrowserExtensionURLSchemeHandler,
            hiddenContainer: NSView,
            useEphemeralDataStore: Bool = false
        ) {
            self.extensionId = extensionId
            self.logger = logger
            self.urlSchemeHandler = urlSchemeHandler
            self.hiddenContainer = hiddenContainer
            self.useEphemeralDataStore = useEphemeralDataStore
        }
    }
    
    /// Create a configured WKWebView for the specified type
    public static func createWebView(
        type: WebViewType,
        configuration: Configuration
    ) throws -> WKWebView {
        let webViewConfiguration = try createWebViewConfiguration(
            type: type,
            configuration: configuration
        )
        
        let webView = WKWebView(frame: CGRect.zero, configuration: webViewConfiguration)
        
        // Background scripts and test webviews are hidden, popups are visible
        switch type {
        case .backgroundScript, .test:
            webView.isHidden = true
            // Add to hidden container (required for full functionality)
            configuration.hiddenContainer.addSubview(webView)
            webView.frame = configuration.hiddenContainer.bounds
        case .popup:
            webView.isHidden = false
            // Popup webviews will be added to visible UI later
        }
        
        return webView
    }
    
    private static func createWebViewConfiguration(
        type: WebViewType,
        configuration: Configuration
    ) throws -> WKWebViewConfiguration {
        let webViewConfiguration = WKWebViewConfiguration()
        
        // Each extension gets its own process pool for true isolation
        // This prevents cookie/cache/memory sharing between extensions
        webViewConfiguration.processPool = WKProcessPool()
        
        // Configure JavaScript window opening behavior based on type
        switch type {
        case .backgroundScript:
            // Background scripts should not open windows
            webViewConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
        case .popup:
            // Popups are interactive UI and may need to open windows
            webViewConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = true
        case .test:
            // Test environments should not open windows
            webViewConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        
        // Register custom URL scheme handler for isolated origins
        webViewConfiguration.setURLSchemeHandler(
            configuration.urlSchemeHandler,
            forURLScheme: BrowserExtensionURLSchemeHandler.scheme
        )
        
        // Set up data store
        try setupDataStore(webViewConfiguration, configuration: configuration)
        
        // Set up user scripts based on type
        try setupUserScripts(webViewConfiguration, type: type, configuration: configuration)
        
        return webViewConfiguration
    }
    
    private static func setupDataStore(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        if configuration.useEphemeralDataStore {
            // Each extension gets its own ephemeral data store for complete isolation
            webViewConfiguration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            configuration.logger.debug("Using ephemeral data store for extension: \(configuration.extensionId)")
        } else {
            // Create a persistent data store with extension-specific identifier
            // This ensures each extension has completely separate storage
            if #available(macOS 14.0, *) {
                webViewConfiguration.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: configuration.extensionId) ?? UUID())
                configuration.logger.debug("Using persistent data store for extension: \(configuration.extensionId)")
            } else {
                fatalError("Extension storage isolation requires macOS 14.0 or later")
            }
        }
    }
    
    private static func setupUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        type: WebViewType,
        configuration: Configuration
    ) throws {
        switch type {
        case .backgroundScript:
            try setupBackgroundScriptUserScripts(webViewConfiguration, configuration: configuration)
        case .popup:
            try setupPopupUserScripts(webViewConfiguration, configuration: configuration)
        case .test:
            try setupTestUserScripts(webViewConfiguration, configuration: configuration)
        }
    }
    
    private static func setupBackgroundScriptUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        // Inject DOM nuke script in both worlds for defense in depth
        let domNukeScript = generateDOMNukeScript()
        
        // Add to .page world
        let nukeUserScriptPage = WKUserScript(
            source: domNukeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        webViewConfiguration.userContentController.addUserScript(nukeUserScriptPage)
        
        // Add to .defaultClient world
        let nukeUserScriptClient = WKUserScript(
            source: domNukeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .defaultClient
        )
        webViewConfiguration.userContentController.addUserScript(nukeUserScriptClient)
        
        // Add console.log override script in .page world
        let consoleOverrideScript = generateConsoleOverrideScript()
        let consoleOverrideUserScript = WKUserScript(
            source: consoleOverrideScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        webViewConfiguration.userContentController.addUserScript(consoleOverrideUserScript)
    }
    
    private static func setupPopupUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        // Popups are interactive UI - they need access to DOM APIs
        // Only inject console override for logging
        let consoleOverrideScript = generateConsoleOverrideScript()
        let consoleOverrideUserScript = WKUserScript(
            source: consoleOverrideScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        webViewConfiguration.userContentController.addUserScript(consoleOverrideUserScript)
    }
    
    private static func setupTestUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        // Test scripts need a clean environment without DOM nuke or console override
        // This allows tests to have full control over the environment
    }
    
    /// Generate DOM nuke script to remove DOM globals from background script context
    private static func generateDOMNukeScript() -> String {
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
                
                // Storage APIs (extensions should use chrome.storage instead)
                'localStorage', 'sessionStorage',
                
                // Selection and Range
                'Selection', 'Range', 'getSelection',
                
                // Parser
                'DOMParser', 'XMLSerializer',
                
                // Observers
                'MutationObserver', 'IntersectionObserver', 'ResizeObserver',
                
                // Other DOM APIs
                'history', 'History',
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
            DOM_GLOBALS.forEach(name => {
                if (name in global) {
                    try {
                        Object.defineProperty(global, name, {
                            value: undefined,
                            writable: false,
                            configurable: true,
                            enumerable: false
                        });
                    } catch (e) {
                        try {
                            global[name] = undefined;
                        } catch (e2) {
                            // If we can't override it, leave it alone
                        }
                    }
                }
            });
            
            // Special handling for window since window === globalThis in WKWebView
            try {
                Object.defineProperty(global, 'window', {
                    value: undefined,
                    writable: false,
                    configurable: true,
                    enumerable: false
                });
            } catch (e) {}
            
            // Set up service worker-like environment
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
            
            // Set debug marker
            global.__domNukeExecuted = true;
            
        })();
        """
    }
    
    /// Generate console override script that overrides console.log to send messages to Swift
    private static func generateConsoleOverrideScript() -> String {
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
            
            // Store original console methods
            const originalConsole = global.console || {};
            const originalLog = originalConsole.log || function() {};
            
            // Override console.log to send messages to .page world
            global.console = global.console || {};
            global.console.log = function(...args) {
                // Call original console.log first (for debugging in Web Inspector)
                try {
                    originalLog.apply(originalConsole, args);
                } catch (e) {
                    // Ignore errors from original console.log
                }
                
                // Send to Swift via webkit.messageHandlers
                try {
                    const message = args.map(arg => {
                        if (typeof arg === 'string') {
                            return arg;
                        } else if (arg === null) {
                            return 'null';
                        } else if (arg === undefined) {
                            return 'undefined';
                        } else {
                            try {
                                return JSON.stringify(arg);
                            } catch (e) {
                                return String(arg);
                            }
                        }
                    }).join(' ');
                    
                    // Send directly to Swift via webkit.messageHandlers
                    if (typeof webkit !== 'undefined' && 
                        webkit.messageHandlers && 
                        webkit.messageHandlers.consoleLog) {
                        webkit.messageHandlers.consoleLog.postMessage(message);
                    }
                } catch (e) {
                    // Ignore errors when sending to Swift
                }
            };
            
            // Preserve other console methods
            ['debug', 'info', 'warn', 'error', 'trace', 'dir', 'dirxml', 'group', 'groupEnd', 'time', 'timeEnd', 'assert', 'clear'].forEach(method => {
                if (originalConsole[method] && !global.console[method]) {
                    global.console[method] = originalConsole[method];
                }
            });
            
        })();
        """
    }
}