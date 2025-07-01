// Function to extract text fragment from an element for URL text fragments
// This follows the Text Fragment URL specification for reliable deep linking

function extractTextFragment(element) {
    if (!element) return null;
    
    // Get the text content, cleaned up
    var textContent = getCleanTextContent(element);
    if (!textContent || textContent.length < 10) {
        // Try to get text from parent if current element doesn't have enough
        var parent = element.parentNode;
        if (parent && parent.nodeType === Node.ELEMENT_NODE) {
            textContent = getCleanTextContent(parent);
        }
    }
    
    if (!textContent || textContent.length < 10) {
        return null; // Not enough text to create a meaningful fragment
    }
    
    // For Text Fragment URLs, we want a distinctive portion of text
    // that can reliably identify the location
    var fragment = createTextFragment(textContent);
    
    return fragment;
}

function getCleanTextContent(element) {
    if (!element) return '';
    
    // Get all text nodes, but ignore script/style content
    var walker = document.createTreeWalker(
        element,
        NodeFilter.SHOW_TEXT,
        function(node) {
            var parentTag = node.parentNode.tagName.toLowerCase();
            if (parentTag === 'script' || parentTag === 'style' || parentTag === 'noscript') {
                return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
        }
    );
    
    var texts = [];
    var node;
    while (node = walker.nextNode()) {
        var text = node.textContent.trim();
        if (text.length > 0) {
            texts.push(text);
        }
    }
    
    return texts.join(' ').replace(/\s+/g, ' ').trim();
}

function createTextFragment(text) {
    // Clean up the text for URL fragment use
    var cleaned = text.replace(/\s+/g, ' ').trim();
    
    // For text fragments, we want something distinctive but not too long
    // Aim for 10-20 words or up to 100 characters
    var words = cleaned.split(' ');
    var fragment = '';
    
    if (words.length <= 20 && cleaned.length <= 100) {
        // Use the whole text if it's short enough
        fragment = cleaned;
    } else if (words.length > 20) {
        // Use first 15 words
        fragment = words.slice(0, 15).join(' ');
    } else {
        // Text is long but few words - truncate at word boundary near 80 chars
        var truncated = '';
        for (var i = 0; i < words.length; i++) {
            var candidate = truncated + (truncated ? ' ' : '') + words[i];
            if (candidate.length > 80) break;
            truncated = candidate;
        }
        fragment = truncated || words.slice(0, 10).join(' ');
    }
    
    // Remove characters that would cause issues in URLs
    fragment = fragment.replace(/[#\?&]/g, ' ').replace(/\s+/g, ' ').trim();
    
    return fragment.length > 0 ? fragment : null;
}

// Function to create a text fragment with context for better uniqueness
function createContextualTextFragment(element) {
    var fragment = extractTextFragment(element);
    if (!fragment) return null;
    
    // Try to add prefix/suffix context for disambiguation if the text appears multiple times
    var fullPageText = document.body.textContent;
    var occurrences = (fullPageText.match(new RegExp(escapeRegExp(fragment), 'gi')) || []).length;
    
    if (occurrences > 1) {
        // Text appears multiple times, try to add context
        var contextFragment = createFragmentWithContext(element, fragment);
        if (contextFragment) {
            return contextFragment;
        }
    }
    
    return fragment;
}

function createFragmentWithContext(element, fragment) {
    // Try to get surrounding text for context
    var container = element.parentNode || element;
    var fullText = getCleanTextContent(container);
    
    var fragmentIndex = fullText.toLowerCase().indexOf(fragment.toLowerCase());
    if (fragmentIndex === -1) return null;
    
    // Get some words before and after for context
    var beforeText = fullText.substring(0, fragmentIndex).trim();
    var afterText = fullText.substring(fragmentIndex + fragment.length).trim();
    
    var beforeWords = beforeText.split(/\s+/).slice(-3).join(' ');
    var afterWords = afterText.split(/\s+/).slice(0, 3).join(' ');
    
    // Create a range fragment: text=start,end or text=prefix-,start,-suffix
    if (beforeWords && afterWords) {
        // Use prefix and suffix
        return beforeWords + '-,' + fragment + ',-' + afterWords;
    } else if (afterWords) {
        // Use just suffix  
        return fragment + ',-' + afterWords;
    } else if (beforeWords) {
        // Use just prefix
        return beforeWords + '-,' + fragment;
    }
    
    return fragment;
}

function escapeRegExp(string) {
    return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Export the main function for template substitution
function getTextFragmentData(element, offsetY) {
    var baseData = getElementData(element, offsetY);
    var textFragment = createContextualTextFragment(element);
    
    if (textFragment) {
        baseData.textFragment = textFragment;
    }
    
    return baseData;
}