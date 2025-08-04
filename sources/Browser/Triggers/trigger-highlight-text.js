    // Add highlightText function directly to the api object
    
    api.highlightText = function(matchId, textColor, backgroundColor) {
        if (!matchId) {
            return;
        }

        // Get match data from api
        const matchData = api.getMatchById(matchId);
        if (!matchData) {
            console.error('iTerm2 Text Highlighter: No match data found for ID:', matchId);
            return;
        }


        // Check if we have a Range object
        if (!matchData.range) {
            console.error('iTerm2 Text Highlighter: No range found in match data');
            return;
        }

        // Validate that it's actually a Range object
        if (!(matchData.range instanceof Range)) {
            console.error('iTerm2 Text Highlighter: Stored range is not a Range object:', typeof matchData.range, matchData.range);
            return;
        }

        try {
            // Use the Range to wrap the matched text
            const range = matchData.range;
            
            // Check if the range is still valid
            if (!range.startContainer || !range.endContainer) {
                console.error('iTerm2 Text Highlighter: Invalid range - containers are null');
                return;
            }
            
            // Create a span element for highlighting
            const span = document.createElement('span');
            span.setAttribute('data-iterm2-highlight', 'true');
            span.setAttribute('data-iterm2-match-id', matchId);
            
            // Apply colors if specified
            if (textColor) {
                span.style.color = textColor;
            }
            if (backgroundColor) {
                span.style.backgroundColor = backgroundColor;
            }
            
            // Extract and wrap the contents of the range
            try {
                // Clone the range to avoid modifying the stored one
                const workingRange = range.cloneRange();
                
                // Extract the contents and append to span
                const contents = workingRange.extractContents();
                span.appendChild(contents);
                
                // Insert the span at the range location
                workingRange.insertNode(span);
                
            } catch (e) {
                console.error('iTerm2 Text Highlighter: Error wrapping range:', e);
                
                // Fallback: try to highlight by finding the text
                highlightFallback(matchData, matchId, textColor, backgroundColor);
            }
            
        } catch (error) {
            console.error('iTerm2 Text Highlighter: Error during highlighting:', error);
        }
    };
    
    // Fallback function if Range manipulation fails
    function highlightFallback(matchData, matchId, textColor, backgroundColor) {
        
        const matchText = matchData.matchText;
        if (!matchText) {
            console.error('iTerm2 Text Highlighter: No match text available for fallback');
            return;
        }
        
        // Walk through text nodes and find the match
        function walkTextNodes(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent;
                const index = text.indexOf(matchText);
                
                if (index !== -1 && !node.parentNode.hasAttribute('data-iterm2-highlight')) {
                    // Found the text, create a replacement
                    const before = text.substring(0, index);
                    const after = text.substring(index + matchText.length);
                    
                    const span = document.createElement('span');
                    span.textContent = matchText;
                    span.setAttribute('data-iterm2-highlight', 'true');
                    span.setAttribute('data-iterm2-match-id', matchId);
                    
                    if (textColor) span.style.color = textColor;
                    if (backgroundColor) span.style.backgroundColor = backgroundColor;
                    
                    const fragment = document.createDocumentFragment();
                    if (before) fragment.appendChild(document.createTextNode(before));
                    fragment.appendChild(span);
                    if (after) fragment.appendChild(document.createTextNode(after));
                    
                    node.parentNode.replaceChild(fragment, node);
                    return true;
                }
            } else if (node.nodeType === Node.ELEMENT_NODE && node.tagName !== 'SCRIPT' && node.tagName !== 'STYLE') {
                for (const child of [...node.childNodes]) {
                    if (walkTextNodes(child)) return true;
                }
            }
            return false;
        }
        
        walkTextNodes(document.body);
    }
        
