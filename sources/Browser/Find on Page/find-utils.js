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

// Find text node and offset by walking the DOM directly using coordinates
function findTextNodeByCoordinates(segment, targetOffset, matchLength) {
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

