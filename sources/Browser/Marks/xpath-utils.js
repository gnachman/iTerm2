// Shared XPath utility functions

// Function to check if an element is meaningful (not just background/body)
function isMeaningfulElement(element) {
    if (!element) return false;
    var tagName = element.tagName.toLowerCase();
    
    // Skip body, html, and other structural elements
    if (tagName === 'body' || tagName === 'html' || tagName === 'div' && !element.id && !element.className) {
        return false;
    }
    
    // Prefer elements with content, IDs, or meaningful classes
    return element.textContent.trim().length > 0 || 
           element.id || 
           (element.className && element.className.length > 0);
}

// Function to build a stable XPath for an element
function buildStableXPath(element) {
    var path = [];
    var current = element;
    
    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.body && current !== document.documentElement) {
        var selector = '';
        
        // Prefer ID if available - look for ID in current element or its children
        if (current.id) {
            selector = "//*[@id='" + current.id + "']";
            path.unshift(selector);
            break; // Stop here since ID should be unique
        }
        
        // Check if any child has an ID we can use
        var childWithId = current.querySelector('[id]');
        if (childWithId && childWithId.id) {
            // Use the child's ID and add the path back to our element
            var childPath = "//*[@id='" + childWithId.id + "']";
            // If our target element is the direct parent of the ID element, use that
            if (childWithId.parentNode === current) {
                selector = childPath + "/..";
                path.unshift(selector);
                break;
            }
        }
        
        // Use class if available, stable, and likely to be unique in context
        var className = current.className;
        if (className && typeof className === 'string' && 
            !className.match(/^[a-f0-9-]+$/) && // Not hash-like
            !className.includes('generated') &&
            !className.includes('temp') &&
            className.length < 50) { // Not too long
            
            // Check if this class combination is unique enough
            var cssSelector = current.tagName.toLowerCase() + "[class='" + className + "']";
            var elementsWithSameClass = document.querySelectorAll(cssSelector);
            
            // Only use class if it's relatively unique (fewer than 5 elements)
            if (elementsWithSameClass.length < 5) {
                selector = current.tagName.toLowerCase() + "[@class='" + className + "']";
            } else {
                // Fall back to positional selector
                var tagName = current.tagName.toLowerCase();
                var siblings = Array.from(current.parentNode.children).filter(
                    child => child.tagName.toLowerCase() === tagName
                );
                
                if (siblings.length === 1) {
                    selector = tagName;
                } else {
                    var index = siblings.indexOf(current) + 1;
                    selector = tagName + "[" + index + "]";
                }
            }
        } else {
            // Fall back to tag name with position
            var tagName = current.tagName.toLowerCase();
            var siblings = Array.from(current.parentNode.children).filter(
                child => child.tagName.toLowerCase() === tagName
            );
            
            if (siblings.length === 1) {
                selector = tagName;
            } else {
                var index = siblings.indexOf(current) + 1;
                selector = tagName + "[" + index + "]";
            }
        }
        
        path.unshift(selector);
        current = current.parentNode;
    }
    
    // If we didn't find an ID, add body as root
    if (path.length === 0 || !path[0].startsWith("//*[@id=")) {
        path.unshift("//body");
    }
    
    return path.join("/");
}

// Function to highlight an element briefly
function highlightElement(element) {
    var originalOutline = element.style.outline;
    var originalOutlineOffset = element.style.outlineOffset;
    
    element.style.outline = '2px solid #007AFF';
    element.style.outlineOffset = '2px';
    
    setTimeout(function() {
        element.style.outline = originalOutline;
        element.style.outlineOffset = originalOutlineOffset;
    }, 2000);
}

// Function to get scroll position and element data
function getElementData(element, offsetY) {
    var scrollX = window.pageXOffset || document.documentElement.scrollLeft;
    var scrollY = window.pageYOffset || document.documentElement.scrollTop;
    
    return {
        xpath: buildStableXPath(element),
        offsetY: Math.round(offsetY),
        scrollX: Math.round(scrollX),
        scrollY: Math.round(scrollY),
        elementTag: element.tagName.toLowerCase(),
        elementId: element.id || null,
        elementClass: element.className || null
    };
}