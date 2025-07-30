const SelectionMode = {
    CHARACTER: 0,
    WORD: 1,
    LINE: 2,
    SMART: 3,
    BOX: 4,
    WHOLE_LINE: 5
};

// Helper function to check if text node should be included in cursor navigation
function isTextNodeVisible(node) {
    if (!node.textContent.trim()) {
        return false;
    }

    // Skip hidden/clipped content using standard CSS properties
    let element = node.parentElement;
    while (element) {
        const style = getComputedStyle(element);

        // Standard ways content can be hidden
        if (style.display === 'none' ||
            style.visibility === 'hidden' ||
            element.hidden ||
            element.getAttribute('aria-hidden') === 'true' ||
            style.opacity === '0') {
            return false;
        }

        // Skip content that's clipped to be invisible
        if (style.clip === 'rect(0px, 0px, 0px, 0px)' ||
            style.clipPath === 'inset(50%)' ||
            style.clipPath === 'inset(100%)') {
            return false;
        }

        // Skip elements with tiny dimensions (common accessibility pattern)
        if ((style.width === '1px' && style.height === '1px') ||
            (style.width === '0px' || style.height === '0px')) {
            return false;
        }

        element = element.parentElement;
    }

    return true;
}

function reverseTreeWalk(root, filter) {
    // Modified reverse traversal that visits parents before children
    // This allows FILTER_REJECT to properly skip entire subtrees

    function traverseNode(node) {
        if (!node) return;

        // Visit current node first (parent before children)
        const filterResult = filter(node);

        if (filterResult === NodeFilter.FILTER_REJECT) {
            // Skip this entire subtree (don't visit children)
            return;
        }

        // Visit children in reverse order (right to left)
        const children = Array.from(node.children);
        for (let i = children.length - 1; i >= 0; i--) {
            traverseNode(children[i]);
        }
    }

    // Start with root's children in reverse order
    const children = Array.from(root.children);
    for (let i = children.length - 1; i >= 0; i--) {
        traverseNode(children[i]);
    }
}

// Shared function to get page coordinates for a text node position
function getTextNodePageCoordinates(textNode, characterOffset) {
    // Convert DOM position to page coordinates
    if (!textNode) {
        return null;
    }

    if (textNode.nodeType !== Node.TEXT_NODE) {
        return null;
    }

    if (characterOffset > textNode.textContent.length) {
        return null;
    }

    try {
        const range = document.createRange();

        // Special handling for cursor at end of text node
        if (characterOffset === textNode.textContent.length) {
            // Position cursor after the last character
            range.setStart(textNode, characterOffset);
            range.setEnd(textNode, characterOffset);
        } else {
            // Normal case: select the character at the offset
            range.setStart(textNode, characterOffset);
            range.setEnd(textNode, characterOffset + 1);
        }

        // Use getClientRects() for accurate single-character positioning
        const rects = range.getClientRects();
        if (rects.length === 0) {
            return null;
        }

        // Take the last rect, which represents where the character actually appears visually
        const rect = rects[rects.length - 1];

        // Take the last rect, which represents where the character actually appears visually

        // For collapsed ranges (cursor at end of text), width might be 0
        if (rect.height > 0) {
            const scrollX = window.pageXOffset || document.documentElement.scrollLeft;
            const scrollY = window.pageYOffset || document.documentElement.scrollTop;
            return {
                pageX: rect.left + scrollX,
                pageY: rect.top + scrollY,
                height: rect.height
            };
        }
    } catch (e) {
    }
    return null;
}
