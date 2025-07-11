(() => {
    'use strict';
    // console-override.js
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
            // Check for webkit.messageHandlers availability more robustly
            if (typeof webkit === 'undefined' || 
                !webkit || 
                !webkit.messageHandlers || 
                typeof webkit.messageHandlers.consoleLog === 'undefined') {
                // webkit.messageHandlers not available, skip sending to Swift
                return;
            }
            
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
                    } catch (jsonError) {
                        // Fallback to String() if JSON.stringify fails
                        try {
                            return String(arg);
                        } catch (stringError) {
                            return '[object Object]';
                        }
                    }
                }
            }).join(' ');
            
            // Additional safety check before sending
            if (typeof webkit.messageHandlers.consoleLog.postMessage === 'function') {
                webkit.messageHandlers.consoleLog.postMessage(message);
            }
        } catch (e) {
            // Silently ignore errors when sending to Swift to prevent console.log from breaking
            // This could happen if webkit.messageHandlers becomes unavailable during execution
        }
    };
    
    // Preserve other console methods
    ['debug', 'info', 'warn', 'error', 'trace', 'dir', 'dirxml', 'group', 'groupEnd', 'time', 'timeEnd', 'assert', 'clear'].forEach(method => {
        if (originalConsole[method] && !global.console[method]) {
            global.console[method] = originalConsole[method];
        }
    });
    
})();
