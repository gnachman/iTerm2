(function() {
    var updatePending = false;
    var observer = null;
    var disabledCount = 0;

    function scheduleMarkUpdate() {
        console.debug("scheduleMarkUpdate called")
        if (updatePending || observer === null) {
            console.debug("scheduleMarkUpdate stopping because pending/not enabled",updatePending, observer);
            return;
        }
        updatePending = true;

        setTimeout(function() {
            console.debug("scheduleMarkUpdate timeout function running");
            updatePending = false;

            try {
                console.debug("Post layoutChange");
                // Turn off DOM mutation observation after posting layoutChange
                disableMonitoring();
                window.webkit.messageHandlers.iTerm2MarkLayoutUpdate.postMessage({
                    type: 'layoutChange'
                });

            } catch (error) {
                console.debug('Error sending layout update:', error.toString(), error);
                enableMonitoring();
            }
        }, 500); // Debounce updates
    }

    function disableMonitoring() {
        disabledCount += 1;
        if (observer) {
            observer.disconnect();
            observer = null;
            console.debug('DOM mutation monitoring disabled');
        }
    }

    function enableMonitoring() {
        disabledCount -= 1;
        if (window.MutationObserver && !observer && disabledCount === 0) {
            setupMutationObserver();
            console.debug('DOM mutation monitoring enabled');
        }
    }

    // Keep track of shadow roots we're observing
    var shadowObservers = new WeakMap();
    var scanIntervalId = null;
    var lastShadowCount = 0;
    
    // Create mutation observer callback with batching
    function createMutationCallback(source) {
        return function(mutations) {
            // Quick exit for tiny mutations
            if (mutations.length > 100) {
                // Too many mutations at once, likely a major page change
                console.debug("Major change detected (", mutations.length, "mutations), scheduling update");
                scheduleMarkUpdate();
                return;
            }
            
            var hasContentChanges = false;
            var shadowRootsToAttach = [];
            
            // Process mutations more efficiently
            for (var i = 0; i < mutations.length; i++) {
                var mutation = mutations[i];
                
                if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                    // Batch check for shadow roots and significant nodes
                    for (var j = 0; j < mutation.addedNodes.length; j++) {
                        var node = mutation.addedNodes[j];
                        
                        if (node.nodeType === Node.ELEMENT_NODE) {
                            // Queue shadow root attachment (don't do it inline)
                            if (node.shadowRoot) {
                                shadowRootsToAttach.push(node.shadowRoot);
                            }
                            
                            // Quick visibility check (skip getBoundingClientRect for performance)
                            if (!hasContentChanges && node.offsetHeight > 10) {
                                hasContentChanges = true;
                            }
                        } else if (!hasContentChanges && node.nodeType === Node.TEXT_NODE) {
                            // Quick text check
                            if (node.textContent && node.textContent.length > 20) {
                                hasContentChanges = true;
                            }
                        }
                        
                        if (hasContentChanges && shadowRootsToAttach.length === 0) {
                            break; // Early exit if we've decided to update
                        }
                    }
                }
                
                if (hasContentChanges) {
                    break; // No need to check more mutations
                }
            }
            
            // Attach to shadow roots after processing mutations
            if (shadowRootsToAttach.length > 0) {
                shadowRootsToAttach.forEach(attachShadowObserver);
            }
            
            if (hasContentChanges) {
                scheduleMarkUpdate();
            }
        };
    }
    
    // Attach observer to a shadow root
    function attachShadowObserver(shadowRoot) {
        if (!shadowObservers.has(shadowRoot)) {
            var shadowObserver = new MutationObserver(createMutationCallback('shadow'));
            shadowObserver.observe(shadowRoot, {
                childList: true,
                subtree: true,
                // Reduce attribute observation for performance
                attributes: false
            });
            shadowObservers.set(shadowRoot, shadowObserver);
        }
    }
    
    // More efficient shadow root discovery
    function findAndObserveShadowRoots() {
        // Target specific elements that commonly have shadow roots
        var shadowHosts = document.querySelectorAll('shreddit-comment, shreddit-post, .Comment, [slot]');
        var newShadowCount = 0;
        
        for (var i = 0; i < shadowHosts.length; i++) {
            if (shadowHosts[i].shadowRoot && !shadowObservers.has(shadowHosts[i].shadowRoot)) {
                attachShadowObserver(shadowHosts[i].shadowRoot);
                newShadowCount++;
            }
        }
        
        if (newShadowCount > 0) {
            console.debug("Attached observers to", newShadowCount, "new shadow roots");
            lastShadowCount += newShadowCount;
        }
        
        // Stop scanning if we've found enough shadow roots and they're stable
        if (lastShadowCount > 10 && newShadowCount === 0) {
            if (scanIntervalId) {
                clearInterval(scanIntervalId);
                scanIntervalId = null;
                console.debug("Shadow root scanning stopped (stable state reached)");
            }
        }
    }
    
    function setupMutationObserver() {
        if (window.MutationObserver) {
            observer = new MutationObserver(createMutationCallback('document'));

            observer.observe(document.body, {
                childList: true,
                subtree: true,
                // Reduce attribute observation for performance
                attributes: false
            });
            
            // Initial shadow root scan
            findAndObserveShadowRoots();
            
            // Scan periodically but stop when stable
            scanIntervalId = setInterval(findAndObserveShadowRoots, 3000);
            
            // Stop scanning after 30 seconds regardless
            setTimeout(function() {
                if (scanIntervalId) {
                    clearInterval(scanIntervalId);
                    scanIntervalId = null;
                    console.debug("Shadow root scanning stopped (timeout)");
                }
            }, 30000);
        }
    }

    // Monitor resize events
    window.addEventListener('resize', scheduleMarkUpdate);

    // Monitor scroll events (for significant scrolling that might indicate content changes)
    window.addEventListener('scroll', scheduleMarkUpdate);

    // Set up initial DOM mutation monitoring
    setupMutationObserver();

    // Expose API to re-enable layout change monitoring
    window.iTermLayoutChangeMonitor = {
        reenableLayoutChangeMonitoring: enableMonitoring,
        disableLayoutChangeMonitoring: disableMonitoring,
    };

    console.debug('Mark layout monitoring initialized');
})();
