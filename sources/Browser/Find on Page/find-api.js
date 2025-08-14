async function handleCommand(command) {
    const validated = validateCommand(command);
    if (!validated) {
        console.error(TAG, 'Invalid command');
        return false;
    }

    const engine = getEngine(validated.instanceId);
    if (!engine) {
        console.error(TAG, 'Could not create engine');
        return false;
    }

    let result = await engine.handleFindCommand(validated);
    return result;
}

function clearStateWithoutResponse(command) {
    console.debug(TAG, "clearStateWithoutResponse");
    if (!validateSessionSecret(command?.sessionSecret)) {
        console.error(TAG, 'Invalid session secret for clearStateWithoutResponse');
        return { error: 'Unauthorized' };
    }

    const id = sanitizeInstanceId(command.instanceId);
    const engine = INSTANCES.get(id);
    if (!engine) {
        console.debug(TAG, 'clearStateWithoutResponse: No engine found for id:', id);
        return { error: 'No engine found' };
    }

    // Clear search state without sending response to Swift
    // Note: We preserve click location as it represents user intent about where to search from
    engine.log('clearStateWithoutResponse: clearing highlights for engine');
    engine.clearHighlights();
    engine.currentSearchTerm = '';

    return { cleared: true };
}

async function getMatchBoundsInEngine(command) {
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
            index: validateNumber(command.identifier.index, 0, Number.MAX_SAFE_INTEGER, 0),
            coordinates: Array.isArray(command.identifier.coordinates) ? 
                command.identifier.coordinates.slice(0, 10).map(n => validateNumber(n, 0, Number.MAX_SAFE_INTEGER, 0)) : [],
            text: sanitizeString(command.identifier.text, 100)
        };
    }

    let result = await engine.getMatchBounds(identifier)
    engine.log(`getMatchBoundsInEngine: return`, result);
    return result;
}

// Helper functions for iframe highlighting and navigation
function highlightMatches(instanceId) {
    console.debug('highlightMatches: called with instanceId:', instanceId);
    const engine = getEngine(instanceId);
    if (!engine) {
        console.debug('highlightMatches: no engine found for instanceId:', instanceId);
        return;
    }
    if (!engine.matches) {
        console.debug('highlightMatches: engine has no matches');
        return;
    }
    
    console.debug('highlightMatches: engine has', engine.matches.length, 'matches and', engine.segments.length, 'segments');
    for (let i = 0; i < engine.segments.length; i++) {
        const segment = engine.segments[i];
        if (segment.type === 'text') {
            console.debug('highlightMatches: segment', i, 'has', segment.textContent.length, 'chars:', segment.textContent.substring(0, 50) + '...');
        }
    }
    
    for (const match of engine.matches) {
        if (match.type === 'local') {
            console.debug('highlightMatches: highlighting match at coordinates', match.coordinates, 'text:', match.text.substring(0, 20));
            engine.highlighter.highlightLocalMatch(match, engine.segments, engine);
        }
    }
}

function highlightRemoteMatch(index, instanceId) {
    const engine = getEngine(instanceId);
    if (!engine) {
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
            engine.highlighter.unhighlightCurrentMatch(engine.matches);
            engine.highlighter.highlightCurrentMatch(match);
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
        return;
    }

    engine.log('clearCurrentHighlight: clearing current highlights in iframe');

    if (engine.matches) {
        engine.highlighter.unhighlightCurrentMatch(engine.matches)
    } else {
        engine.log('clearCurrentHighlight: no matches to clear');
    }
}

function getRemoteMatchBounds(index, instanceId) {
    const engine = getEngine(instanceId);
    if (!engine) {
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

    // Get click location without setting it in the iframe (main frame will handle the converted coordinates)
    const result = engine.handleTextSegmentClickInternal(x, y);
    engine.log('handleClickInFrame: click handling completed with result:', result);

    // Don't set click location in iframe - let main frame handle the global coordinates
    // The main frame will convert the returned coordinates and set its own click location
    return result;
}

// Helper function for frames to search their own content when called by evaluateInAll
function searchInFrame(params) {
    const { searchTerm, searchMode, contextLength, instanceId } = params;

    // Use the passed instance ID to get the correct engine
    const engine = getEngine(instanceId);
    if (!engine) {
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
    getMatchBoundsInEngine,

    // For internal cross-iframe use
    clearStateWithoutResponse,
    searchInFrame,
    highlightMatches,
    highlightRemoteMatch,
    clearCurrentHighlight,
    getRemoteMatchBounds,
    handleClickInFrame,

    getEngine
};

// Freeze the API object and all its methods
Object.freeze(api);
Object.freeze(api.handleCommand);
Object.freeze(api.getMatchBoundsInEngine);
Object.freeze(api.clearStateWithoutResponse);
Object.freeze(api.searchInFrame);
Object.freeze(api.highlightMatches);
Object.freeze(api.highlightRemoteMatch);
Object.freeze(api.clearCurrentHighlight);
Object.freeze(api.getRemoteMatchBounds);
Object.freeze(api.handleClickInFrame);

// Use Object.defineProperty to make it non-configurable and non-writable
Object.defineProperty(window, 'iTermCustomFind', {
    value: api,
    writable: false,
    configurable: false,
    enumerable: true
});
