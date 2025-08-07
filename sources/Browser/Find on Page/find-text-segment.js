class TextSegment extends Segment {
    constructor(index, element) {
        super('text', index);
        this.element = element;           // The block DOM element
        this.textContent = '';           // Concatenated text from all text nodes
        this.bounds = null;              // DOMRect - will be computed when needed
    }

    collectTextNodes(engine) {
        console.debug('TextSegment.collectTextNodes: ENTER - element:', this.element.tagName, 'id:', this.element.id, 'className:', this.element.className);
        this.textContent = '';
        let nodeCount = 0;

        const walker = _createTreeWalker(
            this.element,
            _SHOW_TEXT,
            {
                acceptNode: (node) => {
                    const parent = node.parentElement;
                    if (!parent) return _FILTER_REJECT;

                    // Skip script and style
                    const tag = parent.tagName;
                    if (tag === 'SCRIPT' || tag === 'STYLE') {
                        return _FILTER_REJECT;
                    }

                    // Skip find highlight spans from other instances (they may be hidden)
                    // These are temporary DOM modifications that shouldn't affect text collection
                    if (parent.classList && (
                        parent.classList.contains('iterm-find-highlight') ||
                        parent.classList.contains('iterm-find-highlight-current') ||
                        parent.classList.contains('iterm-find-removed')
                    )) {
                        // Accept the text node - it's part of the original content
                        return _FILTER_ACCEPT;
                    }

                    // Check if node is hidden and try to find revealer
                    if (engine && isHidden(parent)) {
                        const rev = firstRevealableAncestor(parent);
                        if (!rev) {
                            engine.hiddenSkippedCount++;
                            engine.log('reject hidden node', node.textContent.slice(0, 40));
                            return _FILTER_REJECT;
                        } else {
                            node._itermReveal = rev;
                            engine.log('accept hidden via revealer', rev.tagName, node.textContent.slice(0, 40));
                        }
                    }

                    // Skip completely empty text nodes, but keep whitespace-containing nodes
                    if (!node.textContent || node.textContent.length === 0) {
                        return _FILTER_REJECT;
                    }

                    return _FILTER_ACCEPT;
                }
            }
        );

        let node;
        let currentOffset = 0;
        while (node = _TreeWalker_nextNode.call(walker)) {
            nodeCount++;
            const nodeText = node.textContent;
            console.debug('TextSegment.collectTextNodes: node', nodeCount, 'offset:', currentOffset, 'length:', nodeText.length, 'content:', JSON.stringify(nodeText), 'parent:', node.parentElement?.tagName);
            this.textContent += nodeText;
            currentOffset += nodeText.length;
        }

        console.debug('TextSegment.collectTextNodes: COMPLETE - collected', nodeCount, 'nodes, total length:', this.textContent.length);
        console.debug('TextSegment.collectTextNodes: final textContent:', JSON.stringify(this.textContent.substring(0, 100) + (this.textContent.length > 100 ? '...' : '')));
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
