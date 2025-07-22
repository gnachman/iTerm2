(function() {
    'use strict';
    
    const sessionSecret = "{{SECRET}}";
    
    // CSS for highlighting matches
    const highlightStyles = `
        .iterm-find-highlight {
            background-color: #FFFF00 !important;
            color: #000000 !important;
            border-radius: 2px;
        }
        
        .iterm-find-highlight-current {
            background-color: #FF9632 !important;
            color: #000000 !important;
            border-radius: 2px;
        }
        
        .iterm-find-removed {
            display: none !important;
        }
    `;
    
    // State management
    let currentSearchTerm = '';
    let currentMatchIndex = -1;
    let matches = [];
    let searchMode = 'substring'; // substring, regex, caseSensitive, caseInsensitive
    let highlightedElements = [];
    
    // Inject styles
    function injectStyles() {
        if (!document.getElementById('iterm-find-styles')) {
            const styleElement = document.createElement('style');
            styleElement.id = 'iterm-find-styles';
            styleElement.textContent = highlightStyles;
            document.head.appendChild(styleElement);
        }
    }
    
    // Clear all highlights
    function clearHighlights() {
        highlightedElements.forEach(element => {
            if (element.parentNode) {
                const parent = element.parentNode;
                while (element.firstChild) {
                    parent.insertBefore(element.firstChild, element);
                }
                parent.removeChild(element);
            }
        });
        highlightedElements = [];
        matches = [];
        currentMatchIndex = -1;
    }
    
    // Create a highlight span
    function createHighlight(text, isCurrent) {
        const span = document.createElement('span');
        span.className = isCurrent ? 'iterm-find-highlight-current' : 'iterm-find-highlight';
        span.textContent = text;
        return span;
    }
    
    // Get text nodes from element
    function getTextNodes(element) {
        const textNodes = [];
        const walker = document.createTreeWalker(
            element,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    // Skip script and style elements
                    const parent = node.parentElement;
                    if (parent && (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE')) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    // Skip already highlighted nodes
                    if (parent && parent.classList && 
                        (parent.classList.contains('iterm-find-highlight') || 
                         parent.classList.contains('iterm-find-highlight-current'))) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    // Skip empty text nodes
                    if (!node.textContent.trim()) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                }
            }
        );
        
        let node;
        while (node = walker.nextNode()) {
            textNodes.push(node);
        }
        return textNodes;
    }
    
    // Create regex based on search mode
    function createSearchRegex(term) {
        let flags = 'g';
        let pattern = term;
        
        switch (searchMode) {
            case 'regex':
                // Use term as-is for regex mode
                break;
            case 'caseSensitive':
                // Escape special regex characters for literal search
                pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                break;
            case 'caseInsensitive':
                pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                flags += 'i';
                break;
            case 'substring':
            default:
                // Default case-insensitive substring search
                pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                flags += 'i';
                break;
        }
        
        try {
            return new RegExp(pattern, flags);
        } catch (e) {
            // If regex is invalid, fall back to escaped literal search
            pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            return new RegExp(pattern, flags);
        }
    }
    
    // Highlight matches in text nodes
    function highlightMatches(searchTerm) {
        if (!searchTerm) return;
        
        const regex = createSearchRegex(searchTerm);
        const textNodes = getTextNodes(document.body);
        
        textNodes.forEach(node => {
            const text = node.textContent;
            const matchArray = [...text.matchAll(regex)];
            
            if (matchArray.length > 0) {
                const parent = node.parentNode;
                const fragment = document.createDocumentFragment();
                let lastIndex = 0;
                
                matchArray.forEach(match => {
                    // Add text before match
                    if (match.index > lastIndex) {
                        fragment.appendChild(
                            document.createTextNode(text.substring(lastIndex, match.index))
                        );
                    }
                    
                    // Add highlighted match
                    const highlight = createHighlight(match[0], false);
                    fragment.appendChild(highlight);
                    highlightedElements.push(highlight);
                    matches.push({
                        element: highlight,
                        rect: null // Will be calculated when needed
                    });
                    
                    lastIndex = match.index + match[0].length;
                });
                
                // Add remaining text
                if (lastIndex < text.length) {
                    fragment.appendChild(
                        document.createTextNode(text.substring(lastIndex))
                    );
                }
                
                parent.replaceChild(fragment, node);
            }
        });
        
        // Update match positions
        updateMatchPositions();
        
        // Report results
        reportResults();
    }
    
    // Update match positions for scrollbar indicators
    function updateMatchPositions() {
        matches.forEach(match => {
            match.rect = match.element.getBoundingClientRect();
        });
    }
    
    // Navigate to a specific match
    function navigateToMatch(index) {
        if (matches.length === 0) return;
        
        // Clear current highlight
        if (currentMatchIndex >= 0 && currentMatchIndex < matches.length) {
            matches[currentMatchIndex].element.className = 'iterm-find-highlight';
        }
        
        // Wrap around
        currentMatchIndex = ((index % matches.length) + matches.length) % matches.length;
        
        // Highlight current match
        const currentMatch = matches[currentMatchIndex];
        currentMatch.element.className = 'iterm-find-highlight-current';
        
        // Scroll into view
        currentMatch.element.scrollIntoView({
            behavior: 'smooth',
            block: 'center',
            inline: 'center'
        });
        
        reportResults();
    }
    
    // Report results to Swift
    function reportResults() {
        const positions = matches.map(match => {
            const rect = match.element.getBoundingClientRect();
            return {
                x: rect.left + window.scrollX,
                y: rect.top + window.scrollY,
                width: rect.width,
                height: rect.height
            };
        });
        
        window.webkit.messageHandlers.iTermCustomFind.postMessage({
            sessionSecret: sessionSecret,
            action: 'resultsUpdated',
            data: {
                searchTerm: currentSearchTerm,
                totalMatches: matches.length,
                currentMatch: currentMatchIndex + 1,
                matchPositions: positions
            }
        });
    }
    
    // Handle find commands
    function handleFindCommand(command) {
        switch (command.action) {
            case 'startFind':
                clearHighlights();
                currentSearchTerm = command.searchTerm;
                searchMode = command.searchMode || 'substring';
                if (currentSearchTerm) {
                    highlightMatches(currentSearchTerm);
                    if (matches.length > 0) {
                        navigateToMatch(0);
                    }
                }
                break;
                
            case 'findNext':
                if (matches.length > 0) {
                    navigateToMatch(currentMatchIndex + 1);
                }
                break;
                
            case 'findPrevious':
                if (matches.length > 0) {
                    navigateToMatch(currentMatchIndex - 1);
                }
                break;
                
            case 'clearFind':
                clearHighlights();
                currentSearchTerm = '';
                reportResults();
                break;
                
            case 'updatePositions':
                updateMatchPositions();
                reportResults();
                break;
        }
    }
    
    // Set up message listener
    window.iTermCustomFind = {
        handleCommand: handleFindCommand
    };
    
    // Update positions on scroll/resize
    let updateTimer;
    function schedulePositionUpdate() {
        clearTimeout(updateTimer);
        updateTimer = setTimeout(() => {
            if (matches.length > 0) {
                updateMatchPositions();
                reportResults();
            }
        }, 100);
    }
    
    window.addEventListener('scroll', schedulePositionUpdate, true);
    window.addEventListener('resize', schedulePositionUpdate);
    
    // Initialize
    injectStyles();
    
    // Freeze the object to prevent tampering
    Object.freeze(window.iTermCustomFind);
})();