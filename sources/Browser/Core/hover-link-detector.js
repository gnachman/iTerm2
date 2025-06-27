// hover-link-detector.js
// JavaScript bridge for detecting link hovers in WKWebView
// Uses event delegation for efficient tracking of mouseover/mouseout events

(function() {
    'use strict';
    try {
        // Generate a cryptographically secure random token for this session
        const sessionSecret = "{{SECRET}}";
        
        let currentHoverURL = null;
        let lastMouseX = 0;
        let lastMouseY = 0;
        
        // Find the closest link element
        function findLinkElement(element) {
            while (element && element !== document.body) {
                if (element.tagName === 'A' && element.href) {
                    return element;
                }
                if (element.tagName === 'AREA' && element.href) {
                    return element;
                }
                element = element.parentElement;
            }
            return null;
        }
        
        // Send hover info to native code
        function sendHoverInfo(url, rect) {
            if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.iTermHoverLink) {
                return;
            }
            
            try {
                // getBoundingClientRect() gives viewport coordinates, which is what we want
                // No need to subtract scroll position since we want coordinates relative to the visible area
                window.webkit.messageHandlers.iTermHoverLink.postMessage({
                    type: url ? 'hover' : 'clear',
                    url: url,
                    x: rect ? rect.left : 0,
                    y: rect ? rect.top : 0,
                    width: rect ? rect.width : 0,
                    height: rect ? rect.height : 0,
                    sessionSecret: sessionSecret
                });
            } catch (error) {
                console.warn('Failed to send hover message to native:', error);
            }
        }
        
        // Handle mouseover events
        function handleMouseOver(event) {
            lastMouseX = event.clientX;
            lastMouseY = event.clientY;
            const linkElement = findLinkElement(event.target);
            if (linkElement && linkElement.href) {
                const url = linkElement.href;
                if (currentHoverURL !== url) {
                    currentHoverURL = url;
                    const rect = linkElement.getBoundingClientRect();
                    sendHoverInfo(url, rect);
                }
            }
        }
        
        // Handle mouseout events
        function handleMouseOut(event) {
            const linkElement = findLinkElement(event.target);
            if (linkElement && linkElement.href === currentHoverURL) {
                // Check if we're really leaving the link (not just moving to a child element)
                const relatedTarget = event.relatedTarget;
                if (!relatedTarget || !linkElement.contains(relatedTarget)) {
                    currentHoverURL = null;
                    sendHoverInfo(null, null);
                }
            }
        }
        
        // Handle scroll events to validate hover when page scrolls (throttled)
        let scrollTimeout = null;
        function handleScroll(event) {
            if (currentHoverURL && !scrollTimeout) {
                scrollTimeout = setTimeout(() => {
                    // Re-check if mouse is still over the same link after scroll
                    if (currentHoverURL) {
                        const elementAtPoint = document.elementFromPoint(lastMouseX, lastMouseY);
                        const linkElement = findLinkElement(elementAtPoint);
                        
                        if (!linkElement || linkElement.href !== currentHoverURL) {
                            currentHoverURL = null;
                            sendHoverInfo(null, null);
                        }
                    }
                    scrollTimeout = null;
                }, 100); // 100ms throttle
            }
        }
        
        // Set up event delegation on document
        document.addEventListener('mouseover', handleMouseOver, { passive: true, capture: true });
        document.addEventListener('mouseout', handleMouseOut, { passive: true, capture: true });
        document.addEventListener('scroll', handleScroll, { passive: true, capture: true });
        
        // Create handler for native code to clear hover state (used when mouse exits webview)
        function createSecureHandler(methodName, implementation) {
            return function() {
                const providedSecret = arguments[0];
                if (providedSecret !== sessionSecret) {
                    console.error('iTermHoverLinkHandler: Invalid session secret for', methodName);
                    return;
                }
                const args = Array.prototype.slice.call(arguments, 1);
                return implementation.apply(this, args);
            };
        }
        
        const handlerMethods = {
            clearHover: createSecureHandler('clearHover', function() {
                if (currentHoverURL) {
                    currentHoverURL = null;
                    sendHoverInfo(null, null);
                }
            })
        };
        
        // Expose handler to native code
        Object.defineProperty(window, 'iTermHoverLinkHandler', {
            value: Object.freeze(Object.create(null, {
                clearHover: {
                    value: handlerMethods.clearHover,
                    writable: false,
                    configurable: false,
                    enumerable: true
                }
            })),
            writable: false,
            configurable: false,
            enumerable: false
        });
        
    } catch (err) {
        console.error(
            '[HoverLinkDetector:init error]',
            'message:', err.message,
            'stack:', err.stack
        );
    }
})();