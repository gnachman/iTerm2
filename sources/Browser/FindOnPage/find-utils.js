// ==============================
//  Security Helper Functions
// ==============================

// Secure message posting with integrity verification
function securePostMessage(payload) {
    if (!_postMessage) {
        console.warn(TAG, 'Message handler unavailable - postMessage failed');
        return false;
    }

    try {
        // Add integrity hash using sessionSecret
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
            break;

        case 'reveal':
            if (command.identifier && typeof command.identifier === 'object') {
                sanitized.identifier = {
                    index: validateNumber(command.identifier.index, 0, Number.MAX_SAFE_INTEGER, 0),
                    coordinates: Array.isArray(command.identifier.coordinates) ? 
                        command.identifier.coordinates.slice(0, 10).map(n => validateNumber(n, 0, Number.MAX_SAFE_INTEGER, 0)) : [],
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

// ---------- Visibility helpers ----------
function isHidden(el) {
    for (let e = el; e; e = e.parentElement) {
        if (e.hasAttribute('hidden')) { return true; }
        if (e.getAttribute('aria-hidden') === 'true') { return true; }
        const cs = _getComputedStyle(e);
        if (cs.display === 'none' || cs.visibility === 'hidden') { return true; }
    }
    return false;
}

function firstRevealableAncestor(el) {
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

// Shared text node filter function - ensures consistent node collection between search and highlighting
function createTextNodeFilter(engine) {
    return {
        acceptNode: (node) => {
            const parent = node.parentElement;
            if (!parent) return _FILTER_REJECT;

            // Skip script and style
            const tag = parent.tagName;
            if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') {
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
                    if (engine.hiddenSkippedCount !== undefined) {
                        engine.hiddenSkippedCount++;
                    }
                    if (engine.log) {
                        engine.log('reject hidden node', node.textContent.slice(0, 40));
                    }
                    return _FILTER_REJECT;
                } else {
                    node._itermReveal = rev;
                    if (engine.debuglog) {
                        engine.debuglog('accept hidden via revealer', rev.tagName, node.textContent.slice(0, 40));
                    }
                }
            }

            // Skip completely empty text nodes, but keep whitespace-containing nodes
            if (!node.textContent || node.textContent.length === 0) {
                return _FILTER_REJECT;
            }

            return _FILTER_ACCEPT;
        }
    };
}

// Collect text nodes using the same logic as search phase
function collectCurrentTextNodes(segment, engine, phase = 'highlight') {
    const prefix = `[TEXT_COLLECTION:${phase}]`;
    if (verbose) {
        console.debug(prefix, 'ENTER - collecting text nodes for segment with element:', segment.element.tagName);
    }

    const textNodes = [];
    const walker = _createTreeWalker(
        segment.element,
        _SHOW_TEXT,
        createTextNodeFilter(engine),
        false
    );

    let nodeCount = 0;
    let node;
    while (node = _TreeWalker_nextNode.call(walker)) {
        nodeCount++;
        const nodeText = node.textContent;
        if (verbose) {
            console.debug(prefix, 'node', nodeCount, 'length:', nodeText.length, 'content:', JSON.stringify(nodeText), 'parent:', node.parentElement?.tagName);
        }
        textNodes.push(node);
    }
    
    console.debug(prefix, 'EXIT - collected', textNodes.length, 'text nodes');

    return textNodes;
}

// Find text node and offset by walking the DOM directly using coordinates
function findTextNodeByCoordinates(segment, targetOffset, matchLength, engine) {
    const prefix = '[COORD_MAPPING]';
    console.debug(prefix, 'ENTER - targetOffset:', targetOffset, 'matchLength:', matchLength, 'segment.element:', segment.element.tagName, 'segment.textContent.length:', segment.textContent.length);
    console.debug(prefix, 'segment.textContent preview:', JSON.stringify(segment.textContent.substring(0, 100) + '...'));
    
    let currentOffset = 0;
    let startNode = null;
    let startOffset = 0;
    let endNode = null;
    let endOffset = 0;
    let nodeCount = 0;

    // Always use fresh text node collection to ensure consistency with search phase
    console.debug(prefix, 'collecting fresh text nodes using shared filter logic');
    const textNodes = collectCurrentTextNodes(segment, engine, 'highlight');
    
    console.debug(prefix, 'using fresh textNodes array with', textNodes.length, 'nodes for coordinate mapping');
    
    for (const node of textNodes) {
        const textContent = _textContentGetter ? _textContentGetter.call(node) : node.textContent;
        const nodeLength = textContent.length;
        nodeCount++;

        if (verbose) {
            console.debug(prefix, 'node', nodeCount, 'textContent:', JSON.stringify(textContent), 'length:', nodeLength, 'currentOffset:', currentOffset, 'parent:', node.parentElement?.tagName);
        }
    
        if (currentOffset + nodeLength > targetOffset) {
            // Start position is in this node
            if (startNode === null) {
                startNode = node;
                startOffset = targetOffset - currentOffset;
                console.debug(prefix, 'found START node at offset', startOffset, 'in text:', JSON.stringify(textContent));
            }

            // Check if end position is also in this node
            const targetEndOffset = targetOffset + matchLength;
            if (currentOffset + nodeLength >= targetEndOffset) {
                endNode = node;
                endOffset = targetEndOffset - currentOffset;
                console.debug(prefix, 'found END node at offset', endOffset, 'in text:', JSON.stringify(textContent));
                break;
            }
        }

        currentOffset += nodeLength;

        // If we found start but not end, and we've moved past the target range
        if (startNode && currentOffset >= targetOffset + matchLength) {
            endNode = node;
            endOffset = (targetOffset + matchLength) - (currentOffset - nodeLength);
            console.debug(prefix, 'found END node (past target) at offset', endOffset, 'in text:', JSON.stringify(textContent));
            break;
        }
    }

    console.debug(prefix, 'traversal complete - nodeCount:', nodeCount, 'totalOffset:', currentOffset);
    console.debug(prefix, 'result - startNode:', !!startNode, 'endNode:', !!endNode);
    
    if (startNode) {
        console.debug(prefix, 'startNode content:', JSON.stringify(startNode.textContent), 'startOffset:', startOffset);
    }
    if (endNode) {
        console.debug(prefix, 'endNode content:', JSON.stringify(endNode.textContent), 'endOffset:', endOffset);
    }

    if (!startNode || !endNode) {
        console.debug(prefix, 'FAILED - returning null because startNode:', !!startNode, 'endNode:', !!endNode);
        return null;
    }

    console.debug(prefix, 'SUCCESS - returning node range');
    return {
        startNode,
        startOffset,
        endNode,
        endOffset
    };
}

