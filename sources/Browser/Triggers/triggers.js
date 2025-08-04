;(function() {
    'use strict';

    const TAG = 'iTerm2Triggers';
    const sessionSecret = "{{SECRET}}";
    // This is a dictionary from string to Trigger Dictionary, which has keys defined in
    // Trigger.m (e.g., kTriggerRegexKey)
    let triggers = {};
    // Map from trigger identifier to compiled regex
    let compiledRegexes = {};
    // Map from trigger identifier to compiled content regex (lazy-loaded)
    let compiledContentRegexes = {};
    // Map from match ID to match data (for public API)
    let storedMatches = {};
    // Counter for generating unique match IDs
    let matchIdCounter = 0;

    console.debug(TAG, 'Initializing...');

    const _messageHandler = window.webkit?.messageHandlers?.iTerm2Trigger;
    const _postMessage = _messageHandler?.postMessage?.bind(_messageHandler);

    // Request triggers from the host on startup
    function requestTriggers() {
        if (!_postMessage) {
            console.error(TAG, 'Message handler unavailable for requesting triggers');
            return;
        }

        console.debug(TAG, 'Requesting triggers from host');
        try {
            _postMessage({
                sessionSecret: sessionSecret,
                requestTriggers: true
            });
        } catch (error) {
            console.error(TAG, 'Failed to request triggers:', error.toString());
        }
    }

    // Eagerly compile URL regexes for both URL triggers (matchType 1) and page content triggers (matchType 2)
    function compileTriggersRegexes(triggerDict) {
        console.debug(TAG, 'Compiling URL regexes for', Object.keys(triggerDict).length, 'triggers');
        const newCompiledRegexes = {};

        for (const [identifier, trigger] of Object.entries(triggerDict)) {
            const matchType = trigger.matchType || 0;

            // Eagerly compile URL regex for both URL triggers (matchType 1) and page content triggers (matchType 2)
            if (matchType === 1 || matchType === 2) {
                const regex = trigger.regex;
                if (!regex) {
                    continue;
                }

                try {
                    newCompiledRegexes[identifier] = new RegExp(regex);
                } catch (error) {
                    console.error(TAG, 'Invalid URL regex pattern for', identifier, ':', regex, error.toString());
                }
            }
        }
        return newCompiledRegexes;
    }

    // Lazy compilation of content regex for page content triggers
    function getCompiledContentRegex(identifier, trigger) {
        if (compiledContentRegexes[identifier]) {
            return compiledContentRegexes[identifier];
        }

        const contentRegex = trigger.contentregex;
        if (!contentRegex) {
            return null;
        }

        try {
            const compiled = new RegExp(contentRegex);
            compiledContentRegexes[identifier] = compiled;
            return compiled;
        } catch (error) {
            console.error(TAG, 'Invalid content regex pattern for', identifier, ':', contentRegex, error.toString());
            // Cache the error so we don't try again
            compiledContentRegexes[identifier] = null;
            return null;
        }
    }

    function setTriggers(command) {
        try {
            console.debug(TAG, 'setTriggers called');
            const validated = validateCommand(command);
            if (!validated) {
                console.error(TAG, 'Invalid command');
                return;
            }
            triggers = command.triggers;
            compiledRegexes = compileTriggersRegexes(triggers);
            // Clear cached content regexes since triggers have changed
            compiledContentRegexes = {};

            // Check current URL against new triggers
            checkTriggers();
        } catch(e) {
            console.error(e.toString());
            console.error(e);
            throw e;
        }
    }

    function validateSessionSecret(secret) {
        return secret === sessionSecret;
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
        return command
    }

    // Block elements that create line breaks
    const BLOCK_ELEMENTS = new Set([
        'P', 'DIV', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6',
        'LI', 'TR', 'BR', 'HR', 'BLOCKQUOTE', 'ADDRESS',
        'ARTICLE', 'ASIDE', 'FOOTER', 'HEADER', 'MAIN',
        'NAV', 'SECTION', 'PRE', 'TABLE', 'DD', 'DT'
    ]);

    // Build searchable text representation while tracking node positions
    function buildTextWithNodeMap() {
        let fullText = "";
        const nodeMap = []; // Maps character positions to nodes
        
        function walkNodes(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const startPos = fullText.length;
                fullText += node.textContent;
                nodeMap.push({
                    node: node,
                    start: startPos,
                    end: fullText.length
                });
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                const tagName = node.tagName?.toUpperCase();
                
                // Skip invisible elements
                const style = window.getComputedStyle(node);
                if (style.display === 'none' || style.visibility === 'hidden') {
                    return;
                }
                
                // Add newline before block elements (except at the very beginning)
                if (BLOCK_ELEMENTS.has(tagName) && fullText.length > 0 && !fullText.endsWith('\n')) {
                    fullText += '\n';
                }
                
                // Process children
                for (const child of node.childNodes) {
                    walkNodes(child);
                }
                
                // Add newline after block elements
                if (BLOCK_ELEMENTS.has(tagName) && !fullText.endsWith('\n')) {
                    fullText += '\n';
                }
            }
        }
        
        if (document.body) {
            walkNodes(document.body);
        }
        
        return { fullText, nodeMap };
    }

    // Create a Range object from position in the built text
    function createRangeFromPosition(startPos, length, nodeMap) {
        const endPos = startPos + length;
        let startNode, startOffset, endNode, endOffset;
        
        // Find which nodes contain the start and end positions
        for (const entry of nodeMap) {
            if (startPos >= entry.start && startPos < entry.end) {
                startNode = entry.node;
                startOffset = startPos - entry.start;
            }
            if (endPos > entry.start && endPos <= entry.end) {
                endNode = entry.node;
                endOffset = endPos - entry.start;
            }
        }
        
        // If the match spans multiple nodes, we need to handle it differently
        if (startNode && endNode) {
            try {
                const range = document.createRange();
                range.setStart(startNode, startOffset);
                range.setEnd(endNode, endOffset);
                return range;
            } catch (e) {
                console.error(TAG, 'Failed to create range:', e);
                return null;
            }
        }
        
        return null;
    }

    // Generate a unique match ID
    function generateMatchId() {
        return `match_${++matchIdCounter}`;
    }

    // Public API: Get match data by ID
    function getMatchById(matchId) {
        return storedMatches[matchId] || null;
    }

    // Store match data for later retrieval
    function storeMatch(matchId, matchData) {
        storedMatches[matchId] = matchData;
    }

    // Check URL and page content against triggers and post matches
    function checkTriggers() {
        console.debug(TAG, 'checkTriggers called, current URL:', window.location.href);

        if (!_postMessage) {
            console.error(TAG, 'Message handler unavailable');
            return;
        }

        const currentURL = window.location.href;
        const matches = [];

        // Check each compiled regex
        for (const [identifier, regex] of Object.entries(compiledRegexes)) {
            const trigger = triggers[identifier];
            if (!trigger) {
                continue;
            }

            const matchType = trigger.matchType || 0;
            const urlMatch = currentURL.match(regex);

            if (urlMatch) {
                if (matchType === 1) {
                    // URL regex trigger - URL match is sufficient
                    matches.push({
                        matchType: 'urlRegex',
                        urlCaptures: Array.from(urlMatch),
                        identifier: identifier
                    });
                } else if (matchType === 2) {
                    // Page content trigger - URL matched, now check content
                    const contentRegex = getCompiledContentRegex(identifier, trigger);
                    if (contentRegex) {
                        // Build text representation with node mapping
                        const { fullText, nodeMap } = buildTextWithNodeMap();
                        
                        // Find ALL content matches, not just the first one
                        const globalContentRegex = new RegExp(contentRegex.source, contentRegex.flags.includes('g') ? contentRegex.flags : contentRegex.flags + 'g');
                        let contentMatch;
                        
                        console.debug(TAG, 'Testing content regex for', identifier, 'in text of length:', fullText.length);

                        while ((contentMatch = globalContentRegex.exec(fullText)) !== null) {
                            const matchId = generateMatchId();
                            const matchText = contentMatch[0];
                            const matchIndex = contentMatch.index;
                            
                            // Create Range for this match
                            const range = createRangeFromPosition(matchIndex, matchText.length, nodeMap);
                            
                            if (range) {
                                console.debug(TAG, 'Content match found:', matchText, 'at index', matchIndex);
                                
                                const matchData = {
                                    matchType: 'pageContent',
                                    urlCaptures: Array.from(urlMatch),
                                    contentCaptures: Array.from(contentMatch),
                                    identifier: identifier,
                                    matchText: matchText,
                                    range: range  // Store the Range object instead of index
                                };
                                
                                // Store the match data for later retrieval
                                storeMatch(matchId, matchData);
                                
                                matches.push({
                                    matchType: 'pageContent',
                                    urlCaptures: Array.from(urlMatch),
                                    contentCaptures: Array.from(contentMatch),
                                    identifier: identifier,
                                    matchID: matchId
                                });
                            } else {
                                console.warn(TAG, 'Failed to create range for match at index:', matchIndex);
                            }
                            
                            // Prevent infinite loop for zero-length matches
                            if (contentMatch.index === globalContentRegex.lastIndex) {
                                globalContentRegex.lastIndex++;
                            }
                        }
                    }
                }
            }
        }

        console.debug(TAG, 'Found', matches.length, 'matches');

        // If we found matches, post them
        if (matches.length > 0) {
            const matchEvent = {
                matches: matches
            };

            try {
                _postMessage({
                    sessionSecret: sessionSecret,
                    matchEvent: JSON.stringify(matchEvent)
                });
            } catch (error) {
                console.error(TAG, 'Failed to post message:', error.toString());
            }
        }
    }

    // Listen for document ready and URL changes
    function setupTriggerListeners() {
        console.debug(TAG, 'Setting up trigger listeners');

        // Check triggers when document loads (for every page load)
        document.addEventListener('DOMContentLoaded', () => {
            checkTriggers();
        });

        // Listen for popstate events (back/forward navigation)
        window.addEventListener('popstate', () => {
            checkTriggers();
        });

        // Listen for pushstate/replacestate (modern SPA navigation)
        const originalPushState = history.pushState;
        const originalReplaceState = history.replaceState;

        history.pushState = function(...args) {
            originalPushState.apply(this, args);
            setTimeout(checkTriggers, 0); // Async to let URL update
        };

        history.replaceState = function(...args) {
            originalReplaceState.apply(this, args);
            setTimeout(checkTriggers, 0); // Async to let URL update
        };
    }

    // Initialize trigger checking
    setupTriggerListeners();

    // Request triggers from the host
    requestTriggers();

    const api = {
        setTriggers,
        getMatchById,
        // Expose the stored matches for debugging
        _storedMatches: storedMatches
    };

    // Include additional trigger functionality
    {{INCLUDE:trigger-highlight-text.js}}
    {{INCLUDE:trigger-make-hyperlink.js}}

    Object.freeze(api);
    Object.freeze(api.setTriggers);

    Object.defineProperty(window, TAG, {
        value: api,
        writable: false,
        configurable: false,
        enumerable: true
    });
    true;
})();

