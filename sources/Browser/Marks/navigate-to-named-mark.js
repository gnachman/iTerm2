(function() {
    console.debug('navigate-to-named-mark.js: Starting navigation');
    
    // Parameters passed via template substitution
    var xpath = "{{XPATH}}";
    var offsetY = parseInt("{{OFFSET_Y}}") || 0;
    var scrollY = parseInt("{{SCROLL_Y}}") || 0;
    var textFragment = "{{TEXT_FRAGMENT}}";
    
    console.debug('navigate-to-named-mark.js: Parameters - xpath:', xpath, 'offsetY:', offsetY, 'scrollY:', scrollY, 'textFragment:', textFragment);
    
    var targetElement = null;
    
    try {
        console.debug('navigate-to-named-mark.js: Evaluating XPath:', xpath);
        // Try XPath first
        var result = document.evaluate(
            xpath,
            document,
            null,
            XPathResult.FIRST_ORDERED_NODE_TYPE,
            null
        );
        
        targetElement = result.singleNodeValue;
        
        if (!targetElement && textFragment) {
            console.debug('navigate-to-named-mark.js: XPath failed, trying text fragment fallback');
            targetElement = findElementByTextFragment(textFragment);
        }
        
        if (!targetElement) {
            console.debug('navigate-to-named-mark.js: Element not found with XPath or text fragment');
            return false; // Element not found
        }
        
        console.debug('navigate-to-named-mark.js: Found target element:', targetElement);
        
        // Get element position
        var rect = targetElement.getBoundingClientRect();
        var elementTop = rect.top + window.pageYOffset;
        
        console.debug('navigate-to-named-mark.js: Element rect:', rect, 'elementTop:', elementTop);
        
        // Calculate scroll position to center the element in the viewport
        var viewportCenter = window.innerHeight / 2;
        var targetScrollY = elementTop + offsetY - viewportCenter;
        
        // Ensure we don't scroll past document bounds
        targetScrollY = Math.max(0, Math.min(targetScrollY, document.body.scrollHeight - window.innerHeight));
        
        console.debug('navigate-to-named-mark.js: Scrolling to:', targetScrollY);
        
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
        
        console.debug('navigate-to-named-mark.js: Navigation successful');
        return true; // Successfully navigated
        
    } catch (error) {
        console.debug('navigate-to-named-mark.js: Error navigating to mark:', error);
        console.debug('navigate-to-named-mark.js: Error stack:', error.stack);
        return false;
    }
    
    // Function to find element by text fragment as fallback
    function findElementByTextFragment(fragment) {
        if (!fragment) return null;
        
        console.debug('navigate-to-named-mark.js: Searching for text fragment:', fragment);
        
        // Handle contextual fragments (prefix-,text,-suffix or text,end)
        var searchText = fragment;
        var isRange = false;
        var startText, endText, prefix, suffix;
        
        // Parse contextual fragments
        if (fragment.includes('-,') || fragment.includes(',-')) {
            // Has prefix or suffix
            var parts = fragment.split(',');
            if (parts.length >= 2) {
                for (var i = 0; i < parts.length; i++) {
                    if (parts[i].endsWith('-')) {
                        prefix = parts[i].slice(0, -1);
                    } else if (parts[i].startsWith('-')) {
                        suffix = parts[i].slice(1);
                    } else if (!startText) {
                        startText = parts[i];
                    } else if (!endText) {
                        endText = parts[i];
                        isRange = true;
                    }
                }
                searchText = startText || searchText;
            }
        } else if (fragment.includes(',')) {
            // Range without prefix/suffix: start,end
            var rangeParts = fragment.split(',');
            if (rangeParts.length === 2) {
                startText = rangeParts[0];
                endText = rangeParts[1];
                isRange = true;
                searchText = startText;
            }
        }
        
        console.debug('navigate-to-named-mark.js: Parsed fragment - searchText:', searchText, 'isRange:', isRange, 'prefix:', prefix, 'suffix:', suffix);
        
        // Create a tree walker to traverse all text nodes
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
        
        var textNodes = [];
        var node;
        while (node = walker.nextNode()) {
            textNodes.push(node);
        }
        
        // Search for the text in the page
        for (var i = 0; i < textNodes.length; i++) {
            var textNode = textNodes[i];
            var text = textNode.textContent;
            var normalizedText = text.replace(/\s+/g, ' ').trim();
            var searchTextNormalized = searchText.replace(/\s+/g, ' ').trim();
            
            // Case-insensitive search
            var index = normalizedText.toLowerCase().indexOf(searchTextNormalized.toLowerCase());
            if (index !== -1) {
                // Found the text, check context if needed
                var contextMatch = true;
                
                if (prefix) {
                    // Check if prefix appears before
                    var beforeText = normalizedText.substring(0, index).toLowerCase();
                    if (!beforeText.includes(prefix.toLowerCase())) {
                        contextMatch = false;
                    }
                }
                
                if (suffix && contextMatch) {
                    // Check if suffix appears after
                    var afterText = normalizedText.substring(index + searchTextNormalized.length).toLowerCase();
                    if (!afterText.includes(suffix.toLowerCase())) {
                        contextMatch = false;
                    }
                }
                
                if (contextMatch) {
                    console.debug('navigate-to-named-mark.js: Found text fragment match in element:', textNode.parentNode);
                    return textNode.parentNode;
                }
            }
        }
        
        console.debug('navigate-to-named-mark.js: Text fragment not found');
        return null;
    }
})();
