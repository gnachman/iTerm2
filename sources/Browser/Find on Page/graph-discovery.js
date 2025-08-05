// iframe Graph Discovery Script for WKWebView
// This script is injected into all frames and discovers the complete iframe hierarchy

(function() {
    'use strict';


    // Use symbols to avoid global namespace pollution
    const DISCOVERY_SYMBOL = Symbol.for('iTermGraphDiscovery');
    const START_DISCOVERY_SYMBOL = Symbol.for('startIframeDiscovery');
    
    // Check if already initialized in this frame
    if (window[DISCOVERY_SYMBOL]) {
        return;
    }

    // Configuration
    const CONFIG = {
        DISCOVERY_TIMEOUT: 2000, // ms to wait for child responses
        MESSAGE_NAMESPACE: 'IFRAME_GRAPH_DISCOVERY',
        NATIVE_HANDLER: 'iTermGraphDiscovery' // webkit message handler name
    };
    
    // Register the message handler early (if in WKWebView)
    if (window.webkit && window.webkit.messageHandlers) {
    } else {
    }

    // Message types
    const MessageType = {
        INIT: 'DISCOVERY_INIT',
        CHILD_RESPONSE: 'CHILD_RESPONSE',
        DOM_CHANGED: 'DOM_CHANGED',
        EVAL_REQUEST: 'EVAL_REQUEST',
        EVAL_RESPONSE: 'EVAL_RESPONSE'
    };

    class FrameDiscovery {
        constructor() {
            this.frameId = this.generateFrameId();
            this.isMainFrame = (window === window.top);
            this.childResponseMap = new Map(); // Maps expected child frameIds to iframe elements
            this.childFrames = new Map(); // Maps iframe elements to their responses
            this.pendingResponses = new Set();
            this.responseTimeout = null;
            this.currentRequestId = null;
            this.discoveryCallback = null;
            this.messageListener = null;
            this.mutationObserver = null;
            this.rediscoveryTimer = null;
            this.lastDiscoveryTime = 0; // Using performance.now() for monotonic time
            
            // JavaScript evaluation system
            this.pendingEvaluations = new Map(); // requestId -> { callback, timeout, frameIds }
            this.evaluationResponses = new Map(); // requestId -> { responses, expectedCount }
            this.currentGraph = null; // Cache the current graph
            
            // Discovery queue system
            this.discoveryInProgress = false;
            this.discoveryQueue = []; // Queue of callbacks waiting for discovery
            
            this.log(`Initialized FrameDiscovery. isMainFrame: ${this.isMainFrame}, URL: ${window.location.href}`);
            
            this.setupMessageListener();
            this.setupMutationObserver();
            
            // Expose to window for native app to call (using symbol to avoid pollution)
            if (this.isMainFrame) {
                window[START_DISCOVERY_SYMBOL] = () => this.startDiscovery();
                // Also expose with regular name for native bridge
                window.startIframeDiscovery = () => this.startDiscovery();
                this.log('Exposed startIframeDiscovery() on main frame');
                
                // Expose the iframe graph API
                this.setupIframeGraphAPI();
            }
        }

        log(message) {
            console.debug(`[IFD:${this.frameId.substring(0, 8)}] ${message}`);
        }

        generateFrameId() {
            const array = new Uint8Array(16);
            crypto.getRandomValues(array);
            return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
        }

        setupMessageListener() {
            this.messageListener = (event) => {
                // Only handle our protocol messages
                if (!event.data || typeof event.data !== 'object') return;
                if (!event.data.namespace || event.data.namespace !== CONFIG.MESSAGE_NAMESPACE) return;

                this.log(`Received message: type=${event.data.type}, requestId=${event.data.requestId}, from=${event.origin}`);
                this.handleMessage(event);
            };
            
            window.addEventListener('message', this.messageListener);
            this.log('Message listener setup complete');
        }

        setupMutationObserver() {
            // Wait for DOM to be ready before setting up observer
            const startObserver = () => {
                if (this.mutationObserver) return; // Already setup
                
                // Watch for iframe additions/removals
                this.mutationObserver = new MutationObserver((mutations) => {
                    let iframeChanged = false;
                    
                    for (const mutation of mutations) {
                        // Check added nodes
                        for (const node of mutation.addedNodes) {
                            if (node.nodeName === 'IFRAME' || 
                                (node.querySelectorAll && node.querySelectorAll('iframe').length > 0)) {
                                iframeChanged = true;
                                this.log(`Detected iframe addition`);
                                break;
                            }
                        }
                        
                        // Check removed nodes
                        for (const node of mutation.removedNodes) {
                            if (node.nodeName === 'IFRAME' || 
                                (node.querySelectorAll && node.querySelectorAll('iframe').length > 0)) {
                                iframeChanged = true;
                                this.log(`Detected iframe removal`);
                                break;
                            }
                        }
                        
                        if (iframeChanged) break;
                    }
                    
                    if (iframeChanged) {
                        this.handleDOMChange();
                    }
                });
                
                // Start observing
                const target = document.body || document.documentElement;
                if (target) {
                    this.mutationObserver.observe(target, {
                        childList: true,
                        subtree: true
                    });
                    this.log('MutationObserver setup complete');
                }
            };
            
            // Setup observer when DOM is ready
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', startObserver);
            } else {
                startObserver();
            }
        }

        handleDOMChange() {
            if (this.isMainFrame) {
                // Main frame: debounce and restart discovery
                this.scheduleRediscovery();
            } else {
                // Child frame: notify parent about the change
                this.log('Notifying parent about DOM change');
                if (window.parent && window.parent !== window) {
                    this.sendMessage(window.parent, MessageType.DOM_CHANGED, {
                        frameId: this.frameId
                    });
                }
            }
        }

        scheduleRediscovery() {
            // Debounce: clear existing timer
            if (this.rediscoveryTimer) {
                clearTimeout(this.rediscoveryTimer);
            }
            
            // Schedule new discovery after a short delay
            this.rediscoveryTimer = setTimeout(() => {
                const now = performance.now();
                // Prevent discovery storms - minimum 500ms between discoveries
                if (now - this.lastDiscoveryTime > 500) {
                    this.log('DOM changed - restarting discovery');
                    this.lastDiscoveryTime = now;
                    this.startDiscovery();
                } else {
                    this.log('Skipping rediscovery - too soon after last discovery');
                }
            }, 100); // 100ms debounce
        }

        cleanup() {
            this.log('Cleaning up FrameDiscovery');
            if (this.messageListener) {
                window.removeEventListener('message', this.messageListener);
                this.messageListener = null;
                this.log('Removed message listener');
            }
            if (this.responseTimeout) {
                clearTimeout(this.responseTimeout);
                this.responseTimeout = null;
                this.log('Cleared response timeout');
            }
            if (this.rediscoveryTimer) {
                clearTimeout(this.rediscoveryTimer);
                this.rediscoveryTimer = null;
                this.log('Cleared rediscovery timer');
            }
            if (this.mutationObserver) {
                this.mutationObserver.disconnect();
                this.mutationObserver = null;
                this.log('Disconnected mutation observer');
            }
            
            // Clear evaluation timeouts
            for (const [requestId, request] of this.pendingEvaluations) {
                if (request.timeout) {
                    clearTimeout(request.timeout);
                }
            }
            this.pendingEvaluations.clear();
            this.evaluationResponses.clear();
            
            // Clear discovery queue
            this.discoveryQueue = [];
            this.discoveryInProgress = false;
        }

        handleMessage(event) {
            const { type, payload, requestId } = event.data;

            switch (type) {
                case MessageType.INIT:
                    this.log(`Handling DISCOVERY_INIT from parent`);
                    this.handleDiscoveryInit(event, payload, requestId);
                    break;
                case MessageType.CHILD_RESPONSE:
                    this.log(`Handling CHILD_RESPONSE`);
                    this.handleChildResponse(event, payload, requestId);
                    break;
                case MessageType.DOM_CHANGED:
                    this.log(`Handling DOM_CHANGED from child`);
                    this.handleChildDOMChanged(event, payload);
                    break;
                case MessageType.EVAL_REQUEST:
                    this.log(`Handling EVAL_REQUEST`);
                    this.handleEvaluationRequest(event, payload, requestId);
                    break;
                case MessageType.EVAL_RESPONSE:
                    this.log(`Handling EVAL_RESPONSE`);
                    this.handleEvaluationResponse(event, payload, requestId);
                    break;
                default:
                    this.log(`Unknown message type: ${type}`);
            }
        }

        handleChildDOMChanged(event, payload) {
            // A child frame detected a DOM change
            if (payload && payload.frameId) {
                this.log(`Child frame ${payload.frameId} reported DOM change`);
            }
            
            // Propagate up or trigger rediscovery
            if (this.isMainFrame) {
                // We're the main frame - restart discovery
                this.scheduleRediscovery();
            } else {
                // We're an intermediate frame - pass the message up
                if (window.parent && window.parent !== window) {
                    this.log('Propagating DOM change notification to parent');
                    this.sendMessage(window.parent, MessageType.DOM_CHANGED, {
                        frameId: this.frameId,
                        originalFrameId: payload ? payload.frameId : null
                    });
                }
            }
        }

        handleDiscoveryInit(event, payload, requestId) {
            // Don't respond to our own messages or messages without a source
            if (!event.source || event.source === window) {
                this.log('Ignoring INIT message (source is self or missing)');
                return;
            }
            
            // Extract tracking ID if provided (for cross-origin identification)
            const trackingId = payload ? payload.trackingId : null;
            this.log(`Processing INIT with trackingId=${trackingId}, requestId=${requestId}`);
            
            // Start discovering our children
            this.discoverChildren((subtree) => {
                // Include tracking ID in response for cross-origin identification
                if (trackingId) {
                    subtree.trackingId = trackingId;
                }
                
                this.log(`Sending CHILD_RESPONSE back to parent with ${subtree.children ? subtree.children.length : 0} children`);
                // Send our complete subtree back to parent with the same requestId
                this.sendMessage(event.source, MessageType.CHILD_RESPONSE, subtree, requestId);
            });
        }

        handleChildResponse(event, subtree, requestId) {
            // Validate this response is for our current discovery session
            if (requestId !== this.currentRequestId) {
                this.log(`Ignoring CHILD_RESPONSE with mismatched requestId. Expected: ${this.currentRequestId}, Got: ${requestId}`);
                return; // Ignore stale or rogue responses
            }
            
            this.log(`Processing CHILD_RESPONSE with frameId=${subtree?.frameId}, trackingId=${subtree?.trackingId}`);
            
            // Find which iframe this response came from by checking source
            const iframes = Array.from(document.querySelectorAll('iframe'));
            let matchedIframe = null;
            
            for (const iframe of iframes) {
                if (iframe.contentWindow === event.source) {
                    matchedIframe = iframe;
                    this.log(`Matched iframe by contentWindow comparison`);
                    break;
                }
            }
            
            // If we couldn't match by source (cross-origin),
            // use the tracking ID sent in the init message
            if (!matchedIframe && subtree && subtree.trackingId) {
                matchedIframe = this.childResponseMap.get(subtree.trackingId);
                if (matchedIframe) {
                    this.log(`Matched iframe by trackingId: ${subtree.trackingId}`);
                }
            }
            
            if (matchedIframe && this.pendingResponses.has(matchedIframe)) {
                this.log(`Recording response from child frame ${subtree?.frameId}`);
                this.childFrames.set(matchedIframe, subtree);
                this.pendingResponses.delete(matchedIframe);
                if (subtree.trackingId) {
                    this.childResponseMap.delete(subtree.trackingId);
                }
                this.log(`Pending responses remaining: ${this.pendingResponses.size}`);
            } else {
                this.log(`Could not match response to any pending iframe`);
            }

            // Check if discovery is complete
            this.checkDiscoveryComplete();
        }

        discoverChildren(callback) {
            if (callback !== undefined) {
                // Callback provided - handle API discovery logic
                if (this.discoveryInProgress) {
                    this.log('API: Discovery in progress, queueing callback');
                    this.discoveryQueue.push(callback);
                    return;
                }
                
                // Start new discovery
                this.log('API: Starting new graph discovery');
                this.discoveryInProgress = true;
                this.discoveryCallback = callback;
            }
            // If no callback, this is called from startDiscovery() - preserve existing state
            
            this.currentRequestId = this.generateFrameId();
            const iframes = document.querySelectorAll('iframe');
            
            this.log(`Starting child discovery. Found ${iframes.length} iframes. RequestId: ${this.currentRequestId}`);
            
            if (iframes.length === 0) {
                this.log('No child iframes found, returning empty children array');
                this.checkDiscoveryComplete();
                return;
            }

            // Reset state
            this.childFrames.clear();
            this.pendingResponses.clear();
            this.childResponseMap.clear();

            // Track which iframes we're waiting for
            iframes.forEach((iframe, index) => {
                // Generate a tracking ID for cross-origin iframe identification
                const trackingId = `${this.frameId}-child-${index}-${Math.floor(performance.now())}`;
                this.pendingResponses.add(iframe);
                this.childResponseMap.set(trackingId, iframe);
                
                const src = iframe.src || 'about:blank';
                this.log(`Sending INIT to iframe[${index}] src=${src}, trackingId=${trackingId}`);
                
                // Send discovery init to each child iframe with tracking ID
                this.sendMessage(iframe.contentWindow, MessageType.INIT, {
                    parentFrameId: this.frameId,
                    trackingId: trackingId
                }, this.currentRequestId);
            });

            // Set timeout for responses
            this.log(`Setting ${CONFIG.DISCOVERY_TIMEOUT}ms timeout for child responses`);
            this.responseTimeout = setTimeout(() => {
                this.handleTimeout();
            }, CONFIG.DISCOVERY_TIMEOUT);
        }

        handleTimeout() {
            this.log(`Discovery timeout reached. ${this.pendingResponses.size} iframes did not respond`);
            
            // Mark any non-responsive iframes with a placeholder
            let timeoutIndex = 0;
            for (const iframe of this.pendingResponses) {
                const timeoutId = `timeout-${this.frameId.substring(0, 8)}-${timeoutIndex++}`;
                this.log(`Marking iframe as timed out: ${timeoutId}`);
                this.childFrames.set(iframe, {
                    frameId: timeoutId,
                    children: [],
                    error: 'timeout'
                });
            }
            
            this.pendingResponses.clear();
            this.childResponseMap.clear();
            this.checkDiscoveryComplete();
        }

        checkDiscoveryComplete() {
            // Check if we're still waiting for any responses
            if (this.pendingResponses.size > 0) {
                this.log(`Still waiting for ${this.pendingResponses.size} responses`);
                return;
            }

            this.log('All children have responded or timed out');

            // Clear timeout if all responded
            if (this.responseTimeout) {
                clearTimeout(this.responseTimeout);
                this.responseTimeout = null;
                this.log('Cleared response timeout');
            }

            // Build our complete subtree
            const subtree = {
                frameId: this.frameId,
                children: Array.from(this.childFrames.values())
            };

            this.log(`Discovery complete. Subtree has ${subtree.children.length} children`);

            // Cache the graph in the main frame
            if (this.isMainFrame) {
                this.currentGraph = subtree;
                this.discoveryInProgress = false;
            }

            // If we have a callback (from parent request), call it
            this.log('checkDiscoveryComplete: checking for discovery callback, callback exists:', !!this.discoveryCallback);
            if (this.discoveryCallback) {
                this.log('Invoking discovery callback');
                this.discoveryCallback(subtree);
                this.discoveryCallback = null;
                this.currentRequestId = null;
            } else {
                this.log('No discovery callback to invoke');
            }

            // If we're the main frame, send to native and process queue
            if (this.isMainFrame) {
                this.log('Main frame discovery complete, sending to native');
                this.sendToNative(subtree);
                
                // Process any queued discovery requests
                this.processDiscoveryQueue(subtree);
            }
        }

        // Process queued discovery callbacks
        processDiscoveryQueue(graph) {
            if (this.discoveryQueue.length === 0) {
                return;
            }
            
            this.log(`Processing ${this.discoveryQueue.length} queued discovery callbacks`);
            
            // Save and clear the queue before processing to handle re-entrant calls
            const queuedCallbacks = [...this.discoveryQueue];
            this.discoveryQueue = [];
            
            // Call all queued callbacks
            for (const callback of queuedCallbacks) {
                try {
                    callback(graph);
                } catch (e) {
                    this.log(`Error in queued discovery callback: ${e.message}`);
                }
            }
        }

        // JavaScript Evaluation Methods
        handleEvaluationRequest(event, payload, requestId) {
            // Child frame receives evaluation request
            const { javascript, targetFrameId } = payload;
            
            // Check if this request is for us or needs to be forwarded
            if (targetFrameId && targetFrameId !== this.frameId) {
                // Need to forward to child frame
                this.forwardEvaluationRequest(targetFrameId, javascript, requestId, event.source);
                return;
            }
            
            // Execute JavaScript in this frame
            this.executeJavaScript(javascript, requestId, event.source);
        }

        forwardEvaluationRequest(targetFrameId, javascript, requestId, originalSource) {
            // Find the iframe that contains the target frame
            const iframes = document.querySelectorAll('iframe');
            for (const iframe of iframes) {
                // Send the request to all children - they'll filter by targetFrameId
                this.sendMessage(iframe.contentWindow, MessageType.EVAL_REQUEST, {
                    javascript: javascript,
                    targetFrameId: targetFrameId,
                    originalSource: originalSource
                }, requestId);
            }
        }

        executeJavaScript(javascript, requestId, responseTarget) {
            this.log(`Executing JavaScript: ${javascript}`);

            let result;
            let error = null;
            
            try {
                result = eval(javascript);
            } catch (e) {
                error = {
                    type: 'EXECUTION_ERROR',
                    message: e.message,
                    frameId: this.frameId
                };
                this.log(`JavaScript execution failed: ${e.message}`);
            }
            
            // Send response back
            this.sendMessage(responseTarget, MessageType.EVAL_RESPONSE, {
                result: result,
                error: error,
                frameId: this.frameId
            }, requestId);
        }

        handleEvaluationResponse(event, payload, requestId) {
            // Main frame receives evaluation response
            if (!this.isMainFrame) {
                // Child frame - forward response to parent
                if (window.parent && window.parent !== window) {
                    this.sendMessage(window.parent, MessageType.EVAL_RESPONSE, payload, requestId);
                }
                return;
            }
            
            // Main frame - collect response
            const { result, error, frameId } = payload;
            
            if (!this.evaluationResponses.has(requestId)) {
                this.log(`Received response for unknown request: ${requestId}`);
                return;
            }
            
            const evalData = this.evaluationResponses.get(requestId);
            evalData.responses[frameId] = error ? null : result;
            evalData.receivedCount++;
            
            this.log(`Evaluation response ${evalData.receivedCount}/${evalData.expectedCount} for request ${requestId}`);
            
            // Check if all responses received
            if (evalData.receivedCount >= evalData.expectedCount) {
                this.completeEvaluation(requestId);
            }
        }

        completeEvaluation(requestId) {
            const evalData = this.evaluationResponses.get(requestId);
            const pendingData = this.pendingEvaluations.get(requestId);
            
            if (!evalData || !pendingData) return;
            
            // Clear timeout
            if (pendingData.timeout) {
                clearTimeout(pendingData.timeout);
            }
            
            // Call callback with results
            if (pendingData.callback) {
                pendingData.callback(evalData.responses);
            }
            
            // Cleanup
            this.evaluationResponses.delete(requestId);
            this.pendingEvaluations.delete(requestId);
            
            this.log(`Evaluation ${requestId} completed with ${Object.keys(evalData.responses).length} results`);
        }

        sendMessage(target, type, payload, requestId) {
            if (!target) {
                this.log('Cannot send message: target is null');
                return;
            }
            
            try {
                const message = {
                    namespace: CONFIG.MESSAGE_NAMESPACE,
                    type: type,
                    payload: payload,
                    requestId: requestId
                };
                this.log(`Sending message: type=${type}, requestId=${requestId}`);
                target.postMessage(message, '*');
            } catch (e) {
                this.log(`Failed to send message: ${e.message}`);
            }
        }

        sendToNative(graph) {
            this.log(`Sending graph to native. Total nodes in graph: ${this.countNodes(graph)}`);
            
            // Send to native app via webkit message handler
            if (window.webkit && window.webkit.messageHandlers && 
                window.webkit.messageHandlers[CONFIG.NATIVE_HANDLER]) {
                
                this.log(`Posting message to webkit handler: ${CONFIG.NATIVE_HANDLER}`);
                window.webkit.messageHandlers[CONFIG.NATIVE_HANDLER].postMessage({
                    type: 'DISCOVERY_COMPLETE',
                    graph: graph
                });
            } else {
                this.log('Webkit message handler not available, using fallback');
                // Fallback: log to console for debugging
                
                // Also expose on window for alternative access (using symbol)
                window[Symbol.for('iTermGraphDiscovery')] = graph;
            }
        }

        countNodes(node) {
            let count = 1;
            if (node.children && Array.isArray(node.children)) {
                for (const child of node.children) {
                    count += this.countNodes(child);
                }
            }
            return count;
        }

        // Setup the public iframe graph API
        setupIframeGraphAPI() {
            const self = this;
            
            window.iTermGraphDiscovery = {
                // Discover the iframe graph
                discover(callback) {
                    if (!callback || typeof callback !== 'function') {
                        throw new Error('discover() requires a callback function');
                    }
                    
                    self.log('API: Graph discovery requested');
                    self.log('API: Debug state - currentGraph:', !!self.currentGraph, 'discoveryInProgress:', self.discoveryInProgress);
                    
                    // If we already have a cached graph, return it immediately
                    if (self.currentGraph) {
                        self.log('API: Returning cached graph');
                        setTimeout(() => {
                            self.log('API: Calling cached graph callback');
                            callback(self.currentGraph);
                        }, 0);
                        return;
                    }
                    
                    // Let discoverChildren handle the queue management and discovery
                    self.discoverChildren(callback);
                },
                
                // Evaluate JavaScript in all frames
                evaluateInAll(javascript, callback, timeout = CONFIG.DISCOVERY_TIMEOUT) {
                    if (!javascript || typeof javascript !== 'string') {
                        throw new Error('evaluateInAll() requires a JavaScript string');
                    }
                    if (!callback || typeof callback !== 'function') {
                        throw new Error('evaluateInAll() requires a callback function');
                    }
                    
                    self.log(`API: Evaluating in all frames: ${javascript}`);
                    self.log(`API: Current graph cached: ${!!self.currentGraph}`);
                    
                    if (!self.currentGraph) {
                        self.log('API: No cached graph, discovering first');
                        // Need to discover graph first
                        window.iTermGraphDiscovery.discover((graph) => {
                            self.log('API: Discovery complete, now evaluating');
                            self._evaluateInAll(javascript, callback, timeout);
                        });
                    } else {
                        self.log('API: Using cached graph for evaluation');
                        self._evaluateInAll(javascript, callback, timeout);
                    }
                },
                
                // Evaluate JavaScript in specific frame
                evaluateInFrame(frameId, javascript, callback, timeout = CONFIG.DISCOVERY_TIMEOUT) {
                    if (!frameId || typeof frameId !== 'string') {
                        throw new Error('evaluateInFrame() requires a frameId string');
                    }
                    if (!javascript || typeof javascript !== 'string') {
                        throw new Error('evaluateInFrame() requires a JavaScript string');
                    }
                    if (!callback || typeof callback !== 'function') {
                        throw new Error('evaluateInFrame() requires a callback function');
                    }
                    
                    self.log(`API: Evaluating in frame ${frameId}: ${javascript}`);
                    self._evaluateInFrame(frameId, javascript, callback, timeout);
                }
            };
            
            this.log('API: window.iTermGraphDiscovery exposed');
        }

        // Helper method to collect all frame IDs from graph
        _collectFrameIds(node) {
            const frameIds = [node.frameId];
            
            if (node.children) {
                for (const child of node.children) {
                    frameIds.push(...this._collectFrameIds(child));
                }
            }
            
            return frameIds;
        }

        // Internal method to evaluate in all frames
        _evaluateInAll(javascript, callback, timeout = CONFIG.DISCOVERY_TIMEOUT) {
            const frameIds = this._collectFrameIds(this.currentGraph);
            const requestId = this.generateFrameId();
            
            this.log(`Evaluating in ${frameIds.length} frames with ${timeout}ms timeout`);
            
            // Setup response collection
            this.evaluationResponses.set(requestId, {
                responses: {},
                expectedCount: frameIds.length,
                receivedCount: 0
            });
            
            // Setup timeout
            const timeoutHandle = setTimeout(() => {
                this.log(`Evaluation ${requestId} timed out after ${timeout}ms`);
                this.completeEvaluation(requestId);
            }, timeout);
            
            this.pendingEvaluations.set(requestId, {
                callback: callback,
                timeout: timeoutHandle,
                frameIds: frameIds
            });
            
            // Send evaluation requests
            for (const frameId of frameIds) {
                if (frameId === this.frameId) {
                    // Execute in main frame directly
                    this.executeJavaScript(javascript, requestId, window);
                } else {
                    // Send to child frames
                    this._sendEvaluationToFrame(frameId, javascript, requestId);
                }
            }
        }

        // Internal method to evaluate in specific frame
        _evaluateInFrame(frameId, javascript, callback, timeout = CONFIG.DISCOVERY_TIMEOUT) {
            const requestId = this.generateFrameId();
            
            this.log(`Evaluating in frame ${frameId} with ${timeout}ms timeout`);
            
            // Setup response collection for single frame
            this.evaluationResponses.set(requestId, {
                responses: {},
                expectedCount: 1,
                receivedCount: 0
            });
            
            // Setup timeout
            const timeoutHandle = setTimeout(() => {
                this.log(`Single frame evaluation ${requestId} timed out after ${timeout}ms`);
                callback(null, { type: 'TIMEOUT', frameId: frameId });
            }, timeout);
            
            this.pendingEvaluations.set(requestId, {
                callback: (results) => {
                    const result = results[frameId];
                    callback(result !== undefined ? result : null);
                },
                timeout: timeoutHandle,
                frameIds: [frameId]
            });
            
            // Execute
            if (frameId === this.frameId) {
                this.executeJavaScript(javascript, requestId, window);
            } else {
                this._sendEvaluationToFrame(frameId, javascript, requestId);
            }
        }

        // Send evaluation request to a specific frame
        _sendEvaluationToFrame(frameId, javascript, requestId) {
            // Broadcast to all child iframes - they'll filter by frameId
            const iframes = document.querySelectorAll('iframe');
            for (const iframe of iframes) {
                this.sendMessage(iframe.contentWindow, MessageType.EVAL_REQUEST, {
                    javascript: javascript,
                    targetFrameId: frameId
                }, requestId);
            }
        }

        startDiscovery() {
            // Only main frame can start discovery
            if (!this.isMainFrame) {
                this.log('ERROR: Discovery can only be started from main frame');
                return;
            }

            this.log('Starting iframe graph discovery from main frame');
            this.lastDiscoveryTime = performance.now();
            
            // Start discovering children - no callback needed, checkDiscoveryComplete handles native sending
            this.discoverChildren();
        }
    }

    // Initialize discovery system in this frame
    window[DISCOVERY_SYMBOL] = new FrameDiscovery();
    
})();
