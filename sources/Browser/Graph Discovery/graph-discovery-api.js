const DISCOVERY_SYMBOL = Symbol.for('iTermGraphDiscovery');

function graphDiscoveryDiscover(callback) {
    const discovery = window[DISCOVERY_SYMBOL];
    if (!discovery) {
        throw new Error('Graph discovery not initialized. Ensure graph-discovery.js is loaded first.');
    }
    discovery.discover(callback);
}

function graphDiscoveryEvaluateInAll(javascript, callback, timeout) {
    const discovery = window[DISCOVERY_SYMBOL];
    if (!discovery) {
        throw new Error('Graph discovery not initialized. Ensure graph-discovery.js is loaded first.');
    }
    discovery.evaluateInAll(javascript, callback, timeout);
}

function graphDiscoveryEvaluateInFrame(frameId, javascript, callback, timeout) {
    const discovery = window[DISCOVERY_SYMBOL];
    if (!discovery) {
        throw new Error('Graph discovery not initialized. Ensure graph-discovery.js is loaded first.');
    }
    discovery.evaluateInFrame(frameId, javascript, callback, timeout);
}

function graphDiscoveryGetFrameId() {
    const discovery = window[DISCOVERY_SYMBOL];
    if (!discovery) {
        throw new Error('Graph discovery not initialized. Ensure graph-discovery.js is loaded first.');
    }
    return discovery.frameId;
}
