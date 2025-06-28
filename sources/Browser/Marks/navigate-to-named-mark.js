(function() {
    console.log('navigate-to-named-mark.js: Starting navigation');
    
    // Parameters passed via template substitution
    var xpath = "{{XPATH}}";
    var offsetY = parseInt("{{OFFSET_Y}}") || 0;
    var scrollY = parseInt("{{SCROLL_Y}}") || 0;
    
    console.log('navigate-to-named-mark.js: Parameters - xpath:', xpath, 'offsetY:', offsetY, 'scrollY:', scrollY);
    
    try {
        console.log('navigate-to-named-mark.js: Evaluating XPath:', xpath);
        // Use XPath to find the target element
        var result = document.evaluate(
            xpath,
            document,
            null,
            XPathResult.FIRST_ORDERED_NODE_TYPE,
            null
        );
        
        var targetElement = result.singleNodeValue;
        if (!targetElement) {
            console.log('navigate-to-named-mark.js: Element not found with XPath:', xpath);
            console.log('navigate-to-named-mark.js: Current document body:', document.body);
            return false; // Element not found
        }
        
        console.log('navigate-to-named-mark.js: Found target element:', targetElement);
        
        // Get element position
        var rect = targetElement.getBoundingClientRect();
        var elementTop = rect.top + window.pageYOffset;
        
        console.log('navigate-to-named-mark.js: Element rect:', rect, 'elementTop:', elementTop);
        
        // Calculate scroll position to center the element in the viewport
        var viewportCenter = window.innerHeight / 2;
        var targetScrollY = elementTop + offsetY - viewportCenter;
        
        // Ensure we don't scroll past document bounds
        targetScrollY = Math.max(0, Math.min(targetScrollY, document.body.scrollHeight - window.innerHeight));
        
        console.log('navigate-to-named-mark.js: Scrolling to:', targetScrollY);
        
        // Smooth scroll to position
        window.scrollTo({
            top: targetScrollY,
            left: 0,
            behavior: 'smooth'
        });
        
        // Optionally highlight the target element briefly
        var originalOutline = targetElement.style.outline;
        var originalOutlineOffset = targetElement.style.outlineOffset;
        
        targetElement.style.outline = '2px solid #007AFF';
        targetElement.style.outlineOffset = '2px';
        
        setTimeout(function() {
            targetElement.style.outline = originalOutline;
            targetElement.style.outlineOffset = originalOutlineOffset;
        }, 2000);
        
        console.log('navigate-to-named-mark.js: Navigation successful');
        return true; // Successfully navigated
        
    } catch (error) {
        console.log('navigate-to-named-mark.js: Error navigating to mark:', error);
        console.log('navigate-to-named-mark.js: Error stack:', error.stack);
        return false;
    }
})();