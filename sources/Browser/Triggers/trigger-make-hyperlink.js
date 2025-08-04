    // Add makeHyperlink function directly to the api object
    
    api.makeHyperlink = function(matchId, url) {
        if (!matchId || !url) {
            return;
        }

        // Get match data from api
        const matchData = api.getMatchById(matchId);
        if (!matchData) {
            console.error('iTerm2 Hyperlink Maker: No match data found for ID:', matchId);
            return;
        }


        // Check if we have a Range object
        if (!matchData.range) {
            console.error('iTerm2 Hyperlink Maker: No range found in match data');
            return;
        }

        // Validate that it's actually a Range object
        if (!(matchData.range instanceof Range)) {
            console.error('iTerm2 Hyperlink Maker: Stored range is not a Range object:', typeof matchData.range, matchData.range);
            return;
        }

        try {
            // Use the Range to wrap the matched text
            const range = matchData.range;
            
            // Check if the range is still valid
            if (!range.startContainer || !range.endContainer) {
                console.error('iTerm2 Hyperlink Maker: Invalid range - containers are null');
                return;
            }
            
            // Check if already wrapped in a link
            let parent = range.commonAncestorContainer;
            if (parent.nodeType === Node.TEXT_NODE) {
                parent = parent.parentNode;
            }
            
            // Walk up to check if we're already in a link
            let currentNode = parent;
            while (currentNode && currentNode !== document.body) {
                if (currentNode.tagName === 'A') {
                    return;
                }
                currentNode = currentNode.parentNode;
            }
            
            // Create a link element
            const link = document.createElement('a');
            link.href = url;
            link.setAttribute('data-iterm2-hyperlink', 'true');
            link.setAttribute('data-iterm2-match-id', matchId);
            link.setAttribute('target', '_blank');
            link.setAttribute('rel', 'noopener noreferrer');
            
            // Extract and wrap the contents of the range
            try {
                // Clone the range to avoid modifying the stored one
                const workingRange = range.cloneRange();
                
                // Extract the contents and append to link
                const contents = workingRange.extractContents();
                link.appendChild(contents);
                
                // Insert the link at the range location
                workingRange.insertNode(link);
            } catch (e) {
                console.error('iTerm2 Hyperlink Maker: Error wrapping range:', e);
                
                // Fallback: try to create hyperlink by finding the text
                hyperlinkFallback(matchData, matchId, url);
            }
            
        } catch (error) {
            console.error('iTerm2 Hyperlink Maker: Error during hyperlink creation:', error);
        }
    };
    
    // Fallback function if Range manipulation fails
    function hyperlinkFallback(matchData, matchId, url) {
        
        const matchText = matchData.matchText;
        if (!matchText) {
            console.error('iTerm2 Hyperlink Maker: No match text available for fallback');
            return;
        }
        
        // Walk through text nodes and find the match
        function walkTextNodes(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent;
                const index = text.indexOf(matchText);
                
                if (index !== -1 && !node.parentNode.hasAttribute('data-iterm2-hyperlink')) {
                    // Check if not already in a link
                    let parent = node.parentNode;
                    while (parent && parent !== document.body) {
                        if (parent.tagName === 'A') {
                            return false; // Already in a link
                        }
                        parent = parent.parentNode;
                    }
                    
                    // Found the text, create a replacement
                    const before = text.substring(0, index);
                    const after = text.substring(index + matchText.length);
                    
                    const link = document.createElement('a');
                    link.textContent = matchText;
                    link.href = url;
                    link.setAttribute('data-iterm2-hyperlink', 'true');
                    link.setAttribute('data-iterm2-match-id', matchId);
                    link.setAttribute('target', '_blank');
                    link.setAttribute('rel', 'noopener noreferrer');
                    
                    const fragment = document.createDocumentFragment();
                    if (before) fragment.appendChild(document.createTextNode(before));
                    fragment.appendChild(link);
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
        
