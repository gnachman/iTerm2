// iframe Graph Discovery Script for WKWebView
// Injected in all frames, runs in .defaultClient world.

(() => {
    'use strict';

    const DISCOVERY_SYMBOL = Symbol.for('iTermGraphDiscovery');

    if (window[DISCOVERY_SYMBOL]) {
        // Avoid double-install on the same page/frame.
        return;
    }

    const CONFIG = {
        DISCOVERY_TIMEOUT: 2000,
        MESSAGE_NAMESPACE: 'IFRAME_GRAPH_DISCOVERY',
        NATIVE_HANDLER: 'iTermGraphDiscovery'
    };

    const MessageType = {
        CHILD_REPORT: 'CHILD_REPORT'
    };

    class FrameDiscovery {
        constructor() {
            this.log('constructor: entering');
            this.isMainFrame = (window === window.top);
            this.frameId = this.generateRandom();
            this.currentGraph = null;
            this.discoveryQueue = [];
            this.currentRequestId = null;
            this.pendingResponses = 0;

            this.outstandingEvals = new Map(); // requestID -> { callback, timerId }

            this.responseTimeout = null;
            this.mutationObserver = null;

            this.log('constructor: initialized properties, isMainFrame=' + this.isMainFrame);

            this.registerWithNative();
            this.setupMessageListener();
            this.setupMutationObserver();
            this.log('constructor: completed setup');
        }

        // ---------- Public API for pages ----------

        discover(callback) {
            this.log('discover: entering');
            if (typeof callback !== 'function') {
                this.log('discover: invalid callback type');
                throw new Error('discover(callback) requires a function');
            }
            if (this.currentGraph && this.pendingResponses === 0) {
                // Fast path: already have a stable graph.
                this.log('discover: using cached graph');
                setTimeout(() => callback(this.currentGraph), 0);
                return;
            }
            this.log('discover: performing new discovery');
            this.performDiscovery(CONFIG.DISCOVERY_TIMEOUT, callback);
        }

        evaluateInFrame(frameId, javascript, callback, timeout = CONFIG.DISCOVERY_TIMEOUT) {
            this.log('evaluateInFrame: entering, frameId=' + frameId);
            this._evaluateInFrame(frameId, javascript, timeout, callback);
        }

        evaluateInAll(javascript, callback, timeout = CONFIG.DISCOVERY_TIMEOUT) {
            this.log('evaluateInAll: entering');
            if (this.currentGraph && this.pendingResponses === 0) {
                this.log(`evaluateInAll: using existing graph: ${JSON.stringify(this.currentGraph)}`);
                this._evaluateInAll(javascript, callback, timeout);
            } else {
                this.log('evaluateInAll: need to discover first');
                const start = performance.now();
                this.performDiscovery(timeout, (/*graph*/) => {
                    const elapsed = performance.now() - start;
                    const remaining = Math.max(0, timeout - elapsed);
                    this.log('evaluateInAll: discovery complete, proceeding with eval');
                    this._evaluateInAll(javascript, callback, remaining);
                });
            }
        }

        // ---------- Public API for native ----------

        // Called by native across all frames before any report() calls.
        prepareForReport(requestId) {
            this.log('prepareForReport: entering, requestId=' + requestId);
            this.currentRequestId = requestId;
            const iframes = Array.from(document.querySelectorAll('iframe'));
            this.currentGraph = { frameId: this.frameId, children: [] };
            this.pendingResponses = iframes.length;
            this.log(`prepareForReport: prepared, id=${requestId} children=${this.pendingResponses}`);
        }

        // Called by native across all frames after prepareForReport.
        report(requestId) {
            this.log('report: entering, requestId=' + requestId);
            if (requestId !== this.currentRequestId) {
                this.log(`report: unexpected id=${requestId} (current=${this.currentRequestId})`);
                return;
            }
            if (this.pendingResponses > 0) {
                this.log(`report: still waiting on ${this.pendingResponses} child(ren)`);
                return;
            }
            if (this.isMainFrame) {
                this.log('report: main frame, completing discovery');
                this.discoveryDidComplete();
            } else {
                this.log('report: child frame, sending to parent');
                this.sendReportToParent();
            }
        }

        // Called by native to deliver eval result to the requesting frame.
        handleEvalResponse(requestID, value) {
            this.log(`handleEvalResponse: entering, requestID=${requestID} value=${value}`);
            const rec = this.outstandingEvals.get(requestID);
            if (!rec) {
                this.log(`handleEvalResponse: no callback for ${requestID}`);
                return;
            }
            if (rec.timerId) {
                this.log('handleEvalResponse: clearing timeout');
                clearTimeout(rec.timerId);
            }
            this.outstandingEvals.delete(requestID);
            try {
                this.log('handleEvalResponse: invoking callback');
                rec.callback(value);
            } catch (e) {
                this.log(`handleEvalResponse: callback error: ${String(e)}`);
            }
        }

        // Native may call this when DOM changes are observed (from us).
        rediscover(callback = () => {}, timeout = CONFIG.DISCOVERY_TIMEOUT) {
            this.log('rediscover: entering');
            this.performDiscovery(timeout, callback);
        }

        // ---------- Private ----------

        setupMessageListener() {
            this.log('setupMessageListener: entering');
            this.messageListener = (event) => {
                const data = event?.data;
                if (!data || typeof data !== 'object') {
                    return;
                }
                if (data.namespace !== CONFIG.MESSAGE_NAMESPACE) {
                    return;
                }
                this.log('setupMessageListener: received message, type=' + data.type);
                const { type, payload, requestId } = data;
                if (type === MessageType.CHILD_REPORT) {
                    this.log('setupMessageListener: handling child report');
                    this.handleChildReport(payload, requestId);
                    return;
                }
            };
            window.addEventListener('message', this.messageListener);
            this.log('setupMessageListener: listener attached');
        }

        handleChildReport(payload, requestId) {
            this.log(`handleChildReport: entering, requestId=${requestId} payload=${payload}`);
            if (requestId !== this.currentRequestId) {
                this.log(`handleChildReport: ignored old id=${requestId} current=${this.currentRequestId}`);
                return;
            }
            if (this.pendingResponses === 0) {
                this.log('handleChildReport: ignored, more than expected');
                return;
            }
            this.pendingResponses -= 1;
            this.currentGraph.children.push(payload.graph);
            this.log(`handleChildReport: accepted; remaining=${this.pendingResponses}`);
            if (this.pendingResponses === 0) {
                if (this.isMainFrame) {
                    this.log('handleChildReport: all received, main frame completing');
                    this.discoveryDidComplete();
                } else {
                    this.log('handleChildReport: all received, child frame reporting to parent');
                    this.sendReportToParent();
                }
            }
        }

        sendReportToParent() {
            this.log('sendReportToParent: entering');
            if (window.parent && window.parent !== window) {
                this.log('sendReportToParent: has parent, sending message');
                const msg = {
                    namespace: CONFIG.MESSAGE_NAMESPACE,
                    type: MessageType.CHILD_REPORT,
                    requestId: this.currentRequestId,
                    payload: { graph: this.currentGraph }
                };
                window.parent.postMessage(msg, '*');
                this.log('sendReportToParent: message sent');
            } else {
                this.log('sendReportToParent: topmost frame, not sending');
            }
            this.currentRequestId = null;
        }

        registerWithNative() {
            this.log('registerWithNative: entering, frameId=' + this.frameId);
            this.sendToNative({
                type: 'REGISTER_FRAME',
                frameId: this.frameId
            });
            this.log('registerWithNative: registration sent');
        }

        log(message) {
            try {
                console.debug(`[IFD:${this.frameId.slice(0, 8)}] ${message}`);
            } catch (_) {}
        }

        generateRandom() {
            const a = new Uint8Array(16);
            crypto.getRandomValues(a);
            const id = Array.from(a, b => b.toString(16).padStart(2, '0')).join('');
            return id;
        }

        sendToNative(message) {
            this.log(`sendToNative: sending ${message}`);
            try {
                window.webkit.messageHandlers[CONFIG.NATIVE_HANDLER].postMessage(message);
                this.log('sendToNative: success');
            } catch (e) {
                this.log(`sendToNative: failed: ${String(e)}`);
            }
        }

        performDiscovery(timeout, callback) {
            this.log('performDiscovery: entering, timeout=' + timeout);
            this.discoveryQueue.push(callback);
            if (this.discoveryQueue.length > 1) {
                // Already in progress; queued.
                this.log('performDiscovery: already in progress, queued');
                return;
            }
            this.log('performDiscovery: starting new discovery');
            this._performDiscovery(timeout);
        }

        _performDiscovery(timeout) {
            this.log('_performDiscovery: entering, timeout=' + timeout);
            const t = Math.max(0, timeout);
            this.currentRequestId = this.generateRandom();
            const iframes = Array.from(document.querySelectorAll('iframe'));
            this.currentGraph = { frameId: this.frameId, children: [] };
            this.pendingResponses = iframes.length;

            this.log(`_performDiscovery: start id=${this.currentRequestId} children=${this.pendingResponses}`);

            // Ask native to orchestrate prepare/report across all frames with our id.
            this.sendToNative({
                type: 'REQUEST_REPORT',
                requestId: this.currentRequestId
            });

            if (this.responseTimeout) {
                this.log('_performDiscovery: clearing existing timeout');
                clearTimeout(this.responseTimeout);
            }
            this.responseTimeout = setTimeout(() => {
                this.log('_performDiscovery: timeout reached, completing with partial');
                this.discoveryDidComplete();
            }, t);
            this.log('_performDiscovery: timeout set for ' + t + 'ms');
        }

        discoveryDidComplete() {
            this.log('discoveryDidComplete: entering');
            if (this.responseTimeout) {
                this.log('discoveryDidComplete: clearing timeout');
                clearTimeout(this.responseTimeout);
                this.responseTimeout = null;
            }
            const cbs = this.discoveryQueue.splice(0, this.discoveryQueue.length);
            this.currentRequestId = null;
            this.pendingResponses = 0;
            this.log('discoveryDidComplete: invoking ' + cbs.length + ' callbacks');
            for (const cb of cbs) {
                try {
                    this.log('discoveryDidComplete: invoking callback');
                    cb(this.currentGraph);
                } catch (e) {
                    this.log(`discoveryDidComplete: callback error: ${String(e)}`);
                }
            }
            this.log('discoveryDidComplete: completed');
        }

        _evaluateInFrame(frameId, javascript, timeout, callback) {
            this.log(`_evaluateInFrame: entering, frameId=${frameId}, timeout=${timeout}, js=${javascript}`);
            const requestID = this.generateRandom();
            const rec = { callback, timerId: null };
            this.outstandingEvals.set(requestID, rec);

            // Dispatch to native.
            this.log('_evaluateInFrame: sending to native, requestID=' + requestID);
            this.sendToNative({
                type: 'EVAL_IN_FRAME',
                requestID,
                target: frameId,
                sender: this.frameId,
                code: String(javascript)
            });

            rec.timerId = setTimeout(() => {
                this.log(`_evaluateInFrame: timeout for ${requestID}`);
                this.handleEvalResponse(requestID, null);
            }, Math.max(0, timeout));
            this.log('_evaluateInFrame: timeout set');
        }

        _evaluateInAll(javascript, callback, timeout) {
            this.log(`_evaluateInAll: entering, timeout=${timeout} js=${javascript}`);
            const graph = this.currentGraph;
            if (!graph) {
                this.log('_evaluateInAll: no graph, returning null');
                setTimeout(() => callback(null), 0);
                return;
            }
            const requestID = this.generateRandom();
            const rec = { callback, timerId: null };
            this.outstandingEvals.set(requestID, rec);
            const results = {};
            let seen = 0;
            const t = Math.max(0, timeout);
            this.log('_evaluateInAll: evaluating in self and children');
            const total = this.evaluateInSelfAndChildren(graph, String(javascript), t, (frameID, value) => {
                this.log('_evaluateInAll: received result from ' + frameID);
                results[frameID] = value;
                seen += 1;
                if (seen === total) {
                    this.log('_evaluateInAll: all results received');
                    this.handleEvalResponse(requestID, results);
                }
            });
            this.log('_evaluateInAll: expecting ' + total + ' results');
            rec.timerId = setTimeout(() => {
                this.log('_evaluateInAll: timeout, returning partial results');
                this.handleEvalResponse(requestID, results);
            }, t);
        }

        evaluateInSelfAndChildren(graph, javascript, timeout, callback) {
            this.log('evaluateInSelfAndChildren: entering, frameId=' + graph.frameId);
            // Evaluate in self
            let count = 1;
            this.log('evaluateInSelfAndChildren: evaluating in self');
            this._evaluateInFrame(graph.frameId, javascript, timeout, (value) => {
                callback(graph.frameId, value);
            });

            // And then in my children, if any.
            const children = Array.isArray(graph.children) ? graph.children : [];
            this.log('evaluateInSelfAndChildren: processing ' + children.length + ' children');
            for (const child of children) {
                this.log('evaluateInSelfAndChildren: recursing into child');
                count += this.evaluateInSelfAndChildren(child, javascript, timeout, callback);
            }
            this.log('evaluateInSelfAndChildren: returning count=' + count);
            return count;
        }

        setupMutationObserver() {
            this.log('setupMutationObserver: entering');
            const startObserver = () => {
                this.log('setupMutationObserver.startObserver: entering');
                if (this.mutationObserver) { 
                    this.log('setupMutationObserver.startObserver: already exists');
                    return; 
                }

                let pendingDomChanged = false;
                const notifyDomChanged = () => {
                    if (pendingDomChanged) { 
                        this.log('setupMutationObserver.notifyDomChanged: already pending');
                        return; 
                    }
                    this.log('setupMutationObserver.notifyDomChanged: scheduling DOM change notification');
                    pendingDomChanged = true;
                    setTimeout(() => {
                        pendingDomChanged = false;
                        this.log('setupMutationObserver.notifyDomChanged: triggering handleDOMChange');
                        this.handleDOMChange();
                    }, 100);
                };

                this.mutationObserver = new MutationObserver((mutations) => {
                    this.log('mutationObserver: mutations detected, count=' + mutations.length);
                    for (const m of mutations) {
                        if (m.type === 'childList') {
                            this.log('mutationObserver: childList mutation');
                            for (const n of m.addedNodes) {
                                if (n.nodeType === 1 && (n.nodeName === 'IFRAME' || (n.querySelectorAll && n.querySelectorAll('iframe').length > 0))) {
                                    this.log('mutationObserver: iframe added');
                                    notifyDomChanged();
                                    return;
                                }
                            }
                            for (const n of m.removedNodes) {
                                if (n.nodeType === 1 && (n.nodeName === 'IFRAME' || (n.querySelectorAll && n.querySelectorAll('iframe').length > 0))) {
                                    this.log('mutationObserver: iframe removed');
                                    notifyDomChanged();
                                    return;
                                }
                            }
                        } else if (m.type === 'attributes' && m.target && m.target.nodeName === 'IFRAME' && (m.attributeName === 'src' || m.attributeName === 'sandbox')) {
                            this.log('mutationObserver: iframe attribute changed: ' + m.attributeName);
                            notifyDomChanged();
                            return;
                        }
                    }
                });

                const target = document.body || document.documentElement;
                if (target) {
                    this.log('setupMutationObserver.startObserver: observing target');
                    this.mutationObserver.observe(target, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'srcdoc', 'sandbox'] });
                } else {
                    this.log('setupMutationObserver.startObserver: no target found');
                }
            };
            if (document.readyState === 'loading') {
                this.log('setupMutationObserver: waiting for DOMContentLoaded');
                document.addEventListener('DOMContentLoaded', startObserver, { once: true });
            } else {
                this.log('setupMutationObserver: starting observer immediately');
                startObserver();
            }
        }

        handleDOMChange() {
            this.log('handleDOMChange: entering');
            this.sendToNative({ type: 'DOM_CHANGED' });
            this.log('handleDOMChange: notification sent');
        }
    }

    console.debug('[IFD:init] Creating FrameDiscovery instance');
    window[DISCOVERY_SYMBOL] = new FrameDiscovery();
    console.debug('[IFD:init] FrameDiscovery initialized');
})();
