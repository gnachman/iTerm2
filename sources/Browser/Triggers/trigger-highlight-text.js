;(function() {
    'use strict';

    const regex = {{REGEX}};
    const textColor = {{TEXT_COLOR}};
    const backgroundColor = {{BACKGROUND_COLOR}};

    // Highlight all matching text in textColor/backgroundColor. If either is null, then leave the corresponding color unaffected.
    
    console.debug('iTerm2 Text Highlighter: Starting with regex:', regex, 'textColor:', textColor, 'backgroundColor:', backgroundColor);

    function highlightText() {
        console.debug('iTerm2 Text Highlighter: highlightText() called');

        if (!regex) {
            console.debug('iTerm2 Text Highlighter: No regex provided, exiting');
            return;
        }

        // Create a regex object from the template-substituted regex
        let regexObj;
        try {
            regexObj = new RegExp(regex, 'g'); // global, case-sensitive
            console.debug('iTerm2 Text Highlighter: Regex compiled successfully:', regexObj);
        } catch (error) {
            console.error('iTerm2 Text Highlighter: Invalid regex pattern:', regex, error);
            return;
        }

        // Function to wrap text nodes with highlighting
        function highlightTextNode(textNode) {
            const text = textNode.textContent;
            console.debug('iTerm2 Text Highlighter: Processing text node:', text.substring(0, 100) + (text.length > 100 ? '...' : ''));
            
            const matches = [];
            let match;
            
            // Find all matches
            regexObj.lastIndex = 0; // Reset regex state
            while ((match = regexObj.exec(text)) !== null) {
                console.debug('iTerm2 Text Highlighter: Found match:', match[0], 'at position', match.index);
                matches.push({
                    start: match.index,
                    end: match.index + match[0].length,
                    text: match[0]
                });
                
                // Prevent infinite loop for zero-length matches
                if (match.index === regexObj.lastIndex) {
                    regexObj.lastIndex++;
                }
            }

            if (matches.length === 0) {
                console.debug('iTerm2 Text Highlighter: No matches found in this text node');
                return;
            }

            console.debug('iTerm2 Text Highlighter: Found', matches.length, 'matches in text node');

            // Create document fragment with highlighted text
            const fragment = document.createDocumentFragment();
            let lastIndex = 0;

            matches.forEach((match, index) => {
                console.debug('iTerm2 Text Highlighter: Processing match', index + 1, ':', match.text);

                // Add text before the match
                if (match.start > lastIndex) {
                    fragment.appendChild(document.createTextNode(text.substring(lastIndex, match.start)));
                }

                // Create highlighted span
                const span = document.createElement('span');
                span.textContent = match.text;
                
                // Apply colors if specified
                if (textColor) {
                    span.style.color = textColor;
                    console.debug('iTerm2 Text Highlighter: Applied text color:', textColor);
                }
                if (backgroundColor) {
                    span.style.backgroundColor = backgroundColor;
                    console.debug('iTerm2 Text Highlighter: Applied background color:', backgroundColor);
                }
                
                // Add marker attribute
                span.setAttribute('data-iterm2-highlight', 'true');

                fragment.appendChild(span);
                lastIndex = match.end;
            });

            // Add remaining text
            if (lastIndex < text.length) {
                fragment.appendChild(document.createTextNode(text.substring(lastIndex)));
            }

            // Replace the original text node
            console.debug('iTerm2 Text Highlighter: Replacing text node with highlighted version');
            textNode.parentNode.replaceChild(fragment, textNode);
        }

        // Walk through all text nodes in the document
        function walkTextNodes(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                // Skip if parent already has highlighting to avoid double-highlighting
                if (!node.parentNode.hasAttribute('data-iterm2-highlight')) {
                    highlightTextNode(node);
                } else {
                    console.debug('iTerm2 Text Highlighter: Skipping already highlighted text node');
                }
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                // Skip script and style elements
                const tagName = node.tagName.toLowerCase();
                if (tagName !== 'script' && tagName !== 'style') {
                    // Create a copy of childNodes since we might modify the DOM
                    const children = Array.from(node.childNodes);
                    children.forEach(child => walkTextNodes(child));
                } else {
                    console.debug('iTerm2 Text Highlighter: Skipping', tagName, 'element');
                }
            }
        }

        // Start highlighting from document body
        if (document.body) {
            console.debug('iTerm2 Text Highlighter: Starting to walk through document body');
            walkTextNodes(document.body);
            console.debug('iTerm2 Text Highlighter: Finished processing document');
        } else {
            console.debug('iTerm2 Text Highlighter: No document body found');
        }
    }

    // Run highlighting when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', highlightText);
    } else {
        highlightText();
    }

    true;
})();
