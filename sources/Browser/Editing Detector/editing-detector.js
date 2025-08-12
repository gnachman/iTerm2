(() => {
    try {
        console.log("[editing-detector] starting");

        const mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iTerm2EditingDetector;
        const isMainFrame = window === window.top;
        
        // Only main frame needs native message handler
        if (!isMainFrame && !mh) { 
            // Child frames don't need native handler, they'll use postMessage
        } else if (isMainFrame && !mh) { 
            return; 
        }

        const sessionSecret = '{{SECRET}}';
        const frameId = (() => {
            try {
                const a = new Uint32Array(2);
                crypto.getRandomValues(a);
                return `${Date.now().toString(36)}-${a[0].toString(36)}${a[1].toString(36)}`;
            } catch (_) {
                return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
            }
        })();

        function frameDepth() {
            let d = 0;
            let w = window;
            while (true) {
                try {
                    if (w === w.parent) { break; }
                } catch (_) {
                    // Cross-origin parent still compares by identity.
                }
                w = w.parent;
                d += 1;
            }
            return d;
        }

        let lastComputed = null;   // null | boolean
        let lastSent = null;       // null | boolean
        
        // State tracking for main frame
        const frameStates = new Map(); // frameId -> boolean
        let aggregatedState = false;

        function deepActiveElement(doc) {
            let el = (doc || document).activeElement || null;
            while (el && el.shadowRoot && el.shadowRoot.activeElement) {
                el = el.shadowRoot.activeElement;
            }
            return el;
        }

        function isTextLikeEditor(el) {
            console.log("[editing-detector] isTextLikeEditor:", el && el.tagName);
            if (!el) { return false; }
            
            // Iframe elements themselves are not editable, focus is delegated to their contents
            const tag = el.tagName ? el.tagName.toLowerCase() : "";
            if (tag === "iframe") { return false; }
            
            if (el.isContentEditable === true) { return true; }
            if (typeof el.closest === "function" && el.closest('[contenteditable],[contenteditable="true"]')) { return true; }
            if (tag === "textarea") { return true; }
            if (tag !== "input") { return false; }
            const type = (el.getAttribute("type") || "text").toLowerCase();
            switch (type) {
                case "text":
                case "search":
                case "url":
                case "tel":
                case "email":
                case "password":
                    return true;
                default:
                    return false;
            }
        }

        function computeEditable() {
            if (!document.hasFocus()) { return false; }
            if (String(document.designMode).toLowerCase() === "on") { return true; }
            if (document.body && document.body.isContentEditable === true) { return true; }
            const el = deepActiveElement(document);
            return isTextLikeEditor(el);
        }

        function postToNative(editable) {
            if (!mh) return;
            try {
                mh.postMessage({
                    sessionSecret: sessionSecret,
                    frameId: frameId,
                    depth: frameDepth(),
                    editable: editable
                });
                console.log("[editing-detector] sent editable <-", editable, "depth:", frameDepth());
            } catch (e) {
                console.error(e.toString(), e);
            }
        }

        function postToParent(editable) {
            try {
                window.parent.postMessage({
                    type: 'iterm2-editing-state',
                    frameId: frameId,
                    editable: editable,
                    sessionSecret: sessionSecret
                }, '*');
                console.log("[editing-detector] sent to parent editable <-", editable, "frameId:", frameId);
            } catch (e) {
                console.error("[editing-detector] Failed to post to parent:", e);
            }
        }

        function updateAggregatedState() {
            if (!isMainFrame) return;
            
            const newState = Array.from(frameStates.values()).some(state => state === true);
            if (newState !== aggregatedState) {
                aggregatedState = newState;
                postToNative(aggregatedState);
                lastSent = aggregatedState;
            }
        }

        function notifyIfChanged() {
            const editable = !!computeEditable();

            if (editable === lastComputed) { return; }
            lastComputed = editable;

            if (isMainFrame) {
                // Main frame: update its own state and aggregate
                frameStates.set(frameId, editable);
                updateAggregatedState();
            } else {
                // Child frame: send to parent
                if (document.hasFocus()) {
                    postToParent(editable);
                    lastSent = editable;
                }
            }
        }

        function handleFocusChange() {
            // For main frame, also check if focus moved away from all iframes
            if (isMainFrame) {
                const activeEl = document.activeElement;
                const isIframeFocused = activeEl && activeEl.tagName && activeEl.tagName.toLowerCase() === 'iframe';
                
                if (!isIframeFocused && !computeEditable()) {
                    // Focus is not in an iframe and main frame has no editable element
                    // Clear all child frame states
                    frameStates.clear();
                    frameStates.set(frameId, false);
                    updateAggregatedState();
                }
            }
            notifyIfChanged();
        }

        // Message handler for child frame updates (main frame only)
        if (isMainFrame) {
            window.addEventListener('message', (event) => {
                if (event.data && event.data.type === 'iterm2-editing-state' && 
                    event.data.sessionSecret === sessionSecret) {
                    frameStates.set(event.data.frameId, event.data.editable);
                    updateAggregatedState();
                    console.log("[editing-detector] received from child frameId:", event.data.frameId, "editable:", event.data.editable);
                    
                    // If child reports true, set up a watchdog to detect if it doesn't report false
                    if (event.data.editable) {
                        setTimeout(() => {
                            // Check if this frame is still in an editable state after a delay
                            // If main frame focus has moved elsewhere, clear child states
                            const activeEl = document.activeElement;
                            const isIframeFocused = activeEl && activeEl.tagName && activeEl.tagName.toLowerCase() === 'iframe';
                            if (!isIframeFocused && !computeEditable()) {
                                frameStates.clear();
                                frameStates.set(frameId, false);
                                updateAggregatedState();
                            }
                        }, 100);
                    }
                }
            });
        }

        document.addEventListener("focusin", handleFocusChange, true);
        document.addEventListener("focusout", handleFocusChange, true);
        document.addEventListener("selectionchange", notifyIfChanged, true);
        window.addEventListener("pageshow", notifyIfChanged, true);
        window.addEventListener("blur", handleFocusChange, true);
        window.addEventListener("pagehide", () => {
            lastComputed = false;
            if (isMainFrame) {
                frameStates.set(frameId, false);
                updateAggregatedState();
            } else {
                postToParent(false);
                lastSent = false;
            }
        }, true);

        document.addEventListener("compositionstart", notifyIfChanged, true);
        document.addEventListener("compositionend", notifyIfChanged, true);

        setTimeout(notifyIfChanged, 0);
        return true;
    } catch (e) {
        console.error("[editing-detector] Error:", e.toString(), e);
    }
})();