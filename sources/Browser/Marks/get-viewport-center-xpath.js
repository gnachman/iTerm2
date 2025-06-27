(function() {
    // Include shared XPath utilities
    {{INCLUDE:xpath-utils.js}}
    
    // Get viewport center coordinates
    var centerX = window.innerWidth / 2;
    var centerY = window.innerHeight / 2;
    
    // Try to find a meaningful element around the center point
    var element = null;
    var searchRadii = [0, 10, 20, 40, 60]; // Search outward from center
    
    for (var i = 0; i < searchRadii.length; i++) {
        var radius = searchRadii[i];
        var offsets = [];
        
        if (radius === 0) {
            offsets = [{x: 0, y: 0}];
        } else {
            // Create a circle of points around the center
            var numPoints = 8;
            for (var j = 0; j < numPoints; j++) {
                var angle = (j * 2 * Math.PI) / numPoints;
                offsets.push({
                    x: Math.round(radius * Math.cos(angle)),
                    y: Math.round(radius * Math.sin(angle))
                });
            }
        }
        
        for (var k = 0; k < offsets.length; k++) {
            var testX = centerX + offsets[k].x;
            var testY = centerY + offsets[k].y;
            
            // Make sure we're still within the viewport
            if (testX >= 0 && testX < window.innerWidth && 
                testY >= 0 && testY < window.innerHeight) {
                
                var candidate = document.elementFromPoint(testX, testY);
                if (isMeaningfulElement(candidate)) {
                    element = candidate;
                    break;
                }
            }
        }
        
        if (element) break;
    }
    
    // If we still didn't find anything meaningful, use whatever is at the center
    if (!element) {
        element = document.elementFromPoint(centerX, centerY);
    }
    
    if (!element) return null;
    
    // Calculate vertical offset from the top of the element to the viewport center
    var rect = element.getBoundingClientRect();
    var offsetY = centerY - rect.top;
    
    // Highlight the captured element briefly to show what was saved
    highlightElement(element);
    
    // Return element data using shared utility
    return getElementData(element, offsetY);
})();