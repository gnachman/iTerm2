// onMessage listener management functions

// Add a listener for onMessage events
function addListener(listener) {
    __ext_listeners.push({ "external": false, "callback": listener });
}

// Remove a listener for onMessage events
function removeListener(listener) {
    const idx = __ext_listeners.findIndex(entry =>
        entry.external === false &&
        entry.callback === listener);
    if (idx !== -1) {
        __ext_listeners.splice(idx, 1);
    }
}

// Check if a listener exists for onMessage events
function hasListener(listener) {
    return __ext_listeners.some(entry =>
        entry.external === false &&
        entry.callback === listener);
}