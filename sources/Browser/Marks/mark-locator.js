// Common module for locating marks in the document using various strategies
// This module provides a unified approach to finding elements and calculating positions

// Main function to locate a mark using fallback strategies
// Returns: { element: DOMElement|null, documentPosition: number, strategy: string }
function locateMark(mark) {
    var element = null;
    var documentPosition = 0;
    var strategy = 'none';
    
    // Strategy 1: Use XPath as hint for text fragment selection
    if (mark.textFragment) {
        var xpathHintElement = null;
        
        // Try to get XPath element as a hint
        if (mark.xpath) {
            xpathHintElement = findElementByXPath(mark.xpath);
        }
        
        // Find the best text fragment match (closest to XPath hint if available)
        element = findBestTextFragmentMatch(mark.textFragment, xpathHintElement);
        
        if (element) {
            if (xpathHintElement) {
                strategy = 'textFragment+xpath';
                console.debug('mark-locator: Found text fragment closest to XPath hint');
            } else {
                strategy = 'textFragment';
                console.debug('mark-locator: Found text fragment (no XPath hint available)');
            }
        }
    }
    
    // Strategy 2: Fall back to XPath only if no text fragment available
    if (!element && mark.xpath && !mark.textFragment) {
        element = findElementByXPath(mark.xpath);
        if (element) {
            strategy = 'xpath';
            console.debug('mark-locator: Found element via XPath (no text fragment available)');
        }
    }
    
    // Calculate position based on what we found
    if (element) {
        var rect = element.getBoundingClientRect();
        var pageYOffset = window.pageYOffset || document.documentElement.scrollTop;
        documentPosition = rect.top + pageYOffset + (mark.offsetY || 0);
    } else if (mark.y !== undefined && mark.y !== null) {
        // Strategy 3: Fall back to absolute Y position
        documentPosition = mark.y;
        strategy = 'absolute';
        console.debug('mark-locator: Using absolute Y position:', documentPosition);
    } else {
        console.debug('mark-locator: No valid positioning data available');
    }
    
    return {
        element: element,
        documentPosition: Math.round(documentPosition),
        strategy: strategy
    };
}

// Find element by XPath with error handling
function findElementByXPath(xpath) {
    if (!xpath) return null;
    
    try {
        var result = document.evaluate(
            xpath,
            document,
            null,
            XPathResult.FIRST_ORDERED_NODE_TYPE,
            null
        );
        return result.singleNodeValue;
    } catch (error) {
        console.debug('mark-locator: Invalid XPath:', error);
        return null;
    }
}

// Find the best text fragment match, using XPath element as a hint if available
function findBestTextFragmentMatch(textFragment, xpathHintElement) {
    if (!textFragment) return null;
    
    // Find all text fragment matches
    var allMatches = findAllTextFragmentMatches(textFragment);
    
    if (allMatches.length === 0) {
        return null;
    }
    
    if (allMatches.length === 1) {
        return allMatches[0];
    }
    
    // If we have multiple matches and an XPath hint, find the closest one
    if (xpathHintElement) {
        return findClosestElementToHint(allMatches, xpathHintElement);
    }
    
    // No hint available, return the first match
    return allMatches[0];
}

// Find all elements that match the text fragment
function findAllTextFragmentMatches(textFragment) {
    if (!textFragment) return [];
    
    var matches = [];
    
    // Extract the main text from contextual fragments (prefix-,text,-suffix)
    var searchText = extractSearchTextFromFragment(textFragment);
    if (!searchText) return [];
    
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
    
    // Search for all matching text
    var node;
    while (node = walker.nextNode()) {
        var text = node.textContent;
        var normalizedText = text.replace(/\s+/g, ' ').trim();
        var searchTextNormalized = searchText.replace(/\s+/g, ' ').trim();
        
        if (normalizedText.toLowerCase().includes(searchTextNormalized.toLowerCase())) {
            // If we have a contextual fragment, verify the context
            if (textFragment.includes('-,') || textFragment.includes(',-')) {
                if (verifyTextFragmentContext(textFragment, normalizedText, searchTextNormalized)) {
                    matches.push(node.parentNode);
                }
            } else {
                matches.push(node.parentNode);
            }
        }
    }
    
    return matches;
}

// Find the element closest to the XPath hint using a reasonable distance metric
function findClosestElementToHint(elements, hintElement) {
    if (!elements || elements.length === 0 || !hintElement) {
        return null;
    }
    
    var hintRect = hintElement.getBoundingClientRect();
    var hintPageY = hintRect.top + (window.pageYOffset || document.documentElement.scrollTop);
    var hintPageX = hintRect.left + (window.pageXOffset || document.documentElement.scrollLeft);
    
    var bestElement = null;
    var bestDistance = Infinity;
    
    for (var i = 0; i < elements.length; i++) {
        var element = elements[i];
        var rect = element.getBoundingClientRect();
        var elementPageY = rect.top + (window.pageYOffset || document.documentElement.scrollTop);
        var elementPageX = rect.left + (window.pageXOffset || document.documentElement.scrollLeft);
        
        // Calculate distance using Euclidean distance with Y-axis weighted more heavily
        // This accounts for the fact that vertical movement is more significant for text positioning
        var deltaX = elementPageX - hintPageX;
        var deltaY = elementPageY - hintPageY;
        var distance = Math.sqrt(deltaX * deltaX + (deltaY * deltaY * 2)); // Weight Y distance 2x
        
        if (distance < bestDistance) {
            bestDistance = distance;
            bestElement = element;
        }
    }
    
    console.debug('mark-locator: Found', elements.length, 'text fragment matches, selected closest (distance:', Math.round(bestDistance), 'px)');
    
    return bestElement;
}

// Find element by text fragment (legacy function for backward compatibility)
function findElementByTextFragment(textFragment) {
    var matches = findAllTextFragmentMatches(textFragment);
    return matches.length > 0 ? matches[0] : null;
}

// Extract the main search text from a text fragment
function extractSearchTextFromFragment(textFragment) {
    if (!textFragment) return null;
    
    // Handle contextual fragments (prefix-,text,-suffix or text,end)
    if (textFragment.includes('-,') || textFragment.includes(',-')) {
        var parts = textFragment.split(',');
        for (var i = 0; i < parts.length; i++) {
            // Find the main text (not prefix or suffix)
            if (!parts[i].startsWith('-') && !parts[i].endsWith('-')) {
                return parts[i];
            }
        }
    } else if (textFragment.includes(',')) {
        // Range fragment: start,end - use the start text
        return textFragment.split(',')[0];
    }
    
    // Simple fragment
    return textFragment;
}

// Verify that a text fragment with context matches
function verifyTextFragmentContext(textFragment, fullText, searchText) {
    var parts = textFragment.split(',');
    var prefix = null;
    var suffix = null;
    
    for (var i = 0; i < parts.length; i++) {
        if (parts[i].endsWith('-')) {
            prefix = parts[i].slice(0, -1).toLowerCase();
        } else if (parts[i].startsWith('-')) {
            suffix = parts[i].slice(1).toLowerCase();
        }
    }
    
    var normalizedFullText = fullText.toLowerCase();
    var index = normalizedFullText.indexOf(searchText.toLowerCase());
    
    if (index === -1) return false;
    
    // Check prefix if present
    if (prefix) {
        var beforeText = normalizedFullText.substring(0, index);
        if (!beforeText.includes(prefix)) {
            return false;
        }
    }
    
    // Check suffix if present
    if (suffix) {
        var afterText = normalizedFullText.substring(index + searchText.length);
        if (!afterText.includes(suffix)) {
            return false;
        }
    }
    
    return true;
}

// Calculate viewport-centered scroll position for navigation
function calculateScrollPosition(mark) {
    var locationInfo = locateMark(mark);
    var viewportCenter = window.innerHeight / 2;
    var targetScrollY;
    
    if (locationInfo.element || locationInfo.strategy === 'absolute') {
        // Center the position in the viewport
        targetScrollY = locationInfo.documentPosition - viewportCenter;
    } else {
        // No valid position found
        return null;
    }
    
    // Ensure we don't scroll past document bounds
    var maxScroll = Math.max(0, document.body.scrollHeight - window.innerHeight);
    targetScrollY = Math.max(0, Math.min(targetScrollY, maxScroll));
    
    return {
        scrollY: targetScrollY,
        element: locationInfo.element,
        strategy: locationInfo.strategy
    };
}
