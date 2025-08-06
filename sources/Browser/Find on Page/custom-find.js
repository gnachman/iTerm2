(function() {
    'use strict';

    {{INCLUDE:graph-discovery.js}}

    // ==============================
    //  Security: Native API Capture
    // ==============================

    // Capture all native DOM APIs before any user code can tamper with them
    const _createRange = document.createRange.bind(document);
    const _createTreeWalker = document.createTreeWalker.bind(document);
    const _createElement = document.createElement.bind(document);
    const _querySelectorAll = document.querySelectorAll.bind(document);
    const _getElementById = document.getElementById.bind(document);

    // Range prototype methods
    const _Range_setStart = Range.prototype.setStart;
    const _Range_setEnd = Range.prototype.setEnd;
    const _Range_extractContents = Range.prototype.extractContents;
    const _Range_insertNode = Range.prototype.insertNode;
    const _Range_surroundContents = Range.prototype.surroundContents;

    // TreeWalker/NodeFilter
    const _TreeWalker_nextNode = TreeWalker.prototype.nextNode;
    const _SHOW_TEXT = NodeFilter.SHOW_TEXT;
    const _FILTER_ACCEPT = NodeFilter.FILTER_ACCEPT;
    const _FILTER_REJECT = NodeFilter.FILTER_REJECT;

    // Element methods
    const _matches = Element.prototype.matches;
    const _getBoundingClientRect = Element.prototype.getBoundingClientRect;
    const _scrollIntoView = Element.prototype.scrollIntoView;
    const _appendChild = Element.prototype.appendChild;
    const _insertBefore = Element.prototype.insertBefore;
    const _removeChild = Element.prototype.removeChild;
    const _setAttribute = Element.prototype.setAttribute;
    const _getAttribute = Element.prototype.getAttribute;
    const _removeAttribute = Element.prototype.removeAttribute;
    const _hasAttribute = Element.prototype.hasAttribute;

    // Node methods
    const _normalize = Node.prototype.normalize;

    // Window/Document methods
    const _getComputedStyle = window.getComputedStyle;
    const _addEventListener = EventTarget.prototype.addEventListener;
    const _removeEventListener = EventTarget.prototype.removeEventListener;
    const _caretRangeFromPoint = document.caretRangeFromPoint ? document.caretRangeFromPoint.bind(document) : null;

    // Text node properties - capture descriptor to get native getter/setter
    const _textContentDescriptor = Object.getOwnPropertyDescriptor(Node.prototype, 'textContent');
    const _textContentGetter = _textContentDescriptor ? _textContentDescriptor.get : null;

    // ClassList methods
    const _classList_add = DOMTokenList.prototype.add;
    const _classList_remove = DOMTokenList.prototype.remove;
    const _classList_contains = DOMTokenList.prototype.contains;

    // RegExp methods
    const _RegExp_exec = RegExp.prototype.exec;

    // JSON methods
    const _JSON_stringify = JSON.stringify;

    // Freeze critical prototypes to prevent tampering after our capture
    Object.freeze(document.createRange);
    Object.freeze(document.createTreeWalker);
    Object.freeze(Range.prototype.setStart);
    Object.freeze(Range.prototype.setEnd);
    Object.freeze(Range.prototype.extractContents);
    Object.freeze(Range.prototype.insertNode);
    Object.freeze(TreeWalker.prototype.nextNode);
    Object.freeze(Element.prototype.matches);
    Object.freeze(Element.prototype.getBoundingClientRect);
    Object.freeze(Element.prototype.appendChild);
    Object.freeze(Element.prototype.insertBefore);
    Object.freeze(Element.prototype.removeChild);
    Object.freeze(Element.prototype.setAttribute);
    Object.freeze(Element.prototype.getAttribute);
    Object.freeze(Element.prototype.removeAttribute);
    Object.freeze(Element.prototype.hasAttribute);
    Object.freeze(Element.prototype.scrollIntoView);
    Object.freeze(Node.prototype.removeChild);
    Object.freeze(Node.prototype.normalize);
    Object.freeze(DOMTokenList.prototype.add);
    Object.freeze(DOMTokenList.prototype.remove);
    Object.freeze(DOMTokenList.prototype.contains);
    Object.freeze(RegExp.prototype.exec);
    Object.freeze(JSON.stringify);
    Object.freeze(window.getComputedStyle);

    // Message handler capture (done early to prevent tampering)
    const _messageHandler = window.webkit?.messageHandlers?.iTermCustomFind;
    const _postMessage = _messageHandler?.postMessage?.bind(_messageHandler);

    // ==============================
    //  Block-Based Find Engine
    // ==============================

    const TAG = '[iTermCustomFind-BlockBased]';
    const sessionSecret = "{{SECRET}}";
    const DEFAULT_INSTANCE_ID = 'default';

    // Security constants
    const MAX_SEARCH_TERM_LENGTH = 1000;
    const MAX_CONTEXT_LENGTH = 500;
    const MAX_REGEX_COMPLEXITY = 100;
    const MAX_INSTANCES = 10;
    const VALID_SEARCH_MODES = ['caseSensitive', 'caseInsensitive', 'caseSensitiveRegex', 'caseInsensitiveRegex'];
    const VALID_ACTIONS = ['startFind', 'findNext', 'findPrevious', 'clearFind', 'reveal', 'hideResults', 'showResults', 'updatePositions'];

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

    // ==============================
    //  Security Helper Functions
    // ==============================

    // Simple hash function for integrity verification
    function simpleHash(str) {
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            const char = str.charCodeAt(i);
            hash = ((hash << 5) - hash) + char;
            hash = hash & hash; // Convert to 32-bit integer
        }
        return hash.toString(36);
    }

    // Secure message posting with integrity verification
    function securePostMessage(payload) {
        if (!_postMessage) {
            console.warn(TAG, 'Message handler unavailable - postMessage failed');
            return false;
        }

        try {
            // Add integrity hash using sessionSecret
            payload.integrity = simpleHash(_JSON_stringify(payload.data) + sessionSecret);
            _postMessage(payload);
            return true;
        } catch (e) {
            console.error(TAG, 'Failed to post message:', e);
            return false;
        }
    }

    function validateSessionSecret(secret) {
        return secret === sessionSecret;
    }

    function sanitizeString(str, maxLength = MAX_SEARCH_TERM_LENGTH) {
        if (typeof str !== 'string') {
            return '';
        }
        // Remove null bytes and control characters
        str = str.replace(/\0/g, '').replace(/[\x00-\x1F\x7F-\x9F]/g, '');
        // Limit length
        return str.slice(0, maxLength);
    }

    function sanitizeInstanceId(id) {
        if (typeof id !== 'string') {
            return DEFAULT_INSTANCE_ID;
        }
        // Only allow alphanumeric characters, underscore, and hyphen
        const cleaned = id.replace(/[^A-Za-z0-9_-]/g, '');
        // Ensure it's not empty and within length limits
        const result = cleaned.slice(0, 50);
        return result.length > 0 ? result : DEFAULT_INSTANCE_ID;
    }

    function validateNumber(value, min, max, defaultValue) {
        const num = parseInt(value, 10);
        if (isNaN(num) || num < min || num > max) {
            return defaultValue;
        }
        return num;
    }

    function validateSearchMode(mode) {
        return VALID_SEARCH_MODES.includes(mode) ? mode : 'caseInsensitive';
    }

    function validateAction(action) {
        return VALID_ACTIONS.includes(action) ? action : null;
    }

    function escapeHtml(str) {
        const div = _createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    function validateRegexComplexity(pattern) {
        // Check for patterns that could cause catastrophic backtracking
        const dangerousPatterns = [
            /(\w+\+)+\w/,           // Nested quantifiers
            /(\w+\*)+\w/,
            /(\w+\?)+\w/,
            /(\w+\{[\d,]+\})+\w/,
            /([\w\s]+)+$/,          // Alternation with overlapping
            /(\w+\|)+\w/,
            /\(\?.*\)/              // Advanced regex features
        ];

        for (const dangerous of dangerousPatterns) {
            if (dangerous.test(pattern)) {
                return false;
            }
        }

        // Limit pattern length
        if (pattern.length > MAX_REGEX_COMPLEXITY) {
            return false;
        }

        return true;
    }

    function validateCommand(command) {
        if (!command || typeof command !== 'object') {
            return null;
        }

        // Validate session secret
        if (!validateSessionSecret(command.sessionSecret)) {
            console.error(TAG, 'Invalid session secret');
            return null;
        }

        // Create sanitized command
        const sanitized = {
            action: validateAction(command.action),
            instanceId: sanitizeInstanceId(command.instanceId),
            sessionSecret: sessionSecret // Use the valid secret
        };

        if (!sanitized.action) {
            console.error(TAG, 'Invalid action:', command.action);
            return null;
        }

        // Validate action-specific parameters
        switch (sanitized.action) {
            case 'startFind':
                sanitized.searchTerm = sanitizeString(command.searchTerm);
                sanitized.searchMode = validateSearchMode(command.searchMode);
                sanitized.contextLength = validateNumber(command.contextLength, 0, MAX_CONTEXT_LENGTH, 0);

                // Validate regex patterns
                if (sanitized.searchMode.includes('Regex')) {
                    if (!validateRegexComplexity(sanitized.searchTerm)) {
                        console.error(TAG, 'Regex pattern too complex or dangerous');
                        return null;
                    }
                }
                break;

            case 'reveal':
                if (command.identifier && typeof command.identifier === 'object') {
                    sanitized.identifier = {
                        bufferStart: validateNumber(command.identifier.bufferStart, 0, Number.MAX_SAFE_INTEGER, 0),
                        bufferEnd: validateNumber(command.identifier.bufferEnd, 0, Number.MAX_SAFE_INTEGER, 0),
                        text: sanitizeString(command.identifier.text, 100)
                    };
                }
                break;
        }

        return sanitized;
    }

    function injectStyles() {
        if (_getElementById('iterm-find-styles')) {
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

        const styleElement = _createElement('style');
        styleElement.id = 'iterm-find-styles';
        styleElement.textContent = highlightStyles;
        _appendChild.call(document.head, styleElement);
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

    // Represents a segment in the document - either text content or an iframe
    class Segment {
        constructor(type, index) {
            this.type = type;           // 'text' or 'iframe'
            this.index = index;         // Position in parent's segment array
        }
    }
    
    class TextSegment extends Segment {
        constructor(index, element) {
            super('text', index);
            this.element = element;           // The block DOM element
            this.textContent = '';           // Concatenated text from all text nodes
            this.textNodeMap = new TextNodeMap();
            this.bounds = null;              // DOMRect - will be computed when needed
        }

        collectTextNodes(engine) {
            this.textContent = '';
            this.textNodeMap = new TextNodeMap();

            let position = 0;
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

                        // Check if node is hidden and try to find revealer
                        if (engine && engine.isHidden(parent)) {
                            const rev = engine.firstRevealableAncestor(parent);
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
            while (node = _TreeWalker_nextNode.call(walker)) {
                position = this.textNodeMap.addTextNode(node, position);
                this.textContent += node.textContent;
            }
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
    
    class IframeSegment extends Segment {
        constructor(index, iframe, frameId) {
            super('iframe', index);
            this.iframe = iframe;        // The iframe DOM element
            this.frameId = frameId;      // ID from graph discovery
            this.bounds = null;
        }
        
        updateBounds() {
            this.bounds = _getBoundingClientRect.call(this.iframe);
        }
        
        containsPoint(x, y) {
            if (!this.bounds) this.updateBounds();
            return x >= this.bounds.left && x <= this.bounds.right &&
                   y >= this.bounds.top && y <= this.bounds.bottom;
        }
    }

    // Match structure with segment-based coordinates
    class Match {
        constructor(coordinates, text) {
            this.id = Math.random().toString(36).substr(2, 9); // Generate unique ID
            this.coordinates = coordinates;  // Array representing position [segment1, segment2, ..., localPos]
            this.text = text;                // The matched text
            this.type = null;                // 'local' or 'remote'
            this.highlightElements = [];     // For local matches
            this.revealers = new Set();      // For local matches
            
            // Debug: Log match creation
            console.log(`[Match] Created match ID: ${this.id} with coordinates: [${coordinates.join(',')}] text: "${text?.substring(0, 20)}..."`);
            
            // For remote matches
            this.frameId = null;
            this.remoteIndex = null;
            this.contextBefore = null;
            this.contextAfter = null;
        }
        
        // Compare two matches for ordering
        static compare(a, b) {
            // Lexicographic comparison of coordinate arrays
            const minLen = Math.min(a.coordinates.length, b.coordinates.length);
            for (let i = 0; i < minLen; i++) {
                if (a.coordinates[i] < b.coordinates[i]) return -1;
                if (a.coordinates[i] > b.coordinates[i]) return 1;
            }
            // If all compared elements are equal, shorter array comes first
            return a.coordinates.length - b.coordinates.length;
        }
    }
    
    // ------------------------------
    // Utility Functions
    // ------------------------------

    function safeStringify(obj) {
        try {
            return JSON.stringify(obj, (key, value) => {
                // Prevent circular references
                if (typeof value === 'object' && value !== null) {
                    if (value instanceof Node) {
                        return '[DOM Node]';
                    }
                    if (value instanceof Window) {
                        return '[Window]';
                    }
                }
                return value;
            });
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

    function isBlock(el) {
      return getComputedStyle(el).display === 'block';
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

            // Segment-based storage
            this.segments = [];              // Array of segments (text blocks or iframe refs)
            this.matches = [];               // Sorted array of matches with segment coordinates
            this.highlightedElements = [];
            this.hiddenSkippedCount = 0;
            
            // iframe support
            this.frameGraph = null;          // Cached iframe graph from discovery
            this.frameMatches = new Map();   // Map<frameId, array of matches in that frame>
            this.isMainFrame = (window === window.top);
            this.frameId = null;             // Will be set from graph discovery

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
            const frameInfo = this.frameId ? `frame:${this.frameId.substring(0, 8)}` : 'frame:unknown';
            const prefix = `${TAG} [${this.instanceId}|${frameInfo}]`;
            const message = `${prefix} ${args.map(a => (typeof a === 'object' ? safeStringify(a) : a)).join(' ')}`;
            console.debug(message);
            console.log(message); // Also log to regular console for visibility
        }

        // ---------- Visibility helpers ----------
        isHidden(el) {
            for (let e = el; e; e = e.parentElement) {
                if (e.hasAttribute('hidden')) { return true; }
                if (e.getAttribute('aria-hidden') === 'true') { return true; }
                const cs = _getComputedStyle(e);
                if (cs.display === 'none' || cs.visibility === 'hidden') { return true; }
            }
            return false;
        }

        firstRevealableAncestor(el) {
            for (let e = el; e; e = e.parentElement) {
                // Check static selectors first
                if (SAFE_REVEAL_SELECTORS.some(sel => { try { return _matches.call(e, sel); } catch (_) { return false; } })) {
                    return e;
                }

                // Check for CSS-hidden elements that can be revealed
                try {
                    const cs = _getComputedStyle(e);
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

                if (_hasAttribute.call(el, 'hidden')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'hidden', oldValue: '' });
                    _removeAttribute.call(el, 'hidden');
                }

                if (_getAttribute.call(el, 'aria-hidden') === 'true') {
                    this.revealRestores.push({ el, type: 'attr', attr: 'aria-hidden', oldValue: 'true' });
                    _setAttribute.call(el, 'aria-hidden', 'false');
                }

                const cs = _getComputedStyle(el);
                if (cs.display === 'none') {
                    this.revealRestores.push({ el, type: 'style-display', oldValue: el.style.display });
                    el.style.display = 'block';
                }
                if (cs.visibility === 'hidden') {
                    this.revealRestores.push({ el, type: 'style-visibility', oldValue: el.style.visibility });
                    el.style.visibility = 'visible';
                }

                if (_matches.call(el, '.mw-collapsible')) {
                    if (_classList_contains.call(el.classList, 'collapsed')) {
                        this.revealRestores.push({ el, type: 'class-remove-add', removed: 'collapsed' });
                        _classList_remove.call(el.classList, 'collapsed');
                    }
                }
                if (_matches.call(el, '[aria-expanded="false"]')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'aria-expanded', oldValue: _getAttribute.call(el, 'aria-expanded') });
                    _setAttribute.call(el, 'aria-expanded', 'true');
                }
                if (_matches.call(el, '[data-collapsed="true"]')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'data-collapsed', oldValue: _getAttribute.call(el, 'data-collapsed') });
                    _setAttribute.call(el, 'data-collapsed', 'false');
                }
            } catch (e) {
                this.log('forceVisible error:', e);
            }
        }

        // ---------- Segment Collection ----------

        async collectSegments(root) {
            this.log('collectSegments: ENTER - starting segment collection, isMainFrame:', this.isMainFrame);
            this.segments = [];
            
            try {
                // First, discover iframe graph if we're in main frame
                if (this.isMainFrame && window.iTermGraphDiscovery) {
                    this.log('collectSegments: main frame - discovering iframe graph');
                    await this.discoverFrameGraph();
                    this.log('collectSegments: iframe discovery complete, frameId now:', this.frameId?.substring(0, 8));
                } else {
                    this.log('collectSegments: child frame or no graph discovery available');
                }

                // Build segments for this frame
                this.log('collectSegments: building segments for root:', root?.tagName);
                this.buildSegments(root);
                
                const textSegments = this.segments.filter(s => s.type === 'text').length;
                const iframeSegments = this.segments.filter(s => s.type === 'iframe').length;
                this.log(`collectSegments: EXIT - found ${this.segments.length} total segments (${textSegments} text, ${iframeSegments} iframe)`);
            } catch (e) {
                this.log('collectSegments: ERROR during segment collection:', e);
                // Continue with empty segments to avoid completely breaking search
                this.segments = [];
                throw e;
            }
        }
        
        async discoverFrameGraph() {
            this.log('discoverFrameGraph: ENTER - calling graph discovery');
            return new Promise((resolve, reject) => {
                let resolved = false;
                
                // Set a timeout to catch hanging promises
                const timeout = setTimeout(() => {
                    if (!resolved) {
                        this.log('discoverFrameGraph: TIMEOUT - discovery callback not called within 3 seconds');
                        resolved = true;
                        reject(new Error('Graph discovery timeout'));
                    }
                }, 3000);
                
                try {
                    this.log('discoverFrameGraph: about to call window.iTermGraphDiscovery.discover');
                    window.iTermGraphDiscovery.discover((graph) => {
                        if (resolved) {
                            this.log('discoverFrameGraph: WARNING - callback called after timeout');
                            return;
                        }
                        resolved = true;
                        clearTimeout(timeout);
                        
                        this.log('discoverFrameGraph: callback called with graph:', {
                            frameId: graph?.frameId?.substring(0, 8),
                            hasChildren: !!(graph?.children),
                            childCount: graph?.children?.length || 0
                        });
                        
                        this.frameGraph = graph;
                        this.frameId = graph.frameId;  // Set our frame ID from discovery
                        const childCount = graph.children ? graph.children.length : 0;
                        this.log('discoverFrameGraph: EXIT - graph discovered, frameId:', this.frameId?.substring(0, 8), 'children:', childCount);
                        if (childCount > 0) {
                            this.log('discoverFrameGraph: child frame IDs:', graph.children.map(c => c.frameId?.substring(0, 8)));
                        }
                        resolve();
                    });
                    this.log('discoverFrameGraph: window.iTermGraphDiscovery.discover called successfully');
                } catch (e) {
                    if (!resolved) {
                        resolved = true;
                        clearTimeout(timeout);
                        this.log('discoverFrameGraph: ERROR calling graph discovery:', e);
                        reject(e);
                    }
                }
            });
        }
        
        buildSegments(root) {
            this.log('buildSegments: ENTER - analyzing root element:', root?.tagName);
            let segmentIndex = 0;
            const blocks = [];
            const iframePositions = new Map(); // Map iframe element to its position in document flow
            
            // First pass: find all blocks and note iframe positions
            this.log('buildSegments: first pass - finding blocks and iframes');
            const findBlocksAndIframes = (el, currentBlock) => {
                if (el.tagName === 'IFRAME') {
                    // Record iframe position
                    iframePositions.set(el, { afterBlock: currentBlock, beforeNextBlock: true });
                    return currentBlock;
                }
                
                if (isBlock(el)) {
                    // Check for child blocks or iframes
                    const hasChildBlockOrIframe = Array.from(el.children).some(child => 
                        isBlock(child) || child.tagName === 'IFRAME'
                    );
                    
                    if (!hasChildBlockOrIframe) {
                        // This is a leaf block
                        blocks.push(el);
                        return el;
                    }
                }
                
                // Recurse into children
                let lastBlock = currentBlock;
                for (const child of el.children) {
                    lastBlock = findBlocksAndIframes(child, lastBlock);
                }
                return lastBlock;
            };
            
            findBlocksAndIframes(root, null);
            
            this.log('buildSegments: first pass complete - found', blocks.length, 'blocks and', iframePositions.size, 'iframes');
            
            // Second pass: build segments interleaving text blocks and iframes
            this.log('buildSegments: second pass - building segments');
            const processedIframes = new Set();
            
            for (let i = 0; i < blocks.length; i++) {
                const block = blocks[i];
                
                // Add any iframes that come before this block
                for (const [iframe, position] of iframePositions) {
                    if (!processedIframes.has(iframe) && 
                        position.afterBlock === (i > 0 ? blocks[i-1] : null)) {
                        const iframeSegment = new IframeSegment(segmentIndex++, iframe, null);
                        this.segments.push(iframeSegment);
                        processedIframes.add(iframe);
                    }
                }
                
                // Add the text block segment
                const textSegment = new TextSegment(segmentIndex++, block);
                textSegment.collectTextNodes(this);
                if (textSegment.textContent.length > 0) {
                    this.log('buildSegments: added text segment', textSegment.index, 'with', textSegment.textContent.length, 'chars');
                    this.segments.push(textSegment);
                } else {
                    this.log('buildSegments: skipping empty text segment for block', block.tagName);
                }
            }
            
            // Add any remaining iframes at the end
            for (const [iframe, position] of iframePositions) {
                if (!processedIframes.has(iframe)) {
                    const iframeSegment = new IframeSegment(segmentIndex++, iframe, null);
                    this.segments.push(iframeSegment);
                    processedIframes.add(iframe);
                }
            }
            
            // Match iframe segments with frame graph
            if (this.frameGraph) {
                this.matchIframesToGraph();
            }
        }
        
        matchIframesToGraph() {
            // Match iframe elements to their frameIds from the graph
            const iframeSegments = this.segments.filter(s => s.type === 'iframe');
            
            // The graph.children array should correspond to iframes in document order
            if (this.frameGraph.children) {
                for (let i = 0; i < iframeSegments.length && i < this.frameGraph.children.length; i++) {
                    iframeSegments[i].frameId = this.frameGraph.children[i].frameId;
                }
            }
        }

        // ---------- Click Detection ----------

        async handleClick(event) {
            this.log('handleClick: detected at', event.clientX, event.clientY);

            const clickLocation = await this.getClickLocation(event.clientX, event.clientY);
            if (clickLocation) {
                this.lastClickLocation = clickLocation;
                this.useClickLocationForNext = true;
                this.log('handleClick: recorded location', clickLocation);
            }
        }

        async getClickLocation(x, y) {
            this.log('getClickLocation: called with coordinates', x, y);

            // Validate coordinates
            x = validateNumber(x, 0, window.innerWidth, 0);
            y = validateNumber(y, 0, window.innerHeight, 0);

            // Find which segment contains the click
            for (let i = 0; i < this.segments.length; i++) {
                const segment = this.segments[i];
                if (segment.containsPoint && segment.containsPoint(x, y)) {
                    this.log('getClickLocation: click is in segment', i, 'type:', segment.type);

                    if (segment.type === 'iframe') {
                        return await this.handleIframeClick(segment, x, y);
                    } else if (segment.type === 'text') {
                        return this.handleTextSegmentClick(segment, i, x, y);
                    }
                }
            }

            this.log('getClickLocation: click not in any segment');
            return null;
        }
        
        async handleIframeClick(iframeSegment, x, y) {
            this.log('handleIframeClick: starting iframe click handling', {
                frameId: iframeSegment.frameId,
                segmentIndex: iframeSegment.index,
                mainFrameCoords: { x, y }
            });
            
            // Convert main frame coordinates to iframe coordinates
            const iframeRect = _getBoundingClientRect.call(iframeSegment.iframe);
            const iframeX = x - iframeRect.left;
            const iframeY = y - iframeRect.top;
            
            this.log('handleIframeClick: converted coordinates to iframe space:', {
                iframeX,
                iframeY,
                iframeRect: { left: iframeRect.left, top: iframeRect.top, width: iframeRect.width, height: iframeRect.height }
            });
            
            // Delegate click handling to the iframe
            const script = `
                (function() {
                    if (window.iTermCustomFind && window.iTermCustomFind.handleClickInFrame) {
                        return window.iTermCustomFind.handleClickInFrame(${iframeX}, ${iframeY});
                    }
                    return null;
                })()
            `;
            
            this.log('handleIframeClick: evaluating click script in frame:', iframeSegment.frameId);
            
            const iframeClickResult = await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInFrame(iframeSegment.frameId, script, (result) => {
                    this.log('handleIframeClick: iframe click script completed with result:', result);
                    resolve(result);
                });
            });
            
            // If iframe returned a position, prepend our segment index to create full coordinates
            if (iframeClickResult && iframeClickResult.coordinates) {
                const fullCoordinates = [iframeSegment.index, ...iframeClickResult.coordinates];
                this.log('handleIframeClick: returning remote click result with full coordinates:', fullCoordinates);
                return {
                    coordinates: fullCoordinates,
                    type: 'remote'
                };
            }
            
            // Fallback: position at start of iframe
            return {
                coordinates: [iframeSegment.index, 0],
                type: 'iframe_boundary'
            };
        }
        
        handleTextSegmentClick(segment, segmentIndex, x, y) {
            this.log('handleTextSegmentClick: processing click in text segment', segmentIndex);

            // Get caret position within segment
            const range = _caretRangeFromPoint ? _caretRangeFromPoint(x, y) : null;
            if (range && range.startContainer.nodeType === Node.TEXT_NODE) {
                const textNode = range.startContainer;
                const offset = range.startOffset;

                this.log('handleTextSegmentClick: caret found in text node, offset', offset);

                // Find the position of this text node within the segment
                const nodeInfo = segment.textNodeMap.nodeToPosition.get(textNode);
                if (nodeInfo) {
                    const position = nodeInfo.start + offset;
                    this.log('handleTextSegmentClick: calculated position', position, 'in segment');
                    
                    return {
                        coordinates: [segmentIndex, position],
                        type: 'local'
                    };
                }
            }

            // Fallback: return start of segment
            this.log('handleTextSegmentClick: using fallback position');
            return {
                coordinates: [segmentIndex, 0],
                type: 'local'
            };
        }
        
        // Internal method for handling clicks that works in both main frame and iframes
        handleTextSegmentClickInternal(x, y) {
            this.log('handleTextSegmentClickInternal: processing click at', x, y);
            
            // Find which segment contains the click
            for (let i = 0; i < this.segments.length; i++) {
                const segment = this.segments[i];
                if (segment.type === 'text' && segment.containsPoint && segment.containsPoint(x, y)) {
                    return this.handleTextSegmentClick(segment, i, x, y);
                }
            }
            
            // Fallback: return position at start of first segment
            this.log('handleTextSegmentClickInternal: using fallback position');
            return {
                coordinates: [0, 0],
                type: 'local'
            };
        }

        clearClickLocation() {
            this.lastClickLocation = null;
            this.useClickLocationForNext = false;
        }

        getStartingMatchIndex() {
            this.log('getStartingMatchIndex: called');
            this.log('getStartingMatchIndex: lastClickLocation:', this.lastClickLocation);
            this.log('getStartingMatchIndex: matches.length:', this.matches.length);

            if (!this.lastClickLocation || this.matches.length === 0) {
                this.log('getStartingMatchIndex: no click location or no matches, returning 0');
                return 0;
            }

            const clickCoordinates = this.lastClickLocation.coordinates;
            this.log('getStartingMatchIndex: click was at coordinates', clickCoordinates);

            // Create a dummy match object with click coordinates for comparison
            const clickMatch = new Match(clickCoordinates, '');

            // Find first match after click position using lexicographic comparison
            for (let i = 0; i < this.matches.length; i++) {
                const match = this.matches[i];
                this.log(`getStartingMatchIndex: checking match ${i} at coordinates`, match.coordinates);

                // Use existing Match.compare method
                if (Match.compare(match, clickMatch) >= 0) {
                    this.log('getStartingMatchIndex: found first match at or after click at index', i);
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
        
        async findMatchesWithIframes(regex, searchTerm) {
            this.log('findMatchesWithIframes: ENTER - searching for:', searchTerm, 'mode:', this.searchMode);
            this.matches = [];
            this.frameMatches.clear();
            
            if (!this.isMainFrame) {
                // If we're not the main frame, just do local search
                this.log('findMatchesWithIframes: child frame - doing local search only');
                this.matches = this.findLocalMatches(regex);
                this.log('findMatchesWithIframes: EXIT - child frame found', this.matches.length, 'local matches');
                return;
            }
            
            // Main frame: coordinate search across all frames using evaluateInAll
            this.log('findMatchesWithIframes: main frame - coordinating cross-frame search');
            const searchScript = `
                (function() {
                    // Each frame searches its own content
                    if (window.iTermCustomFind && window.iTermCustomFind.searchInFrame) {
                        return window.iTermCustomFind.searchInFrame({
                            searchTerm: ${JSON.stringify(searchTerm)},
                            searchMode: ${JSON.stringify(this.searchMode)},
                            contextLength: ${this.contextLen},
                            instanceId: ${JSON.stringify(this.instanceId)}
                        });
                    }
                    return { matches: [] };
                })()
            `;
            
            this.log('findMatchesWithIframes: executing search script in all frames');
            const allFrameResults = await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInAll(searchScript, (results) => {
                    resolve(results);
                });
            });
            
            this.log('findMatchesWithIframes: received results from', Object.keys(allFrameResults).length, 'frames');
            
            // Process results from all frames
            let localMatchCount = 0;
            let remoteMatchCount = 0;
            
            for (const [frameId, result] of Object.entries(allFrameResults)) {
                const frameIdShort = frameId?.substring(0, 8) || 'unknown';
                this.log('findMatchesWithIframes: processing frame', frameIdShort, 'with', result?.matches?.length || 0, 'matches');
                
                if (!result || !result.matches) {
                    this.log('findMatchesWithIframes: skipping frame', frameIdShort, '- no results');
                    continue;
                }
                
                if (frameId === this.frameId) {
                    // Skip our own frame's matches - we already have them from direct search
                    this.log('findMatchesWithIframes: skipping main frame results (already have them from direct search)');
                    continue;
                } else {
                    // Remote frame's matches - need to prepend iframe segment index
                    const iframeSegment = this.segments.find(s => 
                        s.type === 'iframe' && s.frameId === frameId
                    );
                    
                    if (!iframeSegment) {
                        this.log('findMatchesWithIframes: WARNING - no iframe segment found for frame', frameIdShort);
                        continue;
                    }
                    
                    this.log('findMatchesWithIframes: processing remote matches from frame', frameIdShort, 'in segment', iframeSegment.index);
                    result.matches.forEach((frameMatch, idx) => {
                        const remoteMatch = new Match(
                            [iframeSegment.index, ...frameMatch.coordinates],
                            frameMatch.text
                        );
                        
                        remoteMatch.type = 'remote';
                        remoteMatch.frameId = frameId;
                        remoteMatch.remoteIndex = idx;
                        this.log('findMatchesWithIframes: assigned type "remote" to match ID:', remoteMatch.id, 'frameId:', frameId.substring(0, 8));
                        remoteMatch.contextBefore = frameMatch.contextBefore;
                        remoteMatch.contextAfter = frameMatch.contextAfter;
                        
                        this.matches.push(remoteMatch);
                        remoteMatchCount++;
                        this.log('findMatchesWithIframes: added remote match', idx, 'at coords', remoteMatch.coordinates, 'text:', frameMatch.text.substring(0, 20) + '... (total matches now:', this.matches.length + ')');
                    });
                    
                    this.frameMatches.set(frameId, result.matches.length);
                }
            }
            
            // Sort all matches by coordinates
            this.log('findMatchesWithIframes: sorting', this.matches.length, 'matches by coordinates');
            this.matches.sort(Match.compare);
            
            this.log(`findMatchesWithIframes: EXIT - found ${this.matches.length} total matches (${localMatchCount} local, ${remoteMatchCount} remote)`);
        }
        
        findLocalMatches(regex) {
            const matches = [];
            
            for (let segmentIdx = 0; segmentIdx < this.segments.length; segmentIdx++) {
                const segment = this.segments[segmentIdx];
                
                if (segment.type !== 'text') continue;
                
                regex.lastIndex = 0;
                let match;
                
                while ((match = _RegExp_exec.call(regex, segment.textContent)) !== null) {
                    const localMatch = new Match(
                        [segmentIdx, match.index],  // Coordinates: [segment, position]
                        match[0]  // Matched text
                    );
                    
                    localMatch.type = 'local';
                    localMatch.segment = segment;
                    localMatch.localStart = match.index;
                    this.log('findLocalMatches: assigned type "local" to match ID:', localMatch.id, 'frame:', this.frameId?.substring(0, 8) || 'unknown');
                    localMatch.localEnd = match.index + match[0].length;
                    
                    matches.push(localMatch);
                    
                    if (match[0].length === 0) {
                        regex.lastIndex++;
                    }
                }
            }
            
            return matches;
        }

        findMatchesInBlock(regex, block, blockIndex) {
            const matches = [];
            regex.lastIndex = 0;

            let match;
            while ((match = _RegExp_exec.call(regex, block.textContent)) !== null) {
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
        
        // Find text node and offset by walking the DOM directly using coordinates
        findTextNodeByCoordinates(segment, targetOffset, matchLength) {
            let currentOffset = 0;
            let startNode = null;
            let startOffset = 0;
            let endNode = null;
            let endOffset = 0;
            
            const walker = _createTreeWalker(
                segment.element,
                _SHOW_TEXT,
                {
                    acceptNode: (node) => {
                        const parent = node.parentElement;
                        if (!parent) return _FILTER_REJECT;
                        
                        // Skip nodes inside elements that would be invisible/irrelevant
                        if (_matches.call(parent, 'script, style, noscript')) {
                            return _FILTER_REJECT;
                        }
                        
                        return _FILTER_ACCEPT;
                    }
                },
                false
            );
            
            let node;
            while (node = _TreeWalker_nextNode.call(walker)) {
                const textContent = _textContentGetter ? _textContentGetter.call(node) : node.textContent;
                const nodeLength = textContent.length;
                
                if (currentOffset + nodeLength > targetOffset) {
                    // Start position is in this node
                    if (startNode === null) {
                        startNode = node;
                        startOffset = targetOffset - currentOffset;
                    }
                    
                    // Check if end position is also in this node
                    const targetEndOffset = targetOffset + matchLength;
                    if (currentOffset + nodeLength >= targetEndOffset) {
                        endNode = node;
                        endOffset = targetEndOffset - currentOffset;
                        break;
                    }
                }
                
                currentOffset += nodeLength;
                
                // If we found start but not end, and we've moved past the target range
                if (startNode && currentOffset >= targetOffset + matchLength) {
                    endNode = node;
                    endOffset = (targetOffset + matchLength) - (currentOffset - nodeLength);
                    break;
                }
            }
            
            if (!startNode || !endNode) {
                return null;
            }
            
            return {
                startNode,
                startOffset,
                endNode, 
                endOffset
            };
        }
        
        async clearHighlightsInAllFrames() {
            this.log('clearHighlightsInAllFrames: clearing highlights in all frames');
            
            const clearScript = `
                (function() {
                    if (window.iTermCustomFind && window.iTermCustomFind.clearStateWithoutResponse) {
                        return window.iTermCustomFind.clearStateWithoutResponse({
                            sessionSecret: ${JSON.stringify(sessionSecret)},
                            instanceId: ${JSON.stringify(this.instanceId)}
                        });
                    }
                    return { error: 'API not available' };
                })()
            `;
            
            await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInAll(clearScript, (results) => {
                    const clearedFrames = Object.keys(results).filter(frameId => !results[frameId]?.error);
                    this.log('clearHighlightsInAllFrames: cleared highlights in', clearedFrames.length, 'frames');
                    resolve();
                });
            });
        }

        // ---------- Highlighting ----------

        async highlight() {
            this.log('highlight: starting with', this.matches.length, 'matches');

            // Group local matches by segment to optimize TextNodeMap rebuilding
            const localMatchesBySegment = new Map();
            const remoteMatches = [];
            
            for (const match of this.matches) {
                this.log('highlight: processing match ID:', match.id, 'type:', match.type, 'coordinates:', match.coordinates);
                if (match.type === 'local') {
                    const segmentIndex = match.coordinates[0];
                    if (!localMatchesBySegment.has(segmentIndex)) {
                        localMatchesBySegment.set(segmentIndex, []);
                    }
                    localMatchesBySegment.get(segmentIndex).push(match);
                    this.log('highlight: added local match ID:', match.id, 'to segment', segmentIndex);
                } else if (match.type === 'remote') {
                    remoteMatches.push(match);
                    this.log('highlight: added remote match ID:', match.id, 'to remote matches');
                } else {
                    this.log('highlight: WARNING - match ID:', match.id, 'has unknown type:', match.type);
                }
            }
            
            // Highlight local matches segment by segment in reverse order
            let highlightedCount = 0;
            for (const [segmentIndex, matches] of localMatchesBySegment.entries()) {
                this.log('highlight: processing segment', segmentIndex, 'with', matches.length, 'matches');
                
                // Sort matches within segment in reverse order (end to beginning)
                matches.sort((a, b) => b.localStart - a.localStart);
                
                for (const match of matches) {
                    try {
                        this.log('highlight: attempting to highlight local match ID:', match.id, 'in segment', segmentIndex);
                        this.highlightLocalMatch(match);
                        highlightedCount++;
                        this.log('highlight: successfully highlighted match ID:', match.id);
                    } catch (e) {
                        this.log('highlight: ERROR highlighting match ID:', match.id, ':', e);
                    }
                }
                
                // Rebuild TextNodeMap for this segment after all highlighting is done
                try {
                    const segment = this.segments[segmentIndex];
                    if (segment && segment.type === 'text') {
                        this.log('highlight: rebuilding TextNodeMap for segment', segmentIndex);
                        // Log highlightElements counts before rebuilding
                        const segmentMatches = localMatchesBySegment.get(segmentIndex) || [];
                        segmentMatches.forEach((m, i) => {
                            this.log('highlight: before rebuild - match ID:', m.id, 'at segment index', i, 'has', m.highlightElements ? m.highlightElements.length : 'null', 'highlightElements');
                        });
                        
                        segment.collectTextNodes(this);
                        
                        // Log highlightElements counts after rebuilding  
                        segmentMatches.forEach((m, i) => {
                            this.log('highlight: after rebuild - match ID:', m.id, 'at segment index', i, 'has', m.highlightElements ? m.highlightElements.length : 'null', 'highlightElements');
                        });
                        this.log('highlight: rebuilt TextNodeMap with', segment.textNodeMap.length, 'total characters');
                    }
                } catch (e) {
                    this.log('highlight: error rebuilding TextNodeMap for segment', segmentIndex, ':', e);
                }
            }
            
            // Handle remote matches
            for (const match of remoteMatches) {
                try {
                    // Remote matches are highlighted in their own frames
                    // We just ensure the iframe highlights are updated
                    await this.ensureRemoteHighlighting(match);
                    highlightedCount++;
                } catch (e) {
                    this.log('highlight: error highlighting remote match', match, ':', e);
                }
            }

            this.log('highlight: completed,', highlightedCount, 'of', this.matches.length, 'matches highlighted');
        }
        
        async ensureRemoteHighlighting(match) {
            this.log('highlight: request highlight match in frame', match.frameId);
            // Tell the iframe to highlight its matches
            const script = `
                (function() {
                    if (window.iTermCustomFind && window.iTermCustomFind.highlightMatches) {
                        window.iTermCustomFind.highlightMatches(${JSON.stringify(this.instanceId)});
                    }
                })()
            `;
            
            await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInFrame(match.frameId, script, resolve);
            });
        }

        highlightLocalMatch(match) {
            const segmentIndex = match.coordinates[0];
            const segmentOffset = match.coordinates[1];
            
            const segment = this.segments[segmentIndex];
            if (!segment || segment.type !== 'text') {
                this.log('highlightLocalMatch: invalid segment for match');
                return;
            }

            const elements = [];
            const revealers = new Set();

            this.log('highlightLocalMatch: attempting to highlight match at coordinates', match.coordinates, 'text:', match.text.substring(0, 10) + '...');

            // Use coordinates to find text nodes directly, bypassing potentially stale TextNodeMap
            const result = this.findTextNodeByCoordinates(segment, segmentOffset, match.text.length);
            
            if (!result) {
                this.log('highlightLocalMatch: could not locate text nodes using coordinates');
                return;
            }
            
            const { startNode, startOffset, endNode, endOffset } = result;
            
            // Validate the DOM nodes
            if (!startNode || !endNode) {
                this.log('highlightLocalMatch: invalid DOM nodes from coordinate lookup');
                return;
            }

            // Check if nodes are still connected to the document  
            if (!startNode.isConnected || !endNode.isConnected) {
                this.log('highlightLocalMatch: DOM nodes disconnected - startConnected:', startNode.isConnected, 'endConnected:', endNode.isConnected);
                return;
            }

            try {
                this.log('highlightLocalMatch: creating range for coordinates', match.coordinates, 'startNode:', startNode.nodeName, 'startOffset:', startOffset, 'endNode:', endNode.nodeName, 'endOffset:', endOffset);
                const range = _createRange();
                
                _Range_setStart.call(range, startNode, startOffset);
                _Range_setEnd.call(range, endNode, endOffset);

                // Create the highlight span
                const span = _createElement('span');
                span.className = 'iterm-find-highlight';
                _setAttribute.call(span, 'data-iterm-id', this.instanceId);

                this.log('highlightLocalMatch: surrounding range contents with highlight span');
                _Range_surroundContents.call(range, span);

                elements.push(span);
                this.highlightedElements.push(span);

                this.log('highlightLocalMatch: successfully highlighted match');
            } catch (e) {
                this.log('highlightLocalMatch: error highlighting match:', e.message);
                // Fallback: try character-by-character highlighting
                this.log('highlightLocalMatch: attempting fallback character-by-character highlighting');
                
                for (let i = 0; i < match.text.length; i++) {
                    const charResult = this.findTextNodeByCoordinates(segment, segmentOffset + i, 1);
                    if (charResult) {
                        try {
                            const range = _createRange();
                            _Range_setStart.call(range, charResult.startNode, charResult.startOffset);
                            _Range_setEnd.call(range, charResult.endNode, charResult.endOffset);

                            const span = _createElement('span');
                            span.className = 'iterm-find-highlight';
                            _setAttribute.call(span, 'data-iterm-id', this.instanceId);

                            _Range_surroundContents.call(range, span);
                            elements.push(span);
                            this.highlightedElements.push(span);
                        } catch (e2) {
                            this.log('highlightLocalMatch: fallback failed for character', i, ':', e2.message);
                            continue;
                        }
                    }
                }
            }

            // Store elements in the match
            match.highlightElements = elements;
            match.revealers = revealers;
            
            this.log('highlightLocalMatch: created match with', elements.length, 'highlightElements for match', match.id, 'at array index', this.matches.indexOf(match));

            // TODO: Collect revealers if needed for reveal functionality
        }

        findPositionInBlock(block, position) {
            // Walk the block's DOM tree and count characters until we reach the position
            const walker = _createTreeWalker(
                block.element,
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

                        // Skip completely empty text nodes, but keep whitespace-containing nodes
                        if (!node.textContent || node.textContent.length === 0) {
                            return _FILTER_REJECT;
                        }

                        return _FILTER_ACCEPT;
                    }
                }
            );

            let currentPos = 0;
            let node;

            while (node = _TreeWalker_nextNode.call(walker)) {
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

            const spans = _querySelectorAll(
                `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
                `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
            );

            const parents = new Set();
            spans.forEach(span => {
                const parent = span.parentNode;
                if (!parent) return;

                while (span.firstChild) {
                    _insertBefore.call(parent, span.firstChild, span);
                }
                _removeChild.call(parent, span);
                parents.add(parent);
            });

            // Normalize text nodes
            parents.forEach(p => _normalize.call(p));

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
                        _removeAttribute.call(el, rec.attr);
                    } else {
                        _setAttribute.call(el, rec.attr, rec.oldValue);
                    }
                } else if (rec.type === 'class-remove-add') {
                    if (rec.removed) { _classList_add.call(el.classList, rec.removed); }
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

        async setCurrent(idx, _triedMatches = new Set()) {
            this.log('setCurrent: ENTER - setting current to index', idx, 'total matches:', this.matches.length, 'tried:', _triedMatches.size);
            
            if (this.matches.length === 0) {
                this.log('setCurrent: EXIT - no matches available');
                return;
            }

            // Normalize index
            const normalizedIdx = ((idx % this.matches.length) + this.matches.length) % this.matches.length;
            
            // Check if we've tried all matches without success
            if (_triedMatches.has(normalizedIdx)) {
                this.log('setCurrent: ERROR - already tried match at index', normalizedIdx, '- all matches may be broken');
                if (_triedMatches.size >= this.matches.length) {
                    this.log('setCurrent: ERROR - tried all matches without success, giving up');
                    return;
                }
            }

            // Clear previous current highlight
            if (this.currentMatchIndex >= 0 && this.currentMatchIndex < this.matches.length) {
                const prevMatch = this.matches[this.currentMatchIndex];
                this.log('setCurrent: clearing previous highlight for match', this.currentMatchIndex, 'type:', prevMatch.type);
                
                if (prevMatch.type === 'local') {
                    prevMatch.highlightElements?.forEach(e => {
                        e.className = 'iterm-find-highlight';
                        _setAttribute.call(e, 'data-iterm-id', this.instanceId);
                    });
                } else if (prevMatch.type === 'remote') {
                    // Clear highlight in remote frame
                    await this.clearCurrentInFrame(prevMatch.frameId);
                }
            }

            // Set new current
            this.currentMatchIndex = normalizedIdx;
            const current = this.matches[this.currentMatchIndex];
            this.log('setCurrent: setting new current to index', this.currentMatchIndex, 'ID:', current.id, 'type:', current.type, 'coords:', current.coordinates);

            // Track that we're trying this match
            const newTriedMatches = new Set(_triedMatches);
            newTriedMatches.add(normalizedIdx);

            let highlightingSucceeded = false;

            if (current.type === 'local') {
                this.log('setCurrent: handling local match - ensuring visibility and highlighting');
                this.ensureVisibleForMatch(current);
                
                // Check if this match has highlight elements (was successfully highlighted)
                if (current.highlightElements && current.highlightElements.length > 0) {
                    current.highlightElements.forEach(e => {
                        e.className = 'iterm-find-highlight-current';
                        _setAttribute.call(e, 'data-iterm-id', this.instanceId);
                    });

                    // Scroll into view
                    this.log('setCurrent: scrolling local match into view');
                    _scrollIntoView.call(current.highlightElements[0], {
                        behavior: '{{SCROLL_BEHAVIOR}}',
                        block: 'center',
                        inline: 'center'
                    });
                    
                    highlightingSucceeded = true;
                } else {
                    this.log('setCurrent: WARNING - local match has no highlight elements, may have failed during initial highlighting');
                }
            } else if (current.type === 'remote') {
                // Navigate to remote match
                this.log('setCurrent: handling remote match - delegating to iframe');
                try {
                    await this.navigateToRemoteMatch(current);
                    highlightingSucceeded = true; // Assume success unless an error is thrown
                } catch (e) {
                    this.log('setCurrent: ERROR - remote match navigation failed:', e.message);
                    highlightingSucceeded = false;
                }
            }

            // If highlighting failed, try the next match
            if (!highlightingSucceeded) {
                this.log('setCurrent: highlighting failed for match', this.currentMatchIndex, 'ID:', current.id, '- trying next match');
                const nextIdx = normalizedIdx + 1;
                return await this.setCurrent(nextIdx, newTriedMatches);
            }

            this.log('setCurrent: EXIT - highlighting succeeded, reporting results');
            this.reportResults(false);
        }
        
        async navigateToRemoteMatch(match) {
            this.log('navigateToRemoteMatch: starting navigation to remote match', {
                frameId: match.frameId,
                remoteIndex: match.remoteIndex,
                coordinates: match.coordinates
            });
            
            // First, scroll the iframe into view
            const iframeSegment = this.segments.find(s => 
                s.type === 'iframe' && s.frameId === match.frameId
            );
            
            if (iframeSegment && iframeSegment.iframe) {
                this.log('navigateToRemoteMatch: scrolling iframe into view, segment index:', iframeSegment.index);
                _scrollIntoView.call(iframeSegment.iframe, { behavior: 'smooth', block: 'center' });
            } else {
                this.log('navigateToRemoteMatch: WARNING - iframe segment not found for frameId:', match.frameId);
            }
            
            // Then highlight the match within the iframe
            const script = `
                (function() {
                    if (window.iTermCustomFind && window.iTermCustomFind.highlightRemoteMatch) {
                        return window.iTermCustomFind.highlightRemoteMatch(${match.remoteIndex}, ${JSON.stringify(this.instanceId)});
                    }
                })()
            `;
            
            this.log('navigateToRemoteMatch: evaluating highlight script in frame:', match.frameId);
            
            await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInFrame(match.frameId, script, (result) => {
                    this.log('navigateToRemoteMatch: highlight script completed with result:', result);
                    resolve(result);
                });
            });
            
            this.log('navigateToRemoteMatch: completed navigation to remote match');
        }
        
        async clearCurrentInFrame(frameId) {
            this.log('clearCurrentInFrame: clearing current highlight in frame:', frameId);
            
            const script = `
                (function() {
                    if (window.iTermCustomFind && window.iTermCustomFind.clearCurrentHighlight) {
                        window.iTermCustomFind.clearCurrentHighlight(${JSON.stringify(this.instanceId)});
                    }
                })()
            `;
            
            await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInFrame(frameId, script, (result) => {
                    this.log('clearCurrentInFrame: clear script completed for frame:', frameId, 'result:', result);
                    resolve(result);
                });
            });
        }

        // ---------- Commands ----------

        async startFind(term, mode, contextLen) {
            this.log('=== START FIND ===');
            this.log('startFind: term=' + term + ', mode=' + mode + ', contextLen=' + contextLen + ', frame=' + (this.frameId?.substring(0, 8) || 'unknown'));

            // Clear highlights in all frames (main + iframes) before starting new search
            if (this.isMainFrame) {
                await this.clearHighlightsInAllFrames();
            } else {
                this.clearHighlights();
            }
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

            this.log('startFind: Collecting segments from document.body', document.body);
            await this.collectSegments(document.body);

            this.log('startFind: Finding matches in', this.segments.length, 'segments');
            await this.findMatchesWithIframes(regex, term);

            this.log('startFind: Found', this.matches.length, 'total matches');

            try {
                await this.highlight();
                this.log('startFind: Highlighting completed');
            } catch (e) {
                this.log('startFind: ERROR in highlighting, but continuing:', e);
            }

            // Set current match before reporting results to ensure consistent state
            if (this.matches.length > 0) {
                const startIndex = this.getStartingMatchIndex();
                this.log('startFind: Setting current match to index', startIndex);

                // Set current match and ensure it's visible
                await this.setCurrent(startIndex);

                // Ensure the match is visible (auto-reveal)
                this.ensureVisibleForMatch(current);

                current.els.forEach(e => {
                    e.className = 'iterm-find-highlight-current';
                    _setAttribute.call(e, 'data-iterm-id', this.instanceId);
                });

                // Scroll into view
                if (current.els.length > 0) {
                    _scrollIntoView.call(current.els[0], {
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

        async findNext() {
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
                await this.setCurrent(startIndex);
            } else {
                this.log('findNext: normal next, going to:', this.currentMatchIndex + 1);
                await this.setCurrent(this.currentMatchIndex + 1);
            }
        }

        async findPrevious() {
            if (this.matches.length === 0) return;

            if (this.useClickLocationForNext) {
                const startIndex = this.getStartingMatchIndex();
                this.useClickLocationForNext = false;
                await this.setCurrent(startIndex - 1);
            } else {
                await this.setCurrent(this.currentMatchIndex - 1);
            }
        }

        // Reveal a specific match by its identifier
        async reveal(identifier) {
            if (!identifier) {
                this.log('reveal: no identifier provided');
                return;
            }

            // Find the match by comparing identifier data
            const matchIndex = this.matches.findIndex(m =>
                m.text === identifier.text &&
                JSON.stringify(m.coordinates) === JSON.stringify(identifier.coordinates)
            );

            if (matchIndex === -1) {
                this.log('reveal: match not found for identifier', identifier);
                return;
            }

            this.log('reveal: found match at index', matchIndex);

            // Make this the current match and scroll to it
            // setCurrent will handle scrolling and send currentChanged message
            await this.setCurrent(matchIndex);
        }

        // Get current bounding box for a match using its stable identifier
        async getMatchBounds(identifier) {
            if (!identifier) {
                this.log('getMatchBounds: no identifier provided');
                return {};
            }

            // Find the match by comparing identifier data
            const match = this.matches.find(m =>
                m.text === identifier.text &&
                JSON.stringify(m.coordinates) === JSON.stringify(identifier.coordinates)
            );

            if (!match) {
                this.log('getMatchBounds: match not found for identifier', identifier);
                return {};
            }
            
            // Handle based on match type
            if (match.type === 'local') {
                return this.getLocalMatchBounds(match);
            } else if (match.type === 'remote') {
                return await this.getRemoteMatchBounds(match);
            }
            
            return {};
        }
        
        getLocalMatchBounds(match) {
            // Get bounding boxes for all elements of this match
            const elementBounds = match.highlightElements?.map(el => {
                const rect = _getBoundingClientRect.call(el);
                // Convert viewport-relative coordinates to document-relative coordinates
                return {
                    left: rect.left + window.scrollX,
                    top: rect.top + window.scrollY,
                    right: rect.right + window.scrollX,
                    bottom: rect.bottom + window.scrollY
                };
            }) || [];

            if (elementBounds.length === 0) {
                this.log('getLocalMatchBounds: match has no elements');
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

            this.log('getLocalMatchBounds: returning bounds', result);
            return result;
        }
        
        async getRemoteMatchBounds(match) {
            this.log('getRemoteMatchBounds: starting bounds retrieval for remote match', {
                frameId: match.frameId,
                remoteIndex: match.remoteIndex,
                coordinates: match.coordinates
            });
            
            // Get bounds from the iframe and transform to main frame coordinates
            const script = `
                (function() {
                    if (window.iTermCustomFind && window.iTermCustomFind.getRemoteMatchBounds) {
                        return window.iTermCustomFind.getRemoteMatchBounds(${match.remoteIndex});
                    }
                    return null;
                })()
            `;
            
            this.log('getRemoteMatchBounds: evaluating bounds script in frame:', match.frameId);
            
            const remoteBounds = await new Promise((resolve) => {
                window.iTermGraphDiscovery.evaluateInFrame(match.frameId, script, (result) => {
                    this.log('getRemoteMatchBounds: bounds script completed with result:', result);
                    resolve(result);
                });
            });
            
            if (!remoteBounds || typeof remoteBounds !== 'object') {
                this.log('getRemoteMatchBounds: WARNING - failed to get bounds from iframe, result:', remoteBounds);
                return {};
            }
            
            // Transform coordinates from iframe to main frame
            const iframeSegment = this.segments.find(s => 
                s.type === 'iframe' && s.frameId === match.frameId
            );
            
            if (!iframeSegment) {
                this.log('getRemoteMatchBounds: ERROR - iframe segment not found for frameId:', match.frameId);
                return {};
            }
            
            // Get iframe bounds in main frame
            const iframeRect = _getBoundingClientRect.call(iframeSegment.iframe);
            
            this.log('getRemoteMatchBounds: iframe bounds in main frame:', {
                left: iframeRect.left,
                top: iframeRect.top,
                width: iframeRect.width,
                height: iframeRect.height
            });
            
            this.log('getRemoteMatchBounds: remote bounds from iframe:', remoteBounds);
            
            // Transform iframe-relative coordinates to main frame coordinates
            const result = {
                x: remoteBounds.x + iframeRect.left + window.scrollX,
                y: remoteBounds.y + iframeRect.top + window.scrollY,
                width: remoteBounds.width,
                height: remoteBounds.height
            };
            
            this.log('getRemoteMatchBounds: returning transformed bounds to main frame coordinates', result);
            return result;
        }

        // ---------- Hide/Show Results ----------

        hideResults() {
            this.log('hideResults: hiding all search result highlights');

            // Hide both regular and current highlights for this instance
            const highlights = _querySelectorAll(
                `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
                `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
            );

            highlights.forEach(highlight => {
                // Add the hidden class to hide the highlight
                _classList_add.call(highlight.classList, 'iterm-find-removed');
            });

            this.log(`hideResults: hid ${highlights.length} highlight elements`);
        }

        showResults() {
            this.log('showResults: showing all search result highlights');

            // Show both regular and current highlights for this instance
            const highlights = _querySelectorAll(
                `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
                `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
            );

            highlights.forEach(highlight => {
                // Remove the hidden class to show the highlight
                _classList_remove.call(highlight.classList, 'iterm-find-removed');
            });

            this.log(`showResults: showed ${highlights.length} highlight elements`);
        }

        // ---------- Context Extraction ----------

        extractContextBefore(match, contextLen) {
            if (!contextLen || match.type !== 'local') {
                return '';
            }
            
            const segment = match.segment || this.segments[match.coordinates[0]];
            if (!segment || segment.type !== 'text') {
                return '';
            }
            
            const startPos = Math.max(0, match.localStart - contextLen);
            const endPos = match.localStart;
            
            return segment.textContent.substring(startPos, endPos).replace(/^\s+/, '');
        }
        
        extractContextAfter(match, contextLen) {
            if (!contextLen || match.type !== 'local') {
                return '';
            }
            
            const segment = match.segment || this.segments[match.coordinates[0]];
            if (!segment || segment.type !== 'text') {
                return '';
            }
            
            const startPos = match.localEnd;
            const endPos = Math.min(segment.textContent.length, match.localEnd + contextLen);
            
            return segment.textContent.substring(startPos, endPos).replace(/\s+$/, '');
        }
        
        extractMatchContext(match) {
            if (match.type === 'local') {
                return {
                    contextBefore: this.extractContextBefore(match, this.contextLen),
                    contextAfter: this.extractContextAfter(match, this.contextLen)
                };
            } else if (match.type === 'remote') {
                // Remote matches already have context from iframe search
                return {
                    contextBefore: match.contextBefore || '',
                    contextAfter: match.contextAfter || ''
                };
            }
            
            return {
                contextBefore: '',
                contextAfter: ''
            };
        }
        
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
                coordinates: m.coordinates,
                text: m.text
            }));

            this.log('reportResults: created', matchIdentifiers.length, 'match identifiers');

            // Extract contexts for each match (always create array for consistency)
            let contexts = undefined;
            if (fullUpdate) {
                contexts = this.matches.map((match, index) => {
                    const context = this.extractMatchContext(match);
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

            this.log('reportResults: posting message to Swift...');
            if (securePostMessage(payload)) {
                this.log('reportResults: message posted successfully');
            } else {
                this.log('reportResults: ERROR - failed to post message');
            }
        }

        async handleFindCommand(command) {
            this.log('handleFindCommand:', command);

            switch (command.action) {
                case 'startFind':
                    await this.startFind(command.searchTerm, command.searchMode, command.contextLength);
                    break;
                case 'findNext':
                    await this.findNext();
                    break;
                case 'findPrevious':
                    await this.findPrevious();
                    break;
                case 'clearFind':
                    this.clearHighlights();
                    this.currentSearchTerm = '';
                    this.reportResults(true);
                    break;
                case 'reveal':
                    await this.reveal(command.identifier);
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
            // Limit number of instances
            if (INSTANCES.size >= MAX_INSTANCES) {
                console.error(TAG, 'Maximum number of instances reached');
                return null;
            }
            engine = new FindEngine(key);
            INSTANCES.set(key, engine);
        }
        return engine;
    }

    function handleCommand(command) {
        const validated = validateCommand(command);
        if (!validated) {
            console.error(TAG, 'Invalid command');
            return;
        }

        const engine = getEngine(validated.instanceId);
        if (!engine) {
            console.error(TAG, 'Could not create engine');
            return;
        }

        return engine.handleFindCommand(validated);
    }

    function destroyInstance(command) {
        if (!validateSessionSecret(command?.sessionSecret)) {
            console.error(TAG, 'Invalid session secret for destroyInstance');
            return;
        }

        const id = sanitizeInstanceId(command.instanceId);
        const engine = INSTANCES.get(id);
        if (engine) {
            engine.destroy();
        }
    }

    function getDebugState(command) {
        if (!validateSessionSecret(command?.sessionSecret)) {
            console.error(TAG, 'Invalid session secret for getDebugState');
            return { error: 'Unauthorized' };
        }

        const id = sanitizeInstanceId(command.instanceId);
        const engine = INSTANCES.get(id);
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
            return engine.extractMatchContext(match);
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

    function clearStateWithoutResponse(command) {
        if (!validateSessionSecret(command?.sessionSecret)) {
            console.error(TAG, 'Invalid session secret for clearStateWithoutResponse');
            return { error: 'Unauthorized' };
        }

        const id = sanitizeInstanceId(command.instanceId);
        const engine = INSTANCES.get(id);
        if (!engine) return { error: 'No engine found' };

        // Clear state without sending response to Swift
        engine.clearHighlights();
        engine.currentSearchTerm = '';
        if (engine.clearClickLocation) {
            engine.clearClickLocation();
        }

        return { cleared: true };
    }

    function refreshBlockBounds(command) {
        if (!validateSessionSecret(command?.sessionSecret)) {
            console.error(TAG, 'Invalid session secret for refreshBlockBounds');
            return { error: 'Unauthorized' };
        }

        const id = sanitizeInstanceId(command.instanceId);
        const engine = INSTANCES.get(id);
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

    function getBlocks(command) {
        if (!validateSessionSecret(command?.sessionSecret)) {
            console.error(TAG, 'Invalid session secret for getBlocks');
            return { error: 'Unauthorized' };
        }

        const id = sanitizeInstanceId(command.instanceId);
        const engine = INSTANCES.get(id);
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

    function getMatchBoundsInEngine(command) {
        if (!validateSessionSecret(command?.sessionSecret)) {
            console.error(TAG, 'Invalid session secret for getMatchBoundsInEngine');
            return { error: 'Unauthorized' };
        }

        const id = sanitizeInstanceId(command.instanceId);
        const engine = INSTANCES.get(id);
        if (!engine) {
            return { error: 'No engine found' };
        }

        // Validate identifier
        let identifier = null;
        if (command.identifier && typeof command.identifier === 'object') {
            identifier = {
                bufferStart: validateNumber(command.identifier.bufferStart, 0, Number.MAX_SAFE_INTEGER, 0),
                bufferEnd: validateNumber(command.identifier.bufferEnd, 0, Number.MAX_SAFE_INTEGER, 0),
                text: sanitizeString(command.identifier.text, 100)
            };
        }

        return engine.getMatchBounds ? engine.getMatchBounds(identifier) : { error: 'Method not implemented' };
    }

    {{TEST_IMPLS}}

    // Helper functions for iframe highlighting and navigation
    function highlightMatches(instanceId) {
        console.log('[iTermCustomFind-BlockBased] highlightMatches called with instanceId:', instanceId);
        const engine = getEngine(instanceId);
        if (!engine) {
            console.log('[iTermCustomFind-BlockBased] highlightMatches: no engine found for instanceId:', instanceId);
            return;
        }
        if (!engine.matches) {
            console.log('[iTermCustomFind-BlockBased] highlightMatches: engine has no matches');
            return;
        }
        console.log('[iTermCustomFind-BlockBased] highlightMatches: found', engine.matches.length, 'matches in engine');
        for (const match of engine.matches) {
            console.log('[iTermCustomFind-BlockBased] highlightMatches: processing match type:', match.type);
            if (match.type === 'local') {
                engine.highlightLocalMatch(match);
            }
        }
    }
    
    function highlightRemoteMatch(index, instanceId) {
        const engine = getEngine(instanceId);
        if (!engine) {
            console.log('[iTermCustomFind-BlockBased] highlightRemoteMatch: no engine available for index', index);
            return;
        }
        
        engine.log('highlightRemoteMatch: highlighting match in iframe', {
            index: index,
            totalMatches: engine.matches ? engine.matches.length : 0
        });
        
        if (engine && engine.matches && engine.matches[index]) {
            const match = engine.matches[index];
            engine.log('highlightRemoteMatch: found match to highlight - ID:', match.id, 'at index', index, {
                matchType: match.type,
                coordinates: match.coordinates,
                text: match.text ? match.text.substring(0, 30) + '...' : 'null',
                hasHighlightElements: !!match.highlightElements,
                highlightElementsLength: match.highlightElements ? match.highlightElements.length : 'N/A'
            });
            
            if (match.type === 'local') {
                // Clear all current highlights first
                clearCurrentHighlight(instanceId);
                
                // Set this as current
                if (match.highlightElements && match.highlightElements.length > 0) {
                    engine.log('highlightRemoteMatch: updating', match.highlightElements.length, 'elements to current');
                    match.highlightElements.forEach(e => {
                        e.className = 'iterm-find-highlight-current';
                    });
                    
                    // Scroll into view
                    engine.log('highlightRemoteMatch: scrolling first highlight element into view');
                    _scrollIntoView.call(match.highlightElements[0], {
                        behavior: 'smooth',
                        block: 'center',
                        inline: 'center'
                    });
                } else {
                    engine.log('highlightRemoteMatch: WARNING - no highlight elements to update for match ID:', match.id, 'at index', index, {
                        highlightElementsUndefined: match.highlightElements === undefined,
                        highlightElementsNull: match.highlightElements === null,
                        highlightElementsLength: match.highlightElements ? match.highlightElements.length : 'N/A',
                        highlightElementsType: typeof match.highlightElements
                    });
                }
            } else {
                engine.log('highlightRemoteMatch: WARNING - match is not local type:', match.type);
            }
        } else {
            engine.log('highlightRemoteMatch: WARNING - match not found at index', index, 'total matches:', engine.matches ? engine.matches.length : 0);
        }
    }
    
    function clearCurrentHighlight(instanceId) {
        const engine = getEngine(instanceId);
        if (!engine) {
            console.log('[iTermCustomFind-BlockBased] clearCurrentHighlight: no engine available');
            return;
        }
        
        engine.log('clearCurrentHighlight: clearing current highlights in iframe');
        
        if (engine.matches) {
            let clearedCount = 0;
            for (const match of engine.matches) {
                if (match.type === 'local' && match.highlightElements) {
                    match.highlightElements.forEach(e => {
                        if (e.className === 'iterm-find-highlight-current') {
                            e.className = 'iterm-find-highlight';
                            clearedCount++;
                        }
                    });
                }
            }
            engine.log('clearCurrentHighlight: cleared', clearedCount, 'highlight elements in iframe');
        } else {
            engine.log('clearCurrentHighlight: no matches to clear');
        }
    }
    
    function getRemoteMatchBounds(index, instanceId) {
        const engine = getEngine(instanceId);
        if (!engine) {
            console.log('[iTermCustomFind-BlockBased] getRemoteMatchBounds: no engine available for index', index);
            return null;
        }
        
        engine.log('getRemoteMatchBounds: getting bounds for match in iframe', {
            index: index,
            totalMatches: engine.matches ? engine.matches.length : 0
        });
        
        if (engine.matches && engine.matches[index]) {
            const match = engine.matches[index];
            engine.log('getRemoteMatchBounds: found match', {
                matchType: match.type,
                coordinates: match.coordinates,
                hasHighlightElements: !!match.highlightElements
            });
            
            if (match.type === 'local') {
                const bounds = engine.getLocalMatchBounds(match);
                engine.log('getRemoteMatchBounds: returning bounds from iframe', bounds);
                return bounds;
            } else {
                engine.log('getRemoteMatchBounds: WARNING - match is not local type:', match.type);
            }
        } else {
            engine.log('getRemoteMatchBounds: WARNING - match not found at index', index);
        }
        return null;
    }
    
    function handleClickInFrame(x, y, instanceId) {
        const engine = getEngine(instanceId);
        if (!engine) {
            console.log('[iTermCustomFind-BlockBased] handleClickInFrame: no engine available for coordinates', { x, y });
            return null;
        }
        
        engine.log('handleClickInFrame: handling click in iframe', {
            x: x,
            y: y,
            hasSegments: !!(engine.segments && engine.segments.length > 0)
        });
        
        // Ensure we have segments collected
        if (!engine.segments || engine.segments.length === 0) {
            engine.log('handleClickInFrame: no segments found, building segments synchronously');
            engine.buildSegments(document.body);
            engine.log('handleClickInFrame: built', engine.segments.length, 'segments');
        }
        
        // Use the same click handling logic as main frame
        const result = engine.handleTextSegmentClickInternal(x, y);
        engine.log('handleClickInFrame: click handling completed with result:', result);
        return result;
    }
    
    // Helper function for frames to search their own content when called by evaluateInAll
    function searchInFrame(params) {
        const { searchTerm, searchMode, contextLength, instanceId } = params;
        
        // Use the passed instance ID to get the correct engine
        const engine = getEngine(instanceId);
        if (!engine) {
            console.log('[iTermCustomFind-BlockBased] searchInFrame: no engine available, returning empty results');
            return { matches: [] };
        }
        
        // Ensure iframe engine has its frame ID from graph discovery
        if (!engine.frameId) {
            // For iframe contexts, get frame ID from graph discovery system
            const discoverySymbol = Symbol.for('iTermGraphDiscovery');
            if (window[discoverySymbol] && window[discoverySymbol].frameId) {
                engine.frameId = window[discoverySymbol].frameId;
            }
        }
        
        engine.log('searchInFrame: starting search in iframe', {
            searchTerm: searchTerm,
            searchMode: searchMode,
            contextLength: contextLength
        });
        
        // Set search parameters
        engine.searchMode = searchMode || 'caseInsensitive';
        engine.contextLen = contextLength || 0;
        
        // Ensure we have segments collected
        if (!engine.segments || engine.segments.length === 0) {
            engine.log('searchInFrame: no segments found, building segments synchronously');
            // Synchronously collect segments if not already done
            // For iframes, we can't use async in this context
            engine.buildSegments(document.body);
            engine.log('searchInFrame: built', engine.segments.length, 'segments');
        } else {
            engine.log('searchInFrame: using existing', engine.segments.length, 'segments');
        }
        
        // Create regex and find matches
        const regex = engine.createSearchRegex(searchTerm);
        const matches = engine.findLocalMatches(regex);
        
        // Store matches in the engine so they can be highlighted later
        engine.matches = matches;
        
        engine.log('searchInFrame: found', matches.length, 'local matches in iframe');
        
        // Return matches with their coordinates, positions, and context
        const result = {
            matches: matches.map(match => ({
                coordinates: match.coordinates,
                text: match.text,
                localStart: match.localStart,
                localEnd: match.localEnd,
                contextBefore: contextLength > 0 ? engine.extractContextBefore(match, contextLength) : '',
                contextAfter: contextLength > 0 ? engine.extractContextAfter(match, contextLength) : ''
            }))
        };
        
        engine.log('searchInFrame: returning search results for iframe', {
            matchCount: result.matches.length,
            sampleMatch: result.matches[0] ? {
                coordinates: result.matches[0].coordinates,
                text: result.matches[0].text.substring(0, 20) + '...'
            } : null
        });
        
        return result;
    }
    
    // Expose API - Make it immutable
    const api = {
        handleCommand,
        destroyInstance,
        getMatchBoundsInEngine,
        clearStateWithoutResponse,
        searchInFrame,
        highlightMatches,
        highlightRemoteMatch,
        clearCurrentHighlight,
        getRemoteMatchBounds,
        handleClickInFrame
        {{TEST_FUNCTIONS}}
    };

    // Freeze the API object and all its methods
    Object.freeze(api);
    Object.freeze(api.handleCommand);
    Object.freeze(api.destroyInstance);
    Object.freeze(api.getMatchBoundsInEngine);
    Object.freeze(api.clearStateWithoutResponse);
    Object.freeze(api.searchInFrame);
    Object.freeze(api.highlightMatches);
    Object.freeze(api.highlightRemoteMatch);
    Object.freeze(api.clearCurrentHighlight);
    Object.freeze(api.getRemoteMatchBounds);
    Object.freeze(api.handleClickInFrame);
    {{TEST_FREEZE}}

    // Use Object.defineProperty to make it non-configurable and non-writable
    Object.defineProperty(window, 'iTermCustomFind', {
        value: api,
        writable: false,
        configurable: false,
        enumerable: true
    });

    console.debug(TAG, 'Block-based find engine initialized');
    console.log('Block-based find engine initialized - visible in console');
})();
