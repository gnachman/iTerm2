;(function() {
    'use strict';

    console.log('iTerm2 Highlight Remover: Starting highlight removal');

    // Remove existing highlights from the page
    function removeExistingHighlights() {
        if (!document.body) {
            console.log('iTerm2 Highlight Remover: No document body found');
            return;
        }

        // Find all elements with the highlight marker attribute
        const highlightedElements = document.querySelectorAll('[data-iterm2-highlight="true"]');
        console.log('iTerm2 Highlight Remover: Found', highlightedElements.length, 'highlighted elements to remove');

        highlightedElements.forEach(element => {
            // Replace the highlighted span with its text content
            const textNode = document.createTextNode(element.textContent);
            element.parentNode.replaceChild(textNode, element);
        });

        // Normalize adjacent text nodes that may have been created
        if (document.body.normalize) {
            document.body.normalize();
        }

        console.log('iTerm2 Highlight Remover: Finished removing', highlightedElements.length, 'highlights');
    }

    // Run the removal immediately
    removeExistingHighlights();

    true;
})();