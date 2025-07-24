(function() {
    'use strict';

    // ==============================
    //  Block-Based Find Engine
    // ==============================

    const TAG = '[iTermCustomFind-BlockBased]';
    const sessionSecret = "{{SECRET}}";
    const DEFAULT_INSTANCE_ID = 'default';

    // Global registry of engines on this page
    const INSTANCES = new Map();

    // Inject styles once
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

    function injectStyles() {
        if (document.getElementById('iterm-find-styles')) {
            return;
        }

        if (!document.head) {
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', injectStyles, { once: true });
                console.debug(TAG, 'Deferring style injection until DOMContentLoaded');
                return;
            }
            console.debug(TAG, 'No document.head available');
            return;
        }

        const styleElement = document.createElement('style');
        styleElement.id = 'iterm-find-styles';
        styleElement.textContent = highlightStyles;
        document.head.appendChild(styleElement);
        console.debug(TAG, 'Styles injected');
    }
    injectStyles();

    // ------------------------------
    // Block-Based Data Structures
    // ------------------------------

    class TextNodeMap {
        constructor() {
            // Maps text position → {node: TextNode, offset: number}
            this.positionToNode = new Map();
            // Maps text node → {start: number, end: number} in block text
            this.nodeToPosition = new Map();
        }

        addTextNode(node, startPos) {
            const text = node.textContent || '';
            const endPos = startPos + text.length;

            // Store node position range
            this.nodeToPosition.set(node, { start: startPos, end: endPos, revealer: node._itermReveal || null });

            // Store position to node mapping for each character
            // For empty nodes, still create a mapping at the start position
            if (text.length === 0) {
                this.positionToNode.set(startPos, { node: node, offset: 0, revealer: node._itermReveal || null });
            } else {
                for (let i = 0; i < text.length; i++) {
                    this.positionToNode.set(startPos + i, { node: node, offset: i, revealer: node._itermReveal || null });
                }
            }

            return endPos;
        }

        getNodeAtPosition(position) {
            return this.positionToNode.get(position);
        }

        getPositionRange(node) {
            return this.nodeToPosition.get(node);
        }
    }

    class BlockSegment {
        constructor(element) {
            this.element = element;           // The block DOM element
            this.textContent = '';           // Concatenated text from all text nodes
            this.textNodeMap = new TextNodeMap();
            this.bounds = null;              // DOMRect - will be computed when needed
            this.globalStart = 0;            // Start position in global buffer
            this.globalEnd = 0;              // End position in global buffer
        }

        collectTextNodes(engine) {
            this.textContent = '';
            this.textNodeMap = new TextNodeMap();

            let position = 0;
            const walker = document.createTreeWalker(
                this.element,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode: (node) => {
                        const parent = node.parentElement;
                        if (!parent) return NodeFilter.FILTER_REJECT;

                        // Skip script and style
                        const tag = parent.tagName;
                        if (tag === 'SCRIPT' || tag === 'STYLE') {
                            return NodeFilter.FILTER_REJECT;
                        }

                        // Check if node is hidden and try to find revealer
                        if (engine && engine.isHidden(parent)) {
                            const rev = engine.firstRevealableAncestor(parent);
                            if (!rev) {
                                engine.hiddenSkippedCount++;
                                engine.log('reject hidden node', node.textContent.slice(0, 40));
                                return NodeFilter.FILTER_REJECT;
                            } else {
                                node._itermReveal = rev;
                                engine.log('accept hidden via revealer', rev.tagName, node.textContent.slice(0, 40));
                            }
                        }

                        // Skip completely empty text nodes, but keep whitespace-containing nodes
                        if (!node.textContent || node.textContent.length === 0) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        return NodeFilter.FILTER_ACCEPT;
                    }
                }
            );

            let node;
            while (node = walker.nextNode()) {
                position = this.textNodeMap.addTextNode(node, position);
                this.textContent += node.textContent;
            }
        }

        updateBounds() {
            this.bounds = this.element.getBoundingClientRect();
        }

        containsPoint(x, y) {
            if (!this.bounds) this.updateBounds();
            return x >= this.bounds.left && x <= this.bounds.right &&
                   y >= this.bounds.top && y <= this.bounds.bottom;
        }
    }

    // ------------------------------
    // Utility Functions
    // ------------------------------

    function safeStringify(obj) {
        try {
            return JSON.stringify(obj);
        } catch (_) {
            return String(obj);
        }
    }

    const SAFE_REVEAL_SELECTORS = [
        'details:not([open])',
        '.mw-collapsible.mw-collapsed',
        '.mw-collapsible:not(.mw-expanded)',
        'tr[hidden="until-found"]',
        '.accordion',
        '[aria-expanded="false"]',
        '[data-collapsed="true"]'
    ];

    function ancestors(el) {
        const arr = [];
        for (let e = el; e; e = e.parentElement) {
            arr.push(e);
        }
        return arr;
    }

    const BLOCK_ELEMENTS = new Set([
        'ADDRESS', 'ARTICLE', 'ASIDE', 'BLOCKQUOTE', 'BR', 'DD', 'DIV',
        'DL', 'DT', 'FIELDSET', 'FIGCAPTION', 'FIGURE', 'FOOTER', 'FORM',
        'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEADER', 'HR', 'LI', 'MAIN',
        'NAV', 'OL', 'P', 'PRE', 'SECTION', 'TABLE', 'TD', 'TH', 'TR', 'UL'
    ]);

    function isBlockElement(element) {
        return BLOCK_ELEMENTS.has(element.tagName);
    }

    // ==============================
    //  Block-Based Find Engine Class
    // ==============================

    class FindEngine {
        constructor(instanceId) {
            this.instanceId = instanceId;

            // ---------- State ----------
            this.currentSearchTerm = '';
            this.currentMatchIndex = -1;
            this.searchMode = 'caseSensitive';
            this.contextLen = 0;

            // Block-based storage
            this.blocks = [];                // Array of BlockSegment instances
            this.globalBuffer = '';          // Concatenated text from all blocks
            this.matches = [];               // [{ blockIndex, blockStart, blockEnd, globalStart, globalEnd, els, revealers }]
            this.highlightedElements = [];
            this.hiddenSkippedCount = 0;

            // details elements we opened automatically for *any* match, so we can close on clear
            this.globallyAutoOpenedDetails = new Set();

            // other elements we force-visible; array of restore records
            this.revealRestores = [];

            // Click tracking
            this.lastClickLocation = null;   // { blockIndex, position }
            this.useClickLocationForNext = false;

            // Listeners
            this.boundHandleClick = (event) => { this.handleClick(event); };
            this.boundHandleNavigation = () => { this.clearClickLocation(); };

            document.addEventListener('click', this.boundHandleClick, true);
            window.addEventListener('beforeunload', this.boundHandleNavigation);
            window.addEventListener('pagehide', this.boundHandleNavigation);
        }

        log(...args) {
            const message = `${TAG} [${this.instanceId}] ${args.map(a => (typeof a === 'object' ? safeStringify(a) : a)).join(' ')}`;
            console.debug(message);
            console.log(message); // Also log to regular console for visibility
        }

        // ---------- Visibility helpers ----------
        isHidden(el) {
            for (let e = el; e; e = e.parentElement) {
                if (e.hasAttribute('hidden')) { return true; }
                if (e.getAttribute('aria-hidden') === 'true') { return true; }
                const cs = getComputedStyle(e);
                if (cs.display === 'none' || cs.visibility === 'hidden') { return true; }
            }
            return false;
        }

        firstRevealableAncestor(el) {
            for (let e = el; e; e = e.parentElement) {
                // Check static selectors first
                if (SAFE_REVEAL_SELECTORS.some(sel => { try { return e.matches(sel); } catch (_) { return false; } })) {
                    return e;
                }

                // Check for CSS-hidden elements that can be revealed
                try {
                    const cs = getComputedStyle(e);
                    if (cs.display === 'none' || cs.visibility === 'hidden') {
                        return e;
                    }
                    if (e.hasAttribute('hidden')) {
                        return e;
                    }
                    if (e.getAttribute('aria-hidden') === 'true') {
                        return e;
                    }
                } catch (_) {
                    // Ignore getComputedStyle errors
                }
            }
            return null;
        }

        forceVisible(el) {
            try {
                if (el.tagName === 'DETAILS' && !el.open) {
                    el.open = true;
                    this.globallyAutoOpenedDetails.add(el);
                    return;
                }

                if (el.hasAttribute('hidden')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'hidden', oldValue: '' });
                    el.removeAttribute('hidden');
                }

                if (el.getAttribute('aria-hidden') === 'true') {
                    this.revealRestores.push({ el, type: 'attr', attr: 'aria-hidden', oldValue: 'true' });
                    el.setAttribute('aria-hidden', 'false');
                }

                const cs = getComputedStyle(el);
                if (cs.display === 'none') {
                    this.revealRestores.push({ el, type: 'style-display', oldValue: el.style.display });
                    el.style.display = 'block';
                }
                if (cs.visibility === 'hidden') {
                    this.revealRestores.push({ el, type: 'style-visibility', oldValue: el.style.visibility });
                    el.style.visibility = 'visible';
                }

                if (el.matches('.mw-collapsible')) {
                    if (el.classList.contains('collapsed')) {
                        this.revealRestores.push({ el, type: 'class-remove-add', removed: 'collapsed' });
                        el.classList.remove('collapsed');
                    }
                }
                if (el.matches('[aria-expanded="false"]')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'aria-expanded', oldValue: el.getAttribute('aria-expanded') });
                    el.setAttribute('aria-expanded', 'true');
                }
                if (el.matches('[data-collapsed="true"]')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'data-collapsed', oldValue: el.getAttribute('data-collapsed') });
                    el.setAttribute('data-collapsed', 'false');
                }
            } catch (e) {
                this.log('forceVisible error:', e);
            }
        }

        // ---------- Block Collection ----------

        collectBlocks(root) {
            this.log('collectBlocks: starting block collection');
            this.blocks = [];
            this.globalBuffer = '';

            // Find all block elements
            const blockElements = this.findBlockElements(root);

            let globalPosition = 0;

            for (const element of blockElements) {
                const block = new BlockSegment(element);
                block.collectTextNodes(this);

                if (block.textContent.length > 0) {
                    // Set global positions - no spaces between blocks to preserve semantic boundaries
                    block.globalStart = globalPosition;
                    block.globalEnd = globalPosition + block.textContent.length;

                    this.blocks.push(block);
                    this.globalBuffer += block.textContent;
                    globalPosition += block.textContent.length;
                }
            }

            this.log(`collectBlocks: found ${this.blocks.length} blocks, buffer length: ${this.globalBuffer.length}`);
        }

        findBlockElements(root) {
            const blocks = [];
            const seen = new Set();

            function traverse(element) {
                if (seen.has(element)) return;
                seen.add(element);

                if (isBlockElement(element)) {
                    // Check if this block contains any child blocks
                    let hasChildBlocks = false;
                    for (const child of element.children) {
                        if (isBlockElement(child)) {
                            hasChildBlocks = true;
                            break;
                        }
                    }

                    // Only add blocks that don't contain other blocks (leaf blocks)
                    if (!hasChildBlocks) {
                        blocks.push(element);
                    } else {
                        // This block has child blocks, so traverse children instead
                        for (const child of element.children) {
                            traverse(child);
                        }
                    }
                } else {
                    // Not a block element, traverse children
                    for (const child of element.children) {
                        traverse(child);
                    }
                }
            }

            traverse(root);
            return blocks;
        }

        // ---------- Click Detection ----------

        handleClick(event) {
            this.log('handleClick: detected at', event.clientX, event.clientY);

            const clickLocation = this.getClickLocation(event.clientX, event.clientY);
            if (clickLocation) {
                this.lastClickLocation = clickLocation;
                this.useClickLocationForNext = true;
                this.log('handleClick: recorded location', clickLocation);
            }
        }

        getClickLocation(x, y) {
            this.log('getClickLocation: called with coordinates', x, y);

            // Find which block contains the click
            for (let i = 0; i < this.blocks.length; i++) {
                const block = this.blocks[i];
                if (block.containsPoint(x, y)) {
                    this.log('getClickLocation: click is in block', i);

                    // Get caret position within block
                    const range = document.caretRangeFromPoint(x, y);
                    if (range && range.startContainer.nodeType === Node.TEXT_NODE) {
                        const textNode = range.startContainer;
                        const offset = range.startOffset;

                        this.log('getClickLocation: caret found in text node, offset', offset);
                        this.log('getClickLocation: text node content:', textNode.textContent);
                        this.log('getClickLocation: text node parent element:', textNode.parentElement.tagName, textNode.parentElement.className);

                        // Use DOM-invariant position finding instead of cached textNodeMap
                        // This walks the current DOM state and works after highlighting
                        const walker = document.createTreeWalker(
                            block.element,
                            NodeFilter.SHOW_TEXT,
                            {
                                acceptNode: (node) => {
                                    const parent = node.parentElement;
                                    if (!parent) return NodeFilter.FILTER_REJECT;

                                    const tag = parent.tagName;
                                    if (tag === 'SCRIPT' || tag === 'STYLE') {
                                        return NodeFilter.FILTER_REJECT;
                                    }

                                    if (!node.textContent || node.textContent.length === 0) {
                                        return NodeFilter.FILTER_REJECT;
                                    }

                                    return NodeFilter.FILTER_ACCEPT;
                                }
                            }
                        );

                        let currentPos = 0;
                        let node;

                        while (node = walker.nextNode()) {
                            this.log('getClickLocation: walking text node at pos', currentPos, 'content:', node.textContent.substring(0, 20));
                            if (node === textNode) {
                                // Found our clicked text node
                                const finalPosition = currentPos + offset;
                                this.log('getClickLocation: found clicked text node at block position', finalPosition);
                                return { blockIndex: i, position: finalPosition };
                            }
                            currentPos += node.textContent.length;
                        }

                        this.log('getClickLocation: ERROR - could not find clicked text node in walker');
                    } else {
                        this.log('getClickLocation: no valid caret range found');
                    }
                } else {
                    this.log('getClickLocation: click not in block', i, 'bounds:', block.bounds);
                }
            }

            this.log('getClickLocation: click not in any block');
            return null;
        }

        clearClickLocation() {
            this.lastClickLocation = null;
            this.useClickLocationForNext = false;
        }

        getStartingMatchIndex() {
            this.log('getStartingMatchIndex: called');
            this.log('getStartingMatchIndex: lastClickLocation:', this.lastClickLocation);
            this.log('getStartingMatchIndex: lastClickLocation type:', typeof this.lastClickLocation);
            this.log('getStartingMatchIndex: lastClickLocation === null?', this.lastClickLocation === null);
            this.log('getStartingMatchIndex: !lastClickLocation?', !this.lastClickLocation);
            this.log('getStartingMatchIndex: matches.length:', this.matches.length);

            if (!this.lastClickLocation || this.matches.length === 0) {
                this.log('getStartingMatchIndex: no click location or no matches, returning 0');
                return 0;
            }

            const { blockIndex, position } = this.lastClickLocation;
            this.log('getStartingMatchIndex: click was at block', blockIndex, 'position', position);

            // Log some matches around the click position for context
            this.log('getStartingMatchIndex: examining matches:');
            for (let i = 0; i < Math.min(10, this.matches.length); i++) {
                const match = this.matches[i];
                this.log(`  match ${i}: block ${match.blockIndex}, positions ${match.blockStart}-${match.blockEnd} (global ${match.globalStart}-${match.globalEnd})`);
            }

            // Find first match after click position
            for (let i = 0; i < this.matches.length; i++) {
                const match = this.matches[i];
                this.log(`getStartingMatchIndex: checking match ${i}: block ${match.blockIndex} pos ${match.blockStart}-${match.blockEnd}`);

                if (match.blockIndex > blockIndex ||
                    (match.blockIndex === blockIndex && match.blockStart >= position)) {
                    this.log('getStartingMatchIndex: found first match after click at index', i);
                    return i;
                }
            }

            // No match after click, wrap to beginning
            this.log('getStartingMatchIndex: no match after click, wrapping to 0');
            return 0;
        }

        // ---------- Search ----------

        findMatches(regex) {
            this.matches = [];

            for (let blockIndex = 0; blockIndex < this.blocks.length; blockIndex++) {
                const block = this.blocks[blockIndex];
                const blockMatches = this.findMatchesInBlock(regex, block, blockIndex);
                this.matches.push(...blockMatches);
            }

            this.log(`findMatches: found ${this.matches.length} total matches`);
        }

        findMatchesInBlock(regex, block, blockIndex) {
            const matches = [];
            regex.lastIndex = 0;

            let match;
            while ((match = regex.exec(block.textContent)) !== null) {
                matches.push({
                    blockIndex: blockIndex,
                    blockStart: match.index,
                    blockEnd: match.index + match[0].length,
                    globalStart: block.globalStart + match.index,
                    globalEnd: block.globalStart + match.index + match[0].length,
                    els: [], // Will be filled during highlighting
                    revealers: new Set() // Will be filled during highlighting
                });

                if (match[0].length === 0) {
                    regex.lastIndex++;
                }
            }

            return matches;
        }

        // ---------- Highlighting ----------

        highlight() {
            this.log('highlight: starting with', this.matches.length, 'matches');

            let highlightedCount = 0;
            for (const match of this.matches) {
                try {
                    this.highlightMatch(match);
                    highlightedCount++;
                } catch (e) {
                    this.log('highlight: error highlighting match', match, ':', e);
                }
            }

            this.log('highlight: completed,', highlightedCount, 'of', this.matches.length, 'matches highlighted');
        }

        highlightMatch(match) {
            const block = this.blocks[match.blockIndex];
            const elements = [];
            const revealers = new Set();

            this.log('highlightMatch: attempting to highlight match at block', match.blockIndex, 'positions', match.blockStart, '-', match.blockEnd);

            // Collect revealers for this match range
            for (let pos = match.blockStart; pos < match.blockEnd; pos++) {
                const posResult = this.findPositionInBlock(block, pos);
                if (posResult && posResult.revealer) {
                    revealers.add(posResult.revealer);
                }
            }

            // Use block-invariant approach: find position by walking the tree each time
            const startResult = this.findPositionInBlock(block, match.blockStart);
            const endResult = this.findPositionInBlock(block, match.blockEnd - 1); // -1 because end is exclusive

            if (!startResult || !endResult) {
                this.log('highlightMatch: could not find positions in block');
                return;
            }

            // Collect revealers from start and end nodes too
            if (startResult.revealer) {
                revealers.add(startResult.revealer);
            }
            if (endResult.revealer) {
                revealers.add(endResult.revealer);
            }

            try {
                const range = document.createRange();
                range.setStart(startResult.node, startResult.offset);
                range.setEnd(endResult.node, endResult.offset + 1); // +1 because we want inclusive end

                // Extract the content from the range
                const contents = range.extractContents();

                // Create the highlight span
                const span = document.createElement('span');
                span.className = 'iterm-find-highlight';
                span.setAttribute('data-iterm-id', this.instanceId);
                span.appendChild(contents);

                // Insert the span at the range position
                range.insertNode(span);

                elements.push(span);
                this.highlightedElements.push(span);

                this.log('highlightMatch: successfully highlighted match');
            } catch (e) {
                this.log('highlightMatch: error highlighting match:', e);
                // Fallback: try highlighting each character individually
                for (let pos = match.blockStart; pos < match.blockEnd; pos++) {
                    const charResult = this.findPositionInBlock(block, pos);
                    if (charResult) {
                        try {
                            const range = document.createRange();
                            range.setStart(charResult.node, charResult.offset);
                            range.setEnd(charResult.node, charResult.offset + 1);

                            const span = document.createElement('span');
                            span.className = 'iterm-find-highlight';
                            span.setAttribute('data-iterm-id', this.instanceId);

                            const contents = range.extractContents();
                            span.appendChild(contents);
                            range.insertNode(span);

                            elements.push(span);
                            this.highlightedElements.push(span);

                            // Collect revealer from individual char if present
                            if (charResult.revealer) {
                                revealers.add(charResult.revealer);
                            }
                        } catch (e2) {
                            // Skip this character if it fails
                            continue;
                        }
                    }
                }
            }

            match.els = elements;
            match.revealers = revealers;
        }

        findPositionInBlock(block, position) {
            // Walk the block's DOM tree and count characters until we reach the position
            const walker = document.createTreeWalker(
                block.element,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode: (node) => {
                        const parent = node.parentElement;
                        if (!parent) return NodeFilter.FILTER_REJECT;

                        // Skip script and style
                        const tag = parent.tagName;
                        if (tag === 'SCRIPT' || tag === 'STYLE') {
                            return NodeFilter.FILTER_REJECT;
                        }

                        // Skip completely empty text nodes, but keep whitespace-containing nodes
                        if (!node.textContent || node.textContent.length === 0) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        return NodeFilter.FILTER_ACCEPT;
                    }
                }
            );

            let currentPos = 0;
            let node;

            while (node = walker.nextNode()) {
                const nodeText = node.textContent || '';
                const nodeStart = currentPos;
                const nodeEnd = currentPos + nodeText.length;

                if (position >= nodeStart && position < nodeEnd) {
                    // Found the node containing this position
                    return {
                        node: node,
                        offset: position - nodeStart,
                        revealer: node._itermReveal || null
                    };
                }

                currentPos = nodeEnd;
            }

            return null;
        }

        // ---------- Auto-reveal ----------
        ensureVisibleForMatch(match) {
            if (!match || !match.els || match.els.length === 0) {
                return;
            }

            const firstEl = match.els[0];
            const needOpen = new Set();

            ancestors(firstEl).forEach(el => {
                if (el.tagName === 'DETAILS' && !el.open) {
                    needOpen.add(el);
                }
            });

            needOpen.forEach(d => {
                d.open = true;
                this.globallyAutoOpenedDetails.add(d);
            });

            if (needOpen.size > 0) {
                this.log('ensureVisibleForMatch auto-opened details (ancestor):', needOpen.size);
            }

            if (match.revealers && match.revealers.size > 0) {
                match.revealers.forEach(el => {
                    this.forceVisible(el);
                    ancestors(el).forEach(ae => {
                        if (this.isHidden(ae)) {
                            this.forceVisible(ae);
                        }
                    });
                });
                this.log('ensureVisibleForMatch processed revealers:', match.revealers.size);
            }

            ancestors(firstEl).forEach(ae => {
                if (this.isHidden(ae)) {
                    this.forceVisible(ae);
                }
            });
        }

        // ---------- Clear ----------

        clearHighlights() {
            this.log('clearHighlights: starting');

            const spans = document.querySelectorAll(
                `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
                `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
            );

            const parents = new Set();
            spans.forEach(span => {
                const parent = span.parentNode;
                if (!parent) return;

                while (span.firstChild) {
                    parent.insertBefore(span.firstChild, span);
                }
                parent.removeChild(span);
                parents.add(parent);
            });

            // Normalize text nodes
            parents.forEach(p => p.normalize());

            // Restore revealed elements
            this.globallyAutoOpenedDetails.forEach(d => {
                d.open = false;
            });
            this.globallyAutoOpenedDetails.clear();

            this.revealRestores.forEach(rec => {
                const el = rec.el;
                if (!el) { return; }
                if (rec.type === 'style-display') {
                    el.style.display = rec.oldValue;
                } else if (rec.type === 'style-visibility') {
                    el.style.visibility = rec.oldValue;
                } else if (rec.type === 'attr') {
                    if (rec.oldValue === null || rec.oldValue === '') {
                        el.removeAttribute(rec.attr);
                    } else {
                        el.setAttribute(rec.attr, rec.oldValue);
                    }
                } else if (rec.type === 'class-remove-add') {
                    if (rec.removed) { el.classList.add(rec.removed); }
                }
            });
            this.revealRestores = [];

            this.highlightedElements = [];
            this.matches = [];
            this.blocks = [];
            this.globalBuffer = '';
            this.currentMatchIndex = -1;
            this.hiddenSkippedCount = 0;

            this.log('clearHighlights: completed');
        }

        // ---------- Regex Creation ----------

        createSearchRegex(term) {
            let flags = 'g';
            let pattern = term;

            switch (this.searchMode) {
                case 'caseSensitiveRegex':
                    break;
                case 'caseInsensitiveRegex':
                    flags += 'i';
                    break;
                case 'caseSensitive':
                    pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    break;
                case 'caseInsensitive':
                default:
                    pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    flags += 'i';
                    break;
            }

            try {
                return new RegExp(pattern, flags);
            } catch (e) {
                this.log('createSearchRegex: failed, using fallback', e);
                const fallback = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                return new RegExp(fallback, flags);
            }
        }

        // ---------- Navigation ----------

        setCurrent(idx) {
            if (this.matches.length === 0) {
                this.log('setCurrent: no matches');
                return;
            }

            // Clear previous current highlight
            if (this.currentMatchIndex >= 0 && this.currentMatchIndex < this.matches.length) {
                this.matches[this.currentMatchIndex].els.forEach(e => {
                    e.className = 'iterm-find-highlight';
                    e.setAttribute('data-iterm-id', this.instanceId);
                });
            }

            // Set new current
            this.currentMatchIndex = ((idx % this.matches.length) + this.matches.length) % this.matches.length;
            const current = this.matches[this.currentMatchIndex];

            this.ensureVisibleForMatch(current);

            current.els.forEach(e => {
                e.className = 'iterm-find-highlight-current';
                e.setAttribute('data-iterm-id', this.instanceId);
            });

            // Scroll into view
            if (current.els.length > 0) {
                current.els[0].scrollIntoView({
                    behavior: '{{SCROLL_BEHAVIOR}}',
                    block: 'center',
                    inline: 'center'
                });
            }

            this.reportResults(false);
        }

        // ---------- Commands ----------

        startFind(term, mode, contextLen) {
            this.log('=== START FIND ===');
            this.log('startFind: term=' + term + ', mode=' + mode + ', contextLen=' + contextLen);

            this.clearHighlights();
            this.clearClickLocation(); // Force clear any persisting click location
            this.useClickLocationForNext = false;
            this.currentSearchTerm = term;
            this.searchMode = mode || 'caseInsensitive';
            this.contextLen = contextLen || 0;

            if (!term || typeof term !== 'string' || term.trim().length === 0) {
                this.log('startFind: ERROR - No valid search term provided, term:', term);
                this.matches = [];
                this.currentMatchIndex = -1;
                this.reportResults(true);
                return;
            }

            if (!document.body) {
                this.log('startFind: ERROR - No document.body found');
                this.reportResults(true);
                return;
            }

            this.log('startFind: Creating regex for term:', term);
            const regex = this.createSearchRegex(term);
            this.log('startFind: Regex created:', regex);

            this.log('startFind: Collecting blocks from document.body');
            this.collectBlocks(document.body);

            this.log('startFind: Finding matches in', this.blocks.length, 'blocks');
            this.findMatches(regex);

            this.log('startFind: Found', this.matches.length, 'total matches');

            try {
                this.highlight();
                this.log('startFind: Highlighting completed');
            } catch (e) {
                this.log('startFind: ERROR in highlighting, but continuing:', e);
            }

            // Set current match before reporting results to ensure consistent state
            if (this.matches.length > 0) {
                const startIndex = this.getStartingMatchIndex();
                this.log('startFind: Setting current match to index', startIndex);

                // Set current match and ensure it's visible
                this.currentMatchIndex = ((startIndex % this.matches.length) + this.matches.length) % this.matches.length;
                const current = this.matches[this.currentMatchIndex];

                // Ensure the match is visible (auto-reveal)
                this.ensureVisibleForMatch(current);

                current.els.forEach(e => {
                    e.className = 'iterm-find-highlight-current';
                    e.setAttribute('data-iterm-id', this.instanceId);
                });

                // Scroll into view
                if (current.els.length > 0) {
                    current.els[0].scrollIntoView({
                        behavior: '{{SCROLL_BEHAVIOR}}',
                        block: 'center',
                        inline: 'center'
                    });
                }

                this.log('startFind: Current match set to index', this.currentMatchIndex);
            } else {
                this.log('startFind: No matches found - not setting current');
            }

            this.log('startFind: Reporting results...');
            this.reportResults(true);

            this.log('=== START FIND COMPLETE ===');
        }

        findNext() {
            this.log('findNext: called');
            this.log('findNext: matches.length:', this.matches.length);
            this.log('findNext: currentMatchIndex:', this.currentMatchIndex);
            this.log('findNext: useClickLocationForNext:', this.useClickLocationForNext);

            if (this.matches.length === 0) {
                this.log('findNext: no matches, returning');
                return;
            }

            if (this.useClickLocationForNext) {
                this.log('findNext: using click location for next');
                const startIndex = this.getStartingMatchIndex();
                this.log('findNext: getStartingMatchIndex returned:', startIndex);
                this.useClickLocationForNext = false;
                this.log('findNext: setting current to:', startIndex);
                this.setCurrent(startIndex);
            } else {
                this.log('findNext: normal next, going to:', this.currentMatchIndex + 1);
                this.setCurrent(this.currentMatchIndex + 1);
            }
        }

        findPrevious() {
            if (this.matches.length === 0) return;

            if (this.useClickLocationForNext) {
                const startIndex = this.getStartingMatchIndex();
                this.useClickLocationForNext = false;
                this.setCurrent(startIndex - 1);
            } else {
                this.setCurrent(this.currentMatchIndex - 1);
            }
        }

        // Reveal a specific match by its identifier
        reveal(identifier) {
            if (!identifier) {
                this.log('reveal: no identifier provided');
                return;
            }

            // Find the match by comparing buffer positions and text
            const matchIndex = this.matches.findIndex(m =>
                m.globalStart === identifier.bufferStart &&
                m.globalEnd === identifier.bufferEnd &&
                this.globalBuffer.slice(m.globalStart, m.globalEnd) === identifier.text
            );

            if (matchIndex === -1) {
                this.log('reveal: match not found for identifier', identifier);
                return;
            }

            this.log('reveal: found match at index', matchIndex);

            // Make this the current match and scroll to it
            // setCurrent will handle scrolling and send currentChanged message
            this.setCurrent(matchIndex);
        }

        // Get current bounding box for a match using its stable identifier
        getMatchBounds(identifier) {
            if (!identifier) {
                this.log('getMatchBounds: no identifier provided');
                return {};
            }

            // Find the match by comparing buffer positions and text
            const match = this.matches.find(m =>
                m.globalStart === identifier.bufferStart &&
                m.globalEnd === identifier.bufferEnd &&
                this.globalBuffer.slice(m.globalStart, m.globalEnd) === identifier.text
            );

            if (!match) {
                this.log('getMatchBounds: match not found for identifier', identifier);
                return {};
            }

            // Get bounding boxes for all elements of this match
            const elementBounds = match.els.map(el => {
                const rect = el.getBoundingClientRect();
                // Convert viewport-relative coordinates to document-relative coordinates
                return {
                    left: rect.left + window.scrollX,
                    top: rect.top + window.scrollY,
                    right: rect.right + window.scrollX,
                    bottom: rect.bottom + window.scrollY
                };
            });

            if (elementBounds.length === 0) {
                this.log('getMatchBounds: match has no elements');
                return {};
            }

            // Compute the union bounding box that encompasses all elements
            let left = elementBounds[0].left;
            let top = elementBounds[0].top;
            let right = elementBounds[0].right;
            let bottom = elementBounds[0].bottom;

            for (let i = 1; i < elementBounds.length; i++) {
                const bounds = elementBounds[i];
                left = Math.min(left, bounds.left);
                top = Math.min(top, bounds.top);
                right = Math.max(right, bounds.right);
                bottom = Math.max(bottom, bounds.bottom);
            }

            const result = {
                x: left,
                y: top,
                width: right - left,
                height: bottom - top
            };

            this.log('getMatchBounds: returning bounds', result);
            return result;
        }

        // ---------- Hide/Show Results ----------

        hideResults() {
            this.log('hideResults: hiding all search result highlights');
            
            // Hide both regular and current highlights for this instance
            const highlights = document.querySelectorAll(
                `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
                `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
            );
            
            highlights.forEach(highlight => {
                // Add the hidden class to hide the highlight
                highlight.classList.add('iterm-find-removed');
            });
            
            this.log(`hideResults: hid ${highlights.length} highlight elements`);
        }

        showResults() {
            this.log('showResults: showing all search result highlights');
            
            // Show both regular and current highlights for this instance
            const highlights = document.querySelectorAll(
                `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
                `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
            );
            
            highlights.forEach(highlight => {
                // Remove the hidden class to show the highlight
                highlight.classList.remove('iterm-find-removed');
            });
            
            this.log(`showResults: showed ${highlights.length} highlight elements`);
        }

        // ---------- Context Extraction ----------

        extractContext(match) {
            this.log('extractContext: called for match at globalStart=' + match.globalStart + ', globalEnd=' + match.globalEnd);
            
            if (!this.contextLen || this.contextLen <= 0) {
                this.log('extractContext: no context length set, returning empty context');
                return {
                    contextBefore: '',
                    contextAfter: ''
                };
            }

            const matchStart = match.globalStart;
            const matchEnd = match.globalEnd;
            const bufferLength = this.globalBuffer.length;

            // Calculate context boundaries
            const contextBeforeStart = Math.max(0, matchStart - this.contextLen);
            const contextAfterEnd = Math.min(bufferLength, matchEnd + this.contextLen);

            // Extract context text with block boundary spacing
            let contextBefore = '';
            let contextAfter = '';

            if (contextBeforeStart < matchStart) {
                contextBefore = this.extractContextWithBlockSpacing(contextBeforeStart, matchStart);
                // Trim leading whitespace but preserve structure
                contextBefore = contextBefore.replace(/^\s+/, '');
            }

            if (contextAfterEnd > matchEnd) {
                contextAfter = this.extractContextWithBlockSpacing(matchEnd, contextAfterEnd);
                // Trim trailing whitespace but preserve structure
                contextAfter = contextAfter.replace(/\s+$/, '');
            }

            this.log('extractContext: contextBefore="' + contextBefore + '"');
            this.log('extractContext: contextAfter="' + contextAfter + '"');

            return {
                contextBefore: contextBefore,
                contextAfter: contextAfter
            };
        }

        extractContextWithBlockSpacing(start, end) {
            let result = '';
            let currentPos = start;

            // Find all block boundaries within the range
            const blockBoundaries = [];
            for (const block of this.blocks) {
                if (block.globalStart > start && block.globalStart < end) {
                    blockBoundaries.push(block.globalStart);
                }
            }

            // Sort boundaries
            blockBoundaries.sort((a, b) => a - b);

            // Extract text, adding spaces at block boundaries
            for (const boundary of blockBoundaries) {
                if (currentPos < boundary) {
                    result += this.globalBuffer.slice(currentPos, boundary);
                    result += ' '; // Add space at block boundary
                    currentPos = boundary;
                }
            }

            // Add remaining text
            if (currentPos < end) {
                result += this.globalBuffer.slice(currentPos, end);
            }

            return result;
        }

        // ---------- Reporting ----------

        reportResults(fullUpdate = false) {
            this.log('reportResults: called with fullUpdate=' + fullUpdate);
            this.log('reportResults: matches.length=' + this.matches.length);
            this.log('reportResults: currentMatchIndex=' + this.currentMatchIndex);
            this.log('reportResults: currentSearchTerm=' + this.currentSearchTerm);

            const matchIdentifiers = this.matches.map((m, index) => ({
                index: index,
                bufferStart: m.globalStart,
                bufferEnd: m.globalEnd,
                text: this.globalBuffer.slice(m.globalStart, m.globalEnd)
            }));

            this.log('reportResults: created', matchIdentifiers.length, 'match identifiers');

            // Extract contexts for each match (always create array for consistency)
            let contexts = undefined;
            if (fullUpdate) {
                contexts = this.matches.map((match, index) => {
                    const context = this.extractContext(match);
                    this.log('reportResults: extracted context for match', index, ':', context);
                    return context;
                });
                this.log('reportResults: created', contexts.length, 'contexts');
            }

            const payload = {
                sessionSecret,
                action: fullUpdate ? 'resultsUpdated' : 'currentChanged',
                data: {
                    instanceId: this.instanceId,
                    searchTerm: this.currentSearchTerm,
                    totalMatches: this.matches.length,
                    currentMatch: this.currentMatchIndex + 1,
                    matchIdentifiers: fullUpdate ? matchIdentifiers : undefined,
                    contexts: fullUpdate ? contexts : undefined,
                    hiddenSkipped: this.hiddenSkippedCount,
                    opToken: 0
                }
            };

            this.log('reportResults: payload action=' + payload.action);
            this.log('reportResults: payload data keys=' + Object.keys(payload.data).join(','));
            this.log('reportResults: sessionSecret=' + sessionSecret);

            try {
                this.log('reportResults: checking message handler...');
                if (!window.webkit) {
                    this.log('reportResults: ERROR - window.webkit not found');
                    return;
                }
                if (!window.webkit.messageHandlers) {
                    this.log('reportResults: ERROR - window.webkit.messageHandlers not found');
                    return;
                }
                if (!window.webkit.messageHandlers.iTermCustomFind) {
                    this.log('reportResults: ERROR - window.webkit.messageHandlers.iTermCustomFind not found');
                    return;
                }

                this.log('reportResults: posting message to Swift...');
                window.webkit.messageHandlers.iTermCustomFind.postMessage(payload);
                this.log('reportResults: message posted successfully');
            } catch (e) {
                this.log('reportResults: ERROR posting message:', e);
            }
        }

        handleFindCommand(command) {
            this.log('handleFindCommand:', command);

            switch (command.action) {
                case 'startFind':
                    this.startFind(command.searchTerm, command.searchMode, command.contextLength);
                    break;
                case 'findNext':
                    this.findNext();
                    break;
                case 'findPrevious':
                    this.findPrevious();
                    break;
                case 'clearFind':
                    this.clearHighlights();
                    this.currentSearchTerm = '';
                    this.reportResults(true);
                    break;
                case 'reveal':
                    this.reveal(command.identifier);
                    break;
                case 'hideResults':
                    this.hideResults();
                    break;
                case 'showResults':
                    this.showResults();
                    break;
                case 'updatePositions':
                    this.log('updatePositions command');
                    if (this.matches.length > 0) {
                        // Update block bounds if needed
                        this.blocks.forEach(block => block.updateBounds());
                        // No communication needed - Swift doesn't use positions
                    }
                    break;
                default:
                    this.log('Unknown action:', command.action);
            }
        }

        destroy() {
            this.clearHighlights();
            document.removeEventListener('click', this.boundHandleClick, true);
            window.removeEventListener('beforeunload', this.boundHandleNavigation);
            window.removeEventListener('pagehide', this.boundHandleNavigation);
            INSTANCES.delete(this.instanceId);
        }
    }

    // ==============================
    //  Public API
    // ==============================

    function getEngine(id) {
        const key = id || DEFAULT_INSTANCE_ID;
        let engine = INSTANCES.get(key);
        if (!engine) {
            engine = new FindEngine(key);
            INSTANCES.set(key, engine);
        }
        return engine;
    }

    function handleCommand(command) {
        const id = command.instanceId || DEFAULT_INSTANCE_ID;
        const engine = getEngine(id);
        return engine.handleFindCommand(command);
    }

    function destroyInstance(id) {
        const engine = INSTANCES.get(id);
        if (engine) {
            engine.destroy();
        }
    }

    function getDebugState(id) {
        const engine = INSTANCES.get(id || DEFAULT_INSTANCE_ID);
        if (!engine) return { error: 'No engine found' };

        // Create match identifiers with matched text
        const matchIdentifiers = engine.matches.map((m, index) => ({
            index: index,
            bufferStart: m.globalStart,
            bufferEnd: m.globalEnd,
            text: engine.globalBuffer.slice(m.globalStart, m.globalEnd)
        }));

        // Extract contexts for each match
        const contexts = engine.matches.map((match) => {
            return engine.extractContext(match);
        });

        return {
            lastClickLocation: engine.lastClickLocation,
            useClickLocationForNext: engine.useClickLocationForNext,
            currentMatchIndex: engine.currentMatchIndex,
            totalMatches: engine.matches.length,
            currentSearchTerm: engine.currentSearchTerm,
            matchIdentifiers: matchIdentifiers,
            contexts: contexts
        };
    }

    function clearStateWithoutResponse(id) {
        const engine = INSTANCES.get(id || DEFAULT_INSTANCE_ID);
        if (!engine) return { error: 'No engine found' };

        // Clear state without sending response to Swift
        engine.clearHighlights();
        engine.currentSearchTerm = '';
        if (engine.clearClickLocation) {
            engine.clearClickLocation();
        }

        return { cleared: true };
    }

    function refreshBlockBounds(id) {
        const engine = INSTANCES.get(id || DEFAULT_INSTANCE_ID);
        if (!engine) return { error: 'No engine found' };

        // Update bounds for all blocks
        let updatedCount = 0;
        if (engine.blocks && engine.blocks.length > 0) {
            engine.blocks.forEach(block => {
                block.updateBounds();
                updatedCount++;
            });
        }

        return { updated: updatedCount };
    }

    function getBlocks(id) {
        const engine = INSTANCES.get(id || DEFAULT_INSTANCE_ID);
        if (!engine) return { error: 'No engine found' };

        return {
            count: engine.blocks ? engine.blocks.length : 0,
            blocks: engine.blocks ? engine.blocks.map((block, index) => ({
                index: index,
                text: block.text ? block.text.substring(0, 50) : '',
                element: block.element ? block.element.tagName : 'unknown'
            })) : []
        };
    }

    function getMatchBoundsInEngine(instanceId, identifier) {
        const id = instanceId || DEFAULT_INSTANCE_ID;
        const engine = INSTANCES.get(id);
        if (!engine) {
            return { error: 'No engine found' };
        }
        return engine.getMatchBounds ? engine.getMatchBounds(identifier) : { error: 'Method not implemented' };
    }

    {{TEST_IMPLS}}

    // Expose API
    window.iTermCustomFind = {
        handleCommand,
        destroyInstance,
        getMatchBoundsInEngine,
        clearStateWithoutResponse
        {{TEST_FUNCTIONS}}
    };

    Object.freeze(window.iTermCustomFind);
    console.debug(TAG, 'Block-based find engine initialized');
    console.log('Block-based find engine initialized - visible in console');
})();
