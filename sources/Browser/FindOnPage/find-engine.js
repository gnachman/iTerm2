// Global registry of engines on this page
const INSTANCES = new Map();

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

        // Don't import global click location yet - wait until we have frame graph

        // Listeners
        this.boundHandleClick = (event) => { this.handleClick(event); };
        this.boundHandleNavigation = () => {
            this.log("Clear click location because of navigation");
            this.clearClickLocation();
        };
        this.highlighter = new FindHighlighter(this.log.bind(this), this.instanceId, null);

        document.addEventListener('click', this.boundHandleClick, true);
        window.addEventListener('beforeunload', this.boundHandleNavigation);
        window.addEventListener('pagehide', this.boundHandleNavigation);

        // Listen for iframe click notifications in all frames (to pass them up the chain)
        this.boundHandleMessage = (event) => { this.handleMessage(event); };
        window.addEventListener('message', this.boundHandleMessage);
    }

    log(...args) {
        const frameInfo = this.frameId ? `frame:${this.frameId.substring(0, 8)}` : 'frame:unknown';
        const prefix = `${TAG} [${this.instanceId}|${frameInfo}]`;
        const message = `${prefix} ${args.map(a => (typeof a === 'object' ? safeStringify(a) : a)).join(' ')}`;
        console.debug(message);
    }

    debuglog(...args) {
        if (verbose) {
            const frameInfo = this.frameId ? `frame:${this.frameId.substring(0, 8)}` : 'frame:unknown';
            const prefix = `${TAG} [${this.instanceId}|${frameInfo}]`;
            const message = `${prefix} ${args.map(a => (typeof a === 'object' ? safeStringify(a) : a)).join(' ')}`;
            console.debug(message);
        }
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
            if (this.isMainFrame) {
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
                this.log('discoverFrameGraph: about to call graphDiscoveryDiscover');
                graphDiscoveryDiscover(async (graph) => {
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
                    this.highlighter.frameId = graph.frameId;
                    const childCount = graph.children ? graph.children.length : 0;
                    this.log('discoverFrameGraph: EXIT - graph discovered, frameId:', this.frameId?.substring(0, 8), 'children:', childCount);
                    if (childCount > 0) {
                        this.log('discoverFrameGraph: child frame IDs:', graph.children.map(c => c.frameId?.substring(0, 8)));
                    }

                    // Now that we have the frame graph, we can safely import any global click location
                    await this.importGlobalClickLocation();
                    resolve();
                });
                this.log('discoverFrameGraph: graphDiscoveryDiscover called successfully');
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

        // Collect items (text ranges and iframes) in document order
        const items = this.collectItems(root);
        this.log('buildSegments: collected', items.length, 'items');

        // Build segments from items
        let currentTextNodes = [];
        let currentContainerElement = null;

        for (const item of items) {
            if (item.type === 'iframe') {
                // Finish current text segment if we have text nodes
                if (currentTextNodes.length > 0) {
                    const textSegment = new TextSegment(segmentIndex++, currentContainerElement);
                    textSegment.setTextNodes(currentTextNodes, this);
                    this.segments.push(textSegment);
                    this.log('buildSegments: added text segment', textSegment.index, 'with', textSegment.textContent.length, 'chars');
                    currentTextNodes = [];
                    currentContainerElement = null;
                }

                // Add iframe segment
                const iframeSegment = new IframeSegment(segmentIndex++, item.element, null);
                this.segments.push(iframeSegment);
                this.log('buildSegments: added iframe segment', iframeSegment.index);
            } else if (item.type === 'textRange') {
                // Add text nodes to current segment
                currentTextNodes.push(...item.textNodes);
                if (!currentContainerElement) {
                    currentContainerElement = item.containerElement;
                }
            }
        }

        // Finish final text segment if we have remaining text nodes
        if (currentTextNodes.length > 0) {
            const textSegment = new TextSegment(segmentIndex++, currentContainerElement);
            textSegment.setTextNodes(currentTextNodes, this);
            this.segments.push(textSegment);
            this.log('buildSegments: added final text segment', textSegment.index, 'with', textSegment.textContent.length, 'chars');
        }

        // Match iframe segments with frame graph
        if (this.frameGraph) {
            this.matchIframesToGraph();
        }
    }

    // Collect items (text ranges and iframes) in document order
    collectItems(root) {
        const items = [];
        
        // Walk the DOM tree in document order, collecting text ranges and iframe boundaries
        const walkNode = (node) => {
            if (node.nodeType === Node.TEXT_NODE) {
                // Skip empty text nodes and scripts/styles
                const parent = node.parentElement;
                if (!parent || node.textContent.trim().length === 0) {
                    return;
                }
                if (_matches.call(parent, 'script, style, noscript')) {
                    return;
                }
                
                // Add this text node to the current text range
                // We'll group adjacent text nodes later
                items.push({
                    type: 'text',
                    node: node,
                    containerElement: parent
                });
                return;
            }
            
            if (node.nodeType === Node.ELEMENT_NODE) {
                if (node.tagName === 'IFRAME') {
                    // Iframe creates a segment boundary
                    items.push({ type: 'iframe', element: node });
                    return; // Don't recurse into iframe content
                }
                
                // For all other elements, recurse into children in document order
                for (const child of node.childNodes) {
                    walkNode(child);
                }
            }
        };

        walkNode(root);
        
        // Group adjacent text nodes into text ranges, with iframes creating boundaries
        return this.groupIntoRanges(items);
    }
    
    // Group adjacent text items into ranges, with iframes as boundaries
    groupIntoRanges(items) {
        const ranges = [];
        let currentTextNodes = [];
        
        for (const item of items) {
            if (item.type === 'iframe') {
                // Finish current text range if we have text nodes
                if (currentTextNodes.length > 0) {
                    ranges.push({
                        type: 'textRange',
                        textNodes: currentTextNodes,
                        containerElement: this.findCommonAncestor(currentTextNodes)
                    });
                    currentTextNodes = [];
                }
                
                // Add iframe as boundary
                ranges.push({ type: 'iframe', element: item.element });
            } else if (item.type === 'text') {
                // Add text node to current range
                currentTextNodes.push(item.node);
            }
        }
        
        // Finish final text range if we have remaining text nodes
        if (currentTextNodes.length > 0) {
            ranges.push({
                type: 'textRange',
                textNodes: currentTextNodes,
                containerElement: this.findCommonAncestor(currentTextNodes)
            });
        }
        
        return ranges;
    }
    
    // Find the lowest common ancestor of all text nodes
    findCommonAncestor(textNodes) {
        if (textNodes.length === 0) return null;
        if (textNodes.length === 1) return textNodes[0].parentElement;
        
        // Start with the first node's ancestors
        let commonAncestor = textNodes[0].parentElement;
        
        // Check each subsequent text node
        for (let i = 1; i < textNodes.length; i++) {
            commonAncestor = this.findLowestCommonAncestor(commonAncestor, textNodes[i].parentElement);
            if (!commonAncestor) {
                // Fallback to document.body if no common ancestor found
                return document.body;
            }
        }
        
        return commonAncestor;
    }
    
    // Find the lowest common ancestor of two elements
    findLowestCommonAncestor(element1, element2) {
        if (!element1 || !element2) return null;
        
        // Get all ancestors of element1
        const ancestors1 = [];
        let current = element1;
        while (current) {
            ancestors1.push(current);
            current = current.parentElement;
        }
        
        // Walk up from element2 until we find a common ancestor
        current = element2;
        while (current) {
            if (ancestors1.includes(current)) {
                return current;
            }
            current = current.parentElement;
        }
        
        return null; // Should never happen in a well-formed DOM
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

            // If this is an iframe (not the main frame), also notify the main frame
            if (window.parent && window.parent !== window) {
                this.notifyMainFrameOfClick(clickLocation);
            }
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
            graphDiscoveryEvaluateInFrame(iframeSegment.frameId, script, (result) => {
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

            // Calculate position by walking the DOM
            const position = this.calculateClickPositionInSegment(segment, textNode, offset);
            if (position !== null) {
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

    calculateClickPositionInSegment(segment, targetTextNode, targetOffset) {
        // Walk through all text nodes in the segment to find the target node
        // and calculate its position
        let currentPosition = 0;

        const walker = _createTreeWalker(segment.element, _SHOW_TEXT, {
            acceptNode: (node) => {
                const parent = node.parentElement;
                if (!parent) return _FILTER_REJECT;
                if (_matches.call(parent, 'script, style, noscript')) {
                    return _FILTER_REJECT;
                }
                return _FILTER_ACCEPT;
            }
        }, false);

        let node;
        while (node = walker.nextNode()) {
            if (node === targetTextNode) {
                // Found the target node
                return currentPosition + targetOffset;
            }
            // Add the length of this text node to our position
            currentPosition += node.textContent.length;
        }

        // Target node not found
        this.log('calculateClickPositionInSegment: target text node not found in segment');
        return null;
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
        this.log("clearClickLocation");
        this.lastClickLocation = null;
        this.useClickLocationForNext = false;
    }

    async importGlobalClickLocation() {
        // Convert global click location (if any) to engine coordinates
        if (!globalClickLocation) {
            return;
        }

        this.log('importGlobalClickLocation: attempting to import global click location');

        if (globalClickLocation.type === 'iframe') {
            // Handle iframe clicks
            await this.importIframeGlobalClick();
        } else {
            // Handle main frame clicks
            this.importMainFrameGlobalClick();
        }
    }

    importMainFrameGlobalClick() {
        // Check if the text node is still connected to the document
        if (!globalClickLocation.textNode.isConnected) {
            this.log('importGlobalClickLocation: global click text node is no longer connected, clearing');
            globalClickLocation = null;
            return;
        }

        // Build segments so we can convert the click location
        this.buildSegments(document.body);

        // Find which segment contains the clicked text node
        for (let i = 0; i < this.segments.length; i++) {
            const segment = this.segments[i];
            if (segment.type !== 'text') continue;

            // Calculate position using the same logic as click handling
            const position = this.calculateClickPositionInSegment(segment, globalClickLocation.textNode, globalClickLocation.offset);
            if (position !== null) {
                this.lastClickLocation = {
                    coordinates: [i, position],
                    type: 'local'
                };
                this.useClickLocationForNext = true;
                this.log('importGlobalClickLocation: converted main frame click to coordinates', [i, position]);

                // Clear the global click location since we've consumed it
                globalClickLocation = null;
                return;
            }
        }

        this.log('importGlobalClickLocation: could not find segment containing clicked text node');
        globalClickLocation = null;
    }

    async importIframeGlobalClick() {
        this.log('importGlobalClickLocation: importing iframe click');

        // Build segments to find iframes and their frameIds
        this.buildSegments(document.body);

        // Find the frameId for the iframe that sent the click
        let clickedFrameId = null;
        for (let i = 0; i < this.segments.length; i++) {
            const segment = this.segments[i];
            if (segment.type === 'iframe' && segment.iframe &&
                segment.iframe.contentWindow === globalClickLocation.source) {
                clickedFrameId = segment.frameId;
                break;
            }
        }

        if (!clickedFrameId) {
            this.log('importGlobalClickLocation: could not find frameId for click source');
            globalClickLocation = null;
            return;
        }

        this.log('importGlobalClickLocation: found clicked frameId:', clickedFrameId.substring(0, 8));

        // Find the path to this frameId in the frameGraph
        const iframePath = this.findPathToFrame(this.frameGraph, clickedFrameId);
        if (!iframePath) {
            this.log('importGlobalClickLocation: could not find path to frameId in graph');
            globalClickLocation = null;
            return;
        }

        this.log('importGlobalClickLocation: iframe path:', iframePath);

        // Get local coordinates from the clicked iframe
        const x = globalClickLocation.clickData.coordinates.x;
        const y = globalClickLocation.clickData.coordinates.y;

        const conversionScript = `
            (function() {
                if (window.iTermCustomFind && window.iTermCustomFind.handleClickInFrame) {
                    return window.iTermCustomFind.handleClickInFrame(${x}, ${y}, '${this.instanceId}');
                }
                return null;
            })()
        `;

        try {
            const iframeResult = await new Promise((resolve) => {
                graphDiscoveryEvaluateInFrame(clickedFrameId, conversionScript, (result) => {
                    resolve(result);
                });
            });

            if (iframeResult && iframeResult.coordinates && Array.isArray(iframeResult.coordinates)) {
                // Build full coordinate path: [iframe path] + [local coordinates]
                const remoteCoordinates = [...iframePath, ...iframeResult.coordinates];

                this.lastClickLocation = {
                    coordinates: remoteCoordinates,
                    type: 'remote'
                };
                this.useClickLocationForNext = true;
                this.log('importGlobalClickLocation: converted iframe click to remote coordinates', remoteCoordinates);
            } else {
                this.log('importGlobalClickLocation: iframe coordinate conversion failed');
                globalClickLocation = null;
                return;
            }
        } catch (e) {
            this.log('importGlobalClickLocation: error converting iframe coordinates:', e);
            globalClickLocation = null;
            return;
        }

        globalClickLocation = null;
    }

    findPathToFrame(graph, targetFrameId, currentPath = []) {
        if (!graph) return null;

        // If this is the target frame, return the current path
        if (graph.frameId === targetFrameId) {
            return currentPath;
        }

        // Search in children
        if (graph.children) {
            for (let i = 0; i < graph.children.length; i++) {
                const child = graph.children[i];
                // For each child iframe, the path includes the segment index of that iframe
                // We need to map child index to segment index
                const childPath = this.findPathToFrame(child, targetFrameId, [...currentPath, this.getSegmentIndexForChildFrame(i)]);
                if (childPath) {
                    return childPath;
                }
            }
        }

        return null;
    }

    getSegmentIndexForChildFrame(childIndex) {
        // Find the segment index for the iframe at the given child index
        let iframeCount = 0;
        for (let i = 0; i < this.segments.length; i++) {
            if (this.segments[i].type === 'iframe') {
                if (iframeCount === childIndex) {
                    return i;
                }
                iframeCount++;
            }
        }
        return 0; // fallback
    }

    notifyMainFrameOfClick(iframeClickLocation) {
        this.log('notifyMainFrameOfClick: notifying parent frame of iframe click', iframeClickLocation);

        // Send message to parent frame with click information
        // The parent will either handle it (if it's the main frame) or pass it up the chain
        try {
            window.parent.postMessage({
                type: 'iTermIframeClick',
                frameId: this.frameId,
                clickLocation: iframeClickLocation,
                // Include segment index path for nested iframes
                framePath: [this.frameId]
            }, '*');
            this.log('notifyMainFrameOfClick: posted message to parent frame');
        } catch (e) {
            this.log('notifyMainFrameOfClick: failed to post message to parent:', e);
        }
    }

    handleMessage(event) {
        // Only handle our specific message type
        if (!event.data || event.data.type !== 'iTermIframeClick') {
            return;
        }

        this.log('handleMessage: received iframe click notification', event.data);

        const { frameId, clickLocation, framePath } = event.data;

        // Check if we're the main frame
        if (window === window.top) {
            // We're the main frame - handle the click location
            this.handleIframeClickNotification(frameId, clickLocation, framePath);
        } else {
            // We're an intermediate frame - pass the message up the chain
            // Add our frame ID to the path
            const updatedPath = [...(framePath || []), this.frameId];

            try {
                window.parent.postMessage({
                    type: 'iTermIframeClick',
                    frameId: frameId,  // Keep the original frame ID
                    clickLocation: clickLocation,
                    framePath: updatedPath
                }, '*');
                this.log('handleMessage: forwarded iframe click to parent');
            } catch (e) {
                this.log('handleMessage: failed to forward message to parent:', e);
            }
        }
    }

    handleIframeClickNotification(frameId, clickLocation, framePath) {
        this.log('handleIframeClickNotification: main frame received iframe click', {
            frameId: frameId,
            clickLocation: clickLocation,
            framePath: framePath
        });

        // Find the iframe segment that matches this frame ID
        let iframeSegmentIndex = null;
        for (let i = 0; i < this.segments.length; i++) {
            const segment = this.segments[i];
            if (segment.type === 'iframe' && segment.frameId === frameId) {
                iframeSegmentIndex = i;
                break;
            }
        }

        if (iframeSegmentIndex === null) {
            this.log('handleIframeClickNotification: could not find iframe segment for frame', frameId);
            return;
        }

        // Convert iframe-local coordinates to global coordinates
        // The click location from iframe has coordinates relative to its own segments
        // We need to prepend the iframe segment index to make it global
        const globalCoordinates = [iframeSegmentIndex, ...(clickLocation.coordinates || [])];

        this.log('handleIframeClickNotification: converted to global coordinates', globalCoordinates);

        // Set the click location in the main frame
        this.lastClickLocation = {
            coordinates: globalCoordinates,
            type: 'remote'
        };
        this.useClickLocationForNext = true;

        this.log('handleIframeClickNotification: set main frame click location for findNext');
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

        // DEBUG: Log first 10 matches to understand ordering
        this.log('getStartingMatchIndex: DEBUG - first 10 matches:');
        for (let i = 0; i < Math.min(10, this.matches.length); i++) {
            const match = this.matches[i];
            const comparison = Match.compare(match, clickMatch);
            this.log(`  match ${i}: coordinates=${JSON.stringify(match.coordinates)}, text="${match.text}", comparison=${comparison}`);
        }

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

    async findMatchesWithIframes(regex, searchTerm) {
        this.log('findMatchesWithIframes: ENTER - searching for:', searchTerm, 'mode:', this.searchMode);
        this.log('findMatchesWithIframes: clearing matches array and frameMatches');
        this.matches = [];
        this.frameMatches.clear();
        this.log('findMatchesWithIframes: cleared - matches.length:', this.matches.length);
        
        // Refresh frame graph to catch any dynamically added iframes
        if (this.isMainFrame) {
            this.log('findMatchesWithIframes: refreshing frame graph to catch new iframes');
            await this.discoverFrameGraph();
            this.log('findMatchesWithIframes: frame graph refreshed, frameId:', this.frameId?.substring(0, 8), 'children:', this.frameGraph?.children?.length || 0);
        }

        if (!this.isMainFrame) {
            // If we're not the main frame, just do local search
            this.log('findMatchesWithIframes: child frame - doing local search only');
            this.matches = this.findLocalMatches(regex);
            this.log('findMatchesWithIframes: EXIT - child frame found', this.matches.length, 'local matches');
            return;
        }

        // Main frame: coordinate search across all frames using evaluateInAll
        this.log('findMatchesWithIframes: main frame - first doing local search, then coordinating cross-frame search');

        // First do our own local search
        const localMatches = this.findLocalMatches(regex);
        this.matches = localMatches;
        this.log('findMatchesWithIframes: main frame local search found', this.matches.length, 'matches');

        this.log('findMatchesWithIframes: now coordinating iframe searches');
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
            graphDiscoveryEvaluateInAll(searchScript, (results) => {
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
                this.log('findMatchesWithIframes: SKIPPING', result.matches.length, 'main frame matches - current total matches:', this.matches.length);
                continue;
            } else {
                // Remote frame's matches - need to find path through frame graph tree
                this.log('findMatchesWithIframes: looking for path to frame', frameIdShort, 'in frame graph with root:', this.frameGraph?.frameId?.substring(0, 8));
                const framePath = this.findPathToFrame(this.frameGraph, frameId);
                if (!framePath) {
                    this.log('findMatchesWithIframes: WARNING - no path found to frame', frameIdShort, 'in frame graph');
                    this.log('findMatchesWithIframes: DEBUG - frame graph structure:', JSON.stringify(this.frameGraph, null, 2));
                    continue;
                }

                this.log('findMatchesWithIframes: processing remote matches from frame', frameIdShort, 'via path:', framePath);
                result.matches.forEach((frameMatch, idx) => {
                    const originalCoords = frameMatch.coordinates;
                    const newCoords = [...framePath, ...frameMatch.coordinates];
                    this.log('findMatchesWithIframes: transforming coordinates for match', idx, 'from', originalCoords, 'to', newCoords, 'via path', framePath);
                    
                    const remoteMatch = new Match(
                        newCoords,
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

        // Count actual local vs remote matches for reporting
        const actualLocalCount = this.matches.filter(m => m.type === 'local').length;
        const actualRemoteCount = this.matches.filter(m => m.type === 'remote').length;
        this.log(`findMatchesWithIframes: EXIT - found ${this.matches.length} total matches (${actualLocalCount} local, ${actualRemoteCount} remote)`);
    }

    findLocalMatches(regex) {
        const matches = [];

        for (let segmentIdx = 0; segmentIdx < this.segments.length; segmentIdx++) {
            this.log("Searching segment", segmentIdx,"for",regex);
            const segment = this.segments[segmentIdx];

            if (segment.type !== 'text') {
                this.log("Skip segment of type",segment.type)
                continue;
            }

            regex.lastIndex = 0;
            let match;

            this.log("text is", segment.textContent);
            if (verbose) {
                for (const node of segment.textNodes) {
                    console.debug('findLocalMatches: node', node, 'has textContent:', node.textContent);
                }
            }
            while ((match = _RegExp_exec.call(regex, segment.textContent)) !== null) {
                this.log("found a match");
                const localMatch = new Match(
                    [segmentIdx, match.index],  // Coordinates: [segment, position]
                    match[0]  // Matched text
                );

                localMatch.type = 'local';
                localMatch.segment = segment;
                localMatch.localStart = match.index;
                this.log('findLocalMatches: assigned type "local" to match ID:', localMatch.id, 'frame:', (this.frameId?.substring(0, 8) || 'unknown'), 'coord:', localMatch.coordinates, 'in segment with text:', verbose ? segment.textContent : (segment.textContent.substring(0, 100) + (segment.textContent.length > 100 ? '...' : '')));
                localMatch.localEnd = match.index + match[0].length;

                matches.push(localMatch);

                if (match[0].length === 0) {
                    regex.lastIndex++;
                }
            }
        }

        return matches;
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
            graphDiscoveryEvaluateInAll(clearScript, (results) => {
                const clearedFrames = Object.keys(results).filter(frameId => !results[frameId]?.error);
                this.log('clearHighlightsInAllFrames: cleared highlights in', clearedFrames.length, 'frames - timestamp:', Date.now());
                resolve();
            });
        });
    }


    // ---------- Auto-reveal ----------
    ensureVisibleForMatch(match) {
        this.log('ensureVisibleForMatch: ENTER - match ID:', match?.id, 'type:', match?.type);
        this.log('ensureVisibleForMatch: match.highlightElements length:', match?.highlightElements?.length || 'null/undefined');
        this.log('ensureVisibleForMatch: match.els length:', match?.els?.length || 'null/undefined');

        // Handle both old (match.els) and new (match.highlightElements) structure
        const elements = match.highlightElements || match.els;
        if (!match || !elements || elements.length === 0) {
            this.log('ensureVisibleForMatch: EXIT early - no elements found');
            return;
        }

        const firstEl = elements[0];
        this.log('ensureVisibleForMatch: using firstEl:', firstEl?.tagName, 'className:', firstEl?.className);
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
                    if (isHidden(ae)) {
                        this.forceVisible(ae);
                    }
                });
            });
            this.log('ensureVisibleForMatch processed revealers:', match.revealers.size);
        }

        let hiddenAncestorCount = 0;
        ancestors(firstEl).forEach(ae => {
            if (isHidden(ae)) {
                this.forceVisible(ae);
                hiddenAncestorCount++;
            }
        });

        this.log('ensureVisibleForMatch: EXIT - processed', hiddenAncestorCount, 'hidden ancestors for firstEl');
    }

    // ---------- Clear ----------

    // Clear highlights just from this frame
    clearHighlights() {
        this.log('clearHighlights: starting for instanceId:', this.instanceId);

        const spans = _querySelectorAll(
            `.iterm-find-highlight[data-iterm-id="${this.instanceId}"], ` +
            `.iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`
        );

        this.log('clearHighlights: found', spans.length, 'spans to remove');

        const parents = new Set();
        spans.forEach((span, index) => {
            this.log('clearHighlights: removing span', index, 'className:', span.className, 'textContent:', JSON.stringify(span.textContent));
            const parent = span.parentNode;
            if (!parent) {
                this.log('clearHighlights: span', index, 'has no parent, skipping');
                return;
            }

            let childCount = 0;
            while (span.firstChild) {
                _insertBefore.call(parent, span.firstChild, span);
                childCount++;
            }
            this.log('clearHighlights: moved', childCount, 'child nodes from span', index);

            _removeChild.call(parent, span);
            parents.add(parent);
        });

        this.log('clearHighlights: normalizing', parents.size, 'parent elements');
        // Normalize text nodes
        parents.forEach(p => _normalize.call(p));

        this.log('clearHighlights: completed - timestamp:', Date.now());

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

        this.matches = [];
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

        // Debug: check if current match at index has valid highlightElements
        if (idx >= 0 && idx < this.matches.length) {
            const targetMatch = this.matches[idx];
            if (targetMatch.type === 'local') {
                this.log('setCurrent: TARGET MATCH DEBUG - ID:', targetMatch.id, 'type:', targetMatch.type);
                this.log('setCurrent: TARGET MATCH highlightElements length:', targetMatch.highlightElements?.length || 'null/undefined');
                if (targetMatch.highlightElements && targetMatch.highlightElements.length > 0) {
                    targetMatch.highlightElements.forEach((el, i) => {
                        this.log('setCurrent: TARGET MATCH element', i, '- isConnected:', el.isConnected, 'className:', el.className, 'parentNode:', !!el.parentNode);
                    });
                }
            }
        }

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
                    this.highlighter.applyRegularHighlightStyles(e);
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
            this.log('setCurrent: BEFORE ensureVisibleForMatch - current.highlightElements length:', current.highlightElements?.length || 'null/undefined');
            this.ensureVisibleForMatch(current);
            this.log('setCurrent: AFTER ensureVisibleForMatch - current.highlightElements length:', current.highlightElements?.length || 'null/undefined');

            // Check if this match has highlight elements (was successfully highlighted)
            if (current.highlightElements && current.highlightElements.length > 0) {
                this.log('setCurrent: updating', current.highlightElements.length, 'elements to highlight-current class');
                current.highlightElements.forEach((e, index) => {
                    this.log('setCurrent: element', index, 'BEFORE - tagName:', e.tagName, 'className:', e.className, 'isConnected:', e.isConnected);
                    e.className = 'iterm-find-highlight-current';
                    _setAttribute.call(e, 'data-iterm-id', this.instanceId);
                    this.highlighter.applyCurrentHighlightStyles(e);
                    this.log('setCurrent: element', index, 'AFTER - className:', e.className, 'data-iterm-id:', e.getAttribute('data-iterm-id'));
                });

                // Scroll into view
                this.log('setCurrent: scrolling local match into view - first element tagName:', current.highlightElements[0].tagName, 'className:', current.highlightElements[0].className);
                _scrollIntoView.call(current.highlightElements[0], {
                    behavior: '{{SCROLL_BEHAVIOR}}',
                    block: 'center',
                    inline: 'center'
                });
                this.log('setCurrent: scroll completed for local match');

                highlightingSucceeded = true;
            } else {
                this.log('setCurrent: WARNING - local match has no highlight elements, may have failed during initial highlighting');
                this.log('setCurrent: DEBUG - current.highlightElements is:', typeof current.highlightElements, current.highlightElements);
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
            graphDiscoveryEvaluateInFrame(match.frameId, script, (result) => {
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
            graphDiscoveryEvaluateInFrame(frameId, script, (result) => {
                this.log('clearCurrentInFrame: clear script completed for frame:', frameId, 'result:', result);
                resolve(result);
            });
        });
    }

    // ---------- Commands ----------

    async startFind(term, mode, contextLen) {
        this.log('=== START FIND ===');
        this.log('startFind: term=' + term + ', mode=' + mode + ', contextLen=' + contextLen + ', frame=' + (this.frameId?.substring(0, 8) || 'unknown'));
        this.log('startFind: currentSearchTerm was:', this.currentSearchTerm, 'new term:', term);
        this.log('startFind: isMainFrame:', this.isMainFrame, 'timestamp:', Date.now());

        // Clear highlights in all frames (main + iframes) before starting new search
        if (this.isMainFrame) {
            await this.clearHighlightsInAllFrames();
        } else {
            this.clearHighlights();
        }
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
            this.log('startFind: About to call highlight() - timestamp:', Date.now());
            await this.highlighter.highlight(this.matches, this.currentSearchTerm, this.segments, this);
            this.log('startFind: Highlighting completed - timestamp:', Date.now());
        } catch (e) {
            this.log('startFind: ERROR in highlighting, but continuing:', e.toString(), e);
        }

        // Set current match before reporting results to ensure consistent state
        if (this.matches.length > 0) {
            // DEBUG: Log matches before getStartingMatchIndex
            this.log('startFind: DEBUG - about to call getStartingMatchIndex with', this.matches.length, 'matches');
            this.log('startFind: DEBUG - first 10 matches before getStartingMatchIndex:');
            for (let i = 0; i < Math.min(10, this.matches.length); i++) {
                const match = this.matches[i];
                this.log(`  match ${i}: coordinates=${JSON.stringify(match.coordinates)}, text="${match.text}"`);
            }

            const startIndex = this.getStartingMatchIndex();
            this.log('startFind: Setting current match to index', startIndex);

            // Clear the flag after using click location for initial match
            this.useClickLocationForNext = false;

            // Set current match and ensure it's visible
            await this.setCurrent(startIndex);

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
            this.log('reveal: match not found for identifier', identifier, 'in:', JSON.stringify(this.matches));
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
            graphDiscoveryEvaluateInFrame(match.frameId, script, (result) => {
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
                this.clearHighlightsInAllFrames();
                this.currentSearchTerm = '';
                this.reportResults(true);
                break;
            case 'reveal':
                await this.reveal(command.identifier);
                break;
            case 'hideResults':
                this.clearHighlightsInAllFrames();
                break;
            case 'showResults':
                await this.highlighter.highlight(this.matches, this.currentSearchTerm, this.segments, this);
                break;
            case 'startNavigationShortcuts':
                await this.startNavigationShortcuts(command.selectionAction);
                break;
            case 'clearNavigationShortcuts':
                this.clearNavigationShortcuts();
                break;

            default:
                this.log('Unknown action:', command.action);
        }
        this.log('handleFindCommand returning');
        return true;
    }

    // Navigation shortcuts functions
    async startNavigationShortcuts(selectionAction = 'open') {
        if (!this.matches || this.matches.length === 0) {
            return { error: 'No matches to navigate' };
        }

        // Ensure find-nav.js is available
        if (typeof window.findNav === 'undefined') {
            this.log('find-nav.js not loaded');
            return { error: 'Navigation not available' };
        }

        // Start navigation with callback, passing instanceId for bounds calculation
        await window.findNav.startNavigation(this.segments, this.matches, this.instanceId, (text) => {
            // Callback function when shortcut is selected
            this.log('Navigation shortcut selected:', text, 'action:', selectionAction);
            
            if (selectionAction === 'open') {
                // Try to open the text as a URL
                this.openUrl(text);
            } else if (selectionAction === 'copy') {
                // Copy text to clipboard and show toast
                this.copyToClipboard(text);
            }
        });
        return true;
    }

    openUrl(text) {
        // Check if text looks like a URL
        let url = text.trim();
        
        // Add protocol if missing
        if (!/^https?:\/\//i.test(url)) {
            // Check if it looks like a domain
            if (/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/.test(url)) {
                url = 'https://' + url;
            } else {
                this.log('openUrl: text does not appear to be a URL:', text);
                this.showToast('Not a valid URL: ' + text);
                return;
            }
        }
        
        try {
            this.log('openUrl: opening URL:', url);
            window.open(url, '_blank', 'noopener,noreferrer');
        } catch (e) {
            this.log('openUrl: error opening URL:', e);
            this.showToast('Failed to open URL: ' + url);
        }
    }

    async copyToClipboard(text) {
        try {
            if (navigator.clipboard && window.isSecureContext) {
                // Use modern clipboard API
                await navigator.clipboard.writeText(text);
                this.log('copyToClipboard: copied using navigator.clipboard:', text);
            } else {
                // Fallback for older browsers or non-secure contexts
                const textArea = document.createElement('textarea');
                textArea.value = text;
                textArea.style.position = 'fixed';
                textArea.style.opacity = '0';
                document.body.appendChild(textArea);
                textArea.select();
                document.execCommand('copy');
                document.body.removeChild(textArea);
                this.log('copyToClipboard: copied using fallback method:', text);
            }
            this.showToast('Copied');
        } catch (e) {
            this.log('copyToClipboard: error copying to clipboard:', e);
            this.showToast('Failed to copy');
        }
    }

    showToast(message) {
        // Create toast element
        const toast = document.createElement('div');
        toast.textContent = message;
        toast.style.cssText = `
            position: fixed;
            top: 20px;
            left: 50%;
            transform: translateX(-50%);
            background-color: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 8px 16px;
            border-radius: 4px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            font-size: 14px;
            z-index: 10001;
            opacity: 0;
            transition: opacity 0.3s ease-in-out;
        `;
        
        document.body.appendChild(toast);
        
        // Animate in
        requestAnimationFrame(() => {
            toast.style.opacity = '1';
        });
        
        // Remove after 2 seconds
        setTimeout(() => {
            toast.style.opacity = '0';
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 300);
        }, 2000);
        
        this.log('showToast: displayed toast:', message);
    }

    clearNavigationShortcuts() {
        if (typeof window.findNav !== 'undefined') {
            window.findNav.clearNavigation();
        }
        return true;
    }


    destroy() {
        this.clearHighlights();
        document.removeEventListener('click', this.boundHandleClick, true);
        window.removeEventListener('beforeunload', this.boundHandleNavigation);
        window.removeEventListener('pagehide', this.boundHandleNavigation);
        window.removeEventListener('message', this.boundHandleMessage);
        INSTANCES.delete(this.instanceId);
    }
}

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
        console.debug("Created engine with instance id", key);
    }
    return engine;
}

