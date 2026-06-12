class FindHighlighter {
    constructor(logger, instanceId, frameId) {
        this.log = logger
        this.instanceId = instanceId
        this.frameId = frameId
    }

    // Apply inline styles for regular highlights (yellow)
    applyRegularHighlightStyles(element) {
        element.style.setProperty('background-color', '#FFFF00', 'important');
        element.style.setProperty('color', '#000000', 'important');
        element.style.setProperty('border-radius', '2px', 'important');
    }

    // Apply inline styles for current highlight (orange)
    applyCurrentHighlightStyles(element) {
        element.style.setProperty('background-color', '#FF9632', 'important');
        element.style.setProperty('color', '#000000', 'important');
        element.style.setProperty('border-radius', '2px', 'important');
    }

    async highlight(matches, currentSearchTerm, segments, engine) {
        this.log('highlight: ENTER - starting with', matches.length, 'matches');
        this.log('highlight: frame:', this.frameId?.substring(0, 8) || 'unknown', 'term:', currentSearchTerm, 'timestamp:', Date.now());

        // Check if we already have highlights for this term
        const existingHighlights = document.querySelectorAll(`[data-iterm-id="${this.instanceId}"]`);
        this.log('highlight: found', existingHighlights.length, 'existing highlight elements in DOM');

        // Group local matches by segment to optimize DOM rebuilding
        const localMatchesBySegment = new Map();
        const remoteMatches = [];

        for (const match of matches) {
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
                    this.highlightLocalMatch(match, segments, engine);
                    highlightedCount++;
                    this.log('highlight: successfully highlighted match ID:', match.id);
                } catch (e) {
                    this.log('highlight: ERROR highlighting match ID:', match.id, ':', e);
                }
            }

            // Rebuild segment text content after all highlighting is done
            try {
                const segment = segments[segmentIndex];
                if (segment && segment.type === 'text') {
                    this.log('highlight: rebuilding segment text content for segment', segmentIndex);
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
                    this.log('highlight: rebuilt segment text content');
                }
            } catch (e) {
                this.log('highlight: error rebuilding segment for segment', segmentIndex, ':', e);
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

        this.log('highlight: completed,', highlightedCount, 'of', matches.length, 'matches highlighted');
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
            graphDiscoveryEvaluateInFrame(match.frameId, script, resolve);
        });
    }

    highlightLocalMatch(match, segments, engine) {
        this.log('highlightLocalMatch: ENTER - match ID:', match.id, 'timestamp:', Date.now());
        this.log('highlightLocalMatch: frame:', this.frameId?.substring(0, 8) || 'unknown');

        const segmentIndex = match.coordinates[0];
        const segmentOffset = match.coordinates[1];

        const segment = segments[segmentIndex];
        if (!segment || segment.type !== 'text') {
            this.log('highlightLocalMatch: invalid segment for match');
            return;
        }

        const elements = [];
        const revealers = new Set();

        this.log('highlightLocalMatch: attempting to highlight match at coordinates', match.coordinates, 'text:', match.text.substring(0, 10) + '...');

        // Use coordinates to find text nodes directly - pass engine for consistent text node collection
        const result = findTextNodeByCoordinates(segment, segmentOffset, match.text.length, engine);

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
            this.log('highlightLocalMatch: match text length:', match.text.length, 'match text:', JSON.stringify(match.text));

            const range = _createRange();

            _Range_setStart.call(range, startNode, startOffset);
            _Range_setEnd.call(range, endNode, endOffset);

            // Log the actual range contents before highlighting
            const rangeContents = range.toString();
            this.log('highlightLocalMatch: range contents before surroundContents:', JSON.stringify(rangeContents), 'length:', rangeContents.length);

            // Create the highlight span with both class and inline styles
            const span = _createElement('span');
            span.className = 'iterm-find-highlight';
            _setAttribute.call(span, 'data-iterm-id', this.instanceId);
            this.applyRegularHighlightStyles(span);

            this.log('highlightLocalMatch: surrounding range contents with highlight span');
            _Range_surroundContents.call(range, span);

            elements.push(span);

            this.log('highlightLocalMatch: successfully highlighted match');
        } catch (e) {
            this.log('highlightLocalMatch: error highlighting match:', e.message);
            // Fallback: try character-by-character highlighting
            this.log('highlightLocalMatch: attempting fallback character-by-character highlighting');

            for (let i = 0; i < match.text.length; i++) {
                const charResult = findTextNodeByCoordinates(segment, segmentOffset + i, 1, engine);
                if (charResult) {
                    try {
                        const range = _createRange();
                        _Range_setStart.call(range, charResult.startNode, charResult.startOffset);
                        _Range_setEnd.call(range, charResult.endNode, charResult.endOffset);

                        const span = _createElement('span');
                        span.className = 'iterm-find-highlight';
                        _setAttribute.call(span, 'data-iterm-id', this.instanceId);
                        this.applyRegularHighlightStyles(span);

                        _Range_surroundContents.call(range, span);
                        elements.push(span);
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

        this.log('highlightLocalMatch: created match with', elements.length, 'highlightElements for match', match.id);
        this.log('highlightLocalMatch: first element details - tagName:', elements[0]?.tagName, 'className:', elements[0]?.className, 'isConnected:', elements[0]?.isConnected);
    }

    highlightCurrentMatch(match) {
        // Set this as current
        if (match.highlightElements && match.highlightElements.length > 0) {
            this.log('highlightCurrentMatch: updating', match.highlightElements.length, 'elements to current');
            match.highlightElements.forEach(e => {
                e.className = 'iterm-find-highlight-current';
                this.applyCurrentHighlightStyles(e);
            });

            // Scroll into view
            this.log('highlightCurrentMatch: scrolling first highlight element into view');
            _scrollIntoView.call(match.highlightElements[0], {
                behavior: 'smooth',
                block: 'center',
                inline: 'center'
            });
        } else {
            this.log('highlightCurrentMatch: WARNING - no highlight elements to update for match ID:', match.id, {
                highlightElementsUndefined: match.highlightElements === undefined,
                highlightElementsNull: match.highlightElements === null,
                highlightElementsLength: match.highlightElements ? match.highlightElements.length : 'N/A',
                highlightElementsType: typeof match.highlightElements
            });
        }
    }

    unhighlightCurrentMatch(matches) {
        let clearedCount = 0;
        for (const match of matches) {
            if (match.type === 'local' && match.highlightElements) {
                match.highlightElements.forEach(e => {
                    if (e.className === 'iterm-find-highlight-current') {
                        e.className = 'iterm-find-highlight';
                        this.applyRegularHighlightStyles(e);
                        clearedCount++;
                    }
                });
            }
        }
        this.log('unhighlightCurrentMatch: cleared', clearedCount, 'highlight elements in iframe');
    }
}
