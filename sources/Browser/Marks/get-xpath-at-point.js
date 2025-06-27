(function() {
    // Include shared XPath utilities
    {{INCLUDE:xpath-utils.js}}
    
    // Parameters passed via template substitution
    var clickX = parseInt("{{CLICK_X}}") || 0;
    var clickY = parseInt("{{CLICK_Y}}") || 0;
    
    console.log('get-xpath-at-point.js: Getting XPath at point:', clickX, clickY);
    
    // Get element at the click point
    var element = document.elementFromPoint(clickX, clickY);
    if (!element) {
        console.log('get-xpath-at-point.js: No element found at point');
        return null;
    }
    
    console.log('get-xpath-at-point.js: Found element:', element);
    
    // Calculate vertical offset from the top of the element to the click point
    var rect = element.getBoundingClientRect();
    var offsetY = clickY - rect.top;
    
    // Highlight the captured element briefly to show what was saved
    highlightElement(element);
    
    console.log('get-xpath-at-point.js: Generated XPath for element');
    
    // Return element data using shared utility
    return getElementData(element, offsetY);
})();