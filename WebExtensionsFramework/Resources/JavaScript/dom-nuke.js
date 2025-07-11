(() => {
    'use strict';
    // dom-nuke.js
    // Get the proper global object reference
    const global = (function() {
        if (typeof globalThis !== 'undefined') return globalThis;
        if (typeof window !== 'undefined') return window;
        if (typeof global !== 'undefined') return global;
        if (typeof self !== 'undefined') return self;
        throw new Error('Unable to locate global object');
    })();
    
    // List of DOM globals to shadow (make undefined)
    const DOM_GLOBALS = [
        // Core DOM APIs
        'document', 'Document',
        'HTMLDocument', 'XMLDocument',
        
        // Element constructors
        'Element', 'HTMLElement', 'HTMLAnchorElement', 'HTMLButtonElement',
        'HTMLCanvasElement', 'HTMLDivElement', 'HTMLFormElement',
        'HTMLHeadElement', 'HTMLImageElement', 'HTMLInputElement',
        'HTMLLabelElement', 'HTMLLinkElement', 'HTMLMetaElement',
        'HTMLParagraphElement', 'HTMLScriptElement', 'HTMLSelectElement',
        'HTMLSpanElement', 'HTMLStyleElement', 'HTMLTableElement',
        'HTMLTextAreaElement', 'HTMLTitleElement', 'HTMLUListElement',
        
        // Event constructors and APIs
        'Event', 'CustomEvent', 'UIEvent', 'MouseEvent', 'KeyboardEvent',
        'TouchEvent', 'PointerEvent', 'WheelEvent', 'InputEvent',
        'FocusEvent', 'CompositionEvent', 'ClipboardEvent',
        'DragEvent', 'PopStateEvent', 'HashChangeEvent',
        'PageTransitionEvent', 'BeforeUnloadEvent', 'ErrorEvent',
        'ProgressEvent', 'MessageEvent', 'StorageEvent',
        'addEventListener', 'removeEventListener', 'dispatchEvent',
        
        // Node types
        'Node', 'Text', 'Comment', 'DocumentFragment',
        'Attr', 'CDATASection', 'ProcessingInstruction',
        'DocumentType', 'EntityReference', 'Entity', 'Notation',
        
        // CSS and styling
        'CSSStyleDeclaration', 'CSSRule', 'CSSStyleSheet',
        'getComputedStyle',
        
        // Deprecated/dangerous APIs
        'alert', 'confirm', 'prompt',
        'open', 'close', 'print',
        
        // Storage APIs that could leak data
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
