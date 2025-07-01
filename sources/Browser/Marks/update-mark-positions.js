(function() {
    // Include shared XPath utilities
    {{INCLUDE:xpath-utils.js}}
    
    var secret = "{{SECRET}}";
    var updates = [];
    
    console.log('update-mark-positions.js: Starting mark position update');
    
    // Get all current mark annotations to find their GUIDs and XPaths
    var annotations = document.querySelectorAll('.iterm-mark-annotation[data-mark-guid]');
    
    console.log('update-mark-positions.js: Found', annotations.length, 'mark annotations');
    
    for (var i = 0; i < annotations.length; i++) {
        var annotation = annotations[i];
        var guid = annotation.getAttribute('data-mark-guid');
        
        if (!guid) continue;
        
        // Get mark data from the annotation's data attributes
        var xpath = annotation.dataset.markXpath;
        var offsetY = parseInt(annotation.dataset.markOffsetY) || 0;
        var textFragment = annotation.dataset.markTextFragment;
        
        if (!xpath) {
            console.log('update-mark-positions.js: No XPath data found for GUID:', guid);
            continue;
        }
        
        console.log('update-mark-positions.js: Updating position for mark:', guid);
        
        try {
            // Try to find the element using XPath
            var result = document.evaluate(
                xpath,
                document,
                null,
                XPathResult.FIRST_ORDERED_NODE_TYPE,
                null
            );
            
            var element = result.singleNodeValue;
            if (element) {
                // Calculate new position
                var rect = element.getBoundingClientRect();
                var newScrollY = window.pageYOffset || document.documentElement.scrollTop;
                var newOffsetY = offsetY; // Keep original offset within element
                
                console.log('update-mark-positions.js: Element found, new scrollY:', newScrollY);
                
                updates.push({
                    guid: guid,
                    scrollY: Math.round(newScrollY),
                    offsetY: Math.round(newOffsetY),
                    elementTop: Math.round(rect.top + newScrollY)
                });
            } else {
                console.log('update-mark-positions.js: Element not found for XPath:', xpath);
                
                // Try to find element using text fragment as fallback
                if (textFragment) {
                    var foundElement = findElementByTextFragment(textFragment);
                    if (foundElement) {
                        var rect = foundElement.getBoundingClientRect();
                        var newScrollY = window.pageYOffset || document.documentElement.scrollTop;
                        var newOffsetY = 0; // Reset offset since we found a different element
                        
                        console.log('update-mark-positions.js: Found element via text fragment, new scrollY:', newScrollY);
                        
                        updates.push({
                            guid: guid,
                            scrollY: Math.round(newScrollY),
                            offsetY: Math.round(newOffsetY),
                            elementTop: Math.round(rect.top + newScrollY)
                        });
                    }
                }
            }
        } catch (error) {
            console.log('update-mark-positions.js: Error updating mark position:', error);
        }
    }
    
    console.log('update-mark-positions.js: Prepared', updates.length, 'position updates');
    return updates;
    
    // Helper function to find element by text fragment (simplified version)
    function findElementByTextFragment(textFragment) {
        if (!textFragment) return null;
        
        console.log('update-mark-positions.js: Searching for text fragment:', textFragment);
        
        // Simple text search - this could be enhanced with the full text fragment parsing
        var walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            function(node) {
                var parentTag = node.parentNode.tagName.toLowerCase();
                if (parentTag === 'script' || parentTag === 'style' || parentTag === 'noscript') {
                    return NodeFilter.FILTER_REJECT;
                }
                return NodeFilter.FILTER_ACCEPT;
            }
        );
        
        var node;
        while (node = walker.nextNode()) {
            var text = node.textContent;
            var normalizedText = text.replace(/\\s+/g, ' ').trim();
            
            if (normalizedText.toLowerCase().includes(textFragment.toLowerCase())) {
                console.log('update-mark-positions.js: Found text fragment match');
                return node.parentNode;
            }
        }
        
        return null;
    }
})();