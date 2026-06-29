// Global click location - lightweight storage before any engine exists
let globalClickLocation = null;

// Lightweight global click handler - just captures raw DOM info
function handleGlobalClick(event) {
    // Use caretRangeFromPoint to get the precise click location in the DOM
    const range = _caretRangeFromPoint ? _caretRangeFromPoint(event.clientX, event.clientY) : null;
    if (range && range.startContainer.nodeType === Node.TEXT_NODE) {
        const clickData = {
            textNode: range.startContainer,
            offset: range.startOffset,
            coordinates: { x: event.clientX, y: event.clientY }
        };

        if (window === window.top) {
            // Main frame - store directly
            globalClickLocation = clickData;
        } else {
            // Iframe - notify main frame
            try {
                window.parent.postMessage({
                    type: 'iTermGlobalClick',
                    clickData: {
                        // Can't send DOM nodes across frames, so store minimal info
                        offset: range.startOffset,
                        textContent: range.startContainer.textContent,
                        coordinates: { x: event.clientX, y: event.clientY }
                    }
                }, '*');
            } catch (e) {
            }
        }
    } else if (window === window.top) {
        // Clear if click wasn't in text (only for main frame)
        globalClickLocation = null;
    }
}

// Global message handler for iframe clicks
function handleGlobalMessage(event) {
    if (window !== window.top) return; // Only main frame handles these
    if (!event.data || event.data.type !== 'iTermGlobalClick') return;


    // Store the iframe click data - we'll need to resolve it later when engine is created
    globalClickLocation = {
        type: 'iframe',
        source: event.source,
        clickData: event.data.clickData
    };
}
