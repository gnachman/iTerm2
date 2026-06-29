class TextSegment extends Segment {
    constructor(index, element) {
        super('text', index);
        this.element = element;           // The block DOM element
        this.textContent = '';           // Concatenated text from all text nodes
        this.bounds = null;              // DOMRect - will be computed when needed
        this.textNodes = null;           // Array of text nodes in order (when using setTextNodes)
    }

    // Method to set text nodes - now uses shared collection logic for consistency
    setTextNodes(textNodes, engine) {
        const prefix = '[TEXT_COLLECTION:search-via-setTextNodes]';
        console.debug(prefix, 'ENTER - discarding provided', textNodes.length, 'text nodes, using shared collection instead');
        this.textContent = '';

        // Instead of using the provided textNodes, use shared collection for consistency
        // This ensures search and highlight phases use identical text node filtering
        const freshTextNodes = collectCurrentTextNodes(this, engine, 'search');
        this.textNodes = freshTextNodes.slice(); // Store a copy of the fresh text nodes array
        
        let currentOffset = 0;
        for (let i = 0; i < freshTextNodes.length; i++) {
            const node = freshTextNodes[i];
            const nodeText = node.textContent;
            if (verbose) {
                console.debug(prefix, 'processing node', i + 1, 'offset:', currentOffset, 'length:', nodeText.length, 'content:', JSON.stringify(nodeText), 'parent:', node.parentElement?.tagName);
            }
            this.textContent += nodeText;
            currentOffset += nodeText.length;
        }

        console.debug(prefix, 'COMPLETE - collected', freshTextNodes.length, 'nodes, total length:', this.textContent.length);
        console.debug(prefix, 'final textContent:', JSON.stringify(this.textContent.substring(0, 100) + (this.textContent.length > 100 ? '...' : '')));
    }

    collectTextNodes(engine) {
        const prefix = '[TEXT_COLLECTION:search]';
        console.debug(prefix, 'ENTER - element:', this.element.tagName, 'id:', this.element.id, 'className:', this.element.className);
        this.textContent = '';

        // Use the shared text node collection function for consistency
        const textNodes = collectCurrentTextNodes(this, engine, 'search');
        
        let currentOffset = 0;
        for (let i = 0; i < textNodes.length; i++) {
            const node = textNodes[i];
            const nodeText = node.textContent;
            if (verbose) {
                console.debug(prefix, 'processing node', i + 1, 'offset:', currentOffset, 'length:', nodeText.length, 'content:', JSON.stringify(nodeText), 'parent:', node.parentElement?.tagName);
            }
            this.textContent += nodeText;
            currentOffset += nodeText.length;
        }

        console.debug(prefix, 'COMPLETE - collected', textNodes.length, 'nodes, total length:', this.textContent.length);
        console.debug(prefix, 'final textContent:', JSON.stringify(this.textContent.substring(0, 100) + (this.textContent.length > 100 ? '...' : '')));
    }

    updateBounds() {
        this.bounds = _getBoundingClientRect.call(this.element);
    }

    containsPoint(x, y) {
        if (!this.bounds) this.updateBounds();
        return x >= this.bounds.left && x <= this.bounds.right &&
               y >= this.bounds.top && y <= this.bounds.bottom;
    }
}
